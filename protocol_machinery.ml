(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs, <contact@nomadic-labs.com>               *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

open Lwt_result_syntax

module type PROTOCOL_SERVICES = sig
  val hash : Protocol_hash.t

  type wrap_full

  val wrap_full : Tezos_client_base.Client_context.full -> wrap_full

  type endorsing_rights

  val endorsing_rights :
    wrap_full -> Block_hash.t -> endorsing_rights tzresult Lwt.t

  val couple_ops_to_rights :
    (error trace option * Ptime.t * int) list ->
    endorsing_rights ->
    (Signature.public_key_hash
    * (Int32.t option * error trace option * Ptime.t) list)
    list
    * Signature.public_key_hash list

  val consensus_operation_stream :
    wrap_full ->
    (((Operation_hash.t * ((Block_hash.t * int32 * int32 option) * int))
     * error trace option)
     Lwt_stream.t
    * RPC_context.stopper)
    tzresult
    Lwt.t

  val baking_right :
    wrap_full ->
    Block_hash.t ->
    int ->
    (Signature.public_key_hash * Time.Protocol.t option) tzresult Lwt.t

  val block_round : Block_header.t -> (int, tztrace) result

  val consensus_op_participants_of_block :
    wrap_full -> Block_hash.t -> Signature.public_key_hash list tzresult Lwt.t
end

module type S = sig
  val register_commands : unit -> unit
end

module Make (Protocol_services : PROTOCOL_SERVICES) : S = struct
  let print_failures f =
    let*! o = f in
    match o with
    | Ok () -> Lwt.return_unit
    | Error e ->
        let () = Error_monad.pp_print_trace Format.err_formatter e in
        Lwt.return_unit

  let dump_my_current_endorsements cctxt ~full block level ops =
    let* rights = Protocol_services.endorsing_rights cctxt block in
    let (items, missing) = Protocol_services.couple_ops_to_rights ops rights in
    let endorsements =
      if full then
        List.fold_left (fun acc delegate -> (delegate, []) :: acc) items missing
      else items
    in
    let unaccurate = if full then Some false else None in
    let () = Archiver.add_received ?unaccurate level endorsements in
    return_unit

  let endorsements_recorder cctxt current_level =
    let* (op_stream, _stopper) =
      Protocol_services.consensus_operation_stream cctxt
    in
    let*! out =
      Lwt_stream.fold
        (fun ((_hash, ((block, level, _round), news)), errors) acc ->
          let delay = Time.System.now () in
          Block_hash.Map.update
            block
            (function
              | Some (_, l) -> Some (level, (errors, delay, news) :: l)
              | None -> Some (level, [(errors, delay, news)]))
            acc)
        op_stream
        Block_hash.Map.empty
    in
    Block_hash.Map.iter_ep
      (fun block (level, endorsements) ->
        let full = Compare.Int32.(current_level = level) in
        dump_my_current_endorsements cctxt ~full block level endorsements)
      out

  let blocks_loop cctxt =
    let*! block_stream =
      Shell_services.Monitor.valid_blocks cctxt ~chains:[cctxt#chain] ()
    in
    match block_stream with
    | Error e ->
        let () = Error_monad.pp_print_trace Format.err_formatter e in
        Lwt.return_unit
    | Ok (block_stream, _stopper) ->
        let cctxt' = Protocol_services.wrap_full cctxt in
        Lwt_stream.iter_p
          (fun ((_chain_id, hash), header) ->
            let reception_time = Time.System.now () in
            let block_level = header.Block_header.shell.Block_header.level in
            let priority = Protocol_services.block_round header in
            match priority with
            | Error e ->
                Lwt.return (Error_monad.pp_print_trace Format.err_formatter e)
            | Ok priority -> (
                let*! pks =
                  Protocol_services.consensus_op_participants_of_block
                    cctxt'
                    hash
                in
                match pks with
                | Error e ->
                    Lwt.return
                      (Error_monad.pp_print_trace Format.err_formatter e)
                | Ok pks -> (
                    let*! baking_rights =
                      Protocol_services.baking_right cctxt' hash priority
                    in
                    match baking_rights with
                    | Error e ->
                        Error_monad.pp_print_trace Format.err_formatter e ;
                        Lwt.return_unit
                    | Ok (delegate, _) ->
                        let timestamp =
                          header.Block_header.shell.Block_header.timestamp
                        in
                        Archiver.add_block
                          ~level:block_level
                          hash
                          ~round:(Int32.of_int priority)
                          timestamp
                          reception_time
                          delegate
                          pks ;
                        Lwt.return_unit)))
          block_stream

  let endorsements_loop cctxt =
    let*! head_stream = Shell_services.Monitor.heads cctxt cctxt#chain in
    match head_stream with
    | Error e ->
        let () = Error_monad.pp_print_trace Format.err_formatter e in
        Lwt.return_unit
    | Ok (head_stream, _stopper) ->
        let cctxt = Protocol_services.wrap_full cctxt in
        Lwt_stream.iter_p
          (fun (_hash, header) ->
            let block_level = header.Block_header.shell.Block_header.level in
            print_failures (endorsements_recorder cctxt block_level))
          head_stream

  let main cctxt prefix =
    let dumper = Archiver.launch cctxt prefix in
    let main =
      let*! () = Lwt.Infix.(blocks_loop cctxt <&> endorsements_loop cctxt) in
      let () = Archiver.stop () in
      Lwt.return_unit
    in
    let*! out = Lwt.join [dumper; main] in
    return out

  let group =
    {Clic.name = "teztale"; Clic.title = "A delegate operation monitor"}

  let directory_parameter =
    Clic.parameter (fun _ p ->
        if not (Sys.file_exists p && Sys.is_directory p) then
          failwith "Directory doesn't exist: '%s'" p
        else return p)

  let register_commands () =
    Tezos_client_commands.Client_commands.register
      Protocol_services.hash
      (fun _ ->
        [
          Clic.command
            ~group
            ~desc:"Go"
            Clic.no_options
            (Clic.prefixes ["run"; "in"]
            @@ Clic.param
                 ~name:"archive_path"
                 ~desc:"folder in which to dump files"
                 directory_parameter
            @@ Clic.stop)
            (fun () prefix cctxt -> main cctxt prefix);
        ])
end
