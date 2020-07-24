#!/usr/bin/env python3

import json
import time
import pprint
from sys import argv, exit
from os import putenv

from collections import OrderedDict

from prometheus_http_client import Prometheus
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway


def get_series(p, series):
    m = p.series([series])
    j = json.loads(m)
    return j.get("data",[])
# --

def get_results(p, query):
    # Returns results of a range query, so we pick up older runs' latencies
    now = time.time()
    last_week = now - (60 * 60 * 24 * 7)
    m = p.query_rang(metric=query,start=last_week, end=now, step=3600)
    j = json.loads(m)

    return j.get("data",{}).get("result")
# --

def get_completed_runs(p, mesh):
    s = get_series(p,
            'wrk2_benchmark_progress{exported_job="%s",status="done"}'%(mesh,))
    r = sorted([ i.get("run") for i in s ])
    return r
# --

def get_latency_histogram(run,detailed=False):
    # return RPS, histogram of a single run as dict 
    # <RPS>, {<percentile>: <latency in ms>, ...}
    # e.g.: 500, {0.5: 399, 0.75: 478, 0.9: 589, ...}

    ret=OrderedDict()

    if detailed:
        detailed="detailed_"
    else:
        detailed=""

    out=[]
    rps=0
    for res in get_results(
                p, 'wrk2_benchmark_latency_%sms{run="%s"}' %(detailed,run,)):
        perc = float(res["metric"]["p"])
        rps = float(res["metric"].get("rps",0))
        lat = float(res["values"][0][1])
        ret[perc] = lat
        out.append("%s: %s" % (perc,lat))

    if detailed == "":
        print("  Run %s @%sRPS (%s): %s" % 
                        (run, rps, "coarse" if detailed == "" else "detailed",
                                                             "\t".join(out)))
    return rps, ret
# --

def get_latency_histograms(p, mesh, detailed=False):
    # get all runs for a given service mesh.
    # Returns dict of dicts, indexed by RPS, then latency percentile:
    # { <RPS>: { <percentile>: [ <lat>, <lat>, <lat>, ...], <percentile>:...},
    #   <RPS>: { ...}, ...}

    histograms={}
    if False == detailed:
        print("Mesh %s" %(mesh,))
    for run in get_completed_runs(p, mesh):
        rps, h = get_latency_histogram(run, detailed)
        if not histograms.get(rps):
            histograms[rps]={}
        for perc,lat in h.items():
            if histograms[rps].get(perc, False):
                histograms[rps][perc][run]=lat
            else:
                histograms[rps][perc] = OrderedDict({run:lat})

    # sort runs' latencies for each percentile
    for rps in histograms.keys():
        for perc in histograms[rps].keys():
            histograms[rps][perc] = {k: v for k, v in 
                sorted(histograms[rps][perc].items(), key=lambda item: item[1])}

    return histograms
# --

def create_summary_gauge(p, mesh, r, detailed=False):
    histograms = get_latency_histograms(p, mesh, detailed)

    if detailed:
        detailed="detailed_"
    else:
        detailed=""

    g = Gauge('wrk2_benchmark_summary_latency_%sms' % (detailed,),
              '%s latency summary' % (mesh,),
                labelnames=["p","source_run", "requested_rps"], registry=r)

    percs_count=0; runs_count=0

    # create latency entries for all runs, per percentile
    for rps in histograms.keys():
        for perc, latencies in histograms[rps].items():
            percs_count = percs_count + 1
            runs_count=0
            for run, lat in latencies.items():
                runs_count = runs_count + 1
                g.labels(p=perc, source_run=run, requested_rps=rps).set(lat)

    return g, percs_count, runs_count
# --

#
# -- main --
#

if 3 != len(argv):
    print(
       'Command line error: Prometheus URL and push gateway are required.')
    print('Usage:')
    print('  %s <Prometheus server URL> <Prometheus push gateway host:port>'
            % (argv[0],))
    exit(1)

prometheus_url = argv[1]
pgw_url = argv[2]

putenv('PROMETHEUS_URL', prometheus_url)
p = Prometheus()

for mesh in ["bare-metal", "svcmesh-linkerd", "svcmesh-istio"]:

    r = CollectorRegistry()
    workaround = mesh
    g, percs, runs = create_summary_gauge(p, mesh, r)
    dg, dpercs, druns = create_summary_gauge(p, mesh, r, detailed=True)

    print("%s: %d runs with %d percentiles (coarse)" % (mesh, runs, percs))
    print("%s: %d runs with %d percentiles (detailed)" % (mesh, druns, dpercs))

    push_to_gateway(pgw_url, job=mesh,
            grouping_key={"instance":"emojivoto"}, registry=r)
