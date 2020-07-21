#!/bin/bash
#
#
# Usage:
# run_benchmark.sh <baremetal|linkerd|istio> <emojivoto|bookinfo> [<rps>] \
#    [<duration>] [<number of concurrent threads / connections>] \
#    [<run ID>]

pushgw_base=http://pushgateway.monitoring:9091/metrics
DURATION="600"

job="$1"
case "$job" in
    baremetal)
        pushgw_base="$pushgw_base/job/bare-metal"
        ;;
    linkerd)
        pushgw_base="$pushgw_base/job/svcmesh-linkerd"
        ;;
    istio)
        pushgw_base="$pushgw_base/job/svcmesh-istio"
        ;;
    *)
        echo "Unsupported job '$1'."
        echo "Supported jobs are 'baremetal', 'linkerd', and 'istio'."
        exit
        ;;
esac

echo "Benchmark job: $job"


app="$2"
case "$app" in
    emojivoto) 
        PUSHGW=$pushgw_base/instance/emojivoto
        RPS=150000
        app_instance_count=$(kubectl get namespaces | grep emojivoto | wc -l)
        ;;
    bookinfo)
        PUSHGW=$pushgw_base/instance/bookinfo
        RPS=3000
        app_instance_count=$(kubectl get namespaces | grep bookinfo | wc -l)
        ;;
    *)
        echo "Unsupported app '$1'."
        echo "Supported apps are 'emojivoto' and 'bookinfo'."
        exit
        ;;
esac

echo "App: $app"
[ -n "$3" ] && RPS="$3"

echo "RPS: $RPS"

[ -n "$4" ] && DURATION="$4"
echo "Duration: ${DURATION}s"

# a connection / thread can safely handle about 400 concurrent connections
#  but introduces jitter above that (machine dependent though)
CONNECTIONS="$(( $RPS / 400 ))"
[ $CONNECTIONS -lt 1 ] && CONNECTIONS=1

[ -n "$5" ] && CONNECTIONS="$5"
echo "Connections/Threads: ${CONNECTIONS}"

run="$(date --rfc-3339=seconds | sed -e 's/ /_/g' -e 's/+[0-9:]\+$//')"
[ -n "$6" ] && run="$6"
PUSHGW="$PUSHGW/run/$run"
echo "Run: $run"

# clean up stale jobs
kubectl delete jobs/wrk2-prometheus >/dev/null 2>&1

script_location="$(dirname "${BASH_SOURCE[0]}")"

ENDPOINTS=""
for count in $(seq $app_instance_count); do
    INSTANCE="$count"
    export INSTANCE
    if [ -n "$ENDPOINTS" ]; then
        ENDPOINTS="$(echo "$ENDPOINTS";
                     envsubst <"$script_location/endpoints-$app.txt.tmpl")" 
    else
        ENDPOINTS="$(envsubst <"$script_location/endpoints-$app.txt.tmpl")" 
    fi
done

export PUSHGW CONNECTIONS DURATION RPS ENDPOINTS
envsubst < "$script_location/wrk2-prometheus.yaml.tmpl" > wrk2-prometheus.yaml

echo "YAML written to 'wrk2-prometheus.yaml'. Now deploying."

kubectl apply -f wrk2-prometheus.yaml

echo "Benchmark started. Waiting for benchmark to conclude."

sleep 10
while kubectl get jobs \
        | grep wrk2-prometheus \
        | grep  -v "1/1"; do
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

echo "Metrics updated. Cleaning up."

kubectl delete job wrk2-prometheus
kubectl delete job wrk2-metrics-merger

echo "Done."
