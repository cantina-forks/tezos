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

module type S = sig
  type 'a t = 'a Internal_event.Simple.t

  val emit : 'a t -> 'a -> unit Lwt.t

  val api_do_rpc : string t

  val api_get : string t

  val core_created : (string * string) t

  val failing : string t

  val staged_data : (string * int) t
end

module Logger : S = struct
  include Internal_event.Simple

  let section = ["light_mode"]

  let api_do_rpc =
    declare_1
      ~section
      ~name:"do_rpc"
      ~level:Internal_event.Debug
      ~msg:"API call: do_rpc {key}"
      ("key", Data_encoding.string)

  let api_get =
    declare_1
      ~section
      ~name:"get"
      ~level:Internal_event.Debug
      ~msg:"API call: get {key}"
      ("key", Data_encoding.string)

  let core_created =
    declare_2
      ~section
      ~name:"core_created"
      ~level:Internal_event.Debug
      ~msg:"light mode's core created for chain {chain} and block {block}"
      ("chain", Data_encoding.string)
      ("block", Data_encoding.string)

  let failing =
    declare_1
      ~section
      ~name:"failing"
      ~level:Internal_event.Debug
      ~msg:"returning with an error: {errmsg}"
      ("errmsg", Data_encoding.string)

  let staged_data =
    declare_2
      ~section
      ~name:"staged_data"
      ~level:Internal_event.Debug
      ~msg:
        "integrated data for key {key} from one endpoint, about to validate \
         from {nb_validators} other endpoints"
      ("key", Data_encoding.string)
      ("nb_validators", Data_encoding.int16)
end
