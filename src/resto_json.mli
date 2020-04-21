(**************************************************************************)
(*  resto                                                                 *)
(*  Copyright (C) 2016, OCamlPro.                                         *)
(*                                                                        *)
(*    All rights reserved.  This file is distributed under the terms      *)
(*    of the GNU Lesser General Public License version 2.1, with the      *)
(*    special exception on linking described in the file LICENSE.         *)
(*                                                                        *)
(**************************************************************************)

(** A wrapper around [json-data-encoding] that exposes the modules expected by
    [Resto]. *)

(** [Encoding] exposes the minimal part [Json_encoding] that allow to construct
    new encodings as well as pre-made encodings for values useful to [Resto].

    It also makes the type of encodings ['a t] concrete (['a
    Json_encoding.encodings]) which allows for further use -- see [VALUE]. *)
module Encoding : Resto.ENCODING
  with type 'a t = 'a Json_encoding.encoding
   and type schema = Json_schema.schema

(** A [VALUE] module allows the actual conversion of values between different
    representations. It is intended as a companion to the [Encoding] module
    above. *)
module type VALUE = sig
  type t
  type 'a encoding
  val construct: 'a encoding -> 'a -> t
  val destruct: 'a encoding -> t -> 'a
end

module Ezjsonm : VALUE
  with type t = Json_repr.Ezjsonm.value
   and type 'a encoding := 'a Encoding.t

module Bson : VALUE
  with type t = Json_repr_bson.bson
   and type 'a encoding := 'a Encoding.t
