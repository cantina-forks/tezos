#!/bin/sh

OUTPUT="$(pwd)/bench"
JOBS=10
# usage and help
usage() {
  echo "Usage: $(basename "$0") [-h] [-o OUTPUT_DIRECTORY] [-j JOBS]  -- args" 1>&2
}
print_help() {

  # display help
  usage
  echo "Launches the evm-benchmark docker image. [args] are passed on to the benchmark script." 1>&2
  echo 1>&2
  echo "options:" 1>&2
  echo "-o      specify output directory (default ./$(basename "$OUTPUT"))" 1>&2
  echo "-j      number of jobs" 1>&2
  echo "-h      this help" 1>&2
}
# parse options and flags
while getopts "hj:o:" options; do
  case "${options}" in
  h)
    print_help
    exit 0
    ;;
  j)
    JOBS=${OPTARG}
    ;;
  o)
    OUTPUT=${OPTARG}
    ;;
  :) # If expected argument omitted:
    print_help
    exit 1
    ;;
  *) # If unknown (any other) option:
    print_help
    exit 1
    ;;
  esac
done
NB_LINES=$(jq "length" etherlink/kernel_evm/benchmarks/scripts/benchmarks_list.json)
seq 0 "$NB_LINES" | time parallel --eta -j"$JOBS" --results "$OUTPUT/"bench-{}-out "node ./etherlink/kernel_evm/benchmarks/scripts/run_benchmarks.js -o $OUTPUT --nth {}"
