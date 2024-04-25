#!/bin/sh

## Sourceable file with common variables for other scripts related to release

# shellcheck disable=SC2034
architectures='x86_64 arm64'

current_dir=$(cd "$(dirname "${0}")" && pwd)
scripts_dir=$(dirname "$current_dir")
src_dir=$(dirname "$scripts_dir")
script_inputs_dir="$src_dir/script-inputs"

binaries="$(cat "$script_inputs_dir/released-executables")"

# these variables are used in the script scripts/ci/create_gitlab_package.sh
debian_bookworm_packages="$(find packages/debian/bookworm/ -maxdepth 1 -name octez-\*.deb 2> /dev/null || printf '')"
ubuntu_focal_packages="$(find packages/ubuntu/focal/ -maxdepth 1 -name octez-\*.deb 2> /dev/null || printf '')"
ubuntu_jammy_packages="$(find packages/ubuntu/jammy/ -maxdepth 1 -name octez-\*.deb 2> /dev/null || printf '')"
fedora_packages="$(find packages/fedora/39/ -maxdepth 1 -name octez-\*.rpm 2> /dev/null || printf '')"
rockylinux_packages="$(find packages/rockylinux/9.3/ -maxdepth 1 -name octez-\*.rpm 2> /dev/null || printf '')"

octez_source_content="$script_inputs_dir/octez-source-content"

### Compute GitLab release names from git tags

# Git tags for octez releases are on the form `octez-vX.Y`, `octez-vX.Y-rcZ` or `octez-vX.Y-betaZ`.

# Strips the leading 'octez-v'
# X.Y, X.Y-rcZ or  X.Y-betaZ
gitlab_release_no_v=$(echo "${CI_COMMIT_TAG}" | sed -e 's/^octez-v//g')

# Replace '.' with '-'
# X-Y or X-Y-rcZ
# shellcheck disable=SC2034
gitlab_release_no_dot=$(echo "${gitlab_release_no_v}" | sed -e 's/\./-/g')

# X
gitlab_release_major_version=$(echo "${CI_COMMIT_TAG}" | sed -nE 's/^octez-v([0-9]+)\.([0-9]+)(-rc[0-9]+)?$/\1/p')
# Y
gitlab_release_minor_version=$(echo "${CI_COMMIT_TAG}" | sed -nE 's/^octez-v([0-9]+)\.([0-9]+)(-rc[0-9]+)?$/\2/p')
# Z
gitlab_release_rc_version=$(echo "${CI_COMMIT_TAG}" | sed -nE 's/^octez-v([0-9]+)\.([0-9]+)(-rc)?([0-9]+)?$/\4/p')

# Is this a release candidate?
if [ -n "${gitlab_release_rc_version}" ]; then
  # Yes, release name: X.Y~rcZ
  # shellcheck disable=SC2034
  gitlab_release_name="Octez Release Candidate ${gitlab_release_major_version}.${gitlab_release_minor_version}~rc${gitlab_release_rc_version}"
  opam_release_tag="${gitlab_release_major_version}.${gitlab_release_minor_version}~rc${gitlab_release_rc_version}"
else
  # No, release name: Octez Release X.Y
  # shellcheck disable=SC2034
  gitlab_release_name="Octez Release ${gitlab_release_major_version}.${gitlab_release_minor_version}"
  opam_release_tag="${gitlab_release_major_version}.${gitlab_release_minor_version}"
fi

### Compute GitLab generic package names

gitlab_octez_binaries_package_name="octez-binaries-${gitlab_release_no_v}"
gitlab_octez_debian_bookworm_package_name="octez-debian-bookworm-${gitlab_release_no_v}"
gitlab_octez_ubuntu_focal_package_name="octez-ubuntu-focal-${gitlab_release_no_v}"
gitlab_octez_ubuntu_jammy_package_name="octez-ubuntu-jammy-${gitlab_release_no_v}"
gitlab_octez_fedora_package_name="octez-fedora-${gitlab_release_no_v}"
gitlab_octez_rockylinux_package_name="octez-rockylinux-${gitlab_release_no_v}"
gitlab_octez_source_package_name="octez-source-${gitlab_release_no_v}"

# X.Y or X.Y-rcZ
gitlab_package_version="${gitlab_release_no_v}"
