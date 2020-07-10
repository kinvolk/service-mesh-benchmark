#!/bin/bash

[ $# -lt 3 ] && {
    echo
    echo "$0 - Upload a Grafana dashboard back-up (JOSON file) to Grafana" 
    echo "Usage: $0 <grafana-API-key> <dashboard-file> <hostname-and-port>"
    echo
    exit 1
}

apikey="$1"
dashboard="$2"
host="$3"

echo "Uploading dashboard file $dashboard"

out=$(mktemp)

cat  "$dashboard" \
         | jq '. * {overwrite: true, dashboard: {id: null}}' \
         | curl -X POST \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $apikey" \
                http://$host/api/dashboards/import -d @- | tee $out

echo -e "\nDashboard available at $host/$(cat "$out" | jq -r '.importedUrl')"

rm -f "$out"
