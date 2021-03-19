# PyTorch

This chart installs a Kubernetes Job that runs AI/ML workloads using [PyTorch framework](https://pytorch.org/). The workloads are taken from [this repository](https://github.com/pytorch/examples).

## Install

```
helm install --create-namespace pytorch --namespace pytorch .
```

## Upgrade

```
helm upgrade pytorch --namespace pytorch .
```
