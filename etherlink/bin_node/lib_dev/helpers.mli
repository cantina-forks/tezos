(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** [now ()] returns the current time. *)
val now : unit -> Time.Protocol.t

(** [with_timing event k] computes how much time [k ()] takes to be computed
    and advertises it with [event]. *)
val with_timing : (Ptime.span -> unit Lwt.t) -> (unit -> 'a Lwt.t) -> 'a Lwt.t

(** [unwrap_error_monad f] execute f and fails with a Failure when the
    error monad returns an error. *)
val unwrap_error_monad : (unit -> 'a tzresult Lwt.t) -> 'a Lwt.t

(** [normalize_addr addr] normalized an L2 address [addr],
    i.e. lowercase it and remove prefix "0x". *)
val normalize_addr : string -> string
