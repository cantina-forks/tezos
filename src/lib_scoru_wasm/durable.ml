(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 TriliTech <contact@trili.tech>                         *)
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

module T = Tree_encoding.Wrapped
module Runner = Tree_encoding.Runner.Make (Tree_encoding.Wrapped)
module E = Tree_encoding

type t = T.tree

exception Invalid_key of string

exception Not_found

let encoding = E.wrapped_tree

let of_tree = T.select

let to_tree = T.wrap

type key = string list

(* A key is bounded to 250 bytes, including the implicit '/durable' prefix.
   Additionally, values are implicitly appended with '_'. **)
let max_prefix_key_length = 250 - String.length "/durable" - String.length "/_"

let key_of_string_exn s =
  if String.length s > max_prefix_key_length then raise (Invalid_key s) ;
  let key =
    match String.split '/' s with
    | "" :: tl -> tl (* Must start with '/' *)
    | _ -> raise (Invalid_key s)
  in
  let assert_valid_char = function
    | '.' | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> ()
    | _ -> raise (Invalid_key s)
  in
  let all_steps_valid =
    List.for_all (fun x ->
        x <> ""
        &&
        (String.iter assert_valid_char x ;
         true))
  in
  if all_steps_valid key then key else raise (Invalid_key s)

(** We append all values with '_', which is an invalid key-character w.r.t.
    external use.

    This ensures that an external user is prevented from accidentally writing a
    value to a place which is part of another value (e.g. writing a
    chunked_byte_vector to "/a/length", where "/a/length" previously existed as
    part of another chunked_byte_vector encoding.)
*)
let to_value_key k = List.append k ["_"]

let find_value tree key =
  let open Lwt.Syntax in
  let* opt = T.find_tree tree @@ to_value_key key in
  match opt with
  | None -> Lwt.return_none
  | Some subtree ->
      let+ value = Runner.decode E.chunked_byte_vector subtree in
      Some value

let find_value_exn tree key =
  let open Lwt.Syntax in
  let* opt = T.find_tree tree @@ to_value_key key in
  match opt with
  | None -> raise Not_found
  | Some subtree -> Runner.decode E.chunked_byte_vector subtree
