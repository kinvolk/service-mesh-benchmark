#!/bin/bash

N_SVC=49
DURATION=900
INIT_DELAY=200

script_location="$(dirname "${BASH_SOURCE[0]}")"

function grace() {
    grace=10
    [ -n "$2" ] && grace="$2"

    while true; do
        eval $1
        if [ $? -eq 0 ]; then
            sleep 1
            grace=10
            continue
        fi

        if [ $grace -gt 0 ]; then
            sleep 1
            echo "grace period: $grace"
            grace=$(($grace-1))
            continue
        fi

        break
    done
}
# --

function check_meshed() {
    local ns_prefix="$1"

    echo "Checking for unmeshed pods in '$ns_prefix'"
    kubectl get pods --all-namespaces \
            | grep "$ns_prefix" | grep -vE '[012]/2'

    [ $? -ne 0 ] && return 0

    return 1
}
# --

function install_emojivoto() {
    local mesh="$1"

    echo "Installing emojivoto."

    for num in $(seq 0 1 $N_SVC); do
        {
            ns=emojivoto-$num
            kubectl create namespace $ns
	        osm namespace add $ns
            osm metrics enable --namespace $ns

            [ "$mesh" == "istio" ] && \
                kubectl label namespace $ns istio-injection=enabled

	        helm install $ns --namespace $ns \
                             ${script_location}/../configs/emojivoto/
         } &
        sleep 0.5
    done

    wait

    grace "kubectl get pods --all-namespaces | grep emojivoto | grep -v Running" 10
}
# --

function restart_emojivoto_pods() {

    for num in $(seq 0 1 $N_SVC); do
        local ns="emojivoto-$num"
        echo "Restarting pods in $ns"
        {  local pods="$(kubectl get -n "$ns" pods | grep -vE '^NAME' | awk '{print $1}')"
            kubectl delete -n "$ns" pods $pods --wait; } &
    done

    wait

    grace "kubectl get pods --all-namespaces | grep emojivoto | grep -v Running" 10
}
# --

function delete_emojivoto() {
    echo "Deleting emojivoto."

    for i in $(seq 0 1 $N_SVC); do
        { helm uninstall emojivoto-$i --namespace emojivoto-$i;
          kubectl delete namespace emojivoto-$i --wait; } &
    done

    wait

    grace "kubectl get namespaces | grep emojivoto"
}
# --

function run() {
    echo "   Running '$@'"
    $@
}
# --

function install_benchmark() {
    local mesh="$1"
    local rps="$2"

    local duration=$DURATION
    local init_delay=$INIT_DELAY

    local app_count=$(kubectl get namespaces | grep emojivoto | wc -l)

    echo "Running $mesh benchmark"
    kubectl create ns benchmark
    osm namespace add benchmark --disable-sidecar-injection
    kubectl annotate namespace benchmark openservicemesh.io/sidecar-injection-
    [ "$mesh" == "istio" ] && \
        kubectl label namespace benchmark istio-injection=enabled

    if [ "$mesh" != "bare-metal" ] ; then
        helm install benchmark --namespace benchmark \
            --set wrk2.serviceMesh="$mesh" \
            --set wrk2.app.count="$app_count" \
            --set wrk2.RPS="$rps" \
            --set wrk2.duration=$duration \
            --set wrk2.connections=128 \
            --set wrk2.initDelay=$init_delay \
            ${script_location}/../configs/benchmark/
    else
        helm install benchmark --namespace benchmark \
            --set wrk2.app.count="$app_count" \
            --set wrk2.RPS="$rps" \
            --set wrk2.duration=$duration \
            --set wrk2.initDelay=$init_delay \
            --set wrk2.connections=128 \
            ${script_location}/../configs/benchmark/
    fi

    # echo "manually remove osm validation webhook. Wait for key input"
    # read

    for num in $(seq 0 1 $N_SVC); do
        {
            ns=emojivoto-$num
            echo "creating IB for $ns"

            kubectl apply -f - <<EOF
kind: IngressBackend
apiVersion: policy.openservicemesh.io/v1alpha1
metadata:
  name: $ns
  namespace: $ns
spec:
  backends:
  - name: web-svc
    port:
      number: 8080
      protocol: http
  - name: web-svc
    port:
      number: 80
      protocol: http
  sources:
  - kind: Service
    namespace: benchmark
    name: wrk2-prometheus
EOF
         }
        sleep 0.5

    done
}
# --

function run_bench() {
    local mesh="$1"
    local rps="$2"

    install_benchmark "$mesh" "$rps"
    grace "kubectl get pods -n benchmark | grep wrk2-prometheus | grep -v Running" 10

    echo "Benchmark started."

    while kubectl get jobs -n benchmark \
            | grep wrk2-prometheus \
            | grep -qv 1/1; do
        kubectl logs \
                --tail 1 -n benchmark  jobs/wrk2-prometheus -c wrk2-prometheus
        sleep 10
    done

    echo "Benchmark concluded. Updating summary metrics."
    helm install --create-namespace --namespace metrics-merger \
        metrics-merger ${script_location}/../configs/metrics-merger/
    sleep 5
    while kubectl get jobs -n metrics-merger \
            | grep wrk2-metrics-merger \
            | grep  -v "1/1"; do
        sleep 1
    done

    kubectl logs -n metrics-merger jobs/wrk2-metrics-merger
    kubectl logs -n benchmark -l app=wrk2-prometheus -c wrk2-prometheus --tail 150
    # echo "Wait for key enter"
    # read

    echo "Cleaning up."
    helm uninstall benchmark --namespace benchmark
    kubectl delete ns benchmark --wait
    helm uninstall --namespace metrics-merger metrics-merger
    kubectl delete ns metrics-merger --wait
}
# --


function istio_extra_cleanup() {
    # this is ugly but istio-system namespace gets stuck sometimes
    kubectl get -n istio-system \
            istiooperators.install.istio.io \
            istiocontrolplane \
            -o json \
        | sed 's/"istio-finalizer.install.istio.io"//' \
        | kubectl apply -f -

    lokoctl component delete experimental-istio-operator \
                                                --confirm --delete-namespace
    kubectl delete --now --timeout=10s $(kubectl get clusterroles -o name | grep istio)
    kubectl delete --now --timeout=10s $(kubectl get clusterrolebindings -o name | grep istio)
    kubectl delete --now --timeout=10s  $(kubectl get crd -o name | grep istio)
    kubectl delete --now --timeout=10s \
            $(kubectl get validatingwebhookconfigurations -o name | grep istio)
    kubectl delete --now --timeout=10s \
            $(kubectl get mutatingwebhookconfigurations -o name | grep istio)
}
# --

function delete_istio() {
    lokoctl component delete experimental-istio-operator --delete-namespace --confirm
    [ $? -ne 0 ] && {
        # this sometimes fails with a namespace error, works the 2nd time
        sleep 5
        lokoctl component delete experimental-istio-operator --delete-namespace --confirm; }

    grace "kubectl get namespaces | grep istio-operator" 1
    kubectl delete namespace istio-system  --now --timeout=30s
    for i in $(seq 20); do
        istio_extra_cleanup
        kubectl get namespaces | grep istio-system || break
        sleep 1
    done
}
# --

function run_benchmarks() {
    for rps in 1000 ; do
        for repeat in 1; do
            echo "########## Run #$repeat w/ $rps RPS w/ $N_SVC services"

            echo " +++ bare metal benchmark"
            osm install --set=OpenServiceMesh.injector.autoScale.enable=true \
                --set=OpenServiceMesh.osmController.autoScale.enable=true
            install_emojivoto bare-metal
            run_bench bare-metal $rps
            delete_emojivoto
            osm uninstall -f

            echo "wait for 30s to cool down"
            sleep 30
        done
    done
}
# --

if [ "$(basename $0)" = "run_benchmarks_osm.sh" ] ; then
    osm namespace add monitoring --disable-sidecar-injection
    kubectl annotate namespace monitoring openservicemesh.io/sidecar-injection-

    run_benchmarks $@
fi
