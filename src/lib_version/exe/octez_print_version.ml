(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020-2024 Nomadic Labs, <contact@nomadic-labs.com>          *)
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

(* this is a script run at build time to print out the current version of the
   node *)

open Version
open Current_git_info

let help_string =
  "This script prints out the current version of the\n\
   octez node as it is deduced from the git tag of the current branch.\n\
   print_version \
   [--product|--major|--minor|--additional-info|--full|--full-with-commit|--commit]"

let () =
  match Sys.argv with
  | [|_; "--product"|] ->
      print_endline (string_of_product octez_version.product)
  | [|_; "--major"|] -> print_endline (string_of_int octez_version.major)
  | [|_; "--minor"|] -> print_endline (string_of_int octez_version.minor)
  | [|_; "--additional-info"|] ->
      print_endline (string_of_additional_info octez_version.additional_info)
  | [|_; "--full"|] | [|_|] -> print_endline (to_string octez_version)
  | [|_; "--full-with-commit"|] ->
      print_endline Tezos_version_value.Bin_version.octez_simple_version_string
  | [|_; "--commit"|] ->
      print_endline Tezos_version_value.Current_git_info.abbreviated_commit_hash
  | [|_; "--json"|] ->
      print_endline
        (to_json
           octez_version
           Tezos_version_value.Current_git_info.abbreviated_commit_hash)
  | [|_; "--help"|] -> print_endline help_string
  | _ ->
      print_endline help_string ;
      prerr_endline
        ("invalid argument: " ^ String.concat " " (Array.to_list Sys.argv)) ;
      exit 1
