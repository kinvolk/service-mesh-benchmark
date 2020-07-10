#!/bin/bash


[ $# -lt 3 ] && {
    echo
    echo "$0 - download (backup) a Grafana dashboard, write to STDOUT"
    echo "Usage: $0 <grafana-API-key> <dashboard-id> <hostname-and-port> [>dashboard-backup.json]"
    echo
    exit 1
}

apikey="$1"
dashboard_uid="$2"
host="$3"

echo "Downloading dashboard UID $dashboard_uid from $host" >&2


curl -H "Authorization: Bearer $apikey" \
                http://$host/api/dashboards/uid/$dashboard_uid \
        | sed -e 's/"31E2WrGGk"/null/' -e 's/,"url":"[^"]\+",/,/'
