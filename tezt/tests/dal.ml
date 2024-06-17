(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Nomadic Labs <contact@nomadic-labs.com>                *)
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

(* Testing
   -------
   Component:    Data-availability layer
   Requirement:  make -f kernels.mk build

                 For dev-purpose you can also run the follwing to enable debug outputs and faster build time:

                 cd src/kernel_tx_demo/kernel
                 cargo build --release --target wasm32-unknown-unknown --features debug --features dal
                 wasm-strip ../target/wasm32-unknown-unknown/release/tx_kernel.wasm
                 cp ../target/wasm32-unknown-unknown/release/tx_kernel.wasm ../../../tx_kernel_dal.wasm

   Invocation:   dune exec tezt/tests/main.exe -- --file dal.ml
   Subject: Integration tests related to the data-availability layer
*)

let team = Tag.tezos2

let hooks = Tezos_regression.hooks

let rpc_hooks = Tezos_regression.rpc_hooks

module Dal = Dal_common
module Cryptobox = Dal.Cryptobox

module Helpers = struct
  include Dal.Helpers

  (* We override store slot so that it uses a DAL node in this file. *)
  let store_slot dal_node ?with_proof slot =
    store_slot (Either.Left dal_node) ?with_proof slot
end

module Dal_RPC = struct
  include Dal.RPC

  (* We override call_xx RPCs in Dal.RPC to use a DAL node in this file. *)
  include Dal.RPC.Local
end

(* Wait for 'new_head' event. Note that the DAL node processes a new head with a
   delay of one level. Also, this event is emitted before block processing. *)
let wait_for_layer1_head dal_node level =
  Dal_node.wait_for dal_node "dal_node_layer_1_new_head.v0" (fun e ->
      if JSON.(e |-> "level" |> as_int) = level then Some () else None)

(* Wait for 'new_final_block' event. This event is emitted after processing a
   final block. *)
let wait_for_layer1_final_block dal_node level =
  Dal_node.wait_for dal_node "dal_node_layer_1_new_final_block.v0" (fun e ->
      if JSON.(e |-> "level" |> as_int) = level then Some () else None)

(* We use a custom [bake_for], which by default bakes with all delegates, unlike
   [Client.bake_for], to highlight the following: baking in the past with all
   delegates ensures that the baked block has round 0, which is the default
   round used when injecting DAL attestation operations. Note that it is
   normally not necessary to bake with a particular delegate, therefore there is
   no downside to set the case [`All] as the default. *)
let bake_for ?(delegates = `All) ?count ?dal_node_endpoint client =
  let keys =
    match delegates with
    | `All ->
        (* The argument ~keys:[] allows to bake with all available delegates. *)
        []
    | `For keys -> keys
  in
  Client.bake_for_and_wait client ~keys ?count ?dal_node_endpoint

(* Bake until a block at some given [level] has been finalized and
   processed by the given [dal_nodes]. The head level after this is
   [level + 2]. *)
let bake_until_processed ?dal_node_endpoint ~level client dal_nodes =
  let* current_level = Client.level client in
  let final_level = level + 2 in
  assert (current_level < final_level) ;
  let p =
    List.map
      (fun dal_node -> wait_for_layer1_final_block dal_node level)
      dal_nodes
  in
  let* () =
    bake_for ?dal_node_endpoint ~count:(final_level - current_level) client
  in
  Lwt.join p

module Client = struct
  include Client

  let msg =
    "Please use 'bake_for' for DAL tests and not 'Client.bake_for' to be sure \
     to read the comment about the 'keys' argument."

  let bake_for _client = Test.fail "%s" msg

  let bake_for_and_wait _client = Test.fail "%s" msg
end

let next_level node =
  let* current_level = Node.get_level node in
  return (current_level + 1)

let get_peer_score dal_node peer_id =
  let* scores = Dal_RPC.(call dal_node @@ get_scores ()) in
  let peer_score =
    List.find
      (fun Dal_RPC.{peer; score = _} -> String.equal peer peer_id)
      scores
  in
  return peer_score.score

(* DAL/FIXME: https://gitlab.com/tezos/tezos/-/issues/3173
   The functions below are duplicated from sc_rollup.ml.
   They should be moved to a common submodule. *)
let make_int_parameter name = function
  | None -> []
  | Some value -> [(name, `Int value)]

let make_bool_parameter name = function
  | None -> []
  | Some value -> [(name, `Bool value)]

let make_string_parameter name = function
  | None -> []
  | Some value -> [(name, `String value)]

let test ~__FILE__ ?(regression = false) ?(tags = []) ?uses
    ?(supports = Protocol.From_protocol 19) title f =
  let tags = Tag.tezos2 :: "dal" :: tags in
  let register_test =
    if regression then Protocol.register_regression_test
    else Protocol.register_test
  in
  register_test ~__FILE__ ~title ~tags ?uses ~supports f

let dal_enable_param dal_enable =
  make_bool_parameter ["dal_parametric"; "feature_enable"] dal_enable

let sc_rollup_activation_dal_params dal_enable =
  if Option.value dal_enable ~default:false then
    [
      (["smart_rollup_reveal_activation_level"; "dal_parameters"], `Int 0);
      (["smart_rollup_reveal_activation_level"; "dal_page"], `Int 0);
    ]
  else []

let redundancy_factor_param redundancy_factor =
  make_int_parameter ["dal_parametric"; "redundancy_factor"] redundancy_factor

let slot_size_param slot_size =
  make_int_parameter ["dal_parametric"; "slot_size"] slot_size

(* Some initialization functions to start needed nodes. *)

let setup_node ?(use_mock_srs_for_testing = true) ?(custom_constants = None)
    ?(additional_bootstrap_accounts = 0) ~parameters ~protocol
    ?activation_timestamp ?(event_sections_levels = []) ?(node_arguments = [])
    ?(dal_bootstrap_peers = []) () =
  (* Temporary setup to initialise the node. *)
  let base = Either.right (protocol, custom_constants) in
  let* parameter_file = Protocol.write_parameter_file ~base parameters in
  let* client = Client.init_mockup ~parameter_file ~protocol () in
  let nodes_args =
    Node.
      [
        Synchronisation_threshold 0; History_mode (Full None); No_bootstrap_peers;
      ]
  in
  let node = Node.create nodes_args in
  let* () = Node.config_init node [] in
  let* dal_parameters = Dal.Parameters.from_client client in
  let config : Cryptobox.Config.t =
    {
      activated = true;
      use_mock_srs_for_testing;
      bootstrap_peers = dal_bootstrap_peers;
    }
  in
  let* () =
    Node.Config_file.update
      node
      (Node.Config_file.set_sandbox_network_with_dal_config config)
  in
  let* () = Node.run node ~event_sections_levels node_arguments in
  let* () = Node.wait_for_ready node in
  let* client = Client.init ~endpoint:(Node node) () in
  let* additional_account_keys =
    if additional_bootstrap_accounts > 0 then
      Client.stresstest_gen_keys additional_bootstrap_accounts client
    else return []
  in
  let additional_bootstrap_accounts =
    List.map (fun x -> (x, None, false)) additional_account_keys
  in
  let* parameter_file =
    Protocol.write_parameter_file
      ~additional_bootstrap_accounts
      ~base
      parameters
  in
  let* () =
    Client.activate_protocol_and_wait
      ?timestamp:activation_timestamp
      ~parameter_file
      ~protocol
      client
  in
  return (node, client, dal_parameters)

let with_layer1 ?custom_constants ?additional_bootstrap_accounts
    ?consensus_committee_size ?minimal_block_delay ?delay_increment_per_round
    ?attestation_lag ?slot_size ?number_of_slots ?page_size
    ?attestation_threshold ?number_of_shards ?redundancy_factor
    ?commitment_period ?challenge_window ?dal_enable ?event_sections_levels
    ?node_arguments ?activation_timestamp ?dal_bootstrap_peers
    ?(parameters = []) ?smart_rollup_timeout_period_in_blocks
    ?use_mock_srs_for_testing f ~protocol =
  let parameters =
    make_int_parameter ["dal_parametric"; "attestation_lag"] attestation_lag
    @ make_int_parameter ["dal_parametric"; "number_of_shards"] number_of_shards
    @ make_int_parameter
        ["dal_parametric"; "redundancy_factor"]
        redundancy_factor
    @ make_int_parameter ["dal_parametric"; "slot_size"] slot_size
    @ make_int_parameter ["dal_parametric"; "number_of_slots"] number_of_slots
    @ make_int_parameter ["dal_parametric"; "page_size"] page_size
    @ make_int_parameter
        ["dal_parametric"; "redundancy_factor"]
        redundancy_factor
    @ make_int_parameter
        ["dal_parametric"; "attestation_threshold"]
        attestation_threshold
    @ make_int_parameter
        ["smart_rollup_commitment_period_in_blocks"]
        commitment_period
    @ make_int_parameter
        ["smart_rollup_challenge_window_in_blocks"]
        challenge_window
    (* this will produce the empty list if dal_enable is not passed to the function invocation,
       hence the value from the protocol constants will be used. *)
    @ dal_enable_param dal_enable
    @ sc_rollup_activation_dal_params dal_enable
    @ [(["smart_rollup_arith_pvm_enable"], `Bool true)]
    @ make_int_parameter ["consensus_committee_size"] consensus_committee_size
    @ make_string_parameter ["minimal_block_delay"] minimal_block_delay
    @ make_string_parameter
        ["delay_increment_per_round"]
        delay_increment_per_round
    @ make_int_parameter
        ["smart_rollup_timeout_period_in_blocks"]
        smart_rollup_timeout_period_in_blocks
    @ parameters
  in

  let* node, client, dal_parameters =
    setup_node
      ?use_mock_srs_for_testing
      ?custom_constants
      ?additional_bootstrap_accounts
      ?event_sections_levels
      ?node_arguments
      ?activation_timestamp
      ?dal_bootstrap_peers
      ~parameters
      ~protocol
      ()
  in
  let cryptobox = Helpers.make_cryptobox dal_parameters.cryptobox in
  let bootstrap1_key = Constant.bootstrap1.public_key_hash in
  f dal_parameters cryptobox node client bootstrap1_key

let with_fresh_rollup ?(pvm_name = "arith") ?dal_node f tezos_node tezos_client
    bootstrap1_key =
  let* rollup_address =
    Client.Sc_rollup.originate
      ~hooks
      ~burn_cap:Tez.(of_int 9999999)
      ~alias:"rollup"
      ~src:bootstrap1_key
      ~kind:pvm_name
      ~boot_sector:""
      ~parameters_ty:"string"
      tezos_client
  in
  let sc_rollup_node =
    Sc_rollup_node.create
      ?dal_node
      Operator
      tezos_node
      ~base_dir:(Client.base_dir tezos_client)
      ~default_operator:bootstrap1_key
  in
  let* () = bake_for tezos_client in
  f rollup_address sc_rollup_node

let make_dal_node ?name ?peers ?attester_profiles ?producer_profiles
    ?bootstrap_profile ?history_mode tezos_node =
  let dal_node = Dal_node.create ?name ~node:tezos_node () in
  let* () =
    Dal_node.init_config
      ?peers
      ?attester_profiles
      ?producer_profiles
      ?bootstrap_profile
      ?history_mode
      dal_node
  in
  let* () = Dal_node.run ~event_level:`Debug dal_node ~wait_ready:true in
  return dal_node

let with_dal_node ?peers ?attester_profiles ?producer_profiles
    ?bootstrap_profile ?history_mode tezos_node f key =
  let* dal_node =
    make_dal_node
      ?peers
      ?attester_profiles
      ?producer_profiles
      ?bootstrap_profile
      ?history_mode
      tezos_node
  in
  f key dal_node

(* Wrapper scenario functions that should be re-used as much as possible when
   writing tests. *)
let scenario_with_layer1_node ?regression ?(tags = [team])
    ?additional_bootstrap_accounts ?attestation_lag ?number_of_shards
    ?number_of_slots ?custom_constants ?commitment_period ?challenge_window
    ?(dal_enable = true) ?event_sections_levels ?node_arguments
    ?activation_timestamp ?consensus_committee_size ?minimal_block_delay
    ?delay_increment_per_round variant scenario =
  let description = "Testing DAL L1 integration" in
  test
    ?regression
    ~__FILE__
    ~tags
    (Printf.sprintf "%s (%s)" description variant)
    (fun protocol ->
      with_layer1
        ~custom_constants
        ?additional_bootstrap_accounts
        ?consensus_committee_size
        ?minimal_block_delay
        ?delay_increment_per_round
        ?attestation_lag
        ?number_of_shards
        ?number_of_slots
        ?commitment_period
        ?challenge_window
        ?event_sections_levels
        ?node_arguments
        ?activation_timestamp
        ~protocol
        ~dal_enable
      @@ fun parameters cryptobox node client ->
      scenario protocol parameters cryptobox node client)

let scenario_with_layer1_and_dal_nodes ?regression ?(tags = [team])
    ?(uses = fun _ -> []) ?custom_constants ?minimal_block_delay
    ?delay_increment_per_round ?redundancy_factor ?slot_size ?number_of_shards
    ?number_of_slots ?attestation_lag ?attestation_threshold ?commitment_period
    ?challenge_window ?(dal_enable = true) ?activation_timestamp
    ?bootstrap_profile ?producer_profiles ?history_mode variant scenario =
  let description = "Testing DAL node" in
  test
    ?regression
    ~__FILE__
    ~tags
    ~uses:(fun protocol -> Constant.octez_dal_node :: uses protocol)
    (Printf.sprintf "%s (%s)" description variant)
    (fun protocol ->
      with_layer1
        ~custom_constants
        ?minimal_block_delay
        ?delay_increment_per_round
        ?redundancy_factor
        ?slot_size
        ?number_of_slots
        ?number_of_shards
        ?attestation_lag
        ?attestation_threshold
        ?commitment_period
        ?challenge_window
        ?activation_timestamp
        ~protocol
        ~dal_enable
      @@ fun parameters cryptobox node client ->
      with_dal_node ?bootstrap_profile ?producer_profiles ?history_mode node
      @@ fun _key dal_node ->
      scenario protocol parameters cryptobox node client dal_node)

let scenario_with_all_nodes ?custom_constants ?node_arguments
    ?consensus_committee_size ?slot_size ?page_size ?number_of_shards
    ?redundancy_factor ?attestation_lag ?(tags = []) ?(uses = fun _ -> [])
    ?(pvm_name = "arith") ?(dal_enable = true) ?commitment_period
    ?challenge_window ?minimal_block_delay ?delay_increment_per_round
    ?activation_timestamp ?bootstrap_profile ?producer_profiles
    ?smart_rollup_timeout_period_in_blocks ?use_mock_srs_for_testing
    ?(regression = true) variant scenario =
  let description = "Testing DAL rollup and node with L1" in
  test
    ~regression
    ~__FILE__
    ~tags
    ~uses:(fun protocol ->
      Constant.octez_smart_rollup_node :: Constant.octez_dal_node
      :: uses protocol)
    (Printf.sprintf "%s (%s)" description variant)
    (fun protocol ->
      with_layer1
        ?use_mock_srs_for_testing
        ~custom_constants
        ?node_arguments
        ?consensus_committee_size
        ?slot_size
        ?page_size
        ?number_of_shards
        ?redundancy_factor
        ?attestation_lag
        ?commitment_period
        ?challenge_window
        ?minimal_block_delay
        ?delay_increment_per_round
        ?activation_timestamp
        ?smart_rollup_timeout_period_in_blocks
        ~protocol
        ~dal_enable
      @@ fun parameters _cryptobox node client ->
      with_dal_node ?bootstrap_profile ?producer_profiles node
      @@ fun key dal_node ->
      ( with_fresh_rollup ~pvm_name ~dal_node
      @@ fun sc_rollup_address sc_rollup_node ->
        scenario
          protocol
          parameters
          dal_node
          sc_rollup_node
          sc_rollup_address
          node
          client
          pvm_name )
        node
        client
        key)

let update_neighbors dal_node neighbors =
  let neighbors =
    `A
      (List.map
         (fun dal_node ->
           `O
             [
               ("rpc-addr", `String (Dal_node.rpc_host dal_node));
               ("rpc-port", `Float (float_of_int (Dal_node.rpc_port dal_node)));
             ])
         neighbors)
  in
  Dal_node.Config_file.update
    dal_node
    (JSON.put ("neighbors", JSON.annotate ~origin:"dal_node_config" neighbors))

let update_known_peers dal_node known_peers =
  let peers =
    `A
      (List.map
         (fun dal_node -> `String (Dal_node.listen_addr dal_node))
         known_peers)
  in
  Dal_node.Config_file.update
    dal_node
    (JSON.put ("peers", JSON.annotate ~origin:"dal_node_config" peers))

let wait_for_stored_slot ?shard_index dal_node commitment =
  let check_slot_header e =
    JSON.(e |-> "commitment" |> as_string) = commitment
  in
  let check_shard_index e =
    match shard_index with
    | None -> true
    | Some shard_index -> JSON.(e |-> "shard_index" |> as_int) = shard_index
  in
  Dal_node.wait_for dal_node "stored_slot_shard.v0" (fun e ->
      if check_slot_header e && check_shard_index e then Some () else None)

(* Return the baker at round 0 at the given level. *)
let baker_for_round_zero node ~level =
  let* rights =
    Node.RPC.call node
    @@ RPC.get_chain_block_helper_baking_rights ~level ~max_round:0 ()
  in
  JSON.(List.hd JSON.(rights |> as_list) |-> "delegate" |> as_string) |> return

(* Return a delegate from the list of bootstrap accounts that is different from
   the given delegate. *)
let different_delegate pkh =
  List.find
    (fun del -> not @@ String.equal pkh del.Account.public_key_hash)
    (Array.to_list Account.Bootstrap.keys)

(* Return the delegates from the list of bootstrap accounts that are different
   from the given delegate. *)
let different_delegates pkh =
  List.filter
    (fun del -> not @@ String.equal pkh del.Account.public_key_hash)
    (Array.to_list Account.Bootstrap.keys)

(* We support two formats for specifying the attested slots: either a
   list of slot ids or a bitset. *)
type attestation_availability = Slots of int list | Bitset of bool array

let inject_dal_attestation ?level ?(round = 0) ?payload_level ?force ?error
    ?request ~signer ~nb_slots availability client =
  let dal_attestation =
    match availability with
    | Bitset bitset -> bitset
    | Slots availability ->
        let dal_attestation = Array.make nb_slots false in
        List.iter (fun i -> dal_attestation.(i) <- true) availability ;
        dal_attestation
  in
  let* level =
    match level with Some level -> return level | None -> Client.level client
  in
  let* slots =
    Client.RPC.call client
    @@ RPC.get_chain_block_helper_validators
         ~level
         ~delegate:signer.Account.public_key_hash
         ()
  in
  let slot =
    JSON.(List.hd JSON.(slots |> as_list) |-> "slots" |> as_list)
    |> List.hd |> JSON.as_int
  in
  let* block_payload_hash =
    let block =
      (match payload_level with None -> level | Some l -> l) |> string_of_int
    in
    Operation.Consensus.get_block_payload_hash ~block client
  in
  Operation.Consensus.inject
    ?force
    ?error
    ?request
    ~signer
    (Operation.Consensus.attestation
       ~use_legacy_name:false
       ~level
       ~round
       ~dal_attestation
       ~slot
       ~block_payload_hash
       ())
    client

let inject_dal_attestations ?payload_level ?level ?round ?force
    ?(signers = Array.to_list Account.Bootstrap.keys) ~nb_slots availability
    client =
  Lwt_list.map_s
    (fun signer ->
      inject_dal_attestation
        ?payload_level
        ?level
        ?round
        ?force
        ~signer
        ~nb_slots
        availability
        client)
    signers

let inject_dal_attestations_and_bake node client ~number_of_slots indexes =
  let* baker =
    let* level = Node.get_level node in
    baker_for_round_zero node ~level:(level + 1)
  in
  let signers = different_delegates baker in
  let* _op_hashes =
    inject_dal_attestations ~signers ~nb_slots:number_of_slots indexes client
  in
  bake_for ~delegates:(`For [baker]) client

let inject_dal_attestation_for_assigned_shards ~nb_slots ~attested_level
    ~attester_account ~attester_dal_node client =
  let* attestable_slots =
    Dal_RPC.(
      call attester_dal_node
      @@ get_attestable_slots ~attester:attester_account ~attested_level)
  in
  match attestable_slots with
  | Not_in_committee ->
      Test.fail "attester %s not in committee" attester_account.alias
  | Attestable_slots slots ->
      inject_dal_attestation
        ~level:(attested_level - 1)
        (Bitset (Array.of_list slots))
        ~signer:attester_account
        ~nb_slots
        client

let get_validated_dal_attestations_in_mempool node for_level =
  let* mempool_json =
    Node.RPC.call node
    @@ RPC.get_chain_mempool_pending_operations
         ~version:"2"
         ~validated:true
         ~branch_delayed:false
         ~branch_refused:false
         ~refused:false
         ~outdated:false
         ~validation_passes:[0]
         ()
  in
  let validated = JSON.(mempool_json |-> "validated" |> as_list) in
  List.filter
    (fun op ->
      let contents = JSON.(op |-> "contents" |> geti 0) in
      let level = JSON.(contents |-> "level" |> as_int) in
      level = for_level
      && JSON.(contents |-> "kind" |> as_string) |> fun kind ->
         String.equal kind "attestation_with_dal"
         || String.equal kind "endorsement_with_dal")
    validated
  |> return

let test_one_committee_per_level _protocol _parameters _cryptobox node _client
    _bootstrap_key =
  let* current_level =
    Node.RPC.(call node @@ get_chain_block_helper_current_level ())
  in
  (* The test assumes we are at a level when an epoch starts. And
     that is indeed the case. *)
  assert (current_level.cycle_position = 0) ;
  let* current_committee =
    Dal.Committee.at_level node ~level:current_level.level ()
  in
  let* next_committee =
    Dal.Committee.at_level node ~level:(current_level.level + 1) ()
  in
  Check.((current_committee <> next_committee) Dal.Committee.typ)
    ~error_msg:"Unexpected equal DAL committees at subsequent levels: %L and %R" ;
  unit

let publish_dummy_slot ~source ?error ?fee ~index ~message cryptobox =
  let commitment, proof = Dal.(Commitment.dummy_commitment cryptobox message) in
  Helpers.publish_commitment ~source ?fee ?error ~index ~commitment ~proof

(* We check that publishing a slot header with a proof for a different
   slot leads to a proof-checking error. *)
let publish_dummy_slot_with_wrong_proof_for_same_content ~source ?fee ~index
    cryptobox =
  let commitment, _proof = Dal.(Commitment.dummy_commitment cryptobox "a") in
  let _commitment, proof = Dal.(Commitment.dummy_commitment cryptobox "b") in
  Helpers.publish_commitment ~source ?fee ~index ~commitment ~proof

(* We check that publishing a slot header with a proof for the "same"
   slot contents but represented using a different [slot_size] leads
   to a proof-checking error. *)
let publish_dummy_slot_with_wrong_proof_for_different_slot_size ~source ?fee
    ~index parameters cryptobox =
  let cryptobox_params =
    {
      parameters.Dal.Parameters.cryptobox with
      slot_size = 2 * parameters.cryptobox.slot_size;
    }
  in
  let cryptobox' = Helpers.make_cryptobox cryptobox_params in
  let msg = "a" in
  let commitment, _proof = Dal.(Commitment.dummy_commitment cryptobox msg) in
  let _commitment, proof = Dal.(Commitment.dummy_commitment cryptobox' msg) in
  Helpers.publish_commitment ~source ?fee ~index ~commitment ~proof

let publish_commitment ?counter ?force ~source ?(fee = 1200) ~index ~commitment
    ~proof client =
  let commitment = Dal.Commitment.of_string commitment in
  let proof = Dal.Commitment.proof_of_string proof in
  Helpers.publish_commitment
    ?counter
    ?force
    ~source
    ~fee
    ~index
    ~commitment
    ~proof
    client

type status = Applied | Failed of {error_id : string}

let pp fmt = function
  | Applied -> Format.fprintf fmt "applied"
  | Failed {error_id} -> Format.fprintf fmt "failed: %s" error_id

let status_typ = Check.equalable pp ( = )

let check_manager_operation_status result expected_status oph =
  let manager_operations = JSON.(result |=> 3 |> as_list) in
  let op =
    try
      List.find
        (fun op -> JSON.(op |-> "hash" |> as_string) = oph)
        manager_operations
    with Not_found ->
      Test.fail
        "Test expecting operation %s to be included into the last block."
        oph
  in
  let op_result =
    JSON.(op |-> "contents" |=> 0 |-> "metadata" |-> "operation_result")
  in
  let status_kind = JSON.(op_result |-> "status" |> as_string) in
  let status =
    match status_kind with
    | "applied" -> Applied
    | "failed" ->
        let error_id =
          JSON.(op_result |-> "errors" |=> 0 |-> "id" |> as_string)
        in
        Failed {error_id}
    | s -> Test.fail "Unexpected status: %s" s
  in
  let prefix_msg = sf "Unexpected operation result for %s." oph in
  Check.(expected_status = status)
    status_typ
    ~error_msg:(prefix_msg ^ " Expected: %L. Got: %R.")

let check_dal_raw_context node =
  let* dal_raw_json =
    Node.RPC.(call node @@ get_chain_block_context_raw_json ~path:["dal"] ())
  in
  if JSON.is_null dal_raw_json then
    Test.fail "Expected the context to contain information under /dal key."
  else
    let json_to_string j =
      JSON.unannotate j |> Ezjsonm.wrap |> Ezjsonm.to_string
    in
    let* confirmed_slots_opt =
      Node.RPC.(call node @@ get_chain_block_context_dal_commitments_history ())
    in
    if JSON.is_null confirmed_slots_opt then
      Test.fail
        "confirmed_slots_history RPC is not expected to return None if DAL is \
         enabled" ;
    let confirmed_slots = json_to_string confirmed_slots_opt in
    let confirmed_slots_from_ctxt =
      json_to_string @@ JSON.(dal_raw_json |-> "slot_headers_history")
    in
    if not (String.equal confirmed_slots confirmed_slots_from_ctxt) then
      Test.fail "Confirmed slots history mismatch." ;
    unit

let test_slot_management_logic protocol parameters cryptobox node client
    _bootstrap_key =
  let*! () = Client.reveal ~src:"bootstrap6" client in
  let* () = bake_for client in
  Log.info "Inject some valid slot headers" ;
  let* (`OpHash oph1) =
    publish_dummy_slot
      ~source:Constant.bootstrap1
      ~fee:1_000
      ~index:0
      ~message:"a"
      cryptobox
      client
  in
  let* (`OpHash oph2) =
    publish_dummy_slot
      ~source:Constant.bootstrap2
      ~fee:1_500
      ~index:1
      ~message:"b"
      cryptobox
      client
  in
  let* (`OpHash oph3) =
    publish_dummy_slot
      ~source:Constant.bootstrap3
      ~fee:2_000
      ~index:0
      ~message:"c"
      cryptobox
      client
  in
  let* (`OpHash oph4) =
    publish_dummy_slot
      ~source:Constant.bootstrap4
      ~fee:1_200
      ~index:1
      ~message:"d"
      cryptobox
      client
  in
  let* (`OpHash oph5) =
    publish_dummy_slot_with_wrong_proof_for_same_content
      ~source:Constant.bootstrap5
      ~fee:3_000
      ~index:2
      cryptobox
      client
  in
  (* Check another operation now because we are lacking of bootstrap accounts. *)
  let* bootstrap6 = Client.show_address ~alias:"bootstrap6" client in
  let* (`OpHash oph6) =
    publish_dummy_slot_with_wrong_proof_for_different_slot_size
      ~source:bootstrap6
      ~fee:3_000
      ~index:2
      parameters
      cryptobox
      client
  in
  let* mempool = Mempool.get_mempool client in
  let expected_mempool =
    Mempool.{empty with validated = [oph1; oph2; oph3; oph4; oph5; oph6]}
  in
  Check.(
    (mempool = expected_mempool)
      Mempool.classified_typ
      ~error_msg:"Expected all the operations to be applied. Got %L") ;
  let* () = bake_for client in
  let* bytes =
    Client.RPC.call client @@ RPC.get_chain_block_context_raw_bytes ()
  in
  if JSON.(bytes |-> "dal" |> is_null) then
    Test.fail "Expected the context to contain some information about the DAL" ;
  let* operations_result =
    Client.RPC.call client @@ RPC.get_chain_block_operations ()
  in
  let fees_error =
    Failed
      {
        error_id =
          sf
            "proto.%s.dal_publish_commitment_duplicate"
            (Protocol.encoding_prefix protocol);
      }
  in
  let proof_error =
    Failed
      {
        error_id =
          sf
            "proto.%s.dal_publish_commitment_invalid_proof"
            (Protocol.encoding_prefix protocol);
      }
  in
  (* The baker sorts operations fee wise. Consequently order of
     application for the operations will be: oph3 > oph2 > oph4 > oph1

     For slot 0, oph3 is applied first.

     Flor slot1, oph2 is applied first. *)
  check_manager_operation_status operations_result fees_error oph1 ;
  check_manager_operation_status operations_result fees_error oph4 ;
  check_manager_operation_status operations_result proof_error oph5 ;
  check_manager_operation_status operations_result proof_error oph6 ;
  check_manager_operation_status operations_result Applied oph3 ;
  check_manager_operation_status operations_result Applied oph2 ;
  let nb_slots = parameters.Dal.Parameters.number_of_slots in
  let lag = parameters.attestation_lag in
  let* () = repeat (lag - 1) (fun () -> bake_for client) in
  let* _ =
    inject_dal_attestations
      ~nb_slots
      ~signers:[Constant.bootstrap1; Constant.bootstrap2]
      (Slots [1; 0])
      client
  in
  let* _ =
    inject_dal_attestations
      ~nb_slots
      ~signers:[Constant.bootstrap3; Constant.bootstrap4; Constant.bootstrap5]
      (Slots [1])
      client
  in
  let* baker =
    let* level = Node.get_level node in
    baker_for_round_zero node ~level:(level + 1)
  in
  let* () = bake_for ~delegates:(`For [baker]) client in
  let* metadata = Node.RPC.(call node @@ get_chain_block_metadata ()) in
  let attestation =
    match metadata.dal_attestation with
    | None ->
        assert false
        (* Field is part of the encoding when the feature flag is true *)
    | Some x -> x
  in
  Check.(
    (Array.length attestation >= 2)
      int
      ~error_msg:"The attestation should refer to at least 2 slots, got %L") ;
  Check.(
    (attestation.(0) = false)
      bool
      ~error_msg:"Expected slot 0 to be un-attested") ;
  Check.(
    (attestation.(1) = true) bool ~error_msg:"Expected slot 1 to be attested") ;
  check_dal_raw_context node

(** This test tests various situations related to DAL slots attestation.
    See the steps inside the test.
*)
let test_slots_attestation_operation_behavior _protocol parameters _cryptobox
    node client _bootstrap_key =
  (* Some helpers *)
  let nb_slots = parameters.Dal.Parameters.number_of_slots in
  let lag = parameters.attestation_lag in
  assert (lag > 1) ;
  let attest ?payload_level ?(signer = Constant.bootstrap2) ~level () =
    inject_dal_attestation
      ?payload_level
      ~force:true
      ~nb_slots
      ~level
      ~signer
      (Slots [0])
      client
  in
  let mempool_is ~__LOC__ expected_mempool =
    let* mempool = Mempool.get_mempool client in
    Check.(
      (mempool = expected_mempool)
        Mempool.classified_typ
        ~error_msg:(__LOC__ ^ " : Bad mempool !!!. Got %L")) ;
    unit
  in
  let check_slots_availability ~__LOC__ ~attested =
    let* metadata = Node.RPC.(call node @@ get_chain_block_metadata ()) in
    let dal_attestation =
      (* Field is part of the encoding when the feature flag is true *)
      Option.get metadata.dal_attestation
    in
    List.iter
      (fun i ->
        Check.(
          (Array.get dal_attestation i = true)
            bool
            ~error_msg:
              (Format.sprintf
                 "%s : Slot %d is expected to be confirmed."
                 __LOC__
                 i)))
      attested
    |> return
  in
  (* Just bake some blocks before starting attesting. *)
  let* () = bake_for ~count:4 client in

  (* No header published, we just play with attestations with various levels;
     - Initially, only [h3] is applied, [h1; h2] are outdated, and [h4] is
       branch_delayed. After baking a block, [h3] is included in a block and
       [h4] becomes applied.
     - No slot is confirmed as no slot header is published.
  *)
  let* now = Node.get_level node in
  let* (`OpHash h1) = attest ~level:2 () in
  let outdated = [h1] in
  Log.info "expected mempool: outdated: h1 = %s" h1 ;
  let* () = mempool_is ~__LOC__ Mempool.{empty with outdated} in
  let* (`OpHash h2) = attest ~level:(now - 1) () in
  (* level [now-1] is allowed in the mempool for attestations *)
  let* (`OpHash h2') = attest ~level:(now - 2) () in
  let outdated = [h1; h2'] in
  Log.info "expected mempool: outdated: h1, h2' = %s, validated: h2 = %s" h2' h2 ;
  let* () =
    mempool_is ~__LOC__ Mempool.{empty with outdated; validated = [h2]}
  in
  let* (`OpHash h3) = attest ~level:now () in
  Log.info "expected mempool: outdated: h1, h2', validated: h2, h3 = %s" h3 ;
  let* () =
    mempool_is ~__LOC__ Mempool.{empty with outdated; validated = [h2; h3]}
  in
  (* Level [now+1] is allowed in the mempool for attestations, so we inject for
     level [now+2]. We also take care that the attester is not the same one as
     the baker (who will also inject an attestation, and the two ops will
     conflict). *)
  let* baker1 = baker_for_round_zero node ~level:(now + 1) in
  let* baker2 = baker_for_round_zero node ~level:(now + 2) in
  let signer1 = different_delegate baker1 in
  let signer2 = different_delegate baker1 in
  let* (`OpHash h4) =
    attest ~payload_level:now ~level:(now + 1) ~signer:signer1 ()
  in
  let* (`OpHash h4') =
    attest ~payload_level:now ~level:(now + 2) ~signer:signer2 ()
  in
  Log.info
    "expected mempool: outdated: h1, h2', validated: h2, h3, h4 = %s, \
     branch_delayed: h4' = %s"
    h4
    h4' ;
  let* () =
    mempool_is
      ~__LOC__
      Mempool.
        {empty with outdated; validated = [h2; h3; h4]; branch_delayed = [h4']}
  in
  let* () = bake_for ~delegates:(`For [baker1]) client in
  let outdated = [h1; h2; h2'] in
  (* [h4] and [h4'] cannot be included because their payload hash is wrong. *)
  let* () =
    mempool_is ~__LOC__ Mempool.{empty with outdated; validated = [h4; h4']}
  in
  let* () = bake_for ~delegates:(`For [baker2]) client in
  let* _json =
    Node.RPC.call node
    @@ RPC.get_chain_block_operations_validation_pass ~validation_pass:0 ()
  in
  let* () =
    mempool_is ~__LOC__ Mempool.{empty with outdated; validated = [h4; h4']}
  in
  check_slots_availability ~__LOC__ ~attested:[]

let test_all_available_slots _protocol parameters cryptobox node client
    _bootstrap_key =
  let nb_slots = parameters.Dal.Parameters.number_of_slots in
  (* We ensure there is at least one account per manager operation to
     be included. This is because of the 1M restrction. Another way
     could use batched operations, but the current DAL helpers are
     difficult to use for batched operations. *)
  let* accounts =
    Seq.ints 0 |> Seq.take nb_slots |> List.of_seq
    |> Lwt_list.map_p (fun index ->
           Client.show_address
             ~alias:("bootstrap" ^ string_of_int (1 + index))
             client)
  in
  let* () =
    Lwt_list.iter_p
      (fun source ->
        let*! () = Client.reveal ~src:source.Account.alias client in
        unit)
      (List.filteri
         (fun i _ -> i >= Array.length Account.Bootstrap.keys)
         accounts)
  in
  let* () = bake_for client in
  let* () =
    Lwt_list.iteri_p
      (fun index source ->
        let* (`OpHash _oph1) =
          publish_dummy_slot
            ~source
            ~fee:1_000
            ~index
            ~message:"a"
            cryptobox
            client
        in
        unit)
      accounts
  in
  let* () = bake_for client in
  let* result =
    Node.RPC.(call ~rpc_hooks node @@ get_chain_block_metadata_raw ())
  in
  JSON.encode result |> hooks.on_log ;
  let* operations = Node.RPC.(call node @@ get_chain_block_operations ()) in
  let () =
    (* Check validity of operations *)
    let manager_operations = JSON.(operations |=> 3 |> as_list) in
    Check.(List.length manager_operations = nb_slots)
      ~__LOC__
      ~error_msg:"Expected %R manager operations.Got %L"
      Check.int ;
    List.iter
      (fun operation ->
        let status =
          JSON.(
            operation |-> "contents" |=> 0 |-> "metadata" |-> "operation_result"
            |-> "status" |> as_string)
        in
        Check.(status = "applied")
          ~__LOC__
          ~error_msg:
            "Expected all slots to be included. At least one operation failed \
             with status: %L"
          Check.string)
      manager_operations
  in
  unit

(* Tests that DAL attestations are only included in a block if the attestation
   is from a DAL-committee member. This test may be fail sometimes (with
   [List.hd] on an empty list), though care was taken to avoid this as much as
   possible, as it is a bit hard to make sure an attester is in the TB committee
   but not in the DAL committee).*)
let test_slots_attestation_operation_dal_committee_membership_check _protocol
    parameters _cryptobox node client _bootstrap_key =
  (* The attestation from the bootstrap account should succeed as the bootstrap
     node has sufficient stake to be in the DAL committee. *)
  let nb_slots = parameters.Dal.Parameters.number_of_slots in
  let* () = bake_for client in
  let* level = Client.level client in
  let* (`OpHash _oph) =
    inject_dal_attestation
      ~nb_slots
      ~level
      ~signer:Constant.bootstrap1
      (Slots [])
      client
  in
  (* Set up a new account that holds the right amount of tez and make sure it
     can be an attester. *)
  let* proto_params =
    Node.RPC.call node @@ RPC.get_chain_block_context_constants ()
  in
  let consensus_rights_delay =
    JSON.(proto_params |-> "consensus_rights_delay" |> as_int)
  in
  let blocks_per_cycle = JSON.(proto_params |-> "blocks_per_cycle" |> as_int) in
  (* With [consensus_committee_size = 1024] slots in total, the new baker should
     get roughly n / 64 = 16 TB slots on average. So the probability that it is
     on TB committee is high. With [number_of_shards = 32] (which is the minimum
     possible without changing other parameters), the new baker should be
     assigned roughly 32/64 = 1/2 shards on average. *)
  let stake = Tez.of_mutez_int (Protocol.default_bootstrap_balance / 64) in
  let* new_account = Client.gen_and_show_keys client in
  let* () =
    Client.transfer
      ~giver:Constant.bootstrap1.alias
      ~receiver:new_account.alias
      ~amount:Tez.(stake + of_int 10)
      ~burn_cap:Tez.one
      client
  in
  let* () = bake_for client in
  let*! () = Client.reveal ~fee:Tez.one ~src:new_account.alias client in
  let* () = bake_for client in
  let* () = Client.register_key new_account.alias client in
  let* () = bake_for client in
  let num_cycles = 2 + consensus_rights_delay in
  Log.info
    "Bake for %d cycles for %s to be a baker"
    num_cycles
    new_account.alias ;
  let* () = bake_for ~count:(num_cycles * blocks_per_cycle) client in
  (* We iterate until we find a level for which the new account has no assigned
     shard. Recall that the probability to not be assigned a shard is around
     3/4, so a level is found quickly. *)
  let rec iter () =
    let* level = Client.level client in
    let* committee = Dal.Committee.at_level node ~level () in
    if
      List.exists
        (fun member ->
          String.equal member.Dal.Committee.attester new_account.public_key_hash)
        committee
    then (
      Log.info "Bake another block to change the DAL committee" ;
      let* () = bake_for client in
      iter ())
    else (
      Log.info
        "We first check that the new account is in the Tenderbake committee" ;
      let* validators =
        Client.RPC.call client
        @@ RPC.get_chain_block_helper_validators ~level ()
      in
      let is_validator =
        List.exists
          (fun validator ->
            JSON.(validator |-> "delegate" |> as_string)
            |> String.equal new_account.public_key_hash)
          (JSON.as_list validators)
      in
      Check.(
        (is_validator = true)
          bool
          ~error_msg:
            "The new account is not a validator, the test needs to be adapted") ;
      let* (`OpHash _oph) =
        inject_dal_attestation
          ~error:Operation.dal_data_availibility_attester_not_in_committee
          ~nb_slots
          ~level
          ~signer:new_account
          (Slots [])
          client
      in
      (* Bake with all the bootstrap accounts, but not with the new account. *)
      let* () =
        let bootstrap_accounts =
          Array.to_list Account.Bootstrap.keys
          |> List.map (fun a -> a.Account.public_key_hash)
        in
        bake_for ~delegates:(`For bootstrap_accounts) client
      in
      let* json =
        Node.RPC.call node
        @@ RPC.get_chain_block_operations_validation_pass ~validation_pass:0 ()
      in
      let num_ops = JSON.as_list json |> List.length in
      Check.(
        (num_ops = Array.length Account.Bootstrap.keys)
          int
          ~error_msg:"Expected %R operations, found %L") ;
      unit)
  in
  iter ()

let test_dal_node_slot_management _protocol parameters _cryptobox _node _client
    dal_node =
  let slot_size = parameters.Dal.Parameters.cryptobox.slot_size in
  let slot_content = "test with invalid UTF-8 byte sequence \xFA" in
  let* slot_commitment, _proof =
    Helpers.(store_slot dal_node @@ make_slot ~slot_size slot_content)
  in
  let* received_slot =
    Dal_RPC.(call dal_node @@ get_commitment_slot slot_commitment)
  in
  let received_slot_content = Helpers.content_of_slot received_slot in
  Check.(
    (slot_content = received_slot_content)
      string
      ~error_msg:"Wrong slot content: Expected: %L. Got: %R") ;
  (* Only check that the function to retrieve pages succeeds, actual
     contents are checked in the test `rollup_node_stores_dal_slots`. *)
  let* _slots_as_pages =
    Dal_RPC.(call dal_node @@ slot_pages slot_commitment)
  in
  return ()

let () =
  Printexc.register_printer @@ function
  | Data_encoding.Binary.Read_error e ->
      Some
        (Format.asprintf
           "Failed to decode binary: %a@."
           Data_encoding.Binary.pp_read_error
           e)
  | _ -> None

let publish_and_store_slot ?with_proof ?counter ?force ?(fee = 1_200) client
    dal_node source ~index content =
  let* commitment, proof = Helpers.store_slot dal_node ?with_proof content in
  let* _ =
    publish_commitment
      ?counter
      ?force
      ~source
      ~fee
      ~index
      ~commitment
      ~proof
      client
  in
  return commitment

(* Similar to [publish_and_store_slot] but additionally bakes [1 +
   number_of_extra_blocks] blocks to trigger the publication of the
   shards of the published slot commitment. Moreover, the [wait_slot]
   argument can be used to wait for the shards to be received by one
   or several other DAL nodes. Returns the published commitment and
   the level at which it was published. *)
let publish_store_and_wait_slot ?counter ?force ?(fee = 1_200) node client
    slot_producer_dal_node source ~index ~wait_slot
    ~number_of_extra_blocks_to_bake content =
  let* commitment, proof =
    Helpers.store_slot ~with_proof:true slot_producer_dal_node content
  in
  let p = wait_slot commitment in
  let* (`OpHash ophash) =
    publish_commitment
      ?counter
      ?force
      ~source
      ~fee
      ~index
      ~commitment
      ~proof
      client
  in
  (* Bake a first block to include the operation. *)
  let* () = bake_for client in
  let* level = Client.level client in
  (* Check that the operation is included. *)
  let* included_manager_operations =
    let manager_operation_pass = 3 in
    Node.RPC.(
      call node
      @@ get_chain_block_operation_hashes_of_validation_pass
           manager_operation_pass)
  in
  let () =
    Check.list_mem
      Check.string
      ~__LOC__
      ophash
      included_manager_operations
      ~error_msg:"DAL commitment publishment operation not found in head block."
  in
  (* Bake some more blocks to finalize the block containing the publication. *)
  let* () = bake_for ~count:number_of_extra_blocks_to_bake client in
  (* Wait for the shards to be received *)
  let* () = p in
  return (level, commitment)

let publish_store_and_attest_slot ?with_proof ?counter ?force ?fee client node
    dal_node source ~index ~content ~attestation_lag ~number_of_slots =
  let* _commitment =
    publish_and_store_slot
      ?with_proof
      ?counter
      ?force
      ?fee
      client
      dal_node
      source
      ~index
      content
  in
  let* () = repeat attestation_lag (fun () -> bake_for client) in
  inject_dal_attestations_and_bake node client ~number_of_slots (Slots [index])

let check_get_commitment dal_node ~slot_level check_result slots_info =
  Lwt_list.iter_s
    (fun (slot_index, commitment') ->
      let* response =
        Dal_RPC.(
          call_raw dal_node
          @@ get_level_index_commitment ~slot_index ~slot_level)
      in
      return @@ check_result commitment' response)
    slots_info

let get_commitment_succeeds expected_commitment response =
  let commitment =
    JSON.(parse ~origin:__LOC__ response.RPC_core.body |> as_string)
  in
  Check.(commitment = expected_commitment)
    Check.string
    ~error_msg:
      "The value of a stored commitment should match the one computed locally \
       (current = %L, expected = %R)"

let get_commitment_not_found _commit r =
  RPC_core.check_string_response ~code:404 r

let check_get_commitment_headers dal_node ~slot_level check_result slots_info =
  let test check_result ~query_string (slot_index, commit) =
    let slot_level, slot_index =
      if not query_string then (None, None)
      else (Some slot_level, Some slot_index)
    in
    let* response =
      Dal_RPC.(
        call_raw dal_node
        @@ get_commitment_headers ?slot_index ?slot_level commit)
    in
    return @@ check_result response
  in
  let* () = Lwt_list.iter_s (test check_result ~query_string:true) slots_info in
  Lwt_list.iter_s (test check_result ~query_string:false) slots_info

let check_published_level_headers ~__LOC__ dal_node ~pub_level
    ~number_of_headers =
  let* slot_headers =
    Dal_RPC.(call dal_node @@ get_published_level_headers pub_level)
  in
  Check.(List.length slot_headers = number_of_headers)
    ~__LOC__
    Check.int
    ~error_msg:"Unexpected slot headers length (got = %L, expected = %R)" ;
  unit

(* Checks that [response] contains zero or one slot header. If [expected_status]
   is not given, the expected response is the empty list; if it is given, the
   response should contain exactly one header, with the given status. The
   function [check_headers] generalizes this check to more headers. *)
let get_headers_succeeds ~__LOC__ ?expected_status response =
  let headers =
    JSON.(
      parse ~origin:"get_headers_succeeds" response.RPC_core.body
      |> Dal_RPC.slot_headers_of_json)
  in
  match (headers, expected_status) with
  | [], None -> ()
  | _ :: _, None ->
      Test.fail
        ~__LOC__
        "It was expected that there is no slot id for the given commitment, \
         got %d."
        (List.length headers)
  | [header], Some expected_status ->
      Check.(header.Dal_RPC.status = expected_status)
        ~__LOC__
        Check.string
        ~error_msg:
          "The value of the fetched status should match the expected one \
           (current = %L, expected = %R)"
  | _, Some _ ->
      Test.fail
        ~__LOC__
        "It was expected that there is exactly one slot id for the given \
         commitment, got %d."
        (List.length headers)

(* Similar to [get_headers_succeeds], except that it is more general, it does
   not assume that there will be just 0 or 1 header. *)
let check_headers ~__LOC__ expected_headers response =
  let headers =
    JSON.(
      parse ~origin:"check_headers" response.RPC_core.body
      |> Dal_RPC.slot_headers_of_json)
  in
  Check.(List.length headers = List.length expected_headers)
    ~__LOC__
    Check.int
    ~error_msg:"check_headers: Expected %R headers, got %L." ;
  let headers =
    List.map (fun h -> (h.Dal_RPC.slot_level, h.slot_index, h.status)) headers
  in
  List.iter
    (fun (level, index, expected_status) ->
      let status_opt =
        List.find_map
          (fun (l, i, status) ->
            if level = l && index = i then Some status else None)
          headers
      in
      Check.(status_opt = Some expected_status)
        ~__LOC__
        Check.(option string)
        ~error_msg:
          (Format.asprintf
             "Expected to find for slot level %d and slot index %d the status \
              (%%R), found (%%L)."
             level
             index))
    expected_headers

let test_dal_node_slots_headers_tracking _protocol parameters _cryptobox node
    client dal_node =
  let check_published_level_headers = check_published_level_headers dal_node in
  let slot_size = parameters.Dal.Parameters.cryptobox.slot_size in
  let* level = Node.get_level node in
  let pub_level = level + 1 in
  let publish ?fee source ~index content =
    let content = Helpers.make_slot ~slot_size content in
    let* commitment =
      publish_and_store_slot ?fee client dal_node source ~index content
    in
    return (index, commitment)
  in
  let* slot0 = publish Constant.bootstrap1 ~index:0 "test0" in
  let* slot1 = publish Constant.bootstrap2 ~index:1 "test1" in
  let* () =
    (* The slot headers are not yet in a block. *)
    check_published_level_headers ~__LOC__ ~pub_level ~number_of_headers:0
  in

  (* slot2_a and slot3 will not be included as successful, because slot2_b has
     better fees for slot4, while slot3's fee is too low. slot4 is not injected
     into L1 or DAL nodes.

     We decide to have two failed slots instead of just one to better test some
     internal aspects of failed slots headers recording (i.e. having a collection
     of data instead of just one). *)
  let* slot2_a = publish Constant.bootstrap3 ~index:4 ~fee:1_200 "test4_a" in
  let* slot2_b = publish Constant.bootstrap4 ~index:4 ~fee:1_350 "test4_b" in
  let* slot3 = publish Constant.bootstrap5 ~index:5 ~fee:1 "test5" in
  let* slot4 =
    let slot = Helpers.make_slot ~slot_size "never associated to a slot_id" in
    let* commit = Dal_RPC.(call dal_node @@ post_commitment slot) in
    return (6, commit)
  in

  Log.info "Just after injecting slots and before baking, there are no headers" ;
  (* because headers are stored based on information from finalized blocks *)
  let* () =
    check_get_commitment_headers
      dal_node
      ~slot_level:level
      (get_headers_succeeds ~__LOC__)
      [slot0; slot1; slot2_a; slot2_b; slot3; slot4]
  in
  let* () =
    (* The slot headers are still not yet in a block. *)
    check_published_level_headers ~__LOC__ ~pub_level ~number_of_headers:0
  in

  let wait_block_processing1 = wait_for_layer1_head dal_node pub_level in
  let* () = bake_for client in
  let* () = wait_block_processing1 in

  Log.info
    "After baking one block, there is still no header, because the block is \
     not final" ;
  let* () =
    check_get_commitment_headers
      dal_node
      ~slot_level:level
      (get_headers_succeeds ~__LOC__)
      [slot0; slot1; slot2_a; slot2_b; slot3; slot4]
  in

  let wait_block_processing2 = wait_for_layer1_final_block dal_node pub_level in
  let* () = bake_for ~count:2 client in
  let* () = wait_block_processing2 in

  Log.info
    "After baking two more blocks, the slots' status is as expected (eg for \
     published slots it's Waiting_attestation)" ;
  let ok = [slot0; slot1; slot2_b] in
  let ko = slot3 :: slot4 :: List.map (fun (i, c) -> (i + 100, c)) ok in
  let* () =
    (* There are 4 published slots: slot0, slot1, slot2_a, and slot2_b *)
    check_published_level_headers ~__LOC__ ~pub_level ~number_of_headers:4
  in
  let* slot_headers =
    Dal_RPC.(
      call dal_node
      @@ get_published_level_headers ~status:"waiting_attestation" pub_level)
  in
  let slot_headers =
    List.map (fun sh -> (sh.Dal_RPC.slot_index, sh.commitment)) slot_headers
    |> List.fast_sort (fun (idx1, _) (idx2, _) -> Int.compare idx1 idx2)
  in
  Check.(slot_headers = ok)
    Check.(list (tuple2 int string))
    ~error_msg:
      "Published header is different from stored header (current = %L, \
       expected = %R)" ;
  let check_get_commitment_headers =
    check_get_commitment_headers dal_node ~slot_level:pub_level
  in
  let check_get_commitment =
    check_get_commitment dal_node ~slot_level:pub_level
  in

  (* Slots waiting for attestation. *)
  let* () = check_get_commitment get_commitment_succeeds ok in
  let* () =
    check_get_commitment_headers
      (get_headers_succeeds ~__LOC__ ~expected_status:"waiting_attestation")
      ok
  in
  (* slot_2_a is not selected. *)
  let* () =
    check_get_commitment_headers
      (get_headers_succeeds ~__LOC__ ~expected_status:"not_selected")
      [slot2_a]
  in
  (* Slots not published or not included in blocks. *)
  let* () = check_get_commitment get_commitment_not_found ko in

  let lag = parameters.attestation_lag in
  Log.info
    "Attest slots slot0 and slot2_b, and wait for the attestations to be final" ;
  let attested = [slot0; slot2_b] in
  let unattested = [slot1] in
  let number_of_slots = parameters.Dal.Parameters.number_of_slots in
  let* () = bake_for ~count:(lag - 3) client in
  let wait_block_processing3 =
    let attested_level = pub_level + lag in
    wait_for_layer1_final_block dal_node attested_level
  in
  let* () =
    inject_dal_attestations_and_bake
      node
      client
      ~number_of_slots
      (Slots (List.map fst attested))
  in
  let* () = bake_for ~count:2 client in
  let* () = wait_block_processing3 in
  let* () =
    (* The number of published slots has not changed *)
    check_published_level_headers ~__LOC__ ~pub_level ~number_of_headers:4
  in

  Log.info "Check that the store is as expected" ;
  (* Slots confirmed. *)
  let* () = check_get_commitment get_commitment_succeeds ok in
  (* Slot that were waiting for attestation and now attested. *)
  let* () =
    check_get_commitment_headers
      (get_headers_succeeds ~__LOC__ ~expected_status:"attested")
      attested
  in
  (* Slots not published or not included in blocks. *)
  let* () = check_get_commitment get_commitment_not_found ko in
  (* Slot that were waiting for attestation and now unattested. *)
  let* () =
    check_get_commitment_headers
      (get_headers_succeeds ~__LOC__ ~expected_status:"unattested")
      unattested
  in
  (* slot2_a is still not selected. *)
  let* () =
    check_get_commitment_headers
      (get_headers_succeeds ~__LOC__ ~expected_status:"not_selected")
      [slot2_a]
  in
  (* slot3 never finished in an L1 block, so the DAL node did not store a status for it. *)
  let* () =
    check_get_commitment_headers (get_headers_succeeds ~__LOC__) [slot3]
  in
  (* slot4 is never injected in any of the nodes. So, it's not
     known by the Dal node. *)
  let* () =
    check_get_commitment_headers (get_headers_succeeds ~__LOC__) [slot4]
  in
  (* The number of published slots has not changed *)
  let* () =
    check_published_level_headers
      ~__LOC__
      ~pub_level:(pub_level - 1)
      ~number_of_headers:0
  in
  let* () =
    check_published_level_headers ~__LOC__ ~pub_level ~number_of_headers:4
  in
  check_published_level_headers
    ~__LOC__
    ~pub_level:(pub_level + 1)
    ~number_of_headers:0

let generate_dummy_slot slot_size =
  String.init slot_size (fun i ->
      match i mod 3 with 0 -> 'a' | 1 -> 'b' | _ -> 'c')

let get_shards dal_node ~slot_header downloaded_shard_ids =
  Lwt_list.map_s
    (fun shard_id ->
      Dal_RPC.(call dal_node @@ get_shard ~slot_header ~shard_id))
    downloaded_shard_ids

let test_dal_node_rebuild_from_shards _protocol parameters _cryptobox node
    client dal_node =
  (* Steps in this integration test:
     1. Run a dal node
     2. Generate and publish a full slot, then bake
     3. Download exactly 1/redundancy_factor shards
        from this slot (it would work with more)
     4. Ensure we can rebuild the original data using the above shards
  *)
  let crypto_params = parameters.Dal.Parameters.cryptobox in
  let slot_size = crypto_params.slot_size in
  let slot_content = generate_dummy_slot slot_size in
  let publish = publish_and_store_slot client dal_node in
  let* slot_header =
    publish Constant.bootstrap1 ~index:0
    @@ Helpers.make_slot ~slot_size slot_content
  in
  let* () = bake_for client in
  let* _level = Node.wait_for_level node 1 in
  let number_of_shards =
    (crypto_params.number_of_shards / crypto_params.redundancy_factor) - 1
  in
  let downloaded_shard_ids =
    range 0 number_of_shards
    |> List.map (fun i -> i * crypto_params.redundancy_factor)
  in
  let* shards = get_shards dal_node ~slot_header downloaded_shard_ids in
  let shard_of_json shard =
    let shard =
      match Data_encoding.Json.from_string shard with
      | Ok s -> s
      | Error _ -> Test.fail "shard RPC sent invalid json"
    in
    let shard = Data_encoding.Json.destruct Cryptobox.shard_encoding shard in
    ({index = shard.index; share = shard.share} : Cryptobox.shard)
  in
  let shards = shards |> List.to_seq |> Seq.map shard_of_json in
  let cryptobox = Helpers.make_cryptobox parameters.cryptobox in
  let reformed_slot =
    match Cryptobox.polynomial_from_shards cryptobox shards with
    | Ok p -> Cryptobox.polynomial_to_slot cryptobox p |> Bytes.to_string
    | Error _ -> Test.fail "Fail to build polynomial from shards"
  in
  Check.(reformed_slot = slot_content)
    Check.(string)
    ~error_msg:
      "Reconstructed slot is different from original slot (current = %L, \
       expected = %R)" ;
  return ()

let commitment_of_slot cryptobox slot =
  let polynomial =
    Cryptobox.polynomial_from_slot
      cryptobox
      (Helpers.content_of_slot slot |> Bytes.of_string)
    |> Result.get_ok
  in
  match Cryptobox.commit cryptobox polynomial with
  | Ok cm -> cm
  | Error
      ((`Invalid_degree_strictly_less_than_expected _ | `Prover_SRS_not_loaded)
      as commit_error) ->
      Test.fail "%s" (Cryptobox.string_of_commit_error commit_error)

let test_dal_node_test_post_commitments _protocol parameters cryptobox _node
    _client dal_node =
  let slot_size = parameters.Dal.Parameters.cryptobox.slot_size in
  let mk_slot size =
    Helpers.make_slot ~padding:false ~slot_size (generate_dummy_slot size)
  in
  let failing_post_slot_rpc slot =
    let* response = Dal_RPC.(call_raw dal_node @@ post_commitment slot) in
    return
    @@ RPC_core.check_string_response
         ~body_rex:"dal.node.invalid_slot_size"
         ~code:500
         response
  in
  let size = parameters.Dal.Parameters.cryptobox.slot_size in
  let slot_big = mk_slot (size + 1) in
  let slot_small = mk_slot (size - 1) in
  let slot_ok = mk_slot size in
  let* () = failing_post_slot_rpc slot_big in
  let* () = failing_post_slot_rpc slot_small in
  let* commitment1 = Dal_RPC.(call dal_node @@ post_commitment slot_ok) in
  let* commitment2 = Dal_RPC.(call dal_node @@ post_commitment slot_ok) in
  (* TODO/DAL: https://gitlab.com/tezos/tezos/-/issues/4250
     The second RPC call above succeeeds, but the (untested) returned HTTP status
     should likely be 200 and 201 in the first similar RPC call.
  *)
  Check.(commitment1 = commitment2)
    Check.string
    ~error_msg:
      "Storing a slot twice should return the same commitment (current = %L, \
       expected = %R)" ;
  let commitment3 =
    Cryptobox.Commitment.to_b58check @@ commitment_of_slot cryptobox slot_ok
  in
  Check.(commitment1 = commitment3)
    Check.string
    ~error_msg:
      "The commitment of a stored commitment should match the one computed \
       locally (current = %L, expected = %R)" ;
  unit

let test_dal_node_test_patch_commitments _protocol parameters cryptobox _node
    _client dal_node =
  let failing_patch_slot_rpc commit ~slot_level ~slot_index =
    let* response =
      Dal_RPC.(
        call_raw dal_node @@ patch_commitment commit ~slot_level ~slot_index)
    in
    return @@ RPC_core.check_string_response ~code:404 response
  in
  let slot_size = parameters.Dal.Parameters.cryptobox.slot_size in
  let slot = Helpers.make_slot ~slot_size (generate_dummy_slot slot_size) in
  let commitment =
    Cryptobox.Commitment.to_b58check @@ commitment_of_slot cryptobox slot
  in
  let* () = failing_patch_slot_rpc commitment ~slot_level:0 ~slot_index:0 in
  let* commitment' = Dal_RPC.(call dal_node @@ post_commitment slot) in
  Check.(commitment' = commitment)
    Check.string
    ~error_msg:
      "The commitment of a stored commitment should match the one computed \
       locally (current = %L, expected = %R)" ;
  let patch_slot_rpc ~slot_level ~slot_index =
    Dal_RPC.(
      call dal_node @@ patch_commitment commitment ~slot_level ~slot_index)
  in
  let check ~__LOC__ expected_headers =
    let* response =
      Dal_RPC.(call_raw dal_node @@ get_commitment_headers commitment)
    in
    check_headers ~__LOC__ expected_headers response ;
    unit
  in
  let* () = patch_slot_rpc ~slot_level:0 ~slot_index:0 in
  let* () = check ~__LOC__ [(0, 0, "unseen")] in
  let* () = patch_slot_rpc ~slot_level:0 ~slot_index:0 in
  let* () = check ~__LOC__ [(0, 0, "unseen")] in
  let* () = patch_slot_rpc ~slot_level:0 ~slot_index:1 in
  let* () = check ~__LOC__ [(0, 0, "unseen"); (0, 1, "unseen")] in
  let* () = patch_slot_rpc ~slot_level:(-4) ~slot_index:3 in
  let* () =
    check ~__LOC__ [(0, 0, "unseen"); (0, 1, "unseen"); (-4, 3, "unseen")]
  in
  unit

let test_dal_node_test_get_commitment_slot _protocol parameters cryptobox _node
    _client dal_node =
  let slot_size = parameters.Dal.Parameters.cryptobox.slot_size in
  let slot = Helpers.make_slot ~slot_size (generate_dummy_slot slot_size) in
  let commitment =
    Cryptobox.Commitment.to_b58check @@ commitment_of_slot cryptobox slot
  in
  let* () =
    let* response =
      Dal_RPC.(call_raw dal_node @@ get_commitment_slot commitment)
    in
    return @@ RPC_core.check_string_response ~code:404 response
  in
  let* _commitment = Dal_RPC.(call dal_node @@ post_commitment slot) in
  (* commit = _commitment already tested in /POST test. *)
  let* got_slot = Dal_RPC.(call dal_node @@ get_commitment_slot commitment) in
  Check.(Helpers.content_of_slot slot = Helpers.content_of_slot got_slot)
    Check.string
    ~error_msg:
      "The slot content retrieved from the node is not as expected (expected = \
       %L, got = %R)" ;
  unit

let test_dal_node_import_snapshot _protocol parameters _cryptobox node client
    dal_node =
  let* commitment, proof =
    Helpers.(
      store_slot dal_node ~with_proof:true
      @@ make_slot
           ~slot_size:parameters.Dal_common.Parameters.cryptobox.slot_size
           "content1")
  in
  let* _oph =
    publish_commitment
      ~source:Constant.bootstrap1
      ~index:0
      ~commitment
      ~proof
      client
  in
  let* level = Node.get_level node in
  let* () = bake_for client in
  let* export_level = Node.wait_for_level node (level + 1) in
  let file = Temp.file "snapshot" in
  let* () = Node.snapshot_export ~export_level node file in
  let node2 = Node.create [] in
  let* () = Node.config_init node2 [] in
  (* We update the configuration because by default on sandbox mode,
     DAL is not activated. *)
  let config : Cryptobox.Config.t =
    {activated = true; use_mock_srs_for_testing = true; bootstrap_peers = []}
  in
  let* () =
    Node.Config_file.update
      node2
      (Node.Config_file.set_sandbox_network_with_dal_config config)
  in
  let* () = Node.snapshot_import node2 file in
  unit

let test_dal_node_test_get_commitment_proof _protocol parameters cryptobox _node
    _client dal_node =
  let slot_size = parameters.Dal.Parameters.cryptobox.slot_size in
  let slot = Helpers.make_slot ~slot_size (generate_dummy_slot slot_size) in
  let* commitment = Dal_RPC.(call dal_node @@ post_commitment slot) in
  let* proof = Dal_RPC.(call dal_node @@ get_commitment_proof commitment) in
  let _, expected_proof =
    Dal.Commitment.dummy_commitment cryptobox (generate_dummy_slot slot_size)
  in
  let (`Hex expected_proof) =
    Data_encoding.Binary.to_bytes_exn
      Dal.Cryptobox.Commitment_proof.encoding
      expected_proof
    |> Hex.of_bytes
  in
  Check.(proof = expected_proof)
    Check.string
    ~error_msg:"Wrong proof computed (got = %L, expected = %R)" ;
  unit

let test_dal_node_startup =
  Protocol.register_test
    ~__FILE__
    ~title:"dal node startup"
    ~tags:[Tag.tezos2; "dal"]
    ~uses:(fun _protocol -> [Constant.octez_dal_node])
    ~supports:(Protocol.From_protocol 20)
  @@ fun protocol ->
  let run_dal = Dal_node.run ~wait_ready:false in
  let nodes_args = Node.[Synchronisation_threshold 0] in
  let previous_protocol =
    match Protocol.previous_protocol protocol with
    | Some p -> p
    | None -> assert false
  in
  let* node, client =
    Client.init_with_protocol
      `Client
      ~protocol:previous_protocol
      ~event_sections_levels:[("prevalidator", `Debug)]
      ~nodes_args
      ()
  in
  let dal_node = Dal_node.create ~node () in
  let* () = Dal_node.init_config dal_node in
  let* () = run_dal dal_node in
  let* () =
    Dal_node.wait_for
      dal_node
      "dal_node_layer_1_start_tracking_for_plugin.v0"
      (fun _ -> Some ())
  in
  assert (Dal_node.is_running_not_ready dal_node) ;
  let* () = Dal_node.terminate dal_node in
  let* () = Node.terminate node in
  let* () =
    Node.Config_file.update
      node
      (Node.Config_file.set_sandbox_network_with_user_activated_overrides
         [(Protocol.hash previous_protocol, Protocol.hash protocol)])
  in
  let* () = Node.run node nodes_args in
  let* () = Node.wait_for_ready node in
  let* () = run_dal dal_node in
  let* () =
    Lwt.join
      [
        Dal_node.wait_for dal_node "dal_node_plugin_resolved.v0" (fun _ ->
            Some ());
        bake_for client;
      ]
  in
  let* () = Dal_node.terminate dal_node in
  return ()

let send_messages ?(bake = true) ?(src = Constant.bootstrap2.alias)
    ?(alter_final_msg = Fun.id) client msgs =
  let msg =
    alter_final_msg
    @@ Ezjsonm.(to_string ~minify:true @@ list Ezjsonm.string msgs)
  in
  let* () = Client.Sc_rollup.send_message ~hooks ~src ~msg client in
  if bake then bake_for client else unit

let rollup_node_stores_dal_slots ?expand_test protocol parameters dal_node
    sc_rollup_node sc_rollup_address node client _pvm_name =
  (* Check that the rollup node downloaded the confirmed slots to which it is
     subscribed:

     0. Run a DAL node.

     1. Send three slots to DAL node and obtain corresponding headers.

     2. Run rollup node for an originated rollup.

     3. Setting the parameters of the PVM. Rollup node subscribes to slots 0, 2,
     4 and 6.

     4. Publish the three slot headers for slots with indexes 0, 1 and 2.

     5. Check that the slot_headers are fetched by the rollup node.

     6. Attest only slots 1 and 2.

     7. Only slots 1 and 2 are attested. No slot is currently pre-downloaded by
     the rollup.

     8. Bake `attestation_lag` blocks so that the rollup node interprets the
     previously published & attested slot(s).

     9. Verify that rollup node has downloaded slot 2. Slot 0 is unconfirmed,
     and slot 1 has not been downloaded.
  *)
  let slot_size = parameters.Dal.Parameters.cryptobox.slot_size in
  let page_size = parameters.Dal.Parameters.cryptobox.page_size in
  let store_slot content =
    Helpers.(store_slot dal_node @@ make_slot ~slot_size content)
  in
  Log.info
    "Step 1: send three slots to DAL node and obtain corresponding headers" ;
  let slot_contents_0 = " 10 " in
  let* commitment_0, proof_0 = store_slot slot_contents_0 in
  let slot_contents_1 = " 200 " in
  let* commitment_1, proof_1 = store_slot slot_contents_1 in
  let slot_contents_2 = " 400 " in
  let* commitment_2, proof_2 = store_slot slot_contents_2 in

  Log.info "Step 2: run rollup node for an originated rollup" ;
  let* genesis_info =
    Client.RPC.call ~hooks client
    @@ RPC.get_chain_block_context_smart_rollups_smart_rollup_genesis_info
         sc_rollup_address
  in
  let init_level = JSON.(genesis_info |-> "level" |> as_int) in

  let* () = Sc_rollup_node.run sc_rollup_node sc_rollup_address [] in
  let* level = Sc_rollup_node.wait_for_level sc_rollup_node init_level in

  Check.(level = init_level)
    Check.int
    ~error_msg:
      "Current level has moved past origination level (current = %L, expected \
       = %R)" ;

  Log.info
    "Step 3: set the PVM parameters; rollup node subscribes to slots 0, 2, 4 \
     and 6" ;
  let number_of_slots = parameters.number_of_slots in
  let attestation_lag = parameters.attestation_lag in
  let number_of_pages = slot_size / page_size in
  let subscribed_slots = "0:2:4:6" in
  let messages =
    [
      Format.sprintf
        "dal:%d:%d:%d:%s"
        number_of_slots
        attestation_lag
        number_of_pages
        subscribed_slots;
    ]
  in
  let* () = send_messages client messages in

  Log.info "Step 4: publish the slot headers for indexes 0, 1, and 2" ;
  let*! () =
    Client.publish_dal_commitment
      ~src:Constant.bootstrap1.alias
      ~slot_index:0
      ~commitment:commitment_0
      ~proof:proof_0
      client
  in
  let*! () =
    Client.publish_dal_commitment
      ~src:Constant.bootstrap2.alias
      ~slot_index:1
      ~commitment:commitment_1
      ~proof:proof_1
      client
  in
  let*! () =
    Client.publish_dal_commitment
      ~src:Constant.bootstrap3.alias
      ~slot_index:2
      ~commitment:commitment_2
      ~proof:proof_2
      client
  in

  Log.info "Step 5: check that the slot headers are fetched by the rollup node" ;
  let* () = bake_for client in
  let* slots_published_level =
    Sc_rollup_node.wait_for_level sc_rollup_node (init_level + 2)
  in
  let* slots_headers =
    Sc_rollup_node.RPC.call ~rpc_hooks sc_rollup_node
    @@ Sc_rollup_rpc.get_global_block_dal_slot_headers ()
  in
  let commitments =
    slots_headers
    |> List.map (fun Sc_rollup_rpc.{commitment; level = _; index = _} ->
           commitment)
  in
  let expected_commitments = [commitment_0; commitment_1; commitment_2] in
  Check.(commitments = expected_commitments)
    (Check.list Check.string)
    ~error_msg:"Unexpected list of slot headers (current = %L, expected = %R)" ;

  Log.info "Step 6: attest only slots 1 and 2" ;
  let* () = repeat (attestation_lag - 1) (fun () -> bake_for client) in
  let* () =
    inject_dal_attestations_and_bake node client ~number_of_slots (Slots [2; 1])
  in
  let* slot_confirmed_level =
    Sc_rollup_node.wait_for_level
      sc_rollup_node
      (slots_published_level + attestation_lag)
  in
  Check.(slot_confirmed_level = slots_published_level + attestation_lag)
    Check.int
    ~error_msg:
      "Current level has moved past slot attestation level (current = %L, \
       expected = %R)" ;

  Log.info "Step 7: check that the two slots have been attested" ;
  let* downloaded_slots =
    Sc_rollup_node.RPC.call ~rpc_hooks sc_rollup_node
    @@ Sc_rollup_rpc.get_global_block_dal_processed_slots ()
  in
  let downloaded_confirmed_slots =
    List.filter (fun (_i, s) -> String.equal s "confirmed") downloaded_slots
  in
  let expected_number_of_confirmed_slots = 2 in

  Check.(
    List.length downloaded_confirmed_slots = expected_number_of_confirmed_slots)
    Check.int
    ~error_msg:
      "Unexpected number of slots that have been either downloaded or \
       unconfirmed (current = %L, expected = %R)" ;

  Log.info
    "Step 8: bake attestation_lag blocks so that the rollup node interprets \
     the previously published & attested slot(s)" ;
  let* () = repeat attestation_lag (fun () -> bake_for client) in

  let* level =
    Sc_rollup_node.wait_for_level
      sc_rollup_node
      (slot_confirmed_level + attestation_lag)
  in
  Check.(level = slot_confirmed_level + attestation_lag)
    Check.int
    ~error_msg:
      "Current level has moved past slot attestation level (current = %L, \
       expected = %R)" ;

  Log.info
    "Step 9: verify that the rollup node has downloaded slot 2; slot 0 is \
     unconfirmed, and slot 1 has not been downloaded" ;
  let confirmed_level_as_string = Int.to_string slot_confirmed_level in
  let* downloaded_slots =
    Sc_rollup_node.RPC.call ~rpc_hooks sc_rollup_node
    @@ Sc_rollup_rpc.get_global_block_dal_processed_slots
         ~block:confirmed_level_as_string
         ()
  in
  let downloaded_confirmed_slots =
    List.filter (fun (_i, s) -> String.equal s "confirmed") downloaded_slots
  in

  Log.info "Step 10: check the first page of the two attested slots' content" ;
  let expected_number_of_confirmed_slots = 2 in
  Check.(
    List.length downloaded_confirmed_slots = expected_number_of_confirmed_slots)
    Check.int
    ~error_msg:
      "Unexpected number of slots that have been either downloaded or \
       unconfirmed (current = %L, expected = %R)" ;
  let submitted_slots_contents =
    [slot_contents_0; slot_contents_1; slot_contents_2]
  in
  let* () =
    Lwt_list.iteri_s
      (fun index (slot_index, _status) ->
        Check.(
          (index + 1 = slot_index)
            int
            ~error_msg:"unexpected slot index (current = %L, expected = %R)") ;
        let slot_commitment = List.nth commitments slot_index in
        let* slot_pages =
          Dal_RPC.(call dal_node @@ slot_pages slot_commitment)
        in
        let relevant_page = List.nth slot_pages 0 in
        let confirmed_slot_content =
          List.nth submitted_slots_contents slot_index
        in
        let message =
          String.sub relevant_page 0 (String.length confirmed_slot_content)
        in
        Check.(message = confirmed_slot_content)
          Check.string
          ~error_msg:"unexpected message in slot (current = %L, expected = %R)" ;
        unit)
      downloaded_confirmed_slots
  in
  match expand_test with
  | None -> return ()
  | Some f -> f ~protocol client sc_rollup_address sc_rollup_node

let check_saved_value_in_pvm ~rpc_hooks ~name ~expected_value sc_rollup_node =
  let* encoded_value =
    Sc_rollup_node.RPC.call sc_rollup_node ~rpc_hooks
    @@ Sc_rollup_rpc.get_global_block_state ~key:(sf "vars/%s" name) ()
  in
  match Data_encoding.(Binary.of_bytes int31) @@ encoded_value with
  | Error error ->
      failwith
        (Format.asprintf
           "The arithmetic PVM has an unexpected state: %a"
           Data_encoding.Binary.pp_read_error
           error)
  | Ok value ->
      Check.(
        (value = expected_value)
          int
          ~error_msg:
            "Invalid value in rollup state (current = %L, expected = %R)") ;
      return ()

let rollup_node_interprets_dal_pages ~protocol:_ client sc_rollup sc_rollup_node
    =
  let* genesis_info =
    Client.RPC.call ~hooks client
    @@ RPC.get_chain_block_context_smart_rollups_smart_rollup_genesis_info
         sc_rollup
  in
  let init_level = JSON.(genesis_info |-> "level" |> as_int) in
  let* level =
    Sc_rollup_node.wait_for_level ~timeout:120. sc_rollup_node init_level
  in

  (* The Dal content is as follows:
      - the page 0 of slot 0 contains 10,
      - the page 0 of slot 1 contains 200,
      - the page 0 of slot 2 contains 400.
     Only slot 1 abd 2 are confirmed. But PVM Arith only interprets even
     slots, we expect to have value = 502
     (including the values 99 and 3 send via Inbox).
  *)
  let expected_value = 502 in
  (* The code should be adapted if the current level changes. *)
  let* () = send_messages client [" 99 3 "; " + + value"] in
  let* () = repeat 2 (fun () -> bake_for client) in
  let* _lvl =
    Sc_rollup_node.wait_for_level ~timeout:120. sc_rollup_node (level + 1)
  in
  check_saved_value_in_pvm
    ~rpc_hooks
    ~name:"value"
    ~expected_value
    sc_rollup_node

(* Test that the rollup kernel can fetch and store a requested DAL page. Works as follows:
   - Originate a rollup with a kernel that:
      - Downloads page 0 from slot 0 published at level [current_level - attestation_lag].
      - Writes the downloaded slot contents to "/output" in durable storage.
   - At level N, publish a slot to the L1 and DAL.
   - Bake until [attestation_lag] blocks so the L1 attests the published slot.
   - Confirm that the kernel downloaded the slot and wrote the content to "/output/slot-<index>". *)
let test_reveal_dal_page_in_fast_exec_wasm_pvm _protocol parameters dal_node
    sc_rollup_node _sc_rollup_address node client pvm_name =
  Log.info "Assert attestation_lag value." ;
  (* TODO: https://gitlab.com/tezos/tezos/-/issues/6270
     Make the kernel robust against attestation_lag changes. *)
  Check.(
    (parameters.Dal.Parameters.attestation_lag = 4)
      int
      ~error_msg:
        "The kernel used in the test assumes attestation_lag of %R, got %L") ;
  let slot_size = parameters.cryptobox.slot_size in
  Check.(
    (slot_size = 32768)
      int
      ~error_msg:"The kernel used in the test assumes slot_size of %R, got %L") ;
  Check.(
    (parameters.cryptobox.page_size = 128)
      int
      ~error_msg:"The kernel used in the test assumes page_size of %R, got %L") ;
  Log.info "Originate rollup." ;
  let* {boot_sector; _} =
    Sc_rollup_helpers.prepare_installer_kernel
      ~preimages_dir:
        (Filename.concat (Sc_rollup_node.data_dir sc_rollup_node) "wasm_2_0_0")
      Constant.WASM.dal_echo_kernel
  in
  let* sc_rollup_address =
    Client.Sc_rollup.originate
      ~burn_cap:Tez.(of_int 9999999)
      ~alias:"dal_echo_kernel"
      ~src:Constant.bootstrap1.alias
      ~kind:"wasm_2_0_0"
      ~boot_sector
      ~parameters_ty:"unit"
      client
  in
  let* () = bake_for client in
  let* () =
    Sc_rollup_node.run sc_rollup_node sc_rollup_address [Log_kernel_debug]
  in
  let slot_size = parameters.cryptobox.slot_size in
  Log.info "Store slot content to DAL node and submit header." ;
  let slot_content = generate_dummy_slot slot_size in
  let* () =
    publish_store_and_attest_slot
      client
      node
      dal_node
      Constant.bootstrap1
      ~index:0
      ~content:(Helpers.make_slot ~slot_size slot_content)
      ~attestation_lag:parameters.attestation_lag
      ~number_of_slots:parameters.number_of_slots
  in
  let* level = Node.get_level node in
  Log.info "Assert that the slot was attested." ;
  let* {dal_attestation; _} =
    Node.RPC.(call node @@ get_chain_block_metadata ())
  in
  Check.((Some [|true|] = dal_attestation) (option (array bool)))
    ~error_msg:"Unexpected DAL attestations: expected %L, got %R" ;
  Log.info "Wait for the rollup node to catch up to the latest level." ;
  let* _ = Sc_rollup_node.wait_for_level ~timeout:3. sc_rollup_node level in
  Log.info "Read and assert against value written in durable storage." ;
  let key = "/output/slot-0" in
  let* value_written =
    Sc_rollup_node.RPC.call sc_rollup_node ~rpc_hooks
    @@ Sc_rollup_rpc.get_global_block_durable_state_value
         ~pvm_kind:pvm_name
         ~operation:Sc_rollup_rpc.Value
         ~key
         ()
  in
  let encoded_slot_content =
    match Hex.of_string slot_content with `Hex s -> s
  in
  Check.(
    (Some encoded_slot_content = value_written)
      (option string)
      ~error_msg:"Expected value written in /output/slot-0 to be %L, got %R") ;
  unit

let check_profiles ~__LOC__ dal_node ~expected =
  let* profiles = Dal_RPC.(call dal_node @@ get_profiles ()) in
  return
    Check.(
      (profiles = expected)
        Dal.Check.profiles_typ
        ~error_msg:
          (__LOC__ ^ " : Unexpected profiles (Actual: %L <> Expected: %R)"))

let check_topics_peers ~__LOC__ ~subscribed dal_node ~expected =
  let normalize_peers l = List.sort String.compare l in
  let compare_topics {Dal.RPC.topic_slot_index = s1; topic_pkh = p1}
      {Dal.RPC.topic_slot_index = s2; topic_pkh = p2} =
    let c = Int.compare s1 s2 in
    if c = 0 then String.compare p1 p2 else c
  in
  let normalize_topics_peers l =
    l
    |> List.map (fun (topic, peers) -> (topic, normalize_peers peers))
    |> List.sort (fun (t1, _p1) (t2, _p2) -> compare_topics t1 t2)
  in
  let* topic_peers = Dal_RPC.(call dal_node @@ get_topics_peers ~subscribed) in
  return
    Check.(
      (normalize_topics_peers topic_peers = normalize_topics_peers expected)
        Dal.Check.topics_peers_typ
        ~error_msg:
          (__LOC__
         ^ " : Unexpected topic - peers association (Actual: %L <> Expected: \
            %R)"))

let test_dal_node_test_patch_profile _protocol _parameters _cryptobox _node
    _client dal_node =
  let check_bad_attester_pkh_encoding profile =
    let* response = Dal_RPC.(call_raw dal_node @@ patch_profiles [profile]) in
    return @@ RPC_core.check_string_response ~code:400 response
  in
  let patch_profile_rpc profile =
    Dal_RPC.(call dal_node (patch_profiles [profile]))
  in
  let profile1 = Dal_RPC.Attester Constant.bootstrap1.public_key_hash in
  let profile2 = Dal_RPC.Attester Constant.bootstrap2.public_key_hash in
  (* We start with empty profile list *)
  let* () = check_profiles ~__LOC__ dal_node ~expected:(Operator []) in
  (* Adding [Attester] profile with pkh that is not encoded as
     [Tezos_crypto.Signature.Public_key_hash.encoding] should fail. *)
  let* () = check_bad_attester_pkh_encoding (Attester "This is invalid PKH") in
  (* Test adding duplicate profiles stores profile only once *)
  let* () = patch_profile_rpc profile1 in
  let* () = patch_profile_rpc profile1 in
  let* () = check_profiles ~__LOC__ dal_node ~expected:(Operator [profile1]) in
  (* Test adding multiple profiles *)
  let* () = patch_profile_rpc profile2 in
  let* () =
    check_profiles ~__LOC__ dal_node ~expected:(Operator [profile1; profile2])
  in
  (* Test that the patched profiles are persisted after restart using SIGTERM. *)
  let* () = Dal_node.terminate dal_node in
  Log.info "restart DAL node (1)" ;
  let* () = Dal_node.run dal_node ~wait_ready:true in

  let* () =
    check_profiles ~__LOC__ dal_node ~expected:(Operator [profile1; profile2])
  in
  (* Test whether the patched profiles persist after a restart using SIGSTOP
     (that is, even if we stop the DAL node abruptly). *)
  let profile3 = Dal_RPC.Attester Constant.bootstrap3.public_key_hash in
  let* () = patch_profile_rpc profile3 in
  let* () = Dal_node.stop dal_node in
  let* () = Dal_node.kill dal_node in
  Log.info "restart DAL node (2)" ;
  let* () = Dal_node.run dal_node ~wait_ready:true in
  check_profiles
    ~__LOC__
    dal_node
    ~expected:(Operator [profile1; profile2; profile3])

(* Check that result of the DAL node's
   GET /profiles/<public_key_hash>/attested_levels/<level>/assigned_shard_indices
   is consistent with the result of the L1 node GET dal/shards . *)
let test_dal_node_get_assigned_shard_indices _protocol _parameters _cryptobox
    node _client dal_node =
  let pkh = Constant.bootstrap1.public_key_hash in
  let* {level; _} =
    Node.RPC.(call node @@ get_chain_block_helper_current_level ())
  in
  let* committee_from_l1 = Dal.Committee.at_level node ~level () in
  let* shards_from_dal =
    Dal_RPC.(call dal_node @@ get_assigned_shard_indices ~level ~pkh)
  in
  match
    committee_from_l1
    |> List.find_opt (fun member ->
           String.equal member.Dal.Committee.attester pkh)
  with
  | None -> Test.fail ~__LOC__ "pkh %S not found in committee from L1." pkh
  | Some member ->
      let shards_from_l1 = member.indexes in
      Check.(
        (shards_from_dal = shards_from_l1)
          (list int)
          ~error_msg:
            "Shard indexes does not match between DAL and L1  (From DAL: %L <> \
             From L1: %R)") ;
      unit

let test_dal_node_get_attestable_slots _protocol parameters cryptobox node
    client dal_node =
  let slot_size = parameters.Dal.Parameters.cryptobox.slot_size in
  let store_slot s = Helpers.(store_slot dal_node @@ make_slot ~slot_size s) in
  let number_of_slots = parameters.Dal.Parameters.number_of_slots in
  Log.info "Inject the shards of slots 1 and 3." ;
  let slot1_content = "slot 1" in
  let slot2_content = "slot 2" in
  let slot3_content = "slot 3" in
  let* _commitment, _proof = store_slot slot1_content in
  let* _commitment, _proof = store_slot slot3_content in
  Log.info "Publish slots 1 and 2 (inject and bake two blocks)." ;
  let* level = next_level node in
  let publish source ~index message =
    let* _op_hash =
      publish_dummy_slot ~source ~index ~message cryptobox client
    in
    unit
  in
  let* () = publish Constant.bootstrap1 ~index:0 slot1_content in
  let* () = publish Constant.bootstrap2 ~index:2 slot2_content in
  let wait_block_processing = wait_for_layer1_final_block dal_node level in
  (* bake three blocks: at [level + 1] the commitments are published, at [level +
     3] the commitments become final *)
  let* () = bake_for ~count:3 client in
  let* () = wait_block_processing in
  Log.info "Check attestability of slots." ;
  let attested_level = level + parameters.attestation_lag in
  let rec iter i =
    if i < 0 then unit
    else
      let attester = Account.Bootstrap.keys.(i) in
      (* Note: we assume that the key has at least an assigned shard index. *)
      let* res =
        Dal_RPC.(
          call dal_node @@ get_attestable_slots ~attester ~attested_level)
      in
      match res with
      | Not_in_committee ->
          Test.fail "attester %s not in committee" attester.alias
      | Attestable_slots slots ->
          Check.(
            (number_of_slots = List.length slots)
              int
              ~error_msg:"Expected %L slots (got %R)") ;
          (match slots with
          | true :: rest when List.for_all (fun b -> not b) rest ->
              (* 1st slot is attestable; the rest are not: the 2nd is not because
                 the shards are not available; the rest are not because they are not
                 published *)
              ()
          | _ -> Test.fail "Unexpected result") ;
          iter (i - 1)
  in
  let* () = iter (Array.length Account.Bootstrap.keys - 1) in
  Log.info "Check case when pkh not in the DAL committee." ;
  let* new_account = Client.gen_and_show_keys client in
  let* res =
    Dal_RPC.(
      call dal_node
      @@ get_attestable_slots ~attester:new_account ~attested_level)
  in
  match res with
  | Not_in_committee -> return ()
  | Attestable_slots _ ->
      Test.fail "attester %s is in committee!" new_account.alias

(* This test checks that the attester correctly emits attestations, by
   publishing a slot per level for a few levels, then checking that the slots
   are attested or not, depending on whether or not all delegates attested the
   slots. We use [attestation_threshold = 100] to this end; with a smaller
   threshold it is harder to control whether the slot will be attested or not
   (one would have to take into account the distribution of shard indexes to
   delegates).

   There are two variants of the test: with and without the baker daemon. See
   below for the version not using the daemon (only using `bake for`).

   In this version, slots are still published by baking with `bake for`, because
   when running the baker daemon, it is harder to control the time of publishing
   of a slot. See the end-to-end tests for a version without `bake for`.
*)
let test_attester_with_daemon protocol parameters cryptobox node client dal_node
    =
  Check.((parameters.Dal.Parameters.attestation_threshold = 100) int)
    ~error_msg:"attestation_threshold value (%L) should be 100" ;
  let dal_node_endpoint = Helpers.endpoint dal_node in
  let number_of_slots = parameters.Dal.Parameters.number_of_slots in
  let slot_size = parameters.cryptobox.slot_size in
  let slot_idx level = level mod number_of_slots in
  let num_bakers = Array.length Account.Bootstrap.keys in
  let all_delegates =
    Account.Bootstrap.keys |> Array.to_list
    |> List.map (fun key -> key.Account.alias)
  in
  let publish source ~index message =
    let* _op_hash =
      publish_dummy_slot ~source ~index ~message cryptobox client
    in
    unit
  in
  let publish_and_store level =
    let source = Account.Bootstrap.keys.(level mod num_bakers) in
    let index = slot_idx level in
    let slot_content =
      Format.asprintf "content at level %d index %d" level index
    in
    let* () = publish source ~index slot_content in
    let* _commitment, _proof =
      Helpers.(store_slot dal_node @@ make_slot ~slot_size slot_content)
    in
    unit
  in
  let publish_and_bake ~init_level ~target_level =
    Log.info
      "Publish (inject and bake) a slot header at each level from %d to %d."
      init_level
      target_level ;
    let rec iter level =
      if level > target_level then return ()
      else
        let* () = publish_and_store level in
        (* bake (and attest) with all available delegates to go faster *)
        let* () = bake_for ~dal_node_endpoint client in
        let* _ = Node.wait_for_level node level in
        iter (level + 1)
    in
    iter init_level
  in
  let run_baker delegates target_level =
    let* baker =
      Baker.init
        ~event_sections_levels:[(Protocol.name protocol ^ ".baker", `Debug)]
        ~protocol
        ~dal_node
        ~delegates
        ~state_recorder:true
        node
        client
    in
    let* _ = Node.wait_for_level node target_level in
    Baker.terminate baker
  in

  (* Test goal: the published slot at levels in [first_level, intermediary_level - 1]
     should be attested, the one at levels in at levels in [intermediary_level,
     max_level - 1] should not be attested. *)
  let* first_level = next_level node in
  let intermediary_level =
    (* We want at least two levels for which the published slot is attested. *)
    first_level + 2
  in
  let max_level =
    (* We want at least two levels for which the published slot is unattested;
       we add 2 for "safety"; see discussion (D) below. *)
    intermediary_level + 2 + 2
  in
  (* We want [max_level - attestation_lag < first_level], so that the
     delegates that attest at the last level baked by `bake for` (that is, at
     [max_level]) have no published slot to attest, in order not interfere
     with the attestations done by the baker daemon. *)
  Check.((parameters.attestation_lag > max_level - first_level) int)
    ~error_msg:
      "attestation_lag (%L) should be higher than [max_level - first_level] \
       (which is %R)" ;
  let wait_block_processing = wait_for_layer1_head dal_node max_level in
  let* () = publish_and_bake ~init_level:first_level ~target_level:max_level in
  let* () = wait_block_processing in
  let last_level_of_first_baker =
    intermediary_level + parameters.attestation_lag
  in
  let last_level_of_second_baker = max_level + parameters.attestation_lag + 1 in
  (* We need this level to be processed by the DAL node in order to make the
     necessary checks. *)
  let wait_for_dal_node =
    wait_for_layer1_final_block
      dal_node
      (max_level + parameters.attestation_lag - 1)
  in

  Log.info
    "Run the first baker for all delegates till at least level %d."
    last_level_of_first_baker ;
  let* () = run_baker all_delegates last_level_of_first_baker in
  (* (D) We tried to stop the baker as soon as it reaches
     [intermediary_level + attestation_lag], but it may have baked a few
     blocks more *)
  let* actual_intermediary_level = Node.get_level node in
  Log.info "The first baker baked till level %d." actual_intermediary_level ;

  let* dal_attestations =
    get_validated_dal_attestations_in_mempool node actual_intermediary_level
  in
  let num_dal_attestations = List.length dal_attestations in
  Log.info
    "The number of validated DAL attestations in the mempool is %d."
    num_dal_attestations ;

  (* Let L := actual_intermediary_level and PL := L - lag, the corresponding
     publish level.  The second baker may build a new block (1) at level L (and
     a higher round) or (2) directly at level L+1. However, independently of
     this, when it builds the block at level L+1, it should take into account
     the DAL attestations at level L that are present in the mempool. If there
     already 5 attestations then the slot at PL should be attested. If not, it
     cannot be attested because the second baker may only include, when in case
     (2), 4 new attestations. *)
  let first_not_attested_published_level =
    if num_dal_attestations = List.length all_delegates then
      actual_intermediary_level + 2 - parameters.attestation_lag
    else actual_intermediary_level + 1 - parameters.attestation_lag
  in
  Log.info
    "We set first_not_attested_published_level to %d."
    first_not_attested_published_level ;

  Log.info
    "Run the second baker for some (not all) delegates till at least level %d."
    last_level_of_second_baker ;
  let* () = run_baker (List.tl all_delegates) last_level_of_second_baker in
  let* () = wait_for_dal_node in

  Log.info "Check the attestation status of the published slots." ;
  let rec check_attestations level =
    if level >= max_level then return ()
    else
      let* slot_headers =
        Dal_RPC.(call dal_node @@ get_published_level_headers level)
      in
      Check.(
        (1 = List.length slot_headers)
          int
          ~error_msg:"Expected a single header (got %R headers)") ;
      let Dal_RPC.{slot_level; slot_index; status; _} = List.hd slot_headers in
      Check.((level = slot_level) int ~error_msg:"Expected level %L (got %R)") ;
      Check.(
        (slot_idx level = slot_index)
          int
          ~error_msg:"Expected index %L (got %R)") ;
      (* Before [first_not_attested_published_level], it should be [attested],
         and above (and including) [first_not_attested_published_level], it
         should be [unattested]. *)
      let expected_status =
        if level < first_not_attested_published_level then "attested"
        else "unattested"
      in
      Check.(
        (expected_status = status)
          string
          ~error_msg:"Expected status %L (got %R)") ;
      check_attestations (level + 1)
  in
  check_attestations first_level

(* This is the version of [test_attester_with_daemon] that does not use the
   baker daemon, only `bake for`. *)
let test_attester_with_bake_for _protocol parameters cryptobox node client
    dal_node =
  Check.((parameters.Dal.Parameters.attestation_threshold = 100) int)
    ~error_msg:"attestation_threshold value (%L) should be 100" ;
  let dal_node_endpoint = Helpers.endpoint dal_node in
  let number_of_slots = parameters.Dal.Parameters.number_of_slots in
  let slot_size = parameters.cryptobox.slot_size in
  let lag = parameters.attestation_lag in
  let slot_idx level = level mod number_of_slots in
  let num_bakers = Array.length Account.Bootstrap.keys in
  let all_delegates =
    Account.Bootstrap.keys |> Array.to_list
    |> List.map (fun key -> key.Account.alias)
  in
  let not_all_delegates = List.tl all_delegates in

  (* Test goal: the published slot at a level in [first_level,
     intermediary_level] should be attested, the one at a level in
     [intermediary_level + 1, last_checked_level] should not be attested. *)
  let attested_levels = 2 in
  let unattested_levels = 2 in
  let* first_level = next_level node in
  let intermediary_level = first_level + attested_levels - 1 in
  let last_checked_level = intermediary_level + unattested_levels - 1 in
  let last_level = last_checked_level + lag + 1 in

  Log.info "attestation_lag = %d" lag ;

  (* Publish and bake with client *)
  let publish source ~index message =
    let* _op_hash =
      publish_dummy_slot ~source ~index ~message cryptobox client
    in
    unit
  in
  let publish_and_store level =
    let source = Account.Bootstrap.keys.(level mod num_bakers) in
    let index = slot_idx level in
    let slot_content =
      Format.asprintf "content at level %d index %d" level index
    in
    let* () = publish source ~index slot_content in
    let* _commitment, _proof =
      Helpers.(
        store_slot ~with_proof:false dal_node
        @@ make_slot ~slot_size slot_content)
    in
    Log.info "Slot with %d index (normally) published at level %d" index level ;
    unit
  in
  let publish_and_bake ~from_level ~to_level delegates =
    Log.info
      "Publish (inject and bake) a slot header at each level from %d to %d."
      from_level
      to_level ;
    let rec iter level =
      if level > to_level then return ()
      else
        let* () = publish_and_store level in
        let* () =
          bake_for ~delegates:(`For delegates) ~dal_node_endpoint client
        in
        let* _ = Node.wait_for_level node level in
        iter (level + 1)
    in
    iter from_level
  in

  let wait_level = last_level + 1 in
  let wait_block_processing_on_l1 = wait_for_layer1_head dal_node wait_level in

  let wait_block_processing_on_dal =
    wait_for_layer1_final_block dal_node (wait_level - 2)
  in

  let* () =
    publish_and_bake
      ~from_level:first_level
      ~to_level:(intermediary_level + lag)
      all_delegates
  in
  let* () =
    publish_and_bake
      ~from_level:(intermediary_level + lag + 1)
      ~to_level:last_level
      not_all_delegates
  in
  let* () = bake_for client in
  let* _lvl = wait_block_processing_on_l1 in
  let* () = wait_block_processing_on_dal in

  Log.info "Check the attestation status of the published slots." ;
  let rec check_attestations level =
    if level > last_checked_level then return ()
    else
      let* slot_headers =
        Dal_RPC.(call dal_node @@ get_published_level_headers level)
      in
      Check.(
        (1 = List.length slot_headers)
          int
          ~error_msg:"Expected a single header (got %R headers)") ;
      let Dal_RPC.{slot_level; slot_index; status; _} = List.hd slot_headers in
      Check.((level = slot_level) int ~error_msg:"Expected level %L (got %R)") ;
      Check.(
        (slot_idx level = slot_index)
          int
          ~error_msg:"Expected index %L (got %R)") ;
      let expected_status =
        if level <= intermediary_level then "attested" else "unattested"
      in
      Check.(
        (expected_status = status)
          string
          ~error_msg:"Expected status %L (got %R)") ;
      check_attestations (level + 1)
  in
  check_attestations first_level

(** End-to-end DAL Tests.  *)

(* This function publishes the DAL slot whose index is [slot_index] for the
   levels between [from + beforehand_slot_injection] and
   [into + beforehand_slot_injection] with a payload equal to the slot's
   publish_level.

   The parameter [beforehand_slot_injection] (whose value should be at least
   one) allows, for a published level, to inject the slots an amount of blocks
   ahead. In other terms, we have:

   [published level = injection level + beforehand_slot_injection]

   The publication consists in sending the slot to a DAL node, computing its
   shards on the DAL node and associating it to a slot index and published
   level. On the L1 side, a manager operation publish_commitment is also sent.

   Having the ability to inject some blocks ahead (thanks to
   [beforehand_slot_injection]) allows some pipelining, as shards computation
   may take an amount of time to complete.

   The function returns the sum of the payloads submitted via DAL.
*)
let slot_producer ?(beforehand_slot_injection = 1) ~slot_index ~slot_size ~from
    ~into dal_node l1_node l1_client =
  Check.(
    (beforehand_slot_injection >= 1)
      int
      ~error_msg:
        "Value of beforehand_slot_injection should be at least 1 (got %L)") ;
  (* We add the successive slots' contents (that is, published_level-s) injected
     into DAL and L1, and store the result in [!sum]. The final value is then
     returned by this function. *)
  let sum = ref 0 in
  let loop ~from ~into ~task =
    fold
      (into - from + 1)
      ()
      (fun index () ->
        let current_level = index + from in
        task current_level)
  in
  let publish_and_store_slot_promises = ref [] in
  (* This is the account used to sign injected slot headers on L1. *)
  let source = Constant.bootstrap2 in
  let* counter = Operation.get_next_counter ~source l1_client in
  let counter = ref counter in
  let task current_level =
    let* level = Node.wait_for_level l1_node current_level in
    (* We expected to advance level by level, otherwise, the test should fail. *)
    Check.(
      (current_level = level) int ~error_msg:"Expected level is %L (got %R)") ;
    let (publish_level as payload) = level + beforehand_slot_injection in
    sum := !sum + payload ;
    Log.info
      "[e2e.slot_producer] publish slot %d for level %d with payload %d at \
       level %d"
      slot_index
      publish_level
      payload
      level ;
    let promise =
      publish_and_store_slot
        ~with_proof:true
        ~force:true
        ~counter:!counter
        l1_client
        dal_node
        source
        ~index:slot_index
      @@ Helpers.make_slot ~slot_size (sf " %d " payload)
    in
    incr counter ;
    publish_and_store_slot_promises :=
      promise :: !publish_and_store_slot_promises ;
    unit
  in
  let* () = loop ~from ~into ~task in
  let l =
    List.map (fun p ->
        let* _p = p in
        unit)
    @@ List.rev !publish_and_store_slot_promises
  in
  let* () = Lwt.join l in
  Log.info "[e2e.slot_producer] will terminate" ;
  return !sum

(** Given a list of SORU node operators, this function allows to create and run new
    DAL and SORU nodes, where:
    - Each fresh rollup node is configured with a fresh DAL node and a key
    operator;
    - Each fresh DAL node is either connected to the original DAL node if the
    associated operator has an even index in the list of node operators, or to
    the previously generated DAL node otherwise.

    Each element of the [extra_nodes_operators] list can actually be [None], in
    which case the corresponding rollup node is launched in observer mode, or
    [Some account], in which case the [account] is used as the default
    operator of the SORU node. *)
let create_additional_nodes ~extra_node_operators rollup_address l1_node
    l1_client dal_node =
  (* The mutable variable [connect_dal_node_to] below is used to diversify a bit
     the topology of the DAL nodes network as follows:

     [node with odd idx] -- [node with even idx] -- init_node

     So, we initialize its value to [dal_node]. *)
  let dal_node_producer = Dal_node.create ~node:l1_node () in
  let* () = Dal_node.init_config ~producer_profiles:[0] dal_node_producer in
  let* () = Dal_node.run dal_node_producer in
  let connect_dal_node_to = ref dal_node in
  let* nodes =
    Lwt_list.mapi_s
      (fun index key_opt ->
        (* We create a new DAL node and initialize it. *)
        let fresh_dal_node = Dal_node.create ~node:l1_node () in
        let* () = Dal_node.init_config fresh_dal_node in

        (* We connect the fresh DAL node to another node, start it and update the
           value of [connect_dal_node_to] to generate the topology above: *)
        update_neighbors fresh_dal_node [!connect_dal_node_to] ;
        update_neighbors fresh_dal_node [dal_node_producer] ;
        let* () = Dal_node.run fresh_dal_node in
        connect_dal_node_to :=
          if index mod 2 = 0 then fresh_dal_node else dal_node ;

        (* We create a new SORU node, connected to the new DAL node, and
           initialize it. *)
        let rollup_mode =
          Sc_rollup_node.(if Option.is_none key_opt then Observer else Operator)
        in
        let sc_rollup_node =
          Sc_rollup_node.create
            ~dal_node:fresh_dal_node
            rollup_mode
            l1_node
            ~base_dir:(Client.base_dir l1_client)
            ?default_operator:key_opt
        in
        (* We start the rollup node and create a client for it. *)
        let* () = Sc_rollup_node.run sc_rollup_node rollup_address [] in
        return (fresh_dal_node, sc_rollup_node))
      extra_node_operators
  in
  return (dal_node_producer, nodes)

(* This function allows to run an end-to-end test involving L1, DAL and rollup
   nodes. For that it:

   - It configures the PVM Arith's DAL parameters with those of L1 (via an inbox
   message). The PVM is asked to track slot index 5;

   - It starts a baker daemon with all available bootstrap delegates;

   - It starts a [slot_producer] Lwt promise, that will publish
   [number_of_dal_slots] slots on L1 and on the DAL node. The slots' content is
   basically the level at which they are published;

   - Once the slots are processed and attested; an inbox message is sent to the
   Arith PVM to sum all the received integers and to store the result in a
   variable called "value";

   - We finally check that there is a "value" variable in the PVM whose payload
   is the sum of levels as returned by [slot_producer].
*)
let e2e_test_script ?expand_test:_ ?(beforehand_slot_injection = 1)
    ?(extra_node_operators = []) ~slot_index protocol parameters dal_node
    sc_rollup_node sc_rollup_address l1_node l1_client _pvm_name
    ~number_of_dal_slots =
  let slot_size = parameters.Dal.Parameters.cryptobox.slot_size in
  let* current_level = Node.get_level l1_node in
  Log.info "[e2e.startup] current level is %d@." current_level ;
  let* () = Sc_rollup_node.run sc_rollup_node sc_rollup_address [] in
  let bootstrap_dal_node = Dal_node.create ~node:l1_node () in
  let producer_profiles = [slot_index] in
  let* () =
    Dal_node.init_config
      ~peers:[Dal_node.listen_addr dal_node]
      ~bootstrap_profile:true
      bootstrap_dal_node
  in
  let* () = Dal_node.run ~event_level:`Debug bootstrap_dal_node in
  let bootstrap_dal_node_p2p_endpoint =
    Dal_node.listen_addr bootstrap_dal_node
  in
  (* Generate new DAL and rollup nodes if requested. *)
  let create_additional_nodes ~extra_node_operators sc_rollup_address l1_node
      l1_client =
    extra_node_operators
    |> Lwt_list.map_p (fun key_opt ->
           let fresh_dal_node = Dal_node.create ~node:l1_node () in
           let* () =
             match key_opt with
             | Some _ ->
                 Dal_node.init_config
                   ~peers:[bootstrap_dal_node_p2p_endpoint]
                   ~producer_profiles
                   fresh_dal_node
             | None ->
                 Dal_node.init_config
                   ~peers:[bootstrap_dal_node_p2p_endpoint]
                   ~observer_profiles:producer_profiles
                   fresh_dal_node
           in
           let* () = Dal_node.run ~event_level:`Debug fresh_dal_node in
           let rollup_mode =
             Sc_rollup_node.(
               if Option.is_none key_opt then Observer else Operator)
           in
           let sc_rollup_node =
             Sc_rollup_node.create
               ~dal_node:fresh_dal_node
               rollup_mode
               l1_node
               ~base_dir:(Client.base_dir l1_client)
               ?default_operator:key_opt
           in
           (* We start the rollup node and create a client for it. *)
           let* () = Sc_rollup_node.run sc_rollup_node sc_rollup_address [] in
           return (fresh_dal_node, sc_rollup_node))
  in
  let* additional_nodes =
    create_additional_nodes
      ~extra_node_operators
      sc_rollup_address
      l1_node
      l1_client
  in
  Log.info "Start running baker node" ;
  let baker_dal_node = Dal_node.create ~node:l1_node () in
  let* () =
    Dal_node.init_config ~peers:[bootstrap_dal_node_p2p_endpoint] baker_dal_node
  in
  let* () = Dal_node.run ~event_level:`Debug baker_dal_node in
  let producer_dal_node = Dal_node.create ~node:l1_node () in
  let* () =
    Dal_node.init_config
      ~peers:[bootstrap_dal_node_p2p_endpoint]
      ~producer_profiles
      producer_dal_node
  in
  let* () = Dal_node.run ~event_level:`Debug producer_dal_node in
  Log.info
    "[e2e.configure_pvm] configure PVM with DAL parameters via inbox message@." ;
  let Dal.Parameters.{attestation_lag; cryptobox; _} = parameters in
  (* We ask the Arith PVM of [_sc_rollup_address] to track the slot index 5 of
     the DAL. *)
  let* () =
    let number_of_slots = parameters.number_of_slots in
    let pages_per_slot = cryptobox.slot_size / cryptobox.page_size in
    let config =
      sf
        " dal:%d:%d:%d:%d "
        number_of_slots
        attestation_lag
        pages_per_slot
        slot_index
    in
    send_messages ~bake:false l1_client [config]
  in
  (* We need to bake some blocks so that the DAL node starts
     processing blocks and register the committee. *)
  let* () = bake_for l1_client ~count:2 in
  Log.info "[e2e.pvm] PVM Arith configured@." ;

  Log.info
    "[e2e.start_baker] spawn a baker daemon with all bootstrap accounts@." ;
  let* _baker =
    Baker.init ~dal_node:baker_dal_node ~protocol l1_node l1_client
  in

  (* To be sure that we just moved to [start_dal_slots_level], we wait and extra
     level. *)
  let* start_dal_slots_level =
    let* next_level = next_level l1_node in
    Node.wait_for_level l1_node next_level
  in
  let end_dal_slots_level = start_dal_slots_level + number_of_dal_slots - 1 in

  (* start_dal = 4, end_dal = 5 *)
  Log.info
    "[e2e.start_slot_producer] from level %d to level %d@."
    start_dal_slots_level
    end_dal_slots_level ;
  (* The slot producer will publish [number_of_dal_slots] sucessive slots of
     size [slot_size] with index [tracked_slots]. *)
  let* expected_value =
    slot_producer
      ~beforehand_slot_injection
      ~slot_index
      ~from:start_dal_slots_level
      ~into:end_dal_slots_level
      ~slot_size
      producer_dal_node
      l1_node
      l1_client
  in
  (* Wait until the last published slot is included and attested in a final block. *)
  let* _lvl =
    Node.wait_for_level
      l1_node
      (end_dal_slots_level + attestation_lag + beforehand_slot_injection + 1)
  in

  Log.info
    "[e2e.sum_and_store] send an inbox messsage to the PVM to sum the received \
     payloads, and store the result in a 'value' variable@." ;
  let* level =
    let* level = Node.get_level l1_node in
    (* We send instructions "+...+ value" to the PVM of [number_of_dal_slots -
       1] additions, so that it sums the received slots' contents and store the
       result in a variable called "value". *)
    let do_sum = String.make (number_of_dal_slots - 1) '+' in
    let* () = send_messages ~bake:false l1_client [do_sum ^ " value"] in
    (* Wait sufficiently many levels so that the PVM interprets the message. *)
    let* level = Node.wait_for_level l1_node (level + 2) in
    return level
  in
  let* _ = Sc_rollup_node.wait_for_level ~timeout:30. sc_rollup_node level in
  Log.info
    "[e2e.final_check_1] check that the sum stored in the PVM is %d@."
    expected_value ;
  let* () =
    check_saved_value_in_pvm
      ~rpc_hooks
      ~name:"value"
      ~expected_value
      sc_rollup_node
  in

  (* Check the statuses of the additional nodes/PVMs, if any. *)
  Log.info
    "[e2e.final_check_2] Check %d extra nodes@."
    (List.length additional_nodes) ;
  Lwt_list.iter_s
    (fun (_dal_node, rollup_node) ->
      check_saved_value_in_pvm
        ~rpc_hooks
        ~name:"value"
        ~expected_value
        rollup_node)
    additional_nodes

(** Register end-to-end DAL Tests. *)

(* These are the parameters we vary for end-to-end tests. *)
type e2e_test = {
  constants : Protocol.constants;
  attestation_lag : int;
  block_delay : int;
  number_of_dal_slots : int;
  beforehand_slot_injection : int;
  num_extra_nodes : int;
  tags : string list;
}

let e2e_tests =
  (* TODO: https://gitlab.com/tezos/tezos/-/issues/4858

     Move tests that take time to long tests, in particular those with mainnet
     parameters. *)
  let test1 =
    {
      constants = Protocol.Constants_test;
      attestation_lag = 10;
      block_delay = 8;
      number_of_dal_slots = 2;
      beforehand_slot_injection = 1;
      num_extra_nodes = 3;
      tags = [Tag.slow];
    }
  in
  [test1]

(* This function allows to register new (end-to-end) tests using
   [scenario_with_all_nodes] helper. For that, it instantiate function
   [e2e_test_script] with the various configurations in [e2e_tests]. *)
let register_end_to_end_tests ~protocols =
  (* (Mainnet) Tests below are probably flaky because they depend on CPU
     spec/time, as we start a baker daemon, and we set a low block time to avoid
     monopolizing the CI. If it is an issue, those tests could be moved to long
     tests in the future. *)
  List.iter
    (fun test ->
      let {
        constants;
        attestation_lag;
        block_delay;
        number_of_dal_slots;
        beforehand_slot_injection;
        num_extra_nodes;
        tags;
      } =
        test
      in
      let network = Protocol.constants_to_string constants in
      let title =
        sf
          "%s_lag-%d_time-%d_preinject-%d_slots-%d"
          network
          attestation_lag
          block_delay
          beforehand_slot_injection
          number_of_dal_slots
      in
      let activation_timestamp =
        (* and starts it in the past enough so that one can bake
           [expected_bake_for_blocks] with the bake for command, without hitting
           a "Block in the future" error *and* continue from there with baker
           daemons (which cannot bake in the past) without a hitch.

           In the test, we have two [bake_for] invocations: one for the rollup
           origination and another to configure the PVM. Baker daemon is then
           started. *)
        let expected_bake_for_occurrences = 2 in
        Ptime.Span.of_int_s expected_bake_for_occurrences
      in
      (* Preparing the list of node operators for extra nodes. *)
      let extra_node_operators =
        (* So launch the extra SORU nodes in observer mode. So we don't actually
           need to provide public key hashes. *)
        List.init num_extra_nodes (fun _index -> None)
      in
      let slot_index = 5 in
      let producer_profiles = [slot_index] in
      let tags =
        ["e2e"; network; Tag.ci_disabled]
        @ (match constants with Constants_mainnet -> [Tag.slow] | _ -> [])
        @ tags
      in
      scenario_with_all_nodes
        ~producer_profiles
        ~custom_constants:constants
        ~slot_size:(1 lsl 17)
        ~page_size:4096
        ~redundancy_factor:8
        ~number_of_shards:512
        ~consensus_committee_size:512
        ~attestation_lag
        ~activation_timestamp:(Ago activation_timestamp)
        ~minimal_block_delay:(string_of_int block_delay)
        ~tags
        ~uses:(fun protocol -> [Protocol.baker protocol])
        title
        (e2e_test_script
           ~slot_index
           ~number_of_dal_slots
           ~beforehand_slot_injection
           ~extra_node_operators)
        protocols)
    e2e_tests

let wait_for_gossipsub_worker_event ~name dal_node lambda =
  Dal_node.wait_for dal_node (sf "gossipsub_worker_event-%s.v0" name) lambda

let check_expected expected found = if expected <> found then None else Some ()

let ( let*?? ) a b = Option.bind a b

let check_new_connection_event ~main_node ~other_node ~is_trusted =
  wait_for_gossipsub_worker_event ~name:"new_connection" main_node (fun event ->
      let*?? () =
        check_expected
          (Dal_node.read_identity other_node)
          JSON.(event |-> "peer" |> as_string)
      in
      check_expected is_trusted JSON.(event |-> "trusted" |> as_bool))

let check_disconnection_event dal_node ~peer_id =
  wait_for_gossipsub_worker_event
    ~name:"disconnection"
    dal_node
    (fun peer_event -> check_expected peer_id JSON.(peer_event |> as_string))

type peer_id = string

type event_with_topic =
  | Subscribe of peer_id
  | Unsubscribe of peer_id
  | Graft of peer_id
  | Prune of peer_id
  | Join
  | Leave

let event_with_topic_to_string = function
  | Subscribe _ -> "subscribe"
  | Unsubscribe _ -> "unsubscribe"
  | Graft _ -> "graft"
  | Prune _ -> "prune"
  | Join -> "join"
  | Leave -> "leave"

(** This function monitors the Gossipsub worker events whose name is given by
    [event_with_topic].

    More precisely, since topics depend on a pkh and the number of DAL slots,
    this function monitors all the events {pkh; slot_index = 0} ... {pkh;
    slot_index = num_slots - 1}. When the [already_seen_slots] array paramenter
    is used however, the events corresponding to slot indices marked with [true]
    in this array are not monitored.

    Depending on the value of [event_with_topic], some extra checks, such as the
    peer id in case of Graft and Subscribe, are also done.
*)
let check_events_with_topic ~event_with_topic dal_node ~num_slots
    ?(already_seen_slots = Array.make num_slots false) expected_pkh =
  assert (Array.length already_seen_slots = num_slots) ;
  let remaining =
    ref
      (Array.fold_left
         (fun remaining b -> if b then remaining else remaining + 1)
         0
         already_seen_slots)
  in
  let seen = Array.copy already_seen_slots in
  let get_slot_index_opt event =
    let*?? topic =
      match event_with_topic with
      | Subscribe expected_peer
      | Unsubscribe expected_peer
      | Graft expected_peer
      | Prune expected_peer ->
          let*?? () =
            check_expected
              expected_peer
              JSON.(event |-> "peer" |> JSON.as_string)
          in
          Some JSON.(event |-> "topic")
      | Join | Leave -> Some event
    in
    let*?? () =
      check_expected expected_pkh JSON.(topic |-> "pkh" |> JSON.as_string)
    in
    Some JSON.(topic |-> "slot_index" |> as_int)
  in
  wait_for_gossipsub_worker_event
    dal_node
    ~name:(event_with_topic_to_string event_with_topic)
    (fun event ->
      let*?? slot_index = get_slot_index_opt event in
      Check.(
        (seen.(slot_index) = false)
          bool
          ~error_msg:
            (sf "Slot_index %d already seen. Invariant broken" slot_index)) ;
      seen.(slot_index) <- true ;
      let () = remaining := !remaining - 1 in
      if !remaining = 0 && Array.for_all (fun b -> b) seen then Some ()
      else None)

type event_with_message = Publish_message | Message_with_header of peer_id

let event_with_message_to_string = function
  | Publish_message -> "publish_message"
  | Message_with_header _ -> "message_with_header"

(** This function monitors the Gossipsub worker events whose name is given by
    [event_with_message]. It's somehow similar to function
    {!check_events_with_topic}, except that what varies here is the shard index
    instead of slot index. Moreover, shards do not necessiraly start from 0 or
    end at number_of_shards - 1. *)
let check_events_with_message ~event_with_message dal_node ~number_of_shards
    ~shard_indexes ~expected_commitment ~expected_level ~expected_pkh
    ~expected_slot =
  let remaining = ref (List.length shard_indexes) in
  let seen = Array.make number_of_shards false in
  let get_shard_index_opt event =
    let topic_slot_index =
      JSON.(event |-> "topic" |-> "slot_index" |> as_int)
    in
    let topic_pkh = JSON.(event |-> "topic" |-> "pkh" |> as_string) in
    let level = JSON.(event |-> "message_id" |-> "level" |> as_int) in
    let slot_index = JSON.(event |-> "message_id" |-> "slot_index" |> as_int) in
    let shard_index =
      JSON.(event |-> "message_id" |-> "shard_index" |> as_int)
    in
    let pkh = JSON.(event |-> "message_id" |-> "pkh" |> as_string) in
    let commitment =
      JSON.(event |-> "message_id" |-> "commitment" |> as_string)
    in
    let*?? () = check_expected expected_pkh topic_pkh in
    let*?? () = check_expected expected_pkh pkh in
    let*?? () = check_expected expected_level level in
    let*?? () = check_expected expected_slot slot_index in
    let*?? () = check_expected expected_slot topic_slot_index in
    let*?? () = check_expected expected_commitment commitment in
    let*?? () =
      match event_with_message with
      | Publish_message -> Some ()
      | Message_with_header expected_peer_id ->
          check_expected expected_peer_id JSON.(event |-> "peer" |> as_string)
    in
    Some shard_index
  in
  let all_seen () =
    seen |> Array.to_seqi
    |> Seq.for_all (fun (i, b) -> if List.mem i shard_indexes then b else true)
  in
  wait_for_gossipsub_worker_event
    dal_node
    ~name:(event_with_message_to_string event_with_message)
    (fun event ->
      let*?? shard_index = get_shard_index_opt event in
      Check.(
        (seen.(shard_index) = false)
          bool
          ~error_msg:
            (sf "Shard_index %d already seen. Invariant broken" shard_index)) ;
      seen.(shard_index) <- true ;
      let () = remaining := !remaining - 1 in
      if !remaining = 0 && all_seen () then Some () else None)

type event_with_message_id = IHave of {pkh : string; slot_index : int} | IWant

let event_with_message_id_to_string = function
  | IHave _ -> "ihave"
  | IWant -> "iwant"

(** This function monitors the Gossipsub worker events whose name is given by
    [event_with_message_id]. It's somehow similar to function
    {!check_events_with_message}, but for IHave and IWant messages' events. *)
let check_events_with_message_id ~event_with_message_id dal_node
    ~number_of_shards ~shard_indexes ~expected_commitment ~expected_level
    ~expected_pkh ~expected_slot ~expected_peer =
  let remaining = ref (List.length shard_indexes) in
  let seen = Array.make number_of_shards false in
  let get_shard_indices_of_messages event =
    let*?? () =
      check_expected expected_peer JSON.(event |-> "peer" |> as_string)
    in
    let*?? () =
      match event_with_message_id with
      | IWant -> Some ()
      | IHave {pkh; slot_index} ->
          let topic = JSON.(event |-> "topic") in
          let*?? () = check_expected pkh expected_pkh in
          let*?? () = check_expected pkh JSON.(topic |-> "pkh" |> as_string) in
          check_expected slot_index JSON.(topic |-> "slot_index" |> as_int)
    in
    let message_ids = JSON.(event |-> "message_ids" |> as_list) in
    Option.some
    @@ List.map
         (fun id ->
           let level = JSON.(id |-> "level" |> as_int) in
           let slot_index = JSON.(id |-> "slot_index" |> as_int) in
           let shard_index = JSON.(id |-> "shard_index" |> as_int) in
           let pkh = JSON.(id |-> "pkh" |> as_string) in
           let commitment = JSON.(id |-> "commitment" |> as_string) in
           let*?? () = check_expected expected_pkh pkh in
           let*?? () = check_expected expected_level level in
           let*?? () = check_expected expected_slot slot_index in
           let*?? () = check_expected expected_commitment commitment in
           Some shard_index)
         message_ids
  in
  let all_seen () =
    seen |> Array.to_seqi
    |> Seq.for_all (fun (i, b) -> if List.mem i shard_indexes then b else true)
  in
  wait_for_gossipsub_worker_event
    ~name:(event_with_message_id_to_string event_with_message_id)
    dal_node
    (fun event ->
      let*?? shard_indices = get_shard_indices_of_messages event in
      List.iter
        (fun shard_index_opt ->
          match shard_index_opt with
          | None -> ()
          | Some shard_index ->
              Check.(
                (seen.(shard_index) = false)
                  bool
                  ~error_msg:
                    (sf
                       "Shard_index %d already seen. Invariant broken"
                       shard_index)) ;
              seen.(shard_index) <- true ;
              decr remaining)
        shard_indices ;
      if !remaining = 0 && all_seen () then Some () else None)

(** This function is quite similar to those above, except that it checks that a
    range of messages (shards) on a tracked topic have been notified by GS to
    the DAL node. This is typically needed to then be able to attest slots. *)
let check_message_notified_to_app_event dal_node ~number_of_shards
    ~shard_indexes ~expected_commitment ~expected_level ~expected_pkh
    ~expected_slot =
  let remaining = ref (List.length shard_indexes) in
  let seen = Array.make number_of_shards false in
  let get_shard_index_opt event =
    let level = JSON.(event |-> "level" |> as_int) in
    let slot_index = JSON.(event |-> "slot_index" |> as_int) in
    let shard_index = JSON.(event |-> "shard_index" |> as_int) in
    let pkh = JSON.(event |-> "pkh" |> as_string) in
    let commitment = JSON.(event |-> "commitment" |> as_string) in
    let*?? () = check_expected expected_pkh pkh in
    let*?? () = check_expected expected_level level in
    let*?? () = check_expected expected_slot slot_index in
    let*?? () = check_expected expected_commitment commitment in
    Some shard_index
  in
  let all_seen () =
    seen |> Array.to_seqi
    |> Seq.for_all (fun (i, b) -> if List.mem i shard_indexes then b else true)
  in
  Dal_node.wait_for
    dal_node
    "gossipsub_transport_event-message_notified_to_app.v0"
    (fun event ->
      let*?? shard_index = get_shard_index_opt event in
      Check.(
        (seen.(shard_index) = false)
          bool
          ~error_msg:
            (sf "Shard_index %d already seen. Invariant broken" shard_index)) ;
      seen.(shard_index) <- true ;
      let () = remaining := !remaining - 1 in
      if !remaining = 0 && all_seen () then Some () else None)

(** Connect [dal_node1] and [dal_node2] using the bootstrap peer mechanism.
    [dal_node2] will use [dal_node1] as a bootstrap peer.

    For this to work, [dal_node1] must already be running. *)
let connect_nodes_via_p2p dal_node1 dal_node2 =
  let* () =
    Dal_node.init_config ~peers:[Dal_node.listen_addr dal_node1] dal_node2
  in
  (* We ensure that [dal_node1] connects to [dal_node2]. *)
  let conn_ev_in_node1 =
    check_new_connection_event
      ~main_node:dal_node1
      ~other_node:dal_node2
      ~is_trusted:false
  in
  let* () = Dal_node.run dal_node2 in
  Log.info
    "Node %s started. Waiting for connection with node %s"
    (Dal_node.name dal_node2)
    (Dal_node.name dal_node1) ;
  conn_ev_in_node1

(** This helper function makes the nodes [dal_node1] and [dal_node2] join the
    topics of the attester [pkh], by calling the RPC for tracking the corresponding profile.
    The second node calls the RPC only after receiving the Subscribe messages
    from the first node, so that when it joins the topics, it also sends Graft messages
    in addition to sending Subscribe messages. *)
let nodes_join_the_same_topics dal_node1 dal_node2 ~num_slots ~pkh1 =
  let profile1 = Dal_RPC.Attester pkh1 in
  let peer_id1 = Dal_node.read_identity dal_node1 in
  let peer_id2 = Dal_node.read_identity dal_node2 in
  (* node1 joins topic {pkh} -> it sends subscribe messages to node2. *)
  let event_waiter =
    check_events_with_topic
      ~event_with_topic:(Subscribe peer_id1)
      dal_node2
      ~num_slots
      pkh1
  in
  let* () = Dal_RPC.(call dal_node1 @@ patch_profiles [profile1]) in
  let* () = event_waiter in

  (* node2 joins topic {pkh} -> it sends subscribe and graft messages to
     node1. *)
  let event_waiter_subscribe =
    check_events_with_topic
      ~event_with_topic:(Subscribe peer_id2)
      dal_node1
      ~num_slots
      pkh1
  in
  let event_waiter_graft =
    check_events_with_topic
      ~event_with_topic:(Graft peer_id2)
      dal_node1
      ~num_slots
      pkh1
  in
  let* () = Dal_RPC.(call dal_node2 @@ patch_profiles [profile1]) in
  Lwt.join [event_waiter_subscribe; event_waiter_graft]

(** This helper returns the list of promises that allow to wait for the
    publication of a slot's shards into the Gossipsub layer.

    The [l1_committee] used to determine the topic of published messages is the
    one at the attesattion level corresponding to [publish_level].
*)
let waiters_publish_shards l1_committee dal_node commitment ~publish_level
    ~slot_index ~number_of_shards =
  let open Dal.Committee in
  List.map
    (fun {attester; indexes} ->
      check_events_with_message
        ~event_with_message:Publish_message
        dal_node
        ~number_of_shards
        ~shard_indexes:indexes
        ~expected_commitment:commitment
        ~expected_level:publish_level
        ~expected_pkh:attester
        ~expected_slot:slot_index)
    l1_committee

(** This helper returns the promise that allows to wait for the reception of
    messages of [slot_index] published at level [publish_level] by the attester
    [pkh].

    The [l1_committee] used to determine the topic of published messages is the
    one at the attesattion level corresponding to [publish_level]. *)
let waiter_receive_shards l1_committee dal_node commitment ~publish_level
    ~slot_index ~pkh ~from_peer ~number_of_shards =
  let open Dal.Committee in
  match List.find (fun {attester; _} -> attester = pkh) l1_committee with
  | {attester; indexes} ->
      check_events_with_message
        ~event_with_message:(Message_with_header from_peer)
        dal_node
        ~number_of_shards
        ~shard_indexes:indexes
        ~expected_commitment:commitment
        ~expected_level:publish_level
        ~expected_pkh:attester
        ~expected_slot:slot_index
  | exception Not_found ->
      Test.fail "Should not happen as %s is part of the committee" pkh

(** This helper returns the promise that allows to wait for the successful
    notification of messages of [slot_index] published at level [publish_level]
    to the app layer of the attester [pkh].

    The [l1_committee] used to determine the topic of published messages is the
    one at the attesattion level corresponding to [publish_level]. *)
let waiter_successful_shards_app_notification l1_committee dal_node commitment
    ~publish_level ~slot_index ~pkh ~number_of_shards =
  let open Dal.Committee in
  match List.find (fun {attester; _} -> attester = pkh) l1_committee with
  | {attester; indexes} ->
      check_message_notified_to_app_event
        dal_node
        ~number_of_shards
        ~shard_indexes:indexes
        ~expected_commitment:commitment
        ~expected_level:publish_level
        ~expected_pkh:attester
        ~expected_slot:slot_index
  | exception Not_found ->
      Test.fail "Should not happen as %s is part of the committee" pkh

let test_dal_node_p2p_connection_and_disconnection _protocol _parameters
    _cryptobox node _client dal_node1 =
  let dal_node2 = Dal_node.create ~node () in
  (* Connect the nodes *)
  let* () = connect_nodes_via_p2p dal_node1 dal_node2 in
  let peer_id = Dal_node.read_identity dal_node2 in
  (* kill dal_node2 and check "disconnection" event in node1. *)
  let disconn_ev_in_node1 = check_disconnection_event dal_node1 ~peer_id in
  let* () = Dal_node.kill dal_node2 in
  disconn_ev_in_node1

let test_dal_node_join_topic _protocol parameters _cryptobox _node _client
    dal_node1 =
  let pkh1 = Constant.bootstrap1.public_key_hash in
  let profile1 = Dal_RPC.Attester pkh1 in
  let num_slots = parameters.Dal.Parameters.number_of_slots in
  let event_waiter =
    check_events_with_topic ~event_with_topic:Join dal_node1 ~num_slots pkh1
  in
  let* () = Dal_RPC.(call dal_node1 @@ patch_profiles [profile1]) in
  event_waiter

(** This generic test function is used to test messages exchanges between two
    DAL nodes via the P2P/GS layers, once connections are established and topics
    are joined.

   The [mk_dal_node2] function is used to create a second DAL node. We may
   decide to create a regular/normal or a modified dal node.

   The [expect_app_notification] flag is used to tell whether we should wait for
   the application layer of the second DAL node to be notified with received messages.
   In case we don't expect the application layer to be notified (e.g. messages are invalid),
   set to [false].

   The [is_first_slot_attestable] flag is used to tell whether the first slot
   (that has been injected by this function) can be attested by the considered
   attester or not. In particular, it should be set to [false] if the
   application layer of the second DAL node was not notified about the messages
   sent by the first DAL node.
*)
let generic_gs_messages_exchange protocol parameters _cryptobox node client
    dal_node1 ~mk_dal_node2 ~expect_app_notification ~is_first_slot_attestable =
  let* dal_node2 = mk_dal_node2 protocol parameters in

  let* () = connect_nodes_via_p2p dal_node1 dal_node2 in

  let num_slots = parameters.Dal.Parameters.number_of_slots in
  let number_of_shards = parameters.Dal.Parameters.cryptobox.number_of_shards in
  let account1 = Constant.bootstrap1 in
  let pkh1 = account1.public_key_hash in
  (* The two nodes join the same topics *)
  let* () = nodes_join_the_same_topics dal_node1 dal_node2 ~num_slots ~pkh1 in

  (* Posting a DAL message to DAL node and to L1 *)
  let crypto_params = parameters.cryptobox in
  let slot_index = 0 in
  let* slot_commitment =
    let slot_size = crypto_params.slot_size in
    let slot_content = generate_dummy_slot slot_size in
    publish_and_store_slot
      ~with_proof:true
      client
      dal_node1
      Constant.bootstrap1
      ~index:slot_index
    @@ Helpers.make_slot ~slot_size slot_content
  in

  (* Preparing event waiters for different shards that will be published by
     dal_node1 once the slot header is included in an L1 block.

     We also prepare a waiter event for:
     - the shards that will be received by dal_node2 on its topics;
     - the messages (shards) that will be notified to dal_node2 on its topic. *)
  let* publish_level = next_level node in
  let attested_level = publish_level + parameters.attestation_lag in
  let attestation_level = attested_level - 1 in
  let* committee = Dal.Committee.at_level node ~level:attestation_level () in

  let waiter_publish_list =
    waiters_publish_shards
      committee
      dal_node1
      slot_commitment
      ~publish_level
      ~slot_index
      ~number_of_shards
  in
  let waiter_receive_shards =
    waiter_receive_shards
      committee
      dal_node2
      slot_commitment
      ~publish_level
      ~slot_index
      ~pkh:pkh1
      ~from_peer:(Dal_node.read_identity dal_node1)
      ~number_of_shards
  in
  let waiter_app_notifs =
    if expect_app_notification then
      waiter_successful_shards_app_notification
        committee
        dal_node2
        slot_commitment
        ~publish_level
        ~slot_index
        ~pkh:pkh1
        ~number_of_shards
    else unit
  in

  (* We bake a block that includes a [slot_header] operation. And then another
     two blocks so that this operation is final. *)
  let* () = bake_for ~count:3 client in
  let* () = Lwt.join waiter_publish_list
  and* () = waiter_receive_shards
  and* () = waiter_app_notifs in

  (* Check that dal_node2 has the shards needed by attester account1/pkh1 to
     attest the slot with index 0. *)
  let* res =
    Dal_RPC.(
      call dal_node2 @@ get_attestable_slots ~attester:account1 ~attested_level)
  in
  match res with
  | Not_in_committee -> Test.fail "attester %s not in committee" account1.alias
  | Attestable_slots slots ->
      (* only slot 0 is attestable. Others are set to false. *)
      let expected =
        is_first_slot_attestable :: List.init (num_slots - 1) (fun _ -> false)
      in
      Check.(
        (expected = slots)
          (list bool)
          ~error_msg:"Expected %L attestable slots list flags, got %R") ;
      unit

let test_dal_node_gs_valid_messages_exchange _protocol parameters _cryptobox
    node client dal_node1 =
  generic_gs_messages_exchange
    _protocol
    parameters
    _cryptobox
    node
    client
    dal_node1
    ~mk_dal_node2:(fun _protocol _parameters ->
      Dal_node.create ~node () |> return)
    ~expect_app_notification:true
    ~is_first_slot_attestable:true

(* Create a DAL node whose DAL parameters are not compatible with those in
   [parameters]. For that, the redundancy_factor field is multiplied by 2. *)
let make_invalid_dal_node ?use_mock_srs_for_testing protocol parameters =
  (* Create another L1 node with different DAL parameters. *)
  let* node2, _client2, _xdal_parameters2 =
    let crypto_params = parameters.Dal.Parameters.cryptobox in
    let parameters =
      dal_enable_param (Some true)
      @ redundancy_factor_param (Some (crypto_params.redundancy_factor / 2))
      @ slot_size_param (Some (crypto_params.slot_size / 2))
    in
    setup_node ?use_mock_srs_for_testing ~protocol ~parameters ()
  in
  (* Create a second DAL node with node2 and client2 as argument (so different
     DAL parameters compared to dal_node1. *)
  let dal_node2 = Dal_node.create ~node:node2 () in
  return dal_node2

let test_dal_node_gs_invalid_messages_exchange _protocol parameters _cryptobox
    node client dal_node1 =
  (* Messages are invalid, so the app layer is not notified. *)
  let expect_app_notification = false in
  (* The first slot published by [generic_gs_messages_exchange] is not
     attestable by the considered attester pk1 = bootstrap1, because the shards
     received by the Gossipsub layer are classified as 'Invalid'. *)
  let is_first_slot_attestable = false in
  generic_gs_messages_exchange
    _protocol
    parameters
    _cryptobox
    node
    client
    dal_node1
    ~mk_dal_node2:make_invalid_dal_node
    ~expect_app_notification
    ~is_first_slot_attestable

let test_gs_prune_and_ihave protocol parameters _cryptobox node client dal_node1
    =
  let rec repeat_i n f =
    if n <= 0 then unit
    else
      let* () = f n in
      repeat_i (n - 1) f
  in
  let crypto_params = parameters.Dal.Parameters.cryptobox in
  let number_of_shards = crypto_params.number_of_shards in
  let slot_size = crypto_params.slot_size in
  let slot_content = generate_dummy_slot slot_size in

  (* Inject as much slots as possible with available bootstrap accounts.
     The goal is to continuously send invalid messages from dal_node1 to dal_node2,
     thus lowering the score of dal_node1 to the point where it becomes negative. *)
  let* () =
    let num_slots =
      min
        (Array.length Account.Bootstrap.keys)
        parameters.Dal.Parameters.number_of_slots
    in
    Log.info "Publishing %d slots" num_slots ;
    repeat_i num_slots (fun i ->
        let slot_index = i - 1 in
        let account = Account.Bootstrap.keys.(slot_index) in
        let* _slot_commitment =
          publish_and_store_slot
            ~with_proof:true
            client
            dal_node1
            account
            ~index:slot_index
          @@ Helpers.make_slot ~slot_size slot_content
        in
        unit)
  in

  (* Create another (invalid) DAL node *)
  let* dal_node2 = make_invalid_dal_node protocol parameters in

  (* Connect the nodes *)
  let* () = connect_nodes_via_p2p dal_node1 dal_node2 in

  let num_slots = parameters.number_of_slots in
  let account1 = Constant.bootstrap1 in
  let pkh1 = account1.public_key_hash in

  (* The two nodes join the same topics *)
  let* () = nodes_join_the_same_topics dal_node1 dal_node2 ~num_slots ~pkh1 in

  let peer_id1 = Dal_node.read_identity dal_node1 in
  let peer_id2 = Dal_node.read_identity dal_node2 in
  (* Once a block is baked and shards injected into GS, we expect dal_node1 to
     be pruned by dal_node2 because its score will become negative due to
     invalid messages. *)
  let event_waiter_prune =
    check_events_with_topic
      ~event_with_topic:(Prune peer_id2)
      dal_node1
      ~num_slots
      pkh1
  in

  Log.info "Waiting for prune event on %s" (Dal_node.name dal_node1) ;

  (* We bake 3 blocks (one to include publish ops and two more to make that
     block final) and wait for the prune events. *)
  let* () = bake_for ~count:3 client in
  let* () = event_waiter_prune in

  let* score = get_peer_score dal_node2 peer_id1 in
  Log.info "The peer's score after prune is %f" score ;
  Check.(
    (score < 0.)
      float
      ~error_msg:"The dal_node1's score (%L) was expected to be negative.") ;

  (* Now, we'll inject a new slot for the next published_level in
     dal_node1. Since it's pruned, dal_node2 will be notified via IHave
     messages. *)
  let slot_index = 0 in
  let* commitment =
    publish_and_store_slot
      ~with_proof:true
      client
      dal_node1
      account1
      ~index:slot_index
    @@ Helpers.make_slot ~slot_size slot_content
  in

  let* publish_level = next_level node in
  let attested_level = publish_level + parameters.attestation_lag in
  let attestation_level = attested_level - 1 in
  let* committee = Dal.Committee.at_level node ~level:attestation_level () in

  let Dal.Committee.{attester; indexes = shard_indexes} =
    match
      List.find (fun Dal.Committee.{attester; _} -> attester = pkh1) committee
    with
    | exception Not_found ->
        Test.fail "Should not happen as %s is part of the committee" pkh1
    | v -> v
  in
  let ihave_events_waiter =
    check_events_with_message_id
      ~event_with_message_id:(IHave {pkh = pkh1; slot_index = 0})
      dal_node2
      ~number_of_shards
      ~shard_indexes
      ~expected_commitment:commitment
      ~expected_level:publish_level
      ~expected_pkh:attester
      ~expected_slot:slot_index
      ~expected_peer:peer_id1
  in
  let* () = bake_for client ~count:3 in
  ihave_events_waiter

(* Checks that:
   * the baker does not crash when there's a DAL node specified, but it is not
   running
   * the baker register profiles when the DAL node restarts. *)
let test_baker_registers_profiles protocol _parameters _cryptobox l1_node client
    dal_node =
  let delegates =
    List.to_seq Constant.all_secret_keys |> Seq.take 3 |> List.of_seq
  in
  let profiles =
    List.map (fun key -> Dal_RPC.Attester key.Account.public_key_hash) delegates
  in
  let delegates = List.map (fun key -> key.Account.alias) delegates in

  Log.info
    "Terminate the DAL node and then start the baker; the baker cannot attest \
     but can advance" ;
  let* () = Dal_node.terminate dal_node in
  let baker = Baker.create ~dal_node ~protocol l1_node client ~delegates in
  let wait_for_attestation_event =
    Baker.wait_for baker "failed_to_get_attestations.v0" (fun _json -> Some ())
  in
  let* () = Baker.run baker in
  let* () = wait_for_attestation_event in
  let* _lvl = Node.wait_for_level l1_node 3 in

  Log.info "Start (again) the DAL node" ;
  let* () = Dal_node.run dal_node in
  Log.info "Wait 2 seconds; by then, profiles should have been registered" ;
  (* Note: this constant depends on how often the baker retries to register
     profiles (see [max_delay] in [Baking_scheduling.register_dal_profiles]); if
     the baker behavior changes in this respect, the constant may need
     adjusting. *)
  let* () = Lwt_unix.sleep 2.0 in
  check_profiles ~__LOC__ dal_node ~expected:(Operator profiles)

(** This helper funciton terminates dal_node2 and dal_node3 (in addition to
    those in [extra_nodes_to_restart]), and restart them after creating two
    connection events to check that dal_node2 and dal_node3 find each other. *)
let observe_nodes_connection_via_bootstrap ?(extra_nodes_to_restart = []) client
    dal_node2 dal_node3 =
  let nodes = dal_node2 :: dal_node3 :: extra_nodes_to_restart in
  let* () = List.map Dal_node.terminate nodes |> Lwt.join in
  let check_conn_event_from_2_to_3 =
    check_new_connection_event
      ~main_node:dal_node2
      ~other_node:dal_node3
      ~is_trusted:false
  in
  let check_conn_event_from_3_to_2 =
    check_new_connection_event
      ~main_node:dal_node3
      ~other_node:dal_node2
      ~is_trusted:false
  in
  let* () = List.map (Dal_node.run ~wait_ready:true) nodes |> Lwt.join in
  Log.info "Bake a block and then another two to finalize it." ;
  let* () = bake_for ~count:3 client in
  Log.info "Wait for dal_node2 and dal_node3 to find each other." ;

  let* () =
    Lwt.join [check_conn_event_from_2_to_3; check_conn_event_from_3_to_2]
  in
  unit

(** This function tests that a peer can discover another peer via a bootstrap
    node and that discovery works even when the bootstrap is (re-)started at the
    same time (or after) the two other nodes we want to connect. *)
let test_peer_discovery_via_bootstrap_node _protocol _parameters _cryptobox node
    client dal_node1 =
  (* Phase 1: dal_node1 is already running. Start dal_node2 and dal_node3 and
     use dal_node1 to establish connections between them. *)
  let* dal_node2 =
    make_dal_node
      ~peers:[Dal_node.listen_addr dal_node1]
      ~attester_profiles:[Constant.bootstrap1.public_key_hash]
      node
  in
  let* dal_node3 =
    make_dal_node
      ~peers:[Dal_node.listen_addr dal_node1]
      ~producer_profiles:[0]
      node
  in
  (* Here, we observe a first nodes connection via bootstrap nodes thanks to
     peers exchange. *)
  let* () = observe_nodes_connection_via_bootstrap client dal_node2 dal_node3 in

  (* In this variant, we also restart the bootstrap node [dal_node1]. So,
     connections to it from dal_node2 and dal_node3 are always done at startup,
     but Gossipsub worker might be needed to retry connection. *)
  observe_nodes_connection_via_bootstrap
    ~extra_nodes_to_restart:[dal_node1]
    client
    dal_node2
    dal_node3

(** Connect two nodes [dal_node2] and [dal_node3] via a trusted bootstrap peer
    [dal_node1]. Then, disconnect all the nodes (without restarting them) and
    wait for reconnection. *)
let test_peers_reconnection _protocol _parameters _cryptobox node client
    dal_node1 =
  (* Connect two nodes via bootstrap peer. *)
  Log.info "Connect two nodes via bootstrap peer." ;
  let* dal_node2 =
    make_dal_node
      ~peers:[Dal_node.listen_addr dal_node1]
      ~attester_profiles:[Constant.bootstrap1.public_key_hash]
      node
  in
  let* dal_node3 =
    make_dal_node
      ~peers:[Dal_node.listen_addr dal_node1]
      ~producer_profiles:[0]
      node
  in
  let* () =
    (* Here, we observe a first nodes connection via bootstrap nodes thanks to
       peers exchange. Below, we disconnect the nodes without restarting
       them. *)
    observe_nodes_connection_via_bootstrap client dal_node2 dal_node3
  in

  (* Get the nodes' identities. *)
  let id dal_node = Dal_node.read_identity dal_node in
  let id_dal_node1 = id dal_node1 in
  let id_dal_node2 = id dal_node2 in
  let id_dal_node3 = id dal_node3 in

  (* Prepare disconnection events to observe. *)
  let disconn_ev_in_node1_2 =
    check_disconnection_event dal_node1 ~peer_id:id_dal_node2
  in
  let disconn_ev_in_node1_3 =
    check_disconnection_event dal_node1 ~peer_id:id_dal_node3
  in
  let disconn_ev_in_node2_3 =
    check_disconnection_event dal_node2 ~peer_id:id_dal_node3
  in

  (* Prepare reconnection events checks between node1 and node2 (resp. 3). *)
  let check_conn_event_from_1_to_2 =
    check_new_connection_event
      ~main_node:dal_node1
      ~other_node:dal_node2
      ~is_trusted:false
  in
  let check_conn_event_from_1_to_3 =
    check_new_connection_event
      ~main_node:dal_node1
      ~other_node:dal_node3
      ~is_trusted:false
  in
  let check_conn_event_from_2_to_3 =
    check_new_connection_event
      ~main_node:dal_node2
      ~other_node:dal_node3
      ~is_trusted:false
  in

  (* Disconnect all the nodes. *)
  let* () =
    Lwt_list.iter_p
      (fun peer_id ->
        Lwt_list.iter_p
          (fun dal_node ->
            Dal_RPC.(call dal_node @@ delete_p2p_peer_disconnect ~peer_id))
          [dal_node1; dal_node2; dal_node3])
      [id_dal_node1; id_dal_node2; id_dal_node3]
  in

  (* Observe disconnection. *)
  Log.info "Wait for disconnection" ;
  let* () =
    Lwt.join
      [disconn_ev_in_node1_2; disconn_ev_in_node1_3; disconn_ev_in_node2_3]
  in
  Log.info "Disconnection done. Wait for reconnection." ;
  let* () =
    Lwt.join
      [
        check_conn_event_from_1_to_2;
        check_conn_event_from_1_to_3;
        check_conn_event_from_2_to_3;
      ]
  in
  Log.info "Recconnection done." ;
  unit

(* Adapted from sc_rollup.ml *)
let test_l1_migration_scenario ?(tags = []) ~migrate_from ~migrate_to
    ~migration_level ~scenario ~description () =
  let tags =
    Tag.tezos2 :: "dal" :: Protocol.tag migrate_from :: Protocol.tag migrate_to
    :: "migration" :: tags
  in
  Test.register
    ~__FILE__
    ~tags
    ~uses:[Constant.octez_dal_node]
    ~title:
      (sf
         "%s->%s: %s"
         (Protocol.name migrate_from)
         (Protocol.name migrate_to)
         description)
  @@ fun () ->
  let parameters = dal_enable_param (Some true) in
  let* node, client, _dal_parameters =
    setup_node ~parameters ~protocol:migrate_from ()
  in

  Log.info "Set user-activated-upgrade at level %d" migration_level ;
  let* () = Node.terminate node in
  let patch_config =
    Node.Config_file.update_network_with_user_activated_upgrades
      [(migration_level, migrate_to)]
  in
  let nodes_args = Node.[Synchronisation_threshold 0; No_bootstrap_peers] in
  let* () = Node.run ~patch_config node nodes_args in
  let* () = Node.wait_for_ready node in

  let dal_node = Dal_node.create ~node () in
  let* () = Dal_node.init_config dal_node in
  let* () = Dal_node.run dal_node ~wait_ready:true in

  scenario ~migration_level client node dal_node

let test_migration_plugin ~migrate_from ~migrate_to =
  let tags = ["plugin"]
  and description = "test plugin update"
  and scenario ~migration_level client node dal_node =
    let* current_level =
      let* json = Node.RPC.(call node @@ get_chain_block_header_shell ()) in
      JSON.(json |-> "level" |> as_int |> return)
    in

    if migration_level <= current_level then
      Test.fail ~__LOC__ "The migration level (%d) is too low" migration_level ;

    let blocks_till_migration = migration_level - current_level in

    let wait_for_plugin =
      Dal_node.wait_for dal_node "dal_node_plugin_resolved.v0" (fun json ->
          let proto_hash = JSON.(json |> as_string) in
          if String.equal proto_hash (Protocol.hash migrate_to) then Some ()
          else None)
    in

    Log.info "Bake %d blocks" blocks_till_migration ;
    let* () = repeat blocks_till_migration (fun () -> bake_for client) in

    Log.info "Migrated to %s" (Protocol.name migrate_to) ;
    (* The plugin will change after the two blocks, as the migration block
       is not yet finalized. *)
    let* () = bake_for ~count:2 client in
    wait_for_plugin
  in
  test_l1_migration_scenario
    ~migrate_from
    ~migrate_to
    ~scenario
    ~tags
    ~description
    ()

let test_producer_profile _protocol _dal_parameters _cryptobox _node _client
    dal_node =
  let index = 0 in
  let* () = Dal_RPC.(call dal_node (patch_profiles [Producer index])) in
  let* () =
    check_profiles
      ~__LOC__
      dal_node
      ~expected:Dal_RPC.(Operator [Producer index])
  in
  unit

let test_attestation_through_p2p _protocol dal_parameters _cryptobox node client
    dal_bootstrap =
  (* In this test we have three DAL nodes:
     - a boostrap one to connect the other two (producer and attester),
     - a slot producer on slot 0,
     - an attester for all the bootstrap pkh.

     We check that when the slot producer publishes a slot, it ends up
     being attested.
  *)
  let index = 0 in
  let slot_size = dal_parameters.Dal.Parameters.cryptobox.slot_size in
  let num_slots = dal_parameters.Dal.Parameters.number_of_slots in
  let attestation_lag = dal_parameters.Dal.Parameters.attestation_lag in
  let number_of_shards =
    dal_parameters.Dal.Parameters.cryptobox.number_of_shards
  in
  let peers = [Dal_node.listen_addr dal_bootstrap] in
  let peer_id dal_node = Dal_node.read_identity dal_node in
  let bootstrap_peer_id = peer_id dal_bootstrap in

  (* Check that the attestation threshold for this test is 100%. If
     not, this means that we forgot to register the test with
     ~attestation_threshold:100 *)
  Check.((dal_parameters.Dal.Parameters.attestation_threshold = 100) int)
    ~error_msg:"attestation_threshold value (%L) should be 100" ;
  (* Check that the dal node passed as argument to this test function
     is a running bootstrap DAL node. If not, this means that we
     forgot to register the test with ~bootstrap_profile:true *)
  let* () = check_profiles ~__LOC__ dal_bootstrap ~expected:Dal_RPC.Bootstrap in
  Log.info "Bootstrap DAL node is running" ;

  let producer = Dal_node.create ~name:"producer" ~node () in
  let* () = Dal_node.init_config ~producer_profiles:[index] ~peers producer in
  let* () = Dal_node.run ~wait_ready:true producer in
  let producer_peer_id = peer_id producer in
  let* () =
    check_profiles
      ~__LOC__
      producer
      ~expected:Dal_RPC.(Operator [Producer index])
  in
  Log.info "Slot producer DAL node is running" ;

  let all_pkhs =
    Account.Bootstrap.keys |> Array.to_list
    |> List.map (fun account -> account.Account.public_key_hash)
  in
  let attester = Dal_node.create ~name:"attester" ~node () in
  let* () = Dal_node.init_config ~attester_profiles:all_pkhs ~peers attester in
  let* () = Dal_node.run ~wait_ready:true attester in
  let attester_peer_id = peer_id attester in

  (* The connections between attesters and the slot producer have no
     reason to be grafted on other slot indices than the one the slot
     producer is subscribed to, so we instruct
     [check_events_with_topic] to skip all events but the one for
     [index]. *)
  let already_seen_slots =
    Array.init num_slots (fun slot_index -> slot_index <> index)
  in
  (* Wait for a GRAFT message between the attester and the producer,
     in any direction. *)
  let check_graft pkh =
    let graft_from_attester =
      check_events_with_topic
        ~event_with_topic:(Graft attester_peer_id)
        producer
        ~num_slots
        ~already_seen_slots
        pkh
    in
    let graft_from_producer =
      check_events_with_topic
        ~event_with_topic:(Graft producer_peer_id)
        attester
        ~num_slots
        ~already_seen_slots
        pkh
    in
    Lwt.pick [graft_from_attester; graft_from_producer]
  in
  let check_graft_promises = List.map check_graft all_pkhs in
  Log.info "Waiting for grafting of the attester - producer connection" ;
  let* () =
    check_profiles
      ~__LOC__
      attester
      ~expected:Dal_RPC.(Operator (List.map (fun pkh -> Attester pkh) all_pkhs))
  in
  (* We need to bake some blocks until the L1 node notifies the
     attester DAL nodes that some L1 block is final and they have DAL
     attestation rights in it. *)
  let* () = bake_for ~count:3 client in
  let* () = Lwt.join check_graft_promises in
  Log.info "Attester - producer connection grafted" ;

  (* Attester should be connected to:
     - the bootstrap DAL node on all the topics,
     - the producer on all topics with slot_index=index *)
  let* () =
    let expected topic_pkh =
      Seq.ints 0 |> Seq.take num_slots
      |> Seq.map (fun topic_slot_index ->
             ( {Dal_RPC.topic_slot_index; topic_pkh},
               bootstrap_peer_id
               :: (if topic_slot_index = index then [producer_peer_id] else [])
             ))
      |> List.of_seq
    in
    let expected = List.concat (List.map expected all_pkhs) in
    check_topics_peers ~__LOC__ attester ~subscribed:true ~expected
  in

  (* The slot producer should be connected to:
     - the attester and the bootstrap DAL node on all topics with slot_index=index,
  *)
  let* () =
    let expected =
      all_pkhs
      |> List.map (fun topic_pkh ->
             ( {Dal_RPC.topic_slot_index = index; topic_pkh},
               [bootstrap_peer_id; attester_peer_id] ))
    in
    check_topics_peers ~__LOC__ producer ~subscribed:true ~expected
  in

  (* Produce and publish a slot *)
  let source = Constant.bootstrap1 in
  let slot_content = "content" in

  let all_shard_indices =
    Seq.ints 0 |> Seq.take number_of_shards |> List.of_seq
  in
  let wait_slot commitment =
    Lwt.join
    @@ List.map
         (fun shard_index ->
           wait_for_stored_slot ~shard_index attester commitment)
         all_shard_indices
  in
  let attester_dal_node_endpoint = Dal_node.rpc_endpoint attester in
  let* publication_level, commitment =
    publish_store_and_wait_slot
      node
      client
      producer
      source
      ~index
      ~wait_slot
      ~number_of_extra_blocks_to_bake:2
    @@ Helpers.make_slot ~slot_size slot_content
  in

  Log.info "Slot produced and published" ;

  let* () =
    bake_until_processed
      ~dal_node_endpoint:attester_dal_node_endpoint
      ~level:(publication_level + attestation_lag)
      client
      [attester]
  in

  let* slot_headers =
    Dal_RPC.(call attester @@ get_published_level_headers publication_level)
  in
  let expected_slot_header =
    Dal_RPC.
      {
        slot_level = publication_level;
        slot_index = index;
        status = "attested";
        commitment;
      }
  in
  Check.([expected_slot_header] = slot_headers)
    Dal.Check.slot_headers_typ
    ~error_msg:"Expected slot headers %L (got %R)" ;
  Log.info "Slot sucessfully attested" ;
  unit

let test_commitments_history_rpcs _protocol dal_parameters _cryptobox node
    client dal_node =
  let dal_node_endpoint = Dal_node.rpc_endpoint dal_node in
  let slot_size = dal_parameters.Dal.Parameters.cryptobox.slot_size in
  let lag = dal_parameters.attestation_lag in
  let number_of_slots = dal_parameters.number_of_slots in
  let index = number_of_slots - 1 in
  Log.info "attestation_lag = %d, number_of_slots = %d" lag number_of_slots ;
  let last_confirmed_level = 5 in
  let max_level = last_confirmed_level + lag + 2 in
  let wait_for_dal_node =
    wait_for_layer1_final_block dal_node (last_confirmed_level + lag)
  in

  let rec publish level commitments =
    (* Try to publish a slot at each level *)
    if level >= max_level then return @@ List.rev commitments
    else
      let* commitment =
        publish_and_store_slot
          client
          dal_node
          Constant.bootstrap1
          ~index
          ~force:true
        @@ Helpers.make_slot ~slot_size ("slot " ^ string_of_int level)
      in
      let* () = bake_for client ~dal_node_endpoint in
      let* _level = Node.wait_for_level node (level + 1) in
      publish (level + 1) (commitment :: commitments)
  in

  let* () = bake_for client in
  let* first_level = Client.level client in
  Log.info "No slot published at level %d" first_level ;
  Log.info "Publishing slots and baking up to level %d" max_level ;
  let* commitments = publish first_level [] in
  let commitments = Array.of_list commitments in

  let module SeenIndexes = Set.Make (struct
    type t = int

    let compare = compare
  end) in
  let seen_indexes = ref SeenIndexes.empty in
  let rec check_history level =
    (* Try to publish a slot at each level *)
    if level > max_level then unit
    else
      let* cell =
        Node.RPC.call node
        @@ RPC.get_chain_block_context_dal_commitments_history
             ~block:(string_of_int level)
             ()
      in
      let* () = check_cell cell ~check_level:(Some level) in
      check_history (level + 1)
  and check_cell cell ~check_level =
    let skip_list_kind = JSON.(cell |-> "kind" |> as_string) in
    let expected_skip_list_kind = "dal_skip_list" in
    Check.(
      (skip_list_kind = expected_skip_list_kind)
        string
        ~error_msg:"Unexpected skip list kind: got %L, expected %R") ;
    let skip_list = JSON.(cell |-> "skip_list") in
    let cell_index = JSON.(skip_list |-> "index" |> as_int) in
    if SeenIndexes.mem cell_index !seen_indexes then unit
    else (
      seen_indexes := SeenIndexes.add cell_index !seen_indexes ;
      let content = JSON.(skip_list |-> "content") in
      let cell_level = JSON.(content |-> "level" |> as_int) in
      let published_level =
        match check_level with
        | Some level ->
            let expected_level = max 0 (level - lag) in
            Check.(
              (cell_level = expected_level)
                int
                ~error_msg:"Unexpected cell level: got %L, expected %R") ;
            level - lag
        | None -> cell_level
      in
      let slot_index = JSON.(content |-> "index" |> as_int) in
      let () =
        match check_level with
        | None -> ()
        | Some level ->
            let expected_slot_index =
              if level < lag then (* the "slot index" of genesis *) 0
              else number_of_slots - 1
            in
            Check.(
              (slot_index = expected_slot_index)
                int
                ~error_msg:"Unexpected slot index: got %L, expected %R")
      in
      (if cell_index > 0 then
       Check.(
         (cell_index = ((cell_level - 1) * number_of_slots) + slot_index)
           int
           ~error_msg:"Unexpected cell index: got %L, expected %R")) ;
      let cell_kind = JSON.(content |-> "kind" |> as_string) in
      let expected_kind =
        if published_level <= first_level || slot_index != index then
          "unattested"
        else "attested"
      in
      Check.(
        (cell_kind = expected_kind)
          string
          ~error_msg:"Unexpected cell kind: got %L, expected %R") ;
      (if cell_kind = "attested" then
       let commitment = JSON.(content |-> "commitment" |> as_string) in
       Check.(
         (commitment = commitments.(cell_level - (first_level + 1)))
           string
           ~error_msg:"Unexpected commitment: got %L, expected %R")) ;
      let back_pointers =
        JSON.(skip_list |-> "back_pointers" |> as_list)
        |> List.map JSON.as_string
      in
      let expecting_no_back_pointers =
        match check_level with
        | Some level ->
            level < lag || (level = lag && slot_index = number_of_slots - 1)
        | None -> cell_index = 0
      in
      let no_back_pointers = back_pointers = [] in
      Check.(
        (no_back_pointers = expecting_no_back_pointers)
          bool
          ~error_msg:
            "Unexpected non-existence of back_pointers: got %L, expected %R") ;
      if cell_level > first_level && cell_level <= last_confirmed_level then
        Lwt_list.iter_s
          (fun hash ->
            let* cell =
              Dal_RPC.(
                call dal_node @@ get_plugin_commitments_history_hash ~hash ())
            in
            check_cell cell ~check_level:None)
          back_pointers
      else unit)
  in
  let* () = wait_for_dal_node in
  check_history 1

module Amplification = struct
  let step_counter = ref 0

  let info msg =
    let prefix : string = Format.asprintf "Step %d" !step_counter in
    let () = incr step_counter in
    Log.info ~prefix msg

  (* Test the amplification feature: once it has seen enough (but not
     necessarily all) shards of a given slot, an observer DAL node is
     able to reconstruct the complete slot and send the missing shards
     on the DAL network.

     To test this feature, we need a DAL network on which some shards
     have been lost and need to be recomputed. This is achieved by
     building a network with a single slot producer and several
     attesters corresponding to different bakers; the slot producer is
     only connected to some attesters so the shards needed by the
     other attesters are lost.

     More precisely, the DAL network we build is composed of (omitting
     the bootstrap DAL node):

     slot producer --- 3 attesters --- observer --- 2 attesters

     This topology is obtained by making the slot producer ban the
     nodes which should not be connected to it (the observer and 2
     attesters). For this reason, we call "banned attesters" the 2
     attesters which are only connected to the observer node and
     "non-banned attesters" the 3 attesters which are connected to
     both the slot producer and the observer.
  *)

  (* In amplification tests, we have one attester DAL node per
     boostrap baker. For convenience, we bundle the dal node process
     together with information about the corresponding bootstrap
     baker. *)
  type attester = {
    dal_node : Dal_node.t;
    account : Account.key;
    pkh : string;
    index : int; (* From 0 to 4. *)
    name : string; (* From "attester1" to "attester5" *)
    mutable peer_id : string option;
        (* Delayed and cached call to Dal_node.read_identity *)
  }

  let attester_peer_id (attester : attester) =
    match attester.peer_id with
    | Some pid -> pid
    | None ->
        let pid = Dal_node.read_identity attester.dal_node in
        attester.peer_id <- Some pid ;
        pid

  let test_amplification _protocol dal_parameters _cryptobox node client
      dal_bootstrap =
    let number_of_banned_attesters = 2 in
    let slot_index = 0 in
    (* Parameters and constants. *)
    let {
      Dal.Parameters.attestation_lag;
      attestation_threshold;
      number_of_slots;
      cryptobox =
        {Dal.Cryptobox.slot_size; number_of_shards; redundancy_factor; _};
      _;
    } =
      dal_parameters
    in

    (* Note: we don't need to configure and start the DAL bootstrap
       node because it is the node started by the
       scenario_with_layer1_and_dal_nodes wrapper. Instead, we check
       that the dal node passed as argument to this test function is a
       running bootstrap DAL node. If not, this means that we forgot
       to register the test with ~bootstrap_profile:true *)
    let* () =
      check_profiles ~__LOC__ dal_bootstrap ~expected:Dal_RPC.Bootstrap
    in
    info "bootstrap DAL node is running" ;

    (* When configuring the other DAL nodes, we use dal_bootstrap as
       the single peer. *)
    let peers = [Dal_node.listen_addr dal_bootstrap] in

    (* Create and configure all nodes: a slot producer, an observer,
       and one attester per bootstrap baker. *)
    let make_attester index (account : Account.key) : attester Lwt.t =
      let name = Printf.sprintf "attester%d" (index + 1) in
      let pkh = account.public_key_hash in
      let dal_node = Dal_node.create ~name ~node () in
      let* () = Dal_node.init_config ~attester_profiles:[pkh] ~peers dal_node in
      let* () = Dal_node.run ~wait_ready:true dal_node in
      return {name; index; dal_node; pkh; account; peer_id = None}
    in
    let* all_attesters =
      Lwt_list.mapi_p make_attester (Array.to_list Account.Bootstrap.keys)
    in
    info "attester DAL node ready" ;
    let banned_attesters, non_banned_attesters =
      List.partition
        (fun attester -> attester.index < number_of_banned_attesters)
        all_attesters
    in
    let slot_producer = Dal_node.create ~name:"producer" ~node () in
    let* () =
      Dal_node.init_config ~producer_profiles:[slot_index] ~peers slot_producer
    in
    (* Promise which will be resolved once the slot producer will be
       connected to all the other DAL nodes (all attesters + observer
       + bootstrap). We will wait for this to happen before banning
       the observer and some of the attesters. *)
    let wait_for_connections_of_producer_promise =
      Dal_node.wait_for_connections slot_producer (2 + List.length all_attesters)
    in

    let* () = Dal_node.run ~wait_ready:true slot_producer in
    let observer = Dal_node.create ~name:"observer" ~node () in
    let* () =
      Dal_node.init_config ~observer_profiles:[slot_index] ~peers observer
    in
    let* () = Dal_node.run ~wait_ready:true observer in

    (* Check that the DAL nodes have the expected profiles. *)
    let* () =
      check_profiles
        ~__LOC__
        slot_producer
        ~expected:Dal_RPC.(Operator [Producer slot_index])
    in
    let slot_producer_peer_id = Dal_node.read_identity slot_producer in
    info "Slot producer DAL node is running" ;

    let* () =
      check_profiles
        ~__LOC__
        observer
        ~expected:Dal_RPC.(Operator [Observer slot_index])
    in
    let observer_peer_id = Dal_node.read_identity observer in
    info "Observer DAL node is running" ;

    let* () =
      Lwt.join
      @@ List.map
           (fun attester ->
             check_profiles
               ~__LOC__
               attester.dal_node
               ~expected:Dal_RPC.(Operator [Attester attester.pkh]))
           all_attesters
    in
    info "Attesters are running" ;

    (* Now that all the DAL nodes are running, we need some of them to
       establish grafted connections. The connections between
       attesters and the slot producer have no reason to be grafted on
       other slot indices than the one the slot producer is subscribed
       to, so we instruct [check_events_with_topic] to skip all events
       but the one for [slot_index]. *)
    let already_seen_slots =
      Array.init number_of_slots (fun index -> slot_index <> index)
    in
    (* Wait for a GRAFT message between an attester and either a the
       producer the observer, in any direction. *)
    let check_graft_promise (producer_or_observer, peer_id) attester =
      let graft_from_attester_promise =
        check_events_with_topic
          ~event_with_topic:(Graft (attester_peer_id attester))
          producer_or_observer
          ~num_slots:number_of_slots
          ~already_seen_slots
          attester.pkh
      in
      let graft_from_producer_or_observer_promise =
        check_events_with_topic
          ~event_with_topic:(Graft peer_id)
          attester.dal_node
          ~num_slots:number_of_slots
          ~already_seen_slots
          attester.pkh
      in
      Lwt.pick
        [graft_from_attester_promise; graft_from_producer_or_observer_promise]
    in
    (* We don't care if the slot producer establishes full connections
       with the DAL nodes it is about to ban so we only wait for the
       GRAFT messages between:
       - the slot producer and the non-banned attesters,
       - the observer and all the attesters *)
    let check_graft_promises =
      List.map
        (check_graft_promise (slot_producer, slot_producer_peer_id))
        non_banned_attesters
      @ List.map
          (check_graft_promise (observer, observer_peer_id))
          all_attesters
    in
    info "Waiting for grafting of the attester - producer/observer connections" ;
    (* Each attester DAL node won't join the DAL network until it has
       processed some finalized L1 block in which the associated baker
       is reported to have some rights. For this to happen, we need to
       bake a few blocks. *)
    let* () = bake_for ~count:3 client in
    let* () = Lwt.join check_graft_promises in
    info "Attester - producer connections grafted" ;

    (* Wait for producer to be connected to all the dal nodes it wants
       to ban because they cannot be banned earlier. *)
    let* () = wait_for_connections_of_producer_promise in

    let ban_p2p_peer this_node ~peer =
      let this_dal_node, this_id = this_node in
      let peer_dal_node, peer_id = peer in
      let acl = "ban" in
      let p =
        let* () = Dal_node.wait_for_disconnection this_dal_node ~peer_id
        and* () =
          Dal_node.wait_for_disconnection peer_dal_node ~peer_id:this_id
        in
        unit
      in
      let* () =
        Dal_RPC.call this_dal_node
        @@ Dal_RPC.patch_p2p_peers_by_id ~peer_id ~acl ()
      in
      p
    in

    (* Slot producer bans observer and banned_attesters. *)
    let* () =
      ban_p2p_peer
        (slot_producer, slot_producer_peer_id)
        ~peer:(observer, observer_peer_id)
    in
    let* () =
      Lwt.join
      @@ List.map
           (fun attester ->
             ban_p2p_peer
               (slot_producer, slot_producer_peer_id)
               ~peer:(attester.dal_node, attester_peer_id attester))
           banned_attesters
    in
    info "DAL network is ready" ;

    let* level_before_publication = Client.level client in
    let publication_level = level_before_publication + 1 in
    let attested_level = publication_level + attestation_lag in
    let attestation_level = attested_level - 1 in

    let* assigned_shard_indices_non_banned =
      Lwt_list.map_p
        (fun attester ->
          Dal_RPC.(
            call attester.dal_node
            @@ get_assigned_shard_indices
                 ~level:attestation_level
                 ~pkh:attester.pkh))
        non_banned_attesters
    in
    let* assigned_shard_indices_banned =
      Lwt_list.map_p
        (fun attester ->
          Dal_RPC.(
            call attester.dal_node
            @@ get_assigned_shard_indices
                 ~level:attestation_level
                 ~pkh:attester.pkh))
        banned_attesters
    in
    let total_number_of_assigned_shards =
      List.fold_left
        (fun acc l -> acc + List.length l)
        0
        assigned_shard_indices_non_banned
    in

    (* Check that the non-banned attesters have collectively enough
       assigned shards to reconstruct the slot. *)
    Check.(
      number_of_shards / redundancy_factor < total_number_of_assigned_shards)
      ~__LOC__
      Check.int
      ~error_msg:
        "Non-banned attesters don't have enough rights to reconstruct slots, \
         (needed: %L, actual: %R)" ;
    (* Check that no non-banned attester has enough
       assigned shards to attest the slot alone. *)
    List.iter2
      (fun assigned_shard_indices attester ->
        Check.(
          attestation_threshold * number_of_shards / 100
          > List.length assigned_shard_indices)
          ~__LOC__
          Check.int
          ~error_msg:
            ("Attester " ^ attester.name
           ^ " has enough right to attest alone, (needed: %L shards, actual: \
              %R)"))
      assigned_shard_indices_non_banned
      non_banned_attesters ;
    (* Check that no initial attester has enough
       assigned shards to reconstruct. *)
    List.iter2
      (fun assigned_shard_indices attester ->
        Check.(
          number_of_shards / redundancy_factor
          > List.length assigned_shard_indices)
          ~__LOC__
          Check.int
          ~error_msg:
            ("Attester " ^ attester.name
           ^ " has enough rights to reconstruct alone, (needed: %L, actual: %R)"
            ))
      assigned_shard_indices_non_banned
      non_banned_attesters ;

    (* Wait until the given [dal_node] receives all the shards whose
       indices are [shards] for the given [commitment]. *)
    let wait_for_shards ~dal_node ~shards commitment =
      let nshards = List.length shards in
      let count = ref 0 in
      let* () =
        Lwt.join
        @@ List.map
             (fun shard_index ->
               let* () =
                 wait_for_stored_slot ~shard_index dal_node commitment
               in
               let () = incr count in
               let () =
                 Log.info
                   "Dal node %s has received %d/%d shards"
                   (Dal_node.name dal_node)
                   !count
                   nshards
               in
               unit)
             shards
      in
      let () =
        Log.info "Dal node %s has received its shards" (Dal_node.name dal_node)
      in
      unit
    in
    info "Waiting for shards" ;

    let wait_shards_reach_attesters commitment attesters assigned_shard_indices
        message =
      let* () =
        Lwt.join
        @@ List.map2
             (fun {dal_node; _} shards ->
               wait_for_shards ~dal_node ~shards commitment)
             attesters
             assigned_shard_indices
      in
      info message ;
      unit
    in

    let wait_shards_reach_observer commitment =
      let* () =
        Lwt.join
        @@ List.map2
             (fun attester shards ->
               let* () =
                 wait_for_shards ~dal_node:observer ~shards commitment
               in
               let () =
                 Log.info
                   "Dal node %s has sent its shards to observer"
                   attester.name
               in
               unit)
             non_banned_attesters
             assigned_shard_indices_non_banned
      in
      info "Non-banned attesters have transmitted their shards to the observer" ;
      unit
    in

    (* Wait until everyone has reveived the needed shards (first the
       non-banned attesters, then the observer, and finally the banned
       attesters). *)
    let wait_slot commitment =
      let wait_non_banned_promise =
        wait_shards_reach_attesters
          commitment
          non_banned_attesters
          assigned_shard_indices_non_banned
          "Non-banned attesters have received their shards"
      in

      let wait_banned_promise =
        wait_shards_reach_attesters
          commitment
          banned_attesters
          assigned_shard_indices_banned
          "Banned attesters have received their shards"
      in

      let wait_observer_promise = wait_shards_reach_observer commitment in

      let* () = wait_non_banned_promise in
      let* () = wait_observer_promise in

      wait_banned_promise
    in
    let* publication_level_bis, _commitment =
      publish_store_and_wait_slot
        node
        client
        slot_producer
        Constant.bootstrap1
        ~index:slot_index
        ~wait_slot
        ~number_of_extra_blocks_to_bake:2
      @@ Helpers.make_slot ~slot_size "content"
    in
    Check.(publication_level_bis = publication_level)
      ~__LOC__
      Check.int
      ~error_msg:
        "Commitment published at unexpected level: expected: %R, actual: %L" ;
    unit

  (* A simpler test in which a slot producer is directly connected to
     an observer node and sends all shards. *)
  let test_amplification_without_lost_shards _protocol dal_parameters _cryptobox
      node client dal_bootstrap =
    (* In this test we have three DAL nodes:
       - a bootstrap one to connect the other two (producer and observer),
       - a slot producer on slot 0,
       - an observer on slot 0.

       We check that when the slot producer publishes a slot, the
       observer performs an amplification. *)
    let index = 0 in
    let slot_size = dal_parameters.Dal.Parameters.cryptobox.slot_size in
    let num_slots = dal_parameters.Dal.Parameters.number_of_slots in
    let peers = [Dal_node.listen_addr dal_bootstrap] in
    let peer_id dal_node = Dal_node.read_identity dal_node in

    (* Check that the dal node passed as argument to this test function
       is a running bootstrap DAL node. If not, this means that we
       forgot to register the test with ~bootstrap_profile:true *)
    let* () =
      check_profiles ~__LOC__ dal_bootstrap ~expected:Dal_RPC.Bootstrap
    in
    Log.info "Bootstrap DAL node is running" ;

    let producer = Dal_node.create ~name:"producer" ~node () in
    let* () = Dal_node.init_config ~producer_profiles:[index] ~peers producer in
    let* () = Dal_node.run ~wait_ready:true producer in
    let producer_peer_id = peer_id producer in
    let* () =
      check_profiles
        ~__LOC__
        producer
        ~expected:Dal_RPC.(Operator [Producer index])
    in
    Log.info "Slot producer DAL node is running" ;

    let observer = Dal_node.create ~name:"observer" ~node () in
    let* () = Dal_node.init_config ~observer_profiles:[index] ~peers observer in
    let* () = Dal_node.run ~wait_ready:true observer in
    let observer_peer_id = peer_id observer in
    let* () =
      check_profiles
        ~__LOC__
        observer
        ~expected:Dal_RPC.(Operator [Observer index])
    in
    Log.info "Observer DAL node is running" ;

    let all_pkhs =
      Account.Bootstrap.keys |> Array.to_list
      |> List.map (fun account -> account.Account.public_key_hash)
    in

    (* The connections between the slot producer and the observer have
       no reason to be grafted on other slot indices than the one they
       are both subscribed to, so we instruct
       [check_events_with_topic] to skip all events but the one for
       [index]. *)
    let already_seen_slots =
      Array.init num_slots (fun slot_index -> slot_index <> index)
    in
    (* Wait for a GRAFT message between the observer and the producer,
       in any direction. *)
    let check_graft pkh =
      let graft_from_observer =
        check_events_with_topic
          ~event_with_topic:(Graft observer_peer_id)
          producer
          ~num_slots
          ~already_seen_slots
          pkh
      in
      let graft_from_producer =
        check_events_with_topic
          ~event_with_topic:(Graft producer_peer_id)
          observer
          ~num_slots
          ~already_seen_slots
          pkh
      in
      Lwt.pick [graft_from_observer; graft_from_producer]
    in
    let check_graft_promises = List.map check_graft all_pkhs in
    Log.info "Waiting for grafting of the observer - producer connection" ;

    (* We need to bake some blocks until the L1 node notifies the DAL
       nodes that some L1 block is final so that the topic pkhs are
       known. *)
    let* () = bake_for ~count:3 client in
    let* () = Lwt.join check_graft_promises in
    Log.info "Observer - producer connection grafted" ;

    (* Produce and publish a slot *)
    let source = Constant.bootstrap1 in
    let slot_content = "content" in
    let* before_publication_level = Client.level client in
    let publication_level = 1 + before_publication_level in
    let wait_slot _commitment =
      Log.info "Waiting for first reconstruction event" ;
      let* () =
        Dal_node.wait_for observer "reconstruct_starting_in.v0" (fun event ->
            if
              JSON.(
                event |-> "level" |> as_int = publication_level
                && event |-> "slot_index" |> as_int = index)
            then Some ()
            else None)
      in
      Log.info
        "Waiting for reconstruction to be canceled because all shards were \
         received, or for the reconstruction to finish" ;
      let promise_reconstruction_cancelled =
        Dal_node.wait_for
          observer
          "reconstruct_no_missing_shard.v0"
          (fun event ->
            if
              JSON.(
                event |-> "level" |> as_int = publication_level
                && event |-> "slot_index" |> as_int = index)
            then Some ()
            else None)
      in
      let promise_reconstruction_finished =
        Dal_node.wait_for observer "reconstruct_finished.v0" (fun event ->
            if
              JSON.(
                event |-> "level" |> as_int = publication_level
                && event |-> "slot_index" |> as_int = index)
            then Some ()
            else None)
      in
      Lwt.pick
        [promise_reconstruction_cancelled; promise_reconstruction_finished]
    in
    let* publication_level_bis, _commitment =
      publish_store_and_wait_slot
        node
        client
        producer
        source
        ~index
        ~wait_slot
        ~number_of_extra_blocks_to_bake:2
      @@ Helpers.make_slot ~slot_size slot_content
    in
    Check.(publication_level_bis = publication_level)
      ~__LOC__
      Check.int
      ~error_msg:"Unexpected publication level, actual:%L, expected:%R" ;

    unit
end

module Garbage_collection = struct
  (* Test the GC feature: once a period (set by history_mode) is passed after
     receiving the shards, each node deletes them from its storage. *)

  let wait_remove_shards commitment node =
    Dal_node.wait_for node "removed_slot_shards.v0" (fun event ->
        if commitment = JSON.(event |> as_string) then Some () else None)

  let wait_for_first_shard commitment node =
    Dal_node.wait_for node "stored_slot_shard.v0" (fun event ->
        if commitment = JSON.(event |-> "commitment" |> as_string) then
          let shard_index = JSON.(event |-> "shard_index" |> as_int) in
          Some shard_index
        else (
          Log.info
            "bad commitment : received : %s, expected : %s"
            JSON.(event |-> "commitment" |> as_string)
            commitment ;
          None))

  let get_shard_rpc commitment shard_id node =
    Dal_RPC.(call node @@ get_shard ~slot_header:commitment ~shard_id)

  let get_shard_rpc_failure_expected commitment node =
    let* shard_observer_response =
      Dal_RPC.(call_raw node @@ get_shard ~slot_header:commitment ~shard_id:0)
    in
    Check.(shard_observer_response.code = 500)
      ~__LOC__
      Check.int
      ~error_msg:"Unexpected RPC response, expected: %R, actual: %L" ;
    unit

  (* This simple test checks the basic feature, with just a producer that
     produces shards & deletes them *)
  let test_gc_simple_producer _protocol dal_parameters _cryptobox node client
      slot_producer =
    let slot_index = 0 in
    (* Parameters and constants. *)
    let Dal.Parameters.{cryptobox = {Dal.Cryptobox.slot_size; _}; _} =
      dal_parameters
    in
    Log.info "Producer DAL node is running" ;

    let wait_slot commitment =
      (* Check the producer stored the first shard *)
      Log.info "RPC to producer for first shard" ;
      let* _first_shard =
        Dal_RPC.(
          call slot_producer @@ get_shard ~slot_header:commitment ~shard_id:0)
      in
      unit
    in

    let* _publication_level, commitment =
      publish_store_and_wait_slot
        node
        client
        slot_producer
        Constant.bootstrap1
        ~index:slot_index
        ~wait_slot
        ~number_of_extra_blocks_to_bake:2
      @@ Helpers.make_slot ~slot_size "content"
    in

    let wait_remove_shards_promise =
      Log.info "Waiting for the shards of the commitment to be removed" ;
      wait_remove_shards commitment slot_producer
    in

    Log.info "Every shard published for the commitment; baking blocks" ;
    let* () = bake_for ~count:30 client in
    Log.info "Blocks baked." ;

    Log.info "Wait for the shards of the commitment to be removed" ;
    let* () = wait_remove_shards_promise in

    Log.info "RPC deleted shard producer" ;
    let* () = get_shard_rpc_failure_expected commitment slot_producer in

    Log.info "End of test" ;
    unit

  (* For this test, we create a network of three DAL nodes — 1 slot producer,
     1 attester, 1 observer (so we can check for each profile). History mode is
     [Auto].
     The slot producer will send shards from one slot; once a node receives it,
     a request is sent for a received shard, to make sure for reception. After
     25 blocks baked, we check via RPC that attester deleted its shards and the
     others did not.
  *)
  let test_gc_with_all_profiles _protocol dal_parameters _cryptobox node client
      dal_bootstrap =
    let slot_index = 0 in
    (* Parameters and constants. *)
    let Dal.Parameters.
          {number_of_slots; cryptobox = {Dal.Cryptobox.slot_size; _}; _} =
      dal_parameters
    in

    (* Note: we don't need to configure and start the DAL bootstrap
       node because it is the node started by the
       scenario_with_layer1_and_dal_nodes wrapper. Instead, we check
       that the dal node passed as argument to this test function is a
       running bootstrap DAL node. If not, this means that we forgot
       to register the test with ~bootstrap_profile:true *)
    let* () =
      check_profiles ~__LOC__ dal_bootstrap ~expected:Dal_RPC.Bootstrap
    in
    Log.info "bootstrap DAL node is running" ;

    (* When configuring the other DAL nodes, we use dal_bootstrap as
       the single peer. *)
    let peers = [Dal_node.listen_addr dal_bootstrap] in
    let attester_pkh = Account.Bootstrap.keys.(0).public_key_hash in

    (* Create & configure attester *)
    let attester = Dal_node.create ~name:"attester" ~node () in
    Dal_node.log_events attester ;
    let* () =
      Dal_node.init_config ~attester_profiles:[attester_pkh] ~peers attester
    in
    let* () = Dal_node.run ~wait_ready:true attester in
    Log.info "attester DAL node ready" ;

    let slot_producer = Dal_node.create ~name:"producer" ~node () in
    Dal_node.log_events slot_producer ;
    let* () =
      Dal_node.init_config ~producer_profiles:[slot_index] ~peers slot_producer
    in
    (* Promise which will be resolved once the slot producer will be
       connected to all the other DAL nodes (attester + observer
       + bootstrap). *)
    let wait_for_connections_of_producer_promise =
      Dal_node.wait_for_connections slot_producer 3
    in
    let* () = Dal_node.run ~wait_ready:true slot_producer in

    (* Create & configure observer *)
    let observer = Dal_node.create ~name:"observer" ~node () in
    Dal_node.log_events observer ;
    let* () =
      Dal_node.init_config ~observer_profiles:[slot_index] ~peers observer
    in
    let* () = Dal_node.run ~wait_ready:true observer in

    (* Check that the DAL nodes have the expected profiles. *)
    let* () =
      check_profiles
        ~__LOC__
        slot_producer
        ~expected:Dal_RPC.(Operator [Producer slot_index])
    in
    Log.info "Slot producer DAL node is running" ;

    let* () =
      check_profiles
        ~__LOC__
        observer
        ~expected:Dal_RPC.(Operator [Observer slot_index])
    in
    Log.info "Observer DAL node is running" ;

    let* () =
      check_profiles
        ~__LOC__
        attester
        ~expected:Dal_RPC.(Operator [Attester attester_pkh])
    in

    Log.info "Attester DAL node is running" ;

    (* Now that all the DAL nodes are running, we need some of them to
       establish grafted connections. The connections between the
       attester and the slot producer have no reason to be grafted on
       other slot indices than the one the slot producer is subscribed
       to, so we instruct [check_events_with_topic] to skip all events
       but the one for [slot_index]. *)
    let already_seen_slots =
      Array.init number_of_slots (fun index -> slot_index <> index)
    in
    (* Wait for a GRAFT message between all nodes. *)
    let check_graft node1 node2 attester_pkh =
      let check_graft ~from:node1 node2 =
        check_events_with_topic
          ~event_with_topic:(Graft (Dal_node.read_identity node1))
          node2
          ~num_slots:number_of_slots
          ~already_seen_slots
          attester_pkh
      in
      Lwt.pick [check_graft ~from:node1 node2; check_graft ~from:node2 node1]
    in
    let check_graft_promises =
      check_graft slot_producer attester attester_pkh
      :: check_graft observer attester attester_pkh
      :: Account.(
           Array.to_list
           @@ (Array.map (fun key ->
                   check_graft slot_producer observer key.public_key_hash))
                Bootstrap.keys)
    in
    Log.info "Waiting for grafting of the DAL nodes connections" ;
    (* The attester DAL node won't join the DAL network until it has
       processed some finalized L1 block in which the associated baker
       is reported to have some rights. For this to happen, we need to
       bake a few blocks. *)
    let* () = bake_for ~count:3 client in
    let* () = Lwt.join check_graft_promises in
    Log.info "Attester - producer connections grafted" ;

    let* () = wait_for_connections_of_producer_promise in

    Log.info "DAL network is ready" ;

    let wait_slot commitment =
      (* We don’t wait for the producer because at this step it already stored
         its shards *)
      let wait_for_first_shard_observer_promise =
        Log.info "Waiting for first shard to be stored by the observer" ;
        wait_for_first_shard commitment observer
      in
      let wait_for_first_shard_attester_promise =
        Log.info "Waiting for first shard to be stored by the attester" ;
        wait_for_first_shard commitment attester
      in
      let* shard_index_observer = wait_for_first_shard_observer_promise in
      let* shard_index_attester = wait_for_first_shard_attester_promise in

      Log.info "RPC first shard observer" ;
      let* _shard_observer =
        get_shard_rpc commitment shard_index_observer observer
      in
      Log.info "RPC first shard producer" ;
      let* _shard_producer = get_shard_rpc commitment 0 slot_producer in
      Log.info "RPC first shard attester" ;
      let* _shard_attester =
        get_shard_rpc commitment shard_index_attester attester
      in
      unit
    in

    let* _publication_level, commitment =
      publish_store_and_wait_slot
        node
        client
        slot_producer
        Constant.bootstrap1
        ~index:slot_index
        ~wait_slot
        ~number_of_extra_blocks_to_bake:2
      @@ Helpers.make_slot ~slot_size "content"
    in

    let wait_remove_shards_attester_promise =
      Log.info "Waiting for first shard to be removed by the attester" ;
      wait_remove_shards commitment attester
    in

    Log.info "All nodes received a shard, waiting for blocks to be baked" ;
    let* () = bake_for ~count:25 client in
    Log.info "Blocks baked !" ;

    Log.info "Wait for first shard attester" ;
    let* () = wait_remove_shards_attester_promise in

    Log.info "RPC deleted shard attester" ;
    let* () = get_shard_rpc_failure_expected commitment attester in

    Log.info "RPC shard still stored observer" ;
    let* _shard_observer = get_shard_rpc commitment 0 observer in
    Log.info "RPC shard still stored producer" ;
    let* _shard_producer = get_shard_rpc commitment 0 slot_producer in

    Log.info "End of test" ;
    unit
end

module Tx_kernel_e2e = struct
  open Tezos_protocol_alpha.Protocol
  open Tezt_tx_kernel

  (** [keys_of_account account] returns a triplet of pk, pkh, sk of [account]  *)
  let keys_of_account (account : Account.key) =
    let pk =
      account.public_key
      |> Tezos_crypto.Signature.Ed25519.Public_key.of_b58check_exn
    in
    let pkh =
      account.public_key_hash
      |> Tezos_crypto.Signature.Ed25519.Public_key_hash.of_b58check_exn
    in
    let sk =
      account.secret_key
      |> Account.require_unencrypted_secret_key ~__LOC__
      |> Tezos_crypto.Signature.Ed25519.Secret_key.of_b58check_exn
    in
    (pk, pkh, sk)

  (** [bake_until cond client sc_rollup_node] bakes until [cond client] retuns [true].
      After baking each block we wait for the [sc_rollup_node] to catch up to L1. *)
  let rec bake_until cond client sc_rollup_node =
    let* stop = cond client in
    if stop then unit
    else
      let* () = bake_for client in
      let* current_level = Client.level client in
      let* _ =
        Sc_rollup_node.wait_for_level ~timeout:30. sc_rollup_node current_level
      in
      bake_until cond client sc_rollup_node

  (** [get_ticket_balance  ~pvm_name ~pkh ~ticket_index] returns
      the L2 balance of the account with [pkh] for the ticket with [ticket_index] *)
  let get_ticket_balance sc_rollup_node ~pvm_name ~pkh ~ticket_index =
    Sc_rollup_node.RPC.call sc_rollup_node
    @@ Sc_rollup_rpc.get_global_block_durable_state_value
         ~pvm_kind:pvm_name
         ~operation:Sc_rollup_rpc.Value
         ~key:
           (sf
              "/accounts/%s/%d"
              (Tezos_crypto.Signature.Ed25519.Public_key_hash.to_b58check pkh)
              ticket_index)
         ()

  (** E2E test using the tx-kernel. Scenario:
      1. Deposit [450] tickets to the L2 [pk1] using the deposit contract.
      2. Construct two batches of L2 transactions to achieve the following:
          1. Transfer [60] tickets from [pk1] to [pk2].
          2. Withdraw [60] tickets from [pk2].
          3. Transfer [90] tickets from [pk1] to [pk2].
          3. Withdraw [40] tickets from [pk2].
      3. Publish the transaction batch to DAL at slot [0].
      4. Bake [attestation_lag] blocks and attest slot [0].
      5. Check that the L2 [pk1] has [300] tickets and [pk2] has [50] tickets.
   *)
  let test_tx_kernel_e2e protocol parameters dal_node sc_rollup_node
      _sc_rollup_address node client pvm_name =
    Log.info "Originate the tx kernel." ;
    let* {boot_sector; _} =
      Sc_rollup_helpers.prepare_installer_kernel
        ~preimages_dir:
          (Filename.concat
             (Sc_rollup_node.data_dir sc_rollup_node)
             "wasm_2_0_0")
        Constant.WASM.tx_kernel_dal
    in
    (* The kernel is badly written and may ask pages in negative
       levels. We ensure it is not possible by baking enough
       blocks. *)
    let* () =
      bake_for ~count:parameters.Dal.Parameters.attestation_lag client
    in
    let* sc_rollup_address =
      Client.Sc_rollup.originate
        ~burn_cap:Tez.(of_int 9999999)
        ~alias:"tx_kernel_dal"
        ~src:Constant.bootstrap1.public_key_hash
        ~kind:"wasm_2_0_0"
        ~boot_sector
        ~parameters_ty:"pair string (ticket string)"
        client
    in
    let* () = bake_for client in
    Log.info "Run the rollup node and ensure origination succeeds." ;
    let* genesis_info =
      Client.RPC.call client
      @@ RPC.get_chain_block_context_smart_rollups_smart_rollup_genesis_info
           sc_rollup_address
    in
    let init_level = JSON.(genesis_info |-> "level" |> as_int) in
    let* () =
      Sc_rollup_node.run sc_rollup_node sc_rollup_address [Log_kernel_debug]
    in
    let* level =
      Sc_rollup_node.wait_for_level ~timeout:30. sc_rollup_node init_level
    in
    Check.(level = init_level)
      Check.int
      ~error_msg:"Current level has moved past origination level (%L = %R)" ;
    Log.info "Create key pairs used for the test." ;
    let pk1, pkh1, sk1 = keys_of_account Constant.bootstrap1 in
    let pk2, pkh2, sk2 = keys_of_account Constant.bootstrap2 in
    Log.info "Prepare contract for minting and depositing." ;
    let* mint_and_deposit_contract =
      Contracts.prepare_mint_and_deposit_contract client protocol
    in
    Log.info "Deposit [450] tickets to the L2 [pk1] using deposit contract." ;
    let ticket_content = "Hello, Ticket!" in
    let* () =
      Contracts.deposit_string_tickets
        client
        ~mint_and_deposit_contract:
          (Contract_hash.to_b58check mint_and_deposit_contract)
        ~sc_rollup_address
        ~destination_l2_addr:
          (Tezos_crypto.Signature.Ed25519.Public_key_hash.to_b58check pkh1)
        ~ticket_content
        ~amount:450
    in
    Log.info "Prepare contract for receiving withdrawn tickets." ;
    let* receive_withdrawn_tickets_contract =
      Contracts.prepare_receive_withdrawn_tickets_contract client protocol
    in
    (* We have slot index [0] hard-coded in the kernel.

       TODO: https://gitlab.com/tezos/tezos/-/issues/6390
       Make it possible to dynamically change tracked slot indexes. *)
    let slot_index = 0 in
    Log.info
      "Construct a batch of L2 transactions that:\n\
       1. Transfers [60] tickets from [pk1] to [pk2].\n\
       3. Withdraw [60] tickets from [pk2] to \
       [receive_withdrawn_tickets_contract]." ;
    let payload1 =
      Transaction_batch.(
        empty
        |> add_transfer
             ~counter:0
             ~signer:(Public_key pk1)
             ~signer_secret_key:sk1
             ~destination:pkh2
             ~ticketer:(Contract_hash.to_b58check mint_and_deposit_contract)
             ~ticket_content
             ~amount:60
        |> add_withdraw
             ~counter:0
             ~signer:(Public_key pk2)
             ~signer_secret_key:sk2
             ~destination:receive_withdrawn_tickets_contract
             ~entrypoint:"receive_tickets"
             ~ticketer:(Contract_hash.to_b58check mint_and_deposit_contract)
             ~ticket_content
             ~amount:60
        |> make_encoded_batch)
    in
    Log.info
      "Construct a batch of L2 transactions that:\n\
       1. Transfers [90] tickets from [pk1] to [pk2].\n\
       3. Withdraw [50] tickets from [pk2] to \
       [receive_withdrawn_tickets_contract]." ;
    let payload2 =
      Transaction_batch.(
        empty
        |> add_transfer
             ~counter:1
             ~signer:(Public_key pk1)
             ~signer_secret_key:sk1
             ~destination:pkh2
             ~ticketer:(Contract_hash.to_b58check mint_and_deposit_contract)
             ~ticket_content
             ~amount:90
        |> add_withdraw
             ~counter:1
             ~signer:(Public_key pk2)
             ~signer_secret_key:sk2
             ~destination:receive_withdrawn_tickets_contract
             ~entrypoint:"receive_tickets"
             ~ticketer:(Contract_hash.to_b58check mint_and_deposit_contract)
             ~ticket_content
             ~amount:40
        |> make_encoded_batch)
    in
    Log.info
      "Publish the [payload1] of size %d to DAL at slot [0]."
      (String.length payload1) ;
    let* () =
      publish_store_and_attest_slot
        client
        node
        dal_node
        Constant.bootstrap1
        ~index:slot_index
        ~content:
          (Helpers.make_slot
             ~slot_size:parameters.Dal.Parameters.cryptobox.slot_size
             payload1)
        ~attestation_lag:parameters.attestation_lag
        ~number_of_slots:parameters.number_of_slots
    in
    Log.info
      "Publish the [payload2] of size %d to DAL at slot [0]."
      (String.length payload2) ;
    let* () =
      publish_store_and_attest_slot
        client
        node
        dal_node
        Constant.bootstrap1
        ~index:slot_index
        ~content:
          (Helpers.make_slot
             ~slot_size:parameters.Dal.Parameters.cryptobox.slot_size
             payload2)
        ~attestation_lag:parameters.attestation_lag
        ~number_of_slots:parameters.number_of_slots
    in
    Log.info "Wait for the rollup node to catch up." ;
    let* current_level = Node.get_level node in
    let* _level =
      Sc_rollup_node.wait_for_level ~timeout:30. sc_rollup_node current_level
    in
    Log.info "Check that [pk1] has [300] tickets." ;
    let* balance =
      get_ticket_balance sc_rollup_node ~pvm_name ~ticket_index:0 ~pkh:pkh1
    in
    Check.(
      (* [2c01000000000000] is [300] when interpreted as little-endian u64. *)
      (balance = Some "2c01000000000000")
        ~__LOC__
        (option string)
        ~error_msg:"Expected %R, got %L") ;
    Log.info "Check that [pk2] has [50] tickets." ;
    let* balance =
      get_ticket_balance sc_rollup_node ~pvm_name ~ticket_index:0 ~pkh:pkh2
    in
    Check.(
      (* [3200000000000000] is [50] when interpreted as little-endian u64. *)
      (balance = Some "3200000000000000")
        (option string)
        ~__LOC__
        ~error_msg:"Expected %R, got %L") ;
    unit

  let test_echo_kernel_e2e _protocol parameters dal_node sc_rollup_node
      _sc_rollup_address node client pvm_name =
    Log.info "Originate the echo kernel." ;
    let* {boot_sector; _} =
      Sc_rollup_helpers.prepare_installer_kernel
        ~preimages_dir:
          (Filename.concat (Sc_rollup_node.data_dir sc_rollup_node) pvm_name)
        Constant.WASM.dal_echo_kernel
    in
    (* The kernel is badly written and may ask pages in negative
       levels. We ensure it is not possible by baking enough
       blocks. *)
    let* () =
      bake_for ~count:parameters.Dal.Parameters.attestation_lag client
    in
    let* sc_rollup_address =
      Client.Sc_rollup.originate
        ~burn_cap:Tez.(of_int 9999999)
        ~alias:"dal_echo_kernel"
        ~src:Constant.bootstrap1.public_key_hash
        ~kind:pvm_name
        ~boot_sector
        ~parameters_ty:"unit"
        client
    in
    let* () = bake_for client in
    let* () =
      Sc_rollup_node.run sc_rollup_node sc_rollup_address [Log_kernel_debug]
    in
    let* current_level = Node.get_level node in
    let target_level =
      current_level + parameters.Dal.Parameters.attestation_lag + 1
    in
    let payload = "hello" in
    let* () =
      publish_store_and_attest_slot
        client
        node
        dal_node
        Constant.bootstrap1
        ~index:0
        ~content:
          (Helpers.make_slot
             ~slot_size:parameters.Dal.Parameters.cryptobox.slot_size
             payload)
        ~attestation_lag:parameters.attestation_lag
        ~number_of_slots:parameters.number_of_slots
    in
    Log.info "Wait for the rollup node to catch up." ;
    let* _level =
      Sc_rollup_node.wait_for_level ~timeout:30. sc_rollup_node target_level
    in
    let key = "/output/slot-0" in
    let* value_written =
      Sc_rollup_node.RPC.call sc_rollup_node ~rpc_hooks
      @@ Sc_rollup_rpc.get_global_block_durable_state_value
           ~pvm_kind:pvm_name
           ~operation:Sc_rollup_rpc.Value
           ~key
           ()
    in
    match value_written with
    | None -> Test.fail "Expected a value to be found. But none was found."
    | Some value ->
        let value = `Hex value |> Hex.to_string in
        Check.(
          (String.length value = parameters.Dal.Parameters.cryptobox.slot_size)
            int
            ~error_msg:"Expected a value of size %R. Got $L") ;
        if String.starts_with ~prefix:payload value then unit
        else
          let message =
            Format.asprintf
              "Expected the payload '%s' to be a prefix of the value written. \
               Instead found: %s"
              payload
              (String.sub value 0 (String.length payload))
          in
          Test.fail "%s" message
end

module Profiler = Tezos_base.Profiler

let dal_crypto_benchmark () =
  Test.register
    ~__FILE__
    ~title:"Benchmark of the DAL cryptographic primitives"
    ~uses_node:false
    ~uses_client:false
    ~uses_admin_client:false
    ~tags:["dal"; "benchmark"; "crypto"; Tag.slow]
  @@ fun () ->
  let open Dal.Cryptobox in
  let driver = Tezos_base_unix.Simple_profiler.auto_write_to_txt_file in
  let file =
    match Cli.Logs.level with
    | Info | Debug -> "/dev/stdout"
    | _ -> Temp.file "/dev/null"
  in
  let instance = Profiler.instance driver (file, Verbose) in
  Profiler.plug Profiler.main instance ;
  let ( let*? ) x f =
    match x with
    | Error err ->
        Test.fail
          "Unexpected error:@.%a@."
          Dal_common.Helpers.pp_cryptobox_error
          err
    | Ok x -> f x
  in
  Log.info "Downloading SRS files..." ;
  let* () =
    Process.run (Base.project_root // "scripts/install_dal_trusted_setup.sh") []
  in
  Log.info "SRS files downloaded." ;
  let number_of_shards = Cli.get_int ~default:512 "nb_shards" in
  let slot_size = Cli.get_int ~default:126_944 "slot_size" in
  let redundancy_factor = Cli.get_int ~default:8 "redundancy" in
  let page_size = Cli.get_int ~default:3967 "page_size" in
  let verifier_srs = Cli.get_bool ~default:true "verifier_srs" in
  let generate_slot ~slot_size =
    Bytes.init slot_size (fun _ ->
        let x = Random.int 26 in
        Char.chr (x + Char.code 'a'))
  in
  let* () =
    let parameters =
      {number_of_shards; redundancy_factor; page_size; slot_size}
    in
    let message =
      Format.asprintf
        "(shards: %d, slot size: %d, redundancy_factor: %d, page size: %d)"
        number_of_shards
        slot_size
        redundancy_factor
        page_size
    in
    let* () =
      Profiler.record_f Profiler.main "SRS" @@ fun () ->
      Log.info "Loading SRS..." ;
      let* result =
        Config.init_prover_dal
          ~find_srs_files:Tezos_base.Dal_srs.find_trusted_setup_files
          Config.
            {
              activated = true;
              bootstrap_peers = [];
              use_mock_srs_for_testing = false;
            }
      in
      Log.info "SRS loaded." ;
      let*? config =
        Result.map_error
          (fun x ->
            `Fail
              (Format.asprintf
                 "%a"
                 Tezos_error_monad.Error_monad.pp_print_trace
                 x))
          result
      in
      Lwt.return config
    in
    Profiler.record_f Profiler.main message @@ fun () ->
    match make parameters with
    | Error (`Fail msg) ->
        let message = Format.asprintf "Fail: %s" msg in
        Profiler.record_f Profiler.main message @@ fun () -> Lwt.return_unit
    | Ok _ ->
        let*? dal =
          Profiler.record_f Profiler.main "make" @@ fun () -> make parameters
        in
        let*? precomputation =
          Profiler.record_f Profiler.main "shard precomputation" @@ fun () ->
          precompute_shards_proofs dal
        in
        let slot =
          Profiler.record_f Profiler.main "slot generation" @@ fun () ->
          generate_slot ~slot_size
        in
        let*? polynomial =
          Profiler.record_f Profiler.main "polynomial from slot" @@ fun () ->
          polynomial_from_slot dal slot
        in
        let*? commitment =
          Profiler.record_f Profiler.main "commit" @@ fun () ->
          commit dal polynomial
        in
        let*? commitment_proof =
          Profiler.record_f Profiler.main "prove commitment" @@ fun () ->
          prove_commitment dal polynomial
        in
        let shards =
          Profiler.record_f Profiler.main "shards from polynomial" @@ fun () ->
          shards_from_polynomial dal polynomial
        in
        let shard_proofs =
          Profiler.record_f Profiler.main "prove shards" @@ fun () ->
          prove_shards dal ~precomputation ~polynomial |> Array.to_seq
        in
        let _polynomial =
          Profiler.record_f Profiler.main "Reconstruct polynomial" @@ fun () ->
          polynomial_from_shards dal shards
        in
        let nb_pages = slot_size / page_size in
        let page_proofs =
          Seq.ints 0 |> Seq.take 1
          |> Seq.map (fun i ->
                 Profiler.record_f Profiler.main "prove page" @@ fun () ->
                 let*? page_proof = prove_page dal polynomial i in
                 page_proof)
        in
        if verifier_srs then Internal_for_tests.init_verifier_dal_default () ;
        let is_valid =
          Profiler.record_f Profiler.main "verify commitment" @@ fun () ->
          verify_commitment dal commitment commitment_proof
        in
        assert is_valid ;
        let () =
          Seq.zip shards shard_proofs
          |> Seq.take 1
          |> Seq.iter (fun (shard, shard_proof) ->
                 let message =
                   Format.asprintf
                     "verify shard (size: %d)"
                     (Bytes.length
                        (Data_encoding.Binary.to_bytes_exn
                           share_encoding
                           shard.share))
                 in
                 Profiler.record_f Profiler.main message @@ fun () ->
                 let*? () = verify_shard dal commitment shard shard_proof in
                 ())
        in
        let bench_i_shard_verif i =
          Seq.zip shards shard_proofs |> Seq.take i |> List.of_seq |> List.split
          |> fun (shard_list, shard_proof_list) ->
          let message =
            Format.asprintf
              "verify shard multi (size: %d) (number_of_shards:%d)"
              (Bytes.length
                 (Data_encoding.Binary.to_bytes_exn
                    share_encoding
                    (List.hd shard_list).share))
              (List.length shard_list)
          in
          Profiler.record_f Profiler.main message @@ fun () ->
          let*? () =
            verify_shard_multi dal commitment shard_list shard_proof_list
          in
          ()
        in
        bench_i_shard_verif 1 ;
        bench_i_shard_verif 5 ;
        bench_i_shard_verif 20 ;
        bench_i_shard_verif 100 ;
        bench_i_shard_verif 2048 ;
        let pages =
          Seq.ints 0 |> Seq.take nb_pages
          |> Seq.map (fun i -> Bytes.sub slot (i * page_size) page_size)
        in
        let () =
          Seq.zip (Seq.ints 0 |> Seq.take nb_pages) (Seq.zip pages page_proofs)
          |> Seq.take 1
          |> Seq.iter (fun (page_index, (page, page_proof)) ->
                 Profiler.record_f Profiler.main "verify page" @@ fun () ->
                 let*? () =
                   verify_page dal commitment ~page_index page page_proof
                 in
                 ())
        in
        () ;
        Lwt.return_unit
  in
  Profiler.close_and_unplug Profiler.main instance ;
  Lwt.return_unit

(*
 * Test proposing to setup a node, and dal node, a baker, in multiple steps.
 * The scenario tries to follow the tutorial steps described in
 *    https://docs.tezos.com/tutorials/join-dal-baker
 * that concerns weeklynet. We use a sandbox node to simplify
 * Regressions in this test can highlight the tutorial is out of sync with
 * the octez components behavior, and the tutorial might have to be fixed.
 * an issue/pull request should be opened to
 * https://github.com/trilitech/tezos-developer-docs/ in these cases, in order
 * to change the tutorial
 *)
let scenario_tutorial_dal_baker =
  let description = "Test following dal and baker tutorial commands" in
  test
    ~regression:true
    ~__FILE__
    ~tags:["tutorial"; "dal"; "baker"]
    ~uses:(fun protocol -> [Protocol.baker protocol; Constant.octez_dal_node])
    (Printf.sprintf "%s" description)
    (fun protocol ->
      (* Note: Step 1 consists in setting up docker which we don't use
       * in this test
       *)
      Log.info "Step 2: Running octez node with adaptive issuance" ;
      with_layer1
        ~parameters:
          [
            (* Force activation of adaptive issuance *)
            (["adaptive_issuance_force_activation"], `Bool true);
            (["adaptive_issuance_activation_vote_enable"], `Bool false);
          ]
        ~event_sections_levels:[("prevalidator", `Debug)]
        ~protocol
      @@ fun _parameters _cryptobox node client _key ->
      Log.info "Step 3: setup a baker account" ;
      (* Generate the "my_baker" user *)
      let* my_baker = Client.gen_and_show_keys ~alias:"my_baker" client in

      (* Transfer 500k to "my_baker"
       * This value differs from the tutorial to obtain attestation rights *)
      let stake = Tez.of_int 500_000 in
      let* () =
        Client.transfer
          ~hooks
          ~giver:Constant.bootstrap1.alias
          ~receiver:my_baker.alias
          ~amount:stake
          ~burn_cap:Tez.one
          client
      in
      let* () = bake_for client in

      (* Check adaptive issuance is enabled, should be 0 *)
      let* adaptive_issuance_launch_cycle =
        Client.RPC.call ~hooks client
        @@ RPC.get_chain_block_context_adaptive_issuance_launch_cycle ()
      in
      Check.(
        (JSON.as_int adaptive_issuance_launch_cycle = 0)
          ~__LOC__
          Check.int
          ~error_msg:
            "Adaptive issuance will only be launched at cycle %L, expected: %R") ;

      let* balance = Client.get_balance_for ~account:my_baker.alias client in
      Check.(balance = stake)
        ~__LOC__
        Tez.typ
        ~error_msg:"Unexpected balance for 'mybaker'. Expected: %L. Got: %R" ;

      (* Register my_baker as a baker *)
      let* () = Client.register_key ~hooks my_baker.alias client in
      let* () = bake_for client in

      (* As in the tutorial, we stake 99.8% of the balance. *)
      let* () =
        Client.stake
          ~hooks
          Tez.(stake - of_int 100)
          ~staker:my_baker.alias
          client
      in
      let* () = bake_for client in

      let* _ =
        Client.RPC.call ~hooks client
        @@ RPC.get_chain_block_context_delegate my_baker.public_key_hash
      in

      (* Calculate how many cycles to wait for my_baker to be a baker *)
      let* proto_params =
        Node.RPC.call node @@ RPC.get_chain_block_context_constants ()
      in
      let blocks_per_cycle =
        JSON.(proto_params |-> "blocks_per_cycle" |> as_int)
      in
      let num_cycles = 7 (* Value specified in tutorial *) in
      Log.info
        "Bake for %d cycles for %s to be a baker"
        num_cycles
        my_baker.alias ;
      let* () = bake_for ~count:(num_cycles * blocks_per_cycle) client in

      let* attestation_rights =
        Client.RPC.call client
        @@ RPC.get_chain_block_helper_attestation_rights
             ~delegate:my_baker.public_key_hash
             ()
      in

      let attestation_power =
        attestation_rights |> JSON.as_list |> List.length
      in
      Log.info
        "Attestation rights: %s\n%!"
        (if attestation_power > 0 then "OK" else "KO") ;
      Check.(attestation_power > 0)
        Check.int
        ~__LOC__
        ~error_msg:"Attestation rights should be acquired" ;

      (* Only test the request can be processed *)
      let* _ =
        Client.RPC.call client @@ RPC.get_chain_block_context_dal_shards ()
      in

      (* Launch dal node (Step 4) *)
      Log.info "Step 4: Run an Octez dal node" ;
      let* dal_node = make_dal_node node in

      let* topics = Dal_RPC.Local.call dal_node @@ Dal_RPC.get_topics () in
      Check.(
        (List.length topics = 0)
          int
          ~__LOC__
          ~error_msg:"Expecting a empty list of topics") ;

      let wait_join_event_promise =
        Dal_node.wait_for dal_node "gossipsub_worker_event-join.v0" (fun _ ->
            Some ())
      in

      let all_delegates =
        Account.Bootstrap.keys |> Array.to_list |> List.cons my_baker
        |> List.map (fun key -> key.Account.alias)
      in
      Log.info "Step 5: Run an Octez baking daemon" ;
      let* _baker =
        Baker.init
          ~event_sections_levels:[(Protocol.name protocol ^ ".baker", `Debug)]
          ~protocol
          ~dal_node
          ~delegates:all_delegates
          ~liquidity_baking_toggle_vote:(Some On)
          ~state_recorder:true
          ~force_apply:true
          node
          client
      in
      (* Wait for subscribed events, as expected in the tutorial *)
      let* () = wait_join_event_promise in

      let* topics = Dal_RPC.Local.call dal_node @@ Dal_RPC.get_topics () in
      Check.(
        (List.length topics > 0)
          int
          ~__LOC__
          ~error_msg:"Expecting a non-empty list of topcis") ;
      unit)

module Refutations = struct
  (**
     This test provides a scenario where two rollup nodes are initialized, one
     with a faulty DAL node and the other with a correct one. The test aims to
     verify the behavior of the rollup nodes and the protocol under these
     conditions. That is: starting (and finishing) a refutation game involving a
     DAL import tick.

     The test performs the following steps:
     - Initializes two DAL nodes, one honest and one faulty.
     - Initializes two rollup nodes, one for each DAL node.
     - Prepares and provides the kernel code for both rollup nodes.
     - Originates the dal_echo_kernel smart rollup.
     - Publishes DAL slots at indices 0 and 1 of the same level.
     - Attest the two slots.
     - Stops the faulty DAL node and alters its shards store to make it return
       wrong data for the attested shards upon request.
     - Resumes the faulty DAL node.
     - Starts the rollup nodes.
     - Enter an (infinite) loop where we bake and wait for rollup nodes to
       process the block.

     The function exits when either:
     - One of the rollup nodes is not able to catch up after 120 seconds, and in this case the test fails, or
     - The refutation game is lost by the faulty rollup node.
  *)
  let scenario_with_two_rollups_a_faulty_dal_node_and_a_correct_one
      ~refute_operations_priority _protocol parameters _dal_node _sc_rollup_node
      _sc_rollup_address node client pvm_name =
    (* Initializing the real SRS. *)
    Log.info "Downloading SRS files..." ;
    let* () =
      Process.run
        (Base.project_root // "scripts/install_dal_trusted_setup.sh")
        []
    in
    Log.info "SRS files downloaded." ;
    let faulty_operator_key = Constant.bootstrap4.public_key_hash in
    let honest_operator_key = Constant.bootstrap5.public_key_hash in
    (* We have two DAL nodes in producer mode *)
    let* honest_dal_node =
      make_dal_node ~name:"dal-honest" ~peers:[] ~producer_profiles:[0; 1] node
    in
    let* faulty_dal_node =
      make_dal_node
        ~name:"dal-faulty"
        ~peers:[Dal_node.listen_addr honest_dal_node]
        ~producer_profiles:[0; 1]
        node
    in

    (* We have two Rollup nodes. One per DAL node *)
    Log.info "Originate the echo kernel." ;
    let honest_sc_rollup_node =
      Sc_rollup_node.create
        ~name:"sc-honest"
        ~dal_node:honest_dal_node
        Operator
        node
        ~base_dir:(Client.base_dir client)
        ~default_operator:honest_operator_key
    in
    let faulty_sc_rollup_node =
      Sc_rollup_node.create
        ~name:"sc-faulty"
        ~dal_node:faulty_dal_node
        Operator
        node
        ~base_dir:(Client.base_dir client)
        ~default_operator:faulty_operator_key
    in

    (* Provide the kernel's code for both rollups *)
    let* boot_sector =
      Lwt_list.fold_left_s
        (fun _boot_sector sc_rollup ->
          let* {boot_sector; _} =
            Sc_rollup_helpers.prepare_installer_kernel
              ~preimages_dir:
                (Filename.concat (Sc_rollup_node.data_dir sc_rollup) pvm_name)
              Constant.WASM.dal_echo_kernel
          in
          return boot_sector)
        ""
        [honest_sc_rollup_node; faulty_sc_rollup_node]
    in

    (* The kernel is badly written and may ask pages in negative
       levels. We ensure it is not possible by baking enough
       blocks. *)
    let* () =
      bake_for ~count:parameters.Dal.Parameters.attestation_lag client
    in

    (* Originate the dal_echo_kernel smart rollup *)
    let* sc_rollup_address =
      Client.Sc_rollup.originate
        ~burn_cap:Tez.(of_int 9999999)
        ~alias:"dal_echo_kernel"
        ~src:Constant.bootstrap1.public_key_hash
        ~kind:pvm_name
        ~boot_sector
        ~parameters_ty:"unit"
        client
    in
    let* () = bake_for client in

    (* Publish two slots and indices 0 and 1, respectively *)
    let publish source index =
      Helpers.make_slot
        ~slot_size:parameters.Dal.Parameters.cryptobox.slot_size
        (Format.sprintf "Hello slot %d" index)
      |> publish_and_store_slot client honest_dal_node source ~index
    in
    let* commitment0 = publish Constant.bootstrap1 0 in
    let* commitment1 = publish Constant.bootstrap2 1 in

    (* Bake sufficiently many blocks to be able to attest. *)
    let* () = bake_for ~count:parameters.attestation_lag client in
    let* () =
      inject_dal_attestations_and_bake
        node
        client
        ~number_of_slots:parameters.number_of_slots
        (Slots [0; 1])
    in

    (* Stop the faulty DAL node and alter its shards store. *)
    let shards_store =
      Dal_node.data_dir faulty_dal_node ^ "/store/shard_store"
    in

    let* () = Dal_node.terminate faulty_dal_node in
    let* () = Dal_node.kill faulty_dal_node in

    (* We published and attested two slots, with commitments [commitment0] and
       [commitment1] respectively, at the same level above. Below, we alter the
       shards store of the faulty node by interchanging the content/shards of
       [commitment0] and [commitment1]. *)
    let mv_shards from into =
      sf "mv %s/%s %s/%s" shards_store from shards_store into
      |> Sys.command |> ignore
    in
    mv_shards commitment0 "tmp" ;
    mv_shards commitment1 commitment0 ;
    mv_shards "tmp" commitment1 ;

    let* () = Dal_node.run ~wait_ready:true faulty_dal_node in

    (* configure the rollup nodes. *)
    let* () =
      Lwt_list.iter_s
        (fun sc_rollup_node ->
          let* _name =
            Sc_rollup_node.config_init
              ~force:true
              sc_rollup_node
              sc_rollup_address
          in
          unit)
        [faulty_sc_rollup_node; honest_sc_rollup_node]
    in
    (Sc_rollup_helpers.prioritize_refute_operations
    @@
    match refute_operations_priority with
    | `Honest_first -> honest_sc_rollup_node
    | `Faulty_first -> faulty_sc_rollup_node) ;

    (* Start the rollup nodes. *)
    let* () =
      Lwt_list.iter_s
        (fun sc_rollup_node ->
          Sc_rollup_node.run sc_rollup_node sc_rollup_address [Log_kernel_debug])
        [faulty_sc_rollup_node; honest_sc_rollup_node]
    in

    let rec loop () =
      let* current_level = Node.get_level node in
      let target_level = current_level + 1 in
      let* () = bake_for client in
      Log.info "Wait for the rollup nodes to catch up at level %d." target_level ;
      let* () =
        Lwt_list.iter_p
          (fun sc_rollup ->
            let* _level =
              Sc_rollup_node.wait_for_level ~timeout:120. sc_rollup target_level
            in
            unit)
          [faulty_sc_rollup_node; honest_sc_rollup_node]
      in
      loop ()
    in
    let (_ : unit Lwt.t) = loop () in
    Sc_rollup_node.check_error
      faulty_sc_rollup_node
      ~exit_code:1
      ~msg:(rex "lost the refutation game")
end

let register ~protocols =
  (* Tests with Layer1 node only *)
  scenario_with_layer1_node
    ~additional_bootstrap_accounts:1
    "dal basic logic"
    test_slot_management_logic
    protocols ;
  scenario_with_layer1_node
    ~attestation_lag:5
    "slots attestation operation behavior"
    test_slots_attestation_operation_behavior
    protocols ;
  (* We want to test that the number of slots following mainnet
     parameters can be included into one block. We hard-code the
     mainnet value. It could be extended to higher values if
     desired. *)
  scenario_with_layer1_node
    ~regression:true
    ~number_of_slots:32
    ~additional_bootstrap_accounts:(32 - Array.length Account.Bootstrap.keys)
    "Use all available slots"
    test_all_available_slots
    protocols ;
  scenario_with_layer1_node
    "slots attestation operation dal committee membership check"
    test_slots_attestation_operation_dal_committee_membership_check
    (* We need to set the prevalidator's event level to [`Debug]
       in order to capture the errors thrown in the validation phase. *)
    ~event_sections_levels:[("prevalidator", `Debug)]
    ~number_of_shards:32
    ~consensus_committee_size:1024
    protocols ;
  scenario_with_layer1_node
    "one_committee_per_level"
    test_one_committee_per_level
    protocols ;

  (* Tests with layer1 and dal nodes *)
  test_dal_node_startup protocols ;
  scenario_with_layer1_and_dal_nodes
    ~producer_profiles:[0]
    "dal node slot management"
    test_dal_node_slot_management
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~producer_profiles:[0]
    "dal node slot headers tracking"
    test_dal_node_slots_headers_tracking
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~producer_profiles:[0]
    "dal node shard fetching and slot reconstruction"
    test_dal_node_rebuild_from_shards
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~producer_profiles:[0]
    "dal node POST /commitments"
    test_dal_node_test_post_commitments
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~producer_profiles:[0]
    "dal node PATCH /commitments"
    test_dal_node_test_patch_commitments
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~producer_profiles:[0]
    "dal node GET /commitments/<commitment>/slot"
    test_dal_node_test_get_commitment_slot
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~producer_profiles:[0]
    "dal node GET /commitments/<commitment>/proof"
    test_dal_node_test_get_commitment_proof
    protocols ;
  scenario_with_layer1_and_dal_nodes
    "dal node PATCH+GET /profiles"
    test_dal_node_test_patch_profile
    protocols ;
  scenario_with_layer1_and_dal_nodes
    "dal node GET \
     /profiles/<public_key_hash>/attested_levels/<level>/assigned_shard_indices"
    test_dal_node_get_assigned_shard_indices
    protocols ;
  scenario_with_layer1_and_dal_nodes
    "dal node GET \
     /profiles/<public_key_hash>/attested_levels/<level>/attestable_slots"
    ~producer_profiles:[0]
    test_dal_node_get_attestable_slots
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~attestation_threshold:100
    ~producer_profiles:[0]
    "dal attester with bake for"
    test_attester_with_bake_for
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~uses:(fun protocol -> [Protocol.baker protocol])
    ~attestation_threshold:100
    ~attestation_lag:16
    ~activation_timestamp:Now
    ~producer_profiles:[0]
    "dal attester with baker daemon"
    test_attester_with_daemon
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~tags:["snapshot"; "import"]
    ~producer_profiles:[0]
    "dal node import snapshot"
    test_dal_node_import_snapshot
    protocols ;

  (* Tests with layer1 and dal nodes (with p2p/GS) *)
  scenario_with_layer1_and_dal_nodes
    ~tags:["gossipsub"]
    "GS/P2P connection and disconnection"
    test_dal_node_p2p_connection_and_disconnection
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~tags:["gossipsub"]
    "GS join topic"
    test_dal_node_join_topic
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~tags:["gossipsub"]
    ~producer_profiles:[0]
    "GS valid messages exchange"
    test_dal_node_gs_valid_messages_exchange
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~tags:["gossipsub"]
    "GS invalid messages exchange"
    ~producer_profiles:[0]
    test_dal_node_gs_invalid_messages_exchange
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~tags:["gossipsub"]
    ~producer_profiles:[0]
    "GS prune due to negative score, and ihave"
    test_gs_prune_and_ihave
    protocols ;
  scenario_with_layer1_and_dal_nodes
    "baker registers profiles with dal node"
    ~uses:(fun protocol -> [Protocol.baker protocol])
    ~activation_timestamp:Now
    test_baker_registers_profiles
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~tags:["bootstrap"]
    ~bootstrap_profile:true
    "peer discovery via bootstrap node"
    test_peer_discovery_via_bootstrap_node
    protocols ;

  scenario_with_layer1_and_dal_nodes
    ~tags:["bootstrap"; "trusted"; "connection"]
    ~bootstrap_profile:true
    "trusted peers reconnection"
    test_peers_reconnection
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~tags:["producer"; "profile"]
    "producer profile"
    test_producer_profile
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~tags:["attestation"; "p2p"]
    ~attestation_threshold:100
    ~bootstrap_profile:true
    "attestation through p2p"
    test_attestation_through_p2p
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~producer_profiles:[15]
    "commitments history RPCs"
    test_commitments_history_rpcs
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~tags:["amplification"]
    ~bootstrap_profile:true
    ~redundancy_factor:2
      (* With a redundancy factor of 4 or more, not much luck is
         needed for a bootstrap account (with 1/5 of the stake) to be
         assigned enough shards to reconstruct alone. Since the
         redundancy factor must be a power of 2, we use 2 which means
         that half of the shards are needed to perform a
         reconstruction. *)
    ~number_of_slots:1
    "banned attesters receive their shards thanks to amplification"
    Amplification.test_amplification
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~tags:["amplification"; "simple"]
    ~bootstrap_profile:true
    "observer triggers amplification (without lost shards)"
    Amplification.test_amplification_without_lost_shards
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~tags:["gc"; "simple"]
    ~producer_profiles:[0]
    ~history_mode:(Dal_node.Custom 15)
    ~number_of_slots:1
    "garbage collection of shards for producer"
    Garbage_collection.test_gc_simple_producer
    protocols ;
  scenario_with_layer1_and_dal_nodes
    ~tags:["gc"; "multi"]
    ~bootstrap_profile:true
    ~number_of_slots:1
    "garbage collection of shards for all profiles"
    Garbage_collection.test_gc_with_all_profiles
    protocols ;

  (* Tests with all nodes *)
  scenario_with_all_nodes
    ~producer_profiles:[0]
    "rollup_node_downloads_slots"
    rollup_node_stores_dal_slots
    protocols ;
  scenario_with_all_nodes
    ~producer_profiles:[0]
    "rollup_node_applies_dal_pages"
    (rollup_node_stores_dal_slots ~expand_test:rollup_node_interprets_dal_pages)
    protocols ;
  scenario_with_all_nodes
    ~producer_profiles:[0]
    "test reveal_dal_page in fast exec wasm pvm"
    ~uses:(fun _protocol ->
      [Constant.smart_rollup_installer; Constant.WASM.dal_echo_kernel])
    ~pvm_name:"wasm_2_0_0"
    ~number_of_shards:256
    ~slot_size:(1 lsl 15)
    ~redundancy_factor:8
    ~attestation_lag:4
    ~page_size:128
    test_reveal_dal_page_in_fast_exec_wasm_pvm
    protocols ;
  scenario_with_all_nodes
    "test tx_kernel"
    ~uses:(fun _protocol ->
      [Constant.smart_rollup_installer; Constant.WASM.tx_kernel_dal])
    ~pvm_name:"wasm_2_0_0"
    ~producer_profiles:[0]
    ~number_of_shards:256
    ~slot_size:(1 lsl 15)
    ~redundancy_factor:8
    ~page_size:128
    ~attestation_lag:4
    Tx_kernel_e2e.test_tx_kernel_e2e
    protocols ;
  scenario_with_all_nodes
    "test echo_kernel"
    ~uses:(fun _protocol ->
      [Constant.smart_rollup_installer; Constant.WASM.dal_echo_kernel])
    ~pvm_name:"wasm_2_0_0"
    ~slot_size:2048
    ~page_size:256
    ~number_of_shards:64
    ~producer_profiles:[0]
    Tx_kernel_e2e.test_echo_kernel_e2e
    protocols ;

  (* Register tutorial test *)
  scenario_tutorial_dal_baker protocols ;

  scenario_with_all_nodes
    "Refutation where the faulty node timeouts"
    ~regression:false
    ~uses:(fun _protocol ->
      [Constant.smart_rollup_installer; Constant.WASM.dal_echo_kernel])
    ~pvm_name:"wasm_2_0_0"
    ~commitment_period:5
    (Refutations.scenario_with_two_rollups_a_faulty_dal_node_and_a_correct_one
       ~refute_operations_priority:`Faulty_first)
    ~smart_rollup_timeout_period_in_blocks:20
    ~use_mock_srs_for_testing:false
    ~tags:[Tag.slow]
    protocols ;

  scenario_with_all_nodes
    "Refutation where the honest node makes final move"
    ~regression:false
    ~uses:(fun _protocol ->
      [Constant.smart_rollup_installer; Constant.WASM.dal_echo_kernel])
    ~pvm_name:"wasm_2_0_0"
    ~commitment_period:5
    (Refutations.scenario_with_two_rollups_a_faulty_dal_node_and_a_correct_one
       ~refute_operations_priority:`Honest_first)
    ~smart_rollup_timeout_period_in_blocks:20
    ~use_mock_srs_for_testing:false
    ~tags:[Tag.slow]
    protocols ;

  (* Register end-to-end tests *)
  register_end_to_end_tests ~protocols ;
  dal_crypto_benchmark ()

let register_migration ~migrate_from ~migrate_to =
  test_migration_plugin ~migration_level:4 ~migrate_from ~migrate_to
