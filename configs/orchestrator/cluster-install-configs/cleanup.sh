#!/bin/bash

set -euo pipefail

function log() {
  local message="${1:-""}"
  echo -e "\\033[1;37m${message}\\033[0m"
}

function err() {
  local message="${1:-""}"
  echo -e >&2 "\\033[1;31m${message}\\033[0m"
}

for d in $(ls /clusters)
do
  log "Into dir: /clusters/$d"
  cd /clusters/$d
  lokoctl component delete prometheus-operator --confirm
  log "Wait for the BC Prometheus related entries to be cleaned up..."
  sleep 90
  lokoctl component delete external-dns --confirm
  lokoctl cluster destroy --confirm -v
done
