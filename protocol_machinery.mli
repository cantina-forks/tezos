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

module type PROTOCOL_SERVICES = sig
  val hash : Protocol_hash.t

  type wrap_full

  val wrap_full : Tezos_client_base.Client_context.full -> wrap_full

  type endorsing_rights

  val endorsing_rights : wrap_full -> Int32.t -> endorsing_rights tzresult Lwt.t

  val couple_ops_to_rights :
    (error trace option * Ptime.t * Int32.t option * int) list ->
    endorsing_rights ->
    (Signature.public_key_hash
    * (Int32.t option * error trace option * Ptime.t) list)
    list
    * Signature.public_key_hash list

  type block_id

  module BlockIdMap : Map.S with type key = block_id

  val consensus_operation_stream :
    wrap_full ->
    (((Operation_hash.t * ((block_id * Int32.t * Int32.t option) * int))
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

  val block_round : Block_header.t -> int tzresult

  val consensus_op_participants_of_block :
    wrap_full -> Block_hash.t -> Signature.public_key_hash list tzresult Lwt.t
end

module type S = sig
  val register_commands : unit -> unit
end

module Make (Protocol_services : PROTOCOL_SERVICES) : S
