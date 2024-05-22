#!/bin/sh

set -e

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
src_dir="$(dirname "$script_dir")"
cd "$src_dir"

source=script-inputs/slim-mode-dune
target=src/dune

help() {
  cat << EOF
Usage: $0 <check|on|off>"

Slim mode causes Octez to be built without old protocols.
It reduces build times by about 30%.

Old protocols are protocols 001 to N-1 where N is the current protocol of Mainnet.
Non-Mainnet protocols such as demo protocols, genesis and Alpha are kept.

Slim mode is intended for Octez developers.

$0 check

  Check if slim mode is active.
  If it is, print a message.
  Also check if slim mode is configured as expected.
  This is meant to be run by 'make'.

$0 on

  Enable slim mode.
  If slim mode is already enabled, update the list of disabled protocols.

$0 off

  Disable slim mode.
EOF
}

check() {
  if [ -f "$target" ]; then
    cat << EOF
Slim mode is ENABLED: old protocols will not be built by 'make'.
EOF

    if ! diff -q "$source" "$target" > /dev/null; then
      cat << EOF
WARNING: Slim mode is OUT OF DATE. Re-enable it to update the list of protocols.
EOF
    fi

    cat << EOF
For more information about slim mode, run:

    scripts/slim-mode.sh

EOF
  fi
}

on() {
  cp "$source" "$target"
  cat << EOF
Slim mode is now ACTIVE and the list of old protocols to disable has been updated.
EOF
}

off() {
  rm -f "$target"
  cat << EOF
Slim mode is now DISABLED.
EOF
}

case "$1" in
check | on | off)
  $1
  ;;
*)
  help
  ;;
esac
