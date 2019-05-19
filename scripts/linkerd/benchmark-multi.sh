#!/bin/bash

set -euo pipefail

echo "$@" | grep -iw 'help' && {
    echo
    echo "Usage: $0 [<number-of-apps>] [<duration>] [<rps>] [<linkerd>=latest] [<istioctl>=latest]"
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

linkerd=$(grok_cmd 4 "linkerd2-cli-edge-19.5.3-linux" $@)
[ -z $linkerd ] && { echo "Aborting."; exit 1; }

istioctl=$(grok_cmd 5 "istioctl" $@)
[ -z $istioctl ] && { echo "Aborting."; exit 1; }


###  Linkerd
echo "##### Running $linkerd benchmark"
${script_dir}/benchmark.sh $nr_apps $duration $rate $linkerd

echo "##### Removing linkerd and installing istio tuned"
${script_dir}/cleanup-linkerd.sh

### Istio tuned

STOCK_MODE=0 ${script_dir}/../istio/setup-cluster.sh $istioctl

echo
echo "##### Running $istioctl benchmark (tuned)"
${script_dir}/../istio/benchmark.sh $nr_apps $duration $rate $istioctl "tuned"

echo "##### Removing istio tuned and installing istio stock"
${script_dir}/../istio/cleanup-istio.sh

### Istio stock

STOCK_MODE=1 ${script_dir}/../istio/setup-cluster.sh $istioctl

echo
echo "##### Running $istioctl benchmark (stock)"
${script_dir}/../istio/benchmark.sh $nr_apps $duration $rate $istioctl "stock"

echo "##### Removing istio"
${script_dir}/../istio/cleanup-istio.sh

### bare

echo "##### installing bare emojivoto"

taint_random_worker_node "$nr_apps" "reserved-for-benchmark-load-generator"

install_emojivoto "cat" $nr_apps

echo "##### Running bare benchmark"
run_benchmark "bare" $nr_apps "cat" "$duration" "$rate"

echo "##### removing bare emojivoto"
kubectl delete -f emojivoto.injected.yaml --wait=true --grace-period=1 --all=true || true
wait_namespace_terminated emojivoto "3600"

untaint_nodes "reserved-for-benchmark-load-generator"

echo "##### Re-installing linkerd to restore original cluster state"
${script_dir}/setup-cluster.sh $linkerd
