#!/bin/bash
#
# Common functions for istio and linkerd set-up scripts
#

function stderr() {
    echo $@ >&2
}
#---

function print_kubeconfig_path() {
    stderr "Checking available kubeconfig file..."
    local asset_dir="$1"

    # check for kubeconfig already in use
    [ -f "${KUBECONFIG:-}" ] && {
        for i in {1..6}; do stderr "Running 'KUBECONFIG=$KUBECONFIG kubectl cluster-info'... ($i/6)"; kubectl cluster-info >/dev/null 2>&1 && {
            stderr "Will use existing cluster with kubeconfig at '$KUBECONFIG'"
            echo "$(readlink -f $KUBECONFIG)"
            exit 0
        } || sleep 5; done
    }

    export KUBECONFIG="$(readlink -f ${asset_dir}/auth/kubeconfig)"
    [ -f "${KUBECONFIG:-}" ] && {
        for i in {1..6}; do stderr "Running 'KUBECONFIG=$KUBECONFIG kubectl cluster-info'... ($i/6)"; kubectl cluster-info >/dev/null 2>&1 && {
            stderr "Will use existing cluster with kubeconfig at '$KUBECONFIG'"
            echo "$(readlink -f $KUBECONFIG)"
            exit 0
        } || sleep 5; done
    }

    stderr "No existing cluster / kubeconfg found."
}
#---
function grok_cmd() {
    local pos="$1"; shift
    local cmd="$1"; shift
    local _c="${!pos:-}"
    [ -z $_c ] && {
        # Use highest version by default
        _c=$(compgen -c $cmd | sort -V -bt- -k4 | uniq | tail -n1) ; }
    local c="$(command -v $_c || true)"
    if $c >/dev/null 2>&1 && [ -n "$c" ] ; then
        echo "$c"
    else
        stderr "$cmd '${!pos:-}' not found."
        echo ""
    fi
}
#---

function ask_create_cluster() {
    local asset_dir="$1"
    local terraform_dir="$2"

    stderr "###################################################"
    stderr " No working cluster found."
    stderr " To get us to a working state, I would like to:"
    stderr ""
    stderr " 1. DELETE existing state in '$(readlink -f $asset_dir)' if present, then"
    stderr " 2. DESTROY existing Terraform resources based on '$(readlink -f $terraform_dir)'"
    stderr " 3. Create a new cluster based on '$(readlink -f $terraform_dir)'"
    stderr ""
    stderr " Press RETURN to continue, or CTRL+C to abort"

    read junk

    rm -rf "$asset_dir"
    pushd "${terraform_dir}"
    (terraform destroy || true) && terraform apply || {
        echo "Failed to set up test cluster."
        exit 1; }
    popd
}
#---

function taint_random_worker_node() {
    local nr_apps="$1"
    local taint="$2"

    local wnode_count=$(kubectl get nodes | grep worker | wc -l)

    [ $nr_apps -ge $wnode_count ] && {
        echo "Benchmarked apps >= workers ($nr_apps >= $wnode_count)"
        echo " Tainting a random node so the benchmark load generator runs"
        echo " separate from the benchmarked apps."
    }

    local rnd_node_nr=$(((RANDOM * wnode_count) / 32767 + 1))
    local rnd_node=$(kubectl get nodes | grep worker \
                | sed -n "${rnd_node_nr}p" | awk '{print $1}')

    kubectl taint nodes "$rnd_node" "$taint"=None:NoSchedule
}
#---

function untaint_nodes() {
    local taint="$1"

    tainted_nodes=$(kubectl describe nodes | grep -E '(Name:|Taints:)' \
                    | grep -B1 "$taint" | awk '{print $2}' \
                    | grep 'worker' || true)

    local n=""
    for n in $tainted_nodes; do
        kubectl taint nodes "$n" $taint:NoSchedule-
    done
}
#---

function wait_namespace_settled() {
    local namespace="$1"
    local timeout="${2:-600}"
    local precondition_state="${3:-}"

    local safety=5
    local up=false
    local st=$(date +%s)
    local ts=$st
    if [ -n "$precondition_state" ] ; then
        while [ $((st + timeout)) -ge $ts ]; do
            kubectl get pods --all-namespaces \
                | grep -E "^${namespace}" \
                | tail -n+2 \
                | awk '{print $4}' \
                | grep -q "$precondition_state" && break
            sleep 1
            ts=$(date +%s)
        done
    fi
    while [ $((st + timeout)) -ge $ts ]; do
        kubectl get pods --all-namespaces \
            | grep -E "^${namespace}" \
            | tail -n+2 \
            | awk '{print $4}' \
            | grep -vqE '(Running|Completed)' || {
                [ $safety -le 0 ] && { up=true; break; }
                ((safety--)); }
            ts=$(date +%s)
        sleep 1
    done

    $up
}
#---

function wait_namespace_terminated() {
    local namespace="$1"
    local timeout="${2:-600}"

    local up=false
    local st=$(date +%s)
    local ts=$st

    stderr "Waiting for namespace $namespace to terminate."

    while [ $((st + timeout)) -ge $ts ]; do
        kubectl get namespaces | grep -qE "^${namespace}" || {
            if kubectl create namespace "$namespace" >/dev/null 2>&1; then
                kubectl delete namespace "$namespace" --grace-period=1 --wait
                up=true
                break
            fi
        }
        sleep 1
    done

    $up
}
#---

function wait_benchmark_completion() {
    local job="$1"
    local namespace="$2"
    local container="$3"

    while true; do
        # print job(s) run time
        kubectl get jobs -n $namespace $job \
            | tail -n +2 \
            | awk '    {x = x " " $3}
                   END {printf "\r Job(s) active for: " x "     "}'
        sleep 10

        # jobs do not reliably Complete when injected
        kubectl logs -n $namespace jobs/$job -c $container \
            | grep -q 'Benchmark run concluded.' \
            && break

    done
}
#---

function cleanup_job_errors() {
    local jobprefix="$1"
    local namespace="$2"
    local logfile="$3"

    local error_pods=$(kubectl get pods -n "$namespace" \
                         | grep -E '(Error)' | awk '{print $1}')
    [ -z "$error_pods" ] && return 0

    echo "The following pods have a status of \"Error\":"
    echo "$error_pods"
    echo
    echo "Will clean up the error pods and put logs into $logfile"

    local p=""
    > $logfile
    for p in $error_pods; do
        echo "$p:" | tee -a $logfile
        kubectl logs -n "$namespace" $p | tee -a $logfile
        kubectl delete -n "$namespace" pods/$p
    done
}
#---

function install_emojivoto() {
    local inject="$1"
    local instances="$2"

    local i
    local script_dir=$(dirname ${BASH_SOURCE[0]})
    stderr -n " Creating deployment for $instances instances of the 'emojivoto' demo app "
    rm -f emojivoto.yaml
    for i in $(seq $instances); do
        cat ${script_dir}/emojivoto.yaml.tmpl \
            | sed "s/%INSTANCE%/$i/g" \
            >> emojivoto.yaml
    done
    stderr ' (emojivoto.yaml)'
    stderr "Injecting service mesh via '$inject emojivoto.yaml' and deploying:"
    $inject emojivoto.yaml > emojivoto.injected.yaml
    kubectl apply -f emojivoto.injected.yaml || {
                        echo "Injecting into demo app failed."; exit 1; }

    stderr "Waiting for injected apps to settle"
    wait_namespace_settled emojivoto 600 || {
                   echo "emojivoto did not finish updating after 10m"; exit 1; }

}
#---

function gen_bench_csv() {
    local log="$1"

    grep -A 999 'Latency Distribution' $log \
         | grep -B 999 '100.000%' \
         | sed -e 's/.*Latency Distribution.*/percentile milliseconds/' \
               -e 's/%//' -e 's/ms//' \
         | awk '{print $1 "," $2}'
    echo ""
    grep -A 999 'Detailed Percentile spectrum' $log \
        | grep -B 999 '1.000000' \
        | tail -n+2 \
        | awk '{print $1 "," $2 "," $3}'
}
#---

function safe_top() {
    while ! kubectl top $@ 1>/dev/null 2>&1; do
        sleep 0.1
    done

    kubectl top $@ --containers=true
}
#---

function metrics_puller() {
    local stop_file="$1"
    local mesh_namespace="$2"

    set +e

    while ! [ -f "$stop_file" ]; do
        date
        safe_top pods -n emojivoto
        echo "---"
        safe_top pods -n benchmark-load-generator
        [ -n "$mesh_namespace" ] && { echo "---"
                                      safe_top pods -n $mesh_namespace ;}
        echo "--------------------------------"
        sleep 30
    done

    set -e
}
#---

function run_benchmark() {
    local tag=$1
    local instances=$2
    local inject=$3
    local log_dir="${BENCHMARK_LOGFILE_DIR:-.}/"
    local duration=${4:-30m}
    local rate=${5:-800}

    local script_dir=$(dirname ${BASH_SOURCE[0]})
    local template="${script_dir}/../wrk2/wrk2.yaml.tmpl"
    local deployment="./benchmark-load-generator.yaml"
    local deployment_injected="./benchmark-load-generator.injected.yaml"

    ${script_dir}/../wrk2/render.sh --instances $instances \
                                    --duration $duration \
                                    --rate $rate > $deployment

    echo "Injecting service mesh via '$inject $deployment'"
    $inject $deployment > $deployment_injected

    local ts=$(date --rfc-3339=seconds | sed 's/\ /_/g')
    local dur=$(grep -A1 '\- -d' $deployment \
                | tail -n1 | sed 's/.* \([0-9]\+.*$\)/\1/')

    echo "##### Starting benchmark at $ts ($instances apps)"

    local asset_dir="${script_dir}/../../assets"
    KUBECONFIG=$(print_kubeconfig_path "$asset_dir")
    export KUBECONFIG

    local namespace=""
    case "$tag" in
        linkerd)     namespace="linkerd";;
        istio-stock) namespace="istio-system";;
        istio-tuned) namespace="istio-system";;
        default)     namespace="";;
    esac

    local log="${log_dir}bench-run-$tag-$ts.log"
    local err="${log_dir}bench-run-$tag-$ts.err"
    local csv="${log_dir}bench-run-$tag-$ts.csv"
    local top="${log_dir}bench-run-$tag-$ts.top"
    local stopfile="${log_dir}bench-run-$tag-$ts.stop"

    printf "Starting metrics puller in background"
    rm -f "$stopfile"
    metrics_puller "$stopfile" "$namespace" > "$top" &

    kubectl apply -f "$deployment_injected"
    wait_namespace_settled "benchmark-load-generator"
    echo " Benchmark is running (started $ts, runtime $dur)"
    wait_benchmark_completion "wrk2" "benchmark-load-generator" "wrk2"
    echo "Done."
    touch "$stopfile"

    echo "Collecting results and cleaning up benchmark job."
    cleanup_job_errors "wrk2" "benchmark-load-generator" "$err"

    local st=$(date +%s)
    local t=$st
    while [ $((st + 60)) -ge $t ]; do
        kubectl logs -n benchmark-load-generator job/wrk2 -c wrk2 | tee $log
        grep -q "Benchmark run concluded." $log  && break
    done

    [ -s $log ] || { echo "ERROR: no benchmark data (log empty)";
                     exit 1; }
    echo >> $log
    cat $top >> $log

    echo "Run $ts" > $csv
    echo "" >> $csv
    gen_bench_csv $log >> $csv

    echo
    echo "(results saved to $log and $csv)"
    echo
    kubectl delete -f "$deployment_injected"
    echo "Waiting for metrics puller to stop"
    wait
    rm -f "$stopfile"
}
#---

function setup_metrics_server() {
    local METRICS_LOCAL_REPO="metrics-server"

    if [ -d "${METRICS_LOCAL_REPO}" ]; then
        pushd "${METRICS_LOCAL_REPO}"
        git fetch origin
    else
        echo "###################################################"
        echo "Cloning metrics repo into ${METRICS_LOCAL_REPO}..."
        git clone https://github.com/kinvolk/metrics-server ${METRICS_LOCAL_REPO}
        pushd "${METRICS_LOCAL_REPO}"
    fi

    git checkout dongsu/deploy-insecure-tls
    kubectl apply -f ./deploy/1.8+/
    popd
}
#---
