(*
 * Copyright (c) 2018-2022 Tarides <contact@tarides.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

(** The [brassaia-pack-unix] package provides an implementation of {!Brassaia_pack}
    for Unix systems.

    [brassaia-pack-unix] provides advanced features such as garbage collection,
    snapshoting, integrity checks. *)

(** {1 Store} *)

module type S = Store.S

module Maker (Config : Brassaia_pack.Conf.S) : Store.Maker
module KV (Config : Brassaia_pack.Conf.S) : Store.KV

(** {1 Key and Values} *)

(* module Pack_store = Pack_store *)
module Pack_key = Pack_key
module Pack_value = Pack_value

(** {1 Integrity Checks} *)

module Checks = Checks

(** {1 Statistics} *)

module Stats = Stats

(** {1 Internal Functors and Utilities} *)

(** Following functors and modules are instantiated automatically or used
    internally when creating a store with {!Maker} or {!KV}.*)

module Index = Pack_index
module Inode = Inode
module Pack_store = Pack_store
module Io_legacy = Io_legacy
module Atomic_write = Atomic_write
module Dict = Dict
module Dispatcher = Dispatcher
module Io = Io
module Async = Async
module Errors = Errors
module Io_errors = Io_errors
module Control_file = Control_file
module Append_only_file = Append_only_file
module Chunked_suffix = Chunked_suffix
module Ranges = Ranges
module Sparse_file = Sparse_file
module File_manager = File_manager
module Lower = Lower
module Utils = Utils
module Lru = Lru
