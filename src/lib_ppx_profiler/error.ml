(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* SPDX-FileCopyrightText: 2024 Nomadic Labs <contact@nomadic-labs.com>      *)
(*                                                                           *)
(*****************************************************************************)

type error =
  | Invalid_payload of Parsetree.payload
  | Invalid_aggregate of Key.t
  | Invalid_mark of Key.t
  | Invalid_record of Key.t
  | Invalid_span of Key.t
  | Invalid_stop of Key.t
  | Improper_let_binding of Ppxlib.expression
  | Malformed_attribute

let error loc err =
  let msg, hint =
    match err with
    | Invalid_payload payload ->
        ( "Invalid or empty attribute payload.",
          Format.asprintf
            "@[<v 2>Accepted attributes payload are:@,\
             - `[@profiler.aggregate_* <string or ident>]@,\
             - `[@profiler.mark [<list of strings>]]@,\
             - `[@profiler.record_* <string or ident>]@,\
             Found: %a@."
            Pprintast.payload
            payload )
    | Invalid_aggregate key ->
        ( "Invalid aggregate.",
          Format.asprintf
            "@[<v 2>A [@profiler.aggregate_*] attribute must be a string or an \
             identifier.@,\
             Found %a@."
            Key.pp
            key )
    | Invalid_mark key ->
        ( "Invalid mark.",
          Format.asprintf
            "@[<v 2>A [@profiler.mark] attribute must be a string list.@,\
             Found %a@."
            Key.pp
            key )
    | Invalid_record key ->
        ( "Invalid record.",
          Format.asprintf
            "@[<v 2>A [@profiler.record_*] attribute must be a string or an \
             identifier.@,\
             Found %a@."
            Key.pp
            key )
    | Invalid_span key ->
        ( "Invalid span.",
          Format.asprintf
            "@[<v 2>A [@profiler.span_*] attribute must be a string list.@,\
             Found %a@."
            Key.pp
            key )
    | Invalid_stop key ->
        ( "Invalid stop.",
          Format.asprintf
            "@[<v 2>A [@profiler.stop] should not have an attribute.@,\
             Found %a@."
            Key.pp
            key )
    | Improper_let_binding expr ->
        ( "Improper let binding expression.",
          Format.asprintf
            "@[<v 2>Expecting a let binding expression.@,Found %a@."
            Pprintast.expression
            expr )
    | Malformed_attribute ->
        ( "Malformed attribute.",
          Format.sprintf
            "@[<v 2>Accepted attributes payload are:@,\
             - `[@profiling.mark [<list of strings>]]'@,\
             - `[@profiling.aggregate_* <string or ident>]'" )
  in
  Location.raise_errorf ~loc "profiling_ppx: %s\nHint: %s" msg hint
