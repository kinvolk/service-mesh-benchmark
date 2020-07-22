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
    for i in $(seq 0 1 59); do
        helm install --create-namespace emojivoto-$i \
                     --namespace emojivoto-$i \
                     ${script_location}/../configs/emojivoto/ &
    done

    wait

    grace "kubectl get pods --all-namespaces | grep emojivoto | grep -v Running"
}
# --

function delete_emojivoto() {
    for i in $(seq 0 1 59); do
        kubectl delete namespace emojivoto-$i --wait &
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
    install_emojivoto
    echo "Running $mesh benchmark"
    run ${script_location}/run_benchmark.sh $mesh emojivoto $rps
    echo "Deleting emojivoto"
    delete_emojivoto

}
# --

function run_benchmarks() {
    for rps in 50000 100000 150000 200000 250000; do
        for repeat in 1 2 3; do

            echo "########## Run #$repeat w/ $rps RPS"

            run_bench baremetal $rps

            echo "Installing linkerd"
            lokoctl component apply experimental-linkerd
            grace "kubectl get pods --all-namespaces | grep linkerd | grep -v Running"

            run_bench linkerd $rps

            echo "Removing linkerd"
            lokoctl component delete experimental-linkerd --delete-namespace --confirm
            kubectl delete namespace linkerd
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

