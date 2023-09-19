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

open Lwt_result_syntax

let print_failures f =
  let*! o = f in
  match o with
  | Ok () -> Lwt.return_unit
  | Error e ->
      let () = Error_monad.pp_print_trace Format.err_formatter e in
      Lwt.return_unit

let split_endorsements_preendorsements operations =
  List.fold_left
    (fun (en, pre) (Consensus_ops.{op = {kind; _}; _} as x) ->
      match kind with
      | Consensus_ops.Preendorsement -> (en, x :: pre)
      | Consensus_ops.Endorsement -> (x :: en, pre))
    ([], [])
    operations

module Ring =
  Aches.Vache.Set (Aches.Vache.FIFO_Precise) (Aches.Vache.Strong)
    (struct
      type t = Int32.t

      let hash = Hashtbl.hash

      let equal = Int32.equal
    end)

let registered_rights_levels = Ring.create 120

let rights_machine = Protocol_hash.Table.create 10

let block_machine = Protocol_hash.Table.create 10

let endorsement_machine = Protocol_hash.Table.create 10

let validated_block_machine = Protocol_hash.Table.create 10

let live_block_machine = Protocol_hash.Table.create 10

let maybe_add_rights (module A : Archiver.S) level rights =
  if Ring.mem registered_rights_levels level then ()
  else
    let () = Ring.add registered_rights_levels level in
    A.add_rights ~level rights

let dump_my_current_endorsements (module A : Archiver.S) ~unaccurate ~level
    rights endorsements =
  let () = maybe_add_rights (module A) level rights in
  let () = A.add_mempool ~unaccurate ~level endorsements in
  return_unit

module Define (Services : Protocol_machinery.PROTOCOL_SERVICES) = struct
  let rights_of ctxt level =
    let cctx = Services.wrap_full ctxt in
    Services.endorsing_rights cctx ~reference_level:level level

  let () = Protocol_hash.Table.add rights_machine Services.hash rights_of

  let block_info_data (delegate, timestamp, round, hash, predecessor) cycle_info
      reception_times =
    Data.Block.
      {
        delegate;
        timestamp;
        round = Int32.of_int round;
        hash;
        predecessor;
        nonce = None;
        cycle_info;
        reception_times;
      }

  let block_data cctx ((_, _, _, hash, _) as info) cycle_info reception_times =
    let* operations = Services.consensus_ops_info_of_block cctx hash in
    return
      ( block_info_data info cycle_info reception_times,
        split_endorsements_preendorsements operations )

  let block_of ctxt level =
    let cctx = Services.wrap_full ctxt in
    let* block_info = Services.get_block_info cctx level in
    block_data cctx block_info None []

  let () = Protocol_hash.Table.add block_machine Services.hash block_of

  let get_validated_block ctxt level hash header reception_times =
    let cctx = Services.wrap_full ctxt in
    let timestamp = header.Block_header.shell.Block_header.timestamp in
    let*? round = Services.block_round header in
    let* delegate = Services.baking_right cctx level round in
    let predecessor = Some header.Block_header.shell.Block_header.predecessor in
    return
      ( block_info_data
          (delegate, timestamp, round, hash, predecessor)
          None
          reception_times,
        ([], []) )

  let () =
    Protocol_hash.Table.add
      validated_block_machine
      Services.hash
      get_validated_block

  let get_applied_block ctxt hash header reception_times =
    let cctx = Services.wrap_full ctxt in
    let timestamp = header.Block_header.shell.Block_header.timestamp in
    let*? round = Services.block_round header in
    let* delegate, (cycle, cycle_position, cycle_size) =
      Services.baker_and_cycle cctx hash
    in
    let predecessor = Some header.Block_header.shell.Block_header.predecessor in
    block_data
      cctx
      (delegate, timestamp, round, hash, predecessor)
      (Some {cycle; cycle_position; cycle_size})
      reception_times

  let () =
    Protocol_hash.Table.add
      live_block_machine
      Services.hash
      (rights_of, get_applied_block)

  let rec pack_by_slot i e = function
    | ((i', l) as x) :: t ->
        if Int.equal i i' then (i, e :: l) :: t else x :: pack_by_slot i e t
    | [] -> [(i, [e])]

  (* [couple_ops_to_rights ops rights] returns [(participating,
     missing)], where [participating] is a list associating delegates
     with their operations in [ops], and [missing] is the list of
     delegates which do not have associated operations in [ops].

     TODO: it might be clearer to use a map instead of an association
     list for [participating]. *)
  let couple_ops_to_rights ops rights =
    let items, missing =
      List.fold_left
        (fun (acc, rights) (slot, ops) ->
          match
            List.partition
              (fun right -> Int.equal slot right.Consensus_ops.first_slot)
              rights
          with
          | ([] | _ :: _ :: _), _ -> assert false
          | [right], rights' -> ((right, ops) :: acc, rights'))
        ([], rights)
        ops
    in
    (items, missing)

  let endorsements_recorder (module A : Archiver.S) cctx current_level =
    let cctx' = Services.wrap_full cctx in
    let* op_stream, _stopper = Services.consensus_operation_stream cctx' in
    let*! out =
      Lwt_stream.fold
        (fun ((hash, ((block, level, kind, round), slot)), errors) acc ->
          let reception_time = Time.System.now () in
          let op =
            Consensus_ops.{op = {hash; kind; round}; errors; reception_time}
          in
          Services.BlockIdMap.update
            block
            (function
              | Some (_, l) -> Some (level, pack_by_slot slot op l)
              | None -> Some (level, [(slot, [op])]))
            acc)
        op_stream
        Services.BlockIdMap.empty
    in
    Services.BlockIdMap.iter_ep
      (fun _ (level, endorsements) ->
        let* rights =
          Services.endorsing_rights cctx' ~reference_level:current_level level
        in
        let items, missing = couple_ops_to_rights endorsements rights in
        let full = Compare.Int32.(current_level = level) in
        let endorsements =
          if full then
            List.fold_left (fun acc right -> (right, []) :: acc) items missing
          else items
        in
        dump_my_current_endorsements
          (module A)
          ~unaccurate:(not full)
          ~level
          rights
          endorsements)
      out

  let () =
    Protocol_hash.Table.add
      endorsement_machine
      Services.hash
      endorsements_recorder
end

module Loops (Archiver : Archiver.S) = struct
  let mecanism chain starting ctxt f =
    let rec loop current ending =
      if current > ending then
        let* {level; _} =
          Tezos_shell_services.Shell_services.Blocks.Header.shell_header
            ctxt
            ~chain
            ~block:(`Head 0)
            ()
        in
        if Int32.equal level ending then return_unit else loop current level
      else
        let* protos =
          Tezos_shell_services.Shell_services.Blocks.protocols
            ctxt
            ~chain
            ~block:(`Level current)
            ()
        in
        let* () = f protos current in
        loop (Int32.succ current) ending
    in
    let* {level = ending; _} =
      Tezos_shell_services.Shell_services.Blocks.Header.shell_header
        ctxt
        ~chain
        ~block:(`Head 0)
        ()
    in
    loop starting ending

  let rights chain starting cctx =
    mecanism chain starting cctx (fun {next_protocol; _} level ->
        match Protocol_hash.Table.find rights_machine next_protocol with
        | Some deal_with ->
            let* rights = deal_with cctx level in
            let () = maybe_add_rights (module Archiver) level rights in
            return_unit
        | None -> return_unit)

  let applied_blocks chain starting cctx =
    mecanism chain starting cctx (fun {current_protocol; next_protocol} level ->
        if Protocol_hash.equal current_protocol next_protocol then
          match Protocol_hash.Table.find block_machine current_protocol with
          | Some deal_with ->
              let* block_data = deal_with cctx level in
              let () = Archiver.add_block ~level block_data in
              return_unit
          | None -> return_unit
        else return_unit
          (* hack to ignore transition block because they need their own instantiation of Block_services *))

  let endorsements_loop cctx =
    let*! head_stream = Shell_services.Monitor.heads cctx cctx#chain in
    match head_stream with
    | Error e ->
        let () = Error_monad.pp_print_trace Format.err_formatter e in
        Lwt.return_unit
    | Ok (head_stream, _stopper) ->
        let*! _ =
          Lwt_stream.fold_s
            (fun (hash, header) acc ->
              let*! endorsements_recorder, acc' =
                match acc with
                | Some (f, proto_level)
                  when proto_level
                       = header.Block_header.shell.Block_header.proto_level ->
                    Lwt.return (f, acc)
                | _ -> (
                    let*! proto_result =
                      Shell_services.Blocks.protocols
                        cctx
                        ~chain:cctx#chain
                        ~block:(`Hash (hash, 0))
                        ()
                    in
                    match proto_result with
                    | Error e -> Lwt.return ((fun _ _ -> fail e), None)
                    | Ok Shell_services.Blocks.{next_protocol; _} -> (
                        let recorder =
                          Protocol_hash.Table.find
                            endorsement_machine
                            next_protocol
                        in
                        match recorder with
                        | None ->
                            let*! () =
                              Lwt_fmt.eprintf
                                "no endorsement recorder found for protocol \
                                 %a@."
                                Protocol_hash.pp
                                next_protocol
                            in
                            Lwt.return ((fun _ _ -> return_unit), None)
                        | Some recorder ->
                            Lwt.return
                              ( recorder (module Archiver),
                                Some
                                  ( recorder (module Archiver),
                                    header.Block_header.shell
                                      .Block_header.proto_level ) )))
              in
              let block_level = header.Block_header.shell.Block_header.level in
              let*! () =
                print_failures (endorsements_recorder cctx block_level)
              in
              Lwt.return acc')
            head_stream
            None
        in
        Lwt.return_unit

  let reception_blocks_loop cctx =
    let*! block_stream =
      Shell_services.Monitor.applied_blocks cctx ~chains:[cctx#chain] ()
    in
    match block_stream with
    | Error e ->
        let () = Error_monad.pp_print_trace Format.err_formatter e in
        Lwt.return_unit
    | Ok (block_stream, _stopper) ->
        let*! _ =
          Lwt_stream.fold_s
            (fun (_chain_id, hash, header, _operations) acc ->
              let*! block_recorder, acc' =
                match acc with
                | Some (f, proto_level)
                  when proto_level
                       = header.Block_header.shell.Block_header.proto_level ->
                    Lwt.return (f, acc)
                | _ -> (
                    let*! proto_result =
                      Shell_services.Blocks.protocols
                        cctx
                        ~chain:cctx#chain
                        ~block:(`Hash (hash, 0))
                        ()
                    in
                    match proto_result with
                    | Error e -> Lwt.return ((fun _ _ _ _ _ -> fail e), None)
                    | Ok Shell_services.Blocks.{current_protocol; next_protocol}
                      ->
                        if Protocol_hash.equal current_protocol next_protocol
                        then
                          let recorder =
                            Protocol_hash.Table.find
                              live_block_machine
                              next_protocol
                          in
                          match recorder with
                          | None ->
                              let*! () =
                                Lwt_fmt.eprintf
                                  "no block recorder found for protocol %a@."
                                  Protocol_hash.pp
                                  current_protocol
                              in
                              Lwt.return ((fun _ _ _ _ _ -> return_unit), None)
                          | Some (rights_of, get_applied_block) ->
                              let recorder cctx level hash header reception_time
                                  =
                                let* (( _block_info,
                                        (endorsements, preendorsements) ) as
                                     block_data) =
                                  get_applied_block
                                    cctx
                                    hash
                                    header
                                    reception_time
                                in
                                let* () =
                                  if List.is_empty endorsements then return_unit
                                  else
                                    let* rights =
                                      rights_of cctx (Int32.pred level)
                                    in
                                    let () =
                                      maybe_add_rights
                                        (module Archiver)
                                        (Int32.pred level)
                                        rights
                                    in
                                    return_unit
                                in
                                let* () =
                                  if List.is_empty preendorsements then
                                    return_unit
                                  else
                                    let* rights = rights_of cctx level in
                                    let () =
                                      maybe_add_rights
                                        (module Archiver)
                                        level
                                        rights
                                    in
                                    return_unit
                                in
                                let () = Archiver.add_block ~level block_data in
                                return_unit
                              in
                              Lwt.return
                                ( recorder,
                                  Some
                                    ( recorder,
                                      header.Block_header.shell
                                        .Block_header.proto_level ) )
                        else
                          let*! () =
                            Lwt_fmt.eprintf
                              "skipping block %a, migrating from protocol %a \
                               to %a@."
                              Block_hash.pp
                              hash
                              Protocol_hash.pp
                              current_protocol
                              Protocol_hash.pp
                              next_protocol
                          in
                          Lwt.return ((fun _ _ _ _ _ -> return_unit), None))
              in
              let reception =
                {
                  Data.Block.source = "archiver";
                  application_time = Some (Time.System.now ());
                  validation_time = None;
                }
              in
              let block_level = header.Block_header.shell.Block_header.level in
              let*! () =
                print_failures
                  (block_recorder cctx block_level hash header [reception])
              in
              Lwt.return acc')
            block_stream
            None
        in
        Lwt.return_unit

  let validation_blocks_loop cctx =
    let*! block_stream =
      Shell_services.Monitor.validated_blocks cctx ~chains:[cctx#chain] ()
    in
    match block_stream with
    | Error e ->
        let () = Error_monad.pp_print_trace Format.err_formatter e in
        Lwt.return_unit
    | Ok (block_stream, _stopper) ->
        let*! _ =
          Lwt_stream.fold_s
            (fun (_chain_id, hash, header, _operations) acc ->
              let*! block_recorder, acc' =
                match acc with
                | Some (f, proto_level)
                  when proto_level
                       = header.Block_header.shell.Block_header.proto_level ->
                    Lwt.return (f, acc)
                | _ -> (
                    let*! proto_result =
                      Shell_services.Blocks.protocols
                        cctx
                        ~chain:cctx#chain
                        ~block:
                          (`Level
                            (Int32.pred
                               header.Block_header.shell.Block_header.level))
                        ()
                    in
                    match proto_result with
                    | Error e -> Lwt.return ((fun _ _ _ _ _ -> fail e), None)
                    | Ok Shell_services.Blocks.{next_protocol; _} -> (
                        let recorder =
                          Protocol_hash.Table.find
                            validated_block_machine
                            next_protocol
                        in
                        match recorder with
                        | None ->
                            let*! () =
                              Lwt_fmt.eprintf
                                "no block recorder found for protocol %a@."
                                Protocol_hash.pp
                                next_protocol
                            in
                            Lwt.return ((fun _ _ _ _ _ -> return_unit), None)
                        | Some get_validated_block ->
                            let recorder cctx level hash header reception_time =
                              let* block_data =
                                get_validated_block
                                  cctx
                                  level
                                  hash
                                  header
                                  reception_time
                              in
                              let () = Archiver.add_block ~level block_data in
                              return_unit
                            in
                            Lwt.return
                              ( recorder,
                                Some
                                  ( recorder,
                                    header.Block_header.shell
                                      .Block_header.proto_level ) )))
              in
              let reception =
                {
                  Data.Block.source = "archiver";
                  application_time = None;
                  validation_time = Some (Time.System.now ());
                }
              in
              let block_level = header.Block_header.shell.Block_header.level in
              let*! () =
                print_failures
                  (block_recorder cctx block_level hash header [reception])
              in
              Lwt.return acc')
            block_stream
            None
        in
        Lwt.return_unit

  let blocks_loop cctx =
    Lwt.Infix.(reception_blocks_loop cctx <&> validation_blocks_loop cctx)
end

module Json_loops = Loops (Json_archiver)
module Server_loops = Loops (Server_archiver)
