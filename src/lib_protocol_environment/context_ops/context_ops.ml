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

(* Backend-agnostic operations on the context *)

module Environment_context = Tezos_protocol_environment.Context
module Memory_context = Tezos_protocol_environment.Memory_context
module Brassaia = Tezos_context_brassaia.Tezos_context.Context

module Brassaia_memory =
  Tezos_context_brassaia_memory.Tezos_context_memory.Context

module Brassaia_memory_context =
  Tezos_protocol_environment.Brassaia_memory_context

let err_implementation_mismatch =
  Tezos_protocol_environment.err_implementation_mismatch

(** Values of type [index] are used to [checkout] contexts specified by their hash. *)
type index =
  | Disk_index of Context.index
  | Memory_index of Tezos_context_memory.Context.index
  | Brassaia_index of Brassaia.index
  | Brassaia_memory_index of Brassaia_memory.index

open Environment_context

let err_impl_mismatch ~got =
  err_implementation_mismatch
    ~expected:"shell, memory, brassaia or brassaia_memory"
    ~got

let init ~kind ?patch_context ?readonly ?index_log_size s =
  let open Lwt_syntax in
  match kind with
  | `Disk ->
      let patch_context =
        Option.map
          (fun f context ->
            let open Lwt_result_syntax in
            let* context = f (Shell_context.wrap_disk_context context) in
            return @@ Shell_context.unwrap_disk_context context)
          patch_context
      in
      let+ index = Context.init ?patch_context ?readonly ?index_log_size s in
      Disk_index index
  | `Memory ->
      let+ index =
        Tezos_context_memory.Context.init ?readonly ?index_log_size s
      in
      Memory_index index
  | `Brassaia ->
      let patch_context =
        Option.map
          (fun f context ->
            let open Lwt_result_syntax in
            let* context = f (Brassaia_context.wrap_disk_context context) in
            return @@ Brassaia_context.unwrap_disk_context context)
          patch_context
      in
      let+ index = Brassaia.init ?patch_context ?readonly ?index_log_size s in
      Brassaia_index index
  | `Brassaia_memory ->
      let+ index = Brassaia_memory.init ?readonly ?index_log_size s in
      Brassaia_memory_index index

(* Wrapper over init that uses an environment variable ('TEZOS_CONTEXT_BACKEND')
   to select the backend between Memory|Brassaia_memory and Disk|Brassaia *)
let init ~kind =
  let backend_variable = "TEZOS_CONTEXT_BACKEND" in
  match Sys.getenv_opt backend_variable with
  | Some "Brassaia" -> (
      match kind with
      | `Disk -> init ~kind:`Brassaia
      | `Memory -> init ~kind:`Brassaia_memory
      | _ -> init ~kind)
  | _ -> init ~kind

let index (context : Environment_context.t) =
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      Disk_index (Context.index ctxt)
  | Context {kind = Memory_context.Context; ctxt; _} ->
      Memory_index (Tezos_context_memory.Context.index ctxt)
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      Brassaia_index (Brassaia.index ctxt)
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      Brassaia_memory_index (Brassaia_memory.index ctxt)
  | Context t -> err_impl_mismatch ~got:t.impl_name

let mem (context : Environment_context.t) key =
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} -> Context.mem ctxt key
  | Context {kind = Memory_context.Context; ctxt; _} ->
      Tezos_context_memory.Context.mem ctxt key
  | Context {kind = Brassaia_context.Context; ctxt; _} -> Brassaia.mem ctxt key
  | Context t -> err_impl_mismatch ~got:t.impl_name

let mem_tree (context : Environment_context.t) key =
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} -> Context.mem_tree ctxt key
  | Context {kind = Memory_context.Context; ctxt; _} ->
      Tezos_context_memory.Context.mem_tree ctxt key
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      Brassaia.mem_tree ctxt key
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      Brassaia_memory.mem_tree ctxt key
  | Context t -> err_impl_mismatch ~got:t.impl_name

let find (context : Environment_context.t) key =
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} -> Context.find ctxt key
  | Context {kind = Memory_context.Context; ctxt; _} ->
      Tezos_context_memory.Context.find ctxt key
  | Context {kind = Brassaia_context.Context; ctxt; _} -> Brassaia.find ctxt key
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      Brassaia_memory.find ctxt key
  | Context t -> err_impl_mismatch ~got:t.impl_name

let add (context : Environment_context.t) key data =
  let open Lwt_syntax in
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      let+ ctxt = Context.add ctxt key data in
      Shell_context.wrap_disk_context ctxt
  | Context {kind = Memory_context.Context; ctxt; _} ->
      let+ ctxt = Tezos_context_memory.Context.add ctxt key data in
      Memory_context.wrap_memory_context ctxt
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      let+ ctxt = Brassaia.add ctxt key data in
      Brassaia_context.wrap_disk_context ctxt
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      let+ ctxt = Brassaia_memory.add ctxt key data in
      Brassaia_memory_context.wrap_memory_context ctxt
  | Context t -> err_impl_mismatch ~got:t.impl_name

let fold_value ?depth (context : Environment_context.t) key ~order ~init ~f =
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      Context.fold ?depth ctxt key ~order ~init ~f:(fun k tree acc ->
          let v () = Context.Tree.to_value tree in
          f k v acc)
  | Context {kind = Memory_context.Context; ctxt; _} ->
      let open Tezos_context_memory in
      Context.fold ?depth ctxt key ~order ~init ~f:(fun k tree acc ->
          let v () = Context.Tree.to_value tree in
          f k v acc)
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      Brassaia.fold ?depth ctxt key ~order ~init ~f:(fun k tree acc ->
          let v () = Brassaia.Tree.to_value tree in
          f k v acc)
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      Brassaia_memory.fold ?depth ctxt key ~order ~init ~f:(fun k tree acc ->
          let v () = Brassaia_memory.Tree.to_value tree in
          f k v acc)
  | Context t -> err_impl_mismatch ~got:t.impl_name

let add_protocol (context : Environment_context.t) proto_hash =
  let open Lwt_syntax in
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      let+ ctxt = Context.add_protocol ctxt proto_hash in
      Shell_context.wrap_disk_context ctxt
  | Context {kind = Memory_context.Context; ctxt; _} ->
      let+ ctxt = Tezos_context_memory.Context.add_protocol ctxt proto_hash in
      Memory_context.wrap_memory_context ctxt
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      let+ ctxt = Brassaia.add_protocol ctxt proto_hash in
      Brassaia_context.wrap_disk_context ctxt
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      let+ ctxt = Brassaia_memory.add_protocol ctxt proto_hash in
      Brassaia_memory_context.wrap_memory_context ctxt
  | Context t -> err_impl_mismatch ~got:t.impl_name

let get_protocol (context : Environment_context.t) =
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} -> Context.get_protocol ctxt
  | Context {kind = Memory_context.Context; ctxt; _} ->
      Tezos_context_memory.Context.get_protocol ctxt
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      Brassaia.get_protocol ctxt
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      Brassaia_memory.get_protocol ctxt
  | Context t -> err_impl_mismatch ~got:t.impl_name

let add_predecessor_block_metadata_hash (context : Environment_context.t) hash =
  let open Lwt_syntax in
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      let+ ctxt = Context.add_predecessor_block_metadata_hash ctxt hash in
      Shell_context.wrap_disk_context ctxt
  | Context {kind = Memory_context.Context; ctxt; _} ->
      let+ ctxt =
        Tezos_context_memory.Context.add_predecessor_block_metadata_hash
          ctxt
          hash
      in
      Memory_context.wrap_memory_context ctxt
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      let+ ctxt = Brassaia.add_predecessor_block_metadata_hash ctxt hash in
      Brassaia_context.wrap_disk_context ctxt
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      let+ ctxt =
        Brassaia_memory.add_predecessor_block_metadata_hash ctxt hash
      in
      Brassaia_memory_context.wrap_memory_context ctxt
  | Context t -> err_impl_mismatch ~got:t.impl_name

let add_predecessor_ops_metadata_hash (context : Environment_context.t) hash =
  let open Lwt_syntax in
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      let+ ctxt = Context.add_predecessor_ops_metadata_hash ctxt hash in
      Shell_context.wrap_disk_context ctxt
  | Context {kind = Memory_context.Context; ctxt; _} ->
      let+ ctxt =
        Tezos_context_memory.Context.add_predecessor_ops_metadata_hash ctxt hash
      in
      Memory_context.wrap_memory_context ctxt
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      let+ ctxt = Brassaia.add_predecessor_ops_metadata_hash ctxt hash in
      Brassaia_context.wrap_disk_context ctxt
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      let+ ctxt = Brassaia_memory.add_predecessor_ops_metadata_hash ctxt hash in
      Brassaia_memory_context.wrap_memory_context ctxt
  | Context t -> err_impl_mismatch ~got:t.impl_name

let hash ~time ?message (context : Environment_context.t) =
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      Context.hash ~time ?message ctxt
  | Context {kind = Memory_context.Context; ctxt; _} ->
      Tezos_context_memory.Context.hash ~time ?message ctxt
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      Brassaia.hash ~time ?message ctxt
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      Brassaia_memory.hash ~time ?message ctxt
  | Context t -> err_impl_mismatch ~got:t.impl_name

let get_test_chain (context : Environment_context.t) =
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      Context.get_test_chain ctxt
  | Context {kind = Memory_context.Context; _} ->
      Lwt.return Test_chain_status.Not_running
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      Brassaia.get_test_chain ctxt
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      Brassaia_memory.get_test_chain ctxt
  | Context t -> err_impl_mismatch ~got:t.impl_name

let add_test_chain (context : Environment_context.t) status =
  let open Lwt_syntax in
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      let+ ctxt = Context.add_test_chain ctxt status in
      Shell_context.wrap_disk_context ctxt
  | Context {kind = Memory_context.Context; ctxt; _} ->
      let+ ctxt = Tezos_context_memory.Context.add_test_chain ctxt status in
      Memory_context.wrap_memory_context ctxt
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      let+ ctxt = Brassaia.add_test_chain ctxt status in
      Brassaia_context.wrap_disk_context ctxt
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      let+ ctxt = Brassaia_memory.add_test_chain ctxt status in
      Brassaia_memory_context.wrap_memory_context ctxt
  | Context t -> err_impl_mismatch ~got:t.impl_name

let fork_test_chain (context : Environment_context.t) ~protocol ~expiration =
  let open Lwt_syntax in
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      let+ ctxt = Context.fork_test_chain ctxt ~protocol ~expiration in
      Shell_context.wrap_disk_context ctxt
  | Context {kind = Memory_context.Context; ctxt; _} ->
      let+ ctxt =
        Tezos_context_memory.Context.fork_test_chain ctxt ~protocol ~expiration
      in
      Memory_context.wrap_memory_context ctxt
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      let+ ctxt = Brassaia.fork_test_chain ctxt ~protocol ~expiration in
      Brassaia_context.wrap_disk_context ctxt
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      let+ ctxt = Brassaia_memory.fork_test_chain ctxt ~protocol ~expiration in
      Brassaia_memory_context.wrap_memory_context ctxt
  | Context t -> err_impl_mismatch ~got:t.impl_name

let commit ~time ?message (context : Environment_context.t) =
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      Context.commit ~time ?message ctxt
  | Context {kind = Memory_context.Context; ctxt; _} ->
      Tezos_context_memory.Context.commit ~time ?message ctxt
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      Brassaia.commit ~time ?message ctxt
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      Brassaia_memory.commit ~time ?message ctxt
  | Context t -> err_impl_mismatch ~got:t.impl_name

let gc context_index context_hash =
  match context_index with
  | Disk_index index -> Context.gc index context_hash
  | Memory_index index -> Tezos_context_memory.Context.gc index context_hash
  | Brassaia_index index -> Brassaia.gc index context_hash
  | Brassaia_memory_index index -> Brassaia_memory.gc index context_hash

let wait_gc_completion context_index =
  match context_index with
  | Disk_index index -> Context.wait_gc_completion index
  | Memory_index index -> Tezos_context_memory.Context.wait_gc_completion index
  | Brassaia_index index -> Brassaia.wait_gc_completion index
  | Brassaia_memory_index index -> Brassaia_memory.wait_gc_completion index

let is_gc_allowed context_index =
  match context_index with
  | Disk_index index -> Context.is_gc_allowed index
  | Memory_index index -> Tezos_context_memory.Context.is_gc_allowed index
  | Brassaia_index index -> Brassaia.is_gc_allowed index
  | Brassaia_memory_index index -> Brassaia_memory.is_gc_allowed index

let split context_index =
  match context_index with
  | Disk_index index -> Context.split index
  | Memory_index index -> Tezos_context_memory.Context.split index
  | Brassaia_index index -> Brassaia.split index
  | Brassaia_memory_index index -> Brassaia_memory.split index

let sync = function
  | Disk_index index -> Context.sync index
  | Memory_index index -> Tezos_context_memory.Context.sync index
  | Brassaia_index index -> Brassaia.sync index
  | Brassaia_memory_index index -> Brassaia_memory.sync index

let commit_test_chain_genesis (context : Environment_context.t) block_header =
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      Context.commit_test_chain_genesis ctxt block_header
  | Context {kind = Memory_context.Context; ctxt; _} ->
      Tezos_context_memory.Context.commit_test_chain_genesis ctxt block_header
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      Brassaia.commit_test_chain_genesis ctxt block_header
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      Brassaia_memory.commit_test_chain_genesis ctxt block_header
  | Context t -> err_impl_mismatch ~got:t.impl_name

let compute_testchain_genesis (context : Environment_context.t) block_hash =
  match context with
  | Context {kind = Shell_context.Context; _} ->
      Context.compute_testchain_genesis block_hash
  | Context {kind = Memory_context.Context; _} ->
      Tezos_context_memory.Context.compute_testchain_genesis block_hash
  | Context {kind = Brassaia_context.Context; _} ->
      Brassaia.compute_testchain_genesis block_hash
  | Context {kind = Brassaia_memory_context.Context; _} ->
      Brassaia_memory.compute_testchain_genesis block_hash
  | Context t -> err_impl_mismatch ~got:t.impl_name

let merkle_tree (context : Environment_context.t) leaf_kind path =
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      Context.merkle_tree ctxt leaf_kind path
  | Context {kind = Memory_context.Context; ctxt; _} ->
      Tezos_context_memory.Context.merkle_tree ctxt leaf_kind path
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      Brassaia.merkle_tree ctxt leaf_kind path
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      Brassaia_memory.merkle_tree ctxt leaf_kind path
  | Context t -> err_impl_mismatch ~got:t.impl_name

let merkle_tree_v2 (context : Environment_context.t) leaf_kind path =
  match context with
  | Context {kind = Shell_context.Context; ctxt; _} ->
      Context.merkle_tree_v2 ctxt leaf_kind path
  | Context {kind = Memory_context.Context; ctxt; _} ->
      Tezos_context_memory.Context.merkle_tree_v2 ctxt leaf_kind path
  | Context {kind = Brassaia_context.Context; ctxt; _} ->
      Brassaia.merkle_tree_v2 ctxt leaf_kind path
  | Context {kind = Brassaia_memory_context.Context; ctxt; _} ->
      Brassaia_memory.merkle_tree_v2 ctxt leaf_kind path
  | Context t -> err_impl_mismatch ~got:t.impl_name

let commit_genesis context_index ~chain_id ~time ~protocol =
  match context_index with
  | Disk_index index -> Context.commit_genesis index ~chain_id ~time ~protocol
  | Memory_index index ->
      Tezos_context_memory.Context.commit_genesis
        index
        ~chain_id
        ~time
        ~protocol
  | Brassaia_index index ->
      Brassaia.commit_genesis index ~chain_id ~time ~protocol
  | Brassaia_memory_index index ->
      Brassaia_memory.commit_genesis index ~chain_id ~time ~protocol

let checkout context_index context_hash =
  let open Lwt_syntax in
  match context_index with
  | Disk_index index ->
      let+ ctxt = Context.checkout index context_hash in
      Option.map Shell_context.wrap_disk_context ctxt
  | Memory_index index ->
      let+ ctxt = Tezos_context_memory.Context.checkout index context_hash in
      Option.map Memory_context.wrap_memory_context ctxt
  | Brassaia_index index ->
      let+ ctxt = Brassaia.checkout index context_hash in
      Option.map Brassaia_context.wrap_disk_context ctxt
  | Brassaia_memory_index index ->
      let+ ctxt = Brassaia_memory.checkout index context_hash in
      Option.map Brassaia_memory_context.wrap_memory_context ctxt

let checkout_exn context_index context_hash =
  let open Lwt_syntax in
  match context_index with
  | Disk_index index ->
      let+ ctxt = Context.checkout_exn index context_hash in
      Shell_context.wrap_disk_context ctxt
  | Memory_index index ->
      let+ ctxt =
        Tezos_context_memory.Context.checkout_exn index context_hash
      in
      Memory_context.wrap_memory_context ctxt
  | Brassaia_index index ->
      let+ ctxt = Brassaia.checkout_exn index context_hash in
      Brassaia_context.wrap_disk_context ctxt
  | Brassaia_memory_index index ->
      let+ ctxt = Brassaia_memory.checkout_exn index context_hash in
      Brassaia_memory_context.wrap_memory_context ctxt

let exists context_index context_hash =
  match context_index with
  | Disk_index index -> Context.exists index context_hash
  | Memory_index index -> Tezos_context_memory.Context.exists index context_hash
  | Brassaia_index index -> Brassaia.exists index context_hash
  | Brassaia_memory_index index -> Brassaia_memory.exists index context_hash

let close context_index =
  match context_index with
  | Disk_index index -> Context.close index
  | Memory_index index -> Tezos_context_memory.Context.close index
  | Brassaia_index index -> Brassaia.close index
  | Brassaia_memory_index index -> Brassaia_memory.close index

let compute_testchain_chain_id (context : Environment_context.t) block_hash =
  match context with
  | Context {kind = Shell_context.Context; _} ->
      Context.compute_testchain_chain_id block_hash
  | Context {kind = Memory_context.Context; _} ->
      Tezos_context_memory.Context.compute_testchain_chain_id block_hash
  | Context {kind = Brassaia_context.Context; _} ->
      Brassaia.compute_testchain_chain_id block_hash
  | Context {kind = Brassaia_memory_context.Context; _} ->
      Brassaia_memory.compute_testchain_chain_id block_hash
  | Context t -> err_impl_mismatch ~got:t.impl_name
