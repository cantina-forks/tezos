(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2024 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** A collection of hooks to personalize the execution of the WASM Fast
    Execution. *)
type t = {
  fast_exec_panicked : (unit -> unit Lwt.t) option;
  fast_exec_completed : (unit -> unit Lwt.t) option;
  fast_exec_fallback : bool;
}

(** [no_hooks] is the empty collection of hooks, which can be used as a
    baseline to build hooks collection. *)
val no_hooks : t

(** [on_fast_exec_panicked k hooks] {b replaces b} the hook executed when
    the Fast Execution engine panics by [k] in [hooks]. *)
val on_fast_exec_panicked : (unit -> unit Lwt.t) -> t -> t

(** [on_fast_exec_completed k hooks] {b replaces b} the hook executed when
    the Fast Execution engine completes a [kernel_run] by [k] in [hooks]. *)
val on_fast_exec_completed : (unit -> unit Lwt.t) -> t -> t

(** [fast_exec_fallback c hooks] returns a new collection of hooks
    instructing the Fast Execution engine to fallback to the WASM PVM in
    case of errors.

    It is true by default, but keep in mind the Fast Execution is {b very b}
    slow. *)
val fast_exec_fallback : bool -> t -> t
