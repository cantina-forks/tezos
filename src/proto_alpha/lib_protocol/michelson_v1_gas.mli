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

open Alpha_context

module Cost_of : sig
  val manager_operation : Gas.cost

  module Interpreter : sig
    val drop : Gas.cost

    val dup : Gas.cost

    val swap : Gas.cost

    val cons_some : Gas.cost

    val cons_none : Gas.cost

    val if_none : Gas.cost

    val cons_pair : Gas.cost

    val unpair : Gas.cost

    val car : Gas.cost

    val cdr : Gas.cost

    val cons_left : Gas.cost

    val cons_right : Gas.cost

    val if_left : Gas.cost

    val cons_list : Gas.cost

    val nil : Gas.cost

    val if_cons : Gas.cost

    val list_map : 'a Script_typed_ir.boxed_list -> Gas.cost

    val list_size : Gas.cost

    val list_iter : 'a Script_typed_ir.boxed_list -> Gas.cost

    val empty_set : Gas.cost

    val set_iter : 'a Script_typed_ir.set -> Gas.cost

    val set_mem : 'a -> 'a Script_typed_ir.set -> Gas.cost

    val set_update : 'a -> 'a Script_typed_ir.set -> Gas.cost

    val set_size : Gas.cost

    val empty_map : Gas.cost

    val map_map : ('k, 'v) Script_typed_ir.map -> Gas.cost

    val map_iter : ('k, 'v) Script_typed_ir.map -> Gas.cost

    val map_mem : 'k -> ('k, 'v) Script_typed_ir.map -> Gas.cost

    val map_get : 'k -> ('k, 'v) Script_typed_ir.map -> Gas.cost

    val map_update : 'k -> ('k, 'v) Script_typed_ir.map -> Gas.cost

    val map_get_and_update : 'k -> ('k, 'v) Script_typed_ir.map -> Gas.cost

    val big_map_mem : (_, _) Script_typed_ir.big_map_overlay -> Gas.cost

    val big_map_get : (_, _) Script_typed_ir.big_map_overlay -> Gas.cost

    val big_map_update : (_, _) Script_typed_ir.big_map_overlay -> Gas.cost

    val big_map_get_and_update :
      (_, _) Script_typed_ir.big_map_overlay -> Gas.cost

    val map_size : Gas.cost

    val add_seconds_timestamp :
      'a Script_int.num -> Script_timestamp.t -> Gas.cost

    val add_timestamp_seconds :
      Script_timestamp.t -> 'a Script_int.num -> Gas.cost

    val sub_timestamp_seconds :
      Script_timestamp.t -> 'a Script_int.num -> Gas.cost

    val diff_timestamps : Script_timestamp.t -> Script_timestamp.t -> Gas.cost

    val concat_string_pair : Script_string.t -> Script_string.t -> Gas.cost

    val slice_string : Script_string.t -> Gas.cost

    val string_size : Gas.cost

    val concat_bytes_pair : bytes -> bytes -> Gas.cost

    val slice_bytes : bytes -> Gas.cost

    val bytes_size : Gas.cost

    val add_tez : Gas.cost

    val sub_tez : Gas.cost

    val mul_teznat : Gas.cost

    val mul_nattez : Gas.cost

    val bool_or : Gas.cost

    val bool_and : Gas.cost

    val bool_xor : Gas.cost

    val bool_not : Gas.cost

    val is_nat : Gas.cost

    val abs_int : Alpha_context.Script_int.z Script_int.num -> Gas.cost

    val int_nat : Gas.cost

    val neg_int : Alpha_context.Script_int.z Script_int.num -> Gas.cost

    val neg_nat : Alpha_context.Script_int.n Script_int.num -> Gas.cost

    val add_intint :
      Alpha_context.Script_int.z Script_int.num ->
      Alpha_context.Script_int.z Script_int.num ->
      Gas.cost

    val add_intnat :
      Alpha_context.Script_int.z Script_int.num ->
      Alpha_context.Script_int.n Script_int.num ->
      Gas.cost

    val add_natint :
      Alpha_context.Script_int.n Script_int.num ->
      Alpha_context.Script_int.z Script_int.num ->
      Gas.cost

    val add_natnat :
      Alpha_context.Script_int.n Script_int.num ->
      Alpha_context.Script_int.n Script_int.num ->
      Gas.cost

    val sub_int : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val mul_intint :
      Alpha_context.Script_int.z Script_int.num ->
      Alpha_context.Script_int.z Script_int.num ->
      Gas.cost

    val mul_intnat :
      Alpha_context.Script_int.z Script_int.num ->
      Alpha_context.Script_int.n Script_int.num ->
      Gas.cost

    val mul_natint :
      Alpha_context.Script_int.n Script_int.num ->
      Alpha_context.Script_int.z Script_int.num ->
      Gas.cost

    val mul_natnat :
      Alpha_context.Script_int.n Script_int.num ->
      Alpha_context.Script_int.n Script_int.num ->
      Gas.cost

    val ediv_teznat : 'a -> 'b Script_int.num -> Gas.cost

    val ediv_tez : Gas.cost

    val ediv_intint :
      Alpha_context.Script_int.z Script_int.num ->
      Alpha_context.Script_int.z Script_int.num ->
      Gas.cost

    val ediv_intnat :
      Alpha_context.Script_int.z Script_int.num ->
      Alpha_context.Script_int.n Script_int.num ->
      Gas.cost

    val ediv_natint :
      Alpha_context.Script_int.n Script_int.num ->
      Alpha_context.Script_int.z Script_int.num ->
      Gas.cost

    val ediv_natnat :
      Alpha_context.Script_int.n Script_int.num ->
      Alpha_context.Script_int.n Script_int.num ->
      Gas.cost

    val eq : Gas.cost

    val lsl_nat : 'a Script_int.num -> Gas.cost

    val lsr_nat : 'a Script_int.num -> Gas.cost

    val or_nat : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val and_nat : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val and_int_nat :
      Alpha_context.Script_int.z Script_int.num ->
      Alpha_context.Script_int.n Script_int.num ->
      Gas.cost

    val xor_nat : 'a Script_int.num -> 'b Script_int.num -> Gas.cost

    val not_int : 'a Script_int.num -> Gas.cost

    val not_nat : 'a Script_int.num -> Gas.cost

    val if_ : Gas.cost

    val loop : Gas.cost

    val loop_left : Gas.cost

    val dip : Gas.cost

    val check_signature : Signature.public_key -> bytes -> Gas.cost

    val blake2b : bytes -> Gas.cost

    val sha256 : bytes -> Gas.cost

    val sha512 : bytes -> Gas.cost

    val dign : int -> Gas.cost

    val dugn : int -> Gas.cost

    val dipn : int -> Gas.cost

    val dropn : int -> Gas.cost

    val voting_power : Gas.cost

    val total_voting_power : Gas.cost

    val keccak : bytes -> Gas.cost

    val sha3 : bytes -> Gas.cost

    val add_bls12_381_g1 : Gas.cost

    val add_bls12_381_g2 : Gas.cost

    val add_bls12_381_fr : Gas.cost

    val mul_bls12_381_g1 : Gas.cost

    val mul_bls12_381_g2 : Gas.cost

    val mul_bls12_381_fr : Gas.cost

    val mul_bls12_381_fr_z : 'a Script_int.num -> Gas.cost

    val mul_bls12_381_z_fr : 'a Script_int.num -> Gas.cost

    val int_bls12_381_fr : Gas.cost

    val neg_bls12_381_g1 : Gas.cost

    val neg_bls12_381_g2 : Gas.cost

    val neg_bls12_381_fr : Gas.cost

    val neq : Gas.cost

    val pairing_check_bls12_381 : 'a Script_typed_ir.boxed_list -> Gas.cost

    val comb : int -> Gas.cost

    val uncomb : int -> Gas.cost

    val comb_get : int -> Gas.cost

    val comb_set : int -> Gas.cost

    val dupn : int -> Gas.cost

    val compare : 'a Script_typed_ir.comparable_ty -> 'a -> 'a -> Gas.cost

    val concat_string_precheck : 'a Script_typed_ir.boxed_list -> Gas.cost

    val concat_string :
      Saturation_repr.may_saturate Saturation_repr.t -> Gas.cost

    val concat_bytes :
      Saturation_repr.may_saturate Saturation_repr.t -> Gas.cost

    val halt : Gas.cost

    val const : Gas.cost

    val empty_big_map : Gas.cost

    val lt : Gas.cost

    val le : Gas.cost

    val gt : Gas.cost

    val ge : Gas.cost

    val exec : Gas.cost

    val apply : Gas.cost

    val lambda : Gas.cost

    val address : Gas.cost

    val contract : Gas.cost

    val transfer_tokens : Gas.cost

    val implicit_account : Gas.cost

    val create_contract : Gas.cost

    val set_delegate : Gas.cost

    val balance : Gas.cost

    val level : Gas.cost

    val now : Gas.cost

    val hash_key : Signature.Public_key.t -> Gas.cost

    val source : Gas.cost

    val sender : Gas.cost

    val self : Gas.cost

    val self_address : Gas.cost

    val amount : Gas.cost

    val chain_id : Gas.cost

    val unpack : bytes -> Gas.cost

    val unpack_failed : bytes -> Gas.cost

    val sapling_empty_state : Gas.cost

    val sapling_verify_update : inputs:int -> outputs:int -> Gas.cost

    val ticket : Gas.cost

    val read_ticket : Gas.cost

    val split_ticket :
      'a Script_int.num -> 'a Script_int.num -> 'a Script_int.num -> Gas.cost

    val join_tickets :
      'a Script_typed_ir.comparable_ty ->
      'a Script_typed_ir.ticket ->
      'a Script_typed_ir.ticket ->
      Gas.cost

    module Control : sig
      val nil : Gas.cost

      val cons : Gas.cost

      val return : Gas.cost

      val undip : Gas.cost

      val loop_in : Gas.cost

      val loop_in_left : Gas.cost

      val iter : Gas.cost

      val list_enter_body : 'a list -> int -> Gas.cost

      val list_exit_body : Gas.cost

      val map_enter_body : Gas.cost

      val map_exit_body : 'k -> ('k, 'v) Script_typed_ir.map -> Gas.cost
    end
  end

  module Typechecking : sig
    val public_key_optimized : Gas.cost

    val public_key_readable : Gas.cost

    val key_hash_optimized : Gas.cost

    val key_hash_readable : Gas.cost

    val signature_optimized : Gas.cost

    val signature_readable : Gas.cost

    val chain_id_optimized : Gas.cost

    val chain_id_readable : Gas.cost

    val address_optimized : Gas.cost

    val contract_optimized : Gas.cost

    val contract_readable : Gas.cost

    val bls12_381_g1 : Gas.cost

    val bls12_381_g2 : Gas.cost

    val bls12_381_fr : Gas.cost

    val check_printable : string -> Gas.cost

    val merge_cycle : Gas.cost

    val parse_type_cycle : Gas.cost

    val parse_instr_cycle : Gas.cost

    val parse_data_cycle : Gas.cost

    val comparable_ty_of_ty_cycle : Gas.cost

    val check_dupable_cycle : Gas.cost

    val bool : Gas.cost

    val unit : Gas.cost

    val timestamp_readable : Gas.cost

    val contract : Gas.cost

    val contract_exists : Gas.cost

    val proof_argument : int -> Gas.cost
  end

  module Unparsing : sig
    val public_key_optimized : Gas.cost

    val public_key_readable : Gas.cost

    val key_hash_optimized : Gas.cost

    val key_hash_readable : Gas.cost

    val signature_optimized : Gas.cost

    val signature_readable : Gas.cost

    val chain_id_optimized : Gas.cost

    val chain_id_readable : Gas.cost

    val timestamp_readable : Gas.cost

    val address_optimized : Gas.cost

    val contract_optimized : Gas.cost

    val contract_readable : Gas.cost

    val bls12_381_g1 : Gas.cost

    val bls12_381_g2 : Gas.cost

    val bls12_381_fr : Gas.cost

    val unparse_type_cycle : Gas.cost

    val unparse_instr_cycle : Gas.cost

    val unparse_data_cycle : Gas.cost

    val unit : Gas.cost

    val contract : Gas.cost

    val operation : bytes -> Gas.cost

    val sapling_transaction : Sapling.transaction -> Gas.cost

    val sapling_diff : Sapling.diff -> Gas.cost
  end
end
