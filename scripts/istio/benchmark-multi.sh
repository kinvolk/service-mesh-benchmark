#!/bin/bash

set -euo pipefail

echo "$@" | grep -iw 'help' && {
    echo
    echo "Usage: $0 [<number-of-apps>] [<duration>] [<rps>] [<istioctl>=latest] [<linkerd>=latest]"
    echo
    exit 0; }

script_dir=$(dirname ${BASH_SOURCE[0]})
source "$script_dir/../common.sh"
asset_dir="${script_dir}/../../assets"
KUBECONFIG=$(print_kubeconfig_path "$asset_dir")
[ ! -f "$KUBECONFIG" ] && {
    echo "No working cluster config found, aborting."
    exit 1; }
export KUBECONFIG

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

linkerd=$(grok_cmd 6 "linkerd2-cli-edge-19.5.3-linux" $@)
[ -z $linkerd ] && { echo "Aborting."; exit 1; }

###  Istio tuned
echo
echo "##### Running $istioctl benchmark (tuned)"
${script_dir}/benchmark.sh $nr_apps "$duration" "$rate" "$threads" $istioctl "tuned"

echo "##### Removing tuned istio and installing stock istio"
${script_dir}/cleanup-istio.sh

###  Istio stock
echo
echo "##### Running $istioctl benchmark (stock)"
STOCK_MODE=1 ${script_dir}/setup-cluster.sh $istioctl

echo
echo "##### Running $istioctl benchmark"
${script_dir}/benchmark.sh $nr_apps "$duration" "$rate" "$threads" $istioctl "stock"

echo "##### Removing istio and installing linkerd"
${script_dir}/cleanup-istio.sh

### Linkerd
${script_dir}/../linkerd/setup-cluster.sh $linkerd

echo "##### Running $linkerd benchmark"
${script_dir}/../linkerd/benchmark.sh $nr_apps "$duration" "$rate" "$threads" $linkerd

echo "##### Removing linkerd"
${script_dir}/../linkerd/cleanup-linkerd.sh

### bare

echo "##### installing bare emojivoto"

taint_random_worker_node "$nr_apps" "reserved-for-benchmark-load-generator"

install_emojivoto "cat" $nr_apps
wait_namespace_settled emojivoto

echo "##### Running bare benchmark"
run_benchmark "bare" $nr_apps "cat" "$duration" "$rate" "$threads"

echo "##### removing bare emojivoto"
kubectl delete -f emojivoto.injected.yaml --wait=true --grace-period=1 --all=true || true
wait_namespace_terminated emojivoto "3600"

untaint_nodes "reserved-for-benchmark-load-generator"

echo "##### Re-installing istio to restore original cluster state"
${script_dir}//setup-cluster.sh $istioctl
