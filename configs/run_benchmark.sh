#!/bin/bash

pushgw_base=http://pushgateway.monitoring:9091/metrics/job/wrk2_bench_test
connections="$((32*3))"
duration="120"

app="$1"
case "$app" in
    emojivoto) 
        pushgw=$pushgw_base/instance/emojivoto
        rps=25000
        app_instance_count=$(kubectl get namespaces | grep emojivoto | wc -l)
        ;;
    bookinfo)
        pushgw=$pushgw_base/instance/bookinfo
        rps=3000
        app_instance_count=$(kubectl get namespaces | grep bookinfo | wc -l)
        ;;
    *)
        echo "Unsupported app '$1'."
        exit
        ;;
esac

echo "App: $app"
echo "RPS: $rps"

[ -n "$2" ] && duration="$2"
echo "Duration: ${duration}s"

[ -n "$3" ] && connections="$2"
echo "Connections/Threads: ${connections}"

script_location="$(dirname "${BASH_SOURCE[0]}")"

kubectl run wrk2-prometheus \
            --restart=Never \
            --image=quay.io/kinvolk/wrk2-prometheus \
            --overrides='{ "apiVersion": "v1", "spec": {"tolerations": [ {"key":"load-generator-node", "operator":"Exists", "effect": "NoSchedule" } ] } }' \
                -- \
            -p $pushgw \
            -c $connections \
            -d $duration \
            -r $rps \
            $($script_location/render_endpoints.sh \
                            $script_location/endpoints-$app.txt.tmpl \
                            $app_instance_count)
