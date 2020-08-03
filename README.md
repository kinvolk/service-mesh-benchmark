# Kinvolk service mesh benchmark suite

This is v2.0 release of our benchmark automation suite.

Please refer to the [1.0 release](tree/release-1.0) for automation discussed in our [2019 blog post](https://kinvolk.io/blog/2019/05/kubernetes-service-mesh-benchmarking/).

# Content

The suite includes:
- orchestrator [tooling](orchestrator) and [Helm charts](configs/orchestrator)
    for deploying benchmark clusters from an orchstrator cluster
    - metrics of all benchmark clusters will be scraped and made available in
      the orchestrator cluster
- a stand-alone benchmark cluster [configuration](configs/packet-cluster.lokocfg) 
    for use with [Lokomotive](https://github.com/kinvolk/lokomotive/releases/)
- helm charts for deploying [Emojivoto](configs/emojivoto)
    to provide application endpoints to run benchmarks against
- helm charts for deploying a [wrk2 benchmark job](configs/benchmark) as well
  as a job to create
    [summary metrics of multiple benchmark runs](configs/metrics-merger)
- Grafana [dashboards](dashboards/) to view benchmark metrics

## Run a benchmark

Prerequisites:
- cluster is set up
- push gateway is installed
- grafana dashboards are uploaded to Grafana
- applications are installed

1. Start the benchmark:
   ```shell
   $ helm install --create-namespace benchmark --namespace benchmark configs/benchmark
   ```
   This will start a 120s, 3000RPS benchmark against 10 emojivoto app
   instances, with 96 threads / simultaneous connections.
   See the helm chart [values](configs/benchmark/values.yaml) for all
   parameters, and use helm command line parameters for different values (eg.
   `--set wrk2.RPS="500"` to change target RPS).
2. Refer to the "wrk2 cockpit" grafana dashboard for live metrics
3. After the run concluded, run the "metrics-merger" job to update summary
   metrics:
   ```shell
   $ helm install --create-namespace --namespace metrics-merger \
                                   metrics-merger configs/metrics-merger/
   ```
   This will update the "wrk2 summary" dashboard.

## Run a benchmark suite

The benchmark suite script will install applications and service meshes, and
run several benchmarks in a loop.

Use the supplied `scripts/run_benchmarks.sh` to run a full benchmark suite:
5 runs of 10 minutes each for 500-5000 RPS, in 500 RPS increases, with 128 threads,
for "bare metal", linkerd, and istio service meshes, against 60 emojivoto
instances.

# Creating prerequisites
## Set up a cluster

We use [Packet](https://www.packet.com/) infrastructure to run the benchmark
on, AWS S3 for sharing cluster state, and AWS Route53 for the clusters' public
DNS entries. You'll need a Packet account and respective API token as well as
an AWS account and accompanying secret key before you can provision a cluster.

You'll also need a recent version of [Lokomotive](https://github.com/kinvolk/lokomotive/releases/).

1. Create `configs/lokocfg.vars` and fill in:
   ```
   packet_project_id = "[ID of the packet project to deploy to]"
   route53_zone = "[cluster's route53 zone]"
   state_s3_bucket = "[PRIVATE AWS S3 bucket to share cluster state in]"
   state_s3_key = "[key in S3 bucket, e.g. cluster name]"
   state_s3_region = "[AWS S3 region to use]"
   lock_dynamodb_table = "[DynamoDB table name to use as state lock, e.g. cluster name]"
   ```
2. Review the benchmark cluster config in `configs/packet-cluster.lokocfg`, and
   add your public SSH key(s) to the `ssh_pubkeys = [` array. 
3. Provision the cluster by running
   ```
   $ cd configs
   configs $ lokoctl cluster apply
   ```

After provisioning concluded, make sure to run
```
$ export KUBECONFIG=assets/cluster-assets/auth/kubeconfig
```
to get `kubectl` access to the cluster.

## Deploy prometheus push gateway

The benchmark load generator will push intermediate run-time metrics as well
as final latency metrics to a prometheus push gateway.
A push gateway is currently not bundled with Lokomotive's prometheus
component. Deploy by issuing
```
$ helm install pushgateway --namespace monitoring configs/pushgateway
```

## Deploy demo apps

Demo apps will be used to run the benchmarks against. We'll use [Linkerd's
emojivoto](https://github.com/BuoyantIO/emojivoto).

We will deploy multiple instances of each app to emulate many applications in a
cluster. For the default set-up, which includes 4 application nodes, we
recommend deploying 30 "bookinfo" instances, and 40 "emojivoto" instances:

```shell
$ cd configs
$ for i in $(seq 10) ; do \
      helm install --create-namespace emojivoto-$i \ --namespace emojivoto-$i \
                configs/emojivoto \
  done
```

### Upload Grafana dashboard

1. Get the Grafana Admin password from the cluster
   ```
   $ kubectl -n monitoring get secret prometheus-operator-grafana -o jsonpath='{.data.admin-password}' | base64 -d && echo
   ```
2. Forward the Grafana service port from the cluster
   ```
   $ kubectl -n monitoring port-forward svc/prometheus-operator-grafana 3000:80 &
   ```
3. Log in to [Grafana](http://localhost:3000/) and create an API key we'll use
   to upload the dashboard
4. Upload the dashboard:
   ```
   $ cd dashboard
   dashboard $ ./upload_dashboard.sh "[API KEY]" grafana-wrk2-cockpit.json localhost:3000
   ```

