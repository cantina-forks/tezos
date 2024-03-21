(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type t = Blueprint_types.payload

(** [create ~secret_key ~timestamp ~smart_rollup_address ~number
    ~parent_hash ~delayed_transactions ~transactions]
    creates a sequencer blueprint at [timestamp] with a given [number]
    containing [transactions], signed with [secret_key].  Returns
    valid list of external messages inputs to put in the inbox.
*)
val create :
  cctxt:#Client_context.wallet ->
  sequencer_key:Client_keys.sk_uri ->
  timestamp:Time.Protocol.t ->
  smart_rollup_address:string ->
  number:Ethereum_types.quantity ->
  parent_hash:Ethereum_types.block_hash ->
  delayed_transactions:Ethereum_types.hash list ->
  transactions:string list ->
  t tzresult Lwt.t
