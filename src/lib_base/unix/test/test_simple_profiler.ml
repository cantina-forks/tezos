(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
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

(* Testing
   -------
   Component:    Base, Unix
   Invocation:   dune exec src/lib_base/unix/test/main.exe -- --file test_simple_profiler.ml
   Subject:      Check syslog primitives
*)

open Tezos_base.TzPervasives
open Profiler
module WithExceptions = Tezos_error_monad.TzLwtreslib.WithExceptions
open Lwt_syntax

let print_file_content file_path =
  let rec read_and_print chan =
    try
      let line = input_line chan in
      print_endline line ;
      read_and_print chan
    with
    | End_of_file -> close_in chan
    | ex ->
        close_in chan ;
        raise ex
  in
  try
    let chan = open_in file_path in
    read_and_print chan
  with Sys_error msg ->
    Printf.eprintf "Error: %s\n" msg ;
    Sys.remove file_path

let noop profiler =
  Profiler.record profiler "noop" ;
  Profiler.stop profiler

let sleep10ms profiler =
  Profiler.record profiler "sleep10ms" ;
  print_endline "---sleep10---" ;
  Unix.sleepf 0.01 ;
  noop profiler ;
  Profiler.stop profiler

let sleep70ms profiler =
  Profiler.record profiler "sleep70ms" ;
  print_endline "---sleep70---" ;
  Unix.sleepf 0.07 ;
  Profiler.stop profiler

let foo profiler =
  Profiler.record profiler "foo" ;
  sleep10ms profiler ;
  sleep70ms profiler ;
  sleep10ms profiler ;
  Profiler.stop profiler

let bar profiler =
  Profiler.record profiler "bar" ;
  sleep70ms profiler ;
  sleep10ms profiler ;
  foo profiler ;
  foo profiler ;
  Profiler.stop profiler

let test70 profiler =
  print_endline "\nTEST: test 70\n" ;
  Profiler.record profiler "test70" ;
  bar profiler ;
  foo profiler ;
  Profiler.stop profiler

let sleep_until_next_second () =
  let current_time = Unix.gettimeofday () in
  let time_in_seconds = int_of_float current_time in
  let next_second = time_in_seconds + 1 in
  let remaining_time = float_of_int next_second -. current_time in
  Lwt_unix.sleep remaining_time

let slp tag profiler =
  let* () =
    Profiler.record_s profiler ("slp " ^ tag) (fun () ->
        let ts = Unix.gettimeofday () in
        let ts_ptime =
          WithExceptions.Option.get ~loc:__LOC__ (Ptime.of_float_s ts)
        in
        Format.printf "%a: sleep in %s\n" Time.System.pp_hum ts_ptime tag ;
        let* () = Lwt_unix.sleep 0.01 in
        let ts = Unix.gettimeofday () in
        let ts_ptime =
          WithExceptions.Option.get ~loc:__LOC__ (Ptime.of_float_s ts)
        in
        Format.printf "%a: sleep done\n" Time.System.pp_hum ts_ptime ;
        Lwt.return_unit)
  in
  return_unit

let sequences profiler =
  let* () = Profiler.record_s profiler "a_seq" (fun () -> slp "a_seq" profiler) in
  let* () =
    Profiler.record_s profiler "b_seq" (fun () ->
        let* () = Profiler.record_s profiler "b_a_seq" (fun () -> slp "b_a_seq" profiler) in
        let* () = Profiler.record_s profiler "b_b_seq" (fun () -> slp "b_b_seq" profiler) in
        slp "b_seq" profiler)
  in
  return_unit

let aggregates profiler =
  let* () = Profiler.aggregate_s profiler "a_aggr" (fun () -> slp "a_aggr" profiler) in
  let* () = Profiler.aggregate_s profiler "b_aggr" (fun () -> slp "b_aggr" profiler) in
  let* () =
    Profiler.aggregate_s profiler "a_aggr" (fun () ->
        let* () = Profiler.aggregate_s profiler "a_a_aggr" (fun () -> slp "a_a_aggr" profiler) in
        let* () = Profiler.aggregate_s profiler "a_b_aggr" (fun () -> slp "a_b_aggr" profiler) in
        let* () = Profiler.aggregate_s profiler "a_c_aggr" (fun () -> slp "a_c_aggr" profiler) in
        slp "a_aggr1" profiler)
  in
  let* () =
    Profiler.aggregate_s profiler "a_aggr" (fun () ->
        let* () =
          Profiler.aggregate_s profiler "a_a_aggr" (fun () ->
              Profiler.aggregate_s profiler "a_a_a_aggr" (fun () -> slp "a_a_a_aggr" profiler))
        in
        slp "a_aggr2" profiler)
  in
  return_unit

let buggy_aggregates profiler =
  let t1 = Profiler.aggregate_s profiler "bug_aggr1" (fun () -> slp "bug_aggr1" profiler) in
  let t2 =
    Profiler.aggregate_s profiler "bug_aggr2" (fun () ->
        let* () = slp "bug_aggr2-1" profiler in
        slp "bug_aggr2-2" profiler)
  in
  Lwt.join [t1; t2]

let spans profiler =
  let t1 = Profiler.span_s profiler ["span1"] (fun () -> slp "span1" profiler) in
  let t2 =
    Profiler.span_s profiler ["span2"; "inner1"] (fun () ->
        let* () = slp "span2, inner1/1" profiler in
        slp "span2, inner1/2" profiler)
  in
  let t3 =
    Profiler.span_s profiler ["span2"; "inner2"] (fun () ->
        let* () = slp "span2, inner2/1" profiler in
        slp "span2, inner2/2" profiler)
  in
  Lwt.join [t1; t2; t3]

let sequences_with_mark_and_stamp profiler =
  let* () = Profiler.record_s profiler "a_seq" (fun () -> slp "a_seq" profiler ) in
  let* () =
    Profiler.record_s profiler "b_seq" (fun () ->
        let* () = Profiler.record_s profiler "b_a_seq" (fun () -> slp "b_a_seq" profiler) in
        let () = List.iter (fun _ -> Profiler.mark profiler ["mark"]) (1 -- 10) in
        let () = Profiler.stamp profiler "stamp" in
        let* () = Profiler.record_s profiler "b_b_seq" (fun () -> slp "b_b_seq" profiler) in
        let () = List.iter (fun _ -> Profiler.mark profiler ["mark"]) (1 -- 10) in
        let () = Profiler.stamp profiler "stamp" in
        slp "b_seq" profiler)
  in
  return_unit

let test_profiler_actions profiler =
  print_endline "\nTEST: test_profiler_actions\n" ;
  let main () =
    let* () = sleep_until_next_second () in
    Profiler.record_s profiler "main" (fun () ->
        let* () = sequences profiler in
        let* () = aggregates profiler in
        let* () = buggy_aggregates profiler in
        let* () = spans profiler in
        let* () = sequences_with_mark_and_stamp profiler in
        Lwt.return_unit) in
  Lwt_main.run (main ())

let get_profiler test_name =  
  let profiler = unplugged () in
  let test_profiler_instance =
    Profiler.instance
      Tezos_base_unix.Simple_profiler.auto_write_to_txt_file
      ("/tmp/output_test_simple_profiling_" ^ test_name ^ ".txt", Profiler.Detailed)
  in
  plug profiler test_profiler_instance ;
  profiler

let print_test_results test_name = 
  print_endline ("\nProfiling result for " ^ test_name) ;
  print_endline ("==================================") ;
  print_file_content ("/tmp/output_test_simple_profiling_" ^ test_name ^ ".txt") 

let run_test_with_profiler test_name test_fn =
  let profiler = get_profiler test_name in
  test_fn profiler ;
  print_test_results test_name

let () =
  Tezt_core.Test.register
    ~__FILE__
    ~title:"Simple profiler: basic profiler test"
    ~tags:["unix"; "profiler"]
  @@ fun () ->

  run_test_with_profiler "test_main" test70 ;
  Tezt_core.Base.unit

let () =
  Tezt_core.Test.register
    ~__FILE__
    ~title:"Simple profiler: all profiler actions"
    ~tags:["unix"; "profiler"]
  @@ fun () ->

  run_test_with_profiler "test_main" test_profiler_actions ;

  Tezt_core.Base.unit