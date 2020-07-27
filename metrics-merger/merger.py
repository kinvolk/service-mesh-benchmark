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

def run_time_info(p, run):
    info = {}
    for kind in ["start", "end", "duration"]:
        res = get_results(p,
                'wrk2_benchmark_run_runtime{kind="%s",run="%s"}' % (kind,run))
        try:
            info[kind] = int(res[0]["values"][0][1])
        except IndexError:
            print(" !!! Run %s lacks '%s' metric." % (run,kind))
            return None

    return info
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
    # Returns dict of latency percentiles:
    # { <percentile>: [ <lat>, <lat>, <lat>, ...], <percentile>:...},
    #   <percentile>: [...]}
    # and info (doct) for each run (rps, start end, duration)

    if False == detailed:
        print("Mesh %s" %(mesh,))

    histograms={}
    info = {}

    for run in get_completed_runs(p, mesh):
        rps, h = get_latency_histogram(run, detailed)
        i = run_time_info(p, run)
        if not i:
            continue
        info[run] = i
        info[run]["rps"] = rps
        for perc,lat in h.items():
            if histograms.get(perc, False):
                histograms[perc][run]=lat
            else:
                histograms[perc] = OrderedDict({run:lat})

    # sort runs' latencies for each percentile
    for perc in histograms.keys():
        histograms[perc] = {k: v for k, v in 
            sorted(histograms[perc].items(), key=lambda item: item[1])}

    return histograms, info
# --

def create_summary_gauge(p, mesh, r, detailed=False):
    histograms, info = get_latency_histograms(p, mesh, detailed)

    if detailed:
        detailed="detailed_"
    else:
        detailed=""

    g = Gauge('wrk2_benchmark_summary_latency_%sms' % (detailed,),
            '%s latency summary' % (mesh,),
            labelnames=[
                "p","source_run", "requested_rps", "start", "end", "duration"],
                registry=r)

    percs_count=0

    # create latency entries for all runs, per percentile
    for perc, latencies in histograms.items():
        percs_count = percs_count + 1
        for run, lat in latencies.items():
            g.labels(p=perc, source_run=run, requested_rps=info[run]["rps"],
                     start=info[run]["start"]*1000,
                     # dashboard link fix: set end to 1min after actual end
                     end = (info[run]["end"] + 60) *1000,
                     duration=info[run]["duration"]).set(lat)

    return g, percs_count, len(info)
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

    push_to_gateway(
          pgw_url, job=mesh, grouping_key={"instance":"emojivoto"}, registry=r)
