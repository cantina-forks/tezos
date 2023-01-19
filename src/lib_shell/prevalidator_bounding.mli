(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2023 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

(** Bound the valid operations in the mempool by limiting both their
    cardinal and their total byte size. *)

(** Mempool bounds.

    They can be retrieved/set using RPCs GET/POST
    [/chains/<chain>/mempool/filter]. *)
type config = {
  max_operations : int;
      (** Maximal allowed number of valid operations in the mempool. *)
  max_total_bytes : int;
      (** Maximal allowed sum of the byte sizes of all valid operations in
          the mempool. *)
}

(** Default {!field-max_total_bytes} is [10_000_000].

    A block can have at most around 700k bytes of operations (see
    [validation_passes] in [proto_xxx/lib_protocol/main.ml]). So with
    this bound, a mempool can have the content of more than 10 blocks,
    which is more than enough. *)
val default_max_total_bytes : int

(** Default {!field-max_operations} is [10_000].

    The smallest operations are around 140 bytes (e.g. 139 bytes for a
    (pre)attestation, 146 bytes for a delegation) so a block can have
    at most around 5_000 operations. But many operations are much
    larger, so in practice a block contains much less operations, so
    keeping 10_000 of them in the mempool is enough. *)
val default_max_operations : int

(** Default bounds. *)
val default_config : config

module type T = sig
  (** Internal overview of all the valid operations present in the mempool. *)
  type state

  (** Empty state containing no operations. *)
  val empty : state

  (** Type [Tezos_protocol_environment.PROTOCOL.operation]. *)
  type protocol_operation

  (** Try and add an operation to the state.

      When the mempool is not full (i.e. adding the operation does not
      break the {!max_operations} nor the {!max_total_bytes} limits),
      return the updated state and an empty list.

      When the mempool is full, return either:
      - an updated state and a list of replaced operations, which are
        all smaller than the new operation (according to the protocol's
        [compare_operations] function) and have been removed from the
        state to make room for the new operation, or
      - [None] when it is not possible to make room for the new
        operation by removing only operations that are smaller than it.

      When the operation is already present in the state, do nothing
      i.e. return the unchanged state and an empty replacement list.

      Precondition: the operation has been validated by the protocol
      in some context (otherwise calling the protocol's
      [compare_operations] function on it may fail). *)
  val add_operation :
    state ->
    config ->
    protocol_operation Shell_operation.operation ->
    (state * Operation_hash.t list) option

  (** Remove the operation from the state.

      Do nothing if the operation was not in the state
      (the returned state is then physically equal to the input state). *)
  val remove_operation : state -> Operation_hash.t -> state
end

module Make (Proto : Tezos_protocol_environment.PROTOCOL) :
  T with type protocol_operation = Proto.operation
