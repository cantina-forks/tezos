# CI-in-OCaml

This directory contains an OCaml library for writing generators of
GitLab CI configuration files (i.e. `.gitlab-ci.yml`).

This directory is structured like this:

 - `lib_gitlab_ci`: contains a partial, slightly opiniated, AST of
   [GitLab CI/CD YAML syntax](https://docs.gitlab.com/ee/ci/yaml/).
 - `bin`: contains a set of helpers for creating the Octez-specific
   GitLab CI configuration files and an executable that generates part
   of the CI configuration using those helpers.

## Usage

To regenerate `.gitlab-ci.yml` (from the root of the repo):

    make -C ci all

To check that `.gitlab-ci.yml` is up-to-date (from the root of the repo):

    make -C ci check
