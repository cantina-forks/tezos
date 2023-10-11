(*****************************************************************************)
(*                                                                           *)
(* MIT License                                                               *)
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

open Plonk.List
module Helpers = Plonk_test.Helpers

let rng6 = [1; 2; 3; 4; 5; 6]

let list_tests () =
  let left, right = split_n 2 rng6 in
  assert (List.equal ( = ) [1; 2] left) ;
  assert (List.equal ( = ) [3; 4; 5; 6] right) ;

  let left, right = split_in_half rng6 in
  assert (List.equal ( = ) [1; 2; 3] left) ;
  assert (List.equal ( = ) [4; 5; 6] right) ;

  assert (
    21 * 21 = fold_left3 (fun acc a b c -> acc + (a * b * c)) 0 rng6 rng6 rng6)

module Fr_generation = struct
  module Scalar = Kzg.Bls.Scalar
  module Scalar_set = Set.Make (Scalar)
  open Kzg.Utils

  let test_powers () =
    let n = 256 in
    let x = Scalar.random () in
    let ps = Fr_generation.powers n x in
    assert (Array.length ps = n) ;
    assert (Scalar.eq Scalar.one ps.(0)) ;
    for i = 1 to n - 1 do
      assert (ps.(i) = Scalar.mul ps.(i - 1) x)
    done

  let test_random_fr () =
    let transcript =
      Transcript.expand Scalar.t (Scalar.random ()) Transcript.empty
    in
    (* check that the transcript changes after sampling *)
    let x, new_transcript = Fr_generation.random_fr transcript in
    assert (not @@ Transcript.equal transcript new_transcript) ;
    (* check that different transcripts lead to different elements (w.h.p.) *)
    let y, _ = Fr_generation.random_fr new_transcript in
    assert (not @@ Scalar.eq x y) ;
    (* check that random_fr and random_fr_list are consistent when only
       one element is sampled *)
    let l, new_transcript' = Fr_generation.random_fr_list transcript 1 in
    assert (Transcript.equal new_transcript new_transcript') ;
    (match l with [x'] -> assert (Scalar.eq x x') | _ -> assert false) ;
    (* check that all outputs of random_fr_list are different (w.h.p.) *)
    let n = 100 in
    let l, _ = Fr_generation.random_fr_list transcript n in
    let dedup_l = List.sort_uniq Scalar.compare l in
    assert (List.length dedup_l = n)

  (* generates the subgroup generated by the default 2^n-th root of unity
     sampled in bls12-381-polynomial fr_generation *)
  let subgroup_H n =
    let w = Domain.primitive_root_of_unity (1 lsl n) in
    Fr_generation.powers (1 lsl n) w |> Array.to_list |> Scalar_set.of_list

  (* check that the subgroup generated by the default 2^n-th root of unity
     leads to disjoint sets when shifted by any of the first k default
     quadratic non-residues *)
  let test_disjoint_shifted_subgroups k n =
    let non_residues = Fr_generation.build_quadratic_non_residues k in
    let sH = subgroup_H n in
    let subgroups =
      Array.map (fun nr -> Scalar_set.map (Scalar.mul nr) sH) non_residues
    in
    for i = 0 to k - 1 do
      for j = i + 1 to k - 1 do
        assert (Scalar_set.disjoint subgroups.(i) subgroups.(j))
      done
    done

  let test_quadratic_non_residues () =
    (* we set k = 3 because we use PLONK we an architecture of 3 wires *)
    let k = 3 in
    for n = 0 to 16 do
      test_disjoint_shifted_subgroups k n
    done

  let test_quadratic_non_residues_slow () =
    (* we set k = 3 because we use PLONK we an architecture of 3 wires *)
    let k = 3 in
    for n = 17 to 21 do
      test_disjoint_shifted_subgroups k n
    done

  let tests =
    Alcotest.
      [
        test_case "powers" `Quick test_powers;
        test_case "random_fr" `Quick test_random_fr;
        test_case "quadratic_non_residues" `Quick test_quadratic_non_residues;
        test_case
          "quadratic_non_residues_slow"
          `Slow
          test_quadratic_non_residues_slow;
      ]
end

let tests =
  Alcotest.(test_case "List.ml" `Quick list_tests) :: Fr_generation.tests
