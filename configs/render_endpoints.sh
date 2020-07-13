#!/bin/bash

usage() {
    echo "Usage: $0 <endpoint-template> <instances-count>"
    echo "          <endpoint-template> is a file with http endpoints, one per"
    echo "             line, with \$INSTANCE placeholders,"
    echo "          <instance-count> is the number of instances to render"
    echo "             endpoints for."
    exit 1
}

[ ! -f "$1" -o $# -lt 2 ] && usage

for INSTANCE in $(seq $2); do
    export INSTANCE
    envsubst <$1
done
