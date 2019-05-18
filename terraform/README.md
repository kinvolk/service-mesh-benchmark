### Setup

This directory contains Terraform code, which spawns a Kubernetes cluster in a
Packet datacenter to perform the benchmark on.

To get it up and running, please create a file `variables.auto.tfvars`
in the `terraform` sub-directory and define these variables:

```
dns_zone          = "cluster.example.com"
# You can get your IP by executing 'curl -4 icanhazip.com'
management_cidrs  = ["cird1/mask", "cidr2/mask", "<your ip address>/32"]
packet_auth_token = "<packet API token>"
packet_project_id = "<packet project id>"
```

Optionally, you may also set:
```
cluster_name="my-lokomotive-benchmarkcluster" 
facility="<packet dataceter>"
ssh_keys=["list of keys to grant ssh access to nodes"]
```

The above variables are defined in the `cluster.tf` file.

After completing the initial set-up, please run `terraform init` in the
terraform sub-directory.
