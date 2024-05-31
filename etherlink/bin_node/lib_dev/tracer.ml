(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2024 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let read_value ?default state path =
  let open Lwt_result_syntax in
  let*! value = Evm_state.inspect state path in
  match value with
  | Some value -> return value
  | None -> (
      match default with
      | Some d -> return d
      | None -> tzfail Tracer_types.Trace_not_found)

let read_logs_length state =
  let open Lwt_result_syntax in
  let* value =
    read_value
      ~default:(Bytes.of_string "\000")
      state
      Durable_storage_path.Trace_transaction.logs_length
  in
  return (Bytes.to_string value |> Z.of_bits |> Z.to_int)

let read_opcode state opcode_index =
  read_value state (Durable_storage_path.Trace_transaction.opcode opcode_index)

let read_logs state =
  let open Lwt_result_syntax in
  let* length = read_logs_length state in
  let*? opcodes =
    List.init
      ~when_negative_length:(TzTrace.make (error_of_fmt "Invalid length"))
      length
      Fun.id
  in
  List.map_es (read_opcode state) opcodes

let read_output state =
  let open Lwt_result_syntax in
  let* gas =
    read_value state Durable_storage_path.Trace_transaction.output_gas
  in
  let* failed =
    read_value state Durable_storage_path.Trace_transaction.output_failed
  in
  let* return_value =
    read_value
    (* The key doesn't exist if there is no value returned by the transaction *)
      ~default:Bytes.empty
      state
      Durable_storage_path.Trace_transaction.output_return_value
  in
  let* struct_logs = read_logs state in
  Lwt.return
  @@ Tracer_types.output_binary_decoder ~gas ~failed ~return_value ~struct_logs

let trace_transaction ~block_number ~transaction_hash ~config =
  let open Lwt_result_syntax in
  let input = Tracer_types.input_rlp_encoder transaction_hash config in
  let set_input state =
    let*! state =
      Evm_state.modify
        ~key:Durable_storage_path.Trace_transaction.input
        ~value:input
        state
    in
    return state
  in
  let* apply_result =
    Evm_context.replay
      ~log_file:"trace_transaction"
      ~alter_evm_state:set_input
      block_number
  in
  match apply_result with
  | Apply_failure -> tzfail Tracer_types.Trace_not_found
  | Apply_success {evm_state; _} -> read_output evm_state
