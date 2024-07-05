(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2024 Functori <contact@functori.com>                        *)
(*                                                                           *)
(*****************************************************************************)

module MakeBackend (Ctxt : sig
  val smart_rollup_address : Tezos_crypto.Hashed.Smart_rollup_address.t
end) : Services_backend_sig.Backend = struct
  module Reader = struct
    let read ?block path = Evm_context.inspect ?block path
  end

  module TxEncoder = struct
    type transactions = string list

    type messages = transactions

    let encode_transactions ~smart_rollup_address:_ ~transactions:_ =
      assert false
  end

  module Publisher = struct
    type messages = TxEncoder.messages

    let publish_messages ~timestamp:_ ~smart_rollup_address:_ ~messages:_ =
      assert false
  end

  module SimulatorBackend = struct
    let simulate_and_read ?block ~input () =
      let open Lwt_result_syntax in
      let* raw_insights = Evm_context.execute_and_inspect ?block input in
      match raw_insights with
      | [Some bytes] -> return bytes
      | _ -> Error_monad.failwith "Invalid insights format"
  end

  let block_param_to_block_number = Evm_context.block_param_to_block_number

  module Tracer = Tracer

  let smart_rollup_address =
    Tezos_crypto.Hashed.Smart_rollup_address.to_string Ctxt.smart_rollup_address
end

module Make (Ctxt : sig
  val smart_rollup_address : Tezos_crypto.Hashed.Smart_rollup_address.t
end) =
  Services_backend_sig.Make (MakeBackend (Ctxt))

let install_finalizer_seq server private_server =
  let open Lwt_syntax in
  Lwt_exit.register_clean_up_callback ~loc:__LOC__ @@ fun exit_status ->
  let* () = Events.shutdown_node ~exit_status in
  let* () = Tezos_rpc_http_server.RPC_server.shutdown server in
  let* () = Events.shutdown_rpc_server ~private_:false in
  let* () =
    Option.iter_s
      (fun private_server ->
        let* () = Tezos_rpc_http_server.RPC_server.shutdown private_server in
        Events.shutdown_rpc_server ~private_:true)
      private_server
  in
  Misc.unwrap_error_monad @@ fun () ->
  let open Lwt_result_syntax in
  let* () = Tx_pool.shutdown () in
  let* () = Evm_events_follower.shutdown () in
  let* () = Blueprints_publisher.shutdown () in
  return_unit

let callback_log server conn req body =
  let open Cohttp in
  let open Lwt_syntax in
  let uri = req |> Request.uri |> Uri.to_string in
  let meth = req |> Request.meth |> Code.string_of_method in
  let* body_str = body |> Cohttp_lwt.Body.to_string in
  let* () = Events.callback_log ~uri ~meth ~body:body_str in
  Tezos_rpc_http_server.RPC_server.resto_callback
    server
    conn
    req
    (Cohttp_lwt.Body.of_string body_str)

let start_server
    Configuration.
      {
        rpc_addr;
        rpc_port;
        cors_origins;
        cors_headers;
        max_active_connections;
        _;
      } ~directory ~private_info =
  let open Lwt_result_syntax in
  let open Tezos_rpc_http_server in
  let p2p_addr = P2p_addr.of_string_exn rpc_addr in
  let host = Ipaddr.V6.to_string p2p_addr in
  let node = `TCP (`Port rpc_port) in
  let acl = RPC_server.Acl.allow_all in
  let cors =
    Resto_cohttp.Cors.
      {allowed_headers = cors_headers; allowed_origins = cors_origins}
  in
  let server =
    RPC_server.init_server
      ~acl
      ~cors
      ~media_types:Supported_media_types.all
      directory
  in
  let private_info =
    Option.map
      (fun (private_directory, private_rpc_port) ->
        let private_server =
          RPC_server.init_server
            ~acl
            ~cors
            ~media_types:Media_type.all_media_types
            private_directory
        in
        (private_server, private_rpc_port))
      private_info
  in
  let private_server = Option.map fst private_info in
  Lwt.catch
    (fun () ->
      let*! () =
        RPC_server.launch
          ~max_active_connections
          ~host
          server
          ~callback:(callback_log server)
          node
      in
      let*! () =
        Option.iter_s
          (fun (private_server, private_rpc_port) ->
            let host = Ipaddr.V4.(to_string localhost) in
            let*! () =
              RPC_server.launch
                ~max_active_connections
                ~host
                private_server
                ~callback:(callback_log private_server)
                (`TCP (`Port private_rpc_port))
            in
            Events.private_server_is_ready
              ~rpc_addr:host
              ~rpc_port:private_rpc_port)
          private_info
      in
      let*! () = Events.is_ready ~rpc_addr ~rpc_port in
      return (server, private_server))
    (fun _ -> return (server, private_server))

(* https://gitlab.com/tezos/tezos/-/issues/7244
   Refactor this in a separate module to react to multiple
   events simultaneously. *)
let loop_sequencer
    (Configuration.Threshold_encryption_sequencer sequencer_config)
    preblocks_monitor =
  let open Lwt_result_syntax in
  let time_between_blocks = sequencer_config.time_between_blocks in
  match time_between_blocks with
  | Nothing ->
      (* Bind on a never-resolved promise ensures this call never returns,
         meaning no block will ever be produced. *)
      let task, _resolver = Lwt.task () in
      let*! () = task in
      return_unit
  | Time_between_blocks time_between_blocks ->
      let rec loop last_produced_block =
        let now = Misc.now () in
        (* We force if the last produced block is older than [time_between_blocks]. *)
        let force =
          let diff = Time.Protocol.(diff now last_produced_block) in
          diff >= Int64.of_float time_between_blocks
        in
        (* Submit a proposal request. *)
        let* () =
          Threshold_encryption_proposals_handler.add_proposal_request
            {timestamp = now; force}
        in
        (* Wait until a preblock is available, or a decision that no preblock will be produced
           has been made. *)
        let* preblock_opt =
          Threshold_encryption_preblocks_monitor.next preblocks_monitor
        in
        let* nb_transactions =
          match preblock_opt with
          | No_preblock ->
              let*! () = Lwt_unix.sleep 0.5 in
              return 0
          | Preblock preblock ->
              Threshold_encryption_block_producer.produce_block preblock
        in
        let* timestamp =
          Threshold_encryption_proposals_handler.notify_proposal_processed ()
        in
        if nb_transactions > 0 || force then loop timestamp
        else loop last_produced_block
      in
      let now = Misc.now () in
      loop now

let main ~data_dir ?(genesis_timestamp = Misc.now ()) ~cctxt
    ~(configuration : Configuration.t) ?kernel () =
  let open Lwt_result_syntax in
  let open Configuration in
  let {rollup_node_endpoint; keep_alive; _} = configuration in
  let* smart_rollup_address =
    Rollup_services.smart_rollup_address
      ~keep_alive:configuration.keep_alive
      rollup_node_endpoint
  in
  let*? (Threshold_encryption_sequencer threshold_encryption_sequencer_config) =
    Configuration.threshold_encryption_sequencer_config_exn configuration
  in
  let* status =
    Evm_context.start
      ?kernel_path:kernel
      ~data_dir
      ~preimages:threshold_encryption_sequencer_config.preimages
      ~preimages_endpoint:
        threshold_encryption_sequencer_config.preimages_endpoint
      ~smart_rollup_address
      ~fail_on_missing_blueprint:true
      ~sqlite_journal_mode:
        (`Force configuration.experimental_features.sqlite_journal_mode)
      ~store_perm:`Read_write
      ()
  in
  let*! head = Evm_context.head_info () in
  let (Qty next_blueprint_number) = head.next_blueprint_number in
  let* () =
    Blueprints_publisher.start
      ~rollup_node_endpoint
      ~config:threshold_encryption_sequencer_config.blueprints_publisher_config
      ~latest_level_seen:(Z.pred next_blueprint_number)
      ~keep_alive
      ()
  in
  let* () =
    if status = Created then
      (* Create the first empty block. *)
      let* genesis =
        Sequencer_blueprint.create
          ~cctxt
          ~sequencer_key:threshold_encryption_sequencer_config.sequencer
          ~timestamp:genesis_timestamp
          ~smart_rollup_address
          ~transactions:[]
          ~delayed_transactions:[]
          ~number:Ethereum_types.(Qty Z.zero)
          ~parent_hash:Ethereum_types.genesis_parent_hash
      in
      let* () = Evm_context.apply_blueprint genesis_timestamp genesis [] in
      Blueprints_publisher.publish Z.zero genesis
    else return_unit
  in

  let smart_rollup_address_typed =
    Tezos_crypto.Hashed.Smart_rollup_address.of_string_exn smart_rollup_address
  in

  let module Rollup_rpc = Make (struct
    let smart_rollup_address = smart_rollup_address_typed
  end) in
  let* () =
    Tx_pool.start
      {
        rollup_node = (module Rollup_rpc);
        smart_rollup_address;
        mode = Sequencer;
        tx_timeout_limit = configuration.tx_pool_timeout_limit;
        tx_pool_addr_limit = Int64.to_int configuration.tx_pool_addr_limit;
        tx_pool_tx_per_addr_limit =
          Int64.to_int configuration.tx_pool_tx_per_addr_limit;
        max_number_of_chunks =
          Some threshold_encryption_sequencer_config.max_number_of_chunks;
      }
  in
  (* Start the preblocks monitor, and obtain a channel for notifying the
     monitor when a proposal will not make it into a preblock.
     This is necessary to avoid the threshold encryption sequencer loop to
     hang waiting for a preblock, when none will ever be produced.
  *)
  let* preblocks_monitor, notify_no_preblock =
    Threshold_encryption_preblocks_monitor.init
      threshold_encryption_sequencer_config.sidecar_endpoint
  in
  let* () =
    Threshold_encryption_proposals_handler.start
      {
        sidecar_endpoint = threshold_encryption_sequencer_config.sidecar_endpoint;
        keep_alive = configuration.keep_alive;
        maximum_number_of_chunks =
          threshold_encryption_sequencer_config.max_number_of_chunks;
        notify_no_preblock;
      }
  in
  let* () =
    Threshold_encryption_block_producer.start
      {
        sequencer_key = threshold_encryption_sequencer_config.sequencer;
        smart_rollup_address;
        cctxt;
      }
  in
  let* () =
    Evm_events_follower.start
      {rollup_node_endpoint; keep_alive; filter_event = (fun _ -> true)}
  in
  let () =
    Rollup_node_follower.start ~keep_alive ~proxy:false ~rollup_node_endpoint ()
  in
  let directory =
    Services.directory configuration ((module Rollup_rpc), smart_rollup_address)
  in
  let directory =
    directory |> Evm_services.register smart_rollup_address_typed
  in
  let private_info =
    Option.map
      (fun private_rpc_port ->
        let private_directory =
          Services.private_directory
            ~threshold_encryption:true
            configuration
            ((module Rollup_rpc), smart_rollup_address)
        in
        (private_directory, private_rpc_port))
      threshold_encryption_sequencer_config.private_rpc_port
  in
  let* server, private_server =
    start_server configuration ~directory ~private_info
  in
  let (_ : Lwt_exit.clean_up_callback_id) =
    install_finalizer_seq server private_server
  in
  let* () =
    loop_sequencer
      (Threshold_encryption_sequencer threshold_encryption_sequencer_config)
      preblocks_monitor
  in
  return_unit
