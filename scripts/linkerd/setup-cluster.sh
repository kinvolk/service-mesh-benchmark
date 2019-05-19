#!/bin/bash

#### Prerequisites check

set -euo pipefail

script_dir=$(dirname ${BASH_SOURCE[0]})
source "$script_dir/../common.sh"

asset_dir="${script_dir}/../../assets"
terraform_dir="${script_dir}/../../terraform"
KUBECONFIG=$(print_kubeconfig_path "$asset_dir")

linkerd=$(grok_cmd 1 "linkerd2-cli" $@)
[ -z $linkerd ] && { echo "Aborting."; exit 1; }

#### Provision new cluster if no usable kubeconfig found

[ ! -f "$KUBECONFIG" ] && {
    ask_create_cluster "$asset_dir" "$terraform_dir"
    KUBECONFIG=$(print_kubeconfig_path "$asset_dir")
}
export KUBECONFIG
[ -z "${KUBECONFIG}" ] && { echo "Aborting."; exit 1; }

####  Deploy metrics server
setup_metrics_server

####  Install linkerd

echo "  Installing '$linkerd' to cluster."

$linkerd check --pre || { echo "linkerd sanity pre-check failed."; exit 1; }

# generate installer yaml and patch PSPs so linkerd can install
$linkerd install > linkerd.yaml
patch -p 1 <${script_dir}/linkerd.yaml.patch || {
                                echo "Patching linkerd yaml failed."; exit 1; }
kubectl apply --request-timeout="0" -f linkerd.yaml || {
                                echo "Installing linkerd failed."; exit 1; }

echo -n "Waiting for linkerd to finish installation..."
wait_namespace_settled linkerd 1800 || {
                   echo "Linkerd did not finish install after 30min"; exit 1; }
$linkerd check || { echo "Linkerd self-check failed"; exit 1; }

echo "###################################################"
echo "  All done."
echo
echo " You might want to:"
echo "   export KUBECONFIG=$KUBECONFIG"
echo " and then"
echo "   $linkerd dashboard &"
echo " and then"
echo "   ${script_dir}/benchmark.sh"
