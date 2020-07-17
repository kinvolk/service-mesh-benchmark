#!/usr/bin/env python3

# pip install prometheus-http-client
# export PROMETHEUS_URL='http://url:port' (default: http://localhost:9090)

import json
from prometheus_http_client import Prometheus

p = Prometheus()

def get_completed_runs(p):
    ret=[]
    metric=json.loads(
                     p.query(metric='wrk2_benchmark_progress{status="done"}'))
    for i in metric.get("data",{}).get("result"):
       ret.append(i["metric"]["run"])

    return ret
# --

def get_latency_histogram(run,detailed=False):
    ret={}
    d_s=""
    if detailed:
        d_s="detailed_"
    metric=json.loads(
            p.query(metric='wrk2_benchmark_latency_%sms{run="%s"}' %(d_s,run,)))
    for i in metric.get("data",{}).get("result"):
       ret[float(i["metric"]["p"])] = float(i["value"][1])

    return ret
# --


for run in get_completed_runs(p):
    print("%s:\n"%(run,))
 
    print("    histogram\n")
    x = get_latency_histogram(run)
    percs = sorted(x.items(), key=lambda item: item[1])
    for perc,lat in percs:
        print("    %f: %fms" % (perc, lat))
    
    print("    ----\n")

    print("    detailed histogram\n")
    x = get_latency_histogram(run,"detailed")
    percs = sorted(x.items(), key=lambda item: item[1])
    for perc,lat in percs:
        print("    %f: %fms" % (perc, lat))
    print("----")


