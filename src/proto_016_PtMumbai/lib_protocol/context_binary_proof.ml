(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Nomadic Labs <contact@nomadic-labs.com>                *)
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

type error += Expected_binary_proof

let () =
  register_error_kind
    `Permanent
    ~id:"Expected_binary_proof"
    ~title:"Expected binary proof"
    ~description:"An invalid proof has been submitted"
    Data_encoding.empty
    (function Expected_binary_proof -> Some () | _ -> None)
    (fun () -> Expected_binary_proof)

(* TODO: https://gitlab.com/tezos/tezos/-/issues/4386 Extracted and
   adapted from {!Tezos_context_memory}. Ideally, this function should
   be exported there.

   In a nutshell, the context library exposed by the environment is
   implemented such that it can verify proofs generated by both
   [Context] and [Context_binary], and the only thing that
   differentiate these proofs from its perspective is the second bit
   of the [version] field of the proof.

   To ensure we only consider proofs computed against a binary tree,
   we check said bit. This prevents a 32-ary proof to be accepted by
   the protocol in the case where a given key-value store has the same
   hash with both [Context] and [Context_binary] (something that
   happens when the tree contains only one entry). *)
let check_is_binary proof =
  let extract_bit v mask = Compare.Int.(v land mask <> 0) in
  let binary_mask = 0b10 in
  let is_binary = extract_bit proof.Context.Proof.version binary_mask in
  error_unless is_binary Expected_binary_proof
