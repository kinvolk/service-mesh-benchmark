#!/bin/bash

pushgw_base=http://pushgateway.monitoring:9091/metrics/job/wrk2_bench_test
CONNECTIONS="$((32*3))"
DURATION="120"

app="$1"
case "$app" in
    emojivoto) 
        PUSHGW=$pushgw_base/instance/emojivoto
        RPS=25000
        app_instance_count=$(kubectl get namespaces | grep emojivoto | wc -l)
        ;;
    bookinfo)
        PUSHGW=$pushgw_base/instance/bookinfo
        RPS=3000
        app_instance_count=$(kubectl get namespaces | grep bookinfo | wc -l)
        ;;
    *)
        echo "Unsupported app '$1'."
        exit
        ;;
esac

echo "App: $app"
[ -n "$2" ] && RPS="$2"
echo "RPS: $RPS"

[ -n "$3" ] && DURATION="$3"
echo "Duration: ${DURATION}s"

[ -n "$4" ] && CONNECTIONS="$4"
echo "Connections/Threads: ${CONNECTIONS}"

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

echo "Done."
