(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
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

open Binary_error_types

let fixed_length e =
  match Encoding.classify e with
  | `Fixed n -> Some n
  | `Dynamic | `Variable -> None

let n_length = Encoding.n_length

let z_length = Encoding.z_length

let rec length : type x. x Encoding.t -> x -> int =
 fun e value ->
  let open Encoding in
  match e.encoding with
  (* Fixed *)
  | Null -> 0
  | Empty -> 0
  | Constant _ -> 0
  | Bool -> Binary_size.bool
  | Int8 -> Binary_size.int8
  | Uint8 -> Binary_size.uint8
  | Int16 -> Binary_size.int16
  | Uint16 -> Binary_size.uint16
  | Int31 -> Binary_size.int31
  | Int32 -> Binary_size.int32
  | Int64 -> Binary_size.int64
  | N -> n_length value
  | Z -> z_length value
  | RangedInt {minimum; maximum} ->
      Binary_size.integer_to_size @@ Binary_size.range_to_size ~minimum ~maximum
  | Float -> Binary_size.float
  | RangedFloat _ -> Binary_size.float
  | Bytes (`Fixed n, _) -> n
  | String (`Fixed n, _) -> n
  | Padded (e, n) -> length e value + n
  | String_enum (_, arr) ->
      Binary_size.integer_to_size @@ Binary_size.enum_size arr
  | Objs {kind = `Fixed n; _} -> n
  | Tups {kind = `Fixed n; _} -> n
  | Union {kind = `Fixed n; _} -> n
  (* Dynamic *)
  | Objs {kind = `Dynamic; left; right} ->
      let v1, v2 = value in
      length left v1 + length right v2
  | Tups {kind = `Dynamic; left; right} ->
      let v1, v2 = value in
      length left v1 + length right v2
  | Mu {kind = `Dynamic; fix; _} -> length (fix e) value
  | Obj (Opt {kind = `Dynamic; encoding = e; _}) -> (
      match value with None -> 1 | Some value -> 1 + length e value)
  (* Variable *)
  | Ignore -> 0
  | Bytes (`Variable, _) -> Bytes.length value
  | String (`Variable, _) -> String.length value
  | Array {length_limit; elts} -> (
      (match length_limit with
      | No_limit -> ()
      | At_most max_length ->
          if Array.length value > max_length then
            raise (Write_error Array_invalid_length)
      | Exactly exact_length ->
          if Array.length value <> exact_length then
            raise (Write_error Array_invalid_length)) ;
      match fixed_length elts with
      | Some s -> Array.length value * s
      | None -> Array.fold_left (fun acc v -> length elts v + acc) 0 value)
  | List {length_limit; elts} -> (
      (match length_limit with
      | No_limit -> ()
      | At_most max_length ->
          if List.compare_length_with value max_length > 0 then
            raise (Write_error List_invalid_length)
      | Exactly exact_length ->
          if List.compare_length_with value exact_length <> 0 then
            raise (Write_error List_invalid_length)) ;
      match fixed_length elts with
      | Some s -> List.length value * s
      | None -> List.fold_left (fun acc v -> length elts v + acc) 0 value)
  | Objs {kind = `Variable; left; right} ->
      let v1, v2 = value in
      length left v1 + length right v2
  | Tups {kind = `Variable; left; right} ->
      let v1, v2 = value in
      length left v1 + length right v2
  | Obj (Opt {kind = `Variable; encoding = e; _}) -> (
      match value with None -> 0 | Some value -> length e value)
  | Mu {kind = `Variable; fix; _} -> length (fix e) value
  (* Variable or Dynamic we don't care for those constructors *)
  | Union {kind = `Dynamic | `Variable; tag_size; match_case; _} ->
      let (Matched (tag, e, value)) = match_case value in
      assert (tag <= Binary_size.max_int tag_size) ;
      Binary_size.tag_size tag_size + length e value
  (* Recursive*)
  | Obj (Req {encoding = e; _}) -> length e value
  | Obj (Dft {encoding = e; _}) -> length e value
  | Tup e -> length e value
  | Conv {encoding = e; proj; _} -> length e (proj value)
  | Describe {encoding = e; _} -> length e value
  | Splitted {encoding = e; _} -> length e value
  | Dynamic_size {kind; encoding = e} ->
      let length = length e value in
      if length > Binary_size.max_int kind then
        raise (Write_error Size_limit_exceeded) ;
      Binary_size.integer_to_size kind + length
  | Check_size {limit; encoding = e} ->
      let length = length e value in
      if length > limit then raise (Write_error Size_limit_exceeded) ;
      length
  | Delayed f -> length (f ()) value

let ( let* ) = Option.bind

let rec maximum_length : type a. a Encoding.t -> int option =
 fun e ->
  let open Encoding in
  match e.encoding with
  (* Fixed *)
  | Null -> Some 0
  | Empty -> Some 0
  | Constant _ -> Some 0
  | Bool -> Some Binary_size.bool
  | Int8 -> Some Binary_size.int8
  | Uint8 -> Some Binary_size.uint8
  | Int16 -> Some Binary_size.int16
  | Uint16 -> Some Binary_size.uint16
  | Int31 -> Some Binary_size.int31
  | Int32 -> Some Binary_size.int32
  | Int64 -> Some Binary_size.int64
  | N -> None
  | Z -> None
  | RangedInt {minimum; maximum} ->
      Some
        (Binary_size.integer_to_size
        @@ Binary_size.range_to_size ~minimum ~maximum)
  | Float -> Some Binary_size.float
  | RangedFloat _ -> Some Binary_size.float
  | Bytes (`Fixed n, _) -> Some n
  | String (`Fixed n, _) -> Some n
  | Padded (e, n) ->
      let* s = maximum_length e in
      Some (s + n)
  | String_enum (_, arr) ->
      Some (Binary_size.integer_to_size @@ Binary_size.enum_size arr)
  | Objs {kind = `Fixed n; _} -> Some n
  | Tups {kind = `Fixed n; _} -> Some n
  | Union {kind = `Fixed n; _} -> Some n
  (* Dynamic *)
  | Obj (Opt {kind = `Dynamic; encoding = e; _}) ->
      let* s = maximum_length e in
      Some (s + Binary_size.uint8)
  (* Variable *)
  | Ignore -> Some 0
  | Bytes (`Variable, _) -> None
  | String (`Variable, _) -> None
  | Array {length_limit; elts = e} -> (
      match length_limit with
      | No_limit -> None
      | At_most max_length ->
          let* s = maximum_length e in
          Some (s * max_length)
      | Exactly exact_length ->
          let* s = maximum_length e in
          Some (s * exact_length))
  | List {length_limit; elts = e} -> (
      match length_limit with
      | No_limit -> None
      | At_most max_length ->
          let* s = maximum_length e in
          Some (s * max_length)
      | Exactly exact_length ->
          let* s = maximum_length e in
          Some (s * exact_length))
  | Obj (Opt {kind = `Variable; encoding = e; _}) -> maximum_length e
  (* Variable or Dynamic we don't care for those constructors *)
  | Union {kind = `Dynamic | `Variable; tag_size; cases; _} ->
      let* s =
        List.fold_left
          (fun acc (Case {encoding = e; _}) ->
            let* acc = acc in
            let* s = maximum_length e in
            Some (Stdlib.max acc s))
          (Some 0)
          cases
      in
      Some (s + Binary_size.tag_size tag_size)
  | Objs {kind = `Dynamic | `Variable; left; right} ->
      let* l = maximum_length left in
      let* r = maximum_length right in
      Some (l + r)
  | Tups {kind = `Dynamic | `Variable; left; right} ->
      let* l = maximum_length left in
      let* r = maximum_length right in
      Some (l + r)
  | Mu _ ->
      (* There could be bounded-size uses of Mu but it's unreasonable to expect
         to detect them statically this way. Use `check_size` around the mu to
         translate user-invariants into static encoding invariants *)
      None
  (* Recursive*)
  | Obj (Req {encoding = e; _}) -> maximum_length e
  | Obj (Dft {encoding = e; _}) -> maximum_length e
  | Tup e -> maximum_length e
  | Conv {encoding = e; _} -> maximum_length e
  | Describe {encoding = e; _} -> maximum_length e
  | Splitted {encoding = e; _} -> maximum_length e
  | Dynamic_size {kind; encoding = e} ->
      (* NOTE: technically the [kind] limits the range of possible sizes for the
         payload and so bounds the overall maximum size even if the payload has
         no limit.
         But in practice we end up returning 4+max_int31 a lot and it makes the
         function brittle on 32bit machines. *)
      let* inner_maximum_length = maximum_length e in
      let inner_maximum_length =
        (* the size may be restricted by the size's size
           E.g., if [kind] is [`Uint8], the payload's size cannot be more than
           256. *)
        min inner_maximum_length (Binary_size.max_int kind)
      in
      Some (Binary_size.integer_to_size kind + inner_maximum_length)
  | Check_size {limit; encoding = e} -> (
      (* NOTE: it is possible that the statically-provable maximum size exceeds
         the dynamically checked limit. But the difference might be explained by
         subtle invariants that do not appear in the encoding. *)
      match maximum_length e with
      | Some s -> Some (min s limit)
      | None -> Some limit)
  | Delayed f -> maximum_length (f ())
