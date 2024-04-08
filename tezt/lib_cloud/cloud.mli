(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* SPDX-FileCopyrightText: 2024 Nomadic Labs <contact@nomadic-labs.com>      *)
(*                                                                           *)
(*****************************************************************************)

type t

(** [register ?vms] is a wrapper around [Test.register]. It
    enables to run a test that can use machines deployed onto the
    cloud. *)
val register :
  ?vms:int ->
  __FILE__:string ->
  title:string ->
  tags:string list ->
  ?seed:Test.seed ->
  (t -> unit Lwt.t) ->
  unit

val agents : t -> Agent.t list

val push_metric :
  t -> ?labels:(string * string) list -> name:string -> int -> unit

val set_agent_name : t -> Agent.t -> string -> unit Lwt.t

type target = {agent : Agent.t; port : int; app_name : string}

val add_prometheus_source :
  t -> ?metric_path:string -> job_name:string -> target list -> unit Lwt.t
