(* Do not edit this file manually.
   This file was automatically generated from benchmark models
   If you wish to update a function in this file,
   a. update the corresponding model, or
   b. move the function to another module and edit it there. *)

[@@@warning "-33"]

module S = Saturation_repr
open S.Syntax

(* model storage/List_key_values/intercept *)
(* fun size -> 470. + (117. * size) *)
let cost_intercept size =
  let size = S.safe_int size in
  let v0 = size in
  S.safe_int 470 + (v0 * S.safe_int 118)
