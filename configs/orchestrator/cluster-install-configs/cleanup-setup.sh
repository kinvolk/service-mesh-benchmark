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

binaries='terraform helm kubectl terraform-provider-ct lokoctl'
for b in $binaries
do
  while ! ls "/binaries/${b}" >/dev/null 2>&1
  do
    log "Waiting for ${b} to be available..."
    sleep 1
  done
  log "Copying /binaries/${b} to /usr/local/bin/"
  /bin/cp "/binaries/${b}" /usr/local/bin/
done

mkdir -p ~/.terraform.d/plugins
cp /binaries/terraform-provider-ct ~/.terraform.d/plugins/terraform-provider-ct_"${CT_VER}"
log "Copied terraform-provider-ct plugin to plugins dir."

echo
log "Now exec into this pod and run"
log "bash /scripts/cleanup.sh"

sleep infinity
