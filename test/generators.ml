(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

let char = Crowbar.map [Crowbar.uint8] Char.chr

let int31 : int Crowbar.gen =
  let open Crowbar in
  map [int32] (fun i32 ->
      let i = Int32.to_int i32 in
      guard (-(1 lsl 30) <= i && i <= (1 lsl 30) - 1) ;
      i)

let string = Crowbar.bytes

let short_string =
  let open Crowbar in
  choose
    [
      const "";
      bytes_fixed 1;
      bytes_fixed 2;
      bytes_fixed 3;
      bytes_fixed 4;
      bytes_fixed 5;
    ]

let short_string1 =
  let open Crowbar in
  choose
    [bytes_fixed 1; bytes_fixed 2; bytes_fixed 3; bytes_fixed 4; bytes_fixed 5]

let bytes = Crowbar.map [Crowbar.bytes] Bytes.of_string

let short_bytes = Crowbar.map [short_string] Bytes.of_string

let short_bytes1 = Crowbar.map [short_string1] Bytes.of_string

(* We need to hide the type parameter of `Encoding.t` to avoid the generator
 * combinator `choose` from complaining about different types. We use first
 * level modules (for now) to encode existentials.
 *
 * An alternative is used in https://gitlab.com/gasche/fuzz-data-encoding *)

type ('a, 'b) either = Left of 'a | Right of 'b

type _ ty =
  | Null : unit ty
  | Empty : unit ty
  | Unit : unit ty
  | Constant : string -> unit ty
  | Int8 : int ty
  | UInt8 : int ty
  | Int16 : int ty
  | UInt16 : int ty
  | Int31 : int ty
  | RangedInt : int * int -> int ty
  | Int32 : int32 ty
  | Int64 : int64 ty
  | Float : float ty
  | RangedFloat : float * float -> float ty
  | Bool : bool ty
  | String : string ty
  | FixedString : int -> string ty
  | Bytes : bytes ty
  | FixedBytes : int -> bytes ty
  | Option : 'a ty -> 'a option ty
  | Result : 'a ty * 'b ty -> ('a, 'b) result ty
  | List : 'a ty -> 'a list ty
  | Array : 'a ty -> 'a array ty
  | Dynamic_size : 'a ty -> 'a ty
  | Tup1 : 'a ty -> 'a ty
  | Tup2 : 'a ty * 'b ty -> ('a * 'b) ty
  | Tup3 : 'a ty * 'b ty * 'c ty -> ('a * 'b * 'c) ty
  | Tup4 : 'a ty * 'b ty * 'c ty * 'd ty -> ('a * 'b * 'c * 'd) ty
  | Union1 : 'a ty -> 'a ty
  | Union2 : 'a ty * 'b ty -> ('a, 'b) either ty
  | Matching2 : 'a ty * 'b ty -> ('a, 'b) either ty
  | Mu_matching : 'a ty -> 'a list ty
  | Check_size : 'a ty -> 'a ty
  | StringEnum : int ty

(* TODO:
   | Tup[5-10] : ..
   | Obj
   | Conv
   | Delayed
*)

let rec pp_ty : type a. a ty Crowbar.printer =
 fun ppf ty ->
  match ty with
  | Null ->
      Crowbar.pp ppf "(null)"
  | Empty ->
      Crowbar.pp ppf "{}"
  | Unit ->
      Crowbar.pp ppf "()"
  | Constant s ->
      Crowbar.pp ppf "(constant:%S)" s
  | Int8 ->
      Crowbar.pp ppf "int8"
  | UInt8 ->
      Crowbar.pp ppf "uint8"
  | Int16 ->
      Crowbar.pp ppf "int16"
  | UInt16 ->
      Crowbar.pp ppf "uint16"
  | Int31 ->
      Crowbar.pp ppf "int31"
  | RangedInt (low, high) ->
      Crowbar.pp ppf "rangedint:[%d;%d]" low high
  | Int32 ->
      Crowbar.pp ppf "int32"
  | Int64 ->
      Crowbar.pp ppf "int64"
  | Float ->
      Crowbar.pp ppf "float"
  | RangedFloat (low, high) ->
      Crowbar.pp ppf "rangedfloat:[%g;%g]" low high
  | Bool ->
      Crowbar.pp ppf "bool"
  | String ->
      Crowbar.pp ppf "string"
  | Bytes ->
      Crowbar.pp ppf "bytes"
  | FixedString n ->
      Crowbar.pp ppf "fixedstring(%d)" n
  | FixedBytes n ->
      Crowbar.pp ppf "fixedbytes(%d)" n
  | Option ty ->
      Crowbar.pp ppf "option(%a)" pp_ty ty
  | Result (tya, tyb) ->
      Crowbar.pp ppf "result(%a,%a)" pp_ty tya pp_ty tyb
  | List ty ->
      Crowbar.pp ppf "list(%a)" pp_ty ty
  | Array ty ->
      Crowbar.pp ppf "array(%a)" pp_ty ty
  | Dynamic_size ty ->
      Crowbar.pp ppf "dynamic_size(%a)" pp_ty ty
  | Tup1 ty ->
      Crowbar.pp ppf "tup1(%a)" pp_ty ty
  | Tup2 (tya, tyb) ->
      Crowbar.pp ppf "tup2(%a,%a)" pp_ty tya pp_ty tyb
  | Tup3 (tya, tyb, tyc) ->
      Crowbar.pp ppf "tup3(%a,%a,%a)" pp_ty tya pp_ty tyb pp_ty tyc
  | Tup4 (tya, tyb, tyc, tyd) ->
      Crowbar.pp
        ppf
        "tup4(%a,%a,%a,%a)"
        pp_ty
        tya
        pp_ty
        tyb
        pp_ty
        tyc
        pp_ty
        tyd
  | Union1 ty ->
      Crowbar.pp ppf "union1(%a)" pp_ty ty
  | Union2 (tya, tyb) ->
      Crowbar.pp ppf "union2(%a,%a)" pp_ty tya pp_ty tyb
  | Matching2 (tya, tyb) ->
      Crowbar.pp ppf "matching2(%a,%a)" pp_ty tya pp_ty tyb
  | Mu_matching ty ->
      Crowbar.pp ppf "mu_matching(%a)" pp_ty ty
  | Check_size ty ->
      Crowbar.pp ppf "check_size(%a)" pp_ty ty
  | StringEnum ->
      Crowbar.pp ppf "string_enum"

let dynamic_if_needed : 'a Data_encoding.t -> 'a Data_encoding.t =
 fun e ->
  match Data_encoding.classify e with
  | `Fixed 0 | `Variable ->
      Data_encoding.dynamic_size e
  | `Fixed _ | `Dynamic ->
      e

type any_ty = AnyTy : _ ty -> any_ty

let pp_any_ty : any_ty Crowbar.printer =
 fun ppf any_ty -> match any_ty with AnyTy ty -> pp_ty ppf ty

let any_ty_gen =
  let open Crowbar in
  let g : any_ty Crowbar.gen =
    fix (fun g ->
        choose
          [
            const @@ AnyTy Null;
            const @@ AnyTy Empty;
            const @@ AnyTy Unit;
            map [string] (fun s -> AnyTy (Constant s));
            const @@ AnyTy Int8;
            const @@ AnyTy UInt8;
            const @@ AnyTy Int16;
            const @@ AnyTy UInt16;
            const @@ AnyTy Int31;
            map [int31; int31] (fun a b ->
                if a = b then Crowbar.bad_test () ;
                let low = min a b in
                let high = max a b in
                AnyTy (RangedInt (low, high)));
            const @@ AnyTy Int32;
            const @@ AnyTy Int64;
            const @@ AnyTy Float;
            map [float; float] (fun a b ->
                if Float.is_nan a || Float.is_nan b then Crowbar.bad_test () ;
                if a = b then Crowbar.bad_test () ;
                let low = min a b in
                let high = max a b in
                AnyTy (RangedFloat (low, high)));
            const @@ AnyTy Bool;
            const @@ AnyTy String;
            const @@ AnyTy Bytes;
            map [range ~min:1 10] (fun i -> AnyTy (FixedString i));
            map [range ~min:1 10] (fun i -> AnyTy (FixedBytes i));
            map [g] (fun (AnyTy ty) -> AnyTy (Option ty));
            map [g; g] (fun (AnyTy ty_ok) (AnyTy ty_error) ->
                AnyTy (Result (ty_ok, ty_error)));
            map [g] (fun (AnyTy ty_both) -> AnyTy (Result (ty_both, ty_both)));
            map [g] (fun (AnyTy ty) -> AnyTy (List ty));
            map [g] (fun (AnyTy ty) -> AnyTy (Array ty));
            map [g] (fun (AnyTy ty) -> AnyTy (Dynamic_size ty));
            map [g] (fun (AnyTy ty) -> AnyTy (Tup1 ty));
            map [g; g] (fun (AnyTy ty_a) (AnyTy ty_b) ->
                AnyTy (Tup2 (ty_a, ty_b)));
            map [g] (fun (AnyTy ty_both) -> AnyTy (Tup2 (ty_both, ty_both)));
            map [g; g; g] (fun (AnyTy ty_a) (AnyTy ty_b) (AnyTy ty_c) ->
                AnyTy (Tup3 (ty_a, ty_b, ty_c)));
            map
              [g; g; g; g]
              (fun (AnyTy ty_a) (AnyTy ty_b) (AnyTy ty_c) (AnyTy ty_d) ->
                AnyTy (Tup4 (ty_a, ty_b, ty_c, ty_d)));
            map [g] (fun (AnyTy ty_a) -> AnyTy (Union1 ty_a));
            map [g; g] (fun (AnyTy ty_a) (AnyTy ty_b) ->
                AnyTy (Union2 (ty_a, ty_b)));
            map [g] (fun (AnyTy ty_both) -> AnyTy (Union2 (ty_both, ty_both)));
            map [g; g] (fun (AnyTy ty_a) (AnyTy ty_b) ->
                AnyTy (Matching2 (ty_a, ty_b)));
            map [g] (fun (AnyTy ty_both) ->
                AnyTy (Matching2 (ty_both, ty_both)));
            map [g] (fun (AnyTy ty) -> AnyTy (Mu_matching ty));
            map [g] (fun (AnyTy ty) -> AnyTy (Check_size ty));
            const @@ AnyTy StringEnum;
          ])
  in
  with_printer pp_any_ty g

module type FULL = sig
  type t

  val ty : t ty

  val eq : t -> t -> bool

  val pp : t Crowbar.printer

  val gen : t Crowbar.gen

  val encoding : t Data_encoding.t
end

type 'a full = (module FULL with type t = 'a)

(* TODO: derive equality from "parent" *)

let make_unit ty s encoding : unit full =
  ( module struct
    type t = unit

    let ty = ty

    let eq _ _ = true

    let pp ppf () = Crowbar.pp ppf "%s" s

    let gen = Crowbar.const ()

    let encoding = encoding
  end )

let full_null : unit full = make_unit Null "null" Data_encoding.null

let full_empty : unit full = make_unit Empty "{}" Data_encoding.empty

let full_unit : unit full = make_unit Unit "()" Data_encoding.unit

let full_constant s : unit full =
  make_unit (Constant s) ("constant:" ^ s) (Data_encoding.constant s)

let make_int ty gen encoding : int full =
  ( module struct
    type t = int

    let ty = ty

    let eq = Int.equal

    let pp ppf v = Crowbar.pp ppf "%d" v

    let gen = gen

    let encoding = encoding
  end )

let full_int8 : int full = make_int Int8 Crowbar.int8 Data_encoding.int8

let full_uint8 : int full = make_int UInt8 Crowbar.uint8 Data_encoding.uint8

let full_int16 : int full = make_int Int16 Crowbar.int16 Data_encoding.int16

let full_uint16 : int full =
  make_int UInt16 Crowbar.uint16 Data_encoding.uint16

let full_int31 : int full = make_int Int31 int31 Data_encoding.int31

let full_rangedint low high : int full =
  assert (low < high) ;
  make_int
    (RangedInt (low, high))
    Crowbar.(map [range (high - low)] (fun v -> v + low))
    (Data_encoding.ranged_int low high)

let full_int32 : int32 full =
  ( module struct
    type t = int32

    let ty = Int32

    let eq = Int32.equal

    let pp ppf v = Crowbar.pp ppf "%ld" v

    let gen = Crowbar.int32

    let encoding = Data_encoding.int32
  end )

let full_int64 : int64 full =
  ( module struct
    type t = int64

    let ty = Int64

    let eq = Int64.equal

    let pp ppf v = Crowbar.pp ppf "%Ld" v

    let gen = Crowbar.int64

    let encoding = Data_encoding.int64
  end )

let make_float ty gen encoding : float full =
  ( module struct
    type t = float

    let ty = ty

    let eq = Float.equal

    let pp ppf v = Crowbar.pp ppf "%g" v

    let gen = gen

    let encoding = encoding
  end )

let full_float : float full =
  make_float Float Crowbar.float Data_encoding.float

let full_rangedfloat low high : float full =
  assert (low < high) ;
  make_float
    (RangedFloat (low, high))
    Crowbar.(
      map [float] (fun f ->
          if Float.is_nan f then Crowbar.bad_test () ;
          if f < low || f > high then Crowbar.bad_test () ;
          f))
    (Data_encoding.ranged_float low high)

let full_bool : bool full =
  ( module struct
    type t = bool

    let ty = Bool

    let eq = Bool.equal

    let pp ppf v = Crowbar.pp ppf "%b" v

    let gen = Crowbar.bool

    let encoding = Data_encoding.bool
  end )

let make_string ty gen encoding : string full =
  ( module struct
    type t = string

    let ty = ty

    let eq = String.equal

    let pp ppf v = Crowbar.pp ppf "%S" v

    let gen = gen

    let encoding = encoding
  end )

let full_string : string full = make_string String string Data_encoding.string

let full_fixed_string n : string full =
  make_string
    (FixedString n)
    (Crowbar.bytes_fixed n)
    (Data_encoding.Fixed.string n)

let make_bytes ty gen encoding : bytes full =
  ( module struct
    type t = bytes

    let ty = ty

    let eq = Bytes.equal

    let pp ppf v = Crowbar.pp ppf "%S" (Bytes.unsafe_to_string v)

    let gen = gen

    let encoding = encoding
  end )

let full_bytes : bytes full = make_bytes Bytes bytes Data_encoding.bytes

let full_fixed_bytes n : bytes full =
  make_bytes
    (FixedBytes n)
    Crowbar.(map [bytes_fixed n] Bytes.unsafe_of_string)
    (Data_encoding.Fixed.bytes n)

let full_option : type a. a full -> a option full =
 fun full ->
  let module Full = (val full) in
  if Data_encoding__Encoding.is_nullable Full.encoding then Crowbar.bad_test ()
  else
    ( module struct
      type t = Full.t option

      let ty = Option Full.ty

      let eq a b =
        match (a, b) with
        | (None, None) ->
            true
        | (Some a, Some b) ->
            Full.eq a b
        | (Some _, None) | (None, Some _) ->
            false

      let pp ppf = function
        | None ->
            Crowbar.pp ppf "none"
        | Some p ->
            Crowbar.pp ppf "some(%a)" Full.pp p

      let gen = Crowbar.option Full.gen

      let encoding = Data_encoding.(option Full.encoding)
    end )

let full_list : type a. a full -> a list full =
 fun full ->
  let module Full = (val full) in
  ( module struct
    type t = Full.t list

    let ty = List Full.ty

    let eq xs ys =
      List.compare_lengths xs ys = 0 && List.for_all2 Full.eq xs ys

    let pp ppf v =
      Crowbar.pp
        ppf
        "list(%a)"
        Format.(
          pp_print_list ~pp_sep:(fun fmt () -> pp_print_char fmt ',') Full.pp)
        v

    let gen = Crowbar.list Full.gen

    let encoding = Data_encoding.(list (dynamic_if_needed Full.encoding))
  end )

let full_array : type a. a full -> a array full =
 fun full ->
  let module Full = (val full) in
  ( module struct
    type t = Full.t array

    let ty = Array Full.ty

    let eq xs ys =
      Array.length xs = Array.length ys
      && Array.for_all Fun.id (Array.map2 Full.eq xs ys)

    let pp ppf v =
      Crowbar.pp
        ppf
        "array(%a)"
        Format.(
          pp_print_list ~pp_sep:(fun fmt () -> pp_print_char fmt ',') Full.pp)
        (Array.to_list v)

    let gen = Crowbar.(map [list Full.gen] Array.of_list)

    let encoding = Data_encoding.(array (dynamic_if_needed Full.encoding))
  end )

let full_dynamic_size : type a. a full -> a full =
 fun full ->
  let module Full = (val full) in
  ( module struct
    include Full

    let ty = Dynamic_size ty

    let encoding = Data_encoding.dynamic_size encoding
  end )

let full_tup1 : type a. a full -> a full =
 fun full ->
  let module Full = (val full) in
  ( module struct
    include Full

    let ty = Tup1 Full.ty

    let pp ppf v = Crowbar.pp ppf "tup1(%a)" Full.pp v

    let encoding = Data_encoding.tup1 Full.encoding
  end )

let full_tup2 : type a b. a full -> b full -> (a * b) full =
 fun fulla fullb ->
  let module Fulla = (val fulla) in
  let module Fullb = (val fullb) in
  ( module struct
    type t = Fulla.t * Fullb.t

    let ty = Tup2 (Fulla.ty, Fullb.ty)

    let eq (a, b) (u, v) = Fulla.eq a u && Fullb.eq b v

    let pp ppf (a, b) = Crowbar.pp ppf "tup2(%a,%a)" Fulla.pp a Fullb.pp b

    let gen = Crowbar.map [Fulla.gen; Fullb.gen] (fun a b -> (a, b))

    let encoding =
      Data_encoding.(tup2 (dynamic_if_needed Fulla.encoding) Fullb.encoding)
  end )

let full_tup3 : type a b c. a full -> b full -> c full -> (a * b * c) full =
 fun fulla fullb fullc ->
  let module Fulla = (val fulla) in
  let module Fullb = (val fullb) in
  let module Fullc = (val fullc) in
  ( module struct
    type t = Fulla.t * Fullb.t * Fullc.t

    let ty = Tup3 (Fulla.ty, Fullb.ty, Fullc.ty)

    let eq (a, b, c) (u, v, w) = Fulla.eq a u && Fullb.eq b v && Fullc.eq c w

    let pp ppf (a, b, c) =
      Crowbar.pp ppf "tup3(%a,%a,%a)" Fulla.pp a Fullb.pp b Fullc.pp c

    let gen =
      Crowbar.map [Fulla.gen; Fullb.gen; Fullc.gen] (fun a b c -> (a, b, c))

    let encoding =
      Data_encoding.(
        tup3
          (dynamic_if_needed Fulla.encoding)
          (dynamic_if_needed Fullb.encoding)
          Fullc.encoding)
  end )

let full_tup4 :
    type a b c d. a full -> b full -> c full -> d full -> (a * b * c * d) full
    =
 fun fulla fullb fullc fulld ->
  let module Fulla = (val fulla) in
  let module Fullb = (val fullb) in
  let module Fullc = (val fullc) in
  let module Fulld = (val fulld) in
  ( module struct
    type t = Fulla.t * Fullb.t * Fullc.t * Fulld.t

    let ty = Tup4 (Fulla.ty, Fullb.ty, Fullc.ty, Fulld.ty)

    let eq (a, b, c, d) (u, v, w, z) =
      Fulla.eq a u && Fullb.eq b v && Fullc.eq c w && Fulld.eq d z

    let pp ppf (a, b, c, d) =
      Crowbar.pp
        ppf
        "tup4(%a,%a,%a,%a)"
        Fulla.pp
        a
        Fullb.pp
        b
        Fullc.pp
        c
        Fulld.pp
        d

    let gen =
      Crowbar.map [Fulla.gen; Fullb.gen; Fullc.gen; Fulld.gen] (fun a b c d ->
          (a, b, c, d))

    let encoding =
      Data_encoding.(
        tup4
          (dynamic_if_needed Fulla.encoding)
          (dynamic_if_needed Fullb.encoding)
          (dynamic_if_needed Fullc.encoding)
          Fulld.encoding)
  end )

let full_result : type a b. a full -> b full -> (a, b) result full =
 fun fulla fullb ->
  let module Fulla = (val fulla) in
  let module Fullb = (val fullb) in
  ( module struct
    type t = (Fulla.t, Fullb.t) result

    let ty = Result (Fulla.ty, Fullb.ty)

    let eq = Result.equal ~ok:Fulla.eq ~error:Fullb.eq

    let gen = Crowbar.result Fulla.gen Fullb.gen

    let encoding = Data_encoding.result Fulla.encoding Fullb.encoding

    let pp ppf = function
      | Ok a ->
          Crowbar.pp ppf "ok(%a)" Fulla.pp a
      | Error b ->
          Crowbar.pp ppf "error(%a)" Fullb.pp b
  end )

let full_union1 : type a. a full -> a full =
 fun fulla ->
  let module Fulla = (val fulla) in
  ( module struct
    type t = Fulla.t

    let ty = Union1 Fulla.ty

    let eq = Fulla.eq

    let a_ding =
      let open Data_encoding in
      obj1 (req "OnlyThisOneOnly" Fulla.encoding)

    let encoding =
      let open Data_encoding in
      union
        [case ~title:"A" (Tag 0) a_ding (function v -> Some v) (fun v -> v)]

    let gen = Fulla.gen

    let pp ppf = function
      | v1 ->
          Crowbar.pp ppf "@[<hv 1>(Union1 %a)@]" Fulla.pp v1
  end )

let full_union2 : type a b. a full -> b full -> (a, b) either full =
 fun fulla fullb ->
  let module Fulla = (val fulla) in
  let module Fullb = (val fullb) in
  ( module struct
    type t = (Fulla.t, Fullb.t) either

    let ty = Union2 (Fulla.ty, Fullb.ty)

    let eq x y =
      match (x, y) with
      | (Left _, Right _) | (Right _, Left _) ->
          false
      | (Left x, Left y) ->
          Fulla.eq x y
      | (Right x, Right y) ->
          Fullb.eq x y

    let a_ding =
      let open Data_encoding in
      obj1 (req "A" Fulla.encoding)

    let b_ding =
      let open Data_encoding in
      obj1 (req "B" Fullb.encoding)

    let encoding =
      let open Data_encoding in
      union
        [
          case
            ~title:"A"
            (Tag 0)
            a_ding
            (function Left v -> Some v | Right _ -> None)
            (fun v -> Left v);
          case
            ~title:"B"
            (Tag 1)
            b_ding
            (function Left _ -> None | Right v -> Some v)
            (fun v -> Right v);
        ]

    let gen =
      let open Crowbar in
      map [bool; Fulla.gen; Fullb.gen] (fun choice a b ->
          if choice then Left a else Right b)

    let pp ppf = function
      | Left v1 ->
          Crowbar.pp ppf "@[<hv 1>(A %a)@]" Fulla.pp v1
      | Right v2 ->
          Crowbar.pp ppf "@[<hv 1>(B %a)@]" Fullb.pp v2
  end )

let full_matching2 : type a b. a full -> b full -> (a, b) either full =
 fun fulla fullb ->
  let module Fulla = (val fulla) in
  let module Fullb = (val fullb) in
  ( module struct
    type t = (Fulla.t, Fullb.t) either

    let ty = Matching2 (Fulla.ty, Fullb.ty)

    let eq x y =
      match (x, y) with
      | (Left _, Right _) | (Right _, Left _) ->
          false
      | (Left x, Left y) ->
          Fulla.eq x y
      | (Right x, Right y) ->
          Fullb.eq x y

    let a_ding =
      let open Data_encoding in
      obj1 (req "A" Fulla.encoding)

    let b_ding =
      let open Data_encoding in
      obj1 (req "B" Fullb.encoding)

    let encoding =
      let open Data_encoding in
      matching
        (function
          | Left v -> matched 0 a_ding v | Right v -> matched 1 b_ding v)
        [
          case
            ~title:"A"
            (Tag 0)
            a_ding
            (function Left v -> Some v | Right _ -> None)
            (fun v -> Left v);
          case
            ~title:"B"
            (Tag 1)
            b_ding
            (function Left _ -> None | Right v -> Some v)
            (fun v -> Right v);
        ]

    let gen =
      let open Crowbar in
      map [bool; Fulla.gen; Fullb.gen] (fun choice a b ->
          if choice then Left a else Right b)

    let pp ppf = function
      | Left v1 ->
          Crowbar.pp ppf "@[<hv 1>(A %a)@]" Fulla.pp v1
      | Right v2 ->
          Crowbar.pp ppf "@[<hv 1>(B %a)@]" Fullb.pp v2
  end )

let fresh_name =
  let r = ref 0 in
  fun () ->
    incr r ;
    "mun" ^ string_of_int !r

let full_mu_matching : type a. a full -> a list full =
 fun fulla ->
  let module Fulla = (val fulla) in
  ( module struct
    type t = Fulla.t list

    let ty = Mu_matching Fulla.ty

    let rec eq x y =
      match (x, y) with
      | ([], []) ->
          true
      | (x :: xs, y :: ys) ->
          Fulla.eq x y && eq xs ys
      | (_ :: _, []) | ([], _ :: _) ->
          false

    let encoding =
      let open Data_encoding in
      mu (fresh_name ())
      @@ fun self ->
      matching
        (function
          | [] ->
              matched 0 (obj1 (req "nil" unit)) ()
          | x :: xs ->
              matched
                2
                (obj2 (req "head" Fulla.encoding) (req "tail" self))
                (x, xs))
        [
          case
            ~title:"nil"
            (Tag 0)
            (obj1 (req "nil" unit))
            (function [] -> Some () | _ :: _ -> None)
            (fun () -> []);
          case
            ~title:"cons"
            (Tag 2)
            (obj2 (req "head" Fulla.encoding) (req "tail" self))
            (function [] -> None | x :: xs -> Some (x, xs))
            (fun (x, xs) -> x :: xs);
        ]

    let gen = Crowbar.list Fulla.gen

    let pp ppf v =
      Crowbar.pp
        ppf
        "list(%a)"
        Format.(
          pp_print_list ~pp_sep:(fun fmt () -> pp_print_char fmt ',') Fulla.pp)
        v
  end )

let full_check_size : type a. a full -> a full =
 fun full ->
  let module Full = (val full) in
  match Data_encoding.Binary.maximum_length Full.encoding with
  | None ->
      Crowbar.bad_test ()
  | Some size ->
      ( module struct
        include Full

        let encoding = Data_encoding.check_size size Full.encoding
      end )

let full_string_enum : int full =
  make_int
    StringEnum
    (Crowbar.range 8)
    (Data_encoding.string_enum
       [
         ("zero", 0);
         ("never", 123234);
         ("one", 1);
         ("two", 2);
         ("three", 3);
         ("four", 4);
         ("also-never", 1232234);
         ("five", 5);
         ("six", 6);
         ("seven", 7);
       ])

let rec full_of_ty : type a. a ty -> a full = function
  | Null ->
      full_null
  | Empty ->
      full_empty
  | Unit ->
      full_unit
  | Constant s ->
      full_constant s
  | Int8 ->
      full_int8
  | UInt8 ->
      full_uint8
  | Int16 ->
      full_int16
  | UInt16 ->
      full_uint16
  | Int31 ->
      full_int31
  | RangedInt (low, high) ->
      full_rangedint low high
  | Int32 ->
      full_int32
  | Int64 ->
      full_int64
  | Float ->
      full_float
  | RangedFloat (low, high) ->
      full_rangedfloat low high
  | Bool ->
      full_bool
  | String ->
      full_string
  | Bytes ->
      full_bytes
  | FixedString n ->
      full_fixed_string n
  | FixedBytes n ->
      full_fixed_bytes n
  | Option ty ->
      full_option (full_of_ty ty)
  | Result (tya, tyb) ->
      full_result (full_of_ty tya) (full_of_ty tyb)
  | List ty ->
      full_list (full_of_ty ty)
  | Array ty ->
      full_array (full_of_ty ty)
  | Dynamic_size ty ->
      full_dynamic_size (full_of_ty ty)
  | Tup1 ty ->
      full_tup1 (full_of_ty ty)
  | Tup2 (tya, tyb) ->
      full_tup2 (full_of_ty tya) (full_of_ty tyb)
  | Tup3 (tya, tyb, tyc) ->
      full_tup3 (full_of_ty tya) (full_of_ty tyb) (full_of_ty tyc)
  | Tup4 (tya, tyb, tyc, tyd) ->
      full_tup4
        (full_of_ty tya)
        (full_of_ty tyb)
        (full_of_ty tyc)
        (full_of_ty tyd)
  | Union1 ty ->
      full_union1 (full_of_ty ty)
  | Union2 (tya, tyb) ->
      full_union2 (full_of_ty tya) (full_of_ty tyb)
  | Matching2 (tya, tyb) ->
      full_matching2 (full_of_ty tya) (full_of_ty tyb)
  | Mu_matching ty ->
      full_mu_matching (full_of_ty ty)
  | Check_size ty ->
      full_check_size (full_of_ty ty)
  | StringEnum ->
      full_string_enum

type full_and_v = FullAndV : 'a full * 'a -> full_and_v

let gen : full_and_v Crowbar.gen =
  let open Crowbar in
  dynamic_bind any_ty_gen (function AnyTy ty ->
      let full = full_of_ty ty in
      let module Full = (val full) in
      map [Full.gen] (fun v -> FullAndV (full, v)))

type any_full = AnyFull : 'a full -> any_full

let gen_full : any_full Crowbar.gen =
  let open Crowbar in
  map [any_ty_gen] (fun (AnyTy ty) -> AnyFull (full_of_ty ty))
