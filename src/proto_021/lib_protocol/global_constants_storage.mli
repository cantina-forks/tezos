(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Marigold <team@marigold.dev>                           *)
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

(** This module represents access to a global table of constant
    Micheline values. Users may register a Micheline value in the
    table, paying the cost of storage. Once stored, scripts may
    reference this value by its hash. 
    
    Note: the table does not typecheck the values stored in it.
    Instead, any place that uses constants must first call [expand]
    before typechecking the code. This decision was made to make it as
    easy as possible for users to register values to the table, and also
    to allow maximum flexibility in the use of constants for different
    parts of a Michelson script (code, types, data, etc.). *)

type error += Expression_too_deep

type error += Expression_already_registered

(** A constant is the prim of the literal characters "constant".
    A constant must have a single argument, being a string with a
    well formed hash of a Micheline expression (i.e generated by
    [Script_expr_hash.to_b58check]). *)
type error += Badly_formed_constant_expression

type error += Nonexistent_global

(** [get context hash] retrieves the Micheline value with the given hash.
     
    Fails with [Nonexistent_global] if no value is found at the given hash.

    Fails with [Storage_error Corrupted_data] if the deserialisation fails.
      
    Consumes [Gas_repr.read_bytes_cost <size of the value>]. *)
val get :
  Raw_context.t ->
  Script_expr_hash.t ->
  (Raw_context.t * Script_repr.expr) tzresult Lwt.t

(** [register context value] registers a constant in the global table of constants,
    returning the hash and storage bytes consumed.

    Does not type-check the Micheline code being registered, allow potentially
    ill-typed Michelson values to be stored in the table (see note at top of module).

    The constant is stored unexpanded, but it is temporarily expanded at registration
    time only to check the expanded version respects the following limits.
    This also ensures there are no cyclic dependencies between constants.

    Fails with [Expression_too_deep] if, after fully expanding all constants,
    the expression would have a depth greater than [Constant_repr.max_allowed_global_constant_depth].

    Fails with [Badly_formed_constant_expression] if constants are not
    well-formed (see declaration of [Badly_formed_constant_expression]) or with
    [Nonexistent_global] if a referenced constant does not exist in the table.

    Consumes serialization cost.
    Consumes [Gas_repr.write_bytes_cost <size>] where size is the number
    of bytes in the binary serialization provided by [Script_repr.expr_encoding]. *)
val register :
  Raw_context.t ->
  Script_repr.expr ->
  (Raw_context.t * Script_expr_hash.t * Z.t) tzresult Lwt.t

(** [expand context expr] replaces every constant in the
    given Michelson expression with its value stored in the global table.

    The expansion is applied recursively so that the returned expression
    contains no constant.

    Fails with [Badly_formed_constant_expression] if constants are not
    well-formed (see declaration of [Badly_formed_constant_expression]) or
    with [Nonexistent_global] if a referenced constant does not exist in
    the table. *)
val expand :
  Raw_context.t ->
  Script_repr.expr ->
  (Raw_context.t * Script_repr.expr) tzresult Lwt.t

module Internal_for_tests : sig
  (** [node_too_large node] returns true if:
      - The number of sub-nodes in the [node] 
        exceeds [Global_constants_storage.node_size_limit].
      - The sum of the bytes in String, Int,
        and Bytes sub-nodes of [node] exceeds
        [Global_constants_storage.bytes_size_limit].
      
      Otherwise returns false.  *)
  val node_too_large : Script_repr.node -> bool

  (** [bottom_up_fold_cps initial_accumulator node initial_k f]
   folds [node] and all its sub-nodes if any, starting from
   [initial_accumulator], using an initial continuation [initial_k].
   At each node, [f] is called to transform the continuation [k] into
   the next one. This explicit manipulation of the continuation
   is typically useful to short-circuit.

   Notice that a common source of bug is to forget to properly call the
   continuation in `f`.
   
   See [Global_constants_storage.expand] for an example.

   TODO: https://gitlab.com/tezos/tezos/-/issues/1609
   Move function to lib_micheline.

   On our next opportunity to update the environment, we
   should move this function to lib_micheline.
   *)
  val bottom_up_fold_cps :
    'accumulator ->
    'loc Script_repr.michelson_node ->
    ('accumulator -> 'loc Script_repr.michelson_node -> 'return) ->
    ('accumulator ->
    'loc Script_repr.michelson_node ->
    ('accumulator -> 'loc Script_repr.michelson_node -> 'return) ->
    'return) ->
    'return

  (* [expr_to_address_in_context context expr] converts [expr]
     into a unique hash represented by a [Script_expr_hash.t].

     Consumes gas corresponding to the cost of converting [expr]
     to bytes and hashing the bytes. *)
  val expr_to_address_in_context :
    Raw_context.t ->
    Script_repr.expr ->
    (Raw_context.t * Script_expr_hash.t) tzresult
end
