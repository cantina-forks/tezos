(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs. <contact@nomadic-labs.com>               *)
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

let raise e = raise (Read_error e)

type slice = {name: string; value: bytes; pretty_printed: string}

type state = {
  buffer: bytes;
  mutable offset: int;
  mutable remaining_bytes: int;
  mutable allowed_bytes: int option;
  mutable slices: slice list;
}

let check_allowed_bytes state size =
  match state.allowed_bytes with
  | Some len when len < size -> raise Size_limit_exceeded
  | Some len -> Some (len - size)
  | None -> None

let check_remaining_bytes state size =
  if state.remaining_bytes < size then raise Not_enough_data;
  state.remaining_bytes - size

let read_atom ?(pp = fun _ -> "") size conv name state =
  let offset = state.offset in
  state.remaining_bytes <- check_remaining_bytes state size;
  state.allowed_bytes <- check_allowed_bytes state size;
  state.offset <- state.offset + size;
  let value = Bytes.sub state.buffer offset size in
  let result = conv state.buffer offset in
  state.slices <- {name; value; pretty_printed = pp result} :: state.slices;
  result

(** Reader for all the atomic types. *)
module Atom = struct
  let read_byte state =
    let size = Binary_size.int8 in
    let offset = state.offset in
    state.remaining_bytes <- check_remaining_bytes state size;
    state.allowed_bytes <- check_allowed_bytes state size;
    state.offset <- state.offset + size;
    Bytes.get_int8 state.buffer offset

  let uint8 = read_atom ~pp:string_of_int Binary_size.uint8 TzEndian.get_uint8

  let uint16 = read_atom ~pp:string_of_int Binary_size.int16 TzEndian.get_uint16

  let int8 = read_atom ~pp:string_of_int Binary_size.int8 TzEndian.get_int8

  let int16 = read_atom ~pp:string_of_int Binary_size.int16 TzEndian.get_int16

  let int32 = read_atom ~pp:Int32.to_string Binary_size.int32 TzEndian.get_int32

  let int64 = read_atom ~pp:Int64.to_string Binary_size.int64 TzEndian.get_int64

  let float =
    read_atom ~pp:string_of_float Binary_size.float TzEndian.get_double

  let bool state name =
    read_atom
      ~pp:(fun x -> string_of_bool (x <> 0))
      Binary_size.int8
      TzEndian.get_int8
      state
      name
    <> 0

  let uint30 =
    read_atom ~pp:string_of_int Binary_size.uint30 @@ fun buffer ofs ->
    let v = Int32.to_int (TzEndian.get_int32 buffer ofs) in
    if v < 0 then raise (Invalid_int {min = 0; v; max = (1 lsl 30) - 1});
    v

  let int31 =
    read_atom ~pp:string_of_int Binary_size.int31 @@ fun buffer ofs ->
    Int32.to_int (TzEndian.get_int32 buffer ofs)

  let int = function
    | `Int31 -> int31
    | `Int16 -> int16
    | `Int8 -> int8
    | `Uint30 -> uint30
    | `Uint16 -> uint16
    | `Uint8 -> uint8

  let ranged_int ~minimum ~maximum name state =
    let read_int =
      match Binary_size.range_to_size ~minimum ~maximum with
      | `Int8 -> int8
      | `Int16 -> int16
      | `Int31 -> int31
      | `Uint8 -> uint8
      | `Uint16 -> uint16
      | `Uint30 -> uint30
    in
    let ranged = read_int name state in
    let ranged = if minimum > 0 then ranged + minimum else ranged in
    if not (minimum <= ranged && ranged <= maximum) then
      raise (Invalid_int {min = minimum; v = ranged; max = maximum});
    ranged

  let ranged_float ~minimum ~maximum name state =
    let ranged = float name state in
    if not (minimum <= ranged && ranged <= maximum) then
      raise (Invalid_float {min = minimum; v = ranged; max = maximum});
    ranged

  let rec read_z res value bit_in_value name state initial_offset =
    let byte = read_byte state in
    let value = value lor ((byte land 0x7F) lsl bit_in_value) in
    let bit_in_value = bit_in_value + 7 in
    let (bit_in_value, value) =
      if bit_in_value < 8 then (bit_in_value, value)
      else (
        Buffer.add_char res (Char.unsafe_chr (value land 0xFF));
        (bit_in_value - 8, value lsr 8) )
    in
    if byte land 0x80 = 0x80 then
      read_z res value bit_in_value name state initial_offset
    else (
      if bit_in_value > 0 then Buffer.add_char res (Char.unsafe_chr value);
      if byte = 0x00 then raise Trailing_zero;
      let result = Z.of_bits (Buffer.contents res) in
      let pretty_printed = Z.to_string result in
      let value =
        Bytes.sub state.buffer initial_offset (state.offset - initial_offset)
      in
      state.slices <- {name; value; pretty_printed} :: state.slices;
      result )

  let n name state =
    let initial_offset = state.offset in
    let first = read_byte state in

    let first_value = first land 0x7F in
    if first land 0x80 = 0x80 then
      read_z (Buffer.create 100) first_value 7 name state initial_offset
    else
      let result = Z.of_int first_value in
      let pretty_printed = Z.to_string result in
      let value =
        Bytes.sub state.buffer initial_offset (state.offset - initial_offset)
      in
      state.slices <- {name; value; pretty_printed} :: state.slices;
      result

  let z name state =
    let initial_offset = state.offset in
    let first = read_byte state in

    let first_value = first land 0x3F in
    let sign = first land 0x40 <> 0 in
    if first land 0x80 = 0x80 then
      let n =
        read_z (Buffer.create 100) first_value 6 name state initial_offset
      in
      if sign then Z.neg n else n
    else
      let n = Z.of_int first_value in
      if sign then Z.neg n else n

  let string_enum arr name state =
    let read_index =
      match Binary_size.enum_size arr with
      | `Uint8 -> uint8
      | `Uint16 -> uint16
      | `Uint30 -> uint30
    in
    let index = read_index name state in
    if index >= Array.length arr then raise No_case_matched;
    arr.(index)

  let fixed_length_bytes length =
    read_atom length @@ fun buf ofs -> Bytes.sub buf ofs length

  let fixed_length_string length =
    read_atom ~pp:(Format.sprintf "%S") length @@ fun buf ofs ->
    Bytes.sub_string buf ofs length

  let tag = function `Uint8 -> uint8 | `Uint16 -> uint16
end

(** Main recursive reading function, in continuation passing style. *)
let rec read_rec : type ret. ret Encoding.t -> ?name:string -> state -> ret =
 fun e ?name state ->
  let ( !! ) x = match name with
    | None -> x
    | Some name -> Format.sprintf "%S (%s)" name x
  in
  let open Encoding in
  match e.encoding with
  | Null -> ()
  | Empty -> ()
  | Constant _ -> ()
  | Ignore -> ()
  | Bool -> Atom.bool !!"bool" state
  | Int8 -> Atom.int8 !!"int8" state
  | Uint8 -> Atom.uint8 !!"uint8" state
  | Int16 -> Atom.int16 !!"int16" state
  | Uint16 -> Atom.uint16 !!"uint16" state
  | Int31 -> Atom.int31 !!"int31" state
  | Int32 -> Atom.int32 !!"int32" state
  | Int64 -> Atom.int64 !!"int64" state
  | N -> Atom.n !!"N" state
  | Z -> Atom.z !!"Z" state
  | Float -> Atom.float !!"float" state
  | Bytes (`Fixed n) -> Atom.fixed_length_bytes n !!"bytes" state
  | Bytes `Variable ->
      Atom.fixed_length_bytes state.remaining_bytes !!"bytes" state
  | String (`Fixed n) -> Atom.fixed_length_string n !!"string" state
  | String `Variable ->
      Atom.fixed_length_string state.remaining_bytes !!"string" state
  | Padded (e, n) ->
      let v = read_rec e ?name state in
      ignore (Atom.fixed_length_string n "padding" state : string);
      v
  | RangedInt {minimum; maximum} ->
      Atom.ranged_int ~minimum ~maximum !!"ranged int" state
  | RangedFloat {minimum; maximum} ->
      Atom.ranged_float ~minimum ~maximum !!"ranged float" state
  | String_enum (_, arr) -> Atom.string_enum arr !!"enum" state
  | Array (max_length, e) ->
      let max_length = match max_length with Some l -> l | None -> max_int in
      let l = read_list List_too_long max_length e ?name state in
      Array.of_list l
  | List (max_length, e) ->
      let max_length = match max_length with Some l -> l | None -> max_int in
      read_list Array_too_long max_length e ?name state
  | Obj (Req {encoding = e; name; _}) -> read_rec e ~name state
  | Obj (Dft {encoding = e; name; _}) -> read_rec e ~name state
  | Obj (Opt {kind = `Dynamic; encoding = e; name; _}) ->
      let present = Atom.bool (name ^ " presence flag") state in
      if not present then None else Some (read_rec e ~name:(!!name) state)
  | Obj (Opt {kind = `Variable; encoding = e; name; _}) ->
      if state.remaining_bytes = 0 then None else Some (read_rec e ~name:(!!name) state)
  | Objs {kind = `Fixed sz; left; right} ->
      ignore (check_remaining_bytes state sz : int);
      ignore (check_allowed_bytes state sz : int option);
      let left = read_rec left ?name state in
      let right = read_rec right ?name state in
      (left, right)
  | Objs {kind = `Dynamic; left; right} ->
      let left = read_rec left ?name state in
      let right = read_rec right ?name state in
      (left, right)
  | Objs {kind = `Variable; left; right} ->
      read_variable_pair left right ?name state
  | Tup e -> read_rec e ?name state
  | Tups {kind = `Fixed sz; left; right} ->
      ignore (check_remaining_bytes state sz : int);
      ignore (check_allowed_bytes state sz : int option);
      let left = read_rec left ?name state in
      let right = read_rec right ?name state in
      (left, right)
  | Tups {kind = `Dynamic; left; right} ->
      let left = read_rec left ?name state in
      let right = read_rec right ?name state in
      (left, right)
  | Tups {kind = `Variable; left; right} ->
      read_variable_pair left right ?name state
  | Conv {inj; encoding; _} -> inj (read_rec encoding ?name state)
  | Union {tag_size; cases; _} ->
      let ctag = Atom.tag tag_size "DUMMY" state in
      let (Case {encoding; inj; _}) =
        try
          List.find
            (function
              | Case {tag = tg; title; _} ->
                  if Uint_option.is_some tg && Uint_option.get tg = ctag then (
                    let {value; pretty_printed; _} = List.hd state.slices in
                    state.slices <-
                      {name = title ^ " tag"; value; pretty_printed}
                      :: List.tl state.slices;
                    true )
                  else false)
            cases
        with Not_found -> raise (Unexpected_tag ctag)
      in
      inj (read_rec encoding ?name state)
  | Dynamic_size {kind; encoding = e} ->
      let sz = Atom.int kind "dynamic length" state in
      let remaining = check_remaining_bytes state sz in
      state.remaining_bytes <- sz;
      ignore (check_allowed_bytes state sz : int option);
      let v = read_rec e ?name state in
      if state.remaining_bytes <> 0 then raise Extra_bytes;
      state.remaining_bytes <- remaining;
      v
  | Check_size {limit; encoding = e} ->
      let old_allowed_bytes = state.allowed_bytes in
      let limit =
        match state.allowed_bytes with
        | None -> limit
        | Some current_limit -> min current_limit limit
      in
      state.allowed_bytes <- Some limit;
      let v = read_rec e ?name state in
      let allowed_bytes =
        match old_allowed_bytes with
        | None -> None
        | Some old_limit ->
            let remaining =
              match state.allowed_bytes with
              | None -> assert false
              | Some remaining -> remaining
            in
            let read = limit - remaining in
            Some (old_limit - read)
      in
      state.allowed_bytes <- allowed_bytes;
      v
  | Describe {encoding = e; id; _} -> read_rec e ~name:(!!id) state
  | Splitted {encoding = e; _} -> read_rec e ?name state
  | Mu {fix; name; _} -> read_rec (fix e) ~name:(!!name) state
  | Delayed f -> read_rec (f ()) ?name state

and read_variable_pair :
    type left right.
    left Encoding.t -> right Encoding.t -> ?name:string -> state -> left * right =
 fun e1 e2 ?name state ->
  match (Encoding.classify e1, Encoding.classify e2) with
  | ((`Dynamic | `Fixed _), `Variable) ->
      let left = read_rec e1 ?name state in
      let right = read_rec e2 ?name state in
      (left, right)
  | (`Variable, `Fixed n) ->
      if n > state.remaining_bytes then raise Not_enough_data;
      state.remaining_bytes <- state.remaining_bytes - n;
      let left = read_rec e1 ?name state in
      assert (state.remaining_bytes = 0);
      state.remaining_bytes <- n;
      let right = read_rec e2 ?name state in
      assert (state.remaining_bytes = 0);
      (left, right)
  | _ -> assert false

(* Should be rejected by [Encoding.Kind.combine] *)
and read_list :
    type a. read_error -> int -> a Encoding.t -> ?name:string -> state -> a list =
 fun error max_length e ?name state ->
  let rec loop max_length acc =
    if state.remaining_bytes = 0 then List.rev acc
    else if max_length = 0 then raise error
    else
      let name = Option.map (fun name -> name ^ " element") name in
      let v = read_rec e ?name state in
      loop (max_length - 1) (v :: acc)
  in
  loop max_length []

(** ******************** *)

(** Various entry points *)

let slice encoding buffer ofs len =
  let state =
    {
      buffer;
      offset = ofs;
      slices = [];
      remaining_bytes = len;
      allowed_bytes = None;
    }
  in
  match read_rec encoding state with
  | exception Read_error _ -> None
  | _ -> Some (List.rev state.slices)

let slice_bytes_exn encoding buffer =
  let len = Bytes.length buffer in
  let state =
    {
      buffer;
      offset = 0;
      slices = [];
      remaining_bytes = len;
      allowed_bytes = None;
    }
  in
  let _ = read_rec encoding state in
  if state.offset <> len then raise Extra_bytes;
  List.rev state.slices

let slice_bytes encoding buffer =
  try Some (slice_bytes_exn encoding buffer) with Read_error _ -> None
