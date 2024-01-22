(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2024 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

include Internal_event.Simple

let section = ["evm_node"; "dev"; "blueprint"]

let publisher_ready =
  declare_0
    ~section
    ~name:"evm_node_dev_blueprint_publisher_is_ready"
    ~msg:"Blueprint publisher is ready"
    ~level:Info
    ()

let publisher_shutdown =
  declare_0
    ~section
    ~name:"evm_node_dev_blueprint_publisher_shutdown"
    ~msg:"Blueprint publishing is shutting down"
    ~level:Info
    ()

let blueprint_injection =
  declare_1
    ~section
    ~name:"evm_node_dev_blueprint_injection"
    ~msg:"Injecting a blueprint for level {level}"
    ~level:Info
    ("level", Data_encoding.n)

let worker_enters_degraded_mode =
  declare_1
    ~section
    ~name:"evm_node_dev_blueprint_degraded"
    ~msg:
      "Could not inject a blueprint for level {level}, entering degraded mode"
    ~level:Error
    ("level", Data_encoding.n)

let publisher_is_ready () = emit publisher_ready ()

let publisher_shutdown () = emit publisher_shutdown ()

let blueprint_injected level = emit blueprint_injection level

let entered_degraded_mode level = emit worker_enters_degraded_mode level
