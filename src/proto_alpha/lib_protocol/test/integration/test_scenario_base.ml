(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2024 Nomadic Labs, <contact@nomadic-labs.com>               *)
(*                                                                           *)
(*****************************************************************************)

(** Testing
    -------
    Component:    Scenario, State
    Invocation:   dune exec src/proto_alpha/lib_protocol/test/integration/main.exe \
                   -- --file test_scenario_base.ml
    Subject:      Test basic functionality of the scenario framework.
*)

open Adaptive_issuance_helpers
open State_account
open Tez_helpers.Ez_tez
open Scenario

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

(** Initializes the constants for testing, with well chosen default values.
    Recommended over [start] or [start_with] *)
let init_constants ?(default = Test) ?(reward_per_block = 0L)
    ?(deactivate_dynamic = false) ?blocks_per_cycle
    ?delegate_parameters_activation_delay ~autostaking_enable () =
  let open Scenario_constants in
  let base_total_issued_per_minute = Tez.of_mutez reward_per_block in
  start ~constants:default
  --> (* default for tests: 12 *)
  set_opt S.blocks_per_cycle blocks_per_cycle
  --> set_opt
        S.delegate_parameters_activation_delay
        delegate_parameters_activation_delay
  --> set
        S.issuance_weights
        {
          base_total_issued_per_minute;
          baking_reward_fixed_portion_weight = 1;
          baking_reward_bonus_weight = 0;
          attesting_reward_weight = 0;
          seed_nonce_revelation_tip_weight = 0;
          vdf_revelation_tip_weight = 0;
        }
  --> set S.liquidity_baking_subsidy Tez.zero
  --> set S.minimal_block_delay Protocol.Alpha_context.Period.one_minute
  --> set S.cost_per_byte Tez.zero
  --> set S.consensus_threshold 0
  --> (if deactivate_dynamic then
       set
         S.Adaptive_issuance.Adaptive_rewards_params.max_bonus
         (Protocol.Issuance_bonus_repr.max_bonus_parameter_of_Q_exn Q.zero)
      else Empty)
  --> set S.Adaptive_issuance.ns_enable false
  --> set S.Adaptive_issuance.autostaking_enable autostaking_enable

(** Initialization of scenarios with 3 cases:
     - AI activated, staker = delegate
     - AI activated, staker != delegate
     - AI not activated (and staker = delegate)
    Any scenario that begins with this will be triplicated.
 *)
let init_scenario ?(force_ai = true) ?reward_per_block () =
  let init_params =
    {limit_of_staking_over_baking = Q.one; edge_of_baking_over_staking = Q.one}
  in
  let begin_test ~activate_ai ~self_stake =
    let name = if self_stake then "staker" else "delegate" in
    init_constants ?reward_per_block ~autostaking_enable:false ()
    --> Scenario_begin.activate_ai activate_ai
    --> begin_test [name]
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

let tests =
  tests_of_scenarios
  @@ [
       ("Test expected error in assert failure", test_expected_error);
       ("Test init", init_scenario () --> Action (fun _ -> return_unit));
     ]

let () = register_tests ~__FILE__ ~tags:["protocol"; "scenario"; "base"] tests
