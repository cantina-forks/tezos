(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2023 Marigold <contact@marigold.dev>                        *)
(* Copyright (c) 2023 Functori <contact@functori.com>                        *)
(* Copyright (c) 2023 Trilitech <contact@trili.tech>                         *)
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

open Rollup_services
open Transaction_format

module MakeBackend (Base : sig
  val base : Uri.t

  val keep_alive : bool

  val drop_duplicate_on_injection : bool

  val smart_rollup_address : string
end) : Services_backend_sig.Backend = struct
  module Reader = struct
    let read ?block path =
      match block with
      | Some param
        when param <> Ethereum_types.Block_parameter.(Block_parameter Latest) ->
          failwith
            "The EVM node in proxy mode support state requests only on latest \
             block."
      | _ ->
          call_service
            ~keep_alive:Base.keep_alive
            ~base:Base.base
            durable_state_value
            ((), Block_id.Head)
            {key = path}
            ()
  end

  module TxEncoder = struct
    type transactions = string list

    type messages = string list

    let encode_transactions ~smart_rollup_address ~transactions =
      let open Result_syntax in
      let* rev_hashes, messages =
        List.fold_left_e
          (fun (tx_hashes, to_publish) tx_raw ->
            let* tx_hash, messages =
              make_encoded_messages ~smart_rollup_address tx_raw
            in
            return (tx_hash :: tx_hashes, to_publish @ messages))
          ([], [])
          transactions
      in
      return (List.rev rev_hashes, messages)
  end

  module Publisher = struct
    type messages = TxEncoder.messages

    let publish_messages ~timestamp:_ ~smart_rollup_address:_ ~messages =
      let open Lwt_result_syntax in
      (* The injection's service returns a notion of L2 message ids (defined
         by the rollup node) used to track the message's injection in the batcher.
         We do not wish to follow the message's inclusion, and thus, ignore
         the resulted ids. *)
      let* _answer =
        call_service
          ~keep_alive:Base.keep_alive
          ~base:Base.base
          batcher_injection
          ()
          (* to be retro-compatible with rollup node version that does
             not have yet the query in the injection rpc, don't add
             the flag if the `drop_duplicate_on_injection` is false.*)
          (if Base.drop_duplicate_on_injection then Some true else None)
          messages
      in
      return_unit
  end

  module SimulatorBackend = struct
    let simulate_and_read ?block ~input () =
      let open Lwt_result_syntax in
      match block with
      | Some param
        when param <> Ethereum_types.Block_parameter.(Block_parameter Latest) ->
          failwith
            "The EVM node in proxy mode support state requests only on latest \
             block."
      | _ -> (
          let* json =
            call_service
              ~keep_alive:Base.keep_alive
              ~base:Base.base
              simulation
              ()
              ()
              input
          in
          let eval_result =
            Data_encoding.Json.destruct Simulation.Encodings.eval_result json
          in
          match eval_result.insights with
          | [data] -> return data
          | _ -> failwith "Inconsistent simulation results")
  end

  let block_param_to_block_number
      (block_param : Ethereum_types.Block_parameter.extended) =
    let open Lwt_result_syntax in
    match block_param with
    | Block_parameter (Number n) -> return n
    | Block_parameter (Earliest | Latest) -> (
        let* value =
          Reader.read
            ~block:(Block_parameter Latest)
            Durable_storage_path.Block.current_number
        in
        match value with
        | Some value ->
            return (Ethereum_types.Qty (Bytes.to_string value |> Z.of_bits))
        | None -> failwith "Cannot read current number")
    | Block_parameter Pending ->
        failwith "Pending block parameter is not supported"
    | Block_hash {hash; _} -> (
        let* value =
          Reader.read
            ~block:(Block_parameter Latest)
            (Durable_storage_path.Block.by_hash hash)
        in
        match value with
        | Some value ->
            let block = Ethereum_types.block_from_rlp value in
            return block.number
        | None ->
            failwith
              "Missing state for block %a"
              Ethereum_types.pp_block_hash
              hash)

  module Tracer = struct
    let trace_transaction ~block_number:_ ~transaction_hash:_ ~config:_ =
      Lwt_result_syntax.tzfail Tracer_types.Not_supported
  end

  let smart_rollup_address = Base.smart_rollup_address
end

module Make (Base : sig
  val base : Uri.t

  val keep_alive : bool

  val drop_duplicate_on_injection : bool

  val smart_rollup_address : string
end) =
  Services_backend_sig.Make (MakeBackend (Base))
