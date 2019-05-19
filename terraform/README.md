### Setup

This directory contains Terraform code, which spawns a Kubernetes cluster in a
Packet datacenter to perform the benchmark on.

To configure your cluster, please copy the file `variables.auto.tfvars.template` 
to `variables.auto.tfvars`, then edit `variables.auto.tfvars` and set the
variables as discussed below.

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
controller_node_type = "t1.small"
worker_node_type = "t1.small"
worker_node_count = "2"   #  must be 2 or higher
```

F.y.i, The above variables are defined in the `cluster.tf` file.

After completing the initial configuration, please run `terraform init` in the
terraform sub-directory.
