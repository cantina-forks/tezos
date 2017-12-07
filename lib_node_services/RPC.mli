(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2017.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

(** Typed RPC services: definition, binding and dispatch. *)

module Data : Resto.ENCODING with type 'a t = 'a Data_encoding.t
                              and type schema = Data_encoding.json_schema

include (module type of struct include Resto end)
module Service : (module type of struct include Resto.MakeService(Data) end)

(** Compatibility layer, to be removed ASAP. *)

val service:
  ?description: string ->
  input: 'input Data_encoding.t ->
  output: 'output Data_encoding.t ->
  ('prefix, 'params) Path.t ->
  ([ `POST ], 'prefix, 'params, unit, 'input, 'output, unit) Service.t

type directory_descr = Data_encoding.json_schema Description.directory

val forge_request :
  (_ , unit, 'params, unit, 'input, 'output, unit) Service.t ->
  'params -> 'input -> MethMap.key * string list * Data_encoding.json

