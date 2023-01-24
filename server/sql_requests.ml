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

open Tezos_crypto
open Teztale_lib

(* TRUE/FALSE literals were introduced in Sqlite 3.23 (and are represented as
   the integers 1 and 0. To support older versions, we convert booleans to
   integers. *)
let bool_to_int b = if b then 1 else 0

let create_delegates =
  "  CREATE TABLE delegates(\n\
  \     id INTEGER PRIMARY KEY,\n\
  \     address BLOB UNIQUE NOT NULL,\n\
  \     alias TEXT)"

let create_nodes =
  "   CREATE TABLE nodes(\n\
  \     id INTEGER PRIMARY KEY,\n\
  \     name TEXT UNIQUE NOT NULL,\n\
  \     comment TEXT)"

let create_blocks =
  "   CREATE TABLE blocks(\n\
  \     id INTEGER PRIMARY KEY,\n\
  \     timestamp INTEGER NOT NULL, -- Unix time\n\
  \     hash BLOB UNIQUE NOT NULL,\n\
  \     level INTEGER NOT NULL,\n\
  \     round INTEGER NOT NULL,\n\
  \     baker INTEGER NOT NULL,\n\
  \     FOREIGN KEY (baker) REFERENCES delegates(id))"

let create_blocks_reception =
  "   CREATE TABLE blocks_reception(\n\
  \     id INTEGER PRIMARY KEY,\n\
  \     timestamp TEXT NOT NULL, -- ISO8601 string\n\
  \     block INTEGER NOT NULL,\n\
  \     source INTEGER NOT NULL,\n\
  \     FOREIGN KEY (block) REFERENCES blocks(id),\n\
  \     FOREIGN KEY (source) REFERENCES nodes(id),\n\
  \     UNIQUE (block, source))"

let create_operations =
  "   CREATE TABLE operations(\n\
  \     id INTEGER PRIMARY KEY,\n\
  \     hash BLOB UNIQUE NOT NULL,\n\
  \     endorsement INTEGER NOT NULL,\n\
  \     endorser INTEGER NOT NULL,\n\
  \     level INTEGER NOT NULL,\n\
  \     round INTEGER,\n\
  \     FOREIGN KEY (endorser) REFERENCES delegates(id))"

let create_operations_reception =
  "   CREATE TABLE operations_reception(\n\
  \     id INTEGER PRIMARY KEY,\n\
  \     timestamp TEXT NOT NULL, -- ISO8601 string\n\
  \     operation INTEGER NOT NULL,\n\
  \     source INTEGER NOT NULL,\n\
  \     errors BLOB,\n\
  \     FOREIGN KEY (operation) REFERENCES operations(id),\n\
  \     FOREIGN KEY (source) REFERENCES nodes(id),\n\
  \     UNIQUE (operation,source))"

let create_operations_inclusion =
  "   CREATE TABLE operations_inclusion(\n\
  \      id INTEGER PRIMARY KEY,\n\
  \      block INTEGER NOT NULL,\n\
  \      operation INTEGER NOT NULL,\n\
  \      FOREIGN KEY (block) REFERENCES blocks(id),\n\
  \      FOREIGN KEY (operation) REFERENCES operations(id),\n\
  \      UNIQUE (block, operation))"

let create_endorsing_rights =
  "   CREATE TABLE endorsing_rights(\n\
  \      id INTEGER PRIMARY KEY,\n\
  \      level INTEGER NOT NULL,\n\
  \      delegate INTEGER NOT NULL,\n\
  \      first_slot INTEGER NOT NULL,\n\
  \      endorsing_power INTEGER NOT NULL,\n\
  \      FOREIGN KEY (delegate) REFERENCES delegates(id),\n\
  \      UNIQUE (level, delegate))"

let create_endorsing_rights_level_idx =
  "   CREATE INDEX endorsing_rights_level_idx ON endorsing_rights(level)"

let create_operations_level_idx =
  "   CREATE INDEX operations_level_idx ON operations(level)"

let create_operations_reception_operation_idx =
  "   CREATE INDEX operations_reception_operation_idx ON \
   operations_reception(operation)"

let create_operations_inclusion_operation_idx =
  "   CREATE INDEX operations_inclusion_operation_idx ON \
   operations_inclusion(operation)"

let create_tables =
  [
    create_delegates;
    create_nodes;
    create_blocks;
    create_blocks_reception;
    create_operations;
    create_operations_reception;
    create_operations_inclusion;
    create_endorsing_rights;
    create_endorsing_rights_level_idx;
    create_operations_level_idx;
    create_operations_reception_operation_idx;
    create_operations_inclusion_operation_idx;
  ]

let db_schema = String.concat "; " create_tables

let maybe_insert_source source =
  "INSERT OR IGNORE INTO nodes (name) VALUES (\'" ^ source ^ "\')"

let maybe_insert_delegates_from_rights rights =
  Format.asprintf
    "INSERT OR IGNORE INTO delegates (address) VALUES %a"
    (Format.pp_print_list
       ~pp_sep:(fun f () -> Format.pp_print_text f ", ")
       (fun f r ->
         Format.fprintf
           f
           "(x'%a')"
           Hex.pp
           (Signature.Public_key_hash.to_hex r.Consensus_ops.address)))
    rights

let maybe_insert_endorsing_rights ~level rights =
  Format.asprintf
    "INSERT OR IGNORE INTO endorsing_rights (level, delegate, first_slot, \
     endorsing_power) SELECT column1, delegates.id, column3, column4 FROM \
     delegates JOIN (VALUES %a) ON delegates.address = column2"
    (Format.pp_print_list
       ~pp_sep:(fun f () -> Format.pp_print_text f ", ")
       (fun f Teztale_lib.Consensus_ops.{address; first_slot; power} ->
         Format.fprintf
           f
           "(%ld, x'%a', %d, %d)"
           level
           Hex.pp
           (Signature.Public_key_hash.to_hex address)
           first_slot
           power))
    rights

let maybe_insert_operations level extractor op_extractor l =
  Format.asprintf
    "INSERT INTO operations (hash, endorsement, endorser, level, round) SELECT \
     column1, column2, delegates.id, %ld, column4 FROM delegates JOIN (VALUES \
     %a) ON delegates.address = column3 WHERE (column2, delegates.id, column4) \
     NOT IN (SELECT endorsement, endorser, round FROM operations WHERE level = \
     %ld)"
    level
    (Format.pp_print_list
       ~pp_sep:(fun f () -> Format.pp_print_text f ", ")
       (fun f x ->
         let delegate, ops = extractor x in
         Format.pp_print_list
           ~pp_sep:(fun f () -> Format.pp_print_text f ", ")
           (fun f y ->
             let op = op_extractor y in
             Format.fprintf
               f
               "(x'%a', %d, x'%a', %a)"
               Hex.pp
               (Operation_hash.to_hex op.Consensus_ops.hash)
               (bool_to_int (op.Consensus_ops.kind = Consensus_ops.Endorsement))
               Hex.pp
               (Signature.Public_key_hash.to_hex delegate)
               (Format.pp_print_option
                  ~none:(fun f () -> Format.pp_print_string f "NULL")
                  (fun f x -> Format.fprintf f "%li" x))
               op.Consensus_ops.round)
           f
           ops))
    l
    level

let maybe_insert_operations_from_block ~level operations =
  maybe_insert_operations
    level
    (fun op -> Consensus_ops.(op.delegate, [op.op]))
    (fun x -> x)
    operations

let maybe_insert_operations_from_received ~level operations =
  let operations = List.filter (fun (_, l) -> l <> []) operations in
  maybe_insert_operations
    level
    (fun (delegate, ops) -> (delegate, ops))
    (fun (op : Consensus_ops.received_operation) -> op.op)
    operations

let maybe_insert_delegates_from_received operations =
  Format.asprintf
    "INSERT OR IGNORE INTO delegates (address) VALUES %a"
    (Format.pp_print_list
       ~pp_sep:(fun f () -> Format.pp_print_text f ", ")
       (fun f (address, _) ->
         Format.fprintf
           f
           "(x'%a')"
           Hex.pp
           (Signature.Public_key_hash.to_hex address)))
    operations

let maybe_insert_block hash ~level ~round timestamp delegate =
  Format.asprintf
    "INSERT OR IGNORE INTO blocks (timestamp, hash, level, round, baker) \
     SELECT column1, column2, %ld, column4, delegates.id FROM delegates JOIN \
     (VALUES ('%a', x'%a', x'%a', %ld)) ON delegates.address = column3"
    level
    Tezos_base.Time.Protocol.pp
    timestamp
    Hex.pp
    (Block_hash.to_hex hash)
    Hex.pp
    (Signature.Public_key_hash.to_hex delegate)
    round

let insert_received_operations ~source ~level operations =
  let operations = List.filter (fun (_, l) -> l <> []) operations in
  Format.asprintf
    "INSERT OR IGNORE INTO operations_reception (timestamp, operation, source, \
     errors) SELECT column1, operations.id, nodes.id, column2 FROM operations, \
     delegates, nodes, (VALUES %a) ON delegates.address = column3 AND \
     operations.endorser = delegates.id AND operations.endorsement = column4 \
     AND ((operations.round IS NULL AND column5 IS NULL) OR operations.round = \
     column5) WHERE nodes.name = '%s' AND operations.level = %ld"
    (Format.pp_print_list
       ~pp_sep:(fun f () -> Format.pp_print_text f ", ")
       (fun f (endorser, l) ->
         (Format.pp_print_list
            ~pp_sep:(fun f () -> Format.pp_print_text f ", ")
            (fun f (op : Consensus_ops.received_operation) ->
              Format.fprintf
                f
                "('%a', %a, x'%a', %d, %a)"
                Tezos_base.Time.System.pp_hum
                op.reception_time
                (Format.pp_print_option
                   ~none:(fun f () -> Format.pp_print_string f "NULL")
                   (fun f errors ->
                     Format.fprintf
                       f
                       "x'%a'"
                       Hex.pp
                       (Hex.of_bytes
                          (Data_encoding.Binary.to_bytes_exn
                             (Data_encoding.list
                                Tezos_error_monad.Error_monad.error_encoding)
                             errors))))
                op.errors
                Hex.pp
                (Signature.Public_key_hash.to_hex endorser)
                (bool_to_int
                   (op.op.Consensus_ops.kind = Consensus_ops.Endorsement))
                (Format.pp_print_option
                   ~none:(fun f () -> Format.pp_print_string f "NULL")
                   (fun f x -> Format.fprintf f "%li" x))
                op.Consensus_ops.op.round))
           f
           l))
    operations
    source
    level

let insert_included_operations block_hash ~level operations =
  Format.asprintf
    "INSERT OR IGNORE INTO operations_inclusion (block, operation) SELECT \
     blocks.id, operations.id FROM operations, delegates, blocks, (VALUES %a) \
     ON delegates.address = column1 AND operations.endorser = delegates.id AND \
     operations.endorsement = column2 AND ((operations.round IS NULL AND \
     column3 IS NULL) OR operations.round = column3) WHERE blocks.hash = x'%a' \
     AND operations.level = %ld"
    (Format.pp_print_list
       ~pp_sep:(fun f () -> Format.pp_print_text f ", ")
       (fun f (op : Consensus_ops.block_op) ->
         Format.fprintf
           f
           "(x'%a', %d, %a)"
           Hex.pp
           (Signature.Public_key_hash.to_hex op.Consensus_ops.delegate)
           (bool_to_int (op.op.Consensus_ops.kind = Consensus_ops.Endorsement))
           (Format.pp_print_option
              ~none:(fun f () -> Format.pp_print_string f "NULL")
              (fun f x -> Format.fprintf f "%li" x))
           op.Consensus_ops.op.round))
    operations
    Hex.pp
    (Block_hash.to_hex block_hash)
    level

let insert_received_block ~source hash reception_time =
  Format.asprintf
    "INSERT OR IGNORE INTO blocks_reception (timestamp, block, source) SELECT \
     '%a', blocks.id, nodes.id FROM blocks,nodes WHERE blocks.hash = x'%a' AND \
     nodes.name = '%s'"
    Tezos_base.Time.System.pp_hum
    reception_time
    Hex.pp
    (Block_hash.to_hex hash)
    source
