(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2018.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

open Client_context

type command = full_context Cli_entries.command

exception Version_not_found

val register: Protocol_hash.t -> command list -> unit
val commands_for_version: Protocol_hash.t -> command list
val get_versions: unit -> (Protocol_hash.t * (command list)) list

(** Have a command execute ignoring warnings.
    Default doc is ["Silence any warnings and some checks."]. *)
val force_switch : ?doc:string -> unit -> (bool, #full_context) Cli_entries.arg
