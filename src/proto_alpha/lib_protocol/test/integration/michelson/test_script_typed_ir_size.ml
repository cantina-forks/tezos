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

(** Testing
    -------
    Component:  Protocol (script typed IR size)
    Invocation: dune exec \
                src/proto_alpha/lib_protocol/test/integration/michelson/main.exe \
                -- test "^script typed ir size$"
    Subject:    Script_typed_ir computes good approximation of values' sizes
*)

open Protocol
open Alpha_context
open Script_ir_translator
open Script_typed_ir

(*
   Helpers
   -------
*)

exception Script_typed_ir_test_error of string

let err x = Exn (Script_typed_ir_test_error x)

let dummy_loc = Micheline.dummy_location

let get = Stdlib.Option.get

let is_ok m = match m with Ok x -> x | _ -> assert false

let footprint v =
  (* This is to turn every statically allocated data into
     heap-allocated data, to consider the worst-case in-memory
     representation of values. Note that it does NOT remove sharing.*)
  let v' =
    try Marshal.(from_bytes (to_bytes v [Closures]) 0)
    with _ -> (* Custom blocks are problematic. *) v
  in
  let size v = Obj.(reachable_words (repr v) * 8) in
  max (size v) (size v')

(** [gen_string s] returns a heap-allocated string. Notice that a
    string literal ["foo"] written in the code is statically allocated
    and is therefore not counted by [Obj.reachable_words]. *)
let gen_string s =
  let s = Bytes.of_string s |> Bytes.to_string in
  is_ok @@ Script_string.of_string s

let boxed_set_elements s = Script_set.fold (fun x s -> x :: s) s []

let boxed_map_bindings s = Script_map.fold (fun k v s -> (k, v) :: s) s []

let big_map_bindings (Big_map s) = Big_map_overlay.bindings s.diff.map

let show_script_int fmt x = Z.pp_print fmt (Script_int.to_zint x)

let show_bool fmt b = Format.fprintf fmt "%B" b

let show_script_string fmt x =
  Format.fprintf fmt "%s" (Script_string.to_string x)

let show_address fmt Script_typed_ir.{destination; entrypoint} =
  Format.fprintf
    fmt
    "%a(%d):%a(%d)"
    Destination.pp
    destination
    (footprint destination)
    Entrypoint.pp
    entrypoint
    (footprint entrypoint)

let dont_show _fmt _ = ()

let size = {Tezos_benchmark.Base_samplers.min = 4; max = 32}

module Crypto_samplers =
Tezos_benchmark.Crypto_samplers.Make_finite_key_pool (struct
  let size = 10

  let algo = `Default
end)

include
  Michelson_samplers.Make
    (struct
      let parameters : Michelson_samplers.parameters =
        {
          base_parameters =
            {
              Michelson_samplers_base.int_size = size;
              string_size = size;
              bytes_size = size;
            };
          list_size = size;
          set_size = size;
          map_size = size;
        }
    end)
    (Crypto_samplers)

let random_state = Random.State.make [|37; 73; 17; 71; 42|]

let sample_ty size = Random_type.m_type ~size random_state

let sample_value ty = Random_value.value ty random_state

type ex = Ex : string * ('a, _) Script_typed_ir.ty * 'a * int -> ex [@@boxed]

let ex ?(error = 0) label ty v = Ex (label, ty, v, error)

let ex_random ?(error = 0) show ty ?(sample = fun () -> sample_value ty) label =
  let v = sample () in
  let label = Format.asprintf "@[%a%s@]@." show v label in
  ex ~error label ty v

let exs ?(error = 0) n show ty ?(sample = fun () -> sample_value ty) label =
  List.map (fun _ -> ex_random ~error show ty label ~sample) (1 -- n)

let nsample = 100

type ex_kinstr = Kinstr : string * ('a, 'b, 'c, 'd) kinstr * int -> ex_kinstr
[@@boxed]

(** [check_value_size ()] covers a finite number of cases of Michelson
   values, checking that the cost model is sound with respect to their
   memory footprint.

   One could wonder why we do not simply use a single value generator
   based on a randomly chosen type. We actually implemented such a
   strategy in a previous version of this test but this results in a
   flaky test. Indeed, for some types, the values are overapproximated
   and it was difficult to correctly handle the accumulation of errors
   when types were randomly composed.

   The current strategy requires more code but, in exchange, it
   provides a finer control over the overapproximation. As a
   consequence, we can check for example that there is no
   overapproximation for values for which the model is exact.  We can
   also check that the overapproximation is at least well understood
   on the values for which size model is not exact. *)
let check_value_size () =
  let check (Ex (what, ty, v, error)) =
    let expected_size = footprint v in
    let _, size = Script_typed_ir_size.value_size ty v in
    let size = Saturation_repr.to_int size in
    fail_when
      (expected_size + error < size || size < expected_size)
      (err
         (Printf.sprintf
            "%s was expected to have size %d while the size model answered %d \
             (with +%d accepted over approximation error)"
            what
            expected_size
            size
            error))
  in
  List.iter_es
    check
    ((*
        Unit_t
        ======
     *)
     [ex "() : unit" Unit_t ()]
    (*
        Int_t
        =====
    *)
    @ (let error = 8 in
       [
         ex ~error "0 : int" Int_t Script_int.zero;
         ex ~error "2^63 : int" Int_t (Script_int.of_int max_int);
         ex
           ~error
           "37^73 : int"
           Int_t
           (Script_int.of_zint Z.(pow (of_int 37) 73));
         ex
           ~error
           "-37^73 : int"
           Int_t
           (Script_int.of_zint Z.(neg (pow (of_int 37) 73)));
         ex
           ~error
           "13270006022583112970 : int"
           Int_t
           (get @@ Script_int.of_string "13270006022583112970");
       ]
       @ exs ~error nsample show_script_int Int_t ": int")
    (*
        Nat_t
        =====
    *)
    @ (let error = 8 in
       [
         ex ~error "0 : nat" Nat_t Script_int.zero_n;
         ex
           ~error
           "2^63 : nat"
           Nat_t
           (get Script_int.(is_nat @@ of_int max_int));
         ex
           ~error
           "37^73 : int"
           Nat_t
           (get Script_int.(is_nat @@ of_zint Z.(pow (of_int 37) 73)));
       ]
       @ exs ~error nsample show_script_int Nat_t ": nat")
    (*
       Signature_t
       ===========
    *)
    @ (let show fmt (Script_typed_ir.Script_signature.Signature_tag s) =
         Signature.pp fmt s
       in
       exs ~error:8 nsample show Signature_t ": signature")
    (*
       String_t
       ========
    *)
    @ (let show fmt s = Format.fprintf fmt "%s" (Script_string.to_string s) in
       exs nsample show String_t ": string")
    (*
       Bytes_t
       =======
    *)
    @ (let show fmt s = Format.fprintf fmt "%s" (Bytes.to_string s) in
       exs nsample show Bytes_t ": bytes")
    (*
       Mutez_t
       =======
    *)
    @ (let show fmt t = Format.fprintf fmt "%s" (Tez.to_string t) in
       exs nsample show Mutez_t ": mutez")
    (*
       Key_hash_t
       ==========
    *)
    @ (let show = Signature.Public_key_hash.pp in
       exs nsample show Key_hash_t ": key_hash")
    (*
       Key_t
       =====
    *)
    @ (let show = Signature.Public_key.pp in
       exs nsample show Key_t ": key_t")
    (*
       Timestamp_t
       ===========
    *)
    @ (let show fmt s =
         Format.fprintf fmt "%s" (Script_timestamp.to_string s)
       in
       exs ~error:8 nsample show Timestamp_t ": timestamp_t")
    (*
       Address_t
       =========
    *)
    @ exs nsample show_address Address_t ": address_t"
    (*
       Tx_rollup_l2_address_t
       ======================
    *)
    @ (let show = Indexable.pp Tx_rollup_l2_address.pp in
       exs nsample show Tx_rollup_l2_address_t ": tx_rollup_l2_t")
    (*
       Bool_t
       ======
    *)
    @ [ex "true : bool" Bool_t true; ex "false : bool" Bool_t false]
    (*
       Pair_t
       ======
    *)
    @ (let module P = struct
         type ('a, 'b) f = {apply : 'c. ('a * 'b, 'c) ty -> ex}
       end in
      let on_pair : type a b. (a, _) ty -> (b, _) ty -> (a, b) P.f -> ex =
       fun ty1 ty2 f ->
        let (Ty_ex_c ty) = is_ok @@ pair_t dummy_loc ty1 ty2 in
        f.apply ty
      in
      let open Script_int in
      [
        (* "int * int" *)
        on_pair
          int_t
          int_t
          {apply = (fun ty -> ex "(0, 0) : int * int" ty (of_int 0, of_int 0))};
        (* "string * string" *)
        on_pair
          string_t
          string_t
          {
            apply =
              (fun ty ->
                let foo = gen_string "foo" in
                let bar = gen_string "bar" in
                ex "(foo, bar) : string * string" ty (foo, bar));
          };
        (* "string * int" *)
        on_pair
          string_t
          int_t
          {
            apply =
              (fun ty ->
                let foo = gen_string "foo" in
                ex "(foo, 0) : string * int" ty (foo, of_int 0));
          };
        (* "int * int * int" *)
        on_pair
          int_t
          int_t
          {
            apply =
              (fun ty ->
                on_pair int_t ty
                @@ {
                     apply =
                       (fun ty ->
                         ex
                           "(0, (1, 2)) : int * int * int"
                           ty
                           (of_int 0, (of_int 1, of_int 2)));
                   });
          };
      ])
    (*
        Union_t
        =======
    *)
    @ (let module P = struct
         type ('a, 'b) f = {apply : 'c. (('a, 'b) union, 'c) ty -> ex}
       end in
      let on_union : type a b. (a, _) ty -> (b, _) ty -> (a, b) P.f -> ex =
       fun ty1 ty2 f ->
        let (Ty_ex_c ty) = is_ok @@ union_t dummy_loc ty1 ty2 in
        f.apply ty
      in
      let open Script_int in
      [
        (* "int + int" *)
        on_union
          int_t
          int_t
          {apply = (fun ty -> ex "L 0 : int + int" ty (L (of_int 0)))};
        on_union
          int_t
          int_t
          {apply = (fun ty -> ex "R 0 : int + int" ty (R (of_int 0)))};
        (* "string + string" *)
        on_union
          string_t
          string_t
          {
            apply =
              (fun ty ->
                let foo = gen_string "foo" in
                ex "L foo : string * string" ty (L foo));
          };
        on_union
          string_t
          string_t
          {
            apply =
              (fun ty ->
                let foo = gen_string "foo" in
                ex "R foo : string * string" ty (R foo));
          };
        (* "string + int" *)
        on_union
          string_t
          int_t
          {
            apply =
              (fun ty ->
                let foo = gen_string "foo" in
                ex "L foo : string * int" ty (L foo));
          };
        (* "int + int + int" *)
        on_union
          int_t
          int_t
          {
            apply =
              (fun ty ->
                on_union
                  int_t
                  ty
                  {
                    apply =
                      (fun ty -> ex "L 0 : int + int + int" ty (L (of_int 0)));
                  });
          };
        on_union
          int_t
          int_t
          {
            apply =
              (fun ty ->
                on_union
                  int_t
                  ty
                  {
                    apply =
                      (fun ty ->
                        ex "R (L 0) : int + int + int" ty (R (L (of_int 0))));
                  });
          };
        on_union
          int_t
          int_t
          {
            apply =
              (fun ty ->
                on_union
                  int_t
                  ty
                  {
                    apply =
                      (fun ty ->
                        ex "R (R 0) : int + int + int" ty (R (R (of_int 0))));
                  });
          };
      ])
    (*
        Option_t
        ========
    *)
    @ (let module P = struct
         type 'a f = {apply : 'c. ('a option, 'c) ty -> ex}
       end in
      let on_option : type a. (a, _) ty -> a P.f -> ex =
       fun ty f -> f.apply @@ is_ok @@ option_t dummy_loc ty
      in
      let open Script_int in
      [
        (* "option int" *)
        on_option int_t {apply = (fun ty -> ex "None : option int" ty None)};
        on_option
          int_t
          {apply = (fun ty -> ex "Some 0 : option int" ty (Some (of_int 0)))};
        (* "option string" *)
        on_option
          string_t
          {apply = (fun ty -> ex "None : option string" ty None)};
        on_option
          string_t
          {
            apply =
              (fun ty ->
                ex "Some \"foo\" : option string" ty (Some (gen_string "foo")));
          };
      ])
    (*
        List_t
        ======
    *)
    @ (let module P = struct
         type 'a f = {apply : 'c. ('a boxed_list, 'c) ty -> ex list}
       end in
      let on_list : type a. (a, _) ty -> a P.f -> ex list =
       fun ty f -> f.apply @@ is_ok @@ list_t dummy_loc ty
      in
      let check ty show_elt =
        on_list
          ty
          {
            apply =
              (fun ty ->
                let show fmt l = Format.pp_print_list show_elt fmt l.elements in
                exs nsample show ty ": list _");
          }
      in
      check string_t show_script_string)
    (*
        Set_t
        ======
    *)
    @ (let module P = struct
         type 'a f = {apply : 'c. ('a set, 'c) ty -> ex list}
       end in
      let on_set : type a. (a, _) ty -> a P.f -> ex list =
       fun ty f -> f.apply @@ is_ok @@ set_t dummy_loc ty
      in
      let check ty show_elt =
        on_set
          ty
          {
            apply =
              (fun ty ->
                let show fmt s =
                  Format.fprintf
                    fmt
                    "%a / %a"
                    show_script_int
                    (Script_set.size s)
                    (Format.pp_print_list show_elt)
                    (boxed_set_elements s)
                in
                exs nsample show ty ": set _");
          }
      in
      check string_t show_script_string)
    (*
        Map_t
        ======
    *)
    @ (let module P = struct
         type ('k, 'v) f = {apply : 'c. (('k, 'v) map, 'c) ty -> ex list}
       end in
      let on_map : type k v. (k, _) ty -> (v, _) ty -> (k, v) P.f -> ex list =
       fun kty vty f -> f.apply @@ is_ok @@ map_t dummy_loc kty vty
      in
      let check kty vty show_key show_value =
        on_map
          kty
          vty
          {
            apply =
              (fun ty ->
                let show_binding fmt (k, v) =
                  Format.fprintf fmt "(%a -> %a)" show_key k show_value v
                in
                let show fmt s =
                  Format.pp_print_list show_binding fmt (boxed_map_bindings s)
                in
                exs nsample show ty ": map _");
          }
      in
      check string_t string_t show_script_string show_script_string)
    (*
        Big_map_t
        ======
    *)
    @ (let module P = struct
         type ('k, 'v) f = {apply : 'c. (('k, 'v) big_map, 'c) ty -> ex list}
       end in
      let on_big_map : type k v. (k, _) ty -> (v, _) ty -> (k, v) P.f -> ex list
          =
       fun kty vty f -> f.apply @@ is_ok @@ big_map_t dummy_loc kty vty
      in
      let check kty vty show_key show_value =
        on_big_map
          kty
          vty
          {
            apply =
              (fun ty ->
                let show_binding fmt (_, (k, v)) =
                  match v with
                  | Some v ->
                      Format.fprintf fmt "(%a -> %a)" show_key k show_value v
                  | None -> Format.fprintf fmt "(%a?)" show_key k
                in
                let show fmt s =
                  Format.pp_print_list show_binding fmt (big_map_bindings s)
                in
                exs nsample show ty ": big_map _");
          }
      in
      check bool_t bool_t show_bool show_bool)
    (*
       Contract_t
       =========
    *)
    @ (let show fmt (Typed_contract {arg_ty = _; address}) =
         show_address fmt address
       in
       exs
         nsample
         show
         (is_ok @@ contract_t dummy_loc string_t)
         ": contract string")
    (*
       Chain_t
       =========
    *)
    @ exs nsample dont_show chain_id_t ": chain_id"
    (*
       Bls12_381_g1_t
       ==============
    *)
    @ exs nsample dont_show bls12_381_g1_t ": bls12_381_g1_t"
    (*
       Bls12_381_g2_t
       ==============
    *)
    @ exs nsample dont_show bls12_381_g2_t ": bls12_381_g2_t"
    (*
       Bls12_381_fr_t
       ==============
    *)
    @ exs nsample dont_show bls12_381_fr_t ": bls12_381_fr_t"
    (*
       Ticket_t
       ========
    *)
    @ exs
        ~error:8
        nsample
        dont_show
        (is_ok @@ ticket_t dummy_loc bool_t)
        ": ticket bool"
      (*
          Missing by lack of fully functional samplers:
          - Sapling_transaction_t ;
          - Sapling_transaction_deprecated_t ;
          - Sapling_state ;
          - Operation_t ;
          - Chest_key_t ;
          - Chest_t ;
          - Lambda_t.
    *)
    )

let check_ty_size () =
  let check () =
    match (sample_ty (Random.int 10 + 1) : ex_ty) with
    | Ex_ty ty ->
        let expected_size = footprint ty in
        let _, size = Script_typed_ir_size.Internal_for_tests.ty_size ty in
        let size = Saturation_repr.to_int size in
        let what = "some type" in
        fail_when
          (size <> expected_size)
          (err
             (Printf.sprintf
                "%s was expected to have size %d while the size model answered \
                 %d."
                what
                expected_size
                size))
  in
  List.iter_es (fun _ -> check ()) (1 -- nsample)

let check_size ~name ~tolerance ~expected ~actual item =
  let open Lwt_result_syntax in
  let exp = expected item in
  let act = actual item in
  let overapprox = 1_000_000 * (exp - act) / act in
  let msg verb =
    Printf.sprintf
      "For %s model predicts the size of %d bytes; while actual measured size \
       is %d bytes. The model %s %d.%04d%%"
      (name item)
      exp
      act
      verb
      (abs @@ (overapprox / 10_000))
      (abs @@ (overapprox mod 10_000))
  in
  let* () = fail_when (overapprox < 0) (err @@ msg "underapproximates by") in
  (* We expected the model to never underapproximate. *)
  fail_when
    (overapprox > tolerance item * 10_000)
    (err @@ msg "overapproximates by too much:")
(* We expect the overapproximation to be bounded by tollerance. *)

(* Test that the model accurately predicts instruction sizes. It tests each
   type of instruction separately as much as possible. Tested values are
   specifically tailored so that they can't be shared (in particular all
   reused values are wrapped in functions to force recomputation). Thanks
   to this the model gives precise predictions for each instruction. In real
   life the model will over-approximate due to sharing. It should never under-
   approximate though. *)
let check_kinstr_size () =
  let open Lwt_result_syntax in
  let check =
    check_size
      ~name:(fun (Kinstr (name, _, _)) -> name)
      ~tolerance:(fun (Kinstr (_, _, tolerance)) -> tolerance)
      ~expected:(fun (Kinstr (_, instr, _)) ->
        let _, expected =
          Script_typed_ir_size.Internal_for_tests.kinstr_size instr
        in
        Saturation_repr.to_int expected)
      ~actual:(fun (Kinstr (_, instr, _)) ->
        8 * Obj.(reachable_words @@ repr instr))
  in
  (* Location is an immediate value, so we don't care if it's shared. *)
  let loc = Micheline.dummy_location in
  let str s =
    (* It's important to transform the string somehow, or else it will be shared
       and thus not reached by Obj.reachable_words. *)
    match Script_string.of_string @@ String.uppercase_ascii s with
    | Ok ss -> ss
    | Error _ -> assert false
  in
  let entrypoint name =
    Entrypoint.of_string_strict_exn @@ String.uppercase_ascii name
  in
  (* Constants below are wrapped in functions to force recomputation and make sharing
     impossible. *)
  let halt () = IHalt loc in
  let drop () = IDrop (loc, halt ()) in
  let cdr = ICdr (loc, halt ()) in
  let const ty v = IConst (loc, ty, v, halt ()) in
  let unit_option_t () =
    WithExceptions.Result.get_ok ~loc:__LOC__ @@ option_t loc Unit_t
  in
  let stack_type () = Item_t (unit_option_t (), Bot_t) in
  let id_lambda () =
    Lam
      ( {
          kloc = loc;
          kbef = stack_type ();
          kaft = stack_type ();
          kinstr = halt ();
        },
        Micheline.Seq (loc, []) )
  in
  (* Following constants are used at most once. *)
  let* str_list_t =
    Lwt.return @@ Environment.wrap_tzresult @@ list_t loc String_t
  in
  let* nat_str_map_t =
    Lwt.return @@ Environment.wrap_tzresult @@ map_t loc Nat_t String_t
  in
  let* (Ty_ex_c nat_str_pair_t) =
    Lwt.return @@ Environment.wrap_tzresult @@ pair_t loc Nat_t String_t
  in
  let zero_memo_size =
    WithExceptions.Result.get_ok ~loc:__LOC__
    @@ Alpha_context.Sapling.Memo_size.parse_z Z.zero
  in
  (* Check size of the lambda alone. *)
  let* () =
    check_size
      ~tolerance:(fun _ -> 0)
      ~name:(fun _ -> "id lambda")
      ~expected:(fun lam ->
        let _, expected = Script_typed_ir_size.lambda_size lam in
        Saturation_repr.to_int expected)
      ~actual:(fun lam -> 8 * Obj.(reachable_words @@ repr lam))
      (id_lambda ())
  in
  (* Testing individual instructions. *)
  List.iter_es
    check
    [
      Kinstr ("IDrop", drop (), 0);
      Kinstr ("IDup", IDup (loc, halt ()), 0);
      Kinstr ("ISwap", ISwap (loc, halt ()), 0);
      Kinstr ("IConst", const String_t @@ str "tezos", 0);
      Kinstr ("ICons_pair", ICons_pair (loc, halt ()), 0);
      Kinstr ("ICar", ICar (loc, halt ()), 0);
      Kinstr ("ICdr", cdr, 0);
      Kinstr ("IUnpair", IUnpair (loc, halt ()), 0);
      Kinstr ("ICons_some", ICons_some (loc, halt ()), 0);
      Kinstr ("ICons_none", ICons_none (loc, Int_t, halt ()), 0);
      Kinstr
        ( "IIf_none",
          IIf_none
            {
              loc;
              branch_if_some = drop ();
              branch_if_none = halt ();
              k = halt ();
            },
          0 );
      Kinstr ("IOpt_map", IOpt_map {loc; body = halt (); k = halt ()}, 0);
      Kinstr ("ICons_left", ICons_left (loc, Nat_t, halt ()), 0);
      Kinstr ("ICons_right", ICons_right (loc, Int_t, halt ()), 0);
      Kinstr
        ( "IIf_left",
          IIf_left
            {
              loc;
              branch_if_left = drop ();
              branch_if_right = drop ();
              k = halt ();
            },
          0 );
      Kinstr ("ICons_list", ICons_list (loc, halt ()), 0);
      Kinstr ("INil", INil (loc, Bytes_t, halt ()), 0);
      Kinstr
        ( "IIf_cons",
          IIf_cons
            {
              loc;
              branch_if_cons = IDrop (loc, drop ());
              branch_if_nil = halt ();
              k = halt ();
            },
          0 );
      Kinstr ("IList_map", IList_map (loc, halt (), str_list_t, halt ()), 0);
      Kinstr ("IList_iter", IList_iter (loc, str_list_t, drop (), halt ()), 0);
      Kinstr ("IList_size", IList_size (loc, halt ()), 0);
      Kinstr ("IEmpty_set", IEmpty_set (loc, String_t, halt ()), 0);
      Kinstr ("ISet_iter", ISet_iter (loc, String_t, drop (), halt ()), 0);
      Kinstr ("ISet_mem", ISet_mem (loc, halt ()), 0);
      Kinstr ("ISet_update", ISet_update (loc, halt ()), 0);
      Kinstr ("ISet_size", ISet_size (loc, halt ()), 0);
      Kinstr ("IEmpty_map", IEmpty_map (loc, Nat_t, String_t, halt ()), 0);
      Kinstr ("IMap_map", IMap_map (loc, nat_str_map_t, cdr, halt ()), 0);
      Kinstr ("IMap_iter", IMap_iter (loc, nat_str_pair_t, drop (), halt ()), 0);
      Kinstr ("IMap_mem", IMap_mem (loc, halt ()), 0);
      Kinstr ("IMap_get", IMap_get (loc, halt ()), 0);
      Kinstr ("IMap_update", IMap_update (loc, halt ()), 0);
      Kinstr ("IMap_get_and_update", IMap_get_and_update (loc, halt ()), 0);
      Kinstr ("IMap_size", IMap_size (loc, halt ()), 0);
      Kinstr
        ("IEmpty_big_map", IEmpty_big_map (loc, Nat_t, String_t, halt ()), 0);
      Kinstr ("IBig_map_mem", IBig_map_mem (loc, halt ()), 0);
      Kinstr ("IBig_map_get", IBig_map_get (loc, halt ()), 0);
      Kinstr ("IBig_map_update", IBig_map_update (loc, halt ()), 0);
      Kinstr
        ("IBig_map_get_and_update", IBig_map_get_and_update (loc, halt ()), 0);
      Kinstr ("IConcat_string", IConcat_string (loc, halt ()), 0);
      Kinstr ("IConcat_string_pair", IConcat_string_pair (loc, halt ()), 0);
      Kinstr ("ISlice_string", ISlice_string (loc, halt ()), 0);
      Kinstr ("IString_size", IString_size (loc, halt ()), 0);
      Kinstr ("IConcat_bytes", IConcat_bytes (loc, halt ()), 0);
      Kinstr ("IConcat_bytes_pair", IConcat_bytes_pair (loc, halt ()), 0);
      Kinstr ("ISlice_bytes", ISlice_bytes (loc, halt ()), 0);
      Kinstr ("IBytes_size", IBytes_size (loc, halt ()), 0);
      Kinstr
        ( "IAdd_seconds_to_timestamp ",
          IAdd_seconds_to_timestamp (loc, halt ()),
          0 );
      Kinstr
        ( "IAdd_timestamp_to_seconds",
          IAdd_timestamp_to_seconds (loc, halt ()),
          0 );
      Kinstr ("ISub_timestamp_seconds", ISub_timestamp_seconds (loc, halt ()), 0);
      Kinstr ("IDiff_timestamps", IDiff_timestamps (loc, halt ()), 0);
      Kinstr ("IAdd_tez", IAdd_tez (loc, halt ()), 0);
      Kinstr ("ISub_tez", ISub_tez (loc, halt ()), 0);
      Kinstr ("ISub_tez_legacy", ISub_tez_legacy (loc, halt ()), 0);
      Kinstr ("IMul_tez_nat", IMul_teznat (loc, halt ()), 0);
      Kinstr ("IMul_nattez", IMul_nattez (loc, halt ()), 0);
      Kinstr ("IEdiv_teznat", IEdiv_teznat (loc, halt ()), 0);
      Kinstr ("IEdiv_nattez", IEdiv_tez (loc, halt ()), 0);
      Kinstr ("IOr", IOr (loc, halt ()), 0);
      Kinstr ("IAnd", IAnd (loc, halt ()), 0);
      Kinstr ("IXor", IXor (loc, halt ()), 0);
      Kinstr ("INot", INot (loc, halt ()), 0);
      Kinstr ("IIs_nat", IIs_nat (loc, halt ()), 0);
      Kinstr ("INeg", INeg (loc, halt ()), 0);
      Kinstr ("IAbs_int", IAbs_int (loc, halt ()), 0);
      Kinstr ("IInt_nat", IInt_nat (loc, halt ()), 0);
      Kinstr ("IAdd_int", IAdd_int (loc, halt ()), 0);
      Kinstr ("IAdd_nat", IAdd_nat (loc, halt ()), 0);
      Kinstr ("ISub_int", ISub_int (loc, halt ()), 0);
      Kinstr ("IMul_int", IMul_int (loc, halt ()), 0);
      Kinstr ("IMul_nat", IMul_nat (loc, halt ()), 0);
      Kinstr ("IEdiv_int", IEdiv_int (loc, halt ()), 0);
      Kinstr ("IEdiv_nat", IEdiv_nat (loc, halt ()), 0);
      Kinstr ("ILsl_nat", ILsl_nat (loc, halt ()), 0);
      Kinstr ("ILsr_nat", ILsr_nat (loc, halt ()), 0);
      Kinstr ("IOr_nat", IOr_nat (loc, halt ()), 0);
      Kinstr ("IAnd_nat", IAnd_nat (loc, halt ()), 0);
      Kinstr ("IAnd_int_nat", IAnd_int_nat (loc, halt ()), 0);
      Kinstr ("IXor_nat", IXor_nat (loc, halt ()), 0);
      Kinstr ("INot_int", INot_int (loc, halt ()), 0);
      Kinstr
        ( "IIf",
          IIf
            {
              loc;
              branch_if_true = halt ();
              branch_if_false = halt ();
              k = halt ();
            },
          0 );
      Kinstr ("ILoop", ILoop (loc, const Bool_t true, halt ()), 0);
      Kinstr ("ILoop_left", ILoop_left (loc, INever loc, halt ()), 0);
      Kinstr ("IDip", IDip (loc, halt (), String_t, halt ()), 0);
      Kinstr ("IExec", IExec (loc, Bot_t, halt ()), 0);
      Kinstr ("IApply", IApply (loc, String_t, halt ()), 0);
      Kinstr ("ILambda", ILambda (loc, id_lambda (), halt ()), 0);
      Kinstr ("IFailwith", IFailwith (loc, String_t), 0);
      Kinstr ("ICompare", ICompare (loc, String_t, halt ()), 0);
      Kinstr ("IEq", IEq (loc, halt ()), 0);
      Kinstr ("INeq", INeq (loc, halt ()), 0);
      Kinstr ("ILt", ILt (loc, halt ()), 0);
      Kinstr ("IGt", IGt (loc, halt ()), 0);
      Kinstr ("ILe", ILe (loc, halt ()), 0);
      Kinstr ("IGe", IGe (loc, halt ()), 0);
      Kinstr ("IAddress", IAddress (loc, halt ()), 0);
      Kinstr
        ("IContract", IContract (loc, Unit_t, entrypoint "entry", halt ()), 0);
      Kinstr
        ( "IView",
          IView
            ( loc,
              View_signature
                {
                  name = str "myview";
                  input_ty = unit_option_t ();
                  output_ty = unit_option_t ();
                },
              stack_type (),
              halt () ),
          0 );
      Kinstr ("ITransfer_tokens", ITransfer_tokens (loc, halt ()), 0);
      Kinstr ("IImplicit_account", IImplicit_account (loc, halt ()), 0);
      Kinstr
        ( "ICreate_contract",
          ICreate_contract
            {
              loc;
              storage_type = Unit_t;
              code = Micheline.(strip_locations @@ Seq (loc, []));
              k = halt ();
            },
          0 );
      Kinstr ("ISet_delegate", ISet_delegate (loc, halt ()), 0);
      Kinstr ("INow", INow (loc, halt ()), 0);
      Kinstr ("IMin_block_time", IMin_block_time (loc, halt ()), 0);
      Kinstr ("IBalance", IBalance (loc, halt ()), 0);
      Kinstr ("ILevel", ILevel (loc, halt ()), 0);
      Kinstr ("ICheck_signature", ICheck_signature (loc, halt ()), 0);
      Kinstr ("IHash_key", IHash_key (loc, halt ()), 0);
      Kinstr ("IPack", IPack (loc, Int_t, halt ()), 0);
      Kinstr ("IUnpack", IUnpack (loc, Int_t, halt ()), 0);
      Kinstr ("IBlake2b", IBlake2b (loc, halt ()), 0);
      Kinstr ("ISha_256", ISha256 (loc, halt ()), 0);
      Kinstr ("ISha512", ISha512 (loc, halt ()), 0);
      Kinstr ("ISource", ISource (loc, halt ()), 0);
      Kinstr ("ISender", ISender (loc, halt ()), 0);
      Kinstr ("ISelf", ISelf (loc, Unit_t, entrypoint "entry", halt ()), 0);
      Kinstr ("ISelf_address", ISelf_address (loc, halt ()), 0);
      Kinstr ("IAmount", IAmount (loc, halt ()), 0);
      Kinstr
        ( "ISapling_empty_state",
          ISapling_empty_state (loc, zero_memo_size, halt ()),
          0 );
      Kinstr ("ISapling_verify_update", ISapling_verify_update (loc, halt ()), 0);
      Kinstr
        ( "ISapling_verify_update_deprecated",
          ISapling_verify_update_deprecated (loc, halt ()),
          0 );
      Kinstr ("IDig", IDig (loc, 0, KRest, halt ()), 0);
      Kinstr ("IDug", IDug (loc, 0, KRest, halt ()), 0);
      Kinstr ("IDipn", IDipn (loc, 0, KRest, halt (), halt ()), 0);
      Kinstr ("IDropn", IDropn (loc, 0, KRest, halt ()), 0);
      Kinstr ("IChainId", IChainId (loc, halt ()), 0);
      Kinstr ("INever", INever loc, 0);
      Kinstr ("IVoting_power", IVoting_power (loc, halt ()), 0);
      Kinstr ("ITotal_voting_power", ITotal_voting_power (loc, halt ()), 0);
      Kinstr ("IKeccak", IKeccak (loc, halt ()), 0);
      Kinstr ("ISha3", ISha3 (loc, halt ()), 0);
      Kinstr ("IAdd_bls12_381_g1", IAdd_bls12_381_g1 (loc, halt ()), 0);
      Kinstr ("IAdd_bls12_381_2g", IAdd_bls12_381_g2 (loc, halt ()), 0);
      Kinstr ("IAdd_bls12_381_fr", IAdd_bls12_381_fr (loc, halt ()), 0);
      Kinstr ("IMul_bls12_381_g1", IMul_bls12_381_g1 (loc, halt ()), 0);
      Kinstr ("IMul_bls12_381_g2", IMul_bls12_381_g2 (loc, halt ()), 0);
      Kinstr ("IMul_bls12_381_fr", IMul_bls12_381_fr (loc, halt ()), 0);
      Kinstr ("IMul_bls12_381_z_fr", IMul_bls12_381_z_fr (loc, halt ()), 0);
      Kinstr ("IMul_bls12_381_fr_z", IMul_bls12_381_fr_z (loc, halt ()), 0);
      Kinstr ("IMul_bls12_381_fr_z", IMul_bls12_381_fr_z (loc, halt ()), 0);
      Kinstr ("IInt_bls12_381_fr", IInt_bls12_381_fr (loc, halt ()), 0);
      Kinstr ("INeg_bls12_381_g1", INeg_bls12_381_g1 (loc, halt ()), 0);
      Kinstr ("INeg_bls12_381_g2", INeg_bls12_381_g2 (loc, halt ()), 0);
      Kinstr ("INeg_bls12_381_fr", INeg_bls12_381_fr (loc, halt ()), 0);
      Kinstr
        ("IPairing_check_bls12_381", IPairing_check_bls12_381 (loc, halt ()), 0);
      Kinstr ("IComb", IComb (loc, 0, Comb_one, halt ()), 0);
      Kinstr ("IUncomb", IUncomb (loc, 0, Uncomb_one, halt ()), 0);
      Kinstr ("IComb_get", IComb_get (loc, 0, Comb_get_zero, halt ()), 0);
      Kinstr ("IComb_set", IComb_set (loc, 0, Comb_set_zero, halt ()), 0);
      Kinstr ("IDup_n", IDup_n (loc, 0, Dup_n_zero, halt ()), 0);
      Kinstr ("ITicket", ITicket (loc, Nat_t, halt ()), 0);
      Kinstr ("IRead_ticket", IRead_ticket (loc, Unit_t, halt ()), 0);
      Kinstr ("ISplit_ticket", ISplit_ticket (loc, halt ()), 0);
      Kinstr ("IJoin_tickets", IJoin_tickets (loc, Unit_t, halt ()), 0);
      Kinstr ("IOpen_chest", IOpen_chest (loc, halt ()), 0);
      Kinstr
        ( "IEmit",
          IEmit
            {
              loc;
              addr = Contract_event_repr.Hash.zero;
              tag = entrypoint "entry";
              ty = Unit_t;
              k = halt ();
            },
          0 );
      Kinstr ("IHalt ()", halt (), 0);
    ]

let tests =
  let open Tztest in
  [
    tztest "check value size" `Quick check_value_size;
    tztest "check ty size" `Quick check_ty_size;
    tztest "check kinstr size" `Quick check_kinstr_size;
  ]
