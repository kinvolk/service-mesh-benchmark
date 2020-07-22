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

log "Cluster name: ${CLUSTER_NAME}"
# Creating file already so that once the cluster is installed the kubeconfig will file will be copied here
mkdir -p ~/.kube

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

cd /clusters
mkdir -p "${CLUSTER_NAME}" && cd "${CLUSTER_NAME}"
cp /scripts/packet.lokocfg .
cp /scripts/lokocfg.vars.envsubst .

public_key=$(cat ~/.ssh/id_rsa.pub)
export SSH_PUB_KEY=${public_key}
envsubst < lokocfg.vars.envsubst > lokocfg.vars
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa
ssh-add -L

lokoctl cluster apply -v --confirm --skip-components

n=0
until [ "$n" -ge 10 ]
do
  lokoctl component apply openebs-operator openebs-storage-class prometheus-operator metrics-server contour metallb cert-manager external-dns && break
  n=$((n+1))
  sleep 5
  log "retry #${n}"
  log "retrying 'lokoctl component apply' again..."
done

# Make an entry in the OC about this BC
# This uses service account credentials to talk to apiserver
kubectl -n monitoring patch prometheus prometheus-operator-prometheus --type merge --patch '{"spec":{"additionalScrapeConfigs":{"name":"scrape-config","key":"scrape.yaml"}}}'

if ! kubectl -n monitoring get secret scrape-config; then
  err "could not find secret 'scrape-config' in 'monitoring' namespace on orchestrating cluster"
  cat > /tmp/scrape.yaml <<EOF
- job_name: 'federate'
  scrape_interval: 15s

  honor_labels: true
  metrics_path: '/federate'

  params:
    'match[]':
    - '{job=~"node-exporter|istio-operator|istiod|emoji-svc|voting-svc|web-svc|details|productpage|ratings|reviews|linkerd-controller-api|linkerd-dst|linkerd-identity|linkerd-proxy-injector|linkerd-sp-validator|linkerd-tap|linkerd-web"}'
    - '{__name__=~"job:.*"}'

  static_configs:
  - targets:
EOF
  log "creating secret 'scrape-config' in 'monitoring' namespace on orchestrating cluster"
  kubectl -n monitoring create secret generic scrape-config --from-file=/tmp/scrape.yaml
fi

kubectl -n monitoring get secret scrape-config -ojsonpath='{.data.scrape\.yaml}' | base64 -d > /tmp/scrape.yaml
echo "    - 'prometheus.$CLUSTER_NAME.dev.lokomotive-k8s.net'" | tee -a /tmp/scrape.yaml
kubectl -n monitoring create secret generic scrape-config --from-file=/tmp/scrape.yaml --dry-run=client -o yaml | kubectl -n monitoring apply -f -
log "updated scrape config"
cat /tmp/scrape.yaml

# Wait for sometime because prometheus can take some time to start scraping
log "waiting for promtheus to apply above setting..."
sleep 300

cp ./assets/cluster-assets/auth/kubeconfig ~/.kube/config

# step: Now install all the stuff that is needed for benchmarking in various combinations
# step: Wait for the metrics to be scraped
