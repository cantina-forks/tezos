#!/bin/sh

set -eu

# Create the APT repository for debian packages and sign it using
# the private key available as ENV variable.

# uses :
# - scripts/packaging/Release.conf for release metadata
# - scripts/packaging/key.asc as the repository pub key

# expected env vars
# - ARCHITECTURES
# - GPG_PASSPHRASE
# - GPG_KEY_ID

if [ $# -lt 2 ]; then
  cat << EOF
Usage: $0 <DISTRIBUTION> <RELEASE..>

<DISTRIBUTION>: The linux distribution, eg. debian or ubuntu

<RELEASE>: The release of the Linux distribution, e.g. 'jammy', 'focal', 'bookworm'.
This argument can be repeated to build for multiple releases.

Set the ARCHITECTURES env variable of packages built for
multiple architectures are available. Eg 'amd64 arm64'
EOF
  exit 1
fi

# shellcheck source=./scripts/ci/octez-release.sh
. ./scripts/ci/octez-release.sh

ARCHITECTURES=${ARCHITECTURES:-"amd64"}

# The linux distribution for which we are creating the apt repository
# E.g. 'ubuntu' or 'debian'
DISTRIBUTION=${1}
shift
# The release of the linux distribution for which
# we are creating the apt repository
# E.g. 'jammy focal', 'bookworm'
RELEASES=$*

# make available the private key for signing the release file
echo "$GPG_PRIVATE_KEY" | base64 --decode | gpg --batch --import --

BUCKET="$GCP_LINUX_PACKAGES_BUCKET"

oldPWD=$PWD

# if it's a release tag, then it can be a RC release or a final release
if [ -n "${gitlab_release_no_v}" ]; then
  # It a release tag, this can be either a real or test release
  if [ -n "${gitlab_release_rc_version}" ]; then
    # Release candidate
    TARGETDIR="public/RC/$DISTRIBUTION"
  else
    # Release
    TARGETDIR="public/$DISTRIBUTION"
  fi
else
  # Not a release tag. This is strictly for testing
  if [ ! "$CI_COMMIT_REF_PROTECTED" = "true" ]; then
    if [ "$CI_COMMIT_REF_NAME" = "RC" ]; then
      echo "Cannot create a repository for a branch named 'RC'"
      exit 1
    else
      TARGETDIR="public/$CI_COMMIT_REF_NAME/$DISTRIBUTION"
    fi
  else
    if [ "$CI_COMMIT_REF_NAME" = "master" ]; then
      TARGETDIR="public/master/$DISTRIBUTION"
    else
      echo "Cannot create a repository for a protected branch that \
        is not associated with a release tag or it's master"
      exit 1
    fi
  fi
fi

mkdir -p "$TARGETDIR/dists"

for architecture in $ARCHITECTURES; do # amd64, arm64 ...
  for release in $RELEASES; do         # unstable, jammy, focal ...
    echo "Setting up APT repository for $DISTRIBUTION / $release / $architecture"

    # create the apt repository root directory and copy the public key
    cp scripts/packaging/package-signing-key.asc "$TARGETDIR/octez.asc"

    target="dists/${release}/main/binary-${architecture}"

    mkdir -p "$TARGETDIR/${target}/"

    for file in packages/"${DISTRIBUTION}/${release}"/*.deb; do
      cp "$file" "$TARGETDIR/${target}/"
      echo "Adding package $file to $TARGETDIR/${target}/"
    done

    cd "$TARGETDIR"
    echo "Create the Packages file"
    apt-ftparchive packages "dists/${release}" > "${target}/Packages"
    gzip -k -f "${target}/Packages"

    echo "Create the Release files using a static configuration file"
    apt-ftparchive \
      -o APT::FTPArchive::Release::Codename="$release" \
      -o APT::FTPArchive::Release::Architectures="noarch $architecture" \
      -c "$oldPWD/scripts/packaging/Release.conf" release \
      "dists/${release}/" > "dists/${release}/Release"

    # sign the release file using GPG. Since gpg is run in a script we need to set
    # some variables and extra options to make it work. The InRelease file contains
    # both the gpg signature and the content of the Release file.
    echo "Sign the release file"
    echo "$GPG_PASSPHRASE" |
      gpg --batch --passphrase-fd 0 --pinentry-mode loopback \
        -u "$GPG_KEY_ID" --clearsign \
        -o "dists/${release}/InRelease" "dists/${release}/Release"
  done
  # back to base
  cd "$oldPWD"
done

if [ "$CI_COMMIT_REF_PROTECTED" = "true" ]; then
  echo "### Logging into protected repo ..."
  echo "${GCP_PROTECTED_SERVICE_ACCOUNT}" | base64 -d > protected_sa.json
  gcloud auth activate-service-account --key-file=protected_sa.json
else
  echo "### Logging into standard repo ..."
  # Nothing to do
fi

GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)
export GOOGLE_OAUTH_ACCESS_TOKEN

echo "Push to $BUCKET"

gsutil -m cp -r public/* gs://"${BUCKET}"

echo "Check the content of the bucket gs://${BUCKET}"

gcloud storage ls -R gs://"${BUCKET}/*"
