#!/bin/sh
set -eu

# GitLab Release command-line tool
# https://gitlab.com/gitlab-org/release-cli

# Enable release-cli verbose mode
export DEBUG='true'

prepare_etherlink_job_id=$(cat kernels_job_id)
kernels_artifact_url="$CI_SERVER_URL/$CI_PROJECT_NAMESPACE/$CI_PROJECT_NAME/-/jobs/$prepare_etherlink_job_id/artifacts/raw/kernels.tar.gz"

release-cli create \
  --name="Release ${CI_COMMIT_TAG}" \
  --tag-name="${CI_COMMIT_TAG}" \
  --assets-link="{\"name\":\"Kernels\",\"url\":\"${kernels_artifact_url}\"}"
