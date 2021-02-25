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

function verify_binaries_download() {
  binaries='terraform helm kubectl lokoctl'
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
}

verify_binaries_download

log "Cluster name: ${CLUSTER_NAME}"

# Always store the cluster configuration in the /clusters directory so that even if this pods fails
# it can be cleaned up later using the debug jobs pod.
cd /clusters
mkdir -p "${CLUSTER_NAME}" && cd "${CLUSTER_NAME}"

# Configs are mounted in /scripts dir so copy from there.
cp /scripts/"${CLOUD}".lokocfg .
cp /scripts/"${CLOUD}".vars.envsubst .

public_key=$(cat ~/.ssh/id_rsa.pub)
export SSH_PUB_KEY=${public_key}
envsubst < "${CLOUD}".vars.envsubst > lokocfg.vars
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa
ssh-add -L

lokoctl cluster apply -v --confirm --skip-components

mkdir -p ~/.kube
cp ./assets/cluster-assets/auth/kubeconfig ~/.kube/config

n=0
until [ "$n" -ge 10 ]
do
  # Edit this to install the components you want.
  lokoctl component apply <component names> && break
  n=$((n+1))
  sleep 5
  log "retry #${n}"
  log "retrying 'lokoctl component apply' again..."
done

# Current repo `service-mesh-benchmark` is also downloaded in the `/binaries` repository.
# Add code to run benchmarks after this.
# ...
