<p align="center">
  <img alt="logo" src="https://raw.githubusercontent.com/StarpTech/k8s-gitops/main/logo.png" />
  <h3 align="center"><a href="https://helm.sh/">Helm</a> + <a href="https://github.com/k14s/kbld">kbld</a>  + <a href="https://github.com/k14s/kapp">kapp</a></h3>
  <p align="center">The GitOps way to manage Kubernetes application at any size and without server components.</p>
</p>

This guide describe a [GitOps](https://www.weave.works/technologies/gitops/) Kubernetes workflow without relying on server components. We provide a modern [Push based](https://www.weave.works/blog/why-is-a-pull-vs-a-push-pipeline-important) CI/CD workflow.

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
|   ├── generated manifests...
```

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

### :heavy_check_mark: Helm solves:

- [X] Compose multiple configurations.
- [X] Manage upgrades, rollbacks.
- [X] Distribute configurations.

## The umbrella-state

Helm guaranteed reproducable builds if you are working with the same helm values. Because all files are checked into git we can reproduce the helm release at any commit. The `umbrella-state` refers to the single-source-of truth of an helm release. The umbrella-state is updated automatically in the CI pipeline.

### :heavy_check_mark: The umbrella-state solves:

- [X] Desired system state versioned in Git.
- [X] Single-source of truth.

## Build, Test and Push your images

If you practice CI you will test, build and deploy new images continuously in your CI. The image tag must be replaced in your helm manifests. In order to automate and standardize this process we use [kbld](https://github.com/k14s/kbld). `kbld` handles the workflow for building, pushing images. It integrates with helm, kustomize really well.


### Define your application images

You must create some sources and image destinations in `umbrella-state/sources.yaml` so that `kbld` is able to know which images belong to your application.
```yaml
#! where to find order-service source
---
apiVersion: kbld.k14s.io/v1alpha1
kind: Sources
sources:
- image: order-service
  path: order-service
---
#! where to push order-service image
---
apiVersion: kbld.k14s.io/v1alpha1
kind: ImageDestinations
destinations:
- image: order-service
  newImage: docker.io/hk/order-service

```

### Release snapshot

This command will prerender your umbrella chart to `umbrella-state/`, builds / push all necessary images and replace all references in your manifests. The result is a complete static snapshot of your release. The `kbld.lock.yml` represents a lock file of all tagged images. This is useful to ensure that the exact same image is used for the deployment.

```sh
$ helm template ./umbrella-chart --values my-vals.yml --verify --namespace production --create-namespace --output-dir umbrella-state
$ kbld -f umbrella-state/ --lock-output umbrella-state/kbld.lock.yml
```

The artifact directory `umbrella-state/` must be commited to git. This means we can reproduce the state at any commit.

### :heavy_check_mark: kbld / umbrella-state solves:

- [X] One way to build, tag and push images.
- [X] Agnostic to how manifests are generated.
- [X] Desired system state versioned in Git.
- [X] Single-source of truth.

## Deployment

We use [kapp](https://github.com/k14s/kapp) to deploy the manifests to the kubernetes cluster. `Kapp` ensures that all ressources are properly installed.

```
$ kapp app-group deploy -g production --directory umbrella-state/
```

### :heavy_check_mark: kapp solves:

- [X] One way to diffing, labeling, deployment and deletion
- [X] Agnostic to how manifests are generated.

## :checkered_flag: Result

> Done! You have an automated CI/CD GitOps workflow to manage an microservice architecture at any size and **without** relying on server components like a kubernetes operator.

## References

- [k14s-kubernetes-tools](https://tanzu.vmware.com/content/blog/introducing-k14s-kubernetes-tools-simple-and-composable-tools-for-application-deployment)
- [why-is-a-pull-vs-a-push-pipeline-important](https://www.weave.works/blog/why-is-a-pull-vs-a-push-pipeline-important)

## Credits

The logo is provided by [icons8.de](https://icons8.de)