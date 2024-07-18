(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
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

(** Testing
    -------
    Component:    Adaptive Issuance, Slashing
    Invocation:   dune exec src/proto_beta/lib_protocol/test/integration/main.exe \
                   -- --file test_scenario_slashing.ml
    Subject:      Test slashing scenarios in the protocol.
*)

open State_account
open Tez_helpers.Ez_tez
open Scenario
open Scenario_constants

let fs = Format.asprintf

(** Test multiple misbehaviors
    - Test a single delegate misbehaving multiple times
    - Test multiple delegates misbehaving
    - Test multiple delegates misbehaving multiple times
    - Test denunciation at once or in a staggered way
    - Test denunciation in chronological order or reverse order
    - Spread misbehaviors/denunciations over multiple cycles
    *)
let test_multiple_misbehaviors =
  (* Denounce all misbehaviours or 14 one by one in chronological or reverse
     order *)
  let make_denunciations () =
    Tag "denounce chronologically"
    --> log "denounce chronologically"
    --> (Tag "all at once" --> make_denunciations ~rev:false ()
        |+ Tag "one by one"
           --> loop
                 12
                 (make_denunciations
                    ~filter:(fun {denounced; _} -> not denounced)
                    ~single:true
                    ~rev:false
                    ()))
    |+ Tag "denounce reverse" --> log "denounce reverse"
       --> (Tag "all at once" --> make_denunciations ~rev:true ()
           |+ Tag "one by one"
              --> loop
                    12
                    (make_denunciations
                       ~filter:(fun {denounced; _} -> not denounced)
                       ~single:true
                       ~rev:true
                       ()))
  in
  (* Misbehaviors scenarios *)
  let misbehave i delegate1 delegate2 =
    (Tag "single delegate"
     (* A single delegate misbehaves several times before being denunced *)
     --> loop
           i
           (double_attest delegate1 --> double_preattest delegate1
          --> double_bake delegate1 --> double_attest delegate1
          --> double_preattest delegate1)
     --> exclude_bakers [delegate1]
    |+ Tag "multiple delegates"
       (* Two delegates double bake sequentially *)
       --> loop
             i
             (loop
                3
                (double_bake delegate1 --> double_bake delegate2 --> next_block))
       --> exclude_bakers [delegate1; delegate2]
    |+ Tag "double misbehaviors"
       (* Two delegates misbehave in parallel for multiple levels *)
       --> loop
             i
             (double_attest_many [delegate1; delegate2]
             --> double_attest_many [delegate1; delegate2]
             --> double_preattest_many [delegate1; delegate2]
             --> double_bake_many [delegate1; delegate2])
       --> exclude_bakers [delegate1; delegate2])
    --> make_denunciations ()
  in
  init_constants ~blocks_per_cycle:24l ~reward_per_block:0L ()
  --> set S.Adaptive_issuance.autostaking_enable false
  --> (Tag "No AI" --> activate_ai `No |+ Tag "Yes AI" --> activate_ai `Force)
  --> branch_flag S.Adaptive_issuance.ns_enable
  --> begin_test ["delegate"; "bootstrap1"; "bootstrap2"; "bootstrap3"]
  --> next_cycle
  --> (* various make misbehaviors spread over 1 or two cycles *)
  List.fold_left
    (fun acc i ->
      acc
      |+ Tag (string_of_int i ^ " misbehavior loops")
         --> misbehave i "delegate" "bootstrap1"
         --> next_cycle)
    Empty
    [1; 3]

let check_is_forbidden ~loc baker =
  assert_failure
    ~expected_error:(fun (_, state) errs ->
      let baker = State.find_account baker state in
      Error_helpers.expect_forbidden_delegate ~loc ~delegate:baker.contract errs)
    (next_block_with_baker baker)

let check_is_not_forbidden baker =
  let open Lwt_result_syntax in
  exec (fun ((block, state) as input) ->
      let baker = State.find_account baker state in
      let* _ = Block.bake ~policy:(By_account baker.pkh) block in
      return input)

(** Tests forbidding delegates ensuring:
  - delegates are not forbidden until a denunciation is made (allowing for
    multiple misbehaviours)
  - a single misbehaviour is enough to be denunced and forbidden
  - delegates are unforbidden after a certain amount of time
  - delegates are not forbidden if denounced for an outdated misbehaviour
*)
let test_delegate_forbidden =
  let crd (_, state) = state.State.constants.consensus_rights_delay in
  init_constants ~blocks_per_cycle:32l ()
  --> set S.Adaptive_issuance.autostaking_enable false
  --> activate_ai `No
  --> branch_flag S.Adaptive_issuance.ns_enable
  --> begin_test ["delegate"; "bootstrap1"; "bootstrap2"]
  --> set_baker "bootstrap1"
  --> (Tag "Is not forbidden until first denunciation"
       --> loop 14 (double_bake "delegate")
       --> exclude_bakers ["delegate"]
       --> (* ensure delegate is not forbidden until the denunciations are done *)
       check_is_not_forbidden "delegate"
       --> make_denunciations ()
       --> (* delegate is forbidden directly after the first denunciation *)
       check_is_forbidden ~loc:__LOC__ "delegate"
      |+ Tag "Is forbidden after single misbehavior"
         --> double_attest "delegate"
         --> (Tag "very early first denounce"
              --> exclude_bakers ["delegate"]
              --> make_denunciations ()
             |+ Tag "in next cycle" --> next_cycle
                --> exclude_bakers ["delegate"]
                --> make_denunciations ())
         --> check_is_forbidden ~loc:__LOC__ "delegate"
      |+ Tag "Is unforbidden after CONSENSUS_RIGHTS_DELAY after slash cycles"
         --> double_attest "delegate"
         --> exclude_bakers ["delegate"]
         --> make_denunciations ()
         --> check_is_forbidden ~loc:__LOC__ "delegate"
         --> next_cycle (* slash occured *) --> stake "delegate" Half
         --> wait_n_cycles_f crd
         --> check_is_not_forbidden "delegate"
      |+ Tag "Is not forbidden after a denunciation is outdated"
         --> double_attest "delegate" --> wait_n_cycles 2
         --> assert_failure
               ~expected_error:(fun (_block, state) errs ->
                 Error_helpers.expect_outdated_denunciation_state
                   ~loc:__LOC__
                   ~state
                   errs)
               (make_denunciations ())
         --> check_is_not_forbidden "delegate"
      |+ Tag
           "Two double attestations, in consecutive cycles, denounce out of \
            order" --> double_attest "delegate" --> next_cycle
         --> double_attest "delegate"
         --> make_denunciations
               ~filter:(fun {denounced; misbehaviour = {level; _}; _} ->
                 (not denounced) && Protocol.Raw_level_repr.to_int32 level > 10l)
               ()
         --> make_denunciations
               ~filter:(fun {denounced; misbehaviour = {level; _}; _} ->
                 (not denounced)
                 && Protocol.Raw_level_repr.to_int32 level <= 10l)
               ()
         --> check_is_forbidden ~loc:__LOC__ "delegate")

let test_slash_unstake =
  init_constants ()
  --> set S.Adaptive_issuance.autostaking_enable false
  --> activate_ai `No
  --> branch_flag S.Adaptive_issuance.ns_enable
  --> begin_test ["delegate"; "bootstrap1"; "bootstrap2"]
  --> set_baker "bootstrap1" --> next_cycle --> unstake "delegate" Half
  --> next_cycle --> double_bake "delegate" --> make_denunciations ()
  --> (Empty |+ Tag "unstake twice" --> unstake "delegate" Half)
  --> wait_n_cycles 5
  --> finalize_unstake "delegate"

let test_slash_monotonous_stake =
  let scenario ~offending_op ~op ~early_d =
    init_constants ~blocks_per_cycle:16l ()
    --> set S.Adaptive_issuance.autostaking_enable false
    --> activate_ai `No
    --> branch_flag S.Adaptive_issuance.ns_enable
    --> begin_test ["delegate"; "bootstrap1"]
    --> next_cycle
    --> loop
          6
          (op "delegate" (Amount (Tez.of_mutez 1_000_000_000L)) --> next_cycle)
    --> offending_op "delegate"
    --> (op "delegate" (Amount (Tez.of_mutez 1_000_000_000L))
        --> loop
              2
              (op "delegate" (Amount (Tez.of_mutez 1_000_000_000L))
              -->
              if early_d then
                make_denunciations ()
                --> exclude_bakers ["delegate"]
                --> next_block
              else offending_op "delegate" --> next_block))
  in
  Tag "slashes with increasing stake"
  --> (Tag "denounce early"
       --> (Tag "Double Bake"
            --> scenario ~offending_op:double_bake ~op:stake ~early_d:true
           |+ Tag "Double attest"
              --> scenario
                    ~offending_op:(fun s -> double_attest s)
                    ~op:stake
                    ~early_d:true)
      |+ Tag "denounce late"
         --> (Tag "Double Bake"
              --> scenario ~offending_op:double_bake ~op:stake ~early_d:false
             |+ Tag "Double attest"
                --> scenario
                      ~offending_op:(fun s -> double_attest s)
                      ~op:stake
                      ~early_d:false)
         --> make_denunciations ())
  |+ Tag "slashes with decreasing stake"
     --> (Tag "Double Bake"
          --> scenario ~offending_op:double_bake ~op:unstake ~early_d:true
         |+ Tag "Double attest"
            --> scenario
                  ~offending_op:(fun s -> double_attest s)
                  ~op:unstake
                  ~early_d:true)
  |+ Tag "denounce late"
     --> (Tag "Double Bake"
          --> scenario ~offending_op:double_bake ~op:unstake ~early_d:false
         |+ Tag "Double attest"
            --> scenario
                  ~offending_op:(fun s -> double_attest s)
                  ~op:unstake
                  ~early_d:false)
     --> make_denunciations ()

let test_slash_timing =
  init_constants ~blocks_per_cycle:8l ()
  --> set S.Adaptive_issuance.autostaking_enable false
  --> activate_ai `No
  --> branch_flag S.Adaptive_issuance.ns_enable
  --> begin_test ["delegate"; "bootstrap1"]
  --> next_cycle
  --> (Tag "stake" --> stake "delegate" Half
      |+ Tag "unstake" --> unstake "delegate" Half)
  --> (Tag "with a first slash" --> double_bake "delegate"
       --> exclude_bakers ["delegate"]
       --> make_denunciations ()
      |+ Tag "without another slash" --> Empty)
  --> stake "delegate" Half
  --> List.fold_left
        (fun acc i ->
          acc |+ Tag (string_of_int i ^ " cycles lag") --> wait_n_cycles i)
        (wait_n_cycles 2)
        [3; 4; 5; 6]
  --> double_bake "delegate"
  --> exclude_bakers ["delegate"]
  --> make_denunciations () --> next_cycle

let test_no_shortcut_for_cheaters =
  let amount = Amount (Tez.of_mutez 333_000_000_000L) in
  let consensus_rights_delay =
    Default_parameters.constants_test.consensus_rights_delay
  in
  init_constants ()
  --> set S.Adaptive_issuance.autostaking_enable false
  --> activate_ai `Force
  --> begin_test ["delegate"; "bootstrap1"]
  --> stake "delegate" (Amount (Tez.of_mutez 1_800_000_000_000L))
  --> next_cycle --> double_bake "delegate" --> make_denunciations ()
  --> set_baker "bootstrap1" (* exclude_bakers ["delegate"] *)
  --> next_cycle
  --> snapshot_balances "init" ["delegate"]
  --> unstake "delegate" amount
  --> (List.fold_left
         (fun acc i -> acc |+ Tag (fs "wait %i cycles" i) --> wait_n_cycles i)
         (Tag "wait 0 cycles" --> Empty)
         (Stdlib.List.init (consensus_rights_delay - 1) (fun i -> i + 1))
       --> stake "delegate" amount
       --> assert_failure_in_check_snapshot_balances ~loc:__LOC__ "init"
      |+ Tag "wait enough cycles (consensus_rights_delay + 1)"
         --> wait_n_cycles (consensus_rights_delay + 1)
         --> stake "delegate" amount
         --> check_snapshot_balances "init")

let test_slash_correct_amount_after_stake_from_unstake =
  let amount_to_unstake = Amount (Tez.of_mutez 200_000_000_000L) in
  let amount_to_restake = Amount (Tez.of_mutez 100_000_000_000L) in
  let amount_expected_in_unstake_after_slash = Tez.of_mutez 50_000_000_000L in
  let consensus_rights_delay =
    Default_parameters.constants_test.consensus_rights_delay
  in
  init_constants ()
  --> set S.Adaptive_issuance.autostaking_enable false
  --> activate_ai `Force
  --> begin_test ["delegate"; "bootstrap1"]
  --> stake "delegate" (Amount (Tez.of_mutez 1_800_000_000_000L))
  --> next_cycle
  --> unstake "delegate" amount_to_unstake
  --> stake "delegate" amount_to_restake
  --> List.fold_left
        (fun acc i -> acc |+ Tag (fs "wait %i cycles" i) --> wait_n_cycles i)
        (Tag "wait 0 cycles" --> Empty)
        (Stdlib.List.init (consensus_rights_delay - 2) (fun i -> i + 1))
  --> double_attest "delegate" --> make_denunciations ()
  --> exclude_bakers ["delegate"]
  --> next_cycle
  --> check_balance_field
        "delegate"
        `Unstaked_frozen_total
        amount_expected_in_unstake_after_slash

(* Test a non-zero request finalizes for a non-zero amount if it hasn't been slashed 100% *)
let test_mini_slash =
  init_constants ()
  --> set S.Adaptive_issuance.autostaking_enable false
  --> (Tag "Yes AI" --> activate_ai `Force --> begin_test ["delegate"; "baker"]
      |+ Tag "No AI" --> activate_ai `No --> begin_test ["delegate"; "baker"])
  --> unstake "delegate" (Amount Tez.one_mutez)
  --> set_baker "baker" --> next_cycle
  --> (Tag "5% slash" --> double_bake "delegate" --> make_denunciations ()
      |+ Tag "95% slash" --> next_cycle --> double_attest "delegate"
         --> loop 9 (double_bake "delegate")
         --> make_denunciations ())
  (* Wait two cycles because of ns_enable *)
  --> next_cycle
  --> next_cycle
  --> check_balance_field "delegate" `Unstaked_frozen_total Tez.zero
  --> wait_n_cycles_f (fun (_, state) ->
          state.constants.consensus_rights_delay + 1)

let test_slash_rounding =
  init_constants ()
  --> set S.Adaptive_issuance.autostaking_enable false
  --> activate_ai `Force
  --> branch_flag S.Adaptive_issuance.ns_enable
  --> begin_test ["delegate"; "baker"]
  --> set_baker "baker"
  --> unstake "delegate" (Amount (Tez.of_mutez 2L))
  --> next_cycle --> double_bake "delegate" --> double_bake "delegate"
  --> make_denunciations () --> wait_n_cycles 7
  --> finalize_unstake "delegate"

(* TODO #6645: reactivate tests *)
let tests =
  tests_of_scenarios
  @@ [
       ("Test multiple misbehaviors", test_multiple_misbehaviors);
       ("Test slashed is forbidden", test_delegate_forbidden);
       ("Test slash with unstake", test_slash_unstake);
       (* TODO: make sure this test passes with blocks_per_cycle:8l
          https://gitlab.com/tezos/tezos/-/issues/6904 *)
       ("Test slashes with simple varying stake", test_slash_monotonous_stake);
       ("Test slash timing", test_slash_timing);
       ( "Test stake from unstake deactivated when slashed",
         test_no_shortcut_for_cheaters );
       ( "Test stake from unstake reduce initial amount",
         test_slash_correct_amount_after_stake_from_unstake );
       ("Test unstake 1 mutez then slash", test_mini_slash);
       ("Test slash rounding", test_slash_rounding);
     ]

let () =
  register_tests ~__FILE__ ~tags:["protocol"; "scenario"; "slashing"] tests
