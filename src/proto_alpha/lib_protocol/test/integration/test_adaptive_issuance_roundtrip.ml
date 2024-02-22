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
    Component:    Adaptive Issuance, launch vote
    Invocation:   dune exec src/proto_alpha/lib_protocol/test/integration/main.exe \
                   -- --file test_adaptive_issuance_roundtrip.ml
    Subject:      Test staking stability under Adaptive Issuance.
*)

open Adaptive_issuance_helpers
open State_account
open Log_helper
open Test_tez.Ez_tez
open Scenario_dsl
open Scenario_base
open Scenario_op

let fs = Format.asprintf

let default_param_wait, default_unstake_wait =
  let constants = Default_parameters.constants_test in
  let crd = constants.consensus_rights_delay in
  let dpad = constants.delegate_parameters_activation_delay in
  let msp = Protocol.Constants_repr.max_slashing_period in
  (dpad, crd + msp)

let test_expected_error =
  assert_failure
    ~expected_error:(fun _ -> [Exn (Failure "")])
    (exec (fun _ -> failwith ""))
  --> assert_failure
        ~expected_error:(fun _ -> [Unexpected_error])
        (assert_failure
           ~expected_error:(fun _ ->
             [Inconsistent_number_of_bootstrap_accounts])
           (exec (fun _ -> failwith "")))

let init_constants ?reward_per_block ?(deactivate_dynamic = false)
    ?blocks_per_cycle ?delegate_parameters_activation_delay ~autostaking_enable
    () =
  let reward_per_block = Option.value ~default:0L reward_per_block in
  let base_total_issued_per_minute = Tez.of_mutez reward_per_block in
  let default_constants = Default_parameters.constants_test in
  (* default for tests: 12 *)
  let blocks_per_cycle =
    Option.value ~default:default_constants.blocks_per_cycle blocks_per_cycle
  in
  let delegate_parameters_activation_delay =
    Option.value
      ~default:default_constants.delegate_parameters_activation_delay
      delegate_parameters_activation_delay
  in
  let issuance_weights =
    Protocol.Alpha_context.Constants.Parametric.
      {
        base_total_issued_per_minute;
        baking_reward_fixed_portion_weight = 1;
        baking_reward_bonus_weight = 0;
        attesting_reward_weight = 0;
        seed_nonce_revelation_tip_weight = 0;
        vdf_revelation_tip_weight = 0;
      }
  in
  let liquidity_baking_subsidy = Tez.zero in
  let minimal_block_delay = Protocol.Alpha_context.Period.one_minute in
  let cost_per_byte = Tez.zero in
  let consensus_threshold = 0 in
  let adaptive_issuance = default_constants.adaptive_issuance in
  let adaptive_rewards_params =
    if deactivate_dynamic then
      {
        adaptive_issuance.adaptive_rewards_params with
        max_bonus =
          Protocol.Issuance_bonus_repr.max_bonus_parameter_of_Q_exn Q.zero;
      }
    else adaptive_issuance.adaptive_rewards_params
  in
  let adaptive_issuance =
    {adaptive_issuance with adaptive_rewards_params; autostaking_enable}
  in
  {
    default_constants with
    delegate_parameters_activation_delay;
    consensus_threshold;
    issuance_weights;
    minimal_block_delay;
    cost_per_byte;
    adaptive_issuance;
    blocks_per_cycle;
    liquidity_baking_subsidy;
  }

(** Initialization of scenarios with 3 cases:
     - AI activated, staker = delegate
     - AI activated, staker != delegate
     - AI not activated (and staker = delegate)
    Any scenario that begins with this will be triplicated.
 *)
let init_scenario ?(force_ai = true) ?reward_per_block () =
  let constants =
    init_constants ?reward_per_block ~autostaking_enable:false ()
  in
  let init_params =
    {limit_of_staking_over_baking = Q.one; edge_of_baking_over_staking = Q.one}
  in
  let begin_test ~activate_ai ~self_stake =
    let name = if self_stake then "staker" else "delegate" in
    begin_test ~activate_ai ~constants [name]
    --> set_delegate_params name init_params
    --> set_baker "__bootstrap__"
  in
  let ai_activated =
    Tag "AI activated"
    --> (Tag "self stake" --> begin_test ~activate_ai:true ~self_stake:true
        |+ Tag "external stake"
           --> begin_test ~activate_ai:true ~self_stake:false
           --> add_account_with_funds
                 "staker"
                 "delegate"
                 (Amount (Tez.of_mutez 2_000_000_000_000L))
           --> set_delegate "staker" (Some "delegate"))
    --> wait_ai_activation
  in

  let ai_deactivated =
    Tag "AI deactivated, self stake"
    --> begin_test ~activate_ai:false ~self_stake:true
  in
  (if force_ai then ai_activated else ai_activated |+ ai_deactivated)
  --> next_block

module Roundtrip = struct
  let stake_init =
    stake "staker" Half
    --> (Tag "no wait after stake" --> Empty
        |+ Tag "wait after stake" --> wait_n_cycles 2)

  let wait_for_unfreeze_and_check wait =
    snapshot_balances "wait snap" ["staker"]
    --> wait_n_cycles (wait - 1)
    (* Balance didn't change yet, but will change next cycle *)
    --> check_snapshot_balances "wait snap"
    --> next_cycle
    --> assert_failure (check_snapshot_balances "wait snap")

  let finalize staker =
    assert_failure (check_balance_field staker `Unstaked_finalizable Tez.zero)
    --> finalize_unstake staker
    --> check_balance_field staker `Unstaked_finalizable Tez.zero

  let simple_roundtrip =
    stake_init
    --> (Tag "full unstake" --> unstake "staker" All
        |+ Tag "half unstake" --> unstake "staker" Half)
    --> wait_for_unfreeze_and_check default_unstake_wait
    --> finalize "staker" --> next_cycle

  let double_roundtrip =
    stake_init --> unstake "staker" Half
    --> (Tag "half then full unstake" --> wait_n_cycles 2
         --> unstake "staker" All
        |+ Tag "half then half unstake" --> wait_n_cycles 2
           --> unstake "staker" Half)
    --> wait_for_unfreeze_and_check (default_unstake_wait - 2)
    --> wait_for_unfreeze_and_check 2
    --> finalize "staker" --> next_cycle

  let shorter_roundtrip_for_baker =
    let constants = init_constants ~autostaking_enable:false () in
    let amount = Amount (Tez.of_mutez 333_000_000_000L) in
    let consensus_rights_delay = constants.consensus_rights_delay in
    begin_test ~activate_ai:true ~constants ["delegate"]
    --> next_block --> wait_ai_activation
    --> stake "delegate" (Amount (Tez.of_mutez 1_800_000_000_000L))
    --> next_cycle
    --> snapshot_balances "init" ["delegate"]
    --> unstake "delegate" amount
    --> List.fold_left
          (fun acc i -> acc |+ Tag (fs "wait %i cycles" i) --> wait_n_cycles i)
          (Tag "wait 0 cycles" --> Empty)
          (Stdlib.List.init (consensus_rights_delay + 1) (fun i -> i + 1))
    --> stake "delegate" amount
    --> check_snapshot_balances "init"

  let status_quo_rountrip =
    let full_amount = Tez.of_mutez 10_000_000L in
    let amount_1 = Tez.of_mutez 2_999_999L in
    let amount_2 = Tez.of_mutez 7_000_001L in
    snapshot_balances "init" ["staker"]
    --> stake "staker" (Amount full_amount)
    --> next_cycle
    --> (Tag "1 unstake" --> unstake "staker" (Amount full_amount)
        |+ Tag "2 unstakes"
           --> unstake "staker" (Amount amount_1)
           --> next_cycle
           --> unstake "staker" (Amount amount_2))
    --> wait_n_cycles default_unstake_wait
    --> finalize "staker"
    --> check_snapshot_balances "init"

  let scenario_finalize =
    no_tag --> stake "staker" Half --> next_cycle --> unstake "staker" Half
    --> wait_n_cycles (default_unstake_wait + 2)
    --> assert_failure
          (check_balance_field "staker" `Unstaked_finalizable Tez.zero)
    --> (Tag "finalize with finalize" --> finalize_unstake "staker"
        |+ Tag "finalize with stake" --> stake "staker" (Amount Tez.one_mutez)
        |+ Tag "finalize with unstake"
           --> unstake "staker" (Amount Tez.one_mutez))
    --> check_balance_field "staker" `Unstaked_finalizable Tez.zero

  (* Finalize does not go through when unstake does nothing *)
  (* Todo: there might be other cases... like changing delegates *)
  let scenario_not_finalize =
    no_tag --> stake "staker" Half --> next_cycle --> unstake "staker" All
    --> wait_n_cycles (default_unstake_wait + 2)
    --> assert_failure
          (check_balance_field "staker" `Unstaked_finalizable Tez.zero)
    --> snapshot_balances "not finalize" ["staker"]
    --> (Tag "no finalize with unstake if staked = 0"
        --> unstake "staker" (Amount Tez.one_mutez))
    --> assert_failure
          (check_balance_field "staker" `Unstaked_finalizable Tez.zero)
    --> check_snapshot_balances "not finalize"

  (* TODO: there's probably more... *)
  let scenario_forbidden_operations =
    let open Lwt_result_syntax in
    let fail_if_staker_is_self_delegate staker =
      exec (fun ((_, state) as input) ->
          if State.(is_self_delegate staker state) then
            failwith "_self_delegate_exit_"
          else return input)
    in
    no_tag
    (* Staking everything works for self delegates, but not for delegated accounts *)
    --> assert_failure
          (fail_if_staker_is_self_delegate "staker" --> stake "staker" All)
    (* stake is always forbidden when amount is zero *)
    --> assert_failure (stake "staker" Nothing)
    (* One cannot stake more that one has *)
    --> assert_failure (stake "staker" Max_tez)
    (* unstake is actually authorized for amount 0, but does nothing (doesn't even finalize if possible) *)
    --> unstake "staker" Nothing

  let full_balance_in_finalizable =
    add_account_with_funds "dummy" "staker" (Amount (Tez.of_mutez 10_000_000L))
    --> stake "staker" All_but_one --> next_cycle --> unstake "staker" All
    --> wait_n_cycles (default_unstake_wait + 2)
    (* At this point, almost all the balance (but one mutez) of the stake is in finalizable *)
    (* Staking is possible, but not transfer *)
    --> assert_failure
          (transfer "staker" "dummy" (Amount (Tez.of_mutez 10_000_000L)))
    --> stake "staker" (Amount (Tez.of_mutez 10_000_000L))
    (* After the stake, transfer is possible again because the funds were finalized *)
    --> transfer "staker" "dummy" (Amount (Tez.of_mutez 10_000_000L))

  (* Stress test: what happens if someone were to stake and unstake every cycle? *)
  let odd_behavior =
    let one_cycle =
      no_tag --> stake "staker" Half --> unstake "staker" Half --> next_cycle
    in
    loop 20 one_cycle

  let change_delegate =
    let constants = init_constants ~autostaking_enable:false () in
    let init_params =
      {
        limit_of_staking_over_baking = Q.one;
        edge_of_baking_over_staking = Q.one;
      }
    in
    begin_test ~activate_ai:true ~constants ["delegate1"; "delegate2"]
    --> set_delegate_params "delegate1" init_params
    --> set_delegate_params "delegate2" init_params
    --> add_account_with_funds
          "staker"
          "delegate1"
          (Amount (Tez.of_mutez 2_000_000_000_000L))
    --> set_delegate "staker" (Some "delegate1")
    --> wait_ai_activation --> next_cycle --> stake "staker" Half --> next_cycle
    --> set_delegate "staker" (Some "delegate2")
    --> next_cycle
    --> assert_failure (stake "staker" Half)
    --> wait_n_cycles (default_unstake_wait + 1)
    --> stake "staker" Half

  let unset_delegate =
    let constants = init_constants ~autostaking_enable:false () in
    let init_params =
      {
        limit_of_staking_over_baking = Q.one;
        edge_of_baking_over_staking = Q.one;
      }
    in
    begin_test ~activate_ai:true ~constants ["delegate"]
    --> set_delegate_params "delegate" init_params
    --> add_account_with_funds
          "staker"
          "delegate"
          (Amount (Tez.of_mutez 2_000_000_000_000L))
    --> add_account_with_funds
          "dummy"
          "delegate"
          (Amount (Tez.of_mutez 2_000_000L))
    --> set_delegate "staker" (Some "delegate")
    --> wait_ai_activation --> next_cycle --> stake "staker" Half
    --> unstake "staker" All --> next_cycle --> set_delegate "staker" None
    --> next_cycle
    --> transfer "staker" "dummy" All
    (* staker has an empty liquid balance, but still has unstaked frozen tokens,
       so it doesn't get deactivated *)
    --> wait_n_cycles (default_unstake_wait + 1)
    --> finalize_unstake "staker"

  let forbid_costaking =
    let default_constants =
      ("default protocol constants", init_constants ~autostaking_enable:false ())
    in
    let small_delegate_parameter_constants =
      ( "small delegate parameters delay",
        init_constants
          ~delegate_parameters_activation_delay:0
          ~autostaking_enable:false
          () )
    in
    let large_delegate_parameter_constants =
      ( "large delegate parameters delay",
        init_constants
          ~delegate_parameters_activation_delay:10
          ~autostaking_enable:false
          () )
    in
    let init_params =
      {
        limit_of_staking_over_baking = Q.one;
        edge_of_baking_over_staking = Q.one;
      }
    in
    let no_costake_params =
      {
        limit_of_staking_over_baking = Q.zero;
        edge_of_baking_over_staking = Q.one;
      }
    in
    let amount = Amount (Tez.of_mutez 1_000_000L) in
    (* init *)
    begin_test
      ~activate_ai:true
      ~constants_list:
        [
          default_constants;
          small_delegate_parameter_constants;
          large_delegate_parameter_constants;
        ]
      ["delegate"]
    --> set_delegate_params "delegate" init_params
    --> add_account_with_funds
          "staker"
          "delegate"
          (Amount (Tez.of_mutez 2_000_000_000_000L))
    --> set_delegate "staker" (Some "delegate")
    --> wait_cycle (`And (`AI_activation, `delegate_parameters_activation))
    --> next_cycle
    (* try stake in normal conditions *)
    --> stake "staker" amount
    (* Change delegate parameters to forbid staking *)
    --> set_delegate_params "delegate" no_costake_params
    (* The changes are not immediate *)
    --> stake "staker" amount
    (* The parameters change is applied exactly
       [delegate_parameters_activation_delay] after the request *)
    --> wait_delegate_parameters_activation
    (* Not yet... *)
    --> stake "staker" amount
    --> next_cycle
    (* External staking is now forbidden *)
    --> assert_failure (stake "staker" amount)
    (* Can still self-stake *)
    --> stake "delegate" amount
    (* Can still unstake *)
    --> unstake "staker" Half
    --> wait_n_cycles (default_unstake_wait + 1)
    --> finalize_unstake "staker"
    (* Can authorize stake again *)
    --> set_delegate_params "delegate" init_params
    --> wait_delegate_parameters_activation
    (* Not yet... *)
    --> assert_failure (stake "staker" amount)
    --> next_cycle
    (* Now possible *)
    --> stake "staker" amount

  let tests =
    tests_of_scenarios
    @@ [
         ("Test simple roundtrip", init_scenario () --> simple_roundtrip);
         ("Test double roundtrip", init_scenario () --> double_roundtrip);
         ("Test preserved balance", init_scenario () --> status_quo_rountrip);
         ("Test finalize", init_scenario () --> scenario_finalize);
         ("Test no finalize", init_scenario () --> scenario_not_finalize);
         ( "Test forbidden operations",
           init_scenario () --> scenario_forbidden_operations );
         ( "Test full balance in finalizable",
           init_scenario () --> full_balance_in_finalizable );
         ("Test stake unstake every cycle", init_scenario () --> odd_behavior);
         ("Test change delegate", change_delegate);
         ("Test unset delegate", unset_delegate);
         ("Test forbid costake", forbid_costaking);
         ("Test stake from unstake", shorter_roundtrip_for_baker);
       ]
end

module Rewards = struct
  let test_wait_with_rewards =
    let constants =
      init_constants
        ~reward_per_block:1_000_000_000L
        ~autostaking_enable:false
        ()
    in
    let set_edge pct =
      let params =
        {
          limit_of_staking_over_baking = Q.one;
          edge_of_baking_over_staking = Q.of_float pct;
        }
      in
      set_delegate_params "delegate" params
    in
    begin_test ~activate_ai:true ~constants ["delegate"; "faucet"]
    --> set_baker "faucet"
    --> (Tag "edge = 0" --> set_edge 0.
        |+ Tag "edge = 0.24" --> set_edge 0.24
        |+ Tag "edge = 0.11..." --> set_edge 0.1111111111
        |+ Tag "edge = 1" --> set_edge 1.)
    --> add_account_with_funds
          "staker1"
          "faucet"
          (Amount (Tez.of_mutez 2_000_000_000L))
    --> add_account_with_funds
          "staker2"
          "faucet"
          (Amount (Tez.of_mutez 2_000_000_000L))
    --> add_account_with_funds
          "staker3"
          "faucet"
          (Amount (Tez.of_mutez 2_000_000_000L))
    --> set_delegate "staker1" (Some "delegate")
    --> set_delegate "staker2" (Some "delegate")
    --> set_delegate "staker3" (Some "delegate")
    --> set_baker "delegate"
    --> (Tag "block step" --> wait_n_blocks 200
        |+ Tag "cycle step" --> wait_n_cycles 20
        |+ Tag "wait AI activation" --> next_block --> wait_ai_activation
           --> (Tag "no staker" --> Empty
               |+ Tag "one staker"
                  --> stake "staker1" (Amount (Tez.of_mutez 450_000_111L))
               |+ Tag "two stakers"
                  --> stake "staker1" (Amount (Tez.of_mutez 444_000_111L))
                  --> stake "staker2" (Amount (Tez.of_mutez 333_001_987L))
                  --> set_baker "delegate"
               |+ Tag "three stakers"
                  --> stake "staker1" (Amount (Tez.of_mutez 444_000_111L))
                  --> stake "staker2" (Amount (Tez.of_mutez 333_001_987L))
                  --> stake "staker3" (Amount (Tez.of_mutez 123_456_788L)))
           --> (Tag "block step" --> wait_n_blocks 100
               |+ Tag "cycle step" --> wait_n_cycles 10))
    --> Tag "staker 1 unstakes half..." --> unstake "staker1" Half
    --> (Tag "block step" --> wait_n_blocks 100
        |+ Tag "cycle step" --> wait_n_cycles 10)

  let test_ai_curve_activation_time =
    let constants =
      init_constants
        ~reward_per_block:1_000_000_000L
        ~deactivate_dynamic:true
        ~autostaking_enable:false
        ()
    in
    let pc = constants.consensus_rights_delay in
    begin_test ~activate_ai:true ~burn_rewards:true ~constants [""]
    --> next_block --> save_current_rate (* before AI rate *)
    --> wait_ai_activation
    (* Rate remains unchanged right after AI activation, we must wait [pc + 1] cycles *)
    --> check_rate_evolution Q.equal
    --> wait_n_cycles pc
    --> check_rate_evolution Q.equal
    --> next_cycle
    (* The new rate should be active now. With the chosen constants, it should be lower.
       We go from 1000tz per day to (at most) 5% of 4_000_000tz per year *)
    --> check_rate_evolution Q.gt

  let test_static =
    let constants =
      init_constants
        ~reward_per_block:1_000_000_000L
        ~deactivate_dynamic:true
        ~autostaking_enable:false
        ()
    in
    let rate_var_lag = constants.consensus_rights_delay in
    let init_params =
      {
        limit_of_staking_over_baking = Q.one;
        edge_of_baking_over_staking = Q.one;
      }
    in
    let delta = Amount (Tez.of_mutez 20_000_000_000L) in
    let cycle_stake =
      save_current_rate --> stake "delegate" delta --> next_cycle
      --> check_rate_evolution Q.gt
    in
    let cycle_unstake =
      save_current_rate --> unstake "delegate" delta --> next_cycle
      --> check_rate_evolution Q.lt
    in
    let cycle_stable =
      save_current_rate --> next_cycle --> check_rate_evolution Q.equal
    in
    begin_test ~activate_ai:true ~burn_rewards:true ~constants ["delegate"]
    --> set_delegate_params "delegate" init_params
    --> save_current_rate --> wait_ai_activation
    (* We stake about 50% of the total supply *)
    --> stake "delegate" (Amount (Tez.of_mutez 1_800_000_000_000L))
    --> stake "__bootstrap__" (Amount (Tez.of_mutez 1_800_000_000_000L))
    --> (Tag "increase stake, decrease rate" --> next_cycle
         --> loop rate_var_lag (stake "delegate" delta --> next_cycle)
         --> loop 10 cycle_stake
        |+ Tag "decrease stake, increase rate" --> next_cycle
           --> loop rate_var_lag (unstake "delegate" delta --> next_cycle)
           --> loop 10 cycle_unstake
        |+ Tag "stable stake, stable rate" --> next_cycle
           --> wait_n_cycles rate_var_lag --> loop 10 cycle_stable
        |+ Tag "test timing" --> wait_n_cycles rate_var_lag
           --> check_rate_evolution Q.equal
           --> next_cycle --> check_rate_evolution Q.gt --> save_current_rate
           --> (Tag "increase stake" --> stake "delegate" delta
                --> wait_n_cycles rate_var_lag
                --> check_rate_evolution Q.equal
                --> next_cycle --> check_rate_evolution Q.gt
               |+ Tag "decrease stake" --> unstake "delegate" delta
                  --> wait_n_cycles rate_var_lag
                  --> check_rate_evolution Q.equal
                  --> next_cycle --> check_rate_evolution Q.lt))

  let tests =
    tests_of_scenarios
    @@ [
         ("Test wait with rewards", test_wait_with_rewards);
         ("Test ai curve activation time", test_ai_curve_activation_time);
         (* ("Test static rate", test_static); *)
       ]
end

module Autostaking = struct
  let assert_balance_evolution ~loc ~for_accounts ~part ~name ~old_balance
      ~new_balance compare =
    let open Lwt_result_syntax in
    let old_b, new_b =
      match part with
      | `liquid ->
          ( Q.of_int64 @@ Tez.to_mutez old_balance.liquid_b,
            Q.of_int64 @@ Tez.to_mutez new_balance.liquid_b )
      | `staked -> (old_balance.staked_b, new_balance.staked_b)
      | `unstaked_frozen ->
          ( Q.of_int64 @@ Tez.to_mutez old_balance.unstaked_frozen_b,
            Q.of_int64 @@ Tez.to_mutez new_balance.unstaked_frozen_b )
      | `unstaked_finalizable ->
          ( Q.of_int64 @@ Tez.to_mutez old_balance.unstaked_finalizable_b,
            Q.of_int64 @@ Tez.to_mutez new_balance.unstaked_finalizable_b )
    in
    if List.mem ~equal:String.equal name for_accounts then
      if compare new_b old_b then return_unit
      else (
        Log.debug ~color:warning_color "Balances changes failed:@." ;
        Log.debug "@[<v 2>Old Balance@ %a@]@." balance_pp old_balance ;
        Log.debug "@[<v 2>New Balance@ %a@]@." balance_pp new_balance ;
        failwith "%s Unexpected stake evolution for %s" loc name)
    else raise Not_found

  let delegate = "delegate"

  and delegator1 = "delegator1"

  and delegator2 = "delegator2"

  let setup ~activate_ai =
    let constants = init_constants ~autostaking_enable:true () in
    begin_test ~activate_ai ~constants [delegate]
    --> add_account_with_funds
          delegator1
          "__bootstrap__"
          (Amount (Tez.of_mutez 2_000_000_000L))
    --> add_account_with_funds
          delegator2
          "__bootstrap__"
          (Amount (Tez.of_mutez 2_000_000_000L))
    --> next_cycle
    --> (if activate_ai then wait_ai_activation else next_cycle)
    --> snapshot_balances "before delegation" [delegate]
    --> set_delegate delegator1 (Some delegate)
    --> check_snapshot_balances "before delegation"
    --> next_cycle

  let test_autostaking =
    Tag "No Ai" --> setup ~activate_ai:false
    --> check_snapshot_balances
          ~f:
            (assert_balance_evolution
               ~loc:__LOC__
               ~for_accounts:[delegate]
               ~part:`staked
               Q.gt)
          "before delegation"
    --> snapshot_balances "before second delegation" [delegate]
    --> (Tag "increase delegation"
         --> set_delegate delegator2 (Some delegate)
         --> next_cycle
         --> check_snapshot_balances
               ~f:
                 (assert_balance_evolution
                    ~loc:__LOC__
                    ~for_accounts:[delegate]
                    ~part:`staked
                    Q.gt)
               "before second delegation"
        |+ Tag "constant delegation"
           --> snapshot_balances "after stake change" [delegate]
           --> wait_n_cycles 8
           --> check_snapshot_balances "after stake change"
        |+ Tag "decrease delegation"
           --> set_delegate delegator1 None
           --> next_cycle
           --> check_snapshot_balances
                 ~f:
                   (assert_balance_evolution
                      ~loc:__LOC__
                      ~for_accounts:[delegate]
                      ~part:`staked
                      Q.lt)
                 "before second delegation"
           --> check_snapshot_balances
                 ~f:
                   (assert_balance_evolution
                      ~loc:__LOC__
                      ~for_accounts:[delegate]
                      ~part:`unstaked_frozen
                      Q.gt)
                 "before second delegation"
           --> snapshot_balances "after unstake" [delegate]
           --> next_cycle
           --> check_snapshot_balances "after unstake"
           --> wait_n_cycles 4
           --> check_snapshot_balances
                 ~f:
                   (assert_balance_evolution
                      ~loc:__LOC__
                      ~for_accounts:[delegate]
                      ~part:`unstaked_frozen
                      Q.lt)
                 "after unstake"
           (* finalizable are auto-finalize immediately  *)
           --> check_snapshot_balances
                 ~f:
                   (assert_balance_evolution
                      ~loc:__LOC__
                      ~for_accounts:[delegate]
                      ~part:`liquid
                      Q.lt)
                 "before finalisation")
    |+ Tag "Yes AI" --> setup ~activate_ai:true
       --> check_snapshot_balances "before delegation"

  let test_overdelegation =
    (* This test assumes that all delegate accounts created in [begin_test]
       begin with 4M tz, with 5% staked *)
    let constants = init_constants ~autostaking_enable:true () in
    begin_test
      ~activate_ai:false
      ~constants
      ["delegate"; "faucet1"; "faucet2"; "faucet3"]
    --> add_account_with_funds
          "delegator_to_fund"
          "delegate"
          (Amount (Tez.of_mutez 3_600_000_000_000L))
    (* Delegate has 200k staked and 200k liquid *)
    --> set_delegate "delegator_to_fund" (Some "delegate")
    (* Delegate stake will not change at the end of cycle: same stake *)
    --> next_cycle
    --> check_balance_field "delegate" `Staked (Tez.of_mutez 200_000_000_000L)
    --> transfer
          "faucet1"
          "delegator_to_fund"
          (Amount (Tez.of_mutez 3_600_000_000_000L))
    (* Delegate is not overdelegated, but will need to freeze 180k *)
    --> next_cycle
    --> check_balance_field "delegate" `Staked (Tez.of_mutez 380_000_000_000L)
    --> transfer
          "faucet2"
          "delegator_to_fund"
          (Amount (Tez.of_mutez 3_600_000_000_000L))
    (* Delegate is now overdelegated, it will freeze 100% *)
    --> next_cycle
    --> check_balance_field "delegate" `Staked (Tez.of_mutez 400_000_000_000L)
    --> transfer
          "faucet3"
          "delegator_to_fund"
          (Amount (Tez.of_mutez 3_600_000_000_000L))
    (* Delegate is overmegadelegated *)
    --> next_cycle
    --> check_balance_field "delegate" `Staked (Tez.of_mutez 400_000_000_000L)

  let tests =
    tests_of_scenarios
      [
        ("Test auto-staking", test_autostaking);
        ("Test auto-staking with overdelegation", test_overdelegation);
      ]
end

module Slashing = struct
  let test_simple_slash =
    let constants = init_constants ~autostaking_enable:false () in
    let any_slash delegate =
      Tag "double baking" --> double_bake delegate
      |+ Tag "double attesting"
         --> double_attest ~other_bakers:("bootstrap2", "bootstrap3") delegate
      |+ Tag "double preattesting"
         --> double_preattest
               ~other_bakers:("bootstrap2", "bootstrap3")
               delegate
    in
    begin_test
      ~activate_ai:true
      ~ns_enable_fork:true
      ~constants
      ["delegate"; "bootstrap1"; "bootstrap2"; "bootstrap3"]
    --> (Tag "No AI" --> next_cycle
        |+ Tag "Yes AI" --> next_block --> wait_ai_activation)
    --> any_slash "delegate"
    --> snapshot_balances "before slash" ["delegate"]
    --> ((Tag "denounce same cycle"
          --> make_denunciations ()
              (* delegate can be forbidden in this case, so we set another baker *)
          --> exclude_bakers ["delegate"]
         |+ Tag "denounce next cycle" --> next_cycle --> make_denunciations ()
            (* delegate can be forbidden in this case, so we set another baker *)
            --> exclude_bakers ["delegate"])
         --> (Empty
             |+ Tag "another slash" --> any_slash "bootstrap1"
                --> make_denunciations ()
                (* bootstrap1 can be forbidden in this case, so we set another baker *)
                --> exclude_bakers ["delegate"; "bootstrap1"])
         --> check_snapshot_balances "before slash"
         --> exec_unit (check_pending_slashings ~loc:__LOC__)
         --> next_cycle
         --> assert_failure
               (exec_unit (fun (_block, state) ->
                    if state.State.constants.adaptive_issuance.ns_enable then
                      failwith "ns_enable = true: slash not applied yet"
                    else return_unit)
               --> check_snapshot_balances "before slash")
         --> exec_unit (check_pending_slashings ~loc:__LOC__)
         --> next_cycle
        |+ Tag "denounce too late" --> next_cycle --> next_cycle
           --> assert_failure
                 ~expected_error:(fun (_block, state) ->
                   let ds = state.State.double_signings in
                   let ds = match ds with [a] -> a | _ -> assert false in
                   let level =
                     Protocol.Alpha_context.Raw_level.Internal_for_tests
                     .from_repr
                       ds.misbehaviour.level
                   in
                   let last_cycle =
                     Cycle.add
                       (Block.current_cycle_of_level
                          ~blocks_per_cycle:
                            state.State.constants.blocks_per_cycle
                          ~current_level:
                            (Protocol.Raw_level_repr.to_int32
                               ds.misbehaviour.level))
                       Protocol.Constants_repr.max_slashing_period
                   in
                   let (kind : Protocol.Alpha_context.Misbehaviour.kind) =
                     (* This conversion would not be needed if
                        Misbehaviour_repr.kind were moved to a
                        separate file that doesn't have under/over
                        Alpha_context versions. *)
                     match ds.misbehaviour.kind with
                     | Double_baking -> Double_baking
                     | Double_attesting -> Double_attesting
                     | Double_preattesting -> Double_preattesting
                   in
                   [
                     Environment.Ecoproto_error
                       (Protocol.Validate_errors.Anonymous.Outdated_denunciation
                          {kind; level; last_cycle});
                   ])
                 (make_denunciations ())
           --> check_snapshot_balances "before slash")

  let check_is_forbidden baker = assert_failure (next_block_with_baker baker)

  let check_is_not_forbidden baker =
    let open Lwt_result_syntax in
    exec (fun ((block, state) as input) ->
        let baker = State.find_account baker state in
        let*! _ = Block.bake ~policy:(By_account baker.pkh) block in
        return input)

  let test_delegate_forbidden =
    let constants =
      init_constants ~blocks_per_cycle:30l ~autostaking_enable:false ()
    in
    begin_test
      ~activate_ai:false
      ~ns_enable_fork:true
      ~constants
      ["delegate"; "bootstrap1"; "bootstrap2"]
    --> set_baker "bootstrap1"
    --> (Tag "Many double bakes"
         --> loop_action 14 (double_bake_ "delegate")
         --> (Tag "14 double bakes are not enough to forbid a delegate"
              (*  7*14 = 98 *)
              --> make_denunciations ()
              --> check_is_not_forbidden "delegate"
             |+ Tag "15 double bakes is one too many"
                (*  7*15 = 105 > 100 *)
                --> double_bake "delegate"
                --> make_denunciations ()
                --> check_is_forbidden "delegate")
        |+ Tag "Is forbidden after first denunciation"
           --> double_attest "delegate"
           --> (Tag "very early first denounce" --> make_denunciations ()
               --> (Tag "in same cycle" --> Empty
                   |+ Tag "next cycle" --> next_cycle)
               --> check_is_forbidden "delegate")
        |+ Tag "Is unforbidden after 7 cycles" --> double_attest "delegate"
           --> make_denunciations ()
           --> exclude_bakers ["delegate"]
           --> check_is_forbidden "delegate"
           --> stake "delegate" Half
           --> check_is_not_forbidden "delegate"
        |+ Tag
             "Two double attestations, in consecutive cycles, denounce out of \
              order" --> double_attest "delegate" --> next_cycle
           --> double_attest "delegate"
           --> make_denunciations
                 ~filter:(fun {denounced; misbehaviour = {level; _}; _} ->
                   (not denounced)
                   && Protocol.Raw_level_repr.to_int32 level > 10l)
                 ()
           --> make_denunciations
                 ~filter:(fun {denounced; misbehaviour = {level; _}; _} ->
                   (not denounced)
                   && Protocol.Raw_level_repr.to_int32 level <= 10l)
                 ()
           --> check_is_forbidden "delegate")

  let test_slash_unstake =
    let constants = init_constants ~autostaking_enable:false () in
    begin_test
      ~activate_ai:false
      ~ns_enable_fork:true
      ~constants
      ["delegate"; "bootstrap1"; "bootstrap2"]
    --> set_baker "bootstrap1" --> next_cycle --> unstake "delegate" Half
    --> next_cycle --> double_bake "delegate" --> make_denunciations ()
    --> (Empty |+ Tag "unstake twice" --> unstake "delegate" Half)
    --> wait_n_cycles 5
    --> finalize_unstake "delegate"

  let test_slash_monotonous_stake =
    let scenario ~offending_op ~op ~early_d =
      let constants =
        init_constants ~blocks_per_cycle:16l ~autostaking_enable:false ()
      in
      begin_test
        ~activate_ai:false
        ~ns_enable_fork:true
        ~constants
        ["delegate"; "bootstrap1"]
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
                --> scenario ~offending_op:double_attest ~op:stake ~early_d:true
             )
        |+ Tag "denounce late"
           --> (Tag "Double Bake"
                --> scenario ~offending_op:double_bake ~op:stake ~early_d:false
               |+ Tag "Double attest"
                  --> scenario
                        ~offending_op:double_attest
                        ~op:stake
                        ~early_d:false)
           --> make_denunciations ())
    |+ Tag "slashes with decreasing stake"
       --> (Tag "Double Bake"
            --> scenario ~offending_op:double_bake ~op:unstake ~early_d:true
           |+ Tag "Double attest"
              --> scenario ~offending_op:double_attest ~op:unstake ~early_d:true
           )
    |+ Tag "denounce late"
       --> (Tag "Double Bake"
            --> scenario ~offending_op:double_bake ~op:unstake ~early_d:false
           |+ Tag "Double attest"
              --> scenario
                    ~offending_op:double_attest
                    ~op:unstake
                    ~early_d:false)
       --> make_denunciations ()

  let test_slash_timing =
    let constants =
      init_constants ~blocks_per_cycle:8l ~autostaking_enable:false ()
    in
    begin_test ~activate_ai:false ~ns_enable_fork:true ~constants ["delegate"]
    --> next_cycle
    --> (Tag "stake" --> stake "delegate" Half
        |+ Tag "unstake" --> unstake "delegate" Half)
    --> (Tag "with a first slash" --> double_bake "delegate"
         --> make_denunciations ()
        |+ Tag "without another slash" --> Empty)
    --> List.fold_left
          (fun acc i ->
            acc |+ Tag (string_of_int i ^ " cycles lag") --> wait_n_cycles i)
          Empty
          [3; 4; 5; 6]
    --> double_bake "delegate" --> make_denunciations () --> next_cycle

  let init_scenario_with_delegators delegate_name faucet_name delegators_list =
    let constants = init_constants ~autostaking_enable:false () in
    let rec init_delegators = function
      | [] -> Empty
      | (delegator, amount) :: t ->
          add_account_with_funds
            delegator
            faucet_name
            (Amount (Tez.of_mutez amount))
          --> set_delegate delegator (Some delegate_name)
          --> init_delegators t
    in
    let init_params =
      {
        limit_of_staking_over_baking = Q.one;
        edge_of_baking_over_staking = Q.one;
      }
    in
    begin_test
      ~activate_ai:true
      ~ns_enable_fork:true
      ~constants
      [delegate_name; faucet_name]
    --> set_baker faucet_name
    --> set_delegate_params "delegate" init_params
    --> init_delegators delegators_list
    --> next_block --> wait_ai_activation

  let test_many_slashes =
    let rec stake_unstake_for = function
      | [] -> Empty
      | staker :: t ->
          stake staker Half --> unstake staker Half --> stake_unstake_for t
    in
    let slash delegate = double_bake delegate --> make_denunciations () in
    Tag "double bake"
    --> (Tag "solo delegate"
        --> init_scenario_with_delegators
              "delegate"
              "faucet"
              [("delegator", 1_234_567_891L)]
        --> loop
              10
              (stake_unstake_for ["delegate"]
              --> slash "delegate" --> next_cycle))
  (* |+ Tag "delegate with one staker"
        --> init_scenario_with_delegators
              "delegate"
              "faucet"
              [("staker", 1_234_356_891L)]
        --> loop
              10
              (stake_unstake_for ["delegate"; "staker"]
              --> slash "delegate" --> next_cycle)
     |+ Tag "delegate with three stakers"
        --> init_scenario_with_delegators
              "delegate"
              "faucet"
              [
                ("staker1", 1_234_356_891L);
                ("staker2", 1_234_356_890L);
                ("staker3", 1_723_333_111L);
              ]
        --> loop
              10
              (stake_unstake_for
                 ["delegate"; "staker1"; "staker2"; "staker3"]
              --> slash "delegate" --> next_cycle))*)

  let test_no_shortcut_for_cheaters =
    let constants = init_constants ~autostaking_enable:false () in
    let amount = Amount (Tez.of_mutez 333_000_000_000L) in
    let consensus_rights_delay = constants.consensus_rights_delay in
    begin_test
      ~activate_ai:true
      ~ns_enable_fork:false
      ~constants
      ["delegate"; "bootstrap1"]
    --> next_block --> wait_ai_activation
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
         --> assert_failure (check_snapshot_balances "init")
        |+ Tag "wait enough cycles (consensus_rights_delay + 1)"
           --> wait_n_cycles (consensus_rights_delay + 1)
           --> stake "delegate" amount
           --> check_snapshot_balances "init")

  let test_slash_correct_amount_after_stake_from_unstake =
    let constants = init_constants ~autostaking_enable:false () in
    let amount_to_unstake = Amount (Tez.of_mutez 200_000_000_000L) in
    let amount_to_restake = Amount (Tez.of_mutez 100_000_000_000L) in
    let amount_expected_in_unstake_after_slash = Tez.of_mutez 50_000_000_000L in
    let consensus_rights_delay = constants.consensus_rights_delay in
    begin_test
      ~activate_ai:true
      ~ns_enable_fork:false
      ~constants
      ["delegate"; "bootstrap1"]
    --> next_block --> wait_ai_activation
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
    let constants = init_constants ~autostaking_enable:false () in
    (Tag "Yes AI"
     --> begin_test
           ~activate_ai:true
           ~ns_enable_fork:false
           ~constants
           ["delegate"; "baker"]
     --> next_block --> wait_ai_activation
    |+ Tag "No AI"
       --> begin_test
             ~activate_ai:false
             ~ns_enable_fork:false
             ~constants
             ["delegate"; "baker"])
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
    --> wait_n_cycles (constants.consensus_rights_delay + 1)

  let test_slash_rounding =
    let constants = init_constants ~autostaking_enable:false () in
    begin_test
      ~activate_ai:true
      ~ns_enable_fork:true
      ~constants
      ["delegate"; "baker"]
    --> set_baker "baker" --> next_block --> wait_ai_activation
    --> unstake "delegate" (Amount (Tez.of_mutez 2L))
    --> next_cycle --> double_bake "delegate" --> double_bake "delegate"
    --> make_denunciations () --> wait_n_cycles 7
    --> finalize_unstake "delegate"

  (* TODO #6645: reactivate tests *)
  let tests =
    tests_of_scenarios
    @@ [
         ("Test simple slashing", test_simple_slash);
         ("Test slashed is forbidden", test_delegate_forbidden);
         ("Test slash with unstake", test_slash_unstake);
         (* TODO: make sure this test passes with blocks_per_cycle:8l
            https://gitlab.com/tezos/tezos/-/issues/6904 *)
         ("Test slashes with simple varying stake", test_slash_monotonous_stake);
         (* This test has been deactivated following the changes of the
            forbidding mechanism that now forbids delegates right after the
            first denunciation, it should be fixed and reactivated
            https://gitlab.com/tezos/tezos/-/issues/6904 *)
         (* ( "Test multiple slashes with multiple stakes/unstakes", *)
         (*   test_many_slashes ); *)
         (* ("Test slash timing", test_slash_timing); *)
         ( "Test stake from unstake deactivated when slashed",
           test_no_shortcut_for_cheaters );
         ( "Test stake from unstake reduce initial amount",
           test_slash_correct_amount_after_stake_from_unstake );
         ("Test unstake 1 mutez then slash", test_mini_slash);
         ("Test slash rounding", test_slash_rounding);
       ]
end

let tests =
  let open Lwt_result_syntax in
  (tests_of_scenarios
  @@ [
       ("Test expected error in assert failure", test_expected_error);
       ("Test init", init_scenario () --> Action (fun _ -> return_unit));
     ])
  @ Roundtrip.tests @ Rewards.tests @ Autostaking.tests @ Slashing.tests

let () =
  Alcotest_lwt.run
    ~__FILE__
    Protocol.name
    [("adaptive issuance roundtrip", tests)]
  |> Lwt_main.run
