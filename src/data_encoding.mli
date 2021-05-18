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

(** Type-safe serialization and deserialization of data structures. *)

(** {1 Data Encoding} *)

(** {2 Overview}

    This module provides type-safe serialization and deserialization of
    data structures. Backends are provided to both /ad hoc/ binary, JSON
    and BSON.

    This works by writing type descriptors by hand, using the provided
    combinators. These combinators can fine-tune the binary
    representation to be compact and efficient, but also provide
    proper field names and meta information. As a result, an API that uses
    those descriptors can be automatically introspected and documented.

    Here is an example encoding for type [(int * string)].

    [let enc = obj2 (req "code" uint16) (req "message" string)]

    In JSON, this encoding maps values of type [int * string] to JSON
    objects with a field [code] whose value is a number and a field
    [message] whose value is a string.

    In binary, this encoding maps to two raw bytes for the [int]
    followed by the size of the string in bytes, and finally the raw
    contents of the string. This binary format is mostly tagless,
    meaning that serialized data cannot be interpreted without the
    encoding that was used for serialization.

    Regarding binary serialization, encodings are classified as either:
    - fixed size (booleans, integers, numbers)
      data is always the same size for that type ;
    - dynamically sized (arbitrary strings and bytes)
      data is of unknown size and requires an explicit length field ;
    - variable size (special case of strings, bytes, and arrays)
      data makes up the remainder of an object of known size,
      thus its size is given by the context, and does not
      have to be serialized.

    JSON operations are delegated to [json-data-encoding]. *)

(** {2 Module structure}

    This [Data_encoding] module provides multiple submodules:
    - [Encoding] contains the necessary types and constructors for making the
    type descriptors.
    - [Json], [Bson], and [Binary] contain functions to serialize and
    deserialize values.

*)

module Encoding : sig
  (** The type descriptors for values of type ['a]. *)
  type 'a t = 'a Encoding.t

  type 'a encoding = 'a t

  (** {3 Ground descriptors} *)

  (** {4 voids} *)

  (** Special value [null] in JSON, nothing in binary. *)
  val null : unit encoding

  (** Empty object (not included in binary, encoded as empty object in JSON). *)
  val empty : unit encoding

  (** Unit value, omitted in binary.
      Serialized as an empty object in JSON, accepts any object when deserializing. *)
  val unit : unit encoding

  (** Constant string (data is not included in the binary data). *)
  val constant : string -> unit encoding

  (** {4 ground numerical types}

      All encodings are big-endians.

      - 8-bit integers (signed or unsigned) are encoded over 1 single byte.
      - 16-bit integers (signed or unsigned) are encoded over 2 bytes.
      - 31-bit integers are always signed and always encoded over 4 bytes.
      - 32-bit integers are always signed and always encoded over 4 bytes.
      - 64-bit integers are always signed and always encoded over 8 bytes.

      A note on 31-bit integers. The internal representation of integers in
      OCaml reserves one bit for GC tagging. The remaining bits encode a signed
      integer. For compatibility with 32-bit machine, we restrict these native
      integers to the 31-bit range. *)

  (** Signed 8 bit integer
      (data is encoded as a byte in binary and an integer in JSON). *)
  val int8 : int encoding

  (** Unsigned 8 bit integer
      (data is encoded as a byte in binary and an integer in JSON). *)
  val uint8 : int encoding

  (** Signed 16 bit integer
      (data is encoded as a short in binary and an integer in JSON). *)
  val int16 : int encoding

  (** Unsigned 16 bit integer
      (data is encoded as a short in binary and an integer in JSON). *)
  val uint16 : int encoding

  (** Signed 31 bit integer, which corresponds to type int on 32-bit OCaml systems
      (data is encoded as a 32 bit int in binary and an integer in JSON). *)
  val int31 : int encoding

  (** Signed 32 bit integer
      (data is encoded as a 32-bit int in binary and an integer in JSON). *)
  val int32 : int32 encoding

  (** Signed 64 bit integer
      (data is encoded as a 64-bit int in binary and a decimal string in JSON). *)
  val int64 : int64 encoding

  (** Integer with bounds in a given range. Both bounds are inclusive.

      @raise Invalid_argument if the bounds are beyond the interval
      [-2^30; 2^30-1]. These bounds are chosen to be compatible with all versions
      of OCaml.
  *)
  val ranged_int : int -> int -> int encoding

  (** Big number
      In JSON, data is encoded as a decimal string.
      In binary, data is encoded as a variable length sequence of
      bytes, with a running unary size bit: the most significant bit of
      each byte tells is this is the last byte in the sequence (0) or if
      there is more to read (1). The second most significant bit of the
      first byte is reserved for the sign (positive if zero). Binary_size and
      sign bits ignored, data is then the binary representation of the
      absolute value of the number in little-endian order. *)
  val z : Z.t encoding

  (** Positive big number, see [z]. *)
  val n : Z.t encoding

  (** Encoding of floating point number
      (encoded as a floating point number in JSON and a double in binary). *)
  val float : float encoding

  (** Float with bounds in a given range. Both bounds are inclusive *)
  val ranged_float : float -> float -> float encoding

  (** {4 Other ground type encodings} *)

  (** Encoding of a boolean
      (data is encoded as a byte in binary and a boolean in JSON). *)
  val bool : bool encoding

  (** Encoding of a string
      - encoded as a byte sequence in binary prefixed by the length
        of the string
      - encoded as a string in JSON. *)
  val string : string encoding

  (** Encoding of arbitrary bytes
      (encoded via hex in JSON and directly as a sequence byte in binary). *)
  val bytes : Bytes.t encoding

  (** {3 Descriptor combinators} *)

  (** Combinator to make an optional value
      (represented as a 1-byte tag followed by the data (or nothing) in binary
       and either the raw value or an empty object in JSON). *)
  val option : 'a encoding -> 'a option encoding

  (** Combinator to make a {!result} value
      (represented as a 1-byte tag followed by the data of either type in binary,
       and either unwrapped value in JSON (the caller must ensure that both
       encodings do not collide)). *)
  val result : 'a encoding -> 'b encoding -> ('a, 'b) result encoding

  (** Array combinator.
      - encoded as an array in JSON
      - encoded as the concatenation of all the element in binary
       prefixed its length in bytes

      If [max_length] is passed and the encoding of elements has fixed
      size, a {!check_size} is automatically added for earlier rejection.

      @raise Invalid_argument if the inner encoding is variable. *)
  val array : ?max_length:int -> 'a encoding -> 'a array encoding

  (** List combinator.
      - encoded as an array in JSON
      - encoded as the concatenation of all the element in binary
       prefixed its length in bytes

      If [max_length] is passed and the encoding of elements has fixed
      size, a {!check_size} is automatically added for earlier rejection.

      @raise Invalid_argument if the inner encoding is also variable. *)
  val list : ?max_length:int -> 'a encoding -> 'a list encoding

  (** Provide a transformer from one encoding to a different one.

      Used to simplify nested encodings or to change the generic tuples
      built by {!obj1}, {!tup1} and the like into proper records.

      A schema may optionally be provided as documentation of the new encoding. *)
  val conv :
    ('a -> 'b) ->
    ('b -> 'a) ->
    ?schema:Json_schema.schema ->
    'b encoding ->
    'a encoding

  (** Association list.
      An object in JSON, a list of pairs in binary. *)
  val assoc : 'a encoding -> (string * 'a) list encoding

  (** {3 Product descriptors} *)

  (** An enriched encoding to represent a component in a structured
      type, augmenting the encoding with a name and whether it is a
      required or optional. Fields are used to encode OCaml tuples as
      objects in JSON, and as sequences in binary, using combinator
      {!obj1} and the like. *)
  type 'a field

  (** Required field. *)
  val req :
    ?title:string -> ?description:string -> string -> 't encoding -> 't field

  (** Optional field. Omitted entirely in JSON encoding if None.
      Omitted in binary if the only optional field in a [`Variable]
      encoding, otherwise a 1-byte prefix (`0` or `255`) tells if the
      field is present or not. *)
  val opt :
    ?title:string ->
    ?description:string ->
    string ->
    't encoding ->
    't option field

  (** Optional field of variable length.
      Only one can be present in a given object. *)
  val varopt :
    ?title:string ->
    ?description:string ->
    string ->
    't encoding ->
    't option field

  (** Required field with a default value.
      If the default value is passed, the field is omitted in JSON.
      The value is always serialized in binary. *)
  val dft :
    ?title:string ->
    ?description:string ->
    string ->
    't encoding ->
    't ->
    't field

  (** {4 Constructors for objects with N fields} *)

  (** These are serialized to binary by converting each internal
      object to binary and placing them in the order of the original
      object. These are serialized to JSON as a JSON object with the
      field names. An object might only contains one 'variable'
      field, typically the last one. If the encoding of more than one
      field are 'variable', the first ones should be wrapped with
      [dynamic_size].

      @raise Invalid_argument if more than one field is a variable one. *)

  val obj1 : 'f1 field -> 'f1 encoding

  val obj2 : 'f1 field -> 'f2 field -> ('f1 * 'f2) encoding

  val obj3 : 'f1 field -> 'f2 field -> 'f3 field -> ('f1 * 'f2 * 'f3) encoding

  val obj4 :
    'f1 field ->
    'f2 field ->
    'f3 field ->
    'f4 field ->
    ('f1 * 'f2 * 'f3 * 'f4) encoding

  val obj5 :
    'f1 field ->
    'f2 field ->
    'f3 field ->
    'f4 field ->
    'f5 field ->
    ('f1 * 'f2 * 'f3 * 'f4 * 'f5) encoding

  val obj6 :
    'f1 field ->
    'f2 field ->
    'f3 field ->
    'f4 field ->
    'f5 field ->
    'f6 field ->
    ('f1 * 'f2 * 'f3 * 'f4 * 'f5 * 'f6) encoding

  val obj7 :
    'f1 field ->
    'f2 field ->
    'f3 field ->
    'f4 field ->
    'f5 field ->
    'f6 field ->
    'f7 field ->
    ('f1 * 'f2 * 'f3 * 'f4 * 'f5 * 'f6 * 'f7) encoding

  val obj8 :
    'f1 field ->
    'f2 field ->
    'f3 field ->
    'f4 field ->
    'f5 field ->
    'f6 field ->
    'f7 field ->
    'f8 field ->
    ('f1 * 'f2 * 'f3 * 'f4 * 'f5 * 'f6 * 'f7 * 'f8) encoding

  val obj9 :
    'f1 field ->
    'f2 field ->
    'f3 field ->
    'f4 field ->
    'f5 field ->
    'f6 field ->
    'f7 field ->
    'f8 field ->
    'f9 field ->
    ('f1 * 'f2 * 'f3 * 'f4 * 'f5 * 'f6 * 'f7 * 'f8 * 'f9) encoding

  val obj10 :
    'f1 field ->
    'f2 field ->
    'f3 field ->
    'f4 field ->
    'f5 field ->
    'f6 field ->
    'f7 field ->
    'f8 field ->
    'f9 field ->
    'f10 field ->
    ('f1 * 'f2 * 'f3 * 'f4 * 'f5 * 'f6 * 'f7 * 'f8 * 'f9 * 'f10) encoding

  (** Create a larger object from the encodings of two smaller ones.
      @raise Invalid_argument if both arguments are not objects  or if both
      tuples contains a variable field.. *)
  val merge_objs : 'o1 encoding -> 'o2 encoding -> ('o1 * 'o2) encoding

  (** {4 Constructors for tuples with N fields} *)

  (** These are serialized to binary by converting each internal
      object to binary and placing them in the order of the original
      object. These are serialized to JSON as JSON arrays/lists.  Like
      objects, a tuple might only contains one 'variable' field,
      typically the last one. If the encoding of more than one field
      are 'variable', the first ones should be wrapped with
      [dynamic_size].

      @raise Invalid_argument if more than one field is a variable one. *)

  val tup1 : 'f1 encoding -> 'f1 encoding

  val tup2 : 'f1 encoding -> 'f2 encoding -> ('f1 * 'f2) encoding

  val tup3 :
    'f1 encoding -> 'f2 encoding -> 'f3 encoding -> ('f1 * 'f2 * 'f3) encoding

  val tup4 :
    'f1 encoding ->
    'f2 encoding ->
    'f3 encoding ->
    'f4 encoding ->
    ('f1 * 'f2 * 'f3 * 'f4) encoding

  val tup5 :
    'f1 encoding ->
    'f2 encoding ->
    'f3 encoding ->
    'f4 encoding ->
    'f5 encoding ->
    ('f1 * 'f2 * 'f3 * 'f4 * 'f5) encoding

  val tup6 :
    'f1 encoding ->
    'f2 encoding ->
    'f3 encoding ->
    'f4 encoding ->
    'f5 encoding ->
    'f6 encoding ->
    ('f1 * 'f2 * 'f3 * 'f4 * 'f5 * 'f6) encoding

  val tup7 :
    'f1 encoding ->
    'f2 encoding ->
    'f3 encoding ->
    'f4 encoding ->
    'f5 encoding ->
    'f6 encoding ->
    'f7 encoding ->
    ('f1 * 'f2 * 'f3 * 'f4 * 'f5 * 'f6 * 'f7) encoding

  val tup8 :
    'f1 encoding ->
    'f2 encoding ->
    'f3 encoding ->
    'f4 encoding ->
    'f5 encoding ->
    'f6 encoding ->
    'f7 encoding ->
    'f8 encoding ->
    ('f1 * 'f2 * 'f3 * 'f4 * 'f5 * 'f6 * 'f7 * 'f8) encoding

  val tup9 :
    'f1 encoding ->
    'f2 encoding ->
    'f3 encoding ->
    'f4 encoding ->
    'f5 encoding ->
    'f6 encoding ->
    'f7 encoding ->
    'f8 encoding ->
    'f9 encoding ->
    ('f1 * 'f2 * 'f3 * 'f4 * 'f5 * 'f6 * 'f7 * 'f8 * 'f9) encoding

  val tup10 :
    'f1 encoding ->
    'f2 encoding ->
    'f3 encoding ->
    'f4 encoding ->
    'f5 encoding ->
    'f6 encoding ->
    'f7 encoding ->
    'f8 encoding ->
    'f9 encoding ->
    'f10 encoding ->
    ('f1 * 'f2 * 'f3 * 'f4 * 'f5 * 'f6 * 'f7 * 'f8 * 'f9 * 'f10) encoding

  (** Create a large tuple encoding from two smaller ones.
      @raise Invalid_argument if both values are not tuples or if both
      tuples contains a variable field. *)
  val merge_tups : 'a1 encoding -> 'a2 encoding -> ('a1 * 'a2) encoding

  (** {3 Sum descriptors} *)

  (** A partial encoding to represent a case in a variant type.  Hides
      the (existentially bound) type of the parameter to the specific
      case, providing its encoder, and converter functions to and from
      the union type. *)
  type 't case

  type case_tag = Tag of int | Json_only

  (** A sum descriptor can be optimized by providing a specific
     [matching_function] which efficiently determines in which case
     some value of type ['a] falls.

     Note that in general you should use a total function (i.e., one defined
     over the whole of the ['a] type) for the [matching_function]. However, in
     the case where you have a good reason to use a partial function, you should
     raise {!No_case_matched} in the dead branches. Reasons why you may want to
     do so include:
     - ['a] is an open variant and you will complete the matching function
       later, and
     - there is a code invariant that guarantees that ['a] is not fully
       inhabited.
     *)
  type 'a matching_function = 'a -> match_result

  and match_result

  (** [matched t e u] represents the fact that a value is tagged with [t] and
      carries the payload [u] which can be encoded with [e].

      The optional argument [tag_size] must match the one passed to the
      {!matching} function [matched] is called inside of.

      An example is given in the documentation of {!matching}.

      @raise [Invalid_argument] if [t < 0]

      @raise [Invalid_argument] if [t] does not fit in [tag_size] *)
  val matched :
    ?tag_size:[`Uint8 | `Uint16] -> int -> 'a encoding -> 'a -> match_result

  (** Encodes a variant constructor. Takes the encoding for the specific
      parameters, a recognizer function that will extract the parameters
      in case the expected case of the variant is being serialized, and
      a constructor function for deserialization.

      The tag must be less than the tag size of the union in which you use the case.
      An optional tag gives a name to a case and should be used to maintain
      compatibility.

      An optional name for the case can be provided, which is used in the binary
      documentation.

      @raise [Invalid_argument] if [case_tag] is [Tag t] with [t < 0]
      *)
  val case :
    title:string ->
    ?description:string ->
    case_tag ->
    'a encoding ->
    ('t -> 'a option) ->
    ('a -> 't) ->
    't case

  (** Create a single encoding from a series of cases.

     In JSON, all cases are tried one after the other using the [case list]. The
     caller is responsible for avoiding collisions. If there are collisions
     (i.e., if multiple cases produce the same JSON output) then the encoding
     and decoding processes might not be inverse of each other. In other words,
     [destruct e (construct e v)] may not be equal to [v].

     In binary, a prefix tag is added to discriminate quickly between
     cases. The default is [`Uint8] and you must use a [`Uint16] if
     you are going to have more than 256 cases.

     The matching function is used during binary encoding of a value
     [v] to efficiently determine which of the cases corresponds to
     [v]. The case list is used during decoding to reconstruct a value based on
     the encoded tag. (Decoding is optimised internally: tag look-up has a
     constant cost.)

     The caller is responsible for ensuring that the [matching_function] and the
     [case list] describe the same encoding. If they describe different
     encodings, then the decoding and encoding processes will not be inverses of
     each others. In other words, [of_bytes e (to_bytes e v)] will not be equal
     to [v].

     If you do not wish to be responsible for this, you can use the unoptimised
     {!union} that uses a [case list] only (see below). Beware that in {!union}
     the complexity of the encoding is linear in the number of cases.

     Following: a basic example use. Note that the [matching_function] uses the
     same tags, payload conversions, and payload encoding as the [case list].

{[
type t = A of string | B of int * int | C
let encoding_t =
  (* Tags and payload encodings for each constructors *)
  let a_tag = 0 and a_encoding = string in
  let b_tag = 1 and b_encoding = obj2 (req "x" int) (req "y" int) in
  let c_tag = 2 and c_encoding = unit in
  matching
    (* optimised encoding function *)
    (function
       | A s -> matched a_tag a_encoding s
       | B (x, y) -> matched b_tag b_encoding (x, y)
       | C -> matched c_tag c_encoding ())
    (* decoding case list *)
    [
       case ~title:"A"
         (Tag a_tag)
         a_encoding
         (function A s -> Some s | _ -> None) (fun s -> A s);
       case ~title:"B"
         (Tag b_tag)
         b_encoding
         (function B (x, y) -> Some (x, y) | _ -> None) (fun (x, y) -> B (x, y));
       case ~title:"C"
         (Tag c_tag)
         c_encoding
         (function C -> Some () | _ -> None) (fun () -> C);
    ]
]}

     @raise [Invalid_argument] if it is given an empty [case list]

     @raise [Invalid_argument] if there are more than one [case] with the same
     [tag] in the [case list]

     @raise [Invalid_argument] if there are more cases in the [case list] than
     can fit in the [tag_size] *)
  val matching :
    ?tag_size:[`Uint8 | `Uint16] ->
    't matching_function ->
    't case list ->
    't encoding

  (** Same as matching except that the matching function is
      a linear traversal of the cases.

     @raise [Invalid_argument] if it is given an empty [case list]

     @raise [Invalid_argument] if there are more than one [case] with the same
     [tag] in the [case list]

     @raise [Invalid_argument] if there are more cases in the [case list] than
     can fit in the [tag_size] *)
  val union : ?tag_size:[`Uint8 | `Uint16] -> 't case list -> 't encoding

  (** {3 Predicates over descriptors} *)

  (** Is the given encoding serialized as a JSON object? *)
  val is_obj : 'a encoding -> bool

  (** Does the given encoding encode a tuple? *)
  val is_tup : 'a encoding -> bool

  (** Classify the binary serialization of an encoding as explained in the
      preamble. *)
  val classify : 'a encoding -> [`Fixed of int | `Dynamic | `Variable]

  (** {3 Specialized descriptors} *)

  (** Encode enumeration via association list
      - represented as a string in JSON and
      - represented as an integer representing the element's position
        in the list in binary. The integer size depends on the list size.*)
  val string_enum : (string * 'a) list -> 'a encoding

  (** Create encodings that produce data of a fixed length when binary encoded.
      See the preamble for an explanation. *)
  module Fixed : sig
    (** @raise Invalid_argument if the argument is less or equal to zero. *)
    val string : int -> string encoding

    (** @raise Invalid_argument if the argument is less or equal to zero. *)
    val bytes : int -> Bytes.t encoding

    (** [add_padding e n] is a padded version of the encoding [e]. In Binary,
        there are [n] null bytes ([\000]) added after the value encoded by [e].
        In JSON, padding is ignored.

        @raise Invalid_argument if [n <= 0]. *)
    val add_padding : 'a encoding -> int -> 'a encoding
  end

  (** Create encodings that produce data of a variable length when binary encoded.
      See the preamble for an explanation. *)
  module Variable : sig
    val string : string encoding

    val bytes : Bytes.t encoding

    (** @raise Invalid_argument if the encoding argument is variable length
        or may lead to zero-width representation in binary. *)
    val array : ?max_length:int -> 'a encoding -> 'a array encoding

    (** @raise Invalid_argument if the encoding argument is variable length
        or may lead to zero-width representation in binary. *)
    val list : ?max_length:int -> 'a encoding -> 'a list encoding
  end

  module Bounded : sig
    (** Encoding of a string whose length does not exceed the specified length.
        The size field uses the smallest integer that can accommodate the
        maximum size - e.g., [`Uint8] for very short strings, [`Uint16] for
        longer strings, etc.

        Attempting to construct a string with a length that is too long causes
        an [Invalid_argument] exception. *)
    val string : int -> string encoding

    (** See {!string} above. *)
    val bytes : int -> Bytes.t encoding
  end

  (** Mark an encoding as being of dynamic size.
      Forces the size to be stored alongside content when needed.
      Typically used to combine two variable encodings in a same
      objects or tuple, or to use a variable encoding in an array or a list. *)
  val dynamic_size :
    ?kind:[`Uint30 | `Uint16 | `Uint8] -> 'a encoding -> 'a encoding

  (** [check_size size encoding] ensures that the binary encoding
      of a value will not be allowed to exceed [size] bytes. The reader
      and the writer fails otherwise. This function do not modify
      the JSON encoding. *)
  val check_size : int -> 'a encoding -> 'a encoding

  (** Recompute the encoding definition each time it is used.
      Useful for dynamically updating the encoding of values of an extensible
      type via a global reference (e.g., exceptions). *)
  val delayed : (unit -> 'a encoding) -> 'a encoding

  (** Define different encodings for JSON and binary serialization. *)
  val splitted : json:'a encoding -> binary:'a encoding -> 'a encoding

  (** Combinator for recursive encodings.

     Notice that the function passed to [mu] must be pure. Otherwise,
     the behavior is unspecified.

     A stateful recursive encoding can still be put under a [delayed]
     combinator to make sure that a new encoding is generated each
     time it is used. Caching the encoding generation when the state
     has not changed is then the responsability of the client.

  *)
  val mu :
    string ->
    ?title:string ->
    ?description:string ->
    ('a encoding -> 'a encoding) ->
    'a encoding

  (** {3 Documenting descriptors} *)

  (** Give a name to an encoding and optionally
      add documentation to an encoding. *)
  val def :
    string -> ?title:string -> ?description:string -> 't encoding -> 't encoding

  (** See {!lazy_encoding} below.*)
  type 'a lazy_t

  (** Combinator to have a part of the binary encoding lazily deserialized.
      This is transparent on the JSON side. *)
  val lazy_encoding : 'a encoding -> 'a lazy_t encoding

  (** Force the decoding (memoized for later calls), and return the
      value if successful. *)
  val force_decode : 'a lazy_t -> 'a option

  (** Obtain the bytes without actually deserializing.  Will serialize
      and memoize the result if the value is not the result of a lazy
      deserialization. *)
  val force_bytes : 'a lazy_t -> Bytes.t

  (** Make a lazy value from an immediate one. *)
  val make_lazy : 'a encoding -> 'a -> 'a lazy_t

  (** Apply on structure of lazy value, and combine results *)
  val apply_lazy :
    fun_value:('a -> 'b) ->
    fun_bytes:(Bytes.t -> 'b) ->
    fun_combine:('b -> 'b -> 'b) ->
    'a lazy_t ->
    'b

  (** Create a {!Data_encoding.t} value which records knowledge of
      older versions of a given encoding as long as one can "upgrade"
      from an older version to the next (if upgrade is impossible one
      should consider that the encoding is completely different).

      See the module [Documented_example] in ["./test/versioned.ml"]
      for a tutorial.
  *)
end

include module type of Encoding with type 'a t = 'a Encoding.t

module With_version : sig
  (** An encapsulation of consecutive encoding versions. *)
  type _ t

  (** [first_version enc] records that [enc] is the first (known)
      version of the object. *)
  val first_version : 'a encoding -> 'a t

  (** [next_version enc upgrade prev] constructs a new version from
      the previous version [prev] and an [upgrade] function. *)
  val next_version : 'a encoding -> ('b -> 'a) -> 'b t -> 'a t

  (** Make an encoding from an encapsulation of versions; the
      argument [~name] is used to prefix the version "tag" in the
      encoding, it should not change from one version to the next. *)
  val encoding : name:string -> 'a t -> 'a encoding
end

module Json : sig
  (** In memory JSON data, compatible with [Ezjsonm]. *)
  type json =
    [ `O of (string * json) list
    | `Bool of bool
    | `Float of float
    | `A of json list
    | `Null
    | `String of string ]

  type t = json

  type schema = Json_schema.schema

  (** Encodes raw JSON data (BSON is used for binary). *)
  val encoding : json Encoding.t

  (** Encodes a JSON schema (BSON encoded for binary). *)
  val schema_encoding : schema Encoding.t

  (** Create a {!Json_encoding.encoding} from an {!encoding}. *)
  val convert : 'a Encoding.t -> 'a Json_encoding.encoding

  (** Generate a schema from an {!encoding}. *)
  val schema : ?definitions_path:string -> 'a Encoding.t -> schema

  (** Construct a JSON object from an encoding. *)
  val construct : 't Encoding.t -> 't -> json

  type jsonm_lexeme =
    [ `Null
    | `Bool of bool
    | `String of string
    | `Float of float
    | `Name of string
    | `As
    | `Ae
    | `Os
    | `Oe ]

  (** [construct_seq enc t] is a representation of [t] as a sequence of json
      lexeme ([jsonm_lexeme Seq.t]). This sequence is lazy: lexemes are computed
      on-demand. *)
  val construct_seq : 't Encoding.t -> 't -> jsonm_lexeme Seq.t

  (** [string_seq_of_jsonm_lexeme_seq ~newline ~chunk_size_hint s] is a sequence
      of strings, the concatenation of which is a valid textual representation
      of the json value represented by [s]. Each string chunk is roughly
      [chunk_size_hint] long (except the last one that may be shorter).

      With the [newline] parameter set to [true], a single newline character is
      appended to the textual representation.

      Forcing one element of the resulting string sequence forces multiple
      elements of the underlying lexeme sequence. Once enough lexemes have been
      forced that roughly [chunk_size_hint] characters are needed to reprensent
      them, the representation is returned and the rest of the sequence is held
      lazily.

      Note that most chunks split at a lexeme boundary. This may not be true for
      string literals or float literals, the representation of which may be
      spread across multiple chunks. *)
  val string_seq_of_jsonm_lexeme_seq :
    newline:bool -> chunk_size_hint:int -> jsonm_lexeme Seq.t -> string Seq.t

  val small_string_seq_of_jsonm_lexeme_seq :
    newline:bool -> jsonm_lexeme Seq.t -> string Seq.t

  (** [blit_instructions_seq_of_jsonm_lexeme_seq ~newline ~buffer json]
      is a sequence of [(buff, offset, length)] such that the concatenation of the
      sub-strings thus designated represents the json value in text form.

      @raise [Invalid_argument _] if [Bytes.length buffer] is less than 32.

      The intended use is to blit each of the substring onto whatever output the
      consumer decides. In most cases, the Sequence's [buff] is physically equal
      to [buffer]. This is not always true and one cannot rely on that fact. E.g.,
      when the json includes a long string literal, the function might instruct
      the consumer to blit from that literal directly.

      This function performs few allocations, especially of fresh strings.

      Note that once the next element of the sequence is forced, the blit
      instructions become invalid: the content of [buff] may have been rewritten
      by the side effect of forcing the next element. *)
  val blit_instructions_seq_of_jsonm_lexeme_seq :
    newline:bool ->
    buffer:bytes ->
    jsonm_lexeme Seq.t ->
    (Bytes.t * int * int) Seq.t

  (** Destruct a JSON object into a value.
      Fail with an exception if the JSON object and encoding do not match.. *)
  val destruct : 't Encoding.t -> json -> 't

  (** JSON Error. *)

  type path = path_item list

  (** A set of accessors that point to a location in a JSON object. *)
  and path_item =
    [ `Field of string  (** A field in an object. *)
    | `Index of int  (** An index in an array. *)
    | `Star  (** Any / every field or index. *)
    | `Next  (** The next element after an array. *) ]

  (** Exception raised by destructors, with the location in the original
      JSON structure and the specific error. *)
  exception Cannot_destruct of (path * exn)

  (** Unexpected kind of data encountered, with the expectation. *)
  exception Unexpected of string * string

  (** Some {!union} couldn't be destructed, with the reasons for each {!case}. *)
  exception No_case_matched of exn list

  (** Array of unexpected size encountered, with the expectation. *)
  exception Bad_array_size of int * int

  (** Missing field in an object. *)
  exception Missing_field of string

  (** Supernumerary field in an object. *)
  exception Unexpected_field of string

  val print_error :
    ?print_unknown:(Format.formatter -> exn -> unit) ->
    Format.formatter ->
    exn ->
    unit

  (** Helpers for writing encoders. *)
  val cannot_destruct : ('a, Format.formatter, unit, 'b) format4 -> 'a

  val wrap_error : ('a -> 'b) -> 'a -> 'b

  (** Read a JSON document from a string. *)
  val from_string : string -> (json, string) result

  (** Write a JSON document to a string. This goes via an intermediate
      buffer and so may be slow on large documents. *)
  val to_string : ?newline:bool -> ?minify:bool -> json -> string

  val pp : Format.formatter -> json -> unit
end

module Bson : sig
  type bson = Json_repr_bson.bson

  type t = bson

  (** Construct a BSON object from an encoding. *)
  val construct : 't Encoding.t -> 't -> bson

  (** Destruct a BSON object into a value.
      Fail with an exception if the JSON object and encoding do not match.. *)
  val destruct : 't Encoding.t -> bson -> 't
end

module Binary_schema : sig
  type t

  val pp : Format.formatter -> t -> unit

  val encoding : t Encoding.t
end

module Binary : sig
  (** All the errors that might be returned while reading a binary value *)
  type read_error =
    | Not_enough_data
    | Extra_bytes
    | No_case_matched
    | Unexpected_tag of int
    | Invalid_size of int
    | Invalid_int of {min: int; v: int; max: int}
    | Invalid_float of {min: float; v: float; max: float}
    | Trailing_zero
    | Size_limit_exceeded
    | List_too_long
    | Array_too_long

  exception Read_error of read_error

  val pp_read_error : Format.formatter -> read_error -> unit

  val read_error_encoding : read_error t

  (** All the errors that might be returned while writing a binary value *)
  type write_error =
    | Size_limit_exceeded
    | No_case_matched
    | Invalid_int of {min: int; v: int; max: int}
    | Invalid_float of {min: float; v: float; max: float}
    | Invalid_bytes_length of {expected: int; found: int}
    | Invalid_string_length of {expected: int; found: int}
    | Invalid_natural
    | List_too_long
    | Array_too_long

  val pp_write_error : Format.formatter -> write_error -> unit

  val write_error_encoding : write_error t

  exception Write_error of write_error

  (** Compute the expected length of the binary representation of a value *)
  val length : 'a Encoding.t -> 'a -> int

  (** Returns the size of the binary representation that the given
      encoding might produce, only when this size does not depends of the value
      itself.

      E.g., [fixed_length (tup2 int64 (Fixed.string 2))] is [Some _]

      E.g., [fixed_length (result int64 (Fixed.string 2))] is [None]

      E.g., [fixed_length (list (tup2 int64 (Fixed.string 2)))] is [None] *)
  val fixed_length : 'a Encoding.t -> int option

  (** Returns the maximum size of the binary representation that the given
      encoding might produce, only when this maximum size does not depends of
      the value itself.

      E.g., [maximum_length (tup2 int64 (Fixed.string 2))] is [Some _]

      E.g., [maximum_length (result int64 (Fixed.string 2))] is [Some _]

      E.g., [maximum_length (list (tup2 int64 (Fixed.string 2)))] is [None]

      Note that the function assumes that recursive encodings (build using [mu])
      are used for recursive data types. As a result, [maximum_length] will
      return [None] if given a recursive encoding.

      If there are static guarantees about the maximum size of the
      representation for values of a given type, you can wrap your encoding in
      [check_size]. This will cause [maximum_length] to return [Some _]. *)
  val maximum_length : 'a Encoding.t -> int option

  (** [read enc buf ofs len] tries to reconstruct a value from the
      bytes in [buf] starting at offset [ofs] and reading at most
      [len] bytes. This function also returns the offset of the first
      unread bytes in the [buf].

      The function will fail (returning [Error _]) if it needs to read more than
      [len] bytes to decode the value.

      The returned value contains no pointer back to [buf] (as a whole or as
      sub-strings), even in the case where the encoding is or includes
      [Fixed.string] or [Fixed.bytes]. *)
  val read :
    'a Encoding.t -> string -> int -> int -> (int * 'a, read_error) result

  val read_opt : 'a Encoding.t -> string -> int -> int -> (int * 'a) option

  val read_exn : 'a Encoding.t -> string -> int -> int -> int * 'a

  (** Return type for the function [read_stream]. *)
  type 'ret status =
    | Success of {result: 'ret; size: int; stream: Binary_stream.t}
        (** Fully decoded value, together with the total amount of bytes reads,
        and the remaining unread stream. *)
    | Await of (Bytes.t -> 'ret status)  (** Partially decoded value.*)
    | Error of read_error
        (** Failure. The stream is garbled and it should be dropped. *)

  (** Streamed equivalent of [read]. This variant cannot be called on
      variable-size encodings. *)
  val read_stream : ?init:Binary_stream.t -> 'a Encoding.t -> 'a status

  (** The internal state that writers handle. It is presented explicitly as an
      abstract type so that you must use the constructor to obtain it. The
      constructor ({!make_writer_state}) performs basic bound checks. *)
  type writer_state

  (** [make_writer_state buffer ~offset ~allowed_bytes] is
      [None] if [allowed_bytes < 0],
      [None] if [allowed_bytes > length buffer - offset],
      [Some _] otherwise. *)
  val make_writer_state :
    bytes -> offset:int -> allowed_bytes:int -> writer_state option

  (** [write enc v state]
      where [Some state] is [make_writer_state buffer ~offset ~allowed_bytes]
      writes the binary [enc] representation of [v] onto [buffer] starting at
      [offset]. The function will fail (returning [Error _]) if the encoding
      would use more than [allowed_bytes].

      The function returns the offset of first unwritten bytes, or returns
      [Error _] in case of failure.
      In the latter case, some data might have been written on the buffer. *)
  val write : 'a Encoding.t -> 'a -> writer_state -> (int, write_error) result

  val write_opt : 'a Encoding.t -> 'a -> writer_state -> int option

  val write_exn : 'a Encoding.t -> 'a -> writer_state -> int

  (** [of_bytes enc buf] is equivalent to [read enc buf 0 (length buf)].
      The function fails if the buffer is not fully read. *)
  val of_bytes : 'a Encoding.t -> Bytes.t -> ('a, read_error) result

  val of_bytes_opt : 'a Encoding.t -> Bytes.t -> 'a option

  (** [of_bytes_exn enc buf] is equivalent to [of_bytes], except
      @raise [Read_error] instead of returning [None] in case of error. *)
  val of_bytes_exn : 'a Encoding.t -> Bytes.t -> 'a

  (** [of_string enc buf] is like [of_bytes enc buf] but it reads bytes from a
      string. *)
  val of_string : 'a Encoding.t -> string -> ('a, read_error) result

  val of_string_opt : 'a Encoding.t -> string -> 'a option

  val of_string_exn : 'a Encoding.t -> string -> 'a

  (** [to_bytes enc v] is the equivalent of [write env buf 0 len]
      where [buf] is a newly allocated buffer.
      The parameter [buffer_size] controls the initial size of [buf].

      @raise [Invalid_argument] if [buffer_size < 0]. *)
  val to_bytes :
    ?buffer_size:int -> 'a Encoding.t -> 'a -> (Bytes.t, write_error) result

  val to_bytes_opt : ?buffer_size:int -> 'a Encoding.t -> 'a -> Bytes.t option

  (** [to_bytes_exn enc v] is equivalent to [to_bytes enc v], except

      @raise [Write_error] instead of returning [None] in case of error. *)
  val to_bytes_exn : ?buffer_size:int -> 'a Encoding.t -> 'a -> Bytes.t

  (** [to_string enc v] is like [to_bytes] but it returns a string.

      Note: [to_string enc v] is always equal to
      [Bytes.to_string (to_bytes enc v)] but more efficient.

      @raise [Invalid_argument] if [buffer_size < 0]. *)
  val to_string :
    ?buffer_size:int -> 'a Encoding.t -> 'a -> (string, write_error) result

  val to_string_opt : ?buffer_size:int -> 'a Encoding.t -> 'a -> string option

  (** @raise [Write_error] instead of returning [None] in case of error. *)
  val to_string_exn : ?buffer_size:int -> 'a Encoding.t -> 'a -> string

  val describe : 'a Encoding.t -> Binary_schema.t

  module Slicer : sig
    (** A [slice] is a part of a binary representation of some data. The
      concatenation of multiple slice represents the whole data. *)
    type slice = {name: string; value: string; pretty_printed: string}

    type slicer_state

    (** [None] if [offset] and [length] do not describe a valid substring. *)
    val make_slicer_state :
      string -> offset:int -> length:int -> slicer_state option

    (** [slice e b offset length] slices the data represented by the [length]
      bytes in [b] starting at index [offset].

      If [e] does not correctly describe the given bytes (i.e., if [read]
      would fail on equivalent parameters) then it returns [Error]. *)
    val slice :
      _ Encoding.t ->
      slicer_state ->
      (slice list, Binary_error_types.read_error) result

    val slice_opt : _ Encoding.t -> slicer_state -> slice list option

    val slice_exn : _ Encoding.t -> slicer_state -> slice list

    (** [slice_string] slices the whole content of the buffer. *)
    val slice_string : _ Encoding.t -> string -> (slice list, read_error) result

    val slice_string_opt : _ Encoding.t -> string -> slice list option

    val slice_string_exn : _ Encoding.t -> string -> slice list

    val slice_bytes : _ Encoding.t -> bytes -> (slice list, read_error) result

    val slice_bytes_opt : _ Encoding.t -> bytes -> slice list option

    val slice_bytes_exn : _ Encoding.t -> bytes -> slice list
  end
end

type json = Json.t

val json : json Encoding.t

type json_schema = Json.schema

val json_schema : json_schema Encoding.t

type bson = Bson.t

module Registration : sig
  type id = string

  (** A encoding that has been {!register}ed. It can be retrieved using either
      {!list} or {!find}. *)
  type t

  (** Descriptions and schemas of registered encodings. *)
  val binary_schema : t -> Binary_schema.t

  val json_schema : t -> Json.schema

  val description : t -> string option

  (** Printers for the encodings. *)
  val json_pretty_printer : t -> Format.formatter -> Json.t -> unit

  val binary_pretty_printer : t -> Format.formatter -> Bytes.t -> unit

  (** [register ~id encoding] registers the [encoding] with the [id]. It can
      later be found using {!find} and providing the matching [id]. It will
      also appear in the results of {!list}. *)
  val register : ?pp:(Format.formatter -> 'a -> unit) -> 'a Encoding.t -> unit

  (** [slice r b] attempts to slice a binary representation [b] of some data
      assuming it is correctly described by the registered encoding [r].
      If [r] does not correctly describe [b], then it returns [None].

      See {!Binary.slice_string} for details about slicing. *)
  val slice :
    t -> string -> (Binary.Slicer.slice list, Binary.read_error) result

  (** [slice_all b] attempts to slice a binary representation [b] of some data
      for all of the registered encodings. It returns a list of the slicing for
      each of the registered encodings that correctly describe [b].

      See {!Binary.slice_string} for details about slicing. *)
  val slice_all : string -> (string * Binary.Slicer.slice list) list

  (** [find id] is [Some r] if [register id e] has been called, in which
      case [r] matches [e]. Otherwise, it is [None]. *)
  val find : id -> t option

  (** [list ()] is a list of pairs [(id, r)] where [r] is
      a registered encoding for the [id]. *)
  val list : unit -> (id * t) list

  (** Conversion functions from/to json to/from bytes. *)
  val bytes_of_json : t -> Json.t -> Bytes.t option

  val json_of_bytes : t -> Bytes.t -> Json.t option
end
