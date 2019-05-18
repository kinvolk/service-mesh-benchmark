#!/bin/bash

#### Prerequisites check

set -euo pipefail

STOCK_MODE="${STOCK_MODE:-0}"

script_dir=$(dirname ${BASH_SOURCE[0]})
source "$script_dir/../common.sh"

asset_dir="${script_dir}/../../assets"
terraform_dir="${script_dir}/../../terraform"
KUBECONFIG=$(print_kubeconfig_path "$asset_dir")

istioctl=$(grok_cmd 1 "istioctl" $@)
[ -z $istioctl ] && { echo "Aborting."; exit 1; }

#### Provision new cluster if no usable kubeconfig found

[ ! -f "$KUBECONFIG" ] && {
    ask_create_cluster "$asset_dir" "$terraform_dir"
    KUBECONFIG=$(print_kubeconfig_path "$asset_dir")
}
export KUBECONFIG
[ -z "${KUBECONFIG}" ] && { echo "Aborting."; exit 1; }

ISTIO_VERSION="1.1.6"

if [ "${STOCK_MODE}" -eq 0 ]; then
    ISTIO_PATCH="$(readlink -f ${script_dir}/istio-psp-tuned.patch)"
else
    ISTIO_PATCH="$(readlink -f ${script_dir}/istio-psp.patch)"
fi

if [ -z "${ISTIO_PATCH}" ]; then
    echo "istio-psp.patch not found. Aborting."
    exit 1
fi

# Deploy metrics server
setup_metrics_server

[ -z "${GOPATH}" ] && export GOPATH="${HOME}/go"

LOCAL_REPO="${GOPATH}/src/istio.io/istio"

if [ ! -d "${LOCAL_REPO}" ]; then
    echo "###################################################"
    echo "Cloning istio repo into ${LOCAL_REPO}..."
    git clone https://github.com/istio/istio ${LOCAL_REPO}
    pushd "${LOCAL_REPO}"
else
    pushd "${LOCAL_REPO}"
    git fetch origin
    git checkout master
fi

echo "###################################################"
echo "  Generating istio yaml files (stock mode: ${STOCK_MODE})"
echo

git checkout ${ISTIO_VERSION}
git am "${ISTIO_PATCH}"

# istio Makefile blindly assumes this path exists
mkdir -p "$(make where-is-out)"

make installgen HUB=docker.io/istio TAG=${ISTIO_VERSION}

echo "###################################################"
echo "  Installing istio "
echo

kubectl apply --request-timeout="0" -f install/kubernetes/istio-demo.yaml

popd

# loop until istio installation has concluded; 10min max
echo -n "Waiting for istio to finish installation..."
wait_namespace_settled istio-system 600 || {
    echo "Istio did not settle after 10min. Aborting."
    exit 1
}
echo "OK"

echo "###################################################"
echo "  All done. Ready to benchmark!"
echo
echo " You might want to:"
echo "   export KUBECONFIG=$KUBECONFIG"
echo " and then"
echo '   kubectl -n istio-system port-forward $(kubectl -n istio-system get pod -l app=grafana -o jsonpath='{.items[0].metadata.name}') 3000:3000 &'
echo " followed by"
echo "   xdg-open http://localhost:3000/dashboard/db/istio-mesh-dashboard"
echo " and then"
echo "   ${script_dir}/benchmark.sh"
