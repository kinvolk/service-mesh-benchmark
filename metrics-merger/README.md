# Service mesh benchmark automation metrics merger

The `merger.py` tool and accompanying Docker build recipe implement results
merging of individual benchmark runs. `merger.py` will query individual run
results from Prometheus, merge the data to create a summary, then publish the
summary to a push gateway. The merger job should run after every benchmark, to
keep the [summary dashboard](../dashboards/grafana-wrk2-summary.json)
up to date.

`merger.py` will merge all data of completed runs (`{status="done"}`) of
(currently hard-coded) `bare-metal`, `svcmesh-linkerd`, and `svcmesh-istio`
jobs, The benchmark starter script `config/run_benchmark.sh` will use these
job names.

# Usage

## Build
```shell
$ docker build -t merger .
```

## Run
```shell
$ docker run -ti --net host merger <prometheus-url> <pushgw-host>
```
e.g.
```shell
$ docker run -ti --net host merger http://localhost:9090 localhost:9091
```

## Run in a cluster
Kinvolk maintains a [docker image at quay.io](https://quay.io/repository/kinvolk/svcmesh-bench-results-merger)
A convenience YAML file is supplied for manual deployment:
```shell
$ kubectl apply -f metrics-merger.yaml
```
