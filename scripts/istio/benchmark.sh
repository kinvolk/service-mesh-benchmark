#!/bin/bash

set -euo pipefail

script_dir=$(dirname ${BASH_SOURCE[0]})
source "$script_dir/../common.sh"

nr_apps="10"
[ $# -ge 1 ] && nr_apps="$1"

duration="30m"
[ $# -ge 2 ] && duration="$2"

rate="800"
[ $# -ge 3 ] && rate="$3"

threads="8"
[ $# -ge 4 ] && threads="$4"

istioctl=$(grok_cmd 5 "istioctl" $@)
[ -z $istioctl ] && { echo "Aborting."; exit 1; }

istio_type="tuned"
[ $# -ge 6 ] && istio_type="$6"

asset_dir="${script_dir}/../../assets"
KUBECONFIG=$(print_kubeconfig_path "$asset_dir")
[ ! -f "$KUBECONFIG" ] && {
    echo "No working cluster config found, aborting. Did you run '$script_dir/setup-cluster.sh' ?"
    exit 1; }
export KUBECONFIG

# make sure we remove leftover taints from previous runs
untaint_nodes "reserved-for-benchmark-load-generator"

taint_random_worker_node "$nr_apps" "reserved-for-benchmark-load-generator"

echo
echo "### Starting benchmark of $istioctl w/ $nr_apps apps"

install_emojivoto "$istioctl kube-inject -f" $nr_apps

echo "Sleeping for $((5*nr_apps)) seconds to let injected apps settle some more."
sleep $((5*nr_apps))

run_benchmark "istio-${istio_type}" $nr_apps "$istioctl kube-inject -f" "$duration" "$rate" "$threads"

echo "### Cleaning up..."
kubectl delete -f emojivoto.injected.yaml --wait=true --grace-period=1 --all=true || true
wait_namespace_terminated emojivoto "3600"

untaint_nodes "reserved-for-benchmark-load-generator"
