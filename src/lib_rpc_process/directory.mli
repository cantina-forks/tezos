(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2023 Nomadic Labs. <contact@nomadic-labs.com>               *)
(*                                                                           *)
(*****************************************************************************)

(** [build_rpc_directory node_version config dynamic_store
    ~head_watcher] builds the Tezos RPC directory for the rpc
    process. RPCs handled here are not forwarded to the node.

    [head_watcher] is the wrapped monitor_head stream on which the
    clients will listen to.
*)
val build_rpc_directory :
  Tezos_version.Octez_node_version.t ->
  Octez_node_config.Config_file.t ->
  Store.t option ref ->
  head_watcher:(Block_hash.t * Block_header.t) Lwt_watcher.input ->
  unit Tezos_rpc.Directory.t
