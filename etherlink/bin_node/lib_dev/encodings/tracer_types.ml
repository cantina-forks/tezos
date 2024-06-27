(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2024 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type error +=
  | Not_supported
  | Transaction_not_found of Ethereum_types.hash
  | Block_not_found of Ethereum_types.quantity
  | Trace_not_found

type tracer_config = {
  enable_return_data : bool;
  enable_memory : bool;
  disable_stack : bool;
  disable_storage : bool;
}

let default_tracer_config =
  {
    enable_return_data = false;
    enable_memory = false;
    disable_stack = false;
    disable_storage = false;
  }

let tracer_config_encoding =
  let open Data_encoding in
  conv
    (fun {enable_return_data; enable_memory; disable_stack; disable_storage} ->
      ( enable_return_data,
        enable_memory,
        disable_stack,
        disable_storage,
        false,
        5 ))
    (fun ( enable_return_data,
           enable_memory,
           disable_stack,
           disable_storage,
           _,
           _ ) ->
      {enable_return_data; enable_memory; disable_stack; disable_storage})
    (obj6
       (dft "enableReturnData" bool default_tracer_config.enable_return_data)
       (dft "enableMemory" bool default_tracer_config.enable_memory)
       (dft "disableStack" bool default_tracer_config.disable_stack)
       (dft "disableStorage" bool default_tracer_config.disable_storage)
       (dft "debug" bool false)
       (dft "limit" int31 5))

type tracer_kind = StructLogger

(* TODO: (#7212) make it return an error so that we can return an understadable
   error to the user. *)
(* Cannot be made a string_enum due to `"data_encoding.string_enum: cannot have a
   single case, use constant instead"`. *)
let tracer_kind_encoding =
  Data_encoding.(
    conv
      (fun StructLogger -> ())
      (fun () -> StructLogger)
      (constant "structLogger"))

type config = {
  tracer : tracer_kind;
  tracer_config : tracer_config;
  timeout : Time.System.Span.t;
  reexec : int64;
}

(* Default config is derived from the specification of the RPC:
   https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-debug#debugtracetransaction. *)
let default_config =
  {
    tracer = StructLogger;
    tracer_config = default_tracer_config;
    timeout = Time.System.Span.of_seconds_exn 5.;
    reexec = 128L;
  }

(* Technically, the tracer_config is specific to `structLogger`. As we only
   support this one for now, the encoding assumes they can be used. However if
   we need to add a new tracer, we might want to make it more constrained to
   structLogger, or simply ignore it. *)
let config_encoding =
  let open Data_encoding in
  conv
    (fun {tracer; tracer_config; timeout; reexec} ->
      ((tracer, timeout, reexec), tracer_config))
    (fun ((tracer, timeout, reexec), tracer_config) ->
      {tracer; tracer_config; timeout; reexec})
    (merge_objs
       (obj3
          (dft "tracer" tracer_kind_encoding default_config.tracer)
          (dft "timeout" Time.System.Span.encoding default_config.timeout)
          (dft "reexec" int64 default_config.reexec))
       tracer_config_encoding)

type input = Ethereum_types.hash * config

type call_input =
  (Ethereum_types.call * Ethereum_types.Block_parameter.extended) * config

let input_encoding =
  Helpers.encoding_with_optional_last_param
    Ethereum_types.hash_encoding
    config_encoding
    default_config

let call_input_encoding =
  Helpers.encoding_with_optional_last_param
    (Data_encoding.tup2
       Ethereum_types.call_encoding
       Ethereum_types.Block_parameter.extended_encoding)
    config_encoding
    default_config

let input_rlp_encoder ?hash config =
  let open Rlp in
  let hash =
    match hash with
    | Some hash -> Value (Ethereum_types.hash_to_bytes hash |> Bytes.of_string)
    | None -> Value Bytes.empty
  in
  let return_data =
    Ethereum_types.bool_to_rlp_bytes config.tracer_config.enable_return_data
  in
  let memory =
    Ethereum_types.bool_to_rlp_bytes config.tracer_config.enable_memory
  in
  let stack =
    Ethereum_types.bool_to_rlp_bytes config.tracer_config.disable_stack
  in
  let storage =
    Ethereum_types.bool_to_rlp_bytes config.tracer_config.disable_storage
  in
  List [hash; return_data; memory; stack; storage] |> encode |> Bytes.to_string

let hex_encoding =
  let open Data_encoding in
  conv Hex.to_bytes_exn Hex.of_bytes bytes

module Opcode = struct
  (* These two pattern matchings are generated
     https://ethereum.org/en/developers/docs/evm/opcodes/, with a combination of
     macros. *)

  type t = Char.t

  let opcode_to_string = function
    | '\x00' -> "STOP"
    | '\x01' -> "ADD"
    | '\x02' -> "MUL"
    | '\x03' -> "SUB"
    | '\x04' -> "DIV"
    | '\x05' -> "SDIV"
    | '\x06' -> "MOD"
    | '\x07' -> "SMOD"
    | '\x08' -> "ADDMOD"
    | '\x09' -> "MULMOD"
    | '\x0A' -> "EXP"
    | '\x0B' -> "SIGNEXTEND"
    | '\x0C' .. '\x0F' -> "invalid"
    | '\x10' -> "LT"
    | '\x11' -> "GT"
    | '\x12' -> "SLT"
    | '\x13' -> "SGT"
    | '\x14' -> "EQ"
    | '\x15' -> "ISZERO"
    | '\x16' -> "AND"
    | '\x17' -> "OR"
    | '\x18' -> "XOR"
    | '\x19' -> "NOT"
    | '\x1A' -> "BYTE"
    | '\x1B' -> "SHL"
    | '\x1C' -> "SHR"
    | '\x1D' -> "SAR"
    | '\x1E' .. '\x1F' -> "invalid"
    | '\x20' -> "KECCAK256"
    | '\x21' .. '\x2F' -> "invalid"
    | '\x30' -> "ADDRESS"
    | '\x31' -> "BALANCE"
    | '\x32' -> "ORIGIN"
    | '\x33' -> "CALLER"
    | '\x34' -> "CALLVALUE"
    | '\x35' -> "CALLDATALOAD"
    | '\x36' -> "CALLDATASIZE"
    | '\x37' -> "CALLDATACOPY"
    | '\x38' -> "CODESIZE"
    | '\x39' -> "CODECOPY"
    | '\x3A' -> "GASPRICE"
    | '\x3B' -> "EXTCODESIZE"
    | '\x3C' -> "EXTCODECOPY"
    | '\x3D' -> "RETURNDATASIZE"
    | '\x3E' -> "RETURNDATACOPY"
    | '\x3F' -> "EXTCODEHASH"
    | '\x40' -> "BLOCKHASH"
    | '\x41' -> "COINBASE"
    | '\x42' -> "TIMESTAMP"
    | '\x43' -> "NUMBER"
    | '\x44' -> "PREVRANDAO"
    | '\x45' -> "GASLIMIT"
    | '\x46' -> "CHAINID"
    | '\x47' -> "SELFBALANCE"
    | '\x48' -> "BASEFEE"
    | '\x49' -> "BLOBHASH"
    | '\x4A' -> "BLOBBASEFEE"
    | '\x4B' .. '\x4F' -> "invalid"
    | '\x50' -> "POP"
    | '\x51' -> "MLOAD"
    | '\x52' -> "MSTORE"
    | '\x53' -> "MSTORE8"
    | '\x54' -> "SLOAD"
    | '\x55' -> "SSTORE"
    | '\x56' -> "JUMP"
    | '\x57' -> "JUMPI"
    | '\x58' -> "PC"
    | '\x59' -> "MSIZE"
    | '\x5A' -> "GAS"
    | '\x5B' -> "JUMPDEST"
    | '\x5C' -> "TLOAD"
    | '\x5D' -> "TSTORE"
    | '\x5E' -> "MCOPY"
    | '\x5F' -> "PUSH0"
    | '\x60' -> "PUSH1"
    | '\x61' -> "PUSH2"
    | '\x62' -> "PUSH3"
    | '\x63' -> "PUSH4"
    | '\x64' -> "PUSH5"
    | '\x65' -> "PUSH6"
    | '\x66' -> "PUSH7"
    | '\x67' -> "PUSH8"
    | '\x68' -> "PUSH9"
    | '\x69' -> "PUSH10"
    | '\x6A' -> "PUSH11"
    | '\x6B' -> "PUSH12"
    | '\x6C' -> "PUSH13"
    | '\x6D' -> "PUSH14"
    | '\x6E' -> "PUSH15"
    | '\x6F' -> "PUSH16"
    | '\x70' -> "PUSH17"
    | '\x71' -> "PUSH18"
    | '\x72' -> "PUSH19"
    | '\x73' -> "PUSH20"
    | '\x74' -> "PUSH21"
    | '\x75' -> "PUSH22"
    | '\x76' -> "PUSH23"
    | '\x77' -> "PUSH24"
    | '\x78' -> "PUSH25"
    | '\x79' -> "PUSH26"
    | '\x7A' -> "PUSH27"
    | '\x7B' -> "PUSH28"
    | '\x7C' -> "PUSH29"
    | '\x7D' -> "PUSH30"
    | '\x7E' -> "PUSH31"
    | '\x7F' -> "PUSH32"
    | '\x80' -> "DUP1"
    | '\x81' -> "DUP2"
    | '\x82' -> "DUP3"
    | '\x83' -> "DUP4"
    | '\x84' -> "DUP5"
    | '\x85' -> "DUP6"
    | '\x86' -> "DUP7"
    | '\x87' -> "DUP8"
    | '\x88' -> "DUP9"
    | '\x89' -> "DUP10"
    | '\x8A' -> "DUP11"
    | '\x8B' -> "DUP12"
    | '\x8C' -> "DUP13"
    | '\x8D' -> "DUP14"
    | '\x8E' -> "DUP15"
    | '\x8F' -> "DUP16"
    | '\x90' -> "SWAP1"
    | '\x91' -> "SWAP2"
    | '\x92' -> "SWAP3"
    | '\x93' -> "SWAP4"
    | '\x94' -> "SWAP5"
    | '\x95' -> "SWAP6"
    | '\x96' -> "SWAP7"
    | '\x97' -> "SWAP8"
    | '\x98' -> "SWAP9"
    | '\x99' -> "SWAP10"
    | '\x9A' -> "SWAP11"
    | '\x9B' -> "SWAP12"
    | '\x9C' -> "SWAP13"
    | '\x9D' -> "SWAP14"
    | '\x9E' -> "SWAP15"
    | '\x9F' -> "SWAP16"
    | '\xA0' -> "LOG0"
    | '\xA1' -> "LOG1"
    | '\xA2' -> "LOG2"
    | '\xA3' -> "LOG3"
    | '\xA4' -> "LOG4"
    | '\xA5' .. '\xEF' -> "invalid"
    | '\xF0' -> "CREATE"
    | '\xF1' -> "CALL"
    | '\xF2' -> "CALLCODE"
    | '\xF3' -> "RETURN"
    | '\xF4' -> "DELEGATECALL"
    | '\xF5' -> "CREATE2"
    | '\xF6' .. '\xF9' -> "invalid"
    | '\xFA' -> "STATICCALL"
    | '\xFB' .. '\xFC' -> "invalid"
    | '\xFD' -> "REVERT"
    | '\xFE' ->
        "INVALID"
        (* This is the "official" INVALID opcode, contrary to
           the others that actually doesn't exist. *)
    | '\xFF' -> "SELFDESTRUCT"

  let string_to_opcode = function
    | "STOP" -> '\x00'
    | "ADD" -> '\x01'
    | "MUL" -> '\x02'
    | "SUB" -> '\x03'
    | "DIV" -> '\x04'
    | "SDIV" -> '\x05'
    | "MOD" -> '\x06'
    | "SMOD" -> '\x07'
    | "ADDMOD" -> '\x08'
    | "MULMOD" -> '\x09'
    | "EXP" -> '\x0A'
    | "SIGNEXTEND" -> '\x0B'
    | "LT" -> '\x10'
    | "GT" -> '\x11'
    | "SLT" -> '\x12'
    | "SGT" -> '\x13'
    | "EQ" -> '\x14'
    | "ISZERO" -> '\x15'
    | "AND" -> '\x16'
    | "OR" -> '\x17'
    | "XOR" -> '\x18'
    | "NOT" -> '\x19'
    | "BYTE" -> '\x1A'
    | "SHL" -> '\x1B'
    | "SHR" -> '\x1C'
    | "SAR" -> '\x1D'
    | "KECCAK256" -> '\x20'
    | "ADDRESS" -> '\x30'
    | "BALANCE" -> '\x31'
    | "ORIGIN" -> '\x32'
    | "CALLER" -> '\x33'
    | "CALLVALUE" -> '\x34'
    | "CALLDATALOAD" -> '\x35'
    | "CALLDATASIZE" -> '\x36'
    | "CALLDATACOPY" -> '\x37'
    | "CODESIZE" -> '\x38'
    | "CODECOPY" -> '\x39'
    | "GASPRICE" -> '\x3A'
    | "EXTCODESIZE" -> '\x3B'
    | "EXTCODECOPY" -> '\x3C'
    | "RETURNDATASIZE" -> '\x3D'
    | "RETURNDATACOPY" -> '\x3E'
    | "EXTCODEHASH" -> '\x3F'
    | "BLOCKHASH" -> '\x40'
    | "COINBASE" -> '\x41'
    | "TIMESTAMP" -> '\x42'
    | "NUMBER" -> '\x43'
    | "PREVRANDAO" -> '\x44'
    | "GASLIMIT" -> '\x45'
    | "CHAINID" -> '\x46'
    | "SELFBALANCE" -> '\x47'
    | "BASEFEE" -> '\x48'
    | "BLOBHASH" -> '\x49'
    | "BLOBBASEFEE" -> '\x4A'
    | "POP" -> '\x50'
    | "MLOAD" -> '\x51'
    | "MSTORE" -> '\x52'
    | "MSTORE8" -> '\x53'
    | "SLOAD" -> '\x54'
    | "SSTORE" -> '\x55'
    | "JUMP" -> '\x56'
    | "JUMPI" -> '\x57'
    | "PC" -> '\x58'
    | "MSIZE" -> '\x59'
    | "GAS" -> '\x5A'
    | "JUMPDEST" -> '\x5B'
    | "TLOAD" -> '\x5C'
    | "TSTORE" -> '\x5D'
    | "MCOPY" -> '\x5E'
    | "PUSH0" -> '\x5F'
    | "PUSH1" -> '\x60'
    | "PUSH2" -> '\x61'
    | "PUSH3" -> '\x62'
    | "PUSH4" -> '\x63'
    | "PUSH5" -> '\x64'
    | "PUSH6" -> '\x65'
    | "PUSH7" -> '\x66'
    | "PUSH8" -> '\x67'
    | "PUSH9" -> '\x68'
    | "PUSH10" -> '\x69'
    | "PUSH11" -> '\x6A'
    | "PUSH12" -> '\x6B'
    | "PUSH13" -> '\x6C'
    | "PUSH14" -> '\x6D'
    | "PUSH15" -> '\x6E'
    | "PUSH16" -> '\x6F'
    | "PUSH17" -> '\x70'
    | "PUSH18" -> '\x71'
    | "PUSH19" -> '\x72'
    | "PUSH20" -> '\x73'
    | "PUSH21" -> '\x74'
    | "PUSH22" -> '\x75'
    | "PUSH23" -> '\x76'
    | "PUSH24" -> '\x77'
    | "PUSH25" -> '\x78'
    | "PUSH26" -> '\x79'
    | "PUSH27" -> '\x7A'
    | "PUSH28" -> '\x7B'
    | "PUSH29" -> '\x7C'
    | "PUSH30" -> '\x7D'
    | "PUSH31" -> '\x7E'
    | "PUSH32" -> '\x7F'
    | "DUP1" -> '\x80'
    | "DUP2" -> '\x81'
    | "DUP3" -> '\x82'
    | "DUP4" -> '\x83'
    | "DUP5" -> '\x84'
    | "DUP6" -> '\x85'
    | "DUP7" -> '\x86'
    | "DUP8" -> '\x87'
    | "DUP9" -> '\x88'
    | "DUP10" -> '\x89'
    | "DUP11" -> '\x8A'
    | "DUP12" -> '\x8B'
    | "DUP13" -> '\x8C'
    | "DUP14" -> '\x8D'
    | "DUP15" -> '\x8E'
    | "DUP16" -> '\x8F'
    | "SWAP1" -> '\x90'
    | "SWAP2" -> '\x91'
    | "SWAP3" -> '\x92'
    | "SWAP4" -> '\x93'
    | "SWAP5" -> '\x94'
    | "SWAP6" -> '\x95'
    | "SWAP7" -> '\x96'
    | "SWAP8" -> '\x97'
    | "SWAP9" -> '\x98'
    | "SWAP10" -> '\x99'
    | "SWAP11" -> '\x9A'
    | "SWAP12" -> '\x9B'
    | "SWAP13" -> '\x9C'
    | "SWAP14" -> '\x9D'
    | "SWAP15" -> '\x9E'
    | "SWAP16" -> '\x9F'
    | "LOG0" -> '\xA0'
    | "LOG1" -> '\xA1'
    | "LOG2" -> '\xA2'
    | "LOG3" -> '\xA3'
    | "LOG4" -> '\xA4'
    | "CREATE" -> '\xF0'
    | "CALL" -> '\xF1'
    | "CALLCODE" -> '\xF2'
    | "RETURN" -> '\xF3'
    | "DELEGATECALL" -> '\xF4'
    | "CREATE2" -> '\xF5'
    | "STATICCALL" -> '\xFA'
    | "REVERT" -> '\xFD'
    | "INVALID" -> '\xFE'
    | "SELFDESTRUCT" -> '\xFF'
    | opcode -> Stdlib.failwith (Format.sprintf "Invalid opcode %s" opcode)

  let encoding =
    Data_encoding.conv opcode_to_string string_to_opcode Data_encoding.string
end

(* Serves only for encoding numeric values in JSON that are up to 2^53. *)
type uint53 = Z.t

let uint53_encoding =
  let open Data_encoding in
  let uint53_to_json i =
    (* See {!Json_data_encoding.int53} *)
    if i < Z.shift_left Z.one 53 then `Float (Z.to_float i)
    else Stdlib.failwith "JSON cannot accept integers more than 2^53"
  in
  let json_to_uint53 = function
    | `Float i -> Z.of_float i
    | _ -> Stdlib.failwith "Invalid representation for uint53"
  in
  let json_encoding = conv uint53_to_json json_to_uint53 json in
  splitted ~json:json_encoding ~binary:z

type opcode_log = {
  pc : uint53;
  op : Opcode.t;
  gas : uint53;
  gas_cost : uint53;
  memory : Hex.t list option;
  mem_size : int32 option;
  stack : Hex.t list option;
  return_data : Hex.t option;
  storage : (Hex.t * Hex.t) list option;
  depth : uint53;
  refund : uint53;
  error : string option;
}

let decode_value decode =
  let open Result_syntax in
  function
  | Rlp.Value b -> decode b
  | _ -> tzfail (error_of_fmt "Invalid RLP encoding for an expected value")

let decode_list decode =
  let open Result_syntax in
  function
  | Rlp.List l -> return (decode l)
  | _ -> tzfail (error_of_fmt "Invalid RLP encoding for an expected list")

let opcode_rlp_decoder bytes =
  let open Result_syntax in
  let* rlp = Rlp.decode bytes in
  match rlp with
  | Rlp.List
      [
        Value pc;
        Value op;
        Value gas;
        Value gas_cost;
        Value depth;
        error;
        stack;
        return_data;
        raw_memory;
        storage;
      ] ->
      let pc = Bytes.to_string pc |> Z.of_bits in
      let* op =
        if Bytes.length op > 1 then
          tzfail
            (error_of_fmt
               "Invalid opcode encoding: %a"
               Hex.pp
               (Hex.of_bytes op))
        else if Bytes.length op = 0 then return '\x00'
        else return (Bytes.get op 0)
      in
      let gas = Bytes.to_string gas |> Z.of_bits in
      let gas_cost = Bytes.to_string gas_cost |> Z.of_bits in
      let depth = Bytes.to_string depth |> Z.of_bits in
      let* error =
        Rlp.decode_option
          (decode_value (fun e -> return @@ Bytes.to_string e))
          error
      in
      let* return_data =
        Rlp.decode_option
          (decode_value (fun d -> return @@ Hex.of_bytes d))
          return_data
      in
      let* stack =
        Rlp.decode_option
          (decode_list
          @@ List.filter_map (function
                 | Rlp.List _ -> None
                 | Rlp.Value v -> Some (Hex.of_bytes v)))
          stack
      in
      let* raw_memory = Rlp.decode_option (decode_value return) raw_memory in
      let mem_size =
        Option.map (fun m -> Bytes.length m |> Int32.of_int) raw_memory
      in
      let* memory =
        Option.map_e
          (fun memory ->
            let* chunks = TzString.chunk_bytes 32 memory in
            return @@ List.map Hex.of_string chunks)
          raw_memory
      in
      let* storage =
        let parse_storage_index = function
          | Rlp.List [Value _; Value index; Value value] ->
              Some (Hex.of_bytes index, Hex.of_bytes value)
          | _ -> None
        in
        Rlp.decode_option
          (decode_list (List.filter_map parse_storage_index))
          storage
      in
      return
        {
          pc;
          op;
          gas;
          gas_cost;
          memory;
          mem_size;
          stack;
          return_data;
          storage;
          depth;
          refund = Z.zero;
          error;
        }
  | _ -> tzfail (error_of_fmt "Invalid rlp encoding for opcode: %a" Rlp.pp rlp)

let opcode_encoding =
  let open Data_encoding in
  conv
    (fun {
           pc;
           op;
           gas;
           gas_cost;
           memory;
           mem_size;
           stack;
           return_data;
           storage;
           depth;
           refund;
           error;
         } ->
      ( ( pc,
          op,
          gas,
          gas_cost,
          memory,
          mem_size,
          stack,
          return_data,
          storage,
          depth ),
        (refund, error) ))
    (fun ( ( pc,
             op,
             gas,
             gas_cost,
             memory,
             mem_size,
             stack,
             return_data,
             storage,
             depth ),
           (refund, error) ) ->
      {
        pc;
        op;
        gas;
        gas_cost;
        memory;
        mem_size;
        stack;
        return_data;
        storage;
        depth;
        refund;
        error;
      })
    (merge_objs
       (obj10
          (req "pc" uint53_encoding)
          (req "op" Opcode.encoding)
          (req "gas" uint53_encoding)
          (req "gasCost" uint53_encoding)
          (req "memory" (option (list hex_encoding)))
          (req "memSize" (option int32))
          (req "stack" (option (list hex_encoding)))
          (req "returnData" (option hex_encoding))
          (req "storage" (option (list (tup2 hex_encoding hex_encoding))))
          (req "depth" uint53_encoding))
       (obj2 (req "refund" uint53_encoding) (req "error" (option string))))

type output = {
  gas : int64;
  failed : bool;
  return_value : Ethereum_types.hash;
  struct_logs : opcode_log list;
}

let output_encoding =
  let open Data_encoding in
  conv
    (fun {gas; failed; return_value; struct_logs} ->
      (gas, failed, return_value, struct_logs))
    (fun (gas, failed, return_value, struct_logs) ->
      {gas; failed; return_value; struct_logs})
    (obj4
       (req "gas" int64)
       (req "failed" bool)
       (req "returnValue" Ethereum_types.hash_encoding)
       (req "structLogs" (list opcode_encoding)))

let output_binary_decoder ~gas ~failed ~return_value ~struct_logs =
  let open Result_syntax in
  let gas =
    Ethereum_types.decode_number gas |> fun (Ethereum_types.Qty z) ->
    Z.to_int64 z
  in
  let failed =
    if Bytes.length failed = 0 then false else Bytes.get failed 0 = '\x01'
  in
  let return_value =
    let (`Hex hex_value) = Hex.of_bytes return_value in
    Ethereum_types.hash_of_string hex_value
  in
  let* struct_logs = List.map_e opcode_rlp_decoder struct_logs in
  return {gas; failed; return_value; struct_logs}
