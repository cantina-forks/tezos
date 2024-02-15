(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2021 Nomadic Labs, <contact@nomadic-labs.com>               *)
(* Copyright (c) 2022 G.B. Fefe, <gb.fefe@protonmail.com>                    *)
(*                                                                           *)
(*****************************************************************************)

(** This module is responsible for ensuring that a delegate doesn't
    get slashed twice for the same offense. To do so, it maintains the
    {!Storage.Already_denounced} table, which tracks which
    denunciations have already been seen in blocks.

    Invariant: {!Storage.Already_denounced} is empty for cycles equal
    to [current_cycle - max_slashing_period] or older. Indeed, such
    denunciations are no longer allowed (see
    [Anonymous.check_denunciation_age] in {!Validate}) so there is no
    need to track them anymore. *)

(** Returns true if the given delegate has already been denounced for
    double baking for the given level and round. *)
val already_denounced_for_double_baking :
  Raw_context.t ->
  Signature.Public_key_hash.t ->
  Level_repr.t ->
  Round_repr.t ->
  bool tzresult Lwt.t

(** Returns true if the given delegate has already been denounced for
    double preattesting or double attesting for the given level and
    round. *)
val already_denounced_for_double_attesting :
  Raw_context.t ->
  Signature.Public_key_hash.t ->
  Level_repr.t ->
  Round_repr.t ->
  bool tzresult Lwt.t

(** Records a denunciation in {!Storage.Already_denounced}.

    Precondition: the given level should be more recent than
    [current_cycle - max_slashing_period] in order to maintain the
    invariant on the age of tracked denunciations. Fortunately, this
    is already enforced in {!Validate} by
    [Anonymous.check_denunciation_age].

    @raise [Assert_failure] if the same denunciation is already
    present in {!Storage.Already_denounced}. *)
val add_denunciation :
  Raw_context.t ->
  Signature.public_key_hash ->
  Level_repr.t ->
  Round_repr.t ->
  Misbehaviour_repr.kind ->
  Raw_context.t tzresult Lwt.t

(** Clear {!Storage.Already_denounced} for the cycle [new_cycle -
    max_slashing_period]. Indeed, denunciations on events which
    happened during this cycle are no longer allowed anyway. *)
val clear_outdated_cycle :
  Raw_context.t -> new_cycle:Cycle_repr.t -> Raw_context.t Lwt.t
