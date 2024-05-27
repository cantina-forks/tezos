(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2024 Nomadic Labs. <contact@nomadic-labs.com>               *)
(* Copyright (c) 2024 TriliTech <contact@trili.tech>                         *)
(*                                                                           *)
(*****************************************************************************)

(* This module contains the definition of stages and Docker
   images used by the Octez CI pipelines.

   It also defines:
    - helpers for defining jobs;
    - changesets shared by jobs;
    - helpers for making jobs;
    - jobs shared between pipelines *)

open Gitlab_ci.Types
open Gitlab_ci.Util
open Tezos_ci

(* Define [stages:]

   The "manual" stage exists to fix a UI problem that occurs when mixing
   manual and non-manual jobs. *)
module Stages = struct
  let start = Stage.register "start"

  (* All automatic image creation is done in the stage [images]. *)
  let images = Stage.register "images"

  let sanity = Stage.register "sanity"

  let build = Stage.register "build"

  let test = Stage.register "test"

  let test_coverage = Stage.register "test_coverage"

  let packaging = Stage.register "packaging"

  let doc = Stage.register "doc"

  let prepare_release = Stage.register "prepare_release"

  let publish_release_gitlab = Stage.register "publish_release_gitlab"

  let publish_release = Stage.register "publish_release"

  let publish_package_gitlab = Stage.register "publish_package_gitlab"

  let manual = Stage.register "manual"
end

(* Get the [build_deps_image_version] from the environment, which is
   typically set by sourcing [scripts/version.sh]. This is used to write
   [build_deps_image_version] in the top-level [variables:], used to
   specify the versions of the [build_deps] images. *)
let build_deps_image_version =
  match Sys.getenv_opt "opam_repository_tag" with
  | None ->
      failwith
        "Please set the environment variable [opam_repository_tag], by e.g. \
         sourcing [scripts/version.sh] before running."
  | Some v -> v

(* Get the [alpine_version] from the environment, which is typically
   set by sourcing [scripts/version.sh]. This is used to set the tag
   of the image {!Images.alpine}. *)
let alpine_version =
  match Sys.getenv_opt "alpine_version" with
  | None ->
      failwith
        "Please set the environment variable [alpine_version], by e.g. \
         sourcing [scripts/version.sh] before running."
  | Some v -> v

(* Register external images.

   Use this module to register images that are as built outside the
   [tezos/tezos] CI.

   For documentation on the [runtime_X_dependencies] and the
   [rust_toolchain] images, refer to
   {{:https://gitlab.com/tezos/opam-repository/}
   tezos/opam-repository}. *)
module Images_external = struct
  let runtime_e2etest_dependencies =
    Image.mk_external
      ~image_path:
        "${build_deps_image_name}:runtime-e2etest-dependencies--${build_deps_image_version}"

  let runtime_build_test_dependencies =
    Image.mk_external
      ~image_path:
        "${build_deps_image_name}:runtime-build-test-dependencies--${build_deps_image_version}"

  let runtime_build_dependencies =
    Image.mk_external
      ~image_path:
        "${build_deps_image_name}:runtime-build-dependencies--${build_deps_image_version}"

  let runtime_prebuild_dependencies =
    Image.mk_external
      ~image_path:
        "${build_deps_image_name}:runtime-prebuild-dependencies--${build_deps_image_version}"

  let nix = Image.mk_external ~image_path:"nixos/nix:2.22.1"

  (* Match GitLab executors version and directly use the Docker socket
     The Docker daemon is already configured, experimental features are enabled
     The following environment variables are already set:
     - [BUILDKIT_PROGRESS]
     - [DOCKER_DRIVER]
     - [DOCKER_VERSION]
     For more info, see {{:https://docs.gitlab.com/ee/ci/docker/using_docker_build.html#use-docker-socket-binding}} here.

     This image is defined in {{:https://gitlab.com/tezos/docker-images/ci-docker}tezos/docker-images/ci-docker}. *)
  let docker =
    Image.mk_external
      ~image_path:"${GCP_REGISTRY}/tezos/docker-images/ci-docker:v1.12.0"

  (* The Alpine version should be kept up to date with the version
     used for the [build_deps_image_name] images and specified in the
     variable [alpine_version] in [scripts/version.sh]. This is
     checked by the jobs [start] and [sanity_ci]. *)
  let alpine = Image.mk_external ~image_path:("alpine:" ^ alpine_version)

  let debian_bookworm = Image.mk_external ~image_path:"debian:bookworm"

  let debian_bullseye = Image.mk_external ~image_path:"debian:bullseye"

  let ubuntu_focal =
    Image.mk_external ~image_path:"public.ecr.aws/lts/ubuntu:20.04_stable"

  let ubuntu_jammy =
    Image.mk_external ~image_path:"public.ecr.aws/lts/ubuntu:22.04_stable"

  let fedora_37 = Image.mk_external ~image_path:"fedora:37"

  let fedora_39 = Image.mk_external ~image_path:"fedora:39"

  let opam_ubuntu_jammy =
    Image.mk_external ~image_path:"ocaml/opam:ubuntu-22.04"

  let opam_ubuntu_mantic =
    Image.mk_external ~image_path:"ocaml/opam:ubuntu-23.10"

  let opam_debian_bullseye =
    Image.mk_external ~image_path:"ocaml/opam:debian-11"

  let ci_release =
    Image.mk_external
      ~image_path:"${GCP_REGISTRY}/tezos/docker-images/ci-release:v1.6.0"

  let hadolint = Image.mk_external ~image_path:"hadolint/hadolint:2.9.3-debian"

  (* We specify the semgrep image by hash to avoid flakiness. Indeed, if we took the
     latest release, then an update in the parser or analyser could result in new
     errors being found even if the code doesn't change. This would place the
     burden for fixing the code on the wrong dev (the devs who happen to open an
     MR coinciding with the semgrep update rather than the dev who wrote the
     infringing code in the first place).
     Update the hash in scripts/semgrep/README.md too when updating it here
     Last update: 2022-01-03 *)
  let semgrep_agent =
    Image.mk_external ~image_path:"returntocorp/semgrep-agent:sha-c6cd7cf"
end

(** {2 Helpers} *)

let before_script ?(take_ownership = false) ?(source_version = false)
    ?(eval_opam = false) ?(init_python_venv = false) ?(install_js_deps = false)
    before_script =
  let toggle t x = if t then [x] else [] in
  (* FIXME: https://gitlab.com/tezos/tezos/-/issues/2865 *)
  toggle take_ownership "./scripts/ci/take_ownership.sh"
  @ toggle source_version ". ./scripts/version.sh"
    (* TODO: this must run in the before_script of all jobs that use the opam environment.
       how to enforce? *)
  @ toggle eval_opam "eval $(opam env)"
  (* Load the environment poetry previously created in the docker image.
     Give access to the Python dependencies/executables *)
  @ toggle init_python_venv ". $HOME/.venv/bin/activate"
  @ toggle install_js_deps ". ./scripts/install_build_deps.js.sh"
  @ before_script

(** A [script:] that executes [script] and propagates its exit code.

    This might seem like a noop but is in fact necessary to please his
    majesty GitLab.

    For more info, see:
     - https://gitlab.com/tezos/tezos/-/merge_requests/9923#note_1538894754;
     - https://gitlab.com/tezos/tezos/-/merge_requests/12141; and
     - https://gitlab.com/groups/gitlab-org/-/epics/6074

   TODO: replace this with [FF_USE_NEW_BASH_EVAL_STRATEGY=true], see
   {{:https://docs.gitlab.com/runner/configuration/feature-flags.html}GitLab
   Runner feature flags}. *)
let script_propagate_exit_code script = [script ^ " || exit $?"]

let opt_var name f = function Some value -> [(name, f value)] | None -> []

(** Add variable for bisect_ppx instrumentation.

    This template should be extended by jobs that build OCaml targets
    that should be instrumented for coverage output. This set of job
    includes build jobs (like [oc.build_x86_64_*]). It also includes
    OCaml unit test jobs like [oc.unit:*-x86_64] as they build the test
    runners before their execution. *)
let enable_coverage_instrumentation : tezos_job -> tezos_job =
  Tezos_ci.append_variables
    [("COVERAGE_OPTIONS", "--instrument-with bisect_ppx")]

(** Add variable specifying coverage trace storage.

    This function should be applied to jobs that either produce (like
    test jobs) or consume (like the [unified_coverage] job) coverage
    traces. In addition to specifying the location of traces, setting
    this variable also _enables_ coverage trace output for
    instrumented binaries. *)
let enable_coverage_location : tezos_job -> tezos_job =
  Tezos_ci.append_variables
    [("BISECT_FILE", "$CI_PROJECT_DIR/_coverage_output/")]

let enable_coverage_report job : tezos_job =
  job
  |> Tezos_ci.add_artifacts
       ~expose_as:"Coverage report"
       ~reports:
         (reports
            ~coverage_report:
              {
                coverage_format = Cobertura;
                path = "_coverage_report/cobertura.xml";
              }
            ())
       ~expire_in:(Duration (Days 15))
       ~when_:Always
       ["_coverage_report/"; "$BISECT_FILE"]
  |> Tezos_ci.append_variables [("SLACK_COVERAGE_CHANNEL", "C02PHBE7W73")]

(** Add variable enabling sccache.

    This function should be applied to jobs that build rust files and
    which has a configured sccache Gitlab CI cache. *)
let enable_sccache ?error_log ?idle_timeout ?log
    ?(dir = "$CI_PROJECT_DIR/_sccache") : tezos_job -> tezos_job =
  Tezos_ci.append_variables
    ([("SCCACHE_DIR", dir); ("RUSTC_WRAPPER", "sccache")]
    @ opt_var "SCCACHE_ERROR_LOG" Fun.id error_log
    @ opt_var "SCCACHE_IDLE_TIMEOUT" Fun.id idle_timeout
    @ opt_var "SCCACHE_LOG" Fun.id log)

(** Add common variables used by jobs compiling kernels *)
let enable_kernels =
  Tezos_ci.append_variables
    [
      ("CC", "clang");
      ("CARGO_HOME", "$CI_PROJECT_DIR/cargo");
      ("NATIVE_TARGET", "x86_64-unknown-linux-musl");
    ]

(** {2 Changesets} *)

(** Modifying these files will unconditionally execute all conditional jobs. *)
let changeset_base = Changeset.make [".gitlab/**/*"; ".gitlab-ci.yml"]

let changeset_images = Changeset.make ["images/**/*"]

(** Only if octez source code has changed *)
let changeset_octez =
  Changeset.(
    changeset_base
    @ make
        [
          "src/**/*";
          "etherlink/**/*";
          "tezt/**/*";
          "michelson_test_scripts/**/*";
          "tzt_reference_test_suite/**/*";
          "irmin/**/*";
          "brassaia/**/*";
        ])

(** Only if octez source code has changed, if the images has changed or
    if kernels.mk changed. *)
let changeset_octez_or_kernels =
  Changeset.(
    changeset_base @ changeset_octez @ changeset_images
    @ make ["scripts/ci/**/*"; "kernels.mk"; "etherlink.mk"])

(** Only if documentation has changed *)
let changeset_octez_docs =
  Changeset.(
    changeset_base
    @ make
        [
          "scripts/**/*/";
          "script-inputs/**/*/";
          "src/**/*";
          "tezt/**/*";
          "vendors/**/*";
          "dune";
          "dune-project";
          "dune-workspace";
          "docs/**/*";
        ])

let changeset_octez_docker_changes_or_master =
  Changeset.(
    changeset_base
    @ make
        [
          "scripts/**/*";
          "script-inputs/**/*";
          "src/**/*";
          "tezt/**/*";
          "vendors/**/*";
          "dune";
          "dune-project";
          "dune-workspace";
          "opam";
          "Makefile";
          "kernels.mk";
          "build.Dockerfile";
          "Dockerfile";
        ])

let changeset_hadolint_docker_files =
  Changeset.make ["build.Dockerfile"; "Dockerfile"]

(** The set of [changes:] that select opam jobs.

    Note: unlike all other changesets, this one does not include {!changeset_base}.
    This is to avoid running these costly jobs too often. *)
let changeset_opam_jobs =
  Changeset.(
    make
      [
        "**/dune";
        "**/dune.inc";
        "**/*.dune.inc";
        "**/dune-project";
        "**/dune-workspace";
        "**/*.opam";
        ".gitlab/ci/jobs/packaging/opam:prepare.yml";
        ".gitlab/ci/jobs/packaging/opam_package.yml";
        "manifest/manifest.ml";
        "manifest/main.ml";
        "scripts/opam-prepare-repo.sh";
        "scripts/version.sh";
      ])

let changeset_kaitai_e2e_files =
  Changeset.(
    changeset_base @ changeset_images
    @ make
        [
          (* Regenerate the client-libs-dependencies image when the CI
             scripts change. *)
          "scripts/ci/**/*";
          "src/**/*";
          "client-libs/*kaitai*/**/*";
        ])

(** Set of OCaml files for type checking ([dune build @check]). *)
let changeset_ocaml_check_files =
  Changeset.(
    changeset_base
    @ make ["src/**/*"; "tezt/**/*"; "devtools/**/*"; "**/*.ml"; "**/*.mli"])

let changeset_lift_limits_patch =
  Changeset.(
    changeset_base
    @ make
        [
          "src/bin_tps_evaluation/lift_limits.patch";
          "src/proto_alpha/lib_protocol/main.ml";
        ])

(* The linting job runs over the set of [source_directories]
   defined in [scripts/lint.sh] that must be included here: *)
let changeset_lint_files =
  Changeset.(
    changeset_base
    @ make
        [
          "src/**/*";
          "tezt/**/*";
          "devtools/**/*";
          "scripts/**/*";
          "docs/**/*";
          "contrib/**/*";
          "client-libs/**/*";
          "etherlink/**/*";
        ])

(** Set of Python files. *)
let changeset_python_files =
  Changeset.(changeset_base @ make ["poetry.lock"; "pyproject.toml"; "**/*.py"])

(** Set of OCaml files for formatting ([dune build @fmt]). *)
let changeset_ocaml_fmt_files =
  Changeset.(changeset_base @ make ["**/.ocamlformat"; "**/*.ml"; "**/*.mli"])

let changeset_semgrep_files =
  Changeset.(
    changeset_base
    @ make ["src/**/*"; "tezt/**/*"; "devtools/**/*"; "scripts/semgrep/**/*"])

(* We only need to run the [oc.script:snapshot_alpha_and_link] job if
   protocol Alpha or if the scripts changed. *)
let changeset_script_snapshot_alpha_and_link =
  Changeset.(
    changeset_base
    @ make
        [
          "src/proto_alpha/**/*";
          "scripts/snapshot_alpha_and_link.sh";
          "scripts/snapshot_alpha.sh";
          "scripts/user_activated_upgrade.sh";
        ])

let changeset_script_b58_prefix =
  Changeset.(
    changeset_base
    @ make
        [
          "scripts/b58_prefix/b58_prefix.py";
          "scripts/b58_prefix/test_b58_prefix.py";
        ])

let changeset_test_liquidity_baking_scripts =
  Changeset.(
    changeset_base
    @ make
        [
          "src/**/*";
          "scripts/ci/test_liquidity_baking_scripts.sh";
          "scripts/check-liquidity-baking-scripts.sh";
        ])

let changeset_test_kernels =
  Changeset.(
    changeset_base
    @ changeset_images (* Run if the [rust-toolchain] image is updated *)
    @ make ["kernels.mk"; "src/kernel_*/**/*"])

let changeset_test_etherlink_kernel =
  Changeset.(
    changeset_base
    @ changeset_images (* Run if the [rust-toolchain] image is updated *)
    @ make ["etherlink.mk"; "etherlink/**/*.rs"; "src/kernel_sdk/**/*"])

let changeset_test_etherlink_firehose =
  Changeset.(
    changeset_base @ changeset_images
    @ make
        [
          "etherlink/firehose/**/*";
          "etherlink/tezt/tests/evm_kernel_inputs/erc20tok.*";
        ])

let changeset_test_riscv_kernels =
  Changeset.(
    changeset_base
    @ changeset_images (* Run if the [rust-toolchain] image is updated *)
    @ make ["src/kernel_sdk/**/*"; "src/riscv/**/*"])

let changeset_test_evm_compatibility =
  Changeset.(
    changeset_base
    @ changeset_images (* Run if the [rust-toolchain] image is updated *)
    @ make
        [
          "etherlink.mk";
          "etherlink/kernel_evm/evm_execution/**/*";
          "etherlink/kernel_evm/evm_evaluation/**/*";
        ])

(** {2 Job makers} *)

(** Helper to create jobs that uses the Docker daemon.

    It sets the appropriate image. Furthermore, unless
    [skip_docker_initialization] is [true], it:
    - activates the Docker daemon as a service;
    - sets up authentification with Docker registries
    in the job's [before_script] section.

    If [ci_docker_hub] is set to [true], then the job will
    authenticate with Docker Hub provided the environment variable
    [CI_DOCKER_AUTH] contains the appropriate credentials. *)
let job_docker_authenticated ?(skip_docker_initialization = false)
    ?ci_docker_hub ?artifacts ?(variables = []) ?rules ?dependencies
    ?image_dependencies ?arch ?tag ?allow_failure ?parallel ~__POS__ ~stage
    ~name script : tezos_job =
  let docker_version = "24.0.6" in
  job
    ?rules
    ?dependencies
    ?image_dependencies
    ?artifacts
    ?arch
    ?tag
    ?allow_failure
    ?parallel
    ~__POS__
    ~image:Images_external.docker
    ~variables:
      ([("DOCKER_VERSION", docker_version)]
      @ opt_var "CI_DOCKER_HUB" Bool.to_string ci_docker_hub
      @ variables)
    ~before_script:
      (if not skip_docker_initialization then
       ["./scripts/ci/docker_initialize.sh"]
      else [])
    ~services:[{name = "docker:${DOCKER_VERSION}-dind"}]
    ~stage
    ~name
    script

(** A set of internally and externally built images.

    Use this module to register images built in the CI of
    [tezos/tezos] that are also used in the same pipelines.See
    {!Images_external} for external images.

    To make the distinction between internal and external images
    transparent to job definitions, this module also includes
    {!Images_external}. *)
module Images = struct
  (* Include external images here for convenience. *)
  include Images_external

  let client_libs_dependencies =
    let image_builder =
      job_docker_authenticated
        ~__POS__
        ~stage:Stages.build
        ~name:"oc.docker:client-libs-dependencies"
          (* These image are not built for external use. *)
        ~ci_docker_hub:false
          (* Handle docker initialization, if necessary, in [./scripts/ci/docker_client_libs_dependencies_build.sh]. *)
        ~skip_docker_initialization:true
        ["./scripts/ci/docker_client_libs_dependencies_build.sh"]
        ~artifacts:
          (artifacts
             ~reports:
               (reports ~dotenv:"client_libs_dependencies_image_tag.env" ())
             [])
    in
    let image_path =
      "${client_libs_dependencies_image_name}:${client_libs_dependencies_image_tag}"
    in
    Image.mk_internal ~image_builder ~image_path

  (** The rust toolchain image *)
  let rust_toolchain =
    (* The job that builds the rust_toolchain image.
       This job is automatically included in any pipeline that uses this image. *)
    let image_builder =
      job_docker_authenticated
        ~__POS__
        ~skip_docker_initialization:true
        ~stage:Stages.images
        ~name:"oc.docker:rust-toolchain"
        ~ci_docker_hub:false
        ~artifacts:
          (artifacts
             ~reports:(reports ~dotenv:"rust_toolchain_image_tag.env" ())
             [])
        ["./scripts/ci/docker_rust_toolchain_build.sh"]
    in
    let image_path =
      "${rust_toolchain_image_name}:${rust_toolchain_image_tag}"
    in
    Image.mk_internal ~image_builder ~image_path
end

(* This version of the job builds both released and experimental executables.
   It is used in the following pipelines:
   - Before merging: check whether static executables still compile,
     i.e. that we do pass the -static flag and that when we do it does compile
   - Master branch: executables (including experimental ones) are used in some test networks
   Variants:
   - an arm64 variant exist, but is only used in the master branch pipeline
     (no need to test that we pass the -static flag twice)
   - released variants exist, that are used in release tag pipelines
     (they do not build experimental executables) *)
let job_build_static_binaries ~__POS__ ~arch ?(release = false) ?rules
    ?dependencies () : tezos_job =
  let arch_string = arch_to_string arch in
  let name = "oc.build:static-" ^ arch_string ^ "-linux-binaries" in
  let artifacts =
    (* Extend the lifespan to prevent failure for external tools using artifacts. *)
    let expire_in = if release then Some (Duration (Days 90)) else None in
    artifacts ?expire_in ["octez-binaries/$ARCH/*"]
  in
  let executable_files =
    "script-inputs/released-executables"
    ^ if not release then " script-inputs/experimental-executables" else ""
  in
  job
    ?rules
    ?dependencies
    ~__POS__
    ~stage:Stages.build
    ~arch
    ~name
    ~image:Images.runtime_build_dependencies
    ~before_script:(before_script ~take_ownership:true ~eval_opam:true [])
    ~variables:[("ARCH", arch_string); ("EXECUTABLE_FILES", executable_files)]
    ~artifacts
    ["./scripts/ci/build_static_binaries.sh"]

(** Type of Docker build jobs.

    The semantics of the type is summed up in this table:

    |                       | Release    | Experimental | Test   | Test_manual |
    |-----------------------+------------+--------------+--------+-------------|
    | Image registry        | Docker hub | Docker hub   | GitLab | GitLab      |
    | Experimental binaries | no         | yes          | yes    | yes         |
    | EVM Kernels           | no         | On amd64     | no     | On amd64    |
    | Manual job            | no         | no           | no     | yes         |

    - [Release] Docker builds include only released executables whereas other
      types also includes experimental ones.
    - [Test_manual] and [Experimental] Docker builds include the EVM kernels in
      amd64 builds.
    - [Release] and [Experimental] Docker builds are pushed to Docker hub,
      whereas other types are pushed to the GitLab registry.
    - [Test_manual] Docker builds are started manually, put in the stage
      [manual] and their failure is allowed. The other types are in the build
      stage, run [on_success] and are not allowed to fail. *)
type docker_build_type = Experimental | Release | Test | Test_manual

(** Creates a Docker build job of the given [arch] and [docker_build_type]. *)
let job_docker_build ?rules ?dependencies ~__POS__ ~arch docker_build_type :
    tezos_job =
  let arch_string = arch_to_string_alt arch in
  let ci_docker_hub =
    match docker_build_type with
    | Release | Experimental -> true
    | Test | Test_manual -> false
  in
  (* Whether to include evm artifacts.
     Including these artifacts requires the rust-toolchain image. *)
  let with_evm_artifacts =
    match (arch, docker_build_type) with
    | Amd64, (Test_manual | Experimental) -> true
    | _ -> false
  in
  let image_dependencies =
    if with_evm_artifacts then [Images.rust_toolchain] else []
  in
  let variables =
    [
      ( "DOCKER_BUILD_TARGET",
        if with_evm_artifacts then "with-evm-artifacts"
        else "without-evm-artifacts" );
      ("IMAGE_ARCH_PREFIX", arch_string ^ "_");
      ( "EXECUTABLE_FILES",
        match docker_build_type with
        | Release -> "script-inputs/released-executables"
        | Test | Test_manual | Experimental ->
            "script-inputs/released-executables \
             script-inputs/experimental-executables" );
    ]
  in
  let stage =
    match docker_build_type with
    | Test_manual -> Stages.manual
    | _ -> Stages.build
  in
  let name = "oc.docker:" ^ arch_string in
  job_docker_authenticated
    ?rules
    ?dependencies
    ~image_dependencies
    ~ci_docker_hub
    ~__POS__
    ~stage
    ~arch
    ~name
    ~variables
    ["./scripts/ci/docker_release.sh"]

let job_docker_merge_manifests ~__POS__ ~ci_docker_hub ~job_docker_amd64
    ~job_docker_arm64 : tezos_job =
  job_docker_authenticated
    ~__POS__
    ~stage:Stages.prepare_release
    ~name:"docker:merge_manifests"
      (* This job merges the images produced in the jobs
         [docker:{amd64,arm64}] into a single multi-architecture image, and
         so must be run after these jobs. *)
    ~dependencies:(Dependent [Job job_docker_amd64; Job job_docker_arm64])
    ~ci_docker_hub
    ["./scripts/ci/docker_merge_manifests.sh"]

type bin_package_target = Dpkg | Rpm

let bin_package_image = Image.mk_external ~image_path:"$DISTRIBUTION"

let job_build_bin_package ?dependencies ?rules ~__POS__ ~name
    ?(stage = Stages.build) ~arch ~target () : tezos_job =
  let arch_string = arch_to_string_alt arch in
  let target_string = match target with Dpkg -> "dpkg" | Rpm -> "rpm" in
  let image = bin_package_image in
  let parallel =
    let distributions =
      match target with
      | Dpkg -> ["debian:bookworm"; "ubuntu:focal"; "ubuntu:jammy"]
      | Rpm -> ["fedora:39"; "rockylinux:9.3"]
    in
    Matrix [[("DISTRIBUTION", distributions)]]
  in
  let artifacts =
    artifacts
      ~expire_in:(Duration (Days 1))
      ~when_:On_success
      ~name:"${TARGET}-$ARCH-$CI_COMMIT_REF_SLUG"
      ["packages/"]
  in
  let before_script =
    before_script
      ~source_version:true
      (match target with
      | Dpkg -> [".gitlab/ci/jobs/build/bin_packages_deb_dependencies.sh"]
      | Rpm -> [".gitlab/ci/jobs/build/bin_packages_rpm_dependencies.sh"])
  in
  job
    ?rules
    ?dependencies
    ~__POS__
    ~name
    ~arch
    ~image
    ~stage
    ~variables:
      [
        ("TARGET", target_string);
        ("OCTEZ_PKGMAINTAINER", "nomadic-labs");
        ("BLST_PORTABLE", "yes");
        ("ARCH", arch_string);
      ]
    ~artifacts
    ~parallel
    ~before_script
    [
      "wget https://sh.rustup.rs/rustup-init.sh";
      "chmod +x rustup-init.sh";
      "./rustup-init.sh --profile minimal --default-toolchain  \
       $recommended_rust_version -y";
      ". $HOME/.cargo/env";
      "export OPAMYES=\"true\"";
      "opam init --bare --disable-sandboxing";
      "make build-deps";
      "eval $(opam env)";
      "make $TARGET";
      "DISTRO=$(echo \"$DISTRIBUTION\" | cut -d':' -f1)";
      "RELEASE=$(echo \"$DISTRIBUTION\" | cut -d':' -f2)";
      "mkdir -p packages/$DISTRO/$RELEASE";
      "mv octez-*.* packages/$DISTRO/$RELEASE/";
    ]

let job_build_dpkg_amd64 : unit -> tezos_job =
  job_build_bin_package
    ~__POS__
    ~name:"oc.build:dpkg:amd64"
    ~target:Dpkg
    ~arch:Amd64
    ~dependencies:(Dependent [])

let job_build_rpm_amd64 : unit -> tezos_job =
  job_build_bin_package
    ~__POS__
    ~name:"oc.build:rpm:amd64"
    ~target:Rpm
    ~arch:Amd64
    ~dependencies:(Dependent [])

let job_build_homebrew ?rules ~__POS__ ~name ?(stage = Stages.build)
    ?dependencies () : tezos_job =
  let image = Images.debian_bookworm in
  job
    ?rules
    ~__POS__
    ~name
    ~arch:Amd64
    ?dependencies
    ~image
    ~stage
    ~before_script:
      [
        "apt update && apt install -y curl git build-essential";
        "./scripts/packaging/homebrew_install.sh";
        "eval \"$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\"";
        "eval $(scripts/active_protocols.sh)";
        "sed \"s|%%VERSION%%|0.0.0-dev| ; \
         s|%%CI_MERGE_REQUEST_SOURCE_PROJECT_URL%%|$CI_MERGE_REQUEST_SOURCE_PROJECT_URL|; \
         s|%%CI_COMMIT_REF_NAME%%|$CI_COMMIT_REF_NAME|; \
         s|%%CI_PROJECT_NAMESPACE%%|$CI_PROJECT_NAMESPACE|; \
         s|%%PROTO_CURRENT%%|$PROTO_CURRENT|; s|%%PROTO_NEXT%%|$PROTO_NEXT|\" \
         scripts/packaging/Formula/octez.rb.template > \
         scripts/packaging/Formula/octez.rb";
      ]
    [
      (* These packages are needed on Linux. For macOS, Homebrew will
         make those available locally. *)
      "apt install -y autoconf cmake libev-dev libffi-dev libgmp-dev \
       libprotobuf-dev libsqlite3-dev protobuf-compiler libhidapi-dev \
       pkg-config zlib1g-dev";
      "brew install -v scripts/packaging/Formula/octez.rb";
    ]

let job_build_dynamic_binaries ?rules ~__POS__ ~arch ?(release = false)
    ?dependencies () =
  let arch_string = arch_to_string arch in
  let name =
    sf
      "oc.build_%s-%s"
      arch_string
      (if release then "released" else "exp-dev-extra")
  in
  let executable_files =
    if release then "script-inputs/released-executables"
    else "script-inputs/experimental-executables script-inputs/dev-executables"
  in
  let build_extra =
    match (release, arch) with
    | true, _ -> None
    | false, Amd64 ->
        Some
          [
            "src/bin_tps_evaluation/main_tps_evaluation.exe";
            "src/bin_octogram/octogram_main.exe";
            "tezt/tests/main.exe";
            "contrib/octez_injector_server/octez_injector_server.exe";
          ]
    | false, Arm64 ->
        Some
          [
            "src/bin_tps_evaluation/main_tps_evaluation.exe";
            "src/bin_octogram/octogram_main.exe tezt/tests/main.exe";
          ]
  in
  let variables =
    [("ARCH", arch_string); ("EXECUTABLE_FILES", executable_files)]
    @
    match build_extra with
    | Some build_extra -> [("BUILD_EXTRA", String.concat " " build_extra)]
    | None -> []
  in
  let artifacts =
    artifacts
      ~name:"build-$ARCH-$CI_COMMIT_REF_SLUG"
      ~when_:On_success
      ~expire_in:(Duration (Days 1))
      (* TODO: [paths] can be refined based on [release] *)
      [
        "octez-*";
        "src/proto_*/parameters/*.json";
        "_build/default/src/lib_protocol_compiler/bin/main_native.exe";
        "_build/default/tezt/tests/main.exe";
        "_build/default/contrib/octez_injector_server/octez_injector_server.exe";
      ]
  in
  let job =
    job
      ?rules
      ?dependencies
      ~__POS__
      ~stage:Stages.build
      ~arch
      ~name
      ~image:Images.runtime_build_dependencies
      ~before_script:
        (before_script
           ~take_ownership:true
           ~source_version:true
           ~eval_opam:true
           [])
      ~variables
      ~artifacts
      ["./scripts/ci/build_full_unreleased.sh"]
  in
  (* Disable coverage for arm64 *)
  if arch = Amd64 then enable_coverage_instrumentation job else job

(** {2 Shared jobs} *)

let job_build_arm64_release ?rules () : tezos_job =
  job_build_dynamic_binaries ?rules ~__POS__ ~arch:Arm64 ~release:true ()

let job_build_arm64_exp_dev_extra ?rules () : tezos_job =
  job_build_dynamic_binaries ?rules ~__POS__ ~arch:Arm64 ~release:false ()
