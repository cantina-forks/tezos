(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

open Protocol
open Alpha_context

type header = {
  block_hash : Tezos_crypto.Block_hash.t;
  level : Raw_level.t;
  predecessor : Tezos_crypto.Block_hash.t;
  commitment_hash : Sc_rollup.Commitment.Hash.t option;
  previous_commitment_hash : Sc_rollup.Commitment.Hash.t;
  context : Context.hash;
  inbox_witness : Sc_rollup.Inbox_merkelized_payload_hashes.Hash.t;
  inbox_hash : Sc_rollup.Inbox.Hash.t;
}

type content = {
  inbox : Sc_rollup.Inbox.t;
  messages : Sc_rollup.Inbox_message.t list;
  commitment : Sc_rollup.Commitment.t option;
}

type ('header, 'content) block = {
  header : 'header;
  content : 'content;
  initial_tick : Sc_rollup.Tick.t;
  num_ticks : int64;
}

type t = (header, unit) block

let commitment_hash_opt_encoding =
  let open Data_encoding in
  let binary =
    conv
      (Option.value ~default:Sc_rollup.Commitment.Hash.zero)
      (fun h -> if Sc_rollup.Commitment.Hash.(h = zero) then None else Some h)
      Sc_rollup.Commitment.Hash.encoding
  in
  let json = option Sc_rollup.Commitment.Hash.encoding in
  splitted ~binary ~json

let header_encoding =
  let open Data_encoding in
  conv
    (fun {
           block_hash;
           level;
           predecessor;
           commitment_hash;
           previous_commitment_hash;
           context;
           inbox_witness;
           inbox_hash;
         } ->
      ( block_hash,
        level,
        predecessor,
        commitment_hash,
        previous_commitment_hash,
        context,
        inbox_witness,
        inbox_hash ))
    (fun ( block_hash,
           level,
           predecessor,
           commitment_hash,
           previous_commitment_hash,
           context,
           inbox_witness,
           inbox_hash ) ->
      {
        block_hash;
        level;
        predecessor;
        commitment_hash;
        previous_commitment_hash;
        context;
        inbox_witness;
        inbox_hash;
      })
  @@ obj8
       (req
          "block_hash"
          Tezos_crypto.Block_hash.encoding
          ~description:"Tezos block hash.")
       (req
          "level"
          Raw_level.encoding
          ~description:
            "Level of the block, corresponds to the level of the tezos block.")
       (req
          "predecessor"
          Tezos_crypto.Block_hash.encoding
          ~description:"Predecessor hash of the Tezos block.")
       (req
          "commitment_hash"
          commitment_hash_opt_encoding
          ~description:
            "Hash of this block's commitment if any was computed for it.")
       (req
          "previous_commitment_hash"
          Sc_rollup.Commitment.Hash.encoding
          ~description:
            "Previous commitment hash in the chain. If there is a commitment \
             for this block, this field contains the commitment that was \
             previously computed.")
       (req
          "context"
          Context.hash_encoding
          ~description:"Hash of the layer 2 context for this block.")
       (req
          "inbox_witness"
          Sc_rollup.Inbox_merkelized_payload_hashes.Hash.encoding
          ~description:
            "Witness for the inbox for this block, i.e. the Merkle hash of \
             payloads of messages.")
       (req
          "inbox_hash"
          Sc_rollup.Inbox.Hash.encoding
          ~description:"Hash of the inbox for this block.")

let header_size =
  WithExceptions.Option.get ~loc:__LOC__
  @@ Data_encoding.Binary.fixed_length header_encoding

let content_encoding =
  let open Data_encoding in
  conv
    (fun {inbox; messages; commitment} -> (inbox, messages, commitment))
    (fun (inbox, messages, commitment) -> {inbox; messages; commitment})
  @@ obj3
       (req
          "inbox"
          Sc_rollup.Inbox.encoding
          ~description:"Inbox for this block.")
       (req
          "messages"
          (list (dynamic_size Sc_rollup.Inbox_message.encoding))
          ~description:"Messages added to the inbox in this block.")
       (opt
          "commitment"
          Sc_rollup.Commitment.encoding
          ~description:"Commitment, if any is computed for this block.")

let block_encoding header_encoding content_encoding =
  let open Data_encoding in
  conv
    (fun {header; content; initial_tick; num_ticks} ->
      (header, (content, (initial_tick, num_ticks))))
    (fun (header, (content, (initial_tick, num_ticks))) ->
      {header; content; initial_tick; num_ticks})
  @@ merge_objs header_encoding
  @@ merge_objs content_encoding
  @@ obj2
       (req
          "initial_tick"
          Sc_rollup.Tick.encoding
          ~description:
            "Initial tick of the PVM at this block, i.e. before evaluation of \
             the messages.")
       (req
          "num_ticks"
          int64
          ~description:
            "Number of ticks produced by the evaluation of the messages in \
             this block.")

let encoding = block_encoding header_encoding Data_encoding.unit

let most_recent_commitment (header : header) =
  Option.value header.commitment_hash ~default:header.previous_commitment_hash

let final_tick {initial_tick; num_ticks; _} =
  Sc_rollup.Tick.jump initial_tick (Z.of_int64 num_ticks)
