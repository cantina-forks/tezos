(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2023 Functori <contact@functori.com>                        *)
(* Copyright (c) 2023 Marigold <contact@marigold.dev>                        *)
(* Copyright (c) 2024 Functori <contact@functori.com>                        *)
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

type time_between_blocks = Nothing | Time_between_blocks of float

type mode =
  | Observer of {
      initial_kernel : string;
      preimages_dir : string;
      rollup_node_endpoint : string;
      devmode : bool;
    }
  | Threshold_encryption_observer of {
      initial_kernel : string;
      preimages_dir : string;
      rollup_node_endpoint : string;
      bundler_node_endpoint : string;
      devmode : bool;
    }
  | Sequencer of {
      initial_kernel : string;
      preimage_dir : string option;
      private_rpc_port : int option;
      time_between_blocks : time_between_blocks option;
      sequencer : string;
      genesis_timestamp : Client.timestamp option;
      max_blueprints_lag : int option;
      max_blueprints_ahead : int option;
      max_blueprints_catchup : int option;
      catchup_cooldown : int option;
      max_number_of_chunks : int option;
      devmode : bool;
      wallet_dir : string option;
      tx_pool_timeout_limit : int option;
      tx_pool_addr_limit : int option;
      tx_pool_tx_per_addr_limit : int option;
    }
  | Threshold_encryption_sequencer of {
      initial_kernel : string;
      preimage_dir : string option;
      private_rpc_port : int option;
      time_between_blocks : time_between_blocks option;
      sequencer : string;
      genesis_timestamp : Client.timestamp option;
      max_blueprints_lag : int option;
      max_blueprints_ahead : int option;
      max_blueprints_catchup : int option;
      catchup_cooldown : int option;
      max_number_of_chunks : int option;
      devmode : bool;
      wallet_dir : string option;
      tx_pool_timeout_limit : int option;
      tx_pool_addr_limit : int option;
      tx_pool_tx_per_addr_limit : int option;
      sequencer_sidecar_endpoint : string;
    }
  | Proxy of {devmode : bool}

module Per_level_map = Map.Make (Int)

module Parameters = struct
  type persistent_state = {
    arguments : string list;
    mutable pending_ready : unit option Lwt.u list;
    mutable last_injected_level : int;
    mutable pending_blueprint_injected : unit option Lwt.u list Per_level_map.t;
    mutable last_applied_level : int;
    mutable pending_blueprint_applied : unit option Lwt.u list Per_level_map.t;
    mode : mode;
    data_dir : string;
    rpc_addr : string;
    rpc_port : int;
    endpoint : string;
    runner : Runner.t option;
  }

  type session_state = {mutable ready : bool}

  let base_default_name = "evm_node"

  let default_colors = Log.Color.[|FG.green; FG.yellow; FG.cyan; FG.magenta|]
end

open Parameters
include Daemon.Make (Parameters)

let mode t = t.persistent_state.mode

let is_sequencer t =
  match t.persistent_state.mode with
  | Sequencer _ | Threshold_encryption_sequencer _ -> true
  | Observer _ | Threshold_encryption_observer _ | Proxy _ -> false

let initial_kernel t =
  match t.persistent_state.mode with
  | Sequencer {initial_kernel; _}
  | Threshold_encryption_sequencer {initial_kernel; _}
  | Observer {initial_kernel; _}
  | Threshold_encryption_observer {initial_kernel; _} ->
      initial_kernel
  | Proxy _ ->
      Test.fail
        "Wrong argument: [initial_kernel] does not support the proxy node"

let can_apply_blueprint t =
  match t.persistent_state.mode with
  | Sequencer _ | Threshold_encryption_sequencer _ | Observer _
  | Threshold_encryption_observer _ ->
      true
  | Proxy _ -> false

let connection_arguments ?rpc_addr ?rpc_port () =
  let open Cli_arg in
  let rpc_port =
    match rpc_port with None -> Port.fresh () | Some port -> port
  in
  ( ["--rpc-port"; string_of_int rpc_port]
    @ optional_arg "rpc-addr" Fun.id rpc_addr,
    Option.value ~default:Constant.default_host rpc_addr,
    rpc_port )

let trigger_ready sc_node value =
  let pending = sc_node.persistent_state.pending_ready in
  sc_node.persistent_state.pending_ready <- [] ;
  List.iter (fun pending -> Lwt.wakeup_later pending value) pending

let trigger_blueprint_injected evm_node level =
  let pending = evm_node.persistent_state.pending_blueprint_injected in
  let pending_for_level = Per_level_map.find_opt level pending in
  evm_node.persistent_state.last_injected_level <- level ;
  evm_node.persistent_state.pending_blueprint_injected <-
    Per_level_map.remove level pending ;
  List.iter (fun pending -> Lwt.wakeup_later pending (Some ()))
  @@ Option.value ~default:[] pending_for_level

let trigger_blueprint_applied evm_node level =
  let pending = evm_node.persistent_state.pending_blueprint_applied in
  let pending_for_level = Per_level_map.find_opt level pending in
  evm_node.persistent_state.last_applied_level <- level ;
  evm_node.persistent_state.pending_blueprint_applied <-
    Per_level_map.remove level pending ;
  List.iter (fun pending -> Lwt.wakeup_later pending (Some ()))
  @@ Option.value ~default:[] pending_for_level

let set_ready evm_node =
  (match evm_node.status with
  | Not_running -> ()
  | Running status -> status.session_state.ready <- true) ;
  trigger_ready evm_node (Some ())

let event_ready_name = "is_ready.v0"

let event_blueprint_injected_name = "blueprint_injection.v0"

let event_blueprint_applied_name = "blueprint_application.v0"

let handle_is_ready_event (evm_node : t) {name; value = _; timestamp = _} =
  if name = event_ready_name then set_ready evm_node else ()

let handle_blueprint_injected_event (evm_node : t) {name; value; timestamp = _}
    =
  if name = event_blueprint_injected_name then
    trigger_blueprint_injected evm_node JSON.(value |> as_int)
  else ()

let handle_blueprint_applied_event (evm_node : t) {name; value; timestamp = _} =
  if name = event_blueprint_applied_name then
    trigger_blueprint_applied evm_node
    @@ JSON.(
         match value |-> "level" |> as_int_opt with
         | Some i -> i (* in devmode. To delete at next upgrade *)
         | None -> value |> as_int (* in prod *))
  else ()

let resolve_or_timeout ?(timeout = 30.) evm_node ~name promise =
  let res = ref None in
  let promise =
    let* result = promise in
    res := Some result ;
    unit
  in
  let* () = Lwt.pick [promise; Lwt_unix.sleep timeout] in
  match !res with
  | Some v -> return v
  | None -> Test.fail "Timeout waiting for %s of %s" name evm_node.name

let wait_for_event ?timeout evm_node ~event f =
  resolve_or_timeout ?timeout evm_node ~name:event @@ wait_for evm_node event f

let raise_terminated_when_none ?where evm_node ~event promise =
  let* res = promise in
  match res with
  | Some x -> return x
  | None ->
      raise (Terminated_before_event {daemon = evm_node.name; event; where})

let wait_for_event_listener ?timeout evm_node ~event promise =
  resolve_or_timeout ?timeout evm_node ~name:event
  @@ raise_terminated_when_none evm_node ~event promise

let wait_for_ready ?timeout evm_node =
  match evm_node.status with
  | Running {session_state = {ready = true; _}; _} -> unit
  | Not_running | Running {session_state = {ready = false; _}; _} ->
      let promise, resolver = Lwt.task () in
      evm_node.persistent_state.pending_ready <-
        resolver :: evm_node.persistent_state.pending_ready ;
      wait_for_event_listener ?timeout evm_node ~event:event_ready_name promise

let wait_for_blueprint_injected ?timeout evm_node level =
  match evm_node.status with
  | Running {session_state = {ready = true; _}; _} when is_sequencer evm_node ->
      let current_level = evm_node.persistent_state.last_injected_level in
      if level <= current_level then unit
      else
        let promise, resolver = Lwt.task () in
        evm_node.persistent_state.pending_blueprint_injected <-
          Per_level_map.update
            level
            (fun pending -> Some (resolver :: Option.value ~default:[] pending))
            evm_node.persistent_state.pending_blueprint_injected ;
        wait_for_event_listener
          ?timeout
          evm_node
          ~event:event_blueprint_injected_name
          promise
  | Running {session_state = {ready = true; _}; _} ->
      failwith "EVM node is not a sequencer"
  | Not_running | Running {session_state = {ready = false; _}; _} ->
      failwith "EVM node is not ready"

let wait_for_blueprint_applied ?timeout evm_node level =
  match evm_node.status with
  | Running {session_state = {ready = true; _}; _}
    when can_apply_blueprint evm_node ->
      let current_level = evm_node.persistent_state.last_applied_level in
      if level <= current_level then unit
      else
        let promise, resolver = Lwt.task () in
        evm_node.persistent_state.pending_blueprint_applied <-
          Per_level_map.update
            level
            (fun pending -> Some (resolver :: Option.value ~default:[] pending))
            evm_node.persistent_state.pending_blueprint_applied ;
        wait_for_event_listener
          ?timeout
          evm_node
          ~event:event_blueprint_applied_name
          promise
  | Running {session_state = {ready = true; _}; _} ->
      failwith "EVM node cannot produce blueprints"
  | Not_running | Running {session_state = {ready = false; _}; _} ->
      failwith "EVM node is not ready"

let wait_for_pending_upgrade ?timeout evm_node =
  wait_for_event ?timeout evm_node ~event:"pending_upgrade.v0"
  @@ JSON.(
       fun json ->
         let root_hash = json |-> "root_hash" |> as_string in
         let timestamp = json |-> "timestamp" |> as_string in
         Some (root_hash, timestamp))

let wait_for_successful_upgrade ?timeout evm_node =
  wait_for_event ?timeout evm_node ~event:"applied_upgrade.v0"
  @@ JSON.(
       fun json ->
         let root_hash = json |-> "root_hash" |> as_string in
         let level = json |-> "level" |> as_int in
         Some (root_hash, level))

let wait_for_block_producer_locked ?timeout evm_node =
  wait_for_event ?timeout evm_node ~event:"block_producer_locked.v0"
  @@ Fun.const (Some ())

let wait_for_block_producer_tx_injected ?timeout evm_node =
  wait_for_event
    ?timeout
    evm_node
    ~event:"block_producer_transaction_injected.v0"
  @@ fun json ->
  let hash = JSON.(json |> as_string) in
  Some hash

let wait_for_retrying_connect ?timeout evm_node =
  wait_for_event ?timeout evm_node ~event:"retrying_connect.v0"
  @@ Fun.const (Some ())

type delayed_transaction_kind = Deposit | Transaction

let delayed_transaction_kind_of_string = function
  | "transaction" -> Transaction
  | "deposit" -> Deposit
  | s -> Test.fail "%s is neither a transaction or deposit" s

let wait_for_rollup_node_follower_connection_acquired ?timeout evm_node =
  wait_for_event
    ?timeout
    evm_node
    ~event:"rollup_node_follower_connection_acquired.v0"
  @@ Fun.const (Some ())

type 'a evm_event_kind =
  | Kernel_upgrade : (string * Client.Time.t) evm_event_kind
  | Sequencer_upgrade : (string * Hex.t * Client.Time.t) evm_event_kind
  | Blueprint_applied : (int * string) evm_event_kind
  | New_delayed_transaction : (delayed_transaction_kind * string) evm_event_kind

let string_of_evm_event_kind : type a. a evm_event_kind -> string = function
  | Kernel_upgrade -> "kernel_upgrade"
  | Sequencer_upgrade -> "sequencer_upgrade"
  | Blueprint_applied -> "blueprint_applied"
  | New_delayed_transaction -> "new_delayed_transaction"

let parse_evm_event_kind : type a. a evm_event_kind -> JSON.t -> a option =
 fun kind json ->
  let open JSON in
  match kind with
  | Kernel_upgrade -> (
      match as_list (json |-> "event") with
      | [hash; timestamp] ->
          let hash = as_string hash in
          let timestamp = as_string timestamp |> Client.Time.of_notation_exn in
          Some (hash, timestamp)
      | _ ->
          Test.fail
            ~__LOC__
            "invalid json for the evm event kind kernel upgrade")
  | Sequencer_upgrade -> (
      match as_list (json |-> "event") with
      | [hash; pool_address; timestamp] ->
          let hash = as_string hash in
          let pool_address = as_string pool_address |> Hex.of_string in
          let timestamp = as_string timestamp |> Client.Time.of_notation_exn in
          Some (hash, pool_address, timestamp)
      | _ ->
          Test.fail
            ~__LOC__
            "invalid json for the evm event kind sequencer upgrade")
  | Blueprint_applied -> (
      match as_list (json |-> "event") with
      | [number; hash] ->
          let number = as_int number in
          let hash = as_string hash in
          Some (number, hash)
      | _ ->
          Test.fail
            ~__LOC__
            "invalid json for the evm event kind blueprint applied")
  | New_delayed_transaction -> (
      match as_list_opt (json |-> "event") with
      | Some [kind; hash; _raw] ->
          let kind = delayed_transaction_kind_of_string (as_string kind) in
          let hash = as_string hash in
          Some (kind, hash)
      | _ ->
          Test.fail
            ~__LOC__
            "invalid json for the evm event kind new delayed transaction")

let wait_for_evm_event ?timeout event ?(check = parse_evm_event_kind event)
    evm_node =
  wait_for_event ?timeout evm_node ~event:"evm_events_new_event.v0"
  @@ JSON.(
       fun json ->
         let found_event_kind = json |-> "kind" |> as_string in
         let expected_event_kind = string_of_evm_event_kind event in
         if expected_event_kind = found_event_kind then check json else None)

let wait_for_shutdown_event evm_node =
  wait_for evm_node "shutting_down.v0" @@ fun json ->
  JSON.(json |> as_int |> Option.some)

let wait_for_diverged evm_node =
  wait_for evm_node "evm_events_follower_diverged.v0" @@ fun json ->
  let open JSON in
  let level = json |-> "level" |> as_int in
  let expected_hash = json |-> "expected_hash" |> as_string in
  let found_hash = json |-> "found_hash" |> as_string in
  Some (level, expected_hash, found_hash)

let wait_for_missing_blueprint evm_node =
  wait_for evm_node "evm_events_follower_missing_blueprint.v0" @@ fun json ->
  let open JSON in
  let level = json |-> "level" |> as_int in
  let expected_hash = json |-> "expected_hash" |> as_string in
  Some (level, expected_hash)

let wait_for_rollup_node_ahead evm_node =
  wait_for evm_node "evm_events_follower_rollup_node_ahead.v0" @@ fun json ->
  let open JSON in
  let level = json |> as_int in
  Some level

let wait_for_tx_pool_add_transaction ?timeout evm_node =
  wait_for_event ?timeout evm_node ~event:"tx_pool_add_transaction.v0"
  @@ JSON.as_string_opt

let create ?name ?runner ?(mode = Proxy {devmode = false}) ?data_dir ?rpc_addr
    ?rpc_port endpoint =
  let arguments, rpc_addr, rpc_port =
    connection_arguments ?rpc_addr ?rpc_port ()
  in
  let new_name () =
    match mode with
    | Proxy _ -> "proxy_" ^ fresh_name ()
    | Sequencer _ -> "sequencer_" ^ fresh_name ()
    | Threshold_encryption_sequencer _ -> "te_sequencer" ^ fresh_name ()
    | Observer _ -> "observer_" ^ fresh_name ()
    | Threshold_encryption_observer _ ->
        "threshold_encryption_observer_" ^ fresh_name ()
  in
  let name = Option.value ~default:(new_name ()) name in
  let data_dir =
    match data_dir with None -> Temp.dir name | Some dir -> dir
  in
  let evm_node =
    create
      ~path:(Uses.path Constant.octez_evm_node)
      ~name
      {
        arguments;
        pending_ready = [];
        last_injected_level = 0;
        pending_blueprint_injected = Per_level_map.empty;
        last_applied_level = 0;
        pending_blueprint_applied = Per_level_map.empty;
        mode;
        data_dir;
        rpc_addr;
        rpc_port;
        endpoint;
        runner;
      }
  in
  on_event evm_node (handle_is_ready_event evm_node) ;
  on_event evm_node (handle_blueprint_injected_event evm_node) ;
  on_event evm_node (handle_blueprint_applied_event evm_node) ;
  evm_node

let name evm_node = evm_node.name

let data_dir evm_node = ["--data-dir"; evm_node.persistent_state.data_dir]

(* assume a valid config for the given command and uses new latest run
   command format. *)
let run_args evm_node =
  let shared_args = data_dir evm_node @ evm_node.persistent_state.arguments in
  let mode_args =
    match evm_node.persistent_state.mode with
    | Proxy _ -> ["run"; "proxy"]
    | Sequencer {initial_kernel; genesis_timestamp; wallet_dir; _} ->
        ["run"; "sequencer"; "--initial-kernel"; initial_kernel]
        @ Cli_arg.optional_arg
            "genesis-timestamp"
            (fun timestamp ->
              Client.time_of_timestamp timestamp |> Client.Time.to_notation)
            genesis_timestamp
        @ Cli_arg.optional_arg "wallet-dir" Fun.id wallet_dir
    | Threshold_encryption_sequencer
        {initial_kernel; genesis_timestamp; wallet_dir; _} ->
        [
          "run";
          "threshold";
          "encryption";
          "sequencer";
          "--initial-kernel";
          initial_kernel;
        ]
        @ Cli_arg.optional_arg
            "genesis-timestamp"
            (fun timestamp ->
              Client.time_of_timestamp timestamp |> Client.Time.to_notation)
            genesis_timestamp
        @ Cli_arg.optional_arg "wallet-dir" Fun.id wallet_dir
    | Observer {initial_kernel; _} ->
        ["run"; "observer"; "--initial-kernel"; initial_kernel]
    | Threshold_encryption_observer {initial_kernel; bundler_node_endpoint; _}
      ->
        [
          "run";
          "observer";
          "--initial-kernel";
          initial_kernel;
          "--bundler-node-endpoint";
          bundler_node_endpoint;
        ]
  in
  mode_args @ shared_args

let run ?(wait = true) ?(extra_arguments = []) evm_node =
  let on_terminate _status =
    (* Cancel all event listeners. *)
    trigger_ready evm_node None ;
    let pending_blueprint_injected =
      evm_node.persistent_state.pending_blueprint_injected
    in
    evm_node.persistent_state.pending_blueprint_injected <- Per_level_map.empty ;
    Per_level_map.iter
      (fun _ pending_list ->
        List.iter (fun pending -> Lwt.wakeup_later pending None) pending_list)
      pending_blueprint_injected ;
    let pending_blueprint_applied =
      evm_node.persistent_state.pending_blueprint_applied
    in
    evm_node.persistent_state.pending_blueprint_applied <- Per_level_map.empty ;
    Per_level_map.iter
      (fun _ pending_list ->
        List.iter (fun pending -> Lwt.wakeup_later pending None) pending_list)
      pending_blueprint_applied ;
    unit
  in
  let* () =
    run
      ~event_level:`Debug
      evm_node
      {ready = false}
      (run_args evm_node @ extra_arguments)
      ~on_terminate
  in
  let* () = if wait then wait_for_ready evm_node else unit in
  unit

let spawn_command evm_node args =
  Process.spawn
    ~name:evm_node.name
    ~color:evm_node.color
    ?runner:evm_node.persistent_state.runner
    (Uses.path Constant.octez_evm_node)
  @@ args

let spawn_run ?(extra_arguments = []) evm_node =
  spawn_command evm_node (run_args evm_node @ extra_arguments)

let spawn_init_config ?(extra_arguments = []) evm_node =
  let shared_args = data_dir evm_node @ evm_node.persistent_state.arguments in
  let mode_args =
    match evm_node.persistent_state.mode with
    | Proxy {devmode} ->
        ["--rollup-node-endpoint"; evm_node.persistent_state.endpoint]
        @ Cli_arg.optional_switch "devmode" devmode
    | Sequencer
        {
          initial_kernel = _;
          preimage_dir;
          private_rpc_port;
          time_between_blocks;
          sequencer;
          genesis_timestamp = _;
          max_blueprints_lag;
          max_blueprints_ahead;
          max_blueprints_catchup;
          catchup_cooldown;
          max_number_of_chunks;
          devmode;
          wallet_dir;
          tx_pool_timeout_limit;
          tx_pool_addr_limit;
          tx_pool_tx_per_addr_limit;
        } ->
        [
          "--rollup-node-endpoint";
          evm_node.persistent_state.endpoint;
          "--sequencer-key";
          sequencer;
        ]
        @ Cli_arg.optional_arg "preimages-dir" Fun.id preimage_dir
        @ Cli_arg.optional_arg "private-rpc-port" string_of_int private_rpc_port
        @ Cli_arg.optional_arg
            "maximum-blueprints-lag"
            string_of_int
            max_blueprints_lag
        @ Cli_arg.optional_arg
            "maximum-blueprints-ahead"
            string_of_int
            max_blueprints_ahead
        @ Cli_arg.optional_arg
            "maximum-blueprints-catch-up"
            string_of_int
            max_blueprints_catchup
        @ Cli_arg.optional_arg
            "catch-up-cooldown"
            string_of_int
            catchup_cooldown
        @ Cli_arg.optional_arg
            "time-between-blocks"
            (function
              | Nothing -> "none"
              | Time_between_blocks f -> Format.sprintf "%.3f" f)
            time_between_blocks
        @ Cli_arg.optional_arg
            "max-number-of-chunks"
            string_of_int
            max_number_of_chunks
        @ Cli_arg.optional_switch "devmode" devmode
        @ Cli_arg.optional_arg "wallet-dir" Fun.id wallet_dir
        @ Cli_arg.optional_arg
            "tx-pool-timeout-limit"
            string_of_int
            tx_pool_timeout_limit
        @ Cli_arg.optional_arg
            "tx-pool-addr-limit"
            string_of_int
            tx_pool_addr_limit
        @ Cli_arg.optional_arg
            "tx-pool-tx-per-addr-limit"
            string_of_int
            tx_pool_tx_per_addr_limit
    | Threshold_encryption_sequencer
        {
          initial_kernel = _;
          preimage_dir;
          private_rpc_port;
          time_between_blocks;
          sequencer;
          genesis_timestamp = _;
          max_blueprints_lag;
          max_blueprints_ahead;
          max_blueprints_catchup;
          catchup_cooldown;
          max_number_of_chunks;
          devmode;
          wallet_dir;
          tx_pool_timeout_limit;
          tx_pool_addr_limit;
          tx_pool_tx_per_addr_limit;
          sequencer_sidecar_endpoint;
        } ->
        [
          "--rollup-node-endpoint";
          evm_node.persistent_state.endpoint;
          "--sequencer-key";
          sequencer;
          "--sequencer-sidecar-endpoint";
          sequencer_sidecar_endpoint;
        ]
        @ Cli_arg.optional_arg "preimages-dir" Fun.id preimage_dir
        @ Cli_arg.optional_arg "private-rpc-port" string_of_int private_rpc_port
        @ Cli_arg.optional_arg
            "maximum-blueprints-lag"
            string_of_int
            max_blueprints_lag
        @ Cli_arg.optional_arg
            "maximum-blueprints-ahead"
            string_of_int
            max_blueprints_ahead
        @ Cli_arg.optional_arg
            "maximum-blueprints-catch-up"
            string_of_int
            max_blueprints_catchup
        @ Cli_arg.optional_arg
            "catch-up-cooldown"
            string_of_int
            catchup_cooldown
        @ Cli_arg.optional_arg
            "time-between-blocks"
            (function
              | Nothing -> "none"
              | Time_between_blocks f -> Format.sprintf "%.3f" f)
            time_between_blocks
        @ Cli_arg.optional_arg
            "max-number-of-chunks"
            string_of_int
            max_number_of_chunks
        @ Cli_arg.optional_switch "devmode" devmode
        @ Cli_arg.optional_arg "wallet-dir" Fun.id wallet_dir
        @ Cli_arg.optional_arg
            "tx-pool-timeout-limit"
            string_of_int
            tx_pool_timeout_limit
        @ Cli_arg.optional_arg
            "tx-pool-addr-limit"
            string_of_int
            tx_pool_addr_limit
        @ Cli_arg.optional_arg
            "tx-pool-tx-per-addr-limit"
            string_of_int
            tx_pool_tx_per_addr_limit
    | Observer
        {preimages_dir; initial_kernel = _; rollup_node_endpoint; devmode} ->
        [
          "--evm-node-endpoint";
          evm_node.persistent_state.endpoint;
          "--rollup-node-endpoint";
          rollup_node_endpoint;
          "--preimages-dir";
          preimages_dir;
        ]
        @ Cli_arg.optional_switch "devmode" devmode
    | Threshold_encryption_observer
        {
          preimages_dir;
          initial_kernel = _;
          rollup_node_endpoint;
          bundler_node_endpoint;
          devmode;
        } ->
        [
          "--evm-node-endpoint";
          evm_node.persistent_state.endpoint;
          "--rollup-node-endpoint";
          rollup_node_endpoint;
          "--bundler-node-endpoint";
          bundler_node_endpoint;
          "--preimages-dir";
          preimages_dir;
        ]
        @ Cli_arg.optional_switch "devmode" devmode
  in
  spawn_command evm_node @@ ["init"; "config"] @ mode_args @ shared_args
  @ extra_arguments

let endpoint ?(private_ = false) (evm_node : t) =
  let addr, port, path =
    if private_ then
      match evm_node.persistent_state.mode with
      | Sequencer {private_rpc_port = Some private_rpc_port; _} ->
          (Constant.default_host, private_rpc_port, "/private")
      | Sequencer {private_rpc_port = None; _} ->
          Test.fail "Sequencer doesn't have a private RPC server"
      | Threshold_encryption_sequencer
          {private_rpc_port = Some private_rpc_port; _} ->
          (Constant.default_host, private_rpc_port, "/private")
      | Threshold_encryption_sequencer {private_rpc_port = None; _} ->
          Test.fail
            "Threshold encryption sequencer doesn't have a private RPC server"
      | Proxy _ -> Test.fail "Proxy doesn't have a private RPC server"
      | Observer _ -> Test.fail "Observer doesn't have a private RPC server"
      | Threshold_encryption_observer _ ->
          Test.fail
            "Threshold encryption observer doesn't have a private RPC server"
    else
      ( evm_node.persistent_state.rpc_addr,
        evm_node.persistent_state.rpc_port,
        "" )
  in
  Format.sprintf "http://%s:%d%s" addr port path

let init ?name ?runner ?mode ?data_dir ?rpc_addr ?rpc_port rollup_node =
  let evm_node =
    create ?name ?runner ?mode ?data_dir ?rpc_addr ?rpc_port rollup_node
  in
  let* () = Process.check @@ spawn_init_config evm_node in
  let* () = run evm_node in
  return evm_node

let init_from_rollup_node_data_dir ?(devmode = false) evm_node rollup_node =
  let rollup_node_data_dir = Sc_rollup_node.data_dir rollup_node in
  let process =
    spawn_command
      evm_node
      (["init"; "from"; "rollup"; "node"; rollup_node_data_dir]
      @ data_dir evm_node
      @ Cli_arg.optional_switch "devmode" devmode)
  in
  Process.check process

type request = {method_ : string; parameters : JSON.u}

let request_to_JSON {method_; parameters} : JSON.u =
  `O
    ([
       ("jsonrpc", `String "2.0");
       ("method", `String method_);
       ("id", `String "0");
     ]
    @ if parameters == `Null then [] else [("params", parameters)])

let build_request request =
  request_to_JSON request |> JSON.annotate ~origin:"evm_node"

let batch_requests requests =
  `A (List.map request_to_JSON requests) |> JSON.annotate ~origin:"evm_node"

(* We keep both encoding (with a single object or an array of objects) and both
   function on purpose, to ensure both encoding are supported by the server. *)
let call_evm_rpc ?(private_ = false) evm_node request =
  let endpoint = endpoint ~private_ evm_node in
  Curl.post endpoint (build_request request) |> Runnable.run

let batch_evm_rpc ?(private_ = false) evm_node requests =
  let endpoint = endpoint ~private_ evm_node in
  Curl.post endpoint (batch_requests requests) |> Runnable.run

let extract_result json = JSON.(json |-> "result")

let extract_error_message json = JSON.(json |-> "error" |-> "message")

let fetch_contract_code evm_node contract_address =
  let* code =
    call_evm_rpc
      evm_node
      {
        method_ = "eth_getCode";
        parameters = `A [`String contract_address; `String "latest"];
      }
  in
  return (extract_result code |> JSON.as_string)

type txpool_slot = {address : string; transactions : (int64 * JSON.t) list}

let txpool_content evm_node =
  let* txpool =
    call_evm_rpc evm_node {method_ = "txpool_content"; parameters = `A []}
  in
  Log.info "Result: %s" (JSON.encode txpool) ;
  let txpool = extract_result txpool in
  let parse field =
    let open JSON in
    let pool = txpool |-> field in
    (* `|->` returns `Null if the field does not exists, and `Null is
       interpreted as the empty list by `as_object`. As such, we must ensure the
       field exists. *)
    if is_null pool then Test.fail "%s must exists" field
    else
      pool |> as_object
      |> List.map (fun (address, transactions) ->
             let transactions =
               transactions |> as_object
               |> List.map (fun (nonce, tx) -> (Int64.of_string nonce, tx))
             in
             {address; transactions})
  in
  return (parse "pending", parse "queued")

let upgrade_payload ~root_hash ~activation_timestamp =
  let args =
    [
      "make";
      "upgrade";
      "payload";
      "with";
      "root";
      "hash";
      root_hash;
      "at";
      "activation";
      "timestamp";
      activation_timestamp;
    ]
  in
  let process = Process.spawn (Uses.path Constant.octez_evm_node) @@ args in
  let* payload = Process.check_and_read_stdout process in
  return (String.trim payload)

let transform_dump ~dump_json ~dump_rlp =
  let args = ["transform"; "dump"; dump_json; "to"; "rlp"; dump_rlp] in
  let process = Process.spawn (Uses.path Constant.octez_evm_node) @@ args in
  Process.check process

let reset evm_node ~l2_level =
  let args =
    ["reset"; "at"; string_of_int l2_level; "--force"] @ data_dir evm_node
  in
  let process = Process.spawn (Uses.path Constant.octez_evm_node) @@ args in
  Process.check process

let sequencer_upgrade_payload ?(devmode = true) ?client ~public_key
    ~pool_address ~activation_timestamp () =
  let args =
    [
      "make";
      "sequencer";
      "upgrade";
      "payload";
      "with";
      "pool";
      "address";
      pool_address;
      "at";
      "activation";
      "timestamp";
      activation_timestamp;
      "for";
      public_key;
    ]
  in
  let process =
    Process.spawn (Uses.path Constant.octez_evm_node)
    @@ args
    @ Cli_arg.optional_arg
        "wallet-dir"
        Fun.id
        (Option.map Client.base_dir client)
    @ Cli_arg.optional_switch "devmode" devmode
  in
  let* payload = Process.check_and_read_stdout process in
  return (String.trim payload)

let chunk_data ?(devmode = true) ~rollup_address ?sequencer_key ?timestamp
    ?parent_hash ?number ?client data =
  let args = "chunk" :: "data" :: data in
  let sequencer =
    match sequencer_key with
    | None -> []
    | Some key -> ["--as-blueprint"; "--sequencer-key"; key]
  in
  let rollup_address = ["--rollup-address"; Fun.id rollup_address] in
  let timestamp = Cli_arg.optional_arg "timestamp" Fun.id timestamp in
  let parent_hash = Cli_arg.optional_arg "parent-hash" Fun.id parent_hash in
  let number = Cli_arg.optional_arg "number" string_of_int number in
  let devmode = Cli_arg.optional_switch "devmode" devmode in
  let process =
    Process.spawn (Uses.path Constant.octez_evm_node)
    @@ args @ rollup_address @ sequencer @ timestamp @ parent_hash @ number
    @ devmode
    @ Cli_arg.optional_arg
        "wallet-dir"
        Fun.id
        (Option.map Client.base_dir client)
  in
  let* output = Process.check_and_read_stdout process in
  (* `tl` will remove the first line `Chunked_transactions :` *)
  let chunks = String.split_on_char '\n' (String.trim output) |> List.tl in
  return chunks

let wait_termination (evm_node : t) =
  match evm_node.status with
  | Not_running -> unit
  | Running {process; _} ->
      let* _status = Process.wait process in
      unit

let make_kernel_installer_config ?(remove_whitelist = false) ?kernel_root_hash
    ?chain_id ?bootstrap_balance ?bootstrap_accounts ?sequencer ?delayed_bridge
    ?ticketer ?administrator ?sequencer_governance ?kernel_governance
    ?kernel_security_governance ?minimum_base_fee_per_gas
    ?(da_fee_per_byte = Wei.zero) ?delayed_inbox_timeout
    ?delayed_inbox_min_levels ?sequencer_pool_address ?maximum_allowed_ticks
    ?maximum_gas_per_transaction ~output () =
  let cmd =
    ["make"; "kernel"; "installer"; "config"; output]
    @ Cli_arg.optional_switch "remove-whitelist" remove_whitelist
    @ Cli_arg.optional_arg "kernel-root-hash" Fun.id kernel_root_hash
    @ Cli_arg.optional_arg "chain-id" string_of_int chain_id
    @ Cli_arg.optional_arg "sequencer" Fun.id sequencer
    @ Cli_arg.optional_arg "delayed-bridge" Fun.id delayed_bridge
    @ Cli_arg.optional_arg "ticketer" Fun.id ticketer
    @ Cli_arg.optional_arg "admin" Fun.id administrator
    @ Cli_arg.optional_arg "sequencer-governance" Fun.id sequencer_governance
    @ Cli_arg.optional_arg "kernel-governance" Fun.id kernel_governance
    @ Cli_arg.optional_arg
        "kernel-security-governance"
        Fun.id
        kernel_security_governance
    @ Cli_arg.optional_arg
        "minimum-base-fee-per-gas"
        Wei.to_string
        minimum_base_fee_per_gas
    @ ["--da-fee-per-byte"; Wei.to_string da_fee_per_byte]
    @ Cli_arg.optional_arg
        "delayed-inbox-timeout"
        string_of_int
        delayed_inbox_timeout
    @ Cli_arg.optional_arg
        "delayed-inbox-min-levels"
        string_of_int
        delayed_inbox_min_levels
    @ Cli_arg.optional_arg
        "sequencer-pool-address"
        Fun.id
        sequencer_pool_address
    @ Cli_arg.optional_arg
        "maximum-allowed-ticks"
        Int64.to_string
        maximum_allowed_ticks
    @ Cli_arg.optional_arg
        "maximum-gas-per-transaction"
        Int64.to_string
        maximum_gas_per_transaction
    @ Cli_arg.optional_arg "bootstrap-balance" Wei.to_string bootstrap_balance
    @
    match bootstrap_accounts with
    | None -> []
    | Some bootstrap_accounts ->
        List.flatten
        @@ List.map
             (fun bootstrap_account ->
               ["--bootstrap-account"; bootstrap_account])
             bootstrap_accounts
  in
  let process = Process.spawn (Uses.path Constant.octez_evm_node) cmd in
  Runnable.{value = process; run = Process.check}
