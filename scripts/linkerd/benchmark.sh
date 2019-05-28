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

linkerd=$(grok_cmd 5 "linkerd2-cli-edge-19.5.3-linux" $@)
[ -z $linkerd ] && { echo "Aborting."; exit 1; }

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
echo "### Starting benchmark of $linkerd w/ $nr_apps apps"

install_emojivoto "$linkerd inject --manual" $nr_apps

$linkerd -n emojivoto check --proxy
clear

echo "Sleeping for $((5*nr_apps)) seconds to let injected apps settle some more."
sleep $((5*nr_apps))

run_benchmark "linkerd" $nr_apps "$linkerd inject --manual" "$duration" "$rate" "$threads"

echo "### Cleaning up..."
kubectl delete -f emojivoto.injected.yaml --wait=true --grace-period=1 --all=true || true
wait_namespace_terminated emojivoto "3600"

untaint_nodes "reserved-for-benchmark-load-generator"
