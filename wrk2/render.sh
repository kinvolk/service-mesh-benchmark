#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

export IMAGE=quay.io/kinvolk/wrk2:latest
export DURATION=5m
export RATE=1500
export INSTANCES=8
export THREADS=8

usage() {
	cat <<HELP_USAGE
Usage: $0 [OPTION...]

 This script will render wrk2.yaml.tmpl with provided parameters, combine it with multi-server.lua and print to stdout.

 Optional arguments:
  -i, --image     wrk2 Docker image name.
  -d, --duration  Duration of benchmark.
  -r, --rate      Requests per second for each instance.
  -I, --instances Number of instances.
  -t, --threads   Number of parallel threads/connections to use.
                  Each thread will use a single connection.
  -h  --help      Prints this message.
HELP_USAGE
}

while [[ $# -gt 0 ]]; do
key="$1"

case $key in
	-h|--help)
		usage
		exit 0
	;;
  -i|--image)
    export IMAGE="$2"
    shift # past argument
    shift # past value
  ;;
  -d|--duration)
    export DURATION="$2"
    shift # past argument
    shift # past value
  ;;
  -r|--rate)
    export RATE="$2"
    shift # past argument
    shift # past value
  ;;
  -I|--instances)
    export INSTANCES="$2"
    shift # past argument
    shift # past value
  ;;
  -t|--threads)
    export THREADS="$2"
    shift # past argument
    shift # past value
  ;;
  *)
    echo "Unknown argument $1"
    usage
    exit 1
  ;;
esac
done

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})

envsubst < $SCRIPT_DIR/wrk2.yaml.tmpl
sed 's/^/    /g' $SCRIPT_DIR/multi-server.lua
