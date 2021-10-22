#!/bin/bash

# Use this script to set up a AKS cluster for running the benchmark.
# Change the variable values as your need.

# Prerequisite:
# * the local kubernetes config sets context to the benchmark cluster, which should be created before running the script.
# * Helm must be installed

# ---- variables
CLUSTER=kinvolk-test
RG=osm-maestro

set -aueox pipefail

if ! [ -x "$(command -v helm)" ]; then
  echo 'Error: helm is not installed.' >&2
  exit 1
fi


az aks get-credentials --name $CLUSTER -g $RG

az aks nodepool add --cluster-name $CLUSTER --resource-group $RG --name benchmark --labels role=benchmark --node-count 1 --node-vm-size standard_d16a_v4

az aks nodepool add --cluster-name $CLUSTER --resource-group $RG --name workload --labels role=workload --min-count 1 --max-count 500 --enable-cluster-autoscaler --node-vm-size Standard_DS2_v2

kubectl create namespace monitoring

# install prometheus-operator
git clone git@github.com:helm/charts.git && cd charts
helm install prom-graf prometheus-community/kube-prometheus-stack --set grafana.sidecar.dashboard.enabled=true --namespace monitoring
cd .. && rm -rf charts

# alternatively

# git clone git@github.com:prometheus-operator/kube-prometheus.git && cd kube-prometheus
# helm install prom-graf stable/prometheus-operator --set grafana.sidecar.dashboards.enabled=true --namespace monitoring
# cd .. && rm -rf kube-prometheus

# install pushgateway
helm install pushgateway --namespace monitoring configs/pushgateway
kubectl apply -f scripts/service-monitor.yaml

cat <<EOT >> configs/metrics-merger/values.yaml
prometheusServiceUrl: "http://prom-graf-kube-prometheus-prometheus.monitoring:9090"
pushgatewayURL: "pushgateway.monitoring:9091"
EOT

kubectl patch service prom-graf-grafana -n monitoring -p '{"spec":{"type":"LoadBalancer"}}'

echo "Done. Please follow the Upload Grafana dashboard section of README, upload wrk2-dash-osm.json instead to setup Kinvolk result dashboard."

