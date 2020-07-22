# benchmark

## Install

```bash
helm install --create-namespace benchmark --namespace benchmark .
```

## Upgrade

```bash
helm upgrade benchmark --namespace benchmark .
```

## Run a scenario

### Deploy Istio

```bash
lokoctl component apply istio-operator
```

### Deploy target application first

```bash
cd configs/emojivoto/
for ((i=0;i<10;i++))
do
  kubectl create namespace emojivoto-$i
  kubectl label namespace emojivoto-$i istio-injection=enabled
  helm install emojivoto-$i --namespace emojivoto-$i .
done
```

### Deploy benchmark application

```bash
cd configs/benchmark/
kubectl create ns benchmark
kubectl label namespace benchmark istio-injection=enabled
helm install benchmark --namespace benchmark . --set wrk2.serviceMesh=istio --set wrk2.app.count=10
```
