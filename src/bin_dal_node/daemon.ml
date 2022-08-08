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

type ctxt = {
  config : Configuration.t;
  dal_constants : Cryptobox.t;
  dal_parameters : Cryptobox.parameters;
}

module RPC_server = struct
  let register_split_slot ctxt store dir =
    RPC_directory.register0
      dir
      (Services.split_slot ())
      (Services.handle_split_slot ctxt.dal_parameters ctxt.dal_constants store)

  let register_show_slot ctxt store dir =
    RPC_directory.register
      dir
      (Services.slot ())
      (Services.handle_slot ctxt.dal_parameters ctxt.dal_constants store)

  let register_shard store dir =
    RPC_directory.register dir (Services.shard ()) (Services.handle_shard store)

  let register ctxt store =
    RPC_directory.empty
    |> register_split_slot ctxt store
    |> register_show_slot ctxt store
    |> register_shard store

  let start configuration dir =
    let open Lwt_syntax in
    let Configuration.{rpc_addr; rpc_port; _} = configuration in
    let rpc_addr = P2p_addr.of_string_exn rpc_addr in
    let host = Ipaddr.V6.to_string rpc_addr in
    let node = `TCP (`Port rpc_port) in
    let acl = RPC_server.Acl.default rpc_addr in
    Lwt.catch
      (fun () ->
        let* server =
          RPC_server.launch
            ~media_types:Media_type.all_media_types
            ~host
            ~acl
            node
            dir
        in
        return_ok server)
      fail_with_exn

  let shutdown = RPC_server.shutdown

  let install_finalizer rpc_server =
    let open Lwt_syntax in
    Lwt_exit.register_clean_up_callback ~loc:__LOC__ @@ fun exit_status ->
    let* () = shutdown rpc_server in
    let* () = Event.(emit shutdown_node exit_status) in
    Tezos_base_unix.Internal_event_unix.close ()
end

let daemonize cctxt handle = Lwt.no_cancel @@ Layer1.iter_events cctxt handle

let resolve_plugin cctxt =
  let open Lwt_result_syntax in
  let* protocols =
    Tezos_shell_services.Chain_services.Blocks.protocols cctxt ()
  in
  return
  @@ Option.either
       (Dal_constants_plugin.get protocols.current_protocol)
       (Dal_constants_plugin.get protocols.next_protocol)

let run ~data_dir ~no_trusted_setup:_ cctxt =
  let open Lwt_result_syntax in
  let*! () = Event.(emit starting_node) () in
  let* config = Configuration.load ~data_dir in
  let config = {config with data_dir} in
  let*! store = Store.init config in
  let*? g1_path, g2_path = Tezos_base.Dal_srs.find_trusted_setup_files () in
  let* initialisation_parameters =
    Cryptobox.initialisation_parameters_from_files ~g1_path ~g2_path
  in
  let*? () = Cryptobox.load_parameters initialisation_parameters in
  let ready = ref false in
  let*! () = Event.(emit layer1_node_tracking_started ()) in
  daemonize cctxt @@ fun (_hash, (_block_header : Tezos_base.Block_header.t)) ->
  if not !ready then
    let* plugin = resolve_plugin cctxt in
    match plugin with
    | Some plugin ->
        let (module Plugin : Dal_constants_plugin.T) = plugin in
        let*! () =
          Event.(
            emit
              protocol_plugin_resolved
              (Format.asprintf "%a" Protocol_hash.pp_short Plugin.Proto.hash))
        in
        let* dal_constants, dal_parameters = Cryptobox.init cctxt plugin in
        let ctxt = {config; dal_constants; dal_parameters} in
        let* rpc_server = RPC_server.(start config (register ctxt store)) in
        let _ = RPC_server.install_finalizer rpc_server in
        let*! () =
          Event.(emit rpc_server_is_ready (config.rpc_addr, config.rpc_port))
        in
        let*! () = Event.(emit node_is_ready ()) in
        ready := true ;
        return_unit
    | None -> return_unit
  else return_unit
