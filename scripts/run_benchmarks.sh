#!/bin/bash

script_location="$(dirname "${BASH_SOURCE[0]}")"

function grace() {
    grace=10
    while true; do
        eval $@
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

function install_emojivoto() {
    local mesh="$1"
    for i in $(seq 0 1 59); do
        kubectl create namespace emojivoto-$i
        [ "$mesh" == "istio" ] && \
            kubectl label namespace emojivoto-$i istio-injection=enabled
        helm install emojivoto-$i --namespace emojivoto-$i \
                                 ${script_location}/../configs/emojivoto/ &
    done

    wait

    grace "kubectl get pods --all-namespaces | grep emojivoto | grep -v Running"
}
# --

function delete_emojivoto() {
    for i in $(seq 0 1 59); do
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

function run_bench() {
    local mesh="$1"
    local rps="$2"

    echo "Installing emojivoto"
    install_emojivoto "$mesh"

    local app_count=$(kubectl get namespaces | grep emojivoto | wc -l)

    echo "Running $mesh benchmark"
    kubectl create ns benchmark
    [ "$mesh" == "istio" ] && \
        kubectl label namespace benchmark istio-injection=enabled
    if [ "$mesh" != "baremetal" ] ; then
        helm install benchmark --namespace benchmark \
            --set wrk2.serviceMesh="$mesh" \
            --set wrk2.app.count="$app_count" \
            --set wrk2.RPS="$rps" \
            --set wrk2.duration=600 \
            --set wrk2.connections=128 \
            ${script_location}/../configs/benchmark/
    else
        helm install benchmark --namespace benchmark \
            --set wrk2.app.count="$app_count" \
            --set wrk2.RPS="$rps" \
            --set wrk2.duration=600 \
            --set wrk2.connections=128 \
            ${script_location}/../configs/benchmark/
    fi

    while kubectl get jobs -n benchmark \
            | grep wrk2-prometheus \
            | grep -qv 1/1; do
        kubectl logs --tail 1 -n wrk2-prometheus \
                                        jobs/wrk2-prometheus -c wrk2-prometheus
        sleep 10
    done

    echo "Benchmark concluded. Updating summary metrics."

    kubectl apply -f ${script_location}/../metrics-merger/metrics-merger.yaml
    sleep 10
    while kubectl get jobs \
            | grep wrk2-metrics-merger \
            | grep  -v "1/1"; do
        sleep 1
    done

    kubectl logs jobs/wrk2-metrics-merger

    echo "Cleaning up."
    helm uninstall benchmark --namespace benchmark
    kubectl delete ns benchmark --wait
    kubectl delete -f ${script_location}/../metrics-merger/metrics-merger.yaml

    echo "Deleting emojivoto"
    delete_emojivoto
}
# --

function run_benchmarks() {
    for rps in 500 1000 1500 2500 3000 3500 4000 4500 5000; do
        for repeat in 1 2 3; do

            echo "########## Run #$repeat w/ $rps RPS"

            run_bench baremetal $rps

            echo "Installing linkerd"
            lokoctl component apply experimental-linkerd
            [ $? -ne 0 ] && {
                # this sometimes fails with a namespace error, works the 2nd time
                sleep 5
                lokoctl component apply experimental-linkerd; }

            grace "kubectl get pods --all-namespaces | grep linkerd | grep -v Running"

            run_bench linkerd $rps

            echo "Removing linkerd"
            lokoctl component delete experimental-linkerd --delete-namespace --confirm
            kubectl delete namespace linkerd --now --timeout=30s
            grace "kubectl get namespaces | grep linkerd"


            echo "Installing istio"
            lokoctl component apply experimental-istio-operator
            grace "kubectl get pods --all-namespaces | grep istio-operator | grep -v Running"

            run_bench istio $rps

            echo "Removing istio"
            lokoctl component delete experimental-istio-operator --delete-namespace --confirm
            kubectl delete namespace istio-system  --now --timeout=30s
            for i in $(seq 20); do
                # this is ugly but istio-system namespace gets stuck sometimes
                kubectl get namespaces | grep istio-system || break
                kubectl get namespace istio-system -o json > istio-system.json
                sed 's/"kubernetes"//' istio-system.json \
                                                    > istio-system-finalise.json
                kubectl replace --raw "/api/v1/namespaces/istio-system/finalize" \
                    -f ./istio-system-finalise.json
                sleep 1
            done
            grace "kubectl get namespaces | grep istio-system"
        done
    done
}
# --

if [ "$(basename $0)" = "run_benchmarks.sh" ] ; then
    run_benchmarks $@
fi

