(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2021-2023 Nomadic Labs <contact@nomadic-labs.com>           *)
(* Copyright (c) 2022-2023 Trili Tech <contact@trili.tech>                   *)
(* Copyright (c) 2023 Marigold <contact@marigold.dev>                        *)
(*                                                                           *)
(*****************************************************************************)

open Manifest
open Externals

include Product (struct
  let name = "tooling"

  let source = ["src"; "devtools"]
end)

let _octez_tooling =
  public_lib
    "tezos-tooling"
    ~path:"src/tooling"
    ~synopsis:"Tezos: tooling for the project"
    ~modules:[]
    ~opam_only_deps:
      [
        bisect_ppx;
        (* These next are only used in the CI, we add this dependency so that
           it is added to images/ci. *)
        ocamlformat;
      ]
    ~npm_deps:
      [
        Npm.make "kaitai-struct" (Version (V.exactly "0.10.0"))
        (* Client-libs project requires Javascript Kaitai runtime. *);
      ]

let _node_wrapper =
  private_exe
    "node_wrapper"
    ~path:"src/tooling"
    ~opam:""
    ~deps:[unix]
    ~modules:["node_wrapper"]
    ~bisect_ppx:No

let _git_gas_diff =
  public_exe
    "git-gas-diff"
    ~path:"devtools/git-gas-diff/bin"
    ~release_status:Unreleased
    ~internal_name:"main"
    ~opam:"tezos-tooling"
    ~deps:[external_lib "num" V.True; re]
    ~static:false
    ~bisect_ppx:No

let _gas_parameter_diff =
  public_exe
    "gas_parameter_diff"
    ~path:"devtools/gas_parameter_diff/bin"
    ~release_status:Unreleased
    ~internal_name:"main"
    ~opam:"tezos-tooling"
    ~deps:[]
    ~static:false
    ~bisect_ppx:No

let _benchmark_tools_purge_disk_cache =
  public_exe
    "purge_disk_cache"
    ~path:"devtools/benchmarks-tools/purge_disk_cache"
    ~internal_name:"purge_disk_cache"
    ~opam:"tezos-tooling"
    ~release_status:Unreleased
    ~deps:[]
    ~static:false
    ~bisect_ppx:No
