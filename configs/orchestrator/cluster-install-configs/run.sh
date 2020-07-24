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
    - '{job=~"node-exporter|kube-state-metrics|istio-operator|istiod|emoji-svc|voting-svc|web-svc|details|productpage|ratings|reviews|linkerd-controller-api|linkerd-dst|linkerd-identity|linkerd-proxy-injector|linkerd-sp-validator|linkerd-tap|linkerd-web|pushgateway|kubelet"}'
    - 'node_namespace_pod_container:container_cpu_usage_seconds_total:sum_rate'
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
sleep 180

cp ./assets/cluster-assets/auth/kubeconfig ~/.kube/config
cp -r /binaries/service-mesh-benchmark .

# Number of workload application deployments to do.
workload_num=60

function install_emojivoto() {
  local mesh="${1}"

  cd /clusters/"${CLUSTER_NAME}"/service-mesh-benchmark/configs/emojivoto/

  local i
  for ((i = 0; i < workload_num; i++))
  do
    kubectl create namespace "emojivoto-${i}"

    [ "$mesh" == "istio" ] && \
        kubectl label namespace "emojivoto-${i}" istio-injection=enabled

    helm install --create-namespace "emojivoto-${i}" \
      --namespace "emojivoto-${i}" \
      /clusters/"${CLUSTER_NAME}"/service-mesh-benchmark/configs/emojivoto/ || true

    [ "$mesh" == "bare-metal" ] && continue

    # Run until injection of proxy happens
    while true
    do
      log "Checking if the proxy is injected."
      output=$(kubectl get pods -n "emojivoto-${i}" | grep -i running | awk '{print $2}' | grep 2) || true
      if [ -z "${output}" ]
      then
        kubectl delete pods --all -n "emojivoto-${i}"
        sleep 2
      else
        break
      fi
    done

    log "Pods in the emojivoto-${i} namespace."
    kubectl get pods -n "emojivoto-${i}"
  done
}

function cleanup_emojivoto() {
  local i
  for ((i = 0; i < workload_num; i++))
  do
    helm uninstall "emojivoto-${i}" --namespace "emojivoto-${i}" || true
    kubectl delete ns "emojivoto-${i}"
  done
}

# Deploy pushgateway in monitoring namespace
function install_pushgateway() {
  cd /clusters/"${CLUSTER_NAME}"/service-mesh-benchmark/configs/pushgateway
  helm install pushgateway --namespace monitoring . || true
}

function install_mesh() {
  local mesh="${1}"
  cd /clusters/"${CLUSTER_NAME}"

  if [ "${mesh}" = "bare-metal" ]; then
    return

  elif [ "${mesh}" = "linkerd" ]; then
    log "installing mesh: ${mesh}"
    lokoctl component apply experimental-linkerd

    # Let linkerd get ready
    log "Waiting for linkerd to be ready..."
    sleep 60

    log "Pods in the linkerd namespace."
    kubectl get pods -n linkerd

  else
    log "installing mesh: ${mesh}"
    lokoctl component apply experimental-istio-operator

    # Let isito get ready
    log "Waiting for istio to be ready..."
    sleep 60

    log "Pods in the istio-operator namespace."
    kubectl get pods -n istio-operator
    log "Pods in the istio-system namespace."
    kubectl get pods -n istio-system
  fi
}

function cleanup_mesh() {
  local mesh="${1}"

  if [ "${mesh}" = "bare-metal" ]; then
    return

  elif [ "${mesh}" = "linkerd" ]; then
    log "cleaning mesh: ${mesh}"
    lokoctl component delete experimental-linkerd --delete-namespace --confirm

  else
    log "cleaning mesh: ${mesh}"

    # Extra cleanup to do after istio because it does not do it automatically.
    kubectl get -n istio-system istiooperators.install.istio.io istiocontrolplane -o json | sed 's/"istio-finalizer.install.istio.io"//' | kubectl apply -f -
    lokoctl component delete experimental-istio-operator --confirm --delete-namespace
    kubectl delete $(kubectl get clusterroles -o name | grep istio) \
      $(kubectl get clusterrolebindings -o name | grep istio) \
      $(kubectl get crd -o name | grep istio) \
      $(kubectl get validatingwebhookconfigurations -o name | grep istio) \
      $(kubectl get mutatingwebhookconfigurations -o name | grep istio)
  fi
}

function wait_for_job() {
  local ns="${1}"
  local job="${2}"

  # Wait for the job to finish
  while true
  do
    complete=$(kubectl -n "${ns}" get job "${job}" -o jsonpath='{.status.completionTime}')
    #
    if [ -z "${complete}" ]; then
      log "waiting for job ${job} to finish in ${ns} namespace"
    else
      break
    fi
    sleep 10
  done
}

function run_benchmark() {
  local mesh="${1}"
  local rps="${2}"
  local ind="${3}"
  local name="benchmark-${mesh}-${rps}-${ind}"

  kubectl create ns "${name}"

  svcmesh="${mesh}"
  if [ "${svcmesh}" = "bare-metal" ]; then
    svcmesh=""
  elif [ "${svcmesh}" = "linkerd" ]; then
    kubectl annotate namespace "${name}" linkerd.io/inject=enabled
  else
    kubectl label namespace "${name}" istio-injection=enabled
  fi

  cd /clusters/"${CLUSTER_NAME}"/service-mesh-benchmark/configs/benchmark/
  helm install "${name}" --namespace "${name}" \
    . --set wrk2.serviceMesh="${svcmesh}" \
      --set wrk2.app.count="${workload_num}" \
      --set wrk2.RPS="${rps}" \
      --set wrk2.duration=600 \
      --set wrk2.connections=128

  log "Pods in the ${name} namespace."
  kubectl get pods -n "${name}"

  wait_for_job "${name}" wrk2-prometheus
}

function run_merge_job() {
  local mesh="${1}"
  local rps="${2}"
  local ind="${3}"
  local name="metrics-merger-${mesh}-${rps}-${ind}"

  cd /clusters/"${CLUSTER_NAME}"/service-mesh-benchmark/configs/metrics-merger/
  helm install "${name}" --create-namespace --namespace "${name}" .

  wait_for_job "${name}" wrk2-metrics-merger
}

install_pushgateway

for rps in 500 1000 1500 2500 3000 3500 4000 4500 5000 5500; do

  for ((i=0;i<5;i++))
  do

    for mesh in bare-metal linkerd istio
    do
      install_mesh "${mesh}"
      install_emojivoto "${mesh}"
      run_benchmark "${mesh}" "${rps}" "${i}"
      run_merge_job "${mesh}" "${rps}" "${i}"
      cleanup_emojivoto
      cleanup_mesh "${mesh}"
    done
  done
done
