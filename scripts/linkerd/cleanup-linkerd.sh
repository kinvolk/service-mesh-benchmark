#!/bin/bash

set -euo pipefail

script_dir=$(dirname ${BASH_SOURCE[0]})
source "$script_dir/../common.sh"

asset_dir="${script_dir}/../../assets"
KUBECONFIG=$(print_kubeconfig_path "$asset_dir")
[ ! -f "$KUBECONFIG" ] && {
    echo "No working cluster config found, aborting."
    exit 1; }
export KUBECONFIG

echo "###################################################"
echo "  Deleting linkerd from cluster."
echo
kubectl delete -f linkerd.yaml  --wait=true --grace-period=0 || true # ignore failure
kubectl delete namespaces/linkerd   --wait=true || true # ignore failure
wait_namespace_terminated linkerd
