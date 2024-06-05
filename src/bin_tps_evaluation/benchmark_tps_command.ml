(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

open Constants

(** The level at which the benchmark starts. We wait till level 3 because we
   need to inject transactions that target already decided blocks. In
   Tenderbake, a block is decided when there are 2 blocks on top of it. We
   cannot target genesis (level 0) because it is not yet in the right
   protocol, thus we wait till level 1 is decided, i.e. we want level 3. *)
let benchmark_starting_level = 3

(** Look up the minimal block delay given [protocol] and [protocol_constants]. *)
let get_minimal_block_delay protocol protocol_constants =
  let json =
    JSON.parse_file
      (Protocol.parameter_file ~constants:protocol_constants protocol)
  in
  int_of_float JSON.(json |-> "minimal_block_delay" |> as_float)

(** Set max prechecked manager operations count. *)
let set_max_prechecked_manager_operations n client =
  let path = ["chains"; "main"; "mempool"; "filter"] in
  let data : RPC_core.data =
    Data (`O [("max_prechecked_manager_operations", `Float (Float.of_int n))])
  in
  let* _ = Client.rpc ~data POST path client in
  Lwt.return_unit

(** Get a list of hashes of the given number of most recent blocks. *)
let get_blocks blocks_total client =
  let open Lwt_syntax in
  let path = ["chains"; "main"; "blocks"] in
  let query_string = [("length", Int.to_string blocks_total)] in
  let+ json = Client.rpc ~query_string GET path client in
  List.map JSON.as_string (JSON.as_list (JSON.geti 0 json))

(** Get the total number of injected transactions. *)
let get_total_injected_transactions () =
  let tmp_dir = Filename.get_temp_dir_name () in

  (* Choose the most recently created file. *)
  let operations_file =
    Sys.readdir tmp_dir |> Array.to_list
    |> List.filter_map (fun file ->
           if
             String.has_prefix
               ~prefix:"client-stresstest-injected_operations"
               file
             && Filename.extension file = ".json"
           then
             let f = Filename.concat tmp_dir file in
             Some (Unix.stat f, f)
           else None)
    |> List.sort (fun (a1, _) (b1, _) -> Unix.(compare b1.st_ctime a1.st_ctime))
    |> List.map snd |> List.hd
  in

  match operations_file with
  | None ->
      Format.kasprintf
        Stdlib.failwith
        "The injected operations json file was not found. It should have been \
         generated by the octez-client stresstest command@."
  | Some f ->
      let block_transactions = JSON.as_list (JSON.parse_file f) in

      List.fold_left
        (fun a b ->
          match
            List.assoc ~equal:String.equal "operation_hashes" (JSON.as_object b)
          with
          | Some v -> List.length (JSON.as_list v) + a
          | None -> a)
        0
        block_transactions

(** Get the number of applied transactions in the block with the given
    hash. *)
let get_total_applied_transactions_for_block block client =
  (*
    N.B. Grouping of the operations by validation passes:
    - 0: consensus
    - 1: governance (voting)
    - 2: anonymous (denounciations)
    - 3: manager operations

    We are interested in 3, so we select that.
   *)
  let open Lwt_syntax in
  let path = ["chains"; "main"; "blocks"; block; "operation_hashes"; "3"] in
  let+ json = Client.rpc GET path client in
  List.length (JSON.as_list json)

(** The entry point of the benchmark. *)
let run_benchmark ~lift_protocol_limits ~provided_tps_of_injection ~blocks_total
    ~average_block_path () =
  let open Lwt_syntax in
  (* We run the gas tps estimation in a separate network first in order to
     figure out just how many accounts we need for the benchmark. *)
  let* gas_tps_estimation_results =
    Gas_tps_command.estimate_gas_tps ~average_block_path ()
  in
  Log.info "Tezos TPS benchmark" ;
  Log.info "Protocol: %s" (Protocol.name protocol) ;
  Log.info "Blocks to bake: %d" blocks_total ;
  let* parameter_file =
    Protocol.write_parameter_file
      ~base:(Either.right (protocol, Some protocol_constants))
      (if lift_protocol_limits then
         [
           (["hard_gas_limit_per_block"], `String_of_int 2147483647);
           (["hard_gas_limit_per_operation"], `String_of_int 2147483647);
         ]
       else [])
  in
  (* It is important to use a good estimate of max possible TPS that is
     theoretically achievable. If we send operations with lower TPS than
     this we risk obtaining a sub-estimated value for TPS. If we use a
     higher TPS than the maximal possible we risk to saturate the mempool
     and again obtain a less-than-perfect estimation in the end. *)
  let target_tps_of_injection =
    match provided_tps_of_injection with
    | Some tps_value -> tps_value
    | None ->
        if lift_protocol_limits then Constants.lifted_limits_tps
        else
          Gas.deduce_tps
            ~protocol
            ~protocol_constants
            ~average_transaction_cost:
              gas_tps_estimation_results.average_transaction_cost
            ()
  in
  let round0_duration = get_minimal_block_delay protocol protocol_constants in
  (* We need as many accounts as operations in a block. *)
  let total_bootstraps = target_tps_of_injection * round0_duration in
  let additional_bootstrap_account_count =
    total_bootstraps - Constants.default_bootstraps_count
  in
  Log.info "Accounts to use: %d" total_bootstraps ;
  Log.info "Spinning up the network..." ;
  let regular_transaction_fee, regular_transaction_gas_limit =
    Gas.deduce_fee_and_gas_limit
      gas_tps_estimation_results.transaction_costs.regular
  in
  let smart_contract_parameters =
    Gas.calculate_smart_contract_parameters
      gas_tps_estimation_results.average_block
      gas_tps_estimation_results.transaction_costs
  in
  let max_single_transaction_fee =
    List.fold_left
      max
      (Tez.to_mutez regular_transaction_fee)
      (List.map
         (fun (_, x) -> Tez.to_mutez x.Client.invocation_fee)
         smart_contract_parameters)
  in
  (* We want to give the extra bootstraps as little as possible, just enough
     to do their job. *)
  let default_accounts_balance =
    (max_single_transaction_fee + Constants.gas_safety_margin) * blocks_total
  in
  let* node, client =
    Client.init_with_protocol
      ~nodes_args:Node.[Connections 0; Synchronisation_threshold 0]
      ~parameter_file
      ~timestamp:Now
      ~additional_bootstrap_account_count
      ~default_accounts_balance
      `Client
      ~protocol
      ()
  in
  (* Unknown smart contracts will fail the benchmark anyway, but later and less
     gracefully. Here we try to do it the nice way. *)
  let* () =
    Average_block.check_for_unknown_smart_contracts
      gas_tps_estimation_results.average_block
  in
  (* Use only the default bootstraps as delegates. The baker doesn't like
     to have tens of thousands of delegates passed to it. Luckily, if we
     give very little Tez to the extra bootstraps, the default bootstraps will
     dominate in terms of stake. *)
  let delegates = make_delegates Constants.default_bootstraps_count in
  let _baker = Baker.init ~protocol ~delegates node client in
  Log.info "Originating smart contracts" ;
  let* () =
    Client.stresstest_originate_smart_contracts originating_bootstrap client
  in
  let* () = set_max_prechecked_manager_operations total_bootstraps client in
  Log.info "Waiting to reach the next level" ;
  let* _ = Node.wait_for_level node (benchmark_starting_level - 1) in
  Log.info "Using the parameter file: %s" parameter_file ;
  Log.info "Waiting to reach level %d" benchmark_starting_level ;
  let* _ = Node.wait_for_level node benchmark_starting_level in
  let bench_start = Unix.gettimeofday () in
  Log.info "The benchmark has been started" ;
  let client_stresstest_process =
    Client.spawn_stresstest
      ~fee:regular_transaction_fee
      ~gas_limit:regular_transaction_gas_limit
      ~tps:target_tps_of_injection
        (* The stresstest command allows a small probability of creating
           new accounts along the way. We do not want that, so we set it to
           0. *)
      ~fresh_probability:0.0
      ~smart_contract_parameters
      ~source_aliases:(make_delegates Constants.default_bootstraps_count)
        (* It is essential not to pass all accounts via aliases because every
           alias has to be normalized and that's an extra call of the client
           per account. This does not scale well. On the other hand, if we
           pass Account.key list directly, the stresstest command can use it
           right away. *)
      ~source_accounts:(Client.additional_bootstraps client)
      client
  in
  let* _level =
    Node.wait_for_level node (benchmark_starting_level + blocks_total)
  in
  Process.terminate client_stresstest_process ;
  let* _ = Process.wait client_stresstest_process in
  let bench_end = Unix.gettimeofday () in
  let bench_duration = bench_end -. bench_start in
  Log.info "Produced %d block(s) in %.2f seconds" blocks_total bench_duration ;
  let* produced_block_hashes = get_blocks blocks_total client in
  let total_injected_transactions = get_total_injected_transactions () in
  let total_applied_transactions = ref 0 in
  let handle_one_block block_hash =
    let+ applied_transactions =
      get_total_applied_transactions_for_block block_hash client
    in
    total_applied_transactions :=
      !total_applied_transactions + applied_transactions ;
    Log.info "%s -> %d" block_hash applied_transactions
  in
  let* () = List.iter_s handle_one_block (List.rev produced_block_hashes) in
  Log.info "Total applied transactions: %d" !total_applied_transactions ;
  Log.info "Total injected transactions: %d" total_injected_transactions ;
  let empirical_tps =
    Float.of_int !total_applied_transactions /. bench_duration
  in
  let de_facto_tps_of_injection =
    Float.of_int total_injected_transactions /. bench_duration
  in
  Log.info "TPS of injection (target): %d" target_tps_of_injection ;
  Log.info "TPS of injection (de facto): %.2f" de_facto_tps_of_injection ;
  Log.info "Empirical TPS: %.2f" empirical_tps ;
  let* () = Node.kill node in
  return (de_facto_tps_of_injection, empirical_tps)

let regression_handling defacto_tps_of_injection empirical_tps
    lifted_protocol_limits ~previous_count =
  let lifted_protocol_limits_tag = string_of_bool lifted_protocol_limits in
  let save_and_check =
    Long_test.measure_and_check_regression
      ~previous_count
      ~minimum_previous_count:previous_count
      ~stddev:false
      ~repeat:1
      ~tags:[(Dashboard.Tag.lifted_protocol_limits, lifted_protocol_limits_tag)]
  in
  let* () =
    save_and_check Dashboard.Measurement.defacto_tps_of_injection @@ fun () ->
    defacto_tps_of_injection
  in
  save_and_check Dashboard.Measurement.empirical_tps @@ fun () -> empirical_tps

let register () =
  Long_test.register
    ~__FILE__
    ~title:Dashboard.Test.benchmark_tps
    ~team:Tag.layer1
    ~tags:[Dashboard.Test.benchmark_tps]
    ~timeout:(Long_test.Minutes 60)
    ~executors:Long_test.[x86_executor1]
    (fun () ->
      let lift_protocol_limits =
        Cli.get_bool ~default:false "lift-protocol-limits"
      in
      let provided_tps_of_injection =
        Cli.get
          ~default:None
          (fun s ->
            match int_of_string_opt s with
            | None -> None
            | Some x -> Some (Some x))
          "provided_tps_of_injection"
      in
      let blocks_total = Cli.get_int ~default:10 "blocks-total" in
      let average_block_path =
        Cli.get ~default:None (fun s -> Some (Some s)) "average-block"
      in
      let previous_count =
        Cli.get_int ~default:10 "regression-previous-sample-count"
      in
      let* defacto_tps_of_injection, empirical_tps =
        run_benchmark
          ~lift_protocol_limits
          ~provided_tps_of_injection
          ~blocks_total
          ~average_block_path
          ()
      in
      regression_handling
        defacto_tps_of_injection
        empirical_tps
        lift_protocol_limits
        ~previous_count)
