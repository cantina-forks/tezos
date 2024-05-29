(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2024 Trilitech <contact@trili.tech>                         *)
(* Copyright (c) 2024 Functori <contact@functori.com>                        *)
(*                                                                           *)
(*****************************************************************************)

(* Testing
   -------
   Component:    Smart Optimistic Rollups: Etherlink Sequencer
   Requirement:  make -f etherlink.mk build
                 npm install eth-cli
                 make octez-dsn-node
   Invocation:   dune exec etherlink/tezt/tests/main.exe -- --file evm_sequencer.ml
*)

open Sc_rollup_helpers
open Rpc.Syntax
open Contract_path

module Sequencer_rpc = struct
  let get_blueprint sequencer number =
    Runnable.run
    @@ Curl.get
         ~args:["--fail"]
         (Evm_node.endpoint sequencer
         ^ "/evm/blueprint/" ^ Int64.to_string number)

  let get_smart_rollup_address sequencer =
    let* res =
      Runnable.run
      @@ Curl.get
           ~args:["--fail"]
           (Evm_node.endpoint sequencer ^ "/evm/smart_rollup_address")
    in
    return (JSON.as_string res)
end

let uses _protocol =
  [
    Constant.octez_smart_rollup_node;
    Constant.octez_evm_node;
    Constant.smart_rollup_installer;
    Constant.WASM.evm_kernel;
  ]

open Helpers

let check_kernel_version ~evm_node ~equal expected =
  let*@ kernel_version = Rpc.tez_kernelVersion evm_node in
  if equal then
    Check.((kernel_version = expected) string)
      ~error_msg:"Expected kernelVersion to be %R, got %L"
  else
    Check.((kernel_version <> expected) string)
      ~error_msg:"Expected kernelVersion to be different than %R" ;
  return kernel_version

let base_fee_for_hardcoded_tx = Wei.to_wei_z @@ Z.of_int 21000

let arb_da_fee_for_delayed_inbox = Wei.of_eth_int 10_000
(* da fee doesn't apply to delayed inbox, set it arbitrarily high
   to prove this *)

type l1_contracts = {
  delayed_transaction_bridge : string;
  exchanger : string;
  bridge : string;
  admin : string;
  sequencer_governance : string;
}

type sequencer_setup = {
  node : Node.t;
  client : Client.t;
  sc_rollup_address : string;
  sc_rollup_node : Sc_rollup_node.t;
  observer : Evm_node.t;
  sequencer : Evm_node.t;
  proxy : Evm_node.t;
  l1_contracts : l1_contracts;
}

let setup_l1_contracts ?(dictator = Constant.bootstrap2) client =
  (* Originates the delayed transaction bridge. *)
  let* delayed_transaction_bridge =
    Client.originate_contract
      ~alias:"evm-seq-delayed-bridge"
      ~amount:Tez.zero
      ~src:Constant.bootstrap1.public_key_hash
      ~prg:(delayed_path ())
      ~burn_cap:Tez.one
      client
  in
  let* () = Client.bake_for_and_wait ~keys:[] client in
  (* Originates the exchanger. *)
  let* exchanger =
    Client.originate_contract
      ~alias:"exchanger"
      ~amount:Tez.zero
      ~src:Constant.bootstrap1.public_key_hash
      ~init:"Unit"
      ~prg:(exchanger_path ())
      ~burn_cap:Tez.one
      client
  in
  (* Originates the bridge. *)
  let* bridge =
    Client.originate_contract
      ~alias:"evm-bridge"
      ~amount:Tez.zero
      ~src:Constant.bootstrap2.public_key_hash
      ~init:(sf "Pair %S None" exchanger)
      ~prg:(bridge_path ())
      ~burn_cap:Tez.one
      client
  (* Originates the administrator contract. *)
  and* admin =
    Client.originate_contract
      ~alias:"evm-admin"
      ~amount:Tez.zero
      ~src:Constant.bootstrap3.public_key_hash
      ~init:(sf "%S" dictator.Account.public_key_hash)
      ~prg:(admin_path ())
      ~burn_cap:Tez.one
      client
    (* Originates the administrator contract. *)
  and* sequencer_governance =
    Client.originate_contract
      ~alias:"evm-sequencer-admin"
      ~amount:Tez.zero
      ~src:Constant.bootstrap4.public_key_hash
      ~init:(sf "%S" dictator.Account.public_key_hash)
      ~prg:(admin_path ())
      ~burn_cap:Tez.one
      client
  in
  let* () = Client.bake_for_and_wait ~keys:[] client in
  return
    {delayed_transaction_bridge; exchanger; bridge; admin; sequencer_governance}

let setup_sequencer ?(devmode = true) ?genesis_timestamp ?time_between_blocks
    ?max_blueprints_lag ?max_blueprints_ahead ?max_blueprints_catchup
    ?catchup_cooldown ?delayed_inbox_timeout ?delayed_inbox_min_levels
    ?max_number_of_chunks
    ?(bootstrap_accounts =
      List.map
        (fun account -> account.Eth_account.address)
        (Array.to_list Eth_account.bootstrap_accounts))
    ?(sequencer = Constant.bootstrap1) ?sequencer_pool_address
    ?(kernel = Constant.WASM.evm_kernel) ?da_fee ?minimum_base_fee_per_gas
    ?preimages_dir ?maximum_allowed_ticks ?maximum_gas_per_transaction
    ?(threshold_encryption = false) ?(wal_sqlite_journal_mode = true)
    ?(drop_duplicate_when_injection = true) protocol =
  let* node, client = setup_l1 ?timestamp:genesis_timestamp protocol in
  let* l1_contracts = setup_l1_contracts client in
  let sc_rollup_node =
    Sc_rollup_node.create
      ~default_operator:Constant.bootstrap1.public_key_hash
      Batcher
      node
      ~base_dir:(Client.base_dir client)
  in
  let preimages_dir =
    Option.value
      ~default:(Sc_rollup_node.data_dir sc_rollup_node // "wasm_2_0_0")
      preimages_dir
  in
  let output_config = Temp.file "config.yaml" in
  let*! () =
    Evm_node.make_kernel_installer_config
      ~sequencer:sequencer.public_key
      ~delayed_bridge:l1_contracts.delayed_transaction_bridge
      ~ticketer:l1_contracts.exchanger
      ~administrator:l1_contracts.admin
      ~sequencer_governance:l1_contracts.sequencer_governance
      ?minimum_base_fee_per_gas
      ?da_fee_per_byte:da_fee
      ?delayed_inbox_timeout
      ?delayed_inbox_min_levels
      ?sequencer_pool_address
      ?maximum_allowed_ticks
      ?maximum_gas_per_transaction
      ~bootstrap_accounts
      ~output:output_config
      ()
  in
  let* {output; _} =
    prepare_installer_kernel ~preimages_dir ~config:(`Path output_config) kernel
  in
  let* sc_rollup_address =
    originate_sc_rollup
      ~keys:[]
      ~kind:"wasm_2_0_0"
      ~boot_sector:("file:" ^ output)
      ~parameters_ty:Helpers.evm_type
      client
  in
  let* () =
    Sc_rollup_node.run sc_rollup_node sc_rollup_address [Log_kernel_debug]
  in
  let private_rpc_port = Some (Port.fresh ()) in
  let patch_config =
    Evm_node.patch_config_with_experimental_feature
      ~wal_sqlite_journal_mode
      ~drop_duplicate_when_injection
    (* When adding new experimental feature please make sure it's a
       good idea to activate it for all test or not. *)
  in
  let* sequencer_mode =
    if threshold_encryption then
      let sequencer_sidecar_port = Some (Port.fresh ()) in
      let sequencer_sidecar =
        Dsn_node.sequencer ?rpc_port:sequencer_sidecar_port ()
      in
      let* () = Dsn_node.start sequencer_sidecar in
      return
      @@ Evm_node.Threshold_encryption_sequencer
           {
             initial_kernel = output;
             preimage_dir = Some preimages_dir;
             private_rpc_port;
             time_between_blocks;
             sequencer = sequencer.alias;
             genesis_timestamp;
             max_blueprints_lag;
             max_blueprints_ahead;
             max_blueprints_catchup;
             catchup_cooldown;
             max_number_of_chunks;
             devmode;
             wallet_dir = Some (Client.base_dir client);
             tx_pool_timeout_limit = None;
             tx_pool_addr_limit = None;
             tx_pool_tx_per_addr_limit = None;
             sequencer_sidecar_endpoint = Dsn_node.endpoint sequencer_sidecar;
           }
    else
      return
      @@ Evm_node.Sequencer
           {
             initial_kernel = output;
             preimage_dir = Some preimages_dir;
             private_rpc_port;
             time_between_blocks;
             sequencer = sequencer.alias;
             genesis_timestamp;
             max_blueprints_lag;
             max_blueprints_ahead;
             max_blueprints_catchup;
             catchup_cooldown;
             max_number_of_chunks;
             devmode;
             wallet_dir = Some (Client.base_dir client);
             tx_pool_timeout_limit = None;
             tx_pool_addr_limit = None;
             tx_pool_tx_per_addr_limit = None;
           }
  in
  let* sequencer =
    Evm_node.init
      ~patch_config
      ~mode:sequencer_mode
      (Sc_rollup_node.endpoint sc_rollup_node)
  in
  let* observer_mode =
    if threshold_encryption then
      let bundler =
        Dsn_node.bundler ~endpoint:(Evm_node.endpoint sequencer) ()
      in
      let* () = Dsn_node.start bundler in
      return
        (Evm_node.Threshold_encryption_observer
           {
             initial_kernel = output;
             preimages_dir;
             rollup_node_endpoint = Sc_rollup_node.endpoint sc_rollup_node;
             bundler_node_endpoint = Dsn_node.endpoint bundler;
             devmode;
           })
    else
      return
        (Evm_node.Observer
           {
             initial_kernel = output;
             preimages_dir;
             rollup_node_endpoint = Sc_rollup_node.endpoint sc_rollup_node;
             devmode;
           })
  in
  let* observer =
    Evm_node.init
      ~patch_config
      ~mode:observer_mode
      (Evm_node.endpoint sequencer)
  in
  let* proxy =
    Evm_node.init
      ~patch_config
      ~mode:(Proxy {devmode})
      (Sc_rollup_node.endpoint sc_rollup_node)
  in
  return
    {
      node;
      client;
      sequencer;
      proxy;
      observer;
      l1_contracts;
      sc_rollup_address;
      sc_rollup_node;
    }

let send_transaction (transaction : unit -> 'a Lwt.t) sequencer : 'a Lwt.t =
  let wait_for = Evm_node.wait_for_tx_pool_add_transaction sequencer in
  (* Send the transaction but doesn't wait to be mined. *)
  let transaction = transaction () in
  let* _ = wait_for in
  (* Once the transaction is in the transaction pool the next block will include it. *)
  let*@ _ = Rpc.produce_block sequencer in
  (* Resolve the transaction send to make sure it was included. *)
  transaction

let send_raw_transaction_to_delayed_inbox ?(wait_for_next_level = true)
    ?(amount = Tez.one) ?expect_failure ~sc_rollup_node ~client ~l1_contracts
    ~sc_rollup_address ?(sender = Constant.bootstrap2) raw_tx =
  let expected_hash =
    `Hex raw_tx |> Hex.to_bytes |> Tezos_crypto.Hacl.Hash.Keccak_256.digest
    |> Hex.of_bytes |> Hex.show
  in
  let* () =
    Client.transfer
      ~arg:(sf "Pair %S 0x%s" sc_rollup_address raw_tx)
      ~amount
      ~giver:sender.public_key_hash
      ~receiver:l1_contracts.delayed_transaction_bridge
      ~burn_cap:Tez.one
      ?expect_failure
      client
  in
  let* () =
    if wait_for_next_level then
      let* _ = next_rollup_node_level ~sc_rollup_node ~client in
      unit
    else unit
  in
  Lwt.return expected_hash

let send_deposit_to_delayed_inbox ~amount ~l1_contracts ~depositor ~receiver
    ~sc_rollup_node ~sc_rollup_address client =
  let* () =
    Client.transfer
      ~entrypoint:"deposit"
      ~arg:(sf "Pair %S %s" sc_rollup_address receiver)
      ~amount
      ~giver:depositor.Account.public_key_hash
      ~receiver:l1_contracts.bridge
      ~burn_cap:Tez.one
      client
  in
  let* _ = next_rollup_node_level ~sc_rollup_node ~client in
  unit

let register_test ?devmode ?genesis_timestamp ?time_between_blocks
    ?max_blueprints_lag ?max_blueprints_ahead ?max_blueprints_catchup
    ?catchup_cooldown ?delayed_inbox_timeout ?delayed_inbox_min_levels
    ?max_number_of_chunks ?bootstrap_accounts ?sequencer ?sequencer_pool_address
    ?kernel ?da_fee ?minimum_base_fee_per_gas ?preimages_dir
    ?maximum_allowed_ticks ?maximum_gas_per_transaction
    ?(threshold_encryption = false) ?(uses = uses) body =
  let uses =
    if threshold_encryption then fun p -> Constant.octez_dsn_node :: uses p
    else uses
  in
  let body protocol =
    let* sequencer_setup =
      setup_sequencer
        ?devmode
        ?genesis_timestamp
        ?time_between_blocks
        ?max_blueprints_lag
        ?max_blueprints_ahead
        ?max_blueprints_catchup
        ?catchup_cooldown
        ?delayed_inbox_timeout
        ?delayed_inbox_min_levels
        ?max_number_of_chunks
        ?bootstrap_accounts
        ?sequencer
        ?sequencer_pool_address
        ?kernel
        ?da_fee
        ?minimum_base_fee_per_gas
        ?preimages_dir
        ?maximum_allowed_ticks
        ?maximum_gas_per_transaction
        ~threshold_encryption
        protocol
    in
    body sequencer_setup protocol
  in
  Protocol.register_test
    ~additional_tags:(function Alpha -> [] | _ -> [Tag.slow])
    ~__FILE__
    ~uses
    body

let register_both ?devmode ?genesis_timestamp ?time_between_blocks
    ?max_blueprints_lag ?max_blueprints_ahead ?max_blueprints_catchup
    ?catchup_cooldown ?delayed_inbox_timeout ?delayed_inbox_min_levels
    ?max_number_of_chunks ?bootstrap_accounts ?sequencer ?sequencer_pool_address
    ?kernel ?da_fee ?minimum_base_fee_per_gas ?preimages_dir
    ?maximum_allowed_ticks ?maximum_gas_per_transaction ?uses ~title ~tags body
    protocols =
  let register ~threshold_encryption =
    register_test
      ?devmode
      ?genesis_timestamp
      ?time_between_blocks
      ?max_blueprints_lag
      ?max_blueprints_ahead
      ?max_blueprints_catchup
      ?catchup_cooldown
      ?delayed_inbox_timeout
      ?delayed_inbox_min_levels
      ?max_number_of_chunks
      ?bootstrap_accounts
      ?sequencer
      ?sequencer_pool_address
      ?kernel
      ?da_fee
      ?minimum_base_fee_per_gas
      ?preimages_dir
      ?maximum_allowed_ticks
      ?maximum_gas_per_transaction
      ?uses
      ~threshold_encryption
      body
      protocols
  in
  register ~threshold_encryption:false ~title:(sf "%s (sequencer)" title) ~tags ;
  register
    ~threshold_encryption:true
    ~title:(sf "%s (te_sequencer)" title)
    ~tags:(Tag.ci_disabled :: "threshold_encryption" :: tags)

module Protocol = struct
  include Protocol

  let register_test ~__FILE__ ~title ~tags ?uses ?uses_node ?uses_client
      ?uses_admin_client ?supports _body protocols =
    Protocol.register_test
      ~__FILE__
      ~title
      ~tags
      ?uses
      ?uses_node
      ?uses_client
      ?uses_admin_client
      ?supports
      (fun _protocol ->
        Test.fail
          ~loc:__LOC__
          "Do not call Protocol.register_test directly. Use register_test, or \
           register_both instead.")
      protocols
    [@@warning "-unused-value-declaration"]
end

let test_remove_sequencer =
  register_both
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "admin"]
    ~title:"Remove sequencer via sequencer admin contract"
  @@ fun {
           sequencer;
           proxy;
           sc_rollup_node;
           client;
           sc_rollup_address;
           l1_contracts;
           observer;
           _;
         }
             _protocol ->
  (* Produce blocks to show that both the sequencer and proxy are not
     progressing. *)
  let* _ =
    repeat 5 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  (* Both are at genesis *)
  let*@ sequencer_head = Rpc.block_number sequencer in
  let*@ proxy_head = Rpc.block_number proxy in
  Check.((sequencer_head = 0l) int32)
    ~error_msg:"Sequencer should be at genesis" ;
  Check.((sequencer_head = proxy_head) int32)
    ~error_msg:"Sequencer and proxy should have the same block number" ;
  (* Remove the sequencer via the sequencer-admin contract. *)
  let* () =
    Client.transfer
      ~amount:Tez.zero
      ~giver:Constant.bootstrap2.public_key_hash
      ~receiver:l1_contracts.sequencer_governance
      ~arg:(sf "Pair %S 0x" sc_rollup_address)
      ~burn_cap:Tez.one
      client
  in
  let* exit_code = Evm_node.wait_for_shutdown_event sequencer
  and* missing_block_nb = Evm_node.wait_for_rollup_node_ahead observer
  and* () =
    (* Produce L1 blocks to show that only the proxy is progressing *)
    repeat 5 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  Check.((exit_code = 100) int) ~error_msg:"Expected exit code %R, got %L" ;
  (* Sequencer is at genesis, proxy is at [advance]. *)
  Check.((missing_block_nb = 1) int)
    ~error_msg:"Sequencer should be missing block %L" ;
  let*@ proxy_head = Rpc.block_number proxy in
  Check.((proxy_head > 0l) int32) ~error_msg:"Proxy should have advanced" ;

  unit

let test_persistent_state =
  register_both
    ~tags:["evm"; "sequencer"]
    ~title:"Sequencer state is persistent across runs"
  @@ fun {sequencer; _} _protocol ->
  (* Force the sequencer to produce a block. *)
  let*@ _ = Rpc.produce_block sequencer in
  (* Ask for the current block. *)
  let*@ block_number = Rpc.block_number sequencer in
  Check.is_true
    ~__LOC__
    (block_number > 0l)
    ~error_msg:"The sequencer should have produced a block" ;
  (* Terminate the sequencer. *)
  let* () = Evm_node.terminate sequencer in
  (* Restart it. *)
  let* () = Evm_node.run sequencer in
  (* Assert the block number is at least [block_number]. Asserting
     that the block number is exactly the same as {!block_number} can
     be flaky if a block is produced between the restart and the
     RPC. *)
  let*@ new_block_number = Rpc.block_number sequencer in
  Check.is_true
    ~__LOC__
    (new_block_number >= block_number)
    ~error_msg:"The sequencer should have produced a block" ;
  unit

let test_publish_blueprints =
  register_both
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "data"]
    ~title:"Sequencer publishes the blueprints to L1"
  @@ fun {sequencer; proxy; client; sc_rollup_node; _} _protocol ->
  let* _ =
    repeat 5 (fun () ->
        let*@ _ = Rpc.produce_block sequencer in
        unit)
  in

  let* () = Evm_node.wait_for_blueprint_injected ~timeout:5. sequencer 5 in

  (* At this point, the evm node should called the batcher endpoint to publish
     all the blueprints. Stopping the node is then not a problem. *)
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in

  (* We have unfortunately noticed that the test can be flaky. Sometimes,
     the following RPC is done before the proxy being initialised, even though
     we wait for it. The source of flakiness is unknown but happens very rarely,
     we put a small sleep to make the least flaky possible. *)
  let* () = Lwt_unix.sleep 2. in
  check_head_consistency ~left:sequencer ~right:proxy ()

let test_sequencer_too_ahead =
  let max_blueprints_ahead = 5 in
  register_both
    ~max_blueprints_ahead
    ~time_between_blocks:Nothing
    ~tags:["evm"; "max_blueprint_ahead"]
    ~title:"Sequencer locks production if it's too ahead"
  @@ fun {sequencer; sc_rollup_node; proxy; client; sc_rollup_address; _}
             _protocol ->
  let* () = bake_until_sync ~sc_rollup_node ~proxy ~sequencer ~client () in
  let* () = Sc_rollup_node.terminate sc_rollup_node in
  let* () =
    repeat (max_blueprints_ahead * 2) (fun () ->
        let*@ _ = Rpc.produce_block sequencer in
        unit)
  and* () = Evm_node.wait_for_block_producer_locked sequencer in
  let*@ block_number = Rpc.block_number sequencer in
  Check.((block_number = 6l) int32)
    ~error_msg:"The sequencer should have been locked" ;
  let* () = Sc_rollup_node.run sc_rollup_node sc_rollup_address []
  and* () = Evm_node.wait_for_rollup_node_follower_connection_acquired sequencer
  and* () = Evm_node.wait_for_rollup_node_follower_connection_acquired proxy in
  let* () = bake_until_sync ~sc_rollup_node ~proxy ~sequencer ~client () in
  let* _ =
    repeat 2 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  let new_blocks = 3l in
  let* () =
    repeat (Int32.to_int new_blocks) (fun () ->
        let*@ _ = Rpc.produce_block sequencer in
        unit)
  in
  let previous_block_number = block_number in
  let*@ block_number = Rpc.block_number sequencer in
  Check.((block_number = Int32.add previous_block_number new_blocks) int32)
    ~error_msg:"The sequencer should have been unlocked" ;
  unit

let test_resilient_to_rollup_node_disconnect =
  (* The objective of this test is to show that the sequencer can deal with
     rollup node outage. The logic of the sequencer at the moment is to
     wait for its advance on the rollup node to be more than [max_blueprints_lag]
     before sending at most [max_blueprints_catchup] blueprints. The sequencer
     waits for [catchup_cooldown] L1 blocks before checking if it needs to push
     new blueprints again. This scenario checks this logic. *)
  let max_blueprints_lag = 10 in
  let max_blueprints_catchup = max_blueprints_lag - 3 in
  let catchup_cooldown = 10 in
  let first_batch_blueprints_count = 5 in
  register_both
    ~max_blueprints_lag
    ~max_blueprints_catchup
    ~catchup_cooldown
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "data"; Tag.flaky]
    ~title:"Sequencer is resilient to rollup node disconnection"
  @@ fun {
           sequencer;
           proxy;
           sc_rollup_node;
           sc_rollup_address;
           client;
           observer;
           _;
         }
             _protocol ->
  (* Produce blueprints *)
  let* _ =
    repeat first_batch_blueprints_count (fun () ->
        let*@ _ = Rpc.produce_block sequencer in
        unit)
  in
  let* () =
    Evm_node.wait_for_blueprint_injected sequencer first_batch_blueprints_count
  in

  (* Produce some L1 blocks so that the rollup node publishes the blueprints. *)
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in

  let*@ rollup_node_head = Rpc.get_block_by_number ~block:"latest" proxy in
  Check.(
    (rollup_node_head.number = Int32.(of_int first_batch_blueprints_count))
      int32)
    ~error_msg:
      "The rollup node should have received the first round of lost blueprints \
       (rollup node level: %L, expected level %R)" ;

  (* Check sequencer and rollup consistency *)
  let* () = check_head_consistency ~left:sequencer ~right:proxy () in

  let* () =
    (* bake 2 block so evm_node sees it as finalized in
       `rollup_node_follower` *)
    repeat 2 (fun () ->
        let* _lvl = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in

  (* Kill the rollup node *)
  let* () = Sc_rollup_node.terminate sc_rollup_node in

  (* The sequencer node should keep producing blocks, enough so that
     it cannot catchup in one go. *)
  let* _ =
    repeat (2 * max_blueprints_lag) (fun () ->
        let*@ _ = Rpc.produce_block sequencer in
        unit)
  in

  let* () =
    Evm_node.wait_for_blueprint_applied
      sequencer
      (first_batch_blueprints_count + (2 * max_blueprints_lag))
  and* () =
    Evm_node.wait_for_blueprint_applied
      observer
      (first_batch_blueprints_count + (2 * max_blueprints_lag))
  in

  (* restart the rollup node to reestablish the connection *)
  let* () = Sc_rollup_node.run sc_rollup_node sc_rollup_address []
  and* () = Evm_node.wait_for_rollup_node_follower_connection_acquired sequencer
  and* () = Evm_node.wait_for_rollup_node_follower_connection_acquired observer
  and* () = Evm_node.wait_for_rollup_node_follower_connection_acquired proxy in

  (* Produce enough blocks in advance to ensure the sequencer node will catch
     up at the end. *)
  let* _ =
    repeat max_blueprints_lag (fun () ->
        let*@ _ = Rpc.produce_block sequencer in
        unit)
  in

  let* () =
    Evm_node.wait_for_blueprint_applied
      sequencer
      (first_batch_blueprints_count + (2 * max_blueprints_catchup) + 1)
  and* () =
    Evm_node.wait_for_blueprint_applied
      observer
      (first_batch_blueprints_count + (2 * max_blueprints_catchup) + 1)
  in

  (* Give some time for the sequencer node to inject the first round of
     blueprints *)
  let* _ =
    let expected_level =
      Int32.of_int @@ (first_batch_blueprints_count + max_blueprints_catchup)
    in
    bake_until
      ~__LOC__
      ~bake:(fun () ->
        let* _lvl = next_rollup_node_level ~sc_rollup_node ~client in

        unit)
      ~result_f:(fun () ->
        let*@ rollup_node_head =
          Rpc.get_block_by_number ~block:"latest" proxy
        in
        if rollup_node_head.number = expected_level then return (Some ())
        else return None)
      ()
  in

  (* Go through several cooldown periods to let the sequencer sends the rest of
     the blueprints. *)
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in

  (* Check the consistency again *)
  check_head_consistency
    ~error_msg:
      "The head should be the same after the outage. Sequencer: {%L}, proxy: \
       {%R}"
    ~left:sequencer
    ~right:proxy
    ()

let test_can_fetch_blueprint =
  register_both
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "data"]
    ~title:"Sequencer can provide blueprints on demand"
  @@ fun {sequencer; _} _protocol ->
  let number_of_blocks = 5 in
  let* _ =
    repeat number_of_blocks (fun () ->
        let*@ _ = Rpc.produce_block sequencer in
        unit)
  in

  let* () = Evm_node.wait_for_blueprint_injected ~timeout:5. sequencer 5 in

  let* blueprints =
    fold number_of_blocks [] (fun i acc ->
        let* blueprint =
          Sequencer_rpc.get_blueprint sequencer Int64.(of_int @@ (i + 1))
        in
        return (blueprint :: acc))
  in

  (* Test for uniqueness  *)
  let blueprints_uniq =
    List.sort_uniq
      (fun b1 b2 -> String.compare (JSON.encode b1) (JSON.encode b2))
      blueprints
  in
  if List.length blueprints = List.length blueprints_uniq then unit
  else
    Test.fail
      ~__LOC__
      "At least two blueprints from a different level are equal."

let test_can_fetch_smart_rollup_address =
  register_both
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "rpc"]
    ~title:"Sequencer can return the smart rollup address on demand"
  @@ fun {sequencer; sc_rollup_address; _} _protocol ->
  let* claimed_address = Sequencer_rpc.get_smart_rollup_address sequencer in

  Check.((sc_rollup_address = claimed_address) string)
    ~error_msg:"Returned address is not the expected one" ;

  unit

let test_send_transaction_to_delayed_inbox =
  register_both
    ~da_fee:arb_da_fee_for_delayed_inbox
    ~tags:["evm"; "sequencer"; "delayed_inbox"]
    ~title:"Send a transaction to the delayed inbox"
  @@ fun {client; l1_contracts; sc_rollup_address; sc_rollup_node; _} _protocol
    ->
  let raw_transfer =
    "f86d80843b9aca00825b0494b53dc01974176e5dff2298c5a94343c2585e3c54880de0b6b3a764000080820a96a07a3109107c6bd1d555ce70d6253056bc18996d4aff4d4ea43ff175353f49b2e3a05f9ec9764dc4a3c3ab444debe2c3384070de9014d44732162bb33ee04da187ef"
  in
  let send ~amount ?expect_failure () =
    send_raw_transaction_to_delayed_inbox
      ~sc_rollup_node
      ~client
      ~l1_contracts
      ~sc_rollup_address
      ~amount
      ?expect_failure
      raw_transfer
  in
  (* Test that paying less than 1XTZ is not allowed. *)
  let* _hash =
    send ~amount:(Tez.parse_floating "0.9") ~expect_failure:true ()
  in
  (* Test the correct case where the user burns 1XTZ to send the transaction. *)
  let* hash = send ~amount:Tez.one ~expect_failure:false () in
  (* Assert that the expected transaction hash is found in the delayed inbox
     durable storage path. *)
  let* delayed_transactions_hashes =
    Sc_rollup_node.RPC.call sc_rollup_node
    @@ Sc_rollup_rpc.get_global_block_durable_state_value
         ~pvm_kind:"wasm_2_0_0"
         ~operation:Sc_rollup_rpc.Subkeys
         ~key:"/evm/delayed-inbox"
         ()
  in
  Check.(list_mem string hash delayed_transactions_hashes)
    ~error_msg:"hash %L should be present in the delayed inbox %R" ;
  (* Test that paying more than 1XTZ is allowed. *)
  let* _hash =
    send ~amount:(Tez.parse_floating "1.1") ~expect_failure:false ()
  in
  unit

let test_send_deposit_to_delayed_inbox =
  register_both
    ~da_fee:arb_da_fee_for_delayed_inbox
    ~tags:["evm"; "sequencer"; "delayed_inbox"; "deposit"]
    ~title:"Send a deposit to the delayed inbox"
  @@ fun {client; l1_contracts; sc_rollup_address; sc_rollup_node; _} _protocol
    ->
  let amount = Tez.of_int 16 in
  let depositor = Constant.bootstrap5 in
  let receiver =
    Eth_account.
      {
        address = "0x1074Fd1EC02cbeaa5A90450505cF3B48D834f3EB";
        private_key =
          "0xb7c548b5442f5b28236f0dcd619f65aaaafd952240908adcf9642d8e616587ee";
        public_key =
          "0466ed90f9a86c0908746475fbe0a40c72237de22d89076302e22c2a8da259b4aba5c7ee1f3dc3fd0b240645462620ae62b6fe8fe5b3464c3b1b4ae6c06c97b7b6";
      }
  in
  let* () =
    send_deposit_to_delayed_inbox
      ~amount
      ~l1_contracts
      ~depositor
      ~receiver:receiver.address
      ~sc_rollup_node
      ~sc_rollup_address
      client
  in
  let* delayed_transactions_hashes =
    Sc_rollup_node.RPC.call sc_rollup_node
    @@ Sc_rollup_rpc.get_global_block_durable_state_value
         ~pvm_kind:"wasm_2_0_0"
         ~operation:Sc_rollup_rpc.Subkeys
         ~key:"/evm/delayed-inbox"
         ()
  in
  Check.(
    list_mem
      string
      "a07feb67aff94089c8d944f5f8ffb5acc37306da9102fc310264e90999a42eb1"
      delayed_transactions_hashes)
    ~error_msg:"the deposit is not present in the delayed inbox" ;
  unit

let test_rpc_produceBlock =
  register_both
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "produce_block"]
    ~title:"RPC method produceBlock"
  @@ fun {sequencer; _} _protocol ->
  let*@ start_block_number = Rpc.block_number sequencer in
  let*@ _ = Rpc.produce_block sequencer in
  let*@ new_block_number = Rpc.block_number sequencer in
  Check.((Int32.succ start_block_number = new_block_number) int32)
    ~error_msg:"Expected new block number to be %L, but got: %R" ;
  unit

let wait_for_event ?(timeout = 30.) ?(levels = 10) event_watcher ~sequencer
    ~sc_rollup_node ~client ~error_msg =
  let event_value = ref None in
  let _ =
    let* return_value = event_watcher in
    event_value := Some return_value ;
    unit
  in
  let rec rollup_node_loop n =
    if n = 0 then Test.fail error_msg
    else
      let* _ = next_rollup_node_level ~sc_rollup_node ~client in
      let*@ _ = Rpc.produce_block sequencer in
      if Option.is_some !event_value then unit else rollup_node_loop (n - 1)
  in
  let* () = Lwt.pick [rollup_node_loop levels; Lwt_unix.sleep timeout] in
  match !event_value with
  | Some value -> return value
  | None -> Test.fail ~loc:__LOC__ "Waiting for event failed"

let wait_for_delayed_inbox_add_tx_and_injected ~sequencer ~sc_rollup_node
    ~client =
  let event_watcher =
    let added = Evm_node.wait_for_evm_event New_delayed_transaction sequencer in
    let injected = Evm_node.wait_for_block_producer_tx_injected sequencer in
    let* (_transaction_kind, added_hash), injected_hash =
      Lwt.both added injected
    in
    Check.((added_hash = injected_hash) string)
      ~error_msg:"Injected hash %R is not the expected one %L" ;
    Lwt.return_unit
  in
  wait_for_event
    event_watcher
    ~sequencer
    ~sc_rollup_node
    ~client
    ~error_msg:
      "Timed out while waiting for transaction to be added to the delayed \
       inbox and injected"

let check_delayed_inbox_is_empty ~sc_rollup_node =
  let* subkeys =
    Sc_rollup_node.RPC.call sc_rollup_node ~rpc_hooks:Tezos_regression.rpc_hooks
    @@ Sc_rollup_rpc.get_global_block_durable_state_value
         ~pvm_kind:"wasm_2_0_0"
         ~operation:Sc_rollup_rpc.Subkeys
         ~key:Durable_storage_path.delayed_inbox
         ()
  in
  Check.((List.length subkeys = 1) int)
    ~error_msg:"Expected no elements in the delayed inbox" ;
  unit

let test_delayed_transfer_is_included =
  register_both
    ~da_fee:arb_da_fee_for_delayed_inbox
    ~tags:["evm"; "sequencer"; "delayed_inbox"; "inclusion"]
    ~title:"Delayed transaction is included"
  @@ fun {
           client;
           l1_contracts;
           sc_rollup_address;
           sc_rollup_node;
           sequencer;
           proxy;
           observer;
           _;
         }
             _protocol ->
  let endpoint = Evm_node.endpoint sequencer in
  (* This is a transfer from Eth_account.bootstrap_accounts.(0) to
     Eth_account.bootstrap_accounts.(1). *)
  let raw_transfer =
    "f86d80843b9aca00825b0494b53dc01974176e5dff2298c5a94343c2585e3c54880de0b6b3a764000080820a96a07a3109107c6bd1d555ce70d6253056bc18996d4aff4d4ea43ff175353f49b2e3a05f9ec9764dc4a3c3ab444debe2c3384070de9014d44732162bb33ee04da187ef"
  in
  let sender = Eth_account.bootstrap_accounts.(0).address in
  let receiver = Eth_account.bootstrap_accounts.(1).address in
  let* sender_balance_prev = Eth_cli.balance ~account:sender ~endpoint in
  let* receiver_balance_prev = Eth_cli.balance ~account:receiver ~endpoint in
  let* tx_hash =
    send_raw_transaction_to_delayed_inbox
      ~sc_rollup_node
      ~client
      ~l1_contracts
      ~sc_rollup_address
      raw_transfer
  in
  let* () =
    wait_for_delayed_inbox_add_tx_and_injected
      ~sequencer
      ~sc_rollup_node
      ~client
  in
  let* () = bake_until_sync ~sc_rollup_node ~proxy ~sequencer ~client () in
  let* () = check_delayed_inbox_is_empty ~sc_rollup_node in
  let* sender_balance_next = Eth_cli.balance ~account:sender ~endpoint in
  let* receiver_balance_next = Eth_cli.balance ~account:receiver ~endpoint in
  Check.((sender_balance_prev > sender_balance_next) Wei.typ)
    ~error_msg:"Expected a smaller sender balance (before: %L < after: %R)" ;
  Check.((receiver_balance_next > receiver_balance_prev) Wei.typ)
    ~error_msg:"Expected a bigger receiver balance (before: %L > after: %R)" ;
  let*@! (_receipt : Transaction.transaction_receipt) =
    Rpc.get_transaction_receipt ~tx_hash observer
  in
  unit

let test_largest_delayed_transfer_is_included =
  register_both
    ~da_fee:arb_da_fee_for_delayed_inbox
    ~tags:["evm"; "sequencer"; "delayed_inbox"; "inclusion"]
    ~title:"Largest possible delayed transaction is included"
  @@ fun {
           client;
           l1_contracts;
           sc_rollup_address;
           sc_rollup_node;
           sequencer;
           proxy;
           _;
         }
             _protocol ->
  let _endpoint = Evm_node.endpoint sequencer in
  (* This is the largest ethereum transaction we transfer via the bridge contract. *)
  let transfer_that_fits =
    "f90fb58209138502540be40082520894b53dc01974176e5dff2298c5a94343c2585e3c54880de0b6b3a7640000b90f4500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000025a0f42f0b16afabe4ab2ecc258987540f63706283e7ad054a06ef2cc762bc32ad0da07edfd65f510c8c7abac684b4a820e1d54182cd67aeec7cff3b089f84fc8c4698"
  in
  let len_transfer_that_fits = String.length transfer_that_fits / 2 in
  Log.info "Maximum size allowed is %d" len_transfer_that_fits ;
  (* We assert that this is the largest by sending a transaction that is 1 byte
     larger, the protocol refuses it. *)
  let transfer_too_big =
    "f90fb68209138502540be40082520894b53dc01974176e5dff2298c5a94343c2585e3c54880de0b6b3a7640000b90f460000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000026a094cee0c8af621cd6ff1cace4265311ee1497e62216413a2db989e26a471fe904a0277da4faf3652d2f3413e00887da47c64fde06da7f1c6c87276bc937ed1c7530"
  in
  let len_transfer_too_big = String.length transfer_too_big / 2 in
  assert (len_transfer_that_fits + 1 = len_transfer_too_big) ;
  let* _hash =
    send_raw_transaction_to_delayed_inbox
      ~sc_rollup_node
      ~client
      ~l1_contracts
      ~sc_rollup_address
      ~expect_failure:true
      transfer_too_big
  in
  (* Now we check that the largest possible transaction is included by the sequencer. *)
  let* _hash =
    send_raw_transaction_to_delayed_inbox
      ~sc_rollup_node
      ~client
      ~l1_contracts
      ~sc_rollup_address
      ~expect_failure:false
      transfer_that_fits
  in
  let* () =
    wait_for_delayed_inbox_add_tx_and_injected
      ~sequencer
      ~sc_rollup_node
      ~client
  in
  let* () = bake_until_sync ~sc_rollup_node ~proxy ~sequencer ~client () in
  let* () = check_delayed_inbox_is_empty ~sc_rollup_node in
  unit

let test_delayed_deposit_is_included =
  register_both
    ~da_fee:arb_da_fee_for_delayed_inbox
    ~tags:["evm"; "sequencer"; "delayed_inbox"; "inclusion"; "deposit"]
    ~title:"Delayed deposit is included"
  @@ fun {
           client;
           l1_contracts;
           sc_rollup_address;
           sc_rollup_node;
           sequencer;
           proxy;
           _;
         }
             _protocol ->
  let endpoint = Evm_node.endpoint sequencer in

  let amount = Tez.of_int 16 in
  let depositor = Constant.bootstrap5 in
  let receiver =
    Eth_account.
      {
        address = "0x1074Fd1EC02cbeaa5A90450505cF3B48D834f3EB";
        private_key =
          "0xb7c548b5442f5b28236f0dcd619f65aaaafd952240908adcf9642d8e616587ee";
        public_key =
          "0466ed90f9a86c0908746475fbe0a40c72237de22d89076302e22c2a8da259b4aba5c7ee1f3dc3fd0b240645462620ae62b6fe8fe5b3464c3b1b4ae6c06c97b7b6";
      }
  in
  let* receiver_balance_prev =
    Eth_cli.balance ~account:receiver.address ~endpoint
  in
  let* () =
    send_deposit_to_delayed_inbox
      ~amount
      ~l1_contracts
      ~depositor
      ~receiver:receiver.address
      ~sc_rollup_node
      ~sc_rollup_address
      client
  in
  let* () =
    wait_for_delayed_inbox_add_tx_and_injected
      ~sequencer
      ~sc_rollup_node
      ~client
  in
  let* () = bake_until_sync ~sc_rollup_node ~proxy ~sequencer ~client () in
  let* () = check_delayed_inbox_is_empty ~sc_rollup_node in
  let* receiver_balance_next =
    Eth_cli.balance ~account:receiver.address ~endpoint
  in
  Check.((receiver_balance_next > receiver_balance_prev) Wei.typ)
    ~error_msg:"Expected a bigger balance" ;
  unit

let test_delayed_deposit_from_init_rollup_node =
  register_both
    ~da_fee:arb_da_fee_for_delayed_inbox
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "delayed_inbox"; "init"]
    ~title:"Delayed inbox is populated at init from rollup node"
  @@ fun {
           client;
           l1_contracts;
           sc_rollup_address;
           sc_rollup_node;
           sequencer;
           proxy;
           _;
         }
             _protocol ->
  let receiver = "0x1074Fd1EC02cbeaa5A90450505cF3B48D834f3EB" in
  let* receiver_balance_prev =
    Eth_cli.balance ~account:receiver ~endpoint:(Evm_node.endpoint sequencer)
  in
  let* () = bake_until_sync ~sc_rollup_node ~sequencer ~proxy ~client () in
  (* We don't care about this sequencer. *)
  let* () = Evm_node.terminate sequencer in
  (* Send the deposit to delayed inbox, no sequencer will be listening to the
     event. *)
  let amount = Tez.of_int 16 in
  let depositor = Constant.bootstrap5 in
  let* () =
    send_deposit_to_delayed_inbox
      ~amount
      ~l1_contracts
      ~depositor
      ~receiver
      ~sc_rollup_node
      ~sc_rollup_address
      client
  in
  (* Bake an extra block for a finalized deposit. *)
  let* _lvl = next_rollup_node_level ~sc_rollup_node ~client in
  let* _lvl = next_rollup_node_level ~sc_rollup_node ~client in

  (* Run a new sequencer that is initialized from a rollup node that has the
     delayed deposit in its state. *)
  let new_sequencer =
    let mode = Evm_node.mode sequencer in
    Evm_node.create ~mode (Sc_rollup_node.endpoint sc_rollup_node)
  in
  let* () = Process.check @@ Evm_node.spawn_init_config new_sequencer in
  let* () =
    Evm_node.init_from_rollup_node_data_dir
      ~devmode:true
      new_sequencer
      sc_rollup_node
  in
  let* () = Evm_node.run new_sequencer in

  Log.info "sequencer restarted" ;
  (* The block will include the delayed deposit. *)
  let* () =
    let*@ _lvl = Rpc.produce_block new_sequencer in
    unit
  and* _hash = Evm_node.wait_for_block_producer_tx_injected new_sequencer in
  let* () =
    bake_until_sync ~sc_rollup_node ~proxy ~sequencer:new_sequencer ~client ()
  in
  let* () = check_delayed_inbox_is_empty ~sc_rollup_node in
  let* receiver_balance_next =
    Eth_cli.balance
      ~account:receiver
      ~endpoint:(Evm_node.endpoint new_sequencer)
  in
  Check.((receiver_balance_next > receiver_balance_prev) Wei.typ)
    ~error_msg:"Expected a bigger balance" ;
  unit

(** test to initialise a sequencer data dir based on a rollup node
        data dir *)
let test_init_from_rollup_node_data_dir =
  register_both
    ~time_between_blocks:Nothing
    ~tags:["evm"; "rollup_node"; "init"]
    ~title:"Init evm node sequencer data dir from a rollup node data dir"
  @@ fun {sc_rollup_node; sequencer; proxy; client; _} _protocol ->
  (* a sequencer is needed to produce an initial block *)
  let* () =
    repeat 5 (fun () ->
        let*@ _ = Rpc.produce_block sequencer in
        unit)
  in
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in
  let* () = Evm_node.terminate sequencer in
  let evm_node' =
    Evm_node.create
      ~mode:(Evm_node.mode sequencer)
      (Sc_rollup_node.endpoint sc_rollup_node)
  in
  let* () = Process.check @@ Evm_node.spawn_init_config evm_node' in
  let* () =
    (* bake 2 blocks so rollup context is for the finalized l1 level
       and can't be reorged. *)
    repeat 2 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in

  let* () =
    Evm_node.init_from_rollup_node_data_dir
      ~devmode:true
      evm_node'
      sc_rollup_node
  in
  let* () = Evm_node.run evm_node' in

  let* () = check_head_consistency ~left:evm_node' ~right:proxy () in

  let*@ _ = Rpc.produce_block evm_node' in
  let* () =
    bake_until_sync ~sc_rollup_node ~client ~sequencer:evm_node' ~proxy ()
  in

  let* () = check_head_consistency ~left:evm_node' ~right:proxy () in

  unit

let test_init_from_rollup_node_with_delayed_inbox =
  register_both
    ~time_between_blocks:Nothing
    ~tags:["evm"; "rollup_node"; "init"; "delayed_inbox"]
    ~title:
      "Init evm node sequencer data dir from a rollup node data dir with \
       delayed items"
  @@ fun {
           sc_rollup_node;
           sequencer;
           proxy;
           client;
           l1_contracts;
           sc_rollup_address;
           _;
         }
             _protocol ->
  (* a sequencer is needed to produce an initial block *)
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in
  let* () = Evm_node.terminate sequencer in

  (* deposit *)
  let amount = Tez.of_int 16 in
  let depositor = Constant.bootstrap5 in
  let receiver = Eth_account.bootstrap_accounts.(0) in
  let* () =
    send_deposit_to_delayed_inbox
      ~amount
      ~l1_contracts
      ~depositor
      ~receiver:receiver.address
      ~sc_rollup_node
      ~sc_rollup_address
      client
  in

  (* start a new sequnecer *)
  let evm_node' =
    Evm_node.create
      ~mode:(Evm_node.mode sequencer)
      (Sc_rollup_node.endpoint sc_rollup_node)
  in
  let* () = Process.check @@ Evm_node.spawn_init_config evm_node' in
  let* () =
    (* bake 2 blocks so rollup context is for the finalized l1 level
       and can't be reorged. *)
    repeat 2 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in

  let* () =
    Evm_node.init_from_rollup_node_data_dir
      ~devmode:true
      evm_node'
      sc_rollup_node
  in

  let* () = Evm_node.run evm_node' in

  let* () = check_head_consistency ~left:evm_node' ~right:proxy () in

  let*@ _ = Rpc.produce_block evm_node' in
  let* () =
    bake_until_sync ~sc_rollup_node ~client ~sequencer:evm_node' ~proxy ()
  in

  let* () = check_head_consistency ~left:evm_node' ~right:proxy () in

  unit

let test_observer_applies_blueprint =
  let tbb = 3. in
  register_both
    ~time_between_blocks:(Time_between_blocks tbb)
    ~tags:["evm"; "observer"]
    ~title:"Can start an Observer node"
  @@ fun {sequencer = sequencer_node; observer = observer_node; _} _protocol ->
  let levels_to_wait = 3 in
  let timeout = tbb *. float_of_int levels_to_wait *. 2. in

  let* _ =
    Evm_node.wait_for_blueprint_applied ~timeout observer_node levels_to_wait
  and* _ =
    Evm_node.wait_for_blueprint_applied ~timeout sequencer_node levels_to_wait
  in

  let* () =
    check_block_consistency
      ~left:sequencer_node
      ~right:observer_node
      ~block:(`Level (Int32.of_int levels_to_wait))
      ()
  in

  (* We stop and start the sequencer, to ensure the observer node correctly
     reconnects to it. *)
  let* () = Evm_node.wait_for_retrying_connect observer_node
  and* () =
    let* () = Evm_node.terminate sequencer_node in
    Evm_node.run sequencer_node
  in

  let levels_to_wait = 2 * levels_to_wait in

  let* _ =
    Evm_node.wait_for_blueprint_applied ~timeout observer_node levels_to_wait
  and* _ =
    Evm_node.wait_for_blueprint_applied ~timeout sequencer_node levels_to_wait
  in

  let* () =
    check_block_consistency
      ~left:sequencer_node
      ~right:observer_node
      ~block:(`Level (Int32.of_int levels_to_wait))
      ()
  in

  unit

let test_observer_applies_blueprint_when_restarted =
  register_both
    ~time_between_blocks:Nothing
    ~tags:["evm"; "observer"]
    ~title:"Can restart an Observer node"
  @@ fun {sequencer; observer; _} _protocol ->
  (* We produce a block and check the observer applies it. *)
  let* _ = Evm_node.wait_for_blueprint_applied observer 1
  and* _ = Rpc.produce_block sequencer in

  (* We restart the observer *)
  let* () = Evm_node.terminate observer in
  let* () = Evm_node.run observer in

  (* We produce a block and check the observer applies it. *)
  let* _ = Evm_node.wait_for_blueprint_applied observer 2
  and* _ = Rpc.produce_block sequencer in

  unit

let test_get_balance_block_param =
  register_both
    ~tags:["evm"; "sequencer"; "rpc"; "get_balance"; "block_param"]
    ~title:"RPC method getBalance uses block parameter"
    ~time_between_blocks:Nothing
  @@ fun {sequencer; sc_rollup_node; proxy; client; _} _protocol ->
  (* Transfer funds to a random address. *)
  let address = "0xB7A97043983f24991398E5a82f63F4C58a417185" in
  let* _tx_hash =
    send_transaction
      (Eth_cli.transaction_send
         ~source_private_key:Eth_account.bootstrap_accounts.(0).private_key
         ~to_public_key:address
         ~value:(Wei.of_eth_int 10)
         ~endpoint:(Evm_node.endpoint sequencer))
      sequencer
  in
  (* Check the balance on genesis block and latest block. *)
  let*@ balance_genesis =
    Rpc.get_balance ~address ~block:(Number 0) sequencer
  in
  let*@ balance_now = Rpc.get_balance ~address ~block:Latest sequencer in
  Check.((balance_genesis = Wei.of_eth_int 0) Wei.typ)
    ~error_msg:(sf "%s should have no funds at genesis, but got %%L" address) ;
  Check.((balance_now = Wei.of_eth_int 10) Wei.typ)
    ~error_msg:(sf "Balance of %s expected to be %%R but got %%L" address) ;
  (* Now we will create another observer initialized from the rollup node, in
     order to test the block parameter "earliest". "Earliest" on the current
     sequencer will be block [0] which is not really robust to test. *)
  let* () = bake_until_sync ~sc_rollup_node ~proxy ~sequencer ~client () in
  let* _ =
    repeat 2 (fun _ ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  let observer_partial_history =
    let name = "observer_partial_history" in
    Evm_node.create
      ~name
      ~mode:
        (Observer
           {
             initial_kernel = "evm_kernel.wasm";
             preimages_dir = "/tmp";
             rollup_node_endpoint = Sc_rollup_node.endpoint sc_rollup_node;
             devmode = true;
           })
      ~data_dir:(Temp.dir name)
      (Evm_node.endpoint sequencer)
  in
  let* () =
    Process.check @@ Evm_node.spawn_init_config observer_partial_history
  in
  let* () =
    Evm_node.init_from_rollup_node_data_dir
      ~devmode:true
      observer_partial_history
      sc_rollup_node
  in
  let* () = Evm_node.run observer_partial_history in
  (* Transfer funds again to the address. *)
  let*@ level = Rpc.block_number sequencer in
  let* _tx_hash =
    send_transaction
      (Eth_cli.transaction_send
         ~source_private_key:Eth_account.bootstrap_accounts.(0).private_key
         ~to_public_key:address
         ~value:(Wei.of_eth_int 10)
         ~endpoint:(Evm_node.endpoint sequencer))
      sequencer
  in
  let* () =
    Evm_node.wait_for_blueprint_applied
      observer_partial_history
      (Int32.to_int level + 1)
  in
  (* Observer does not know block 0. *)
  let*@? (_error : Rpc.error) =
    Rpc.get_balance ~address ~block:(Number 0) observer_partial_history
  in
  let*@ balance_earliest =
    Rpc.get_balance ~address ~block:Earliest observer_partial_history
  in
  let*@ balance_now =
    Rpc.get_balance ~address ~block:Latest observer_partial_history
  in
  Check.((balance_earliest = Wei.of_eth_int 10) Wei.typ)
    ~error_msg:(sf "%s expected to have a balance of %%R but got %%L" address) ;
  Check.((balance_now = Wei.of_eth_int 20) Wei.typ)
    ~error_msg:(sf "%s expected to have a balance of %%R but got %%L" address) ;
  unit

let test_get_block_by_number_block_param =
  register_both
    ~tags:["evm"; "sequencer"; "rpc"; "get_block_by_number"; "block_param"]
    ~title:"RPC method getBlockByNumber uses block parameter"
    ~time_between_blocks:Nothing
  @@ fun {sequencer; observer; sc_rollup_node; proxy; client; _} _protocols ->
  let observer_offset = 3l in
  let* () =
    repeat Int32.(to_int observer_offset) @@ fun () ->
    next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client
  in
  let* () = bake_until_sync ~sc_rollup_node ~proxy ~sequencer ~client () in
  let* _ =
    repeat 2 (fun _ ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  let observer_partial_history =
    let name = "observer_partial_history" in
    Evm_node.create
      ~name
      ~mode:
        (Observer
           {
             initial_kernel = "evm_kernel.wasm";
             preimages_dir = "/tmp";
             rollup_node_endpoint = Sc_rollup_node.endpoint sc_rollup_node;
             devmode = true;
           })
      ~data_dir:(Temp.dir name)
      (Evm_node.endpoint sequencer)
  in
  let* () =
    Process.check @@ Evm_node.spawn_init_config observer_partial_history
  in
  let* () =
    Evm_node.init_from_rollup_node_data_dir
      ~devmode:true
      observer_partial_history
      sc_rollup_node
  in
  let* () = Evm_node.run observer_partial_history in
  let* () =
    repeat 2 @@ fun () ->
    next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client
  in

  let*@ earliest_block_sequencer =
    Rpc.get_block_by_number ~block:"earliest" sequencer
  in
  let*@ earliest_block_observer =
    Rpc.get_block_by_number ~block:"earliest" observer
  in
  let*@ earliest_block_observer_partial =
    Rpc.get_block_by_number ~block:"earliest" observer_partial_history
  in

  Check.(
    ((earliest_block_sequencer.number = 0l) int32)
      ~error_msg:"Earliest block of sequencer is %L instead of %R") ;

  Check.(
    ((earliest_block_observer.number = 0l) int32)
      ~error_msg:"Earliest block of observer is %L instead of %R") ;

  Check.(
    ((earliest_block_observer_partial.number = observer_offset) int32)
      ~error_msg:"Earliest block of observer started late is %L instead of %R") ;

  unit

let test_extended_block_param =
  register_both
    ~tags:["evm"; "sequencer"; "rpc"; "block_param"; "counter"]
    ~title:"Supports extended block parameter"
    ~time_between_blocks:Nothing
  @@ fun {sequencer; _} _protocols ->
  (*
     In this test we will deploy a counter contract, increments its counter
     at multiple consecutives blocks, and check the counter using block
     parameter.
     As the counter contract has a view, we can test the block parameter
     both for read only RPCs such as [eth_getStorageAt] and simulation
     such as [eth_call].
  *)
  let* () =
    Eth_cli.add_abi
      ~label:Solidity_contracts.counter.label
      ~abi:Solidity_contracts.counter.abi
      ()
  in
  (* Deploy the contract. *)
  let* contract, _tx_hash =
    send_transaction
      (fun () ->
        Eth_cli.deploy
          ~source_private_key:Eth_account.bootstrap_accounts.(0).private_key
          ~endpoint:(Evm_node.endpoint sequencer)
          ~abi:Solidity_contracts.counter.abi
          ~bin:Solidity_contracts.counter.bin)
      sequencer
  in
  (* Takes the level where it was originated, the counter value will be 0. *)
  let*@ level = Rpc.block_number sequencer in
  let level = Int32.to_int level in
  (* Increments the counter multiple times. *)
  let* () =
    repeat 2 (fun _ ->
        let* _ =
          send_transaction
            (Eth_cli.contract_send
               ~source_private_key:
                 Eth_account.bootstrap_accounts.(0).private_key
               ~endpoint:(Evm_node.endpoint sequencer)
               ~abi_label:Solidity_contracts.counter.label
               ~address:contract
               ~method_call:"incrementCounter()")
            sequencer
        in
        unit)
  in

  let*@ block0 =
    Rpc.get_block_by_number ~block:(string_of_int level) sequencer
  in
  let*@ block1 =
    Rpc.get_block_by_number ~block:(string_of_int (level + 1)) sequencer
  in
  let*@ block2 =
    Rpc.get_block_by_number ~block:(string_of_int (level + 2)) sequencer
  in

  let check_counter_value ~(block : Block.t) expected_value =
    let counter_value ~block =
      let*@ s =
        Rpc.get_storage_at ~address:contract ~pos:"0x0" ~block sequencer
      in
      return (int_of_string s)
    in
    let* counter_via_number =
      counter_value
        ~block:
          (Block_number
             {number = Int32.to_int block.number; require_canonical = false})
    in
    let* counter_via_hash =
      counter_value
        ~block:(Block_hash {hash = block.hash; require_canonical = false})
    in
    let*@ counter_via_call =
      Rpc.(
        call
          ~block:(Number (Int32.to_int block.number))
          ~to_:contract
          ~data:"a87d942c"
          sequencer)
    in
    let counter_via_call = int_of_string counter_via_call in
    Check.((counter_via_number = expected_value) int)
      ~error_msg:"Expected counter to be %R but got %L, using {blockNumber}" ;
    Check.((counter_via_hash = expected_value) int)
      ~error_msg:"Expected counter to be %R but got %L, using {blockHash}" ;
    Check.((counter_via_call = expected_value) int)
      ~error_msg:"Expected counter to be %R but got %L, using eth_call" ;
    unit
  in

  let* () = check_counter_value ~block:block0 0 in
  let* () = check_counter_value ~block:block1 1 in
  let* () = check_counter_value ~block:block2 2 in

  unit

let test_observer_applies_blueprint_when_sequencer_restarted =
  register_both
    ~time_between_blocks:Nothing
    ~tags:["evm"; "observer"]
    ~title:"Can restart the sequencer node"
  @@ fun {sequencer; observer; _} _protocol ->
  (* We produce a block and check the observer applies it. *)
  let* _ = Evm_node.wait_for_blueprint_applied observer 1
  and* _ = Rpc.produce_block sequencer in

  (* We stop the sequencer and wait for the observer to detect it and emit an
     event accordingly. *)
  let* () = Evm_node.terminate sequencer in
  let* () = Evm_node.wait_for_retrying_connect observer in

  (* We wait for a second event from the observer to witness that its first
     reconnection attempt failed. *)
  let* () = Evm_node.wait_for_retrying_connect observer in

  (* We restart the sequencer. *)
  let* () = Evm_node.run sequencer in

  (* We produce a block and check the observer applies it. *)
  let* _ = Evm_node.wait_for_blueprint_applied observer 2
  and* _ = Rpc.produce_block sequencer in

  unit

let test_observer_forwards_transaction =
  let tags = ["evm"; "observer"; "transaction"] in
  let title = "Observer forwards transaction" in
  let tbb = 1. in
  register_both ~time_between_blocks:(Time_between_blocks tbb) ~tags ~title
  @@ fun {sequencer = sequencer_node; observer = observer_node; _} _protocol ->
  (* Ensure the sequencer has produced the block. *)
  let* () =
    Evm_node.wait_for_blueprint_applied ~timeout:10.0 sequencer_node 1
  in
  (* Ensure the observer node has a correctly initialized local state. *)
  let* () = Evm_node.wait_for_blueprint_applied ~timeout:10.0 observer_node 1 in

  let* txn =
    Eth_cli.transaction_send
      ~source_private_key:Eth_account.bootstrap_accounts.(1).private_key
      ~to_public_key:Eth_account.bootstrap_accounts.(2).address
      ~value:Wei.one
      ~endpoint:(Evm_node.endpoint observer_node)
      ()
  in

  let* receipt =
    Eth_cli.get_receipt ~endpoint:(Evm_node.endpoint sequencer_node) ~tx:txn
  in

  match receipt with
  | Some receipt when receipt.status -> unit
  | Some _ ->
      Test.fail
        "transaction receipt received from the sequencer, but transaction \
         failed"
  | None ->
      Test.fail
        "Missing receipt in the sequencer node for transaction successfully \
         injected in the observer"

let test_sequencer_is_reimbursed =
  let tbb = 1. in
  (* We use an arbitrary address for the pool address, the goal is just to
     verify its balance increases. *)
  let sequencer_pool_address = "0xb7a97043983f24991398e5a82f63f4c58a417185" in
  register_both
    ~da_fee:Wei.one
    ~time_between_blocks:(Time_between_blocks tbb)
    ~sequencer_pool_address
    ~tags:["evm"; "sequencer"; "transaction"]
    ~title:"Sequencer is reimbursed for DA fees"
  @@ fun {sequencer = sequencer_node; _} _protocol ->
  let* balance =
    Eth_cli.balance
      ~account:sequencer_pool_address
      ~endpoint:Evm_node.(endpoint sequencer_node)
  in

  Check.((Wei.zero = balance) Wei.typ)
    ~error_msg:"Balance of the sequencer address pool should be null" ;

  (* Ensure the sequencer has produced the block. *)
  let* () =
    Evm_node.wait_for_blueprint_applied ~timeout:10.0 sequencer_node 1
  in

  let* txn =
    Eth_cli.transaction_send
      ~source_private_key:Eth_account.bootstrap_accounts.(1).private_key
      ~to_public_key:Eth_account.bootstrap_accounts.(2).address
      ~value:Wei.one
      ~endpoint:(Evm_node.endpoint sequencer_node)
      ()
  in

  let* receipt =
    Eth_cli.get_receipt ~endpoint:(Evm_node.endpoint sequencer_node) ~tx:txn
  in

  match receipt with
  | Some receipt when receipt.status ->
      let* balance =
        Eth_cli.balance
          ~account:sequencer_pool_address
          ~endpoint:Evm_node.(endpoint sequencer_node)
      in

      Check.((Wei.zero < balance) Wei.typ)
        ~error_msg:"Balance of the sequencer address pool should not be null" ;
      unit
  | Some _ ->
      Test.fail
        "transaction receipt received from the sequencer, but transaction \
         failed"
  | None ->
      Test.fail
        "Missing receipt in the sequencer node for transaction successfully \
         injected in the observer"

(* TODO: https://gitlab.com/tezos/tezos/-/issues/7215
   This test passes for the threshold encryption sequencer when
   we produce one block or three blocks before upgrading the kernel,
   but not two. This needs to be investigated. *)

(** This tests the situation where the kernel has an upgrade and the
    sequencer upgrade by following the event of the kernel. *)
let test_self_upgrade_kernel =
  (* Add a delay between first block and activation timestamp. *)
  let genesis_timestamp =
    Client.(At (Time.of_notation_exn "2020-01-01T00:00:00Z"))
  in
  let activation_timestamp = "2020-01-01T00:00:10Z" in
  register_both
    ~genesis_timestamp
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "upgrade"; "self"]
    ~title:"EVM Kernel can upgrade to itself"
  @@ fun {
           sc_rollup_node;
           l1_contracts;
           sc_rollup_address;
           client;
           sequencer;
           proxy;
           observer;
           _;
         }
             _protocol ->
  (* Sends the upgrade to L1, but not to the sequencer. *)
  let* () =
    upgrade
      ~sc_rollup_node
      ~sc_rollup_address
      ~admin:Constant.bootstrap2.public_key_hash
      ~admin_contract:l1_contracts.admin
      ~client
      ~upgrade_to:Constant.WASM.evm_kernel
      ~activation_timestamp
  in

  (* Per the activation timestamp, the state will remain synchronised until
     the kernel is upgraded. *)
  let* _ =
    repeat 2 (fun () ->
        let* _ =
          Rpc.produce_block ~timestamp:"2020-01-01T00:00:05Z" sequencer
        in
        unit)
  in

  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy ()
  and* _upgrade_info = Evm_node.wait_for_pending_upgrade sequencer
  and* _upgrade_info_observer = Evm_node.wait_for_pending_upgrade observer in

  let* () =
    check_head_consistency
      ~left:sequencer
      ~right:proxy
      ~error_msg:"The head should be the same before the upgrade"
      ()
  in

  (* Produce a block after activation timestamp, both the rollup
     node and the sequencer will upgrade to itself. *)
  let* _ =
    repeat 2 (fun () ->
        let* _ =
          Rpc.produce_block ~timestamp:"2020-01-01T00:00:15Z" sequencer
        in
        unit)
  and* _ = Evm_node.wait_for_successful_upgrade sequencer
  and* _ = Evm_node.wait_for_successful_upgrade observer in
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in

  let* () =
    check_head_consistency
      ~left:sequencer
      ~right:proxy
      ~error_msg:"The head should be the same after the upgrade"
      ()
  in

  unit

(** This tests the situation where the kernel has an upgrade and the
    sequencer upgrade by following the event of the kernel. *)
let test_upgrade_kernel_auto_sync =
  (* Add a delay between first block and activation timestamp. *)
  let genesis_timestamp =
    Client.(At (Time.of_notation_exn "2020-01-01T00:00:00Z"))
  in
  let activation_timestamp = "2020-01-01T00:00:10Z" in
  register_both
    ~genesis_timestamp
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "upgrade"; "auto"; "sync"]
    ~title:"Rollup-node kernel upgrade is applied to the sequencer state."
  @@ fun {
           sc_rollup_node;
           l1_contracts;
           sc_rollup_address;
           client;
           sequencer;
           proxy;
           _;
         }
             _protocol ->
  (* Sends the upgrade to L1, but not to the sequencer. *)
  let* () =
    upgrade
      ~sc_rollup_node
      ~sc_rollup_address
      ~admin:Constant.bootstrap2.public_key_hash
      ~admin_contract:l1_contracts.admin
      ~client
      ~upgrade_to:Constant.WASM.evm_kernel
      ~activation_timestamp
  in

  (* Per the activation timestamp, the state will remain synchronised until
     the kernel is upgraded. *)
  let* _ =
    repeat 2 (fun () ->
        let*@ _ =
          Rpc.produce_block ~timestamp:"2020-01-01T00:00:05Z" sequencer
        in
        unit)
  in
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in

  let* () =
    check_head_consistency
      ~left:sequencer
      ~right:proxy
      ~error_msg:"The head should be the same before the upgrade"
      ()
  in

  (* Produce a block after activation timestamp, both the rollup
     node and the sequencer will upgrade to debug kernel and
     therefore not produce the block. *)
  let* _ =
    repeat 2 (fun () ->
        let*@ _ =
          Rpc.produce_block ~timestamp:"2020-01-01T00:00:15Z" sequencer
        in
        unit)
  in
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in

  let* () =
    check_head_consistency
      ~left:sequencer
      ~right:proxy
      ~error_msg:"The head should be the same after the upgrade"
      ()
  in

  unit

let test_delayed_transfer_timeout =
  register_both
    ~delayed_inbox_timeout:3
    ~delayed_inbox_min_levels:1
    ~da_fee:arb_da_fee_for_delayed_inbox
    ~tags:["evm"; "sequencer"; "delayed_inbox"; "timeout"]
    ~title:"Delayed transaction timeout"
  @@ fun {
           client;
           node = _;
           l1_contracts;
           sc_rollup_address;
           sc_rollup_node;
           sequencer;
           proxy;
           observer = _;
         }
             _protocol ->
  (* Kill the sequencer *)
  let* () = Evm_node.terminate sequencer in
  let endpoint = Evm_node.endpoint proxy in
  let* _ = next_rollup_node_level ~sc_rollup_node ~client in
  let sender = Eth_account.bootstrap_accounts.(0).address in
  let _ = Rpc.block_number proxy in
  let receiver = Eth_account.bootstrap_accounts.(1).address in
  let* sender_balance_prev = Eth_cli.balance ~account:sender ~endpoint in
  let* receiver_balance_prev = Eth_cli.balance ~account:receiver ~endpoint in
  (* This is a transfer from Eth_account.bootstrap_accounts.(0) to
     Eth_account.bootstrap_accounts.(1). *)
  let raw_transfer =
    "f86d80843b9aca00825b0494b53dc01974176e5dff2298c5a94343c2585e3c54880de0b6b3a764000080820a96a07a3109107c6bd1d555ce70d6253056bc18996d4aff4d4ea43ff175353f49b2e3a05f9ec9764dc4a3c3ab444debe2c3384070de9014d44732162bb33ee04da187ef"
  in
  let* _hash =
    send_raw_transaction_to_delayed_inbox
      ~sc_rollup_node
      ~client
      ~l1_contracts
      ~sc_rollup_address
      raw_transfer
  in
  (* Bake a few blocks, should be enough for the tx to time out and be
     forced *)
  let* _ =
    repeat 5 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  let* sender_balance_next = Eth_cli.balance ~account:sender ~endpoint in
  let* receiver_balance_next = Eth_cli.balance ~account:receiver ~endpoint in
  Check.((sender_balance_prev <> sender_balance_next) Wei.typ)
    ~error_msg:"Balance should be updated" ;
  Check.((receiver_balance_prev <> receiver_balance_next) Wei.typ)
    ~error_msg:"Balance should be updated" ;
  Check.((sender_balance_prev > sender_balance_next) Wei.typ)
    ~error_msg:"Expected a smaller balance" ;
  Check.((receiver_balance_next > receiver_balance_prev) Wei.typ)
    ~error_msg:"Expected a bigger balance" ;
  unit

let test_delayed_transfer_timeout_fails_l1_levels =
  register_both
    ~delayed_inbox_timeout:3
    ~delayed_inbox_min_levels:20
    ~da_fee:arb_da_fee_for_delayed_inbox
    ~tags:["evm"; "sequencer"; "delayed_inbox"; "timeout"; "min_levels"]
    ~title:"Delayed transaction timeout considers l1 level"
  @@ fun {
           client;
           node = _;
           l1_contracts;
           sc_rollup_address;
           sc_rollup_node;
           sequencer;
           proxy;
           observer = _;
         }
             _protocol ->
  (* Kill the sequencer *)
  let* () = Evm_node.terminate sequencer in
  let endpoint = Evm_node.endpoint proxy in
  let* _ = next_rollup_node_level ~sc_rollup_node ~client in
  let sender = Eth_account.bootstrap_accounts.(0).address in
  let _ = Rpc.block_number proxy in
  let receiver = Eth_account.bootstrap_accounts.(1).address in
  let* sender_balance_prev = Eth_cli.balance ~account:sender ~endpoint in
  let* receiver_balance_prev = Eth_cli.balance ~account:receiver ~endpoint in
  (* This is a transfer from Eth_account.bootstrap_accounts.(0) to
     Eth_account.bootstrap_accounts.(1). *)
  let raw_transfer =
    "f86d80843b9aca00825b0494b53dc01974176e5dff2298c5a94343c2585e3c54880de0b6b3a764000080820a96a07a3109107c6bd1d555ce70d6253056bc18996d4aff4d4ea43ff175353f49b2e3a05f9ec9764dc4a3c3ab444debe2c3384070de9014d44732162bb33ee04da187ef"
  in
  let* _hash =
    send_raw_transaction_to_delayed_inbox
      ~sc_rollup_node
      ~client
      ~l1_contracts
      ~sc_rollup_address
      raw_transfer
  in
  (* Bake a few blocks, should be enough for the tx to time out in terms
     of wall time, but not in terms of L1 levels.
     Note that this test is almost the same as the one where the tx
     times out, only difference being the value of [delayed_inbox_min_levels].
  *)
  let* _ =
    repeat 5 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  let* sender_balance_next = Eth_cli.balance ~account:sender ~endpoint in
  let* receiver_balance_next = Eth_cli.balance ~account:receiver ~endpoint in
  Check.((sender_balance_prev = sender_balance_next) Wei.typ)
    ~error_msg:"Sender balance should be the same (prev %L = next %R)" ;
  Check.((receiver_balance_prev = receiver_balance_next) Wei.typ)
    ~error_msg:"Receiver balance should be the same (prev %L = next %R)" ;
  (* Wait until it's forced *)
  let* _ =
    repeat 15 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  let* sender_balance_next = Eth_cli.balance ~account:sender ~endpoint in
  let* receiver_balance_next = Eth_cli.balance ~account:receiver ~endpoint in
  Check.((sender_balance_prev > sender_balance_next) Wei.typ)
    ~error_msg:"Expected a smaller sender balance (prev %L > next %R)" ;
  Check.((receiver_balance_next > receiver_balance_prev) Wei.typ)
    ~error_msg:"Expected a bigger receiver balance (next %L > prev %R)" ;
  unit

(** This tests the situation where force kernel upgrade happens too soon. *)
let test_force_kernel_upgrade_too_early =
  (* Add a delay between first block and activation timestamp. *)
  let genesis_timestamp =
    Client.(At (Time.of_notation_exn "2020-01-10T00:00:00Z"))
  in
  register_both
    ~genesis_timestamp
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "upgrade"; "force"]
    ~title:"Force kernel upgrade fail too early"
    ~uses:(fun protocol -> Constant.WASM.ghostnet_evm_kernel :: uses protocol)
  @@ fun {
           sc_rollup_node;
           l1_contracts;
           sc_rollup_address;
           client;
           sequencer;
           proxy;
           _;
         }
             _protocol ->
  (* Wait for the sequencer to publish its genesis block. *)
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in
  let* proxy =
    Evm_node.init
      ~mode:(Proxy {devmode = true})
      (Sc_rollup_node.endpoint sc_rollup_node)
  in

  (* Assert the kernel version is the same at start up. *)
  let*@ sequencer_kernelVersion = Rpc.tez_kernelVersion sequencer in
  let*@ proxy_kernelVersion = Rpc.tez_kernelVersion proxy in
  Check.((sequencer_kernelVersion = proxy_kernelVersion) string)
    ~error_msg:"Kernel versions should be the same at start up" ;

  (* Activation timestamp is 1 day after the genesis. Therefore, it cannot
     be forced now. *)
  let activation_timestamp = "2020-01-11T00:00:00Z" in
  (* Sends the upgrade to L1 and sequencer. *)
  let* () =
    upgrade
      ~sc_rollup_node
      ~sc_rollup_address
      ~admin:Constant.bootstrap2.public_key_hash
      ~admin_contract:l1_contracts.admin
      ~client
      ~upgrade_to:Constant.WASM.ghostnet_evm_kernel
      ~activation_timestamp
  in

  (* Now we try force the kernel upgrade via an external message. *)
  let* () = force_kernel_upgrade ~sc_rollup_address ~sc_rollup_node ~client in

  (* Assert the kernel version are still the same. *)
  let*@ sequencer_kernelVersion = Rpc.tez_kernelVersion sequencer in
  let*@ new_proxy_kernelVersion = Rpc.tez_kernelVersion proxy in
  Check.((sequencer_kernelVersion = new_proxy_kernelVersion) string)
    ~error_msg:"The force kernel ugprade should have failed" ;
  unit

(** This tests the situation where the kernel does not produce blocks but
    still can be forced to upgrade via an external message. *)
let test_force_kernel_upgrade =
  (* Add a delay between first block and activation timestamp. *)
  let genesis_timestamp =
    Client.(At (Time.of_notation_exn "2020-01-10T00:00:00Z"))
  in
  register_both
    ~genesis_timestamp
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "upgrade"; "force"]
    ~title:"Force kernel upgrade"
    ~uses:(fun protocol -> Constant.WASM.ghostnet_evm_kernel :: uses protocol)
  @@ fun {
           sc_rollup_node;
           l1_contracts;
           sc_rollup_address;
           client;
           sequencer;
           proxy;
           _;
         }
             _protocol ->
  (* Wait for the sequencer to publish its genesis block. *)
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in
  let* proxy =
    Evm_node.init
      ~mode:(Proxy {devmode = true})
      (Sc_rollup_node.endpoint sc_rollup_node)
  in

  (* Assert the kernel version is the same at start up. *)
  let*@ sequencer_kernelVersion = Rpc.tez_kernelVersion sequencer in
  let*@ proxy_kernelVersion = Rpc.tez_kernelVersion proxy in
  Check.((sequencer_kernelVersion = proxy_kernelVersion) string)
    ~error_msg:"Kernel versions should be the same at start up" ;

  (* Activation timestamp is 1 day before the genesis. Therefore, it can
     be forced immediatly. *)
  let activation_timestamp = "2020-01-09T00:00:00Z" in
  (* Sends the upgrade to L1 and sequencer. *)
  let* () =
    upgrade
      ~sc_rollup_node
      ~sc_rollup_address
      ~admin:Constant.bootstrap2.public_key_hash
      ~admin_contract:l1_contracts.admin
      ~client
      ~upgrade_to:Constant.WASM.ghostnet_evm_kernel
      ~activation_timestamp
  in

  (* We bake a few blocks. As the sequencer is not producing anything, the
     kernel will not upgrade. *)
  let* () =
    repeat 5 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  (* Assert the kernel version is the same, it proves the upgrade did not
      happen. *)
  let*@ sequencer_kernelVersion = Rpc.tez_kernelVersion sequencer in
  let*@ proxy_kernelVersion = Rpc.tez_kernelVersion proxy in
  Check.((sequencer_kernelVersion = proxy_kernelVersion) string)
    ~error_msg:"Kernel versions should be the same even after the message" ;

  (* Now we force the kernel upgrade via an external message. They will
     become unsynchronised. *)
  let* () = force_kernel_upgrade ~sc_rollup_address ~sc_rollup_node ~client in

  (* Assert the kernel version are now different, it shows that only the rollup
     node upgraded. *)
  let*@ sequencer_kernelVersion = Rpc.tez_kernelVersion sequencer in
  let*@ new_proxy_kernelVersion = Rpc.tez_kernelVersion proxy in
  Check.((sequencer_kernelVersion <> new_proxy_kernelVersion) string)
    ~error_msg:"Kernel versions should be different after forced upgrade" ;
  Check.((sequencer_kernelVersion = proxy_kernelVersion) string)
    ~error_msg:"Sequencer should be on the previous version" ;
  unit

let test_external_transaction_to_delayed_inbox_fails =
  (* We have a da_fee set to zero here. This is because the proxy will perform
     validation on the tx before adding it the transaction pool. This will fail
     due to 'gas limit too low' if the da fee is set.

     Since we want to test what happens when the tx is actually submitted, we
     bypass the da fee check here. *)
  register_both
    ~minimum_base_fee_per_gas:base_fee_for_hardcoded_tx
    ~time_between_blocks:Nothing
    ~bootstrap_accounts:Eth_account.lots_of_address
    ~tags:["evm"; "sequencer"; "delayed_inbox"; "external"]
    ~title:"Sending an external transaction to the delayed inbox fails"
  @@ fun {client; sequencer; proxy; sc_rollup_node; _} _protocol ->
  let* () = Evm_node.wait_for_blueprint_injected ~timeout:5. sequencer 0 in
  (* Bake a couple more levels for the blueprint to be final *)
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in
  let raw_tx, _ = read_tx_from_file () |> List.hd in
  let*@ tx_hash = Rpc.send_raw_transaction ~raw_tx proxy in
  (* Bake enough levels to make sure the transaction would be processed
     if added *)
  let* () =
    repeat 10 (fun () ->
        let*@ _ = Rpc.produce_block sequencer in
        let* _ = next_rollup_node_level ~client ~sc_rollup_node in
        unit)
  in
  (* Response should be none *)
  let*@ response = Rpc.get_transaction_receipt ~tx_hash proxy in
  assert (Option.is_none response) ;
  let*@ response = Rpc.get_transaction_receipt ~tx_hash sequencer in
  assert (Option.is_none response) ;
  unit

let test_delayed_inbox_flushing =
  (* Setup with a short wall time timeout but a significant lower bound of
     L1 levels needed for timeout.
     The idea is to send 2 transactions to the delayed inbox, having one
     time out and check that the second is also forced.
     We set [delayed_inbox_min_levels] to a value that is large enough
     to give us time to send the second one while the first one is not
     timed out yet.
  *)
  register_both
    ~delayed_inbox_timeout:1
    ~delayed_inbox_min_levels:20
    ~da_fee:arb_da_fee_for_delayed_inbox
    ~tags:["evm"; "sequencer"; "delayed_inbox"; "timeout"]
    ~title:"Delayed inbox flushing"
  @@ fun {
           client;
           node = _;
           l1_contracts;
           sc_rollup_address;
           sc_rollup_node;
           sequencer;
           proxy;
           observer = _;
         }
             _protocol ->
  (* Kill the sequencer *)
  let* () = Evm_node.terminate sequencer in
  let endpoint = Evm_node.endpoint proxy in
  let* _ = next_rollup_node_level ~sc_rollup_node ~client in
  let sender = Eth_account.bootstrap_accounts.(0).address in
  let _ = Rpc.block_number proxy in
  let receiver = Eth_account.bootstrap_accounts.(1).address in
  let* sender_balance_prev = Eth_cli.balance ~account:sender ~endpoint in
  let* receiver_balance_prev = Eth_cli.balance ~account:receiver ~endpoint in
  (* Send the first transaction, this one is dummy (from [100-inputs-for-proxy])
     as we only use it for the timeout. *)
  let tx1 =
    "f863808252088252089400000000000000000000000000000000000000000a80820a95a0aedf43a765be7e57167a732fb460bec1c73f29bc8c2f7e753b652918ea19cd8da04062403d1ddcdf9d80dc69cab4509400a21604f0ec42f82289597f8476792648"
  in
  let* _hash =
    send_raw_transaction_to_delayed_inbox
      ~sc_rollup_node
      ~client
      ~l1_contracts
      ~sc_rollup_address
      tx1
  in
  (* Bake a few blocks but not enough for the first tx to be forced! *)
  let* _ =
    repeat 10 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  (* Send the second transaction, a transfer from
     Eth_account.bootstrap_accounts.(0) to Eth_account.bootstrap_accounts.(1).
  *)
  let tx2 =
    "f86d80843b9aca00825b0494b53dc01974176e5dff2298c5a94343c2585e3c54880de0b6b3a764000080820a96a07a3109107c6bd1d555ce70d6253056bc18996d4aff4d4ea43ff175353f49b2e3a05f9ec9764dc4a3c3ab444debe2c3384070de9014d44732162bb33ee04da187ef"
  in
  let* _hash =
    send_raw_transaction_to_delayed_inbox
      ~sc_rollup_node
      ~client
      ~l1_contracts
      ~sc_rollup_address
      tx2
  in
  (* Bake a few more blocks to make sure the first tx times out, but not
     the second one. However, the latter should also be included. *)
  let* _ =
    repeat 10 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  let* sender_balance_next = Eth_cli.balance ~account:sender ~endpoint in
  let* receiver_balance_next = Eth_cli.balance ~account:receiver ~endpoint in
  Check.((sender_balance_prev <> sender_balance_next) Wei.typ)
    ~error_msg:"Balance should be updated" ;
  Check.((receiver_balance_prev <> receiver_balance_next) Wei.typ)
    ~error_msg:"Balance should be updated" ;
  Check.((sender_balance_prev > sender_balance_next) Wei.typ)
    ~error_msg:"Expected a smaller balance" ;
  Check.((receiver_balance_next > receiver_balance_prev) Wei.typ)
    ~error_msg:"Expected a bigger balance" ;
  unit

let test_no_automatic_block_production =
  register_both
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "block"]
    ~title:"No automatic block production"
  @@ fun {sequencer; _} _protocol ->
  let*@ before_head = Rpc.get_block_by_number ~block:"latest" sequencer in
  let transfer =
    let* tx_hash =
      Eth_cli.transaction_send
        ~source_private_key:Eth_account.(bootstrap_accounts.(0).private_key)
        ~to_public_key:Eth_account.(bootstrap_accounts.(0).address)
        ~value:(Wei.of_eth_int 1)
        ~endpoint:(Evm_node.endpoint sequencer)
        ()
    in
    return (Some tx_hash)
  in
  let timeout =
    let* () = Lwt_unix.sleep 15. in
    return None
  in
  let* tx_hash = Lwt.pick [transfer; timeout] in

  let*@ after_head = Rpc.get_block_by_number ~block:"latest" sequencer in
  (* As the time between blocks is "none", the sequencer should not produce a block
     even if we send a transaction. *)
  Check.((before_head.number = after_head.number) int32)
    ~error_msg:"No block production expected" ;
  (* The transaction hash is not returned as no receipt is produced, and eth-cli
     awaits for the receipt. *)
  Check.is_true
    (Option.is_none tx_hash)
    ~error_msg:"No transaction hash expected" ;
  unit

let test_migration_from_ghostnet =
  (* Creates a sequencer using prod version and ghostnet kernel. *)
  register_test
    ~threshold_encryption:false
    ~time_between_blocks:Nothing
    ~kernel:Constant.WASM.ghostnet_evm_kernel
    ~devmode:false
    ~max_blueprints_lag:0
    ~tags:["evm"; "sequencer"; "upgrade"; "migration"; "ghostnet"]
    ~title:"Sequencer can upgrade from ghostnet"
    ~uses:(fun protocol -> Constant.WASM.ghostnet_evm_kernel :: uses protocol)
  @@ fun {
           sequencer;
           client;
           sc_rollup_node;
           sc_rollup_address;
           l1_contracts;
           proxy;
           _;
         }
             _protocol ->
  let* _ = next_rollup_node_level ~sc_rollup_node ~client in
  (* Check kernelVersion. *)
  let* _kernel_version =
    check_kernel_version
      ~evm_node:sequencer
      ~equal:true
      Constant.WASM.ghostnet_evm_commit
  in
  let* _kernel_version =
    check_kernel_version
      ~evm_node:proxy
      ~equal:true
      Constant.WASM.ghostnet_evm_commit
  in

  (* Produces a few blocks. *)
  let* _ =
    repeat 2 (fun () ->
        let*@ _ = Rpc.produce_block sequencer in
        unit)
  in
  let* () =
    repeat 4 (fun () ->
        let* _ = next_rollup_node_level ~client ~sc_rollup_node in
        unit)
  in
  (* Check the consistency. *)
  let* () = check_head_consistency ~left:proxy ~right:sequencer () in
  (* Sends upgrade to current version. *)
  let* () =
    upgrade
      ~sc_rollup_node
      ~sc_rollup_address
      ~admin:Constant.bootstrap2.public_key_hash
      ~admin_contract:l1_contracts.admin
      ~client
      ~upgrade_to:Constant.WASM.evm_kernel
      ~activation_timestamp:"0"
  in
  (* Bakes 2 blocks for the event follower to see the upgrade. *)
  let* _ =
    repeat 2 (fun () ->
        let* _ = next_rollup_node_level ~client ~sc_rollup_node in
        unit)
  in
  (* Produce a block to trigger the upgrade. *)
  let*@ _ = Rpc.produce_block sequencer in
  let* _ =
    repeat 4 (fun () ->
        let* _ = next_rollup_node_level ~client ~sc_rollup_node in
        unit)
  in
  (* Check that the prod sequencer has updated. *)
  let* new_kernel_version =
    check_kernel_version
      ~evm_node:sequencer
      ~equal:false
      Constant.WASM.ghostnet_evm_commit
  in
  (* Runs sequencer and proxy with --devmode. *)
  let* () = Evm_node.terminate proxy in
  let* () = Evm_node.terminate sequencer in
  (* Manually put `--devmode` to use the same command line. *)
  let* () = Evm_node.run ~extra_arguments:["--devmode"] proxy in
  let* () = Evm_node.run ~extra_arguments:["--devmode"] sequencer in
  (* Check that new sequencer and proxy are on a new version. *)
  let* _kernel_version =
    check_kernel_version ~evm_node:sequencer ~equal:true new_kernel_version
  in
  let* _kernel_version =
    check_kernel_version ~evm_node:proxy ~equal:true new_kernel_version
  in
  (* Check the consistency. *)
  let* () = check_head_consistency ~left:proxy ~right:sequencer () in
  (* Produces a few blocks. *)
  let* _ =
    repeat 2 (fun () ->
        let*@ _ = Rpc.produce_block sequencer in
        unit)
  in
  let* () =
    repeat 4 (fun () ->
        let* _ = next_rollup_node_level ~client ~sc_rollup_node in
        unit)
  in
  (* Final consistency check. *)
  check_head_consistency ~left:sequencer ~right:proxy ()

(** This tests the situation where the kernel has an upgrade and the
    sequencer upgrade by following the event of the kernel. *)
let test_sequencer_upgrade =
  register_both
    ~sequencer:Constant.bootstrap1
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "sequencer_upgrade"; "auto"; "sync"; Tag.flaky]
    ~title:
      "Rollup-node sequencer upgrade is applied to the sequencer local state."
  @@ fun {
           sc_rollup_node;
           l1_contracts;
           sc_rollup_address;
           client;
           sequencer;
           proxy;
           observer;
           _;
         }
             _protocol ->
  (* produce an initial block *)
  let*@ _lvl = Rpc.produce_block sequencer in
  let* () = bake_until_sync ~proxy ~sequencer ~sc_rollup_node ~client () in
  let* () =
    check_head_consistency
      ~left:proxy
      ~right:sequencer
      ~error_msg:"The head should be the same before the upgrade"
      ()
  in
  let*@ previous_proxy_head = Rpc.get_block_by_number ~block:"latest" proxy in
  (* Sends the upgrade to L1. *)
  Log.info "Sending the sequencer upgrade to the L1 contract" ;
  let new_sequencer_key = Constant.bootstrap2.alias in
  let* _upgrade_info = Evm_node.wait_for_evm_event Sequencer_upgrade sequencer
  and* _upgrade_info_observer =
    Evm_node.wait_for_evm_event Sequencer_upgrade observer
  and* () =
    let* () =
      sequencer_upgrade
        ~sc_rollup_address
        ~sequencer_admin:Constant.bootstrap2.alias
        ~sequencer_governance_contract:l1_contracts.sequencer_governance
        ~pool_address:Eth_account.bootstrap_accounts.(0).address
        ~client
        ~upgrade_to:new_sequencer_key
        ~activation_timestamp:"0"
    in
    (* 2 block so the sequencer sees the event from the rollup
       node. *)
    repeat 2 (fun () ->
        let* _ = next_rollup_node_level ~client ~sc_rollup_node in
        unit)
  in
  let* () =
    check_head_consistency
      ~left:proxy
      ~right:sequencer
      ~error_msg:"The head should be the same after the upgrade"
      ()
  in
  let nb_block = 4l in
  (* apply the upgrade in the kernel  *)
  let* _ = next_rollup_node_level ~client ~sc_rollup_node in
  (*   produce_block fails because sequencer changed *)
  let*@? _err = Rpc.produce_block sequencer in
  let* () =
    repeat 5 (fun () ->
        let* _ = next_rollup_node_level ~client ~sc_rollup_node in
        unit)
  in
  let*@ proxy_head = Rpc.get_block_by_number ~block:"latest" proxy in
  Check.((previous_proxy_head.hash = proxy_head.hash) string)
    ~error_msg:
      "The proxy should not have progessed because no block have been produced \
       by the current sequencer." ;
  (* Check that even the evm-node sequencer itself refuses the blocks as they do
     not respect the sequencer's signature. *)
  let* () =
    check_head_consistency
      ~left:proxy
      ~right:sequencer
      ~error_msg:
        "The head should be the same after the sequencer tried to produce \
         blocks, they are are disregarded."
      ()
  in
  Log.info
    "Stopping current sequencer and starting a new one with new sequencer key" ;
  let new_sequencer =
    let mode =
      match Evm_node.mode sequencer with
      | Sequencer config ->
          Evm_node.Sequencer
            {
              config with
              sequencer = new_sequencer_key;
              private_rpc_port = Some (Port.fresh ());
            }
      | Threshold_encryption_sequencer config ->
          Evm_node.Threshold_encryption_sequencer
            {
              config with
              sequencer = new_sequencer_key;
              private_rpc_port = Some (Port.fresh ());
            }
      | _ -> Test.fail "impossible case, it's a sequencer"
    in
    Evm_node.create ~mode (Sc_rollup_node.endpoint sc_rollup_node)
  in
  let* () = Process.check @@ Evm_node.spawn_init_config new_sequencer in

  let* _ = Evm_node.wait_for_shutdown_event sequencer
  and* () =
    let* () =
      Evm_node.init_from_rollup_node_data_dir
        ~devmode:true
        new_sequencer
        sc_rollup_node
    in
    let* () = Evm_node.run new_sequencer in
    let* () =
      repeat (Int32.to_int nb_block) (fun () ->
          let* _ = Rpc.produce_block new_sequencer in
          unit)
    in
    let* () =
      repeat 5 (fun () ->
          let* _ = next_rollup_node_level ~client ~sc_rollup_node in
          unit)
    in
    let previous_proxy_head = proxy_head in
    let* () =
      check_head_consistency
        ~left:proxy
        ~right:new_sequencer
        ~error_msg:
          "The head should be the same after blocks produced by the new \
           sequencer"
        ()
    in
    let*@ proxy_head = Rpc.get_block_by_number ~block:"latest" proxy in
    Check.(
      (Int32.add previous_proxy_head.number nb_block = proxy_head.number) int32)
      ~error_msg:
        "The block number should have incremented (previous: %L, current: %R)" ;
    unit
  in
  unit

(** this test the situation where a sequencer diverged from it
    source. To obtain that we create two sequencers, one is going to
    diverged from the other. *)
let test_sequencer_diverge =
  register_both
    ~sequencer:Constant.bootstrap1
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "diverge"]
    ~title:"Runs two sequencers, one diverge and stop"
  @@ fun {sc_rollup_node; client; sequencer; observer; _} _protocol ->
  let* () =
    repeat 4 (fun () ->
        let*@ _l2_level = Rpc.produce_block sequencer in
        unit)
  in
  let* () =
    (* 3 to make sure it is seen by the rollup node, 2 to finalize it *)
    repeat 5 (fun () ->
        let* _l1_level = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  let* sequencer_bis =
    let* mode =
      match Evm_node.mode sequencer with
      | Sequencer config ->
          return
          @@ Evm_node.Sequencer
               {config with private_rpc_port = Some (Port.fresh ())}
      | Threshold_encryption_sequencer config ->
          let sequencer_sidecar_port = Some (Port.fresh ()) in
          let sequencer_sidecar =
            Dsn_node.sequencer ?rpc_port:sequencer_sidecar_port ()
          in
          let* () = Dsn_node.start sequencer_sidecar in
          return
          @@ Evm_node.Threshold_encryption_sequencer
               {
                 config with
                 private_rpc_port = Some (Port.fresh ());
                 sequencer_sidecar_endpoint =
                   Dsn_node.endpoint sequencer_sidecar;
               }
      | _ -> Test.fail "impossible case, it's a sequencer"
    in
    return @@ Evm_node.create ~mode (Sc_rollup_node.endpoint sc_rollup_node)
  in
  let* () = Process.check @@ Evm_node.spawn_init_config sequencer_bis in
  let observer_bis =
    Evm_node.create
      ~mode:(Evm_node.mode observer)
      (Evm_node.endpoint sequencer_bis)
  in
  let* () = Process.check @@ Evm_node.spawn_init_config observer_bis in
  let* () =
    Evm_node.init_from_rollup_node_data_dir
      ~devmode:true
      sequencer_bis
      sc_rollup_node
  in
  let diverged_and_shutdown sequencer observer =
    let* _ = Evm_node.wait_for_diverged sequencer
    and* _ = Evm_node.wait_for_shutdown_event sequencer
    and* _ = Evm_node.wait_for_diverged observer
    and* _ = Evm_node.wait_for_shutdown_event observer in
    unit
  in
  let* () = Evm_node.run sequencer_bis in
  let* () = Evm_node.run observer_bis in
  let* () =
    Lwt.pick
      [
        diverged_and_shutdown sequencer observer;
        diverged_and_shutdown sequencer_bis observer_bis;
      ]
  and* () =
    (* diff timestamp to differ *)
    let* _ = Rpc.produce_block ~timestamp:"0" sequencer
    and* _ = Rpc.produce_block ~timestamp:"1" sequencer_bis in
    repeat 5 (fun () ->
        let* _ = next_rollup_node_level ~client ~sc_rollup_node in
        unit)
  in
  unit

(** This test that the sequencer evm node can catchup event from the
    rollup node. *)
let test_sequencer_can_catch_up_on_event =
  register_both
    ~sequencer:Constant.bootstrap1
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "event"]
    ~title:"Evm node can catchup event from the rollup node"
  @@ fun {sc_rollup_node; client; sequencer; proxy; observer; _} _protocol ->
  let* () =
    repeat 2 (fun () ->
        let* _ = Rpc.produce_block sequencer in
        unit)
  in
  let* () = bake_until_sync ~sequencer ~sc_rollup_node ~proxy ~client () in
  let* _ = Rpc.produce_block sequencer in
  let*@ last_produced_block = Rpc.block_number sequencer in
  let* () =
    Evm_node.wait_for_blueprint_injected
      sequencer
      ~timeout:5.
      (Int32.to_int last_produced_block)
  in
  let* () = Evm_node.terminate sequencer in
  let* () = Evm_node.terminate observer in
  let* () =
    (* produces some blocks so the rollup node applies latest produced block. *)
    repeat 4 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  let check json =
    let open JSON in
    match as_list (json |-> "event") with
    | [number; hash] ->
        let number = as_int number in
        let hash = as_string hash in
        if number = Int32.to_int last_produced_block then Some (number, hash)
        else None
    | _ ->
        Test.fail
          ~__LOC__
          "invalid json for the evm event kind blueprint applied"
  in
  let* _json = Evm_node.wait_for_evm_event ~check Blueprint_applied sequencer
  and* _json_observer =
    Evm_node.wait_for_evm_event ~check Blueprint_applied observer
  and* () =
    let* () = Evm_node.run sequencer in
    Evm_node.run observer
  in
  let* () = check_head_consistency ~left:proxy ~right:sequencer () in
  unit

let test_sequencer_dont_read_level_twice =
  register_both
    ~sequencer:Constant.bootstrap1
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "event"; Tag.slow]
    ~title:"Evm node don't read the same level twice"
  @@ fun {
           sc_rollup_node;
           client;
           sequencer;
           proxy;
           l1_contracts;
           sc_rollup_address;
           _;
         }
             _protocol ->
  (* We deposit some Tez to the rollup *)
  let* () =
    send_deposit_to_delayed_inbox
      ~amount:Tez.(of_int 16)
      ~l1_contracts
      ~depositor:Constant.bootstrap5
      ~receiver:Eth_account.bootstrap_accounts.(1).address
      ~sc_rollup_node
      ~sc_rollup_address
      client
  in

  (* We bake two blocks, so thet the EVM node can process the deposit and
     create a blueprint with it. *)
  let* _ = next_rollup_node_level ~sc_rollup_node ~client in
  let* _ = next_rollup_node_level ~sc_rollup_node ~client in

  (* We expect the deposit to be in this block. *)
  let* _ = Rpc.produce_block sequencer in

  let*@ block = Rpc.get_block_by_number ~block:Int.(to_string 1) sequencer in
  let nb_transactions =
    match block.transactions with
    | Empty -> 0
    | Hash l -> List.length l
    | Full l -> List.length l
  in
  Check.((nb_transactions = 1) int)
    ~error_msg:"Expected one transaction (the deposit), got %L" ;

  (* We kill the sequencer and restart it. As a result, its last known L1 level
     is still the L1 level of the deposit. *)
  let* _ = Evm_node.terminate sequencer in
  let* _ = Evm_node.run sequencer in

  (* We produce some empty blocks. *)
  let*@ _ = Rpc.produce_block sequencer in
  let*@ _ = Rpc.produce_block sequencer in

  (* If the logic of the sequencer is correct (i.e., it does not process the
     deposit twice), then it is possible for the rollup node to apply them. *)
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in

  unit

let test_stage_one_reboot =
  register_both
    ~sequencer:Constant.bootstrap1
    ~time_between_blocks:Nothing
    ~maximum_allowed_ticks:9_000_000_000L
    ~tags:["evm"; "sequencer"; "reboot"; Tag.slow]
    ~title:
      "Checks the stage one reboots when reading too much chunks in a single \
       L1 level"
  @@ fun {sc_rollup_node; client; sc_rollup_address; _} protocol ->
  let* chunks =
    Lwt_list.map_s (fun i ->
        Evm_node.chunk_data
          ~rollup_address:sc_rollup_address
          ~sequencer_key:Constant.bootstrap1.alias
          ~client
          ~number:i
          [])
    @@ List.init 400 Fun.id
  in
  let chunks = List.flatten chunks in
  let send_chunks chunks src =
    let messages =
      `A (List.map (fun c -> `String c) chunks)
      |> JSON.annotate ~origin:"send_message"
      |> JSON.encode
    in
    Client.Sc_rollup.send_message
      ?wait:None
      ~msg:("hex:" ^ messages)
      ~src
      client
  in
  let rec split_chunks acc chunks =
    match chunks with
    | [] -> acc
    | _ ->
        let messages, rem = Tezos_stdlib.TzList.split_n 100 chunks in
        split_chunks (messages :: acc) rem
  in
  let splitted_messages = split_chunks [] chunks in
  let* () =
    Lwt_list.iteri_s
      (fun i messages -> send_chunks messages Account.Bootstrap.keys.(i).alias)
      splitted_messages
  in
  let* total_tick_number_before_expected_reboots =
    Sc_rollup_node.RPC.call sc_rollup_node
    @@ Sc_rollup_rpc.get_global_block_total_ticks ()
  in
  let* _ = next_rollup_node_level ~client ~sc_rollup_node in
  let* total_tick_number_with_expected_reboots =
    Sc_rollup_node.RPC.call sc_rollup_node
    @@ Sc_rollup_rpc.get_global_block_total_ticks ()
  in
  let ticks_after_expected_reboot =
    total_tick_number_with_expected_reboots
    - total_tick_number_before_expected_reboots
  in

  (* The PVM takes 11G ticks for collecting inputs, 11G for a kernel_run. As such,
     an L1 level is at least 22G ticks. *)
  let ticks_per_snapshot = Sc_rollup_helpers.ticks_per_snapshot protocol in
  let min_ticks_per_l1_level = ticks_per_snapshot * 2 in
  (* If the inbox is not empty, the kernel enforces a reboot after reading it,
     to give the maximum ticks available for the first block production. *)
  let min_ticks_when_inbox_is_not_empty =
    min_ticks_per_l1_level + ticks_per_snapshot
  in
  Check.((ticks_after_expected_reboot > min_ticks_when_inbox_is_not_empty) int)
    ~error_msg:
      "The number of ticks spent during the period should be higher than %R, \
       but got %L, which implies there have been no reboot, contrary to what \
       was expected." ;
  unit

let test_blueprint_is_limited_in_size =
  register_both
    ~sequencer:Constant.bootstrap1
    ~time_between_blocks:Nothing
    ~max_number_of_chunks:2
    ~minimum_base_fee_per_gas:base_fee_for_hardcoded_tx
    ~bootstrap_accounts:Eth_account.lots_of_address
    ~tags:["evm"; "sequencer"; "blueprint"; "limit"]
    ~title:
      "Checks the sequencer doesn't produce blueprint bigger than the given \
       maximum number of chunks"
  @@ fun {sc_rollup_node; client; sequencer; _} _protocol ->
  let txs = read_tx_from_file () |> List.map (fun (tx, _hash) -> tx) in
  let* requests, hashes =
    Helpers.batch_n_transactions ~evm_node:sequencer txs
  in
  (* Each transaction is about 114 bytes, hence 100 * 114 = 11400 bytes, which
     will fit in two blueprints of two chunks each. *)
  let* () = next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client in
  let* () = next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client in
  let first_hash = List.hd hashes in
  let* level_of_first_transaction =
    let*@ receipt = Rpc.get_transaction_receipt ~tx_hash:first_hash sequencer in
    match receipt with
    | None -> Test.fail "Delayed transaction hasn't be included"
    | Some receipt -> return receipt.blockNumber
  in
  let*@ block_with_first_transaction =
    Rpc.get_block_by_number
      ~block:(Int32.to_string level_of_first_transaction)
      sequencer
  in
  (* The block containing the first transaction of the batch cannot contain the
     100 transactions of the batch, as it doesn't fit in two chunks. *)
  let block_size_of_first_transaction =
    match block_with_first_transaction.Block.transactions with
    | Block.Empty -> Test.fail "Expected a non empty block"
    | Block.Full _ ->
        Test.fail "Block is supposed to contain only transaction hashes"
    | Block.Hash hashes ->
        Check.((List.length hashes < List.length requests) int)
          ~error_msg:"Expected less than %R transactions in the block, got %L" ;
        List.length hashes
  in

  let* () = next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client in
  (* It's not clear the first transaction of the batch is applied in the first
     blueprint or the second, as it depends how the tx_pool sorts the
     transactions (by caller address). We need to check that either the previous
     block or the next block contains transactions, which puts in evidence that
     the batch has been splitted into two consecutive blueprints.
  *)
  let check_block_size block_number =
    let*@ block =
      Rpc.get_block_by_number ~block:(Int32.to_string block_number) sequencer
    in
    match block.Block.transactions with
    | Block.Empty -> return 0
    | Block.Full _ ->
        Test.fail "Block is supposed to contain only transaction hashes"
    | Block.Hash hashes -> return (List.length hashes)
  in
  let* next_block_size =
    check_block_size (Int32.succ level_of_first_transaction)
  in
  let* previous_block_size =
    check_block_size (Int32.pred level_of_first_transaction)
  in
  if next_block_size = 0 && previous_block_size = 0 then
    Test.fail
      "The sequencer didn't apply the 100 transactions in two consecutive \
       blueprints" ;
  Check.(
    (block_size_of_first_transaction + previous_block_size + next_block_size
    = List.length hashes)
      int
      ~error_msg:
        "Not all the transactions have been injected, only %L, while %R was \
         expected.") ;
  unit

let test_blueprint_limit_with_delayed_inbox =
  register_both
    ~bootstrap_accounts:Eth_account.lots_of_address
    ~sequencer:Constant.bootstrap1
    ~time_between_blocks:Nothing
    ~max_number_of_chunks:2
    ~minimum_base_fee_per_gas:base_fee_for_hardcoded_tx
    ~tags:["evm"; "sequencer"; "blueprint"; "limit"; "delayed"]
    ~title:
      "Checks the sequencer doesn't produce blueprint bigger than the given \
       maximum number of chunks and count delayed transactions size in the \
       blueprint"
  @@ fun {sc_rollup_node; client; sequencer; sc_rollup_address; l1_contracts; _}
             _protocol ->
  let txs = read_tx_from_file () |> List.map (fun (tx, _hash) -> tx) in
  (* The first 3 transactions will be sent to the delayed inbox *)
  let delayed_txs, direct_txs = Tezos_base.TzPervasives.TzList.split_n 3 txs in
  let send_to_delayed_inbox (sender, raw_tx) =
    send_raw_transaction_to_delayed_inbox
      ~wait_for_next_level:false
      ~sender
      ~sc_rollup_node
      ~sc_rollup_address
      ~client
      ~l1_contracts
      raw_tx
  in
  let* delayed_hashes =
    Lwt_list.map_s send_to_delayed_inbox
    @@ List.combine
         [Constant.bootstrap2; Constant.bootstrap3; Constant.bootstrap4]
         delayed_txs
  in
  (* Ensures the transactions are added to the rollup delayed inbox and picked
     by the sequencer *)
  let* () =
    repeat 4 (fun () ->
        let* _l1_level = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  let* _requests, _hashes =
    Helpers.batch_n_transactions ~evm_node:sequencer direct_txs
  in
  (* Due to the overapproximation of 4096 bytes per delayed transactions, there
     should be only a single delayed transaction per blueprints with 2 chunks. *)
  let* _ = next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client in
  let* _ = next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client in
  let* _ = next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client in
  (* Checks the delayed transactions and at least the first transaction from the
     batch have been applied *)
  let* block_numbers =
    Lwt_list.map_s
      (fun tx_hash ->
        let*@ receipt = Rpc.get_transaction_receipt ~tx_hash sequencer in
        match receipt with
        | None -> Test.fail "Delayed transaction hasn't be included"
        | Some receipt -> return receipt.blockNumber)
      delayed_hashes
  in
  let check_block_contains_delayed_transaction_and_transactions
      (delayed_hash, block_number) =
    let*@ block =
      Rpc.get_block_by_number ~block:(Int32.to_string block_number) sequencer
    in
    match block.Block.transactions with
    | Block.Empty -> Test.fail "Block shouldn't be empty"
    | Block.Full _ ->
        Test.fail "Block is supposed to contain only transaction hashes"
    | Block.Hash hashes ->
        if not (List.mem ("0x" ^ delayed_hash) hashes && 2 < List.length hashes)
        then
          Test.fail
            "The delayed transaction %s hasn't been included in the expected \
             block along other transactions from the pool"
            delayed_hash ;
        unit
  in
  Lwt_list.iter_s check_block_contains_delayed_transaction_and_transactions
  @@ List.combine delayed_hashes block_numbers

let test_reset =
  register_both
    ~sequencer:Constant.bootstrap1
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "reset"]
    ~title:"try to reset sequencer and observer state using the command."
  @@ fun {
           proxy;
           observer;
           sequencer;
           sc_rollup_node;
           client;
           sc_rollup_address;
           _;
         }
             _protocol ->
  let reset_level = 5 in
  let after_reset_level = 5 in
  Log.info "Producing %d level then syncing" reset_level ;
  let* () =
    repeat reset_level (fun () ->
        next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client)
  in
  let* () = bake_until_sync ~sequencer ~sc_rollup_node ~proxy ~client () in
  Log.info
    "Stopping the rollup node, then produce %d more blocks "
    (reset_level + after_reset_level) ;
  let* () = Sc_rollup_node.terminate sc_rollup_node in
  let* () =
    repeat after_reset_level (fun () ->
        next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client)
  in
  let*@ sequencer_level = Rpc.block_number sequencer in
  Check.(
    (sequencer_level = Int32.of_int (reset_level + after_reset_level)) int32)
    ~error_msg:
      "The sequencer level %L should be at %R after producing %R blocks" ;
  Log.info "Stopping sequencer and observer" ;
  let* () = Evm_node.terminate observer
  and* () = Evm_node.terminate sequencer in

  Log.info "Reset sequencer and observer state." ;
  let* () = Evm_node.reset observer ~l2_level:reset_level
  and* () = Evm_node.reset sequencer ~l2_level:reset_level in

  Log.info "Rerun rollup node, sequencer and observer." ;
  let* () =
    Sc_rollup_node.run sc_rollup_node sc_rollup_address [Log_kernel_debug]
  in
  let* () = Evm_node.run sequencer in
  let* () = Evm_node.run observer in

  Log.info "Check sequencer and observer is at %d level" reset_level ;
  let*@ sequencer_level = Rpc.block_number sequencer in
  let*@ observer_level = Rpc.block_number observer in
  Check.((sequencer_level = Int32.of_int reset_level) int32)
    ~error_msg:
      "The sequencer is at level %L, but should be at the level %R after being \
       reset." ;
  Check.((sequencer_level = observer_level) int32)
    ~error_msg:
      "The sequencer (currently at level %L) and observer ( currently at level \
       %R) should be at the same level after both being reset." ;
  let* () =
    repeat after_reset_level (fun () ->
        next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client)
  in
  let* () = bake_until_sync ~sequencer ~sc_rollup_node ~proxy ~client () in
  (* Check sequencer is at the expected level *)
  let*@ sequencer_level = Rpc.block_number sequencer in
  Check.(
    (sequencer_level = Int32.of_int (reset_level + after_reset_level)) int32)
    ~error_msg:
      "The sequencer level %L should be at %R after producing blocks after the \
       reset." ;
  unit

let test_preimages_endpoint =
  register_both
    ~sequencer:Constant.bootstrap1
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "preimages_endpoint"]
    ~title:"Sequencer use remote server to get preimages"
    ~uses:(fun protocol -> Constant.WASM.ghostnet_evm_kernel :: uses protocol)
  @@ fun {
           sc_rollup_node;
           l1_contracts;
           sc_rollup_address;
           client;
           sequencer;
           proxy;
           _;
         }
             _protocol ->
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in
  let* () = Evm_node.terminate sequencer in
  (* Prepares the sequencer without [preimages-dir], to force the use of
     preimages endpoint. *)
  let sequencer_mode_without_preimages_dir =
    match Evm_node.mode sequencer with
    | Evm_node.Sequencer mode ->
        Evm_node.Sequencer {mode with preimage_dir = None}
    | Evm_node.Threshold_encryption_sequencer mode ->
        Evm_node.Threshold_encryption_sequencer {mode with preimage_dir = None}
    | _ -> assert false
  in
  let new_sequencer =
    Evm_node.create
      ~mode:sequencer_mode_without_preimages_dir
      (Sc_rollup_node.endpoint sc_rollup_node)
  in
  let* () = Process.check @@ Evm_node.spawn_init_config new_sequencer in
  let* () =
    repeat 2 (fun () ->
        let* _ = next_rollup_node_level ~sc_rollup_node ~client in
        unit)
  in
  let* () =
    Evm_node.init_from_rollup_node_data_dir
      ~devmode:true
      new_sequencer
      sc_rollup_node
  in
  (* Sends an upgrade with new preimages. *)
  let* () =
    upgrade
      ~sc_rollup_node
      ~sc_rollup_address
      ~admin:Constant.bootstrap2.public_key_hash
      ~admin_contract:l1_contracts.admin
      ~client
      ~upgrade_to:Constant.WASM.ghostnet_evm_kernel
      ~activation_timestamp:"0"
  in
  let* _ =
    repeat 2 (fun () ->
        let* _ = next_rollup_node_level ~client ~sc_rollup_node in
        unit)
  in
  (* Create a file server that serves the preimages. *)
  let provider_port = Port.fresh () in
  let served = ref false in
  Sc_rollup_helpers.serve_files
    ~name:"preimages_server"
    ~port:provider_port
    ~root:(Sc_rollup_node.data_dir sc_rollup_node // "wasm_2_0_0")
    ~on_request:(fun _ -> served := true)
  @@ fun () ->
  let preimages_endpoint =
    sf "http://%s:%d" Constant.default_host provider_port
  in
  let* () =
    Evm_node.run
      ~extra_arguments:["--preimages-endpoint"; preimages_endpoint]
      new_sequencer
  in
  (* Produce a block so the sequencer sees the event. *)
  let* _ = next_rollup_node_level ~sc_rollup_node ~client in
  let* _ = Rpc.produce_block new_sequencer in
  Check.is_true
    !served
    ~error_msg:"The sequencer should have used the file server" ;
  unit

let test_store_smart_rollup_address =
  register_both
    ~time_between_blocks:Nothing
    ~tags:["evm"; "sequencer"; "store"]
    ~title:"Sequencer checks the smart rollup address"
    ~uses
  @@ fun {sequencer; client; node; _} _protocol ->
  (* Starting the sequencer stores the smart rollup address in the store. *)
  (* Kill the sequencer. *)
  let* () = Evm_node.terminate sequencer in
  (* Originate another rollup. *)
  let* other_rollup_address =
    originate_sc_rollup ~keys:[] ~kind:"wasm_2_0_0" ~alias:"vbot" client
  in
  let other_rollup_node =
    Sc_rollup_node.create Observer node ~base_dir:(Client.base_dir client)
  in
  let* () = Sc_rollup_node.run other_rollup_node other_rollup_address [] in
  (* Try to run the sequencer with an invalid smart rollup address. *)
  let process =
    Evm_node.spawn_run
      ~extra_arguments:
        ["--rollup-node-endpoint"; Sc_rollup_node.endpoint other_rollup_node]
      sequencer
  in
  let* () =
    Process.check_error
      ~msg:(rex "The EVM node follows the smart rollup address*")
      process
  in
  unit

let test_replay_rpc =
  register_both
    ~tags:["evm"; "rpc"; "replay"]
    ~title:"Sequencer can replay a block"
  @@ fun {sc_rollup_node; sequencer; client; proxy; _} _protocol ->
  (* Transfer funds to a random address. *)
  let address = "0xB7A97043983f24991398E5a82f63F4C58a417185" in
  let* transaction_hash =
    send_transaction
      (Eth_cli.transaction_send
         ~source_private_key:Eth_account.bootstrap_accounts.(0).private_key
         ~to_public_key:address
         ~value:(Wei.of_eth_int 10)
         ~endpoint:(Evm_node.endpoint sequencer))
      sequencer
  in
  let*@ {Transaction.blockNumber; _} =
    Rpc.get_transaction_by_hash ~transaction_hash sequencer
  in
  (* Block few levels to ensure we are replaying on an old block. *)
  let* () =
    repeat 2 (fun () ->
        next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client)
  in
  let* () = bake_until_sync ~sequencer ~sc_rollup_node ~proxy ~client () in
  let*@ original_block =
    Rpc.get_block_by_number
      ~full_tx_objects:false
      ~block:(Int32.to_string blockNumber)
      sequencer
  in
  let*@ replayed_block =
    Rpc.replay_block (Int32.to_int blockNumber) sequencer
  in
  (* Checks the block hash is the same. If so, we can assume they have the same
     state hash and transactions. *)
  Check.(
    (original_block.hash = replayed_block.hash)
      string
      ~error_msg:"Replayed block hash is %R, but the original block has %L") ;
  unit

let test_txpool_content_empty_with_legacy_encoding =
  let genesis_timestamp =
    Client.(At (Time.of_notation_exn "2020-01-01T00:00:00Z"))
  in
  let activation_timestamp = "2020-01-01T00:00:10Z" in
  register_both
    ~title:
      "`txpool_content` RPC is empty with the legacy encodings of the \
       validation"
    ~tags:["evm"; "txpool_content"; "legacy"]
    ~time_between_blocks:Nothing
    ~minimum_base_fee_per_gas:base_fee_for_hardcoded_tx
    ~uses:(fun _protocol ->
      [
        Constant.octez_evm_node;
        Constant.octez_smart_rollup_node;
        Constant.smart_rollup_installer;
        Constant.WASM.ghostnet_evm_kernel;
        Constant.WASM.evm_kernel;
      ])
    ~kernel:Constant.WASM.ghostnet_evm_kernel
    ~genesis_timestamp
  @@ fun {
           sc_rollup_node;
           l1_contracts;
           sc_rollup_address;
           client;
           sequencer;
           proxy;
           observer;
           _;
         }
             _protocol ->
  let tx1 =
    (* {
         "chainId": "1337",
         "type": "LegacyTransaction",
         "valid": true,
         "hash": "0xb4c823c72996be6f4767997f21dac443568f3d0a1cd24f3b29eeb66cb5aca2f8",
         "nonce": "0",
         "gasPrice": "100000",
         "gasLimit": "23300",
         "from": "0x6ce4d79d4E77402e1ef3417Fdda433aA744C6e1c",
         "to": "0x11D3C9168db9d12a3C591061D555870969b43dC9",
         "v": "0a96",
         "r": "4217494c4c98d5f8015399c004e088d094fcee43bcb9a4a6b29bdff27d6f1079",
         "s": "23ca4eeac30b72e7582f2fcd9a151a855ae943ffb40f4a3ef616f5ae5483a592",
         "value": "100",
         "data": ""
       } *)
    "f86480830186a0825b049411d3c9168db9d12a3c591061d555870969b43dc96480820a96a04217494c4c98d5f8015399c004e088d094fcee43bcb9a4a6b29bdff27d6f1079a023ca4eeac30b72e7582f2fcd9a151a855ae943ffb40f4a3ef616f5ae5483a592"
  in
  let*@ _ = Rpc.send_raw_transaction ~raw_tx:tx1 sequencer in
  let*@ txpool_result = Rpc.txpool_content sequencer in
  (match txpool_result with
  | [], [] -> ()
  | _ ->
      Test.fail
        "The RPC is supposed to return an empty list of pending transactions \
         in the previous kernel.") ;

  let* () =
    upgrade
      ~sc_rollup_node
      ~sc_rollup_address
      ~admin:Constant.bootstrap2.public_key_hash
      ~admin_contract:l1_contracts.admin
      ~client
      ~upgrade_to:Constant.WASM.evm_kernel
      ~activation_timestamp
  in
  (* Per the activation timestamp, the state will remain synchronised until
     the kernel is upgraded. *)
  let* _ =
    repeat 2 (fun () ->
        let* _ =
          Rpc.produce_block ~timestamp:"2020-01-01T00:00:05Z" sequencer
        in
        unit)
  in

  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy ()
  and* _upgrade_info = Evm_node.wait_for_pending_upgrade sequencer
  and* _upgrade_info_observer = Evm_node.wait_for_pending_upgrade observer in

  (* Produce a block after activation timestamp, both the rollup
     node and the sequencer will upgrade to itself. *)
  let* _ =
    repeat 2 (fun () ->
        let* _ =
          Rpc.produce_block ~timestamp:"2020-01-01T00:00:15Z" sequencer
        in
        unit)
  and* _ = Evm_node.wait_for_successful_upgrade sequencer
  and* _ = Evm_node.wait_for_successful_upgrade observer in
  let* () = bake_until_sync ~sc_rollup_node ~client ~sequencer ~proxy () in

  let tx2 =
    (* {
         "chainId": "1337",
         "type": "LegacyTransaction",
         "valid": true,
         "hash": "0xb4c823c72996be6f4767997f21dac443568f3d0a1cd24f3b29eeb66cb5aca2f8",
         "nonce": "1",
         "gasPrice": "100000",
         "gasLimit": "23300",
         "from": "0x6ce4d79d4E77402e1ef3417Fdda433aA744C6e1c",
         "to": "0x11D3C9168db9d12a3C591061D555870969b43dC9",
         "v": "0a95",
         "r": "30d35547c7d39738a85fd6e96d9c9308070b83f334d64f51a94404d20902f970",
         "s": "45ccee6d401d77df59f6831b7d73d1e3df7a9584070f45c117f55a9b81fa997c",
         "value": "100",
         "data": ""
       } *)
    "f86401830186a0825b049411d3c9168db9d12a3c591061d555870969b43dc96480820a95a030d35547c7d39738a85fd6e96d9c9308070b83f334d64f51a94404d20902f970a045ccee6d401d77df59f6831b7d73d1e3df7a9584070f45c117f55a9b81fa997c"
  in

  let*@ _ = Rpc.send_raw_transaction ~raw_tx:tx2 sequencer in
  let*@ txpool_pending, _txpool_queued = Rpc.txpool_content sequencer in
  match txpool_pending with
  | [_] -> unit
  | [] ->
      Test.fail
        "The transaction pool RPC is expected to contain a transaction after \
         the upgrade"
  | _ ->
      Test.fail
        "The transaction pool RPC returns more than a single transaction"

let test_trace_transaction =
  register_both
    ~tags:["evm"; "rpc"; "trace"]
    ~title:"Sequencer can run debug_traceTransaction"
  @@ fun {sc_rollup_node; sequencer; client; proxy; _} _protocol ->
  (* Transfer funds to a random address. *)
  let address = "0xB7A97043983f24991398E5a82f63F4C58a417185" in
  let* transaction_hash =
    send_transaction
      (Eth_cli.transaction_send
         ~source_private_key:Eth_account.bootstrap_accounts.(0).private_key
         ~to_public_key:address
         ~value:(Wei.of_eth_int 10)
         ~endpoint:(Evm_node.endpoint sequencer))
      sequencer
  in
  (* Block few levels to ensure we are replaying on an old block. *)
  let* () =
    repeat 2 (fun () ->
        next_evm_level ~evm_node:sequencer ~sc_rollup_node ~client)
  in
  let* () = bake_until_sync ~sequencer ~sc_rollup_node ~proxy ~client () in
  (* Check tracing without options works *)
  let* trace_result = Rpc.trace_transaction ~transaction_hash sequencer in
  (match trace_result with
  | Ok _ -> ()
  | Error _ -> Test.fail "Trace transaction shouldn't have failed") ;
  (* Check tracing with a tracer without config *)
  let* trace_result =
    Rpc.trace_transaction ~transaction_hash ~tracer:"structLogger" sequencer
  in
  (match trace_result with
  | Ok _ -> ()
  | Error _ -> Test.fail "Trace transaction shouldn't have failed") ;
  (* Check tracing with a tracer and a config *)
  let* trace_result =
    Rpc.trace_transaction
      ~transaction_hash
      ~tracer:"structLogger"
      ~tracer_config:[("enableMemory", `Bool true)]
      sequencer
  in
  (match trace_result with
  | Ok _ -> ()
  | Error _ -> Test.fail "Trace transaction shouldn't have failed") ;
  (* Check tracing without a tracer and a config *)
  let* trace_result =
    Rpc.trace_transaction
      ~transaction_hash
      ~tracer_config:
        [
          ("enableMemory", `Bool true);
          ("enableReturnData", `Bool true);
          ("disableStorage", `Bool true);
          ("disableStack", `Bool true);
        ]
      sequencer
  in
  (match trace_result with
  | Ok _ -> ()
  | Error _ -> Test.fail "Trace transaction shouldn't have failed") ;
  unit

let test_trace_transaction_on_invalid_transaction =
  register_both
    ~tags:["evm"; "rpc"; "trace"; "fail"]
    ~title:"debug_traceTransaction fails on invalid transactions"
  @@ fun {sc_rollup_node; sequencer; client; proxy; _} _protocol ->
  let* () = bake_until_sync ~sequencer ~sc_rollup_node ~proxy ~client () in
  (* Check tracing without options works *)
  let* trace_result =
    Rpc.trace_transaction
      ~transaction_hash:("0x" ^ String.make 64 'f')
      sequencer
  in
  (match trace_result with
  | Ok _ -> Test.fail "Trace transaction should have failed"
  | Error {message; _} ->
      Check.(
        (message =~ rex "not found")
          ~error_msg:"traceTransaction failed with the wrong error")) ;
  unit

let check_trace expect_null expected_returned_value receipt trace =
  (* Checks that each opcode log are either all empty or non empty, considering
     the configuration. *)
  let check_struct_logs expect_null log =
    let check_field field =
      if expect_null then
        Check.(
          JSON.(log |-> field |> JSON.unannotate = `Null)
            json_u
            ~error_msg:
              (Format.sprintf
                 "Field %s was expected to be null, but gor %%L instead"
                 field))
      else
        Check.(
          JSON.(log |-> field |> JSON.unannotate <> `Null)
            json_u
            ~error_msg:
              (Format.sprintf "Field %s wasn't expected to be null" field))
    in
    check_field "memory" ;
    check_field "storage" ;
    check_field "memSize" ;
    check_field "stack" ;
    check_field "returnData"
  in
  let failed = JSON.(trace |-> "failed" |> as_bool) in
  let gas_used = JSON.(trace |-> "gas" |> as_int64) in
  let returned_value =
    JSON.(trace |-> "returnValue" |> as_string |> Durable_storage_path.no_0x)
  in
  let logs = JSON.(trace |-> "structLogs" |> as_list) in
  Check.(
    (failed <> receipt.Transaction.status)
      bool
      ~error_msg:"The trace has a different status than in the receipt") ;
  Check.(
    (gas_used = receipt.gasUsed)
      int64
      ~error_msg:"Trace reported %L gas used, but the trace reported %R") ;

  (* Whether we don't expect a value and we get "0x", or we expect a value and
     it is encoded into a H256. *)
  (match expected_returned_value with
  | Some value ->
      let expected_value = Helpers.hex_256_of_int value in
      Check.(
        (returned_value = expected_value)
          string
          ~error_msg:
            "The transaction returned the value %L, but %R was expected")
  | None ->
      Check.(
        (returned_value = "")
          string
          ~error_msg:"The transaction shouldn't return a value, but returned %L")) ;

  (* Checks the logs are consistent with the configuration (its an all in or
     all out). *)
  Check.((logs <> []) (list json) ~error_msg:"Logs shouldn't be empty") ;
  List.iter
    (check_struct_logs expect_null)
    JSON.(trace |-> "structLogs" |> as_list) ;
  unit

let protocols = Protocol.all

let () =
  test_remove_sequencer protocols ;
  test_persistent_state protocols ;
  test_publish_blueprints protocols ;
  test_sequencer_too_ahead protocols ;
  test_resilient_to_rollup_node_disconnect protocols ;
  test_can_fetch_smart_rollup_address protocols ;
  test_can_fetch_blueprint protocols ;
  test_send_transaction_to_delayed_inbox protocols ;
  test_send_deposit_to_delayed_inbox protocols ;
  test_rpc_produceBlock protocols ;
  test_get_balance_block_param protocols ;
  test_get_block_by_number_block_param protocols ;
  test_extended_block_param protocols ;
  test_delayed_transfer_is_included protocols ;
  test_delayed_deposit_is_included protocols ;
  test_largest_delayed_transfer_is_included protocols ;
  test_delayed_deposit_from_init_rollup_node protocols ;
  test_init_from_rollup_node_data_dir protocols ;
  test_init_from_rollup_node_with_delayed_inbox protocols ;
  test_observer_applies_blueprint protocols ;
  test_observer_applies_blueprint_when_restarted protocols ;
  test_observer_applies_blueprint_when_sequencer_restarted protocols ;
  test_observer_forwards_transaction protocols ;
  test_sequencer_is_reimbursed protocols ;
  test_upgrade_kernel_auto_sync protocols ;
  test_self_upgrade_kernel protocols ;
  test_force_kernel_upgrade protocols ;
  test_force_kernel_upgrade_too_early protocols ;
  test_external_transaction_to_delayed_inbox_fails protocols ;
  test_delayed_transfer_timeout protocols ;
  test_delayed_transfer_timeout_fails_l1_levels protocols ;
  test_delayed_inbox_flushing protocols ;
  test_no_automatic_block_production protocols ;
  test_migration_from_ghostnet protocols ;
  test_sequencer_upgrade protocols ;
  test_sequencer_diverge protocols ;
  test_sequencer_can_catch_up_on_event protocols ;
  test_sequencer_dont_read_level_twice protocols ;
  test_stage_one_reboot protocols ;
  test_blueprint_is_limited_in_size protocols ;
  test_blueprint_limit_with_delayed_inbox protocols ;
  test_reset protocols ;
  test_preimages_endpoint protocols ;
  test_store_smart_rollup_address protocols ;
  test_replay_rpc protocols ;
  test_txpool_content_empty_with_legacy_encoding protocols ;
  test_trace_transaction protocols ;
  test_trace_transaction_on_invalid_transaction protocols
