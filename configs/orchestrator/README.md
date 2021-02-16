# Orchestrator

This will install Lokomotive clusters.

## Install:

```bash
helm install --values=values-real.yaml --set-file runScript=run.sh --create-namespace --namespace orchestrator orchestrator .
```

## Upgrade

```bash
helm upgrade --values=values-real.yaml --set-file runScript=run.sh --namespace orchestrator orchestrator .
```

## Delete

```
helm uninstall orchestrator
kubectl delete ns orchestrator
```
