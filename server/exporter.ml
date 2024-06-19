(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

let maybe_with_metrics = Sql_requests.maybe_with_metrics

open Tezos_lwt_result_stdlib.Lwtreslib.Bare.Monad.Lwt_result_syntax

module Int32Map = Map.Make (Int32)

let parse_block_row ((level, hash, predecessor, delegate), (round, timestamp))
    acc =
  let blocks =
    match Int32Map.find_opt level acc with
    | Some m -> m
    | None -> Tezos_crypto.Hashed.Block_hash.Map.empty
  in
  let blocks =
    Tezos_crypto.Hashed.Block_hash.Map.add
      hash
      Teztale_lib.Data.Block.
        {
          hash;
          predecessor;
          delegate;
          round;
          reception_times = [];
          timestamp;
          nonce = None;
        }
      blocks
  in
  Int32Map.add level blocks acc

let parse_block_reception_row
    ((level, hash, application_time, validation_time), source) acc =
  let blocks =
    match Int32Map.find_opt level acc with
    | Some m -> m
    | None -> Tezos_crypto.Hashed.Block_hash.Map.empty
  in
  let blocks =
    Tezos_crypto.Hashed.Block_hash.Map.update
      hash
      (function
        | Some
            Teztale_lib.Data.Block.
              {
                hash;
                predecessor;
                delegate;
                round;
                reception_times;
                timestamp;
                nonce;
              } ->
            Some
              Teztale_lib.Data.Block.
                {
                  hash;
                  predecessor;
                  delegate;
                  round;
                  reception_times =
                    {source; application_time; validation_time}
                    :: reception_times;
                  timestamp;
                  nonce;
                }
        | None -> None)
      blocks
  in
  Int32Map.add level blocks acc

let select_single_cycle_info db_pool level =
  let cycle_request =
    Caqti_request.Infix.(Caqti_type.int32 ->? Caqti_type.(t3 int32 int32 int32))
      "SELECT id, level, size FROM cycles WHERE level = (SELECT MAX (level) \
       FROM cycles WHERE level <= $1)"
  in
  Caqti_lwt_unix.Pool.use
    (fun (module Db : Caqti_lwt.CONNECTION) -> Db.find_opt cycle_request level)
    db_pool

let select_cycles db_pool boundaries =
  let cycle_request =
    Caqti_request.Infix.(
      Caqti_type.(t2 int32 int32) ->* Caqti_type.(t3 int32 int32 int32))
      "SELECT id, level, size FROM cycles WHERE level >= (SELECT MAX(level) \
       FROM cycles WHERE level <= $1) AND level <= $2"
  in
  Caqti_lwt_unix.Pool.use
    (fun (module Db : Caqti_lwt.CONNECTION) ->
      Db.fold
        cycle_request
        (fun (id, level, size) acc -> (id, level, size) :: acc)
        boundaries
        [])
    db_pool

module RoundBakerMap = Map.Make (struct
  type t = Int32.t * Tezos_crypto.Signature.public_key_hash

  (* No need for comparing delegates since round in unique within a level *)
  let compare (r1, _) (r2, _) = Int32.compare r1 r2
end)

let select_missing_blocks_request =
  Caqti_request.Infix.(
    Caqti_type.(t2 int32 int32)
    ->* Caqti_type.(t4 string int32 int32 Sql_requests.Type.public_key_hash))
    "SELECT\n\
    \  nodes.name,\n\
    \  missing_blocks.level,\n\
    \  missing_blocks.round,\n\
    \  delegates.address\n\
     FROM missing_blocks\n\
     JOIN nodes ON nodes.id = missing_blocks.source\n\
     JOIN delegates ON delegates.id = missing_blocks.baker\n\
     WHERE missing_blocks.level >= $1\n\
     AND missing_blocks.level <= $2"

let select_missing_blocks_parse (source, level, round, baker) acc =
  Int32Map.update
    level
    (function
      | None ->
          Some (RoundBakerMap.add (round, baker) [source] RoundBakerMap.empty)
      | Some data ->
          Some
            (RoundBakerMap.update
               (round, baker)
               (function
                 | None -> Some [source]
                 | Some sources -> Some (source :: sources))
               data))
    acc

let select_missing_blocks conf db_pool boundaries =
  Caqti_lwt_unix.Pool.use
    (fun (module Db : Caqti_lwt.CONNECTION) ->
      maybe_with_metrics conf "select_missing_blocks" @@ fun () ->
      Db.fold
        select_missing_blocks_request
        select_missing_blocks_parse
        boundaries
        Int32Map.empty)
    db_pool

let select_blocks conf db_pool boundaries =
  let block_request =
    Caqti_request.Infix.(
      Caqti_type.(t2 int32 int32)
      ->* Caqti_type.(
            t2
              (t4
                 int32
                 Sql_requests.Type.block_hash
                 (option Sql_requests.Type.block_hash)
                 Sql_requests.Type.public_key_hash)
              (t2 int32 Sql_requests.Type.time_protocol)))
      "SELECT b.level, b.hash, p.hash, d.address, b.round, b.timestamp FROM \
       blocks b JOIN delegates d ON d.id = b.baker LEFT JOIN blocks p ON p.id \
       = b.predecessor WHERE b.level >= ? AND b.level <= ?"
  in
  let* blocks =
    Caqti_lwt_unix.Pool.use
      (fun (module Db : Caqti_lwt.CONNECTION) ->
        maybe_with_metrics conf "select_blocks" @@ fun () ->
        Db.fold block_request parse_block_row boundaries Int32Map.empty)
      db_pool
  in
  let reception_request =
    Caqti_request.Infix.(
      Caqti_type.(t2 int32 int32)
      ->* Caqti_type.(
            t2
              (t4
                 int32
                 Sql_requests.Type.block_hash
                 (option ptime)
                 (option ptime))
              string))
      "SELECT b.level, b.hash, r.application_timestamp, \
       r.validation_timestamp, n.name FROM blocks b JOIN blocks_reception r ON \
       r.block = b.id JOIN nodes n ON n.id = r.source WHERE b.level >= ? AND \
       b.level <= ?"
  in
  Caqti_lwt_unix.Pool.use
    (fun (module Db : Caqti_lwt.CONNECTION) ->
      maybe_with_metrics conf "select_blocks_reception" @@ fun () ->
      Db.fold reception_request parse_block_reception_row boundaries blocks)
    db_pool

type op_info = {
  kind : Teztale_lib.Consensus_ops.operation_kind;
  round : Int32.t option;
  included : Tezos_crypto.Hashed.Block_hash.t list;
  received : Teztale_lib.Data.Delegate_operations.reception list;
}

let kind_of_bool = function
  | false -> Teztale_lib.Consensus_ops.Preendorsement
  | true -> Teztale_lib.Consensus_ops.Endorsement

let select_ops conf db_pool boundaries =
  (* We make 3 queries:
     - one to detect "missing" ops (not included, not received)
     - one to detect included ops
     - one to detect received ops
     We then combine the results.
  *)
  let q_rights =
    Caqti_request.Infix.(
      Caqti_type.(t2 int32 int32)
      ->* Caqti_type.(t4 int32 Sql_requests.Type.public_key_hash int int))
      "SELECT e.level, d.address, e.first_slot, e.endorsing_power FROM \
       endorsing_rights e JOIN delegates d ON e.delegate = d.id WHERE e.level \
       >= ? AND e.level <= ?"
  in
  let q_included =
    Caqti_request.Infix.(
      Caqti_type.(t2 int32 int32)
      ->* Caqti_type.(
            t2
              (t4 int32 Sql_requests.Type.public_key_hash bool (option int32))
              (t2 Sql_requests.Type.operation_hash Sql_requests.Type.block_hash)))
      "SELECT o.level, d.address, o.endorsement, o.round, o.hash, b.hash FROM \
       operations o JOIN operations_inclusion i ON i.operation = o.id JOIN \
       delegates d ON o.endorser = d.id JOIN blocks b ON i.block = b.id WHERE \
       o.level >= ? AND o.level <= ?"
  in
  let q_received =
    Caqti_request.Infix.(
      Caqti_type.(t2 int32 int32)
      ->* Caqti_type.(
            t2
              (t4
                 int32
                 Sql_requests.Type.public_key_hash
                 ptime
                 Sql_requests.Type.operation_hash)
              (t4 Sql_requests.Type.errors string bool (option int32))))
      "SELECT o.level, d.address, r.timestamp, o.hash, r.errors, n.name, \
       o.endorsement, o.round FROM operations o JOIN operations_reception r ON \
       r.operation = o.id JOIN delegates d ON o.endorser = d.id JOIN nodes n \
       ON n.id = r.source WHERE o.level >= ? AND o.level <= ?"
  in
  let module Ops = Tezos_crypto.Signature.Public_key_hash.Map in
  let cb_rights (level, delegate, first_slot, power) info =
    let ops =
      match Int32Map.find_opt level info with Some m -> m | None -> Ops.empty
    in
    let ops =
      Ops.add
        delegate
        (first_slot, power, Tezos_crypto.Hashed.Operation_hash.Map.empty)
        ops
    in
    Int32Map.add level ops info
  in
  let cb_included ((level, delegate, endorsement, round), (op_hash, block_hash))
      info =
    let ops =
      match Int32Map.find_opt level info with Some m -> m | None -> Ops.empty
    in
    let kind = kind_of_bool endorsement in
    let ops =
      Ops.update
        delegate
        (function
          | Some (first_slot, power, ops) ->
              let op =
                match
                  Tezos_crypto.Hashed.Operation_hash.Map.find_opt op_hash ops
                with
                | Some op_info ->
                    {op_info with included = block_hash :: op_info.included}
                | None -> {kind; round; included = [block_hash]; received = []}
              in
              let ops' =
                Tezos_crypto.Hashed.Operation_hash.Map.add op_hash op ops
              in
              Some (first_slot, power, ops')
          | None -> None)
        ops
    in
    Int32Map.add level ops info
  in

  let cb_received
      ( (level, delegate, reception_time, op_hash),
        (errors, source, endorsement, round) ) info =
    let ops =
      match Int32Map.find_opt level info with Some m -> m | None -> Ops.empty
    in
    let kind = kind_of_bool endorsement in
    let received_info =
      Teztale_lib.Data.Delegate_operations.{source; reception_time; errors}
    in
    let ops =
      Ops.update
        delegate
        (function
          | Some (first_slot, power, ops) ->
              let op =
                match
                  Tezos_crypto.Hashed.Operation_hash.Map.find_opt op_hash ops
                with
                | Some op_info ->
                    {op_info with received = received_info :: op_info.received}
                | None ->
                    {kind; round; included = []; received = [received_info]}
              in
              let ops' =
                Tezos_crypto.Hashed.Operation_hash.Map.add op_hash op ops
              in
              Some (first_slot, power, ops')
          | None -> None)
        ops
    in
    Int32Map.add level ops info
  in
  let* out =
    Caqti_lwt_unix.Pool.use
      (fun (module Db : Caqti_lwt.CONNECTION) ->
        maybe_with_metrics conf "select_operations_rights" @@ fun () ->
        Db.fold q_rights cb_rights boundaries Int32Map.empty)
      db_pool
  in
  let* out =
    Caqti_lwt_unix.Pool.use
      (fun (module Db : Caqti_lwt.CONNECTION) ->
        maybe_with_metrics conf "select_operations_inclusion" @@ fun () ->
        Db.fold q_included cb_included boundaries out)
      db_pool
  in
  Caqti_lwt_unix.Pool.use
    (fun (module Db : Caqti_lwt.CONNECTION) ->
      maybe_with_metrics conf "select_operations_reception" @@ fun () ->
      Db.fold q_received cb_received boundaries out)
    db_pool

let translate_ops info =
  let translate pkh_ops =
    Tezos_crypto.Hashed.Operation_hash.Map.fold
      (fun hash {kind; round; included; received} acc ->
        Teztale_lib.Data.Delegate_operations.
          {
            hash;
            kind;
            round;
            mempool_inclusion = received;
            block_inclusion = included;
          }
        :: acc)
      pkh_ops
      []
  in
  Int32Map.map
    (fun info ->
      Tezos_crypto.Signature.Public_key_hash.Map.fold
        (fun pkh (first_slot, power, pkh_ops) acc ->
          Teztale_lib.Data.Delegate_operations.
            {
              delegate = pkh;
              first_slot;
              endorsing_power = power;
              operations = translate pkh_ops;
            }
          :: acc)
        info
        [])
    info

(* NB: We're not yet extracting [Incorrect] operations. we easily
     could, they are quite noisy. At least in some cases, the "consensus
     operations for old/future round/level" errors should be seen as a
     "per block anomaly" rather than a "per delegate anomaly". *)
let anomalies level ops =
  let extract_anomalies delegate pkh_ops =
    let open Teztale_lib.Data.Anomaly in
    Tezos_crypto.Hashed.Operation_hash.Map.fold
      (fun _op_hash {kind; round; received; included} acc ->
        let problem =
          match (received, included) with
          | [], [] -> Some Missed
          | [], _ -> Some Sequestered
          | _, [] -> Some Forgotten
          | _ -> None
        in
        match problem with
        | None -> acc
        | Some problem -> {level; kind; round; delegate; problem} :: acc)
      pkh_ops
      []
  in
  Tezos_crypto.Signature.Public_key_hash.Map.fold
    (fun pkh (_first_slot, _power, pkh_ops) acc ->
      extract_anomalies pkh pkh_ops @ acc)
    ops
    []

let data_at_level_range conf db_pool boundaries =
  let cycles =
    (* FIXME: do better than a list *)
    let low, high = boundaries in
    if high = low then
      Lwt_result.map
        (function
          | Some (cycle_id, cycle_level, cycle_size) ->
              [(cycle_id, cycle_level, cycle_size)]
          | None -> [])
        (select_single_cycle_info db_pool high)
    else Lwt_result.map (List.sort compare) (select_cycles db_pool boundaries)
  in
  let missing_blocks = select_missing_blocks conf db_pool boundaries in
  let blocks = select_blocks conf db_pool boundaries in
  let* delegate_operations = select_ops conf db_pool boundaries in
  let* blocks in
  let* cycles in
  let* missing_blocks in
  let delegate_operations = translate_ops delegate_operations in
  let blocks =
    Int32Map.map
      (fun blocks ->
        Tezos_crypto.Hashed.Block_hash.Map.fold
          (fun _ x acc -> x :: acc)
          blocks
          [])
      blocks
  in
  let unaccurate = false in
  let result =
    Int32Map.fold
      (fun level blocks acc ->
        let delegate_operations =
          match Int32Map.find_opt level delegate_operations with
          | Some x -> x
          | None -> []
        in
        let cycle_info =
          match
            List.find_opt
              (fun (_, cycle_level, cycle_size) ->
                cycle_level <= level && Int32.add cycle_level cycle_size > level)
              cycles
          with
          | Some (cycle_id, cycle_level, cycle_size) ->
              Some
                Teztale_lib.Data.
                  {
                    cycle = cycle_id;
                    cycle_position = Int32.sub level cycle_level;
                    cycle_size;
                  }
          | None -> None
        in
        let missing_blocks =
          match Int32Map.find_opt level missing_blocks with
          | None -> []
          | Some missing_blocks ->
              RoundBakerMap.fold
                (fun (round, delegate) sources acc ->
                  Teztale_lib.Data.{baking_right = {round; delegate}; sources}
                  :: acc)
                missing_blocks
                []
        in
        Teztale_lib.Data.
          {
            level;
            data =
              Teztale_lib.Data.
                {
                  cycle_info;
                  blocks;
                  delegate_operations;
                  unaccurate;
                  missing_blocks;
                };
          }
        :: acc)
      blocks
      []
  in
  return result

let anomalies_at_level conf db_pool level =
  let* ops = select_ops conf db_pool (level, level) in
  let ops = Int32Map.find level ops in
  return (anomalies level ops)
