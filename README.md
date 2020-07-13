# Kinvolk service mesh benchmark suite

This is a work-in-progress of the v2.0 release of our benchmark automation suite.

Please refer to the [1.0 release](tree/release-1.0) for automation discussed in our [2019 blog post](https://kinvolk.io/blog/2019/05/kubernetes-service-mesh-benchmarking/).

## Content

This repository contains following subfolders:

* `configs` - [Lokomotive kubernetes](https://github.com/kinvolk/lokomotive/) configuration files and helper scripts, [helm](https://github.com/helm/helm/releases) charts for demo applications
* `dashboards` - Grafana dashboards


## Set up a cluster

We use [Packet](https://www.packet.com/) infrastructure to run the benchmark
on, AWS S3 for sharing cluster state, and AWS Route53 for the clusters' public
DNS entries. You'll need a Packet account and respective API token as well as
an AWS account and accompanying secret key before you can provision a cluster.

You'll also need a recent version of [Lokomotive](https://github.com/kinvolk/lokomotive/releases/) to provision a cluster.

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

### Deploy prometheus push gateway

The benchmark load generator will push intermediate run-time metrics as well
as final latency metrics to a prometheus push gateway.
A push gateway is currently not bundled with Lokomotive's prometheus
component. Deploy by issuing
```
$ kubectl apply -n monitoring -f configs/prometheus-pushgateway.yaml
```

### Deploy demo apps

Demo apps will be used to run the benchmarks against. We'll use [Linkerd's
emojivoto](https://github.com/BuoyantIO/emojivoto) and [Istio's bookinfo](https://istio.io/latest/docs/examples/bookinfo/) apps. 

We will deploy multiple instances of each app to emulate many applications in a
cluster. For the default set-up, which includes 4 application nodes, we
recommend deploying 30 "bookinfo" instances, and 40 "emojivoto" instances:

```shell
$ cd configs
configs $ for i in $(seq 30) ; do \
            helm install --create-namespace bookinfo-$i \
                         --namespace bookinfo-$i \
                /home/t-lo/code/kinvolk/service-mesh-benchmark/configs/bookinfo \
          done
...
configs $ for i in $(seq 40) ; do \
            helm install --create-namespace emojivoto-$i \
                         --namespace emojivoto-$i \
                /home/t-lo/code/kinvolk/service-mesh-benchmark/configs/emojivoto \
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

## Run a benchmark

Benchmarks use the prometheus metrics pusher container of our [wrk2
fork](https://github.com/kinvolk/wrk2). 

1. Make sure the Grafana port-forward is active and open the "wrk2 cockpit"
   Grafana dashboard uploaded above.
2. Use the `run_benchmarks.sh` wrapper script to deploy the benchmark container
   and to set it up for benchmarking one of the two demo apps deployed above.
   The script will auto-detect the number of instances and will use all
   instances' endpoints:
   ```
   $ configs/run_benchmark.sh emojivoto
   ```
   or
   ```
   $ configs/run_benchmark.sh bookinfo
   ```
