# Kinvolk service mesh benchmark suite

For an introduction to the purpose of this repository please see our [blog post](https://kinvolk.io/blog/2019/05/kubernetes-service-mesh-benchmarking/).

## Content

This repository contains following subfolders:

* `scripts` - Contains scripts to set up clusters and service meshes, and to run benchmarks
* `terraform` - Contains Terraform code required for setting up cluster. See [terraform/README.md](terraform/README.md) for more details.
* `wrk2` - Contains Dockerfile and kubernetes manifest templates for wrk2, which we use for generating load during benchmarks.

## Requirements

In order to run benchmark, following things needs to be set up:
* configure AWS credentials locally with `aws configure`
* make sure BGP is enabled in your packet project. Local BGP is sufficient.
* follow [terraform/README.md](terraform/README.md) for setting up Terraform requirements
* install `isitoctl` [binary](https://istio.io/docs/setup/kubernetes/download/)
* install `Terraform` [binary](https://learn.hashicorp.com/terraform/getting-started/install.html)
* install `terraform-provider-ct` [locally](https://github.com/poseidon/terraform-provider-ct/blob/master/README.md#install)
* install `linkerd` [binary](https://linkerd.io/2/getting-started/)
* have an up-to-date installation of `kubectl` for your respective environment.

## Set up a cluster and install a service mesh

You can now run either
* `scripts/linkerd/setup-cluster.sh`
or
* `scripts/istio/setup-cluster.sh`

The script will detect whether you already have a cluster working (by checking
with `kubectl`) and either install the service mesh right away, or use
terraform to provision a new cluster first, then install the respective service
mesh.  This level of automation lets you call setup-cluster.sh from other scripts.

Please note that you do not commit a cluster to a specific service mesh by
running the setup script in either directory. You may, for example, remove a
linkerd installation and switch to istio by running:
* `scripts/linkerd/cleanup-linkerd.sh`
* `scripts/istio/setup-cluster.sh`

## Run a benchmark

Before continuing, make sure the `KUBECONFIG` environment variable points to
the kubernetes configuration of the correct cluster.

You're now set up to start a benchmark. You may specify the number of apps in
the cluster, the benchmark run time, and the requests per second via the
command line.

The following example starts a linkerd benchmark running 5 minutes, with 10
apps and a constant request rate of 100RPS:
* `scripts/linkerd/benchmark.sh 10 5m 100`

If you want to run a full series of benchmarks for linkerd, istio stock, istio
tuned, and bare, simply issue:
* `scripts/linkerd/benchark-multi.sh 10 5m 100`

Please note that you must always use scripts from the directory of your
respective cluster service mesh. If your cluster currently has istio installed,
please only use scripts from `scripts/istio/`.
