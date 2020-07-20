#!/usr/bin/env python3

# pip install prometheus-http-client (for pulling metrics)
# export PROMETHEUS_URL='http://url:port' (default: http://localhost:9090)
#
# pip install prometheus-client (for publishing metrics to push gateway)
#


import json
from collections import OrderedDict

from prometheus_http_client import Prometheus
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

p = Prometheus()

def metrics_iter(p, query):
    m = p.query(metric=query)
    j = json.loads(m)
    return iter(j.get("data",{}).get("result"))
# --

def get_completed_runs(p):
    ret=[]

    for i in metrics_iter(p, 'wrk2_benchmark_progress{status="done"}'):
       ret.append(i["metric"]["run"])

    return ret
# --

def get_latency_histogram(run,detailed=False):
    ret=OrderedDict()

    if detailed:
        detailed="detailed_"
    else:
        detailed=""

    for i in metrics_iter(p,
                    'wrk2_benchmark_latency_%sms{run="%s"}' %(detailed,run,)):
       ret[float(i["metric"]["p"])] = float(i["value"][1])

    return ret
# --

hist = {}
det_hist = {}

# put latency values of all runs into a dict indexed by latencies' percentile
for run in get_completed_runs(p):
    x = get_latency_histogram(run)
    for perc,lat in x.items():
        if hist.get(perc):
            hist[perc][run]=lat
        else:
            hist[perc] = OrderedDict({run:lat})

    x = get_latency_histogram(run,"detailed")
    for perc,lat in x.items():
        if det_hist.get(perc):
            det_hist[perc][run]=lat
        else:
            det_hist[perc] = {run:lat}


# Now calculate "incremental" latency values that stack in a bar chart
r = CollectorRegistry()
gdiff = Gauge('wrk2_benchmark_summary_latency_ms_diff',
          'latency summary (all runs)',
            labelnames=["p","source_run"],
            registry=r)
g = Gauge('wrk2_benchmark_summary_latency_ms',
          'latency summary (all runs)',
            labelnames=["p","source_run"],
            registry=r)
for perc in hist.keys():
    hist[perc] = {k: v for k, v in 
                        sorted(hist[perc].items(), key=lambda item: item[1])}

    prev=0
    for run, lat in hist[perc].items():
        gdiff.labels(p=perc, source_run=run).set(lat - prev)
        g.labels(p=perc, source_run=run).set(lat)
        prev = lat

push_to_gateway('localhost:9091', job='bare-metal',
        grouping_key={"instance":"emojivoto",}, registry=r)
