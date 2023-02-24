(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

open Protocol.Alpha_context

(** Type to represent {e appoximate upper-bounds} for the fee and limits, used
    to compute an upper bound on the size (in bytes) of an operation. *)
type approximate_fee_bound = {
  fee : Tez.t;
  counter : Manager_counter.t;
  gas_limit : Gas.Arith.integral;
  storage_limit : Z.t;
}

type injection_strategy =
  [ `Each_block  (** Inject pending operations after each new L1 block *)
  | `Delay_block of float
    (** [`Delay_block f] strategy waits for [f] * the next block time to be
        elapsed before injecting pending operations. This strategy allows for
        maximizing the number of the same kind of operations to include in a
        block. *)
  ]

(** Explanation for unsuccessful operations (that are included in a block). *)
type unsuccessful_status =
  | Other_branch
      (** The operation is included in a block that is not on the main chain
          anymore, because of a reorganization. *)
  | Backtracked
      (** The operation is backtracked because of a further failing operation in
          the same batch. *)
  | Skipped
      (** The operation is skipped because of a previous failing operation in
          the same batch. *)
  | Failed of error trace  (** The operation failed with the provided error. *)

type operation_status = Successful | Unsuccessful of unsuccessful_status

(** Action to be taken for unsuccessful operation. *)
type retry_action =
  | Retry  (** The operation is retried by being re-queued for injection. *)
  | Forget  (** The operation is forgotten without error. *)
  | Abort of error trace
      (** The error for the failing operation should be propagated at a higher
          level. *)

(** Signature for tags used in injector  *)
module type TAG = sig
  include Stdlib.Set.OrderedType

  include Stdlib.Hashtbl.HashedType with type t := t

  val pp : Format.formatter -> t -> unit

  val encoding : t Data_encoding.t
end

module type PARAM_OPERATION = sig
  (** The abstract type of operations to inject *)
  type t

  (** An encoding for injector's operations *)
  val encoding : t Data_encoding.t

  (** Convert an injector operation to a manager_operation of the protocol *)
  val to_manager_operation : t -> packed_manager_operation

  (** Pretty-printing injector's operations *)
  val pp : Format.formatter -> t -> unit
end

(** Internal representation of injector operations. *)
module type INJECTOR_OPERATION = sig
  type operation

  (** Hash with b58check encoding iop(53), for hashes of injector operations *)
  module Hash : Tezos_crypto.Intfs.HASH

  (** Alias for L1 operations hashes *)
  type hash = Hash.t

  (** The type of L1 operations that are injected on Tezos. These have a hash
      attached to them that allows tracking and retrieving their status. *)
  type t = private {hash : hash; operation : operation}

  (** [make op] returns an L1 operation with the corresponding hash. *)
  val make : operation -> t

  (** Encoding for L1 operations *)
  val encoding : t Data_encoding.t

  (** Pretty printer for L1 operations. Only the relevant part for the rollup node
      is printed. *)
  val pp : Format.formatter -> t -> unit
end

(** Module type for parameter of functor {!Injector_functor.Make}. *)
module type PARAMETERS = sig
  (** The type of the state that the injector can access *)
  type state

  (** A module which contains the different tags for the injector *)
  module Tag : TAG

  (** A module for the injector operations *)
  module Operation : PARAM_OPERATION

  (** Where to put the events for this injector  *)
  val events_section : string list

  (** Coarse approximation for the number of operation of each tag we expect to
      inject for each block. *)
  val table_estimated_size : Tag.t -> int

  (** Action (see {!retry_action}) to be taken on unsuccessful operation (see
      {!unsuccessful_status}). *)
  val retry_unsuccessful_operation :
    state -> Operation.t -> unsuccessful_status -> retry_action Lwt.t

  (** The tag of a manager operation. This is used to send operations to the
      correct queue automatically (when signer is not provided) and to recover
      persistent information. *)
  val operation_tag : Operation.t -> Tag.t

  (** Returns the {e approximate upper-bounds} for the fee and limits of an
      operation, used to compute an upper bound on the size (in bytes) for this
      operation. *)
  val approximate_fee_bound : state -> Operation.t -> approximate_fee_bound

  (** Returns the fee_parameter (to compute fee w.r.t. gas, size, etc.) and the
      caps of fee and burn for each operation. *)
  val fee_parameter : state -> Operation.t -> Injection.fee_parameter

  (** When injecting the given [operations] in an L1 batch, if
     [batch_must_succeed operations] returns [`All] then all the operations must
     succeed in the simulation of injection. If it returns [`At_least_one], at
     least one operation in the list [operations] must be successful in the
     simulation. In any case, only operations which are known as successful will
     be included in the injected L1 batch. {b Note}: Returning [`At_least_one]
     allows to incrementally build "or-batches" by iteratively removing
     operations that fail from the desired batch. *)
  val batch_must_succeed : Operation.t list -> [`All | `At_least_one]
end

(** Output signature for functor {!Injector_functor.Make}. *)
module type S = sig
  type state

  type tag

  type operation

  module Inj_operation : INJECTOR_OPERATION with type operation = operation

  (** Information stored about an L1 operation that was injected on a Tezos
    node. *)
  type injected_info = {
    op : Inj_operation.t;  (** The injector operation. *)
    oph : Operation_hash.t;
        (** The hash of the operation which contains [op] (this can be an L1 batch
          of several manager operations). *)
    op_index : int;
        (** The index of the operation [op] in the L1 batch corresponding to [oph]. *)
  }

  (** Information stored about an L1 operation that was included in a Tezos
    block. *)
  type included_info = {
    op : Inj_operation.t;  (** The injector operation. *)
    oph : Operation_hash.t;
        (** The hash of the operation which contains [op] (this can be an L1 batch
          of several manager operations). *)
    op_index : int;
        (** The index of the operation [op] in the L1 batch corresponding to [oph]. *)
    l1_block : Block_hash.t;
        (** The hash of the L1 block in which the operation was included. *)
    l1_level : int32;  (** The level of [l1_block]. *)
  }

  (** Status of an operation in the injector. *)
  type status =
    | Pending of operation  (** The operation is pending injection. *)
    | Injected of injected_info
        (** The operation has been injected successfully in the node. *)
    | Included of included_info
        (** The operation has been included in a L1 block. *)

  val injected_info_encoding : injected_info Data_encoding.t

  val included_info_encoding : included_info Data_encoding.t

  (** Initializes the injector with the rollup node state, for a list of
      signers, and start the workers. Each signer has its own worker with a
      queue of operations to inject.

      [retention_period] is the number of blocks for which the injector keeps
      the included information for, must be positive or zero. By default (when
      [0]), the injector will not keep information longer than necessary. It can
      be useful to set this value to something [> 0] if we want to retrieve
      information about operations included on L1 for a given period. *)
  val init :
    #Protocol_client_context.full ->
    data_dir:string ->
    ?retention_period:int ->
    state ->
    signers:(public_key_hash * injection_strategy * tag list) list ->
    unit tzresult Lwt.t

  (** Add an operation as pending injection in the injector. If the source is
      not provided, the operation is queued to the worker which handles the
      corresponding tag. It returns the hash of the operation in the injector
      queue. *)
  val add_pending_operation :
    ?source:public_key_hash -> operation -> Inj_operation.Hash.t tzresult Lwt.t

  (** Notify the injector of a new Tezos head. The injector marks the operations
      appropriately (for instance reverted operations that are part of a
      reorganization are put back in the pending queue). When an operation is
      considered as {e confirmed}, it disappears from the injector. *)
  val new_tezos_head :
    Protocol_client_context.Alpha_block_services.block_info ->
    Protocol_client_context.Alpha_block_services.block_info
    Injector_common.reorg ->
    unit Lwt.t

  (** Trigger an injection of the pending operations for all workers. If [tags]
      is given, only the workers which have a tag in [tags] inject their pending
      operations. [header] must be provided for the [`Delay_block] strategy to
      compute the next block timestamp. *)
  val inject :
    ?tags:tag list -> ?header:Tezos_base.Block_header.t -> unit -> unit Lwt.t

  (** Shutdown the injectors, waiting for the ongoing request to be processed. *)
  val shutdown : unit -> unit Lwt.t

  (** The status of an operation in the injector.  *)
  val operation_status : Inj_operation.Hash.t -> status option
end
