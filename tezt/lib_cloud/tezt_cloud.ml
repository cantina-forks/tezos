(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* SPDX-FileCopyrightText: 2024 Nomadic Labs <contact@nomadic-labs.com>      *)
(*                                                                           *)
(*****************************************************************************)

module Agent = Agent

module Configuration = struct
  include Env
  include Configuration
end

module Cloud = Cloud

let register_docker_push ~tags =
  Cloud.register
    ?vms:None
    ~__FILE__
    ~title:"Push the dockerfile to the GCP registry"
    ~tags:("docker" :: "push" :: tags)
  @@ fun _cloud -> Jobs.docker_build ~push:true ()

let register_docker_build ~tags =
  Cloud.register
    ?vms:None
    ~__FILE__
    ~title:"Build the dockerfile"
    ~tags:("docker" :: "build" :: tags)
  @@ fun _cloud -> Jobs.docker_build ~push:false ()

let register_deploy_docker_registry ~tags =
  Cloud.register
    ?vms:None
    ~__FILE__
    ~title:"Deploy docker registry"
    ~tags:("docker" :: "registry" :: "deploy" :: tags)
  @@ fun _cloud -> Jobs.deploy_docker_registry ()

let register_destroy_vms ~tags =
  Cloud.register
    ?vms:None
    ~__FILE__
    ~title:"Destroy terraform VMs"
    ~tags:("terraform" :: "destroy" :: "vms" :: tags)
  @@ fun _cloud ->
  let tezt_cloud = Env.tezt_cloud in
  let* project_id = Gcloud.project_id () in
  let* workspaces = Terraform.VM.Workspace.list ~tezt_cloud in
  let* () = Terraform.VM.destroy workspaces ~project_id in
  Terraform.VM.Workspace.destroy ~tezt_cloud

let register_prometheus_import ~tags =
  Cloud.register
    ?vms:None
    ~__FILE__
    ~title:"Import a snapshot into a prometheus container"
    ~tags:("prometheus" :: "import" :: tags)
  @@ fun _cloud ->
  let* prometheus = Prometheus.run_with_snapshot () in
  Prometheus.shutdown prometheus

let register_clean_up_vms ~tags =
  Cloud.register
    ?vms:None
    ~__FILE__
    ~title:"Clean ups VMs manually"
    ~tags:("clean" :: "up" :: tags)
  @@ fun _cloud -> Jobs.clean_up_vms ()

let register_list_vms ~tags =
  Cloud.register
    ?vms:None
    ~__FILE__
    ~title:"List VMs"
    ~tags:("list" :: "vms" :: tags)
  @@ fun _cloud ->
  Log.info "TEZT_CLOUD environment variable found with value: %s" Env.tezt_cloud ;
  let* _ = Gcloud.list_vms ~prefix:Env.tezt_cloud in
  Lwt.return_unit

let register ~tags =
  register_docker_push ~tags ;
  register_docker_build ~tags ;
  register_deploy_docker_registry ~tags ;
  register_destroy_vms ~tags ;
  register_prometheus_import ~tags ;
  register_clean_up_vms ~tags ;
  register_list_vms ~tags
