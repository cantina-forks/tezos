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

module Encoding = struct
  include Encoding

  type 'a matching_function = 'a -> match_result

  let splitted ~json ~binary = raw_splitted ~json:(Json.convert json) ~binary

  let uint_as_n ?max_value () =
    let json =
      let max_value = (1 lsl 30) - 1 in
      ranged_int 0 max_value
    in
    let binary = uint_as_n ?max_value () in
    splitted ~json ~binary

  let assoc enc =
    let json = Json_encoding.assoc (Json.convert enc) in
    let binary = list (tup2 string enc) in
    raw_splitted ~json ~binary

  module Bounded = struct
    let string length =
      raw_splitted
        ~binary:
          (let kind = Binary_size.unsigned_range_to_size length in
           check_size (length + Binary_size.integer_to_size kind)
           @@ dynamic_size ~kind Variable.string)
        ~json:
          (let open Json_encoding in
          conv
            (fun s ->
              if String.length s > length then invalid_arg "oversized string" ;
              s)
            (fun s ->
              if String.length s > length then
                raise
                  (Cannot_destruct ([], Invalid_argument "oversized string")) ;
              s)
            string)

    let bytes length =
      raw_splitted
        ~binary:
          (let kind = Binary_size.unsigned_range_to_size length in
           check_size (length + Binary_size.integer_to_size kind)
           @@ dynamic_size ~kind Variable.bytes)
        ~json:
          (let open Json_encoding in
          conv
            (fun s ->
              if Bytes.length s > length then invalid_arg "oversized string" ;
              s)
            (fun s ->
              if Bytes.length s > length then
                raise
                  (Cannot_destruct ([], Invalid_argument "oversized string")) ;
              s)
            Json.bytes_jsont)
  end

  type 'a lazy_state = Value of 'a | Bytes of Bytes.t | Both of Bytes.t * 'a

  type 'a lazy_t = {mutable state : 'a lazy_state; encoding : 'a t}

  let force_decode le =
    match le.state with
    | Value value -> Some value
    | Both (_, value) -> Some value
    | Bytes bytes -> (
        match Binary_reader.of_bytes_opt le.encoding bytes with
        | Some expr ->
            le.state <- Both (bytes, expr) ;
            Some expr
        | None -> None)

  let force_bytes le =
    match le.state with
    | Bytes bytes -> bytes
    | Both (bytes, _) -> bytes
    | Value value ->
        let bytes = Binary_writer.to_bytes_exn le.encoding value in
        le.state <- Both (bytes, value) ;
        bytes

  let lazy_encoding encoding =
    let binary =
      Encoding.conv
        force_bytes
        (fun bytes -> {state = Bytes bytes; encoding})
        Encoding.bytes
    in
    let json =
      Encoding.conv
        (fun le ->
          match force_decode le with
          | Some r -> r
          | None ->
              raise
                (Json_encoding.Cannot_destruct
                   ( [],
                     Invalid_argument "error when decoding lazily encoded value"
                   )))
        (fun value -> {state = Value value; encoding})
        encoding
    in
    splitted ~json ~binary

  let make_lazy encoding value = {encoding; state = Value value}

  let apply_lazy ~fun_value ~fun_bytes ~fun_combine le =
    match le.state with
    | Value value -> fun_value value
    | Bytes bytes -> fun_bytes bytes
    | Both (bytes, value) -> fun_combine (fun_value value) (fun_bytes bytes)

  module Compact = Compact

  type 'a compact = 'a Compact.t
end

include Encoding
module With_version = With_version
module Registration = Registration

module Json = struct
  include Json
  include Json_stream
end

module Bson = Bson
module Binary_schema = Binary_schema
module Binary_stream = Binary_stream

module Binary = struct
  include Binary_error_types
  include Binary_error
  include Binary_length
  include Binary_writer
  include Binary_reader
  include Binary_stream_reader
  module Slicer = Binary_slicer

  let describe = Binary_description.describe
end

type json = Json.t

let json = Json.encoding

type json_schema = Json.schema

let json_schema = Json.schema_encoding

type bson = Bson.t
