# wrk2
This is a tiny Docker image for wrk2, based on Alpine. The image aims for
minimal size. The image is based on the Alpine Linux distribution.

Kinvolk maintains an up-to-date container image at quay.io/kinvolk/wrk2.

## How to
```
./render.sh | kubectl apply -f-
```

This will deploy a kubernetes Job which, with default settings, will benchmark
the [emojivoto](https://github.com/BuoyantIO/emojivoto) application. Emojivoto
is a demo app maintained by Buoyant, and shipped with the `linkerd` service
mesh (please note that emojivoto is not linkerd specific and happily runs
without a service mesh).

### Getting results
```
kubectl -n benchmark-load-generator logs wrk2-<id>
```

Benchmark results can be accessed via `kubectl logs` as wrk2 prints these
via stdout after a benchmark run concluded.

### Parametrizing benchmark runs
```
./render.sh --help
Usage: ./render.sh [OPTION...]

 This script will render wrk2.yaml.tmpl with provided parameters, combine it with multi-server.lua and print to stdout.

 Optional arguments:
  -i, --image     wrk2 Docker image name.
  -d, --duration  Duration of benchmark.
  -r, --rate      Requests per second for each instance.
  -I, --instances Number of instances.
  -h  --help      Prints this message.
```

You can customize wrk2 by passing specific arguments to `render.sh` script.

## Building the image
Build the image by issuing:

```
docker build -t quay.io/kinvolk/wrk2 .
```

After the build concluded, you may push the image to a registry and use the
`--image` option of the `render.sh` script to deploy it.
