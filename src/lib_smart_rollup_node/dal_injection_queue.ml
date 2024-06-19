(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* SPDX-FileCopyrightText: 2024 Functori     <contact@functori.com>          *)
(* SPDX-FileCopyrightText: 2024 Nomadic Labs <contact@nomadic-labs.com>      *)
(*                                                                           *)
(*****************************************************************************)
module Name = struct
  (* We only have a single batcher in the node *)
  type t = unit

  let encoding = Data_encoding.unit

  let base = ["dal-injection"; "worker"]

  let pp _ _ = ()

  let equal () () = true
end

module Dal_worker_types = struct
  module Request = struct
    type ('a, 'b) t =
      | Register : {
          slot_content : string;
          slot_index : int;
        }
          -> (unit, error trace) t

    type view = View : _ t -> view

    let view req = View req

    let encoding : view Data_encoding.t =
      let open Data_encoding in
      conv
        (function
          | View (Register {slot_content; slot_index}) ->
              ((), slot_content, slot_index))
        (fun ((), slot_content, slot_index) ->
          View (Register {slot_content; slot_index}))
        (obj3
           (req "request" (constant "register"))
           (req "slot_content" string)
           (req "slot_index" int31))

    let pp ppf (View r) =
      match r with
      | Register {slot_content = _; slot_index} ->
          Format.fprintf
            ppf
            "register slot injection request for index %d"
            slot_index
  end
end

open Dal_worker_types

module Events = struct
  include Internal_event.Simple

  let section = "smart_rollup_node" :: Name.base

  let injected =
    declare_3
      ~section
      ~name:"injected"
      ~msg:
        "Injected a DAL slot {slot_commitment} at index {slot_index} with hash \
         {operation_hash}"
      ~level:Info
      ~pp1:Tezos_crypto_dal.Cryptobox.Commitment.pp
      ~pp3:Injector.Inj_operation.Id.pp
      ("slot_commitment", Tezos_crypto_dal.Cryptobox.Commitment.encoding)
      ("slot_index", Data_encoding.uint8)
      ("operation_hash", Injector.Inj_operation.Id.encoding)

  let request_failed =
    declare_3
      ~section
      ~name:"request_failed"
      ~msg:"Request {request} failed ({worker_status}): {errors}"
      ~level:Warning
      ("request", Request.encoding)
      ~pp1:Request.pp
      ("worker_status", Worker_types.request_status_encoding)
      ~pp2:Worker_types.pp_status
      ("errors", Error_monad.trace_encoding)
      ~pp3:Error_monad.pp_print_trace

  let request_completed =
    declare_2
      ~section
      ~name:"request_completed"
      ~msg:"{request} {worker_status}"
      ~level:Debug
      ("request", Request.encoding)
      ("worker_status", Worker_types.request_status_encoding)
      ~pp1:Request.pp
      ~pp2:Worker_types.pp_status
end

type state = {node_ctxt : Node_context.ro}

let inject_slot state ~slot_content ~slot_index =
  let open Lwt_result_syntax in
  let {Node_context.dal_cctxt; _} = state.node_ctxt in
  let* commitment, operation =
    match dal_cctxt with
    | Some dal_cctxt ->
        let* commitment, commitment_proof =
          Dal_node_client.post_slot dal_cctxt slot_content
        in
        return
          ( commitment,
            L1_operation.Publish_dal_commitment
              {slot_index; commitment; commitment_proof} )
    | None ->
        (* This should not be reachable, as we tested that some [dal_cctxt] is set
           at startup before launching the worker. *)
        assert false
  in
  let* l1_hash =
    Injector.check_and_add_pending_operation
      state.node_ctxt.config.mode
      operation
  in
  let* l1_hash =
    match l1_hash with
    | Some l1_hash -> return l1_hash
    | None ->
        let op = Injector.Inj_operation.make operation in
        return op.id
  in
  let*! () = Events.(emit injected) (commitment, slot_index, l1_hash) in
  return_unit

let on_register state ~slot_content ~slot_index : unit tzresult Lwt.t =
  let open Lwt_result_syntax in
  let number_of_slots =
    (Reference.get state.node_ctxt.current_protocol).constants.dal
      .number_of_slots
  in
  let* () =
    fail_unless (slot_index >= 0 && slot_index < number_of_slots)
    @@ error_of_fmt "Slot index %d out of range" slot_index
  in
  inject_slot state ~slot_content ~slot_index

let init_dal_worker_state node_ctxt = {node_ctxt}

module Types = struct
  type nonrec state = state

  type parameters = {node_ctxt : Node_context.ro}
end

module Worker = Worker.MakeSingle (Name) (Request) (Types)

type worker = Worker.infinite Worker.queue Worker.t

module Handlers = struct
  type self = worker

  let on_request :
      type r request_error.
      worker -> (r, request_error) Request.t -> (r, request_error) result Lwt.t
      =
   fun w request ->
    let state = Worker.state w in
    match request with
    | Request.Register {slot_content; slot_index} ->
        protect @@ fun () -> on_register state ~slot_content ~slot_index

  type launch_error = error trace

  let on_launch _w () Types.{node_ctxt} =
    let open Lwt_result_syntax in
    let state = init_dal_worker_state node_ctxt in
    return state

  let on_error (type a b) _w st (r : (a, b) Request.t) (errs : b) :
      unit tzresult Lwt.t =
    let open Lwt_result_syntax in
    match r with
    | Request.Register _ ->
        let*! () = Events.(emit request_failed) (Request.view r, st, errs) in
        return_unit

  let on_completion _w r _ st =
    match Request.view r with
    | Request.View (Register _) ->
        Events.(emit request_completed) (Request.view r, st)

  let on_no_request _ = Lwt.return_unit

  let on_close _w = Lwt.return_unit
end

let table = Worker.create_table Queue

let (worker_promise : Worker.infinite Worker.queue Worker.t Lwt.t), worker_waker
    =
  Lwt.task ()

let start node_ctxt =
  let open Lwt_result_syntax in
  let node_ctxt = Node_context.readonly node_ctxt in
  let+ worker = Worker.launch table () {node_ctxt} (module Handlers) in
  Lwt.wakeup worker_waker worker

let start_in_mode mode =
  let open Configuration in
  match mode with
  | Batcher | Operator -> true
  | Observer | Accuser | Bailout | Maintenance -> false
  | Custom ops -> purpose_matches_mode (Custom ops) Batching

let init (node_ctxt : _ Node_context.t) =
  let open Lwt_result_syntax in
  match Lwt.state worker_promise with
  | Lwt.Return _ ->
      (* Worker already started, nothing to do. *)
      return_unit
  | Lwt.Fail exn ->
      (* Worker crashed, not recoverable. *)
      fail [Rollup_node_errors.No_dal_injector; Exn exn]
  | Lwt.Sleep ->
      (* Never started, start it. *)
      if
        Option.is_some node_ctxt.Node_context.dal_cctxt
        && start_in_mode node_ctxt.config.mode
      then start node_ctxt
      else return_unit

(* This is a DAL inection worker for a single scoru *)
let worker =
  lazy
    (match Lwt.state worker_promise with
    | Lwt.Return worker -> Ok worker
    | Lwt.Fail exn -> Error (Error_monad.error_of_exn exn)
    | Lwt.Sleep -> Error Rollup_node_errors.No_dal_injector)

let handle_request_error rq =
  let open Lwt_syntax in
  let* rq in
  match rq with
  | Ok res -> return_ok res
  | Error (Worker.Request_error errs) -> Lwt.return_error errs
  | Error (Closed None) -> Lwt.return_error [Worker_types.Terminated]
  | Error (Closed (Some errs)) -> Lwt.return_error errs
  | Error (Any exn) -> Lwt.return_error [Exn exn]

let register_dal_slot ~slot_content ~slot_index =
  let open Lwt_result_syntax in
  let* w = lwt_map_error TzTrace.make (Lwt.return (Lazy.force worker)) in
  Worker.Queue.push_request_and_wait
    w
    (Request.Register {slot_content; slot_index})
  |> handle_request_error
