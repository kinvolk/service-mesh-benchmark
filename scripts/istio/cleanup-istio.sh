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
echo "  Deleting istio from cluster."
echo

[ -z "${GOPATH}" ] && export GOPATH="${HOME}/go"
LOCAL_REPO="${GOPATH}/src/istio.io/istio"
[ ! -d "${LOCAL_REPO}" ] && {
    echo "No local istio repo found, aborting."
    exit 1; }
pushd "${LOCAL_REPO}"
kubectl delete -f install/kubernetes/istio-demo.yaml  --wait=true --grace-period=0 || true
wait_namespace_terminated istio-system
popd
