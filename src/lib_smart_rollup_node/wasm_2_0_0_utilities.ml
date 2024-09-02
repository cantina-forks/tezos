(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let load_context ~data_dir (module Plugin : Protocol_plugin_sig.S) mode =
  let (module C) = Plugin.Pvm.context Wasm_2_0_0 in
  Context.load
    (module C)
    ~cache_size:0
    mode
    (Configuration.default_context_dir data_dir)

(** [get_wasm_pvm_state ~l2_header data_dir] reads the WASM PVM state in
    [data_dir] for the given [l2_header].*)
let get_wasm_pvm_state ~(l2_header : Sc_rollup_block.header) context =
  let open Lwt_result_syntax in
  let context_hash = l2_header.context in
  let block_hash = l2_header.block_hash in
  (* Now, we can checkout the state of the rollup of the given block hash *)
  let*! ctxt = Context.checkout context context_hash in
  let* ctxt =
    match ctxt with
    | None ->
        tzfail
          (Rollup_node_errors.Cannot_checkout_context
             (block_hash, Some context_hash))
    | Some ctxt -> return ctxt
  in
  let*! state = Context.PVMState.find ctxt in
  match state with
  | Some s -> return s
  | None -> failwith "No PVM state found for block %a" Block_hash.pp block_hash

(** [decode_value tree] decodes a durable storage value from the given tree. *)
let decode_value ~(pvm : (module Pvm_plugin_sig.S)) tree =
  let open Lwt_syntax in
  let module Pvm : Pvm_plugin_sig.S = (val pvm) in
  let* cbv =
    Pvm.Wasm_2_0_0.decode_durable_state
      Tezos_lazy_containers.Chunked_byte_vector.encoding
      tree
  in
  Tezos_lazy_containers.Chunked_byte_vector.to_string cbv

(** Returns whether the value under the current key should be dumped. *)
let check_dumpable_path key =
  match key with
  (* The /readonly subpath cannot be set by the user and is reserved to the PVM.
     The kernel code is rewritten by the installer or the debugger, as such it
     doesn't need to be part of the dump. Any value under these two won't be
     part of the dump. *)
  | "readonly" :: _ | "kernel" :: "boot.wasm" :: _ -> `Nothing
  | l -> (
      match List.rev l with
      | "@" :: path -> `Value (List.rev path)
      | _ -> `Nothing)

(** [print_set_value] dumps a value in the YAML format of the installer. *)
let set_value_instr ~(pvm : (module Pvm_plugin_sig.S)) key tree =
  let open Lwt_syntax in
  let full_key = String.concat "/" key in
  let+ value = decode_value ~pvm tree in
  Installer_config.Set {value; to_ = "/" ^ full_key}

(* [generate_durable_storage tree] folds on the keys in the durable storage and
   their values and generates as set of instructions out of it. The order is not
   specified. *)
let generate_durable_storage ~(plugin : (module Protocol_plugin_sig.S)) tree =
  let open Lwt_syntax in
  let durable_path = "durable" :: [] in
  let module Plugin : Protocol_plugin_sig.S = (val plugin) in
  let* path_exists = Plugin.Pvm.Wasm_2_0_0.proof_mem_tree tree durable_path in
  if path_exists then
    (* This fold on the tree rather than on the durable storage representation
       directly. It would probably be safer but the durable storage does not
       implement a folding function yet. *)
    let* instrs =
      Plugin.Pvm.Wasm_2_0_0.proof_fold_tree
        tree
        durable_path
        ~order:`Undefined
        ~init:[]
        ~f:(fun key tree acc ->
          match check_dumpable_path key with
          | `Nothing -> return acc
          | `Value key ->
              let+ instr = set_value_instr ~pvm:(module Plugin.Pvm) key tree in
              instr :: acc)
    in
    return_ok instrs
  else failwith "The durable storage is not available in the tree\n%!"

let dump_durable_storage ~block ~data_dir ~file =
  let open Lwt_result_syntax in
  let* store =
    Store.load
      Tezos_layer2_store.Store_sigs.Read_only
      ~index_buffer_size:0
      ~l2_blocks_cache_size:5
      (Configuration.default_storage_dir data_dir)
  in
  let get name load =
    let* value = load () in
    match value with
    | Some v -> return v
    | None -> failwith "%s not found in the rollup node storage" name
  in
  let hash_from_level l =
    get (Format.asprintf "Block hash for level %ld" l) (fun () ->
        Store.Levels_to_hashes.find store.levels_to_hashes l)
  in
  let block_from_hash h =
    get (Format.asprintf "Block with hash %a" Block_hash.pp h) (fun () ->
        Store.L2_blocks.read store.l2_blocks h)
  in
  let get_l2_head () =
    get "Processed L2 head" (fun () -> Store.L2_head.read store.l2_head)
  in
  let* block_hash, block_level =
    match block with
    | `Genesis -> failwith "Genesis not supported"
    | `Head 0 ->
        let* {header = {block_hash; level; _}; _} = get_l2_head () in
        return (block_hash, level)
    | `Head offset ->
        let* {header = {level; _}; _} = get_l2_head () in
        let l = Int32.(sub level (of_int offset)) in
        let* h = hash_from_level l in
        return (h, l)
    | `Alias (_, _) -> failwith "Alias not supported"
    | `Hash (h, 0) ->
        let* _block, {block_hash; level; _} = block_from_hash h in
        return (block_hash, level)
    | `Hash (h, offset) ->
        let* _block, block_header = block_from_hash h in
        let l = Int32.(sub block_header.level (of_int offset)) in
        let* h = hash_from_level l in
        return (h, l)
    | `Level l ->
        let* h = hash_from_level l in
        return (h, l)
  in
  let* (plugin : (module Protocol_plugin_sig.S)) =
    Protocol_plugins.proto_plugin_for_level_with_store store block_level
  in
  let* l2_header = Store.L2_blocks.header store.l2_blocks block_hash in
  let* l2_header =
    match l2_header with
    | None -> tzfail Rollup_node_errors.Cannot_checkout_l2_header
    | Some header -> return header
  in
  let* context = load_context ~data_dir plugin Store_sigs.Read_only in
  let* state = get_wasm_pvm_state ~l2_header context in
  let* instrs = generate_durable_storage ~plugin state in
  let* () = Installer_config.to_file instrs ~output:file in
  return_unit

let patch_durable_storage ~data_dir ~key ~value =
  let open Lwt_result_syntax in
  (* Loads the state of the head. *)
  let* _lock = Node_context_loader.lock ~data_dir in
  let* store =
    Store.load
      Tezos_layer2_store.Store_sigs.Read_write
      ~index_buffer_size:0
      ~l2_blocks_cache_size:1
      (Configuration.default_storage_dir data_dir)
  in
  let* ({header = {block_hash; level = block_level; _}; _} as l2_block) =
    let* r = Store.L2_head.read store.l2_head in
    match r with
    | Some v -> return v
    | None ->
        failwith "Processed L2 head is not found in the rollup node storage"
  in

  let* ((module Plugin) as plugin) =
    Protocol_plugins.proto_plugin_for_level_with_store store block_level
  in
  let* l2_header = Store.L2_blocks.header store.l2_blocks block_hash in
  let* l2_header =
    match l2_header with
    | None -> tzfail Rollup_node_errors.Cannot_checkout_l2_header
    | Some header -> return header
  in
  let* () =
    fail_when
      (Option.is_some l2_header.commitment_hash)
      (Rollup_node_errors.Patch_durable_storage_on_commitment block_level)
  in
  let* context = load_context ~data_dir plugin Store_sigs.Read_write in
  let* state = get_wasm_pvm_state ~l2_header context in

  (* Patches the state via an unsafe patch. *)
  let* patched_state =
    Plugin.Pvm.Unsafe.apply_patch
      Kind.Wasm_2_0_0
      state
      (Pvm_patches.Patch_durable_storage {key; value})
  in

  (* Replaces the PVM state. *)
  let*! context = Context.PVMState.set context patched_state in
  let*! new_commit = Context.commit context in
  let new_l2_header = {l2_header with context = new_commit} in
  let new_l2_block = {l2_block with header = (); content = ()} in
  let* () =
    Store.L2_blocks.append
      store.l2_blocks
      ~key:new_l2_header.block_hash
      ~header:new_l2_header
      ~value:new_l2_block
  in
  let new_l2_block_with_header = {l2_block with header = new_l2_header} in
  Store.L2_head.write store.l2_head new_l2_block_with_header
