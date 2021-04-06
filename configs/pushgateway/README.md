# Prometheus pushgateway

## Install

```
helm install pushgateway --namespace monitoring .
```

## Uninstall

```
helm uninstall pushgateway --namespace monitoring
```

## Install with Ingress

It is possible to expose the pushgateway publicly via Kubernetes ingress. Since pushgateway does not come with any kind of authentication mechanism of itself we will use the basic authentication mechanism provided by contour. This chart deploys a [contour-authserver](https://github.com/projectcontour/contour-authserver) which authenticates the users.


Execute the following steps to expose pushgateway over the internet.

### Prerequisites

- Install contour.
- Install cert-manager.
- Install external-dns (optional: If you prefer creating records manually in a DNS provider then you can skip this component).

### Create Password

Create a file with username and password in htpasswd format:

```bash
touch auth
htpasswd -b auth user1 password1
htpasswd -b auth user2 password2
htpasswd -b auth user3 password3
```

Now create a secret out of that file:

```
kubectl create secret generic -n monitoring passwords --from-file=auth
kubectl annotate secret -n monitoring passwords projectcontour.io/auth-type=basic
```

### Special flags

Deploy the pushgateway with extra information overriding the values file:

```bash
helm install pushgateway --namespace monitoring . \
    --set ingress.enabled=true \
    --set ingress.host=<pushgateway URL host value>
```

Set the appropriate host value to deploy the pushgateway. This is the URL you will reach out to when accessing pushgateway over the internet.

### Test

Without password it fails:

```console
$ curl -I https://pushgateway.foobar.com/metrics
HTTP/2 401
www-authenticate: Basic realm="default", charset="UTF-8"
date: Tue, 06 Apr 2021 08:34:41 GMT
server: envoy
```

With password:

```console
$ curl --user user1:password1 -s https://pushgateway.foobar.com/metrics | head -5
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 7.0803e-05
go_gc_duration_seconds{quantile="0.25"} 0.000107011
go_gc_duration_seconds{quantile="0.5"} 0.000119244
```
