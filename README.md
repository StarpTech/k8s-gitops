# k8s-gitops

This guide describe a GitOps Kubernetes workflow without relying on server components. We provide a modern [Push based](https://www.weave.works/blog/why-is-a-pull-vs-a-push-pipeline-important) CI/CD workflow.


## Helm introduction

[Helm](https://helm.sh/) is the package manager for Kubernetes. It provides an interface to manage chart dependencies and releases.

### Dependency Management

- `helm dependency build` - Rebuild the charts/ directory based on the Chart.lock file
- `helm dependency list` - List the dependencies for the given chart
- `helm dependency update` - Update charts/ based on the contents of Chart.yaml

### Release Management

- `helm install` - Install a chart
- `helm uninstall` - Uninstall a release
- `helm upgrade` - Upgrade a release
- `helm rollback` - Roll back a release to a previous revision

You are able to manage a project composed of multiple microservices with a top-level [`umbrella-chart`](https://helm.sh/docs/howto/charts_tips_and_tricks/#complex-charts-with-many-dependencies). You can [override](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/#global-chart-values) sub-chart values in your `values.yaml` of the `umbrella-chart`.

## Project structure
```
├── umbrella-chart
│   ├── charts
│   │   ├── order-service
│   │   └── user-service
│   ├── Chart.lock
|   ├── values.yaml
│   └── Chart.yaml
├── umbrella-state
│   ├── sources.yaml
|   ├── generated manifest...
```

## The umbrella-state

Helm guaranteed reproducable builds if you are working with the same `values.yaml` and `Chart.lock`. Because all files are checked into git we can reproduce the helm release at any commit. The umbrella-state refers to the single-source-of truth of an helm release.

## Automate the build, test and push step

If you practice CI you will test, build and deploy new images continuously in your CI. The image tag must be replaced in your helm manifest. In order to automate and standardize this process we use [kbld](https://github.com/k14s/kbld). `kbld` handles the workflow for building, pushing images. It integrates with helm, kustomize really well.

### Define your application images

You must create your sources in `release/sources.yaml` so that `kbld` is able to know which images belong to your application.
```yaml
#! where to find order-service source
---
apiVersion: kbld.k14s.io/v1alpha1
kind: Sources
sources:
- image: order-service
  path: order-service
---
#! where to push app1 image
---
apiVersion: kbld.k14s.io/v1alpha1
kind: ImageDestinations
destinations:
- image: order-service
  newImage: docker.io/hk/order-service

```

### Prerender your release

This command will prerender your umbrella chart to `release/`, builds / push all necessary images and replace all references in your manifests.

```sh
helm template ./umbrella-chart --values my-vals.yml --verify --namespace production --create-namespace --output-dir release
kbld -f release/
```

The artifact must be commited to git. This means we can rollback at any time, at any commit.

## Automate the deploy step

We use [kapp](https://github.com/k14s/kapp) to deploy the manifests to the kubernetes cluster. `Kapp` ensures that all ressources are properly installed.

```
$ kapp app-group deploy -g production --directory umbrella-state/
```

> Done! You have an automated CI/CD GitOps workflow to manage a microservice application at any size and without relying on server components like a kubernetes operator.

## References

- [helm-s3](https://github.com/hypnoglow/helm-s3) Share private Helm Charts with S3.
- [k14s-kubernetes-tools](https://tanzu.vmware.com/content/blog/introducing-k14s-kubernetes-tools-simple-and-composable-tools-for-application-deployment)