<p align="center">
  <img alt="logo" src="https://raw.githubusercontent.com/StarpTech/k8s-gitops/main/logo.png" />
  <h3 align="center"><a href="https://helm.sh/">Helm</a> + <a href="https://github.com/k14s/kbld">kbld</a>  + <a href="https://github.com/k14s/kapp">kapp</a></h3>
  <p align="center">The GitOps workflow to manage Kubernetes application at any size (without server components).</p>
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

[Helm](https://helm.sh/) is the package manager for Kubernetes. It provides an interface to manage chart dependencies.

### Dependency Management

- `helm dependency build` - Rebuild the charts/ directory based on the Chart.lock file
- `helm dependency list` - List the dependencies for the given chart
- `helm dependency update` - Update charts/ based on the contents of Chart.yaml

Helm allows you to manage a project composed of multiple microservices with a top-level [`umbrella-chart`](https://helm.sh/docs/howto/charts_tips_and_tricks/#complex-charts-with-many-dependencies). You can define [global](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/#global-chart-values) chart values which are accessible in all sub-charts. 

In big teams sharing charts can be an exhauasting tasks. In that situation you should think about to host your own Chart Repoitory. You can use [`chartmuseum`](https://github.com/helm/chartmuseum). The simpler solution is to host your charts on S3 and use the helm plugin [`S3`](https://github.com/hypnoglow/helm-s3) to make them accessible in the cli.

### :heavy_check_mark: Helm solves:

- [X] Compose multiple application into a bigger one.
- [X] Manage dependencies.
- [X] Distribute configurations.

## The umbrella-state

Helm guaranteed reproducable builds if you are working with the same helm values. Because all files are checked into git we can reproduce the helm release at any commit.

The `umbrella-state` refers to the single-source-of truth of an helm release at a particular time.

### :heavy_check_mark: The umbrella-state solves:

- [X] Desired system state versioned in Git.
- [X] Single-source of truth.

## Build, Test and Push your images

If you practice CI you will test, build and deploy new images continuously in your CI. The image tag must be replaced in your helm manifests. In order to automate and standardize this process we use [kbld](https://github.com/k14s/kbld). `kbld` handles the workflow for building, pushing images. It integrates with helm, kustomize really well.


### Define your application images

You must create some sources and image destinations so that `kbld` is able to know which images belong to your application. For the sake of simplicity we put them in `umbrella-state/sources.yaml`.

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

This command will prerender your umbrella chart to `umbrella-state/`, builds and push all necessary images and replace all references in your manifests. The result is a snapshot of your release. The `kbld.lock.yml` represents a lock file of all tagged images. This is useful to ensure that the exact same image is used for the deployment.

```sh
$ helm template ./umbrella-chart --values my-vals.yml --verify --namespace production --create-namespace --validate --output-dir umbrella-state
$ kbld -f umbrella-state/ --lock-output umbrella-state/kbld.lock.yml
```

The artifact directory `umbrella-state/` must be commited to git. This means you can reproduce the state at any commit. `[ci skip]` is necessary to avoid retriggering your CI.

```sh
git add umbrella-state/* && git commit -m "[ci skip] New Release"
```

### :heavy_check_mark: kbld / umbrella-state solves:

- [X] One way to build, tag and push images.
- [X] Agnostic to how manifests are generated.
- [X] Desired system state versioned in Git.
- [X] Single-source of truth.

## Deployment

We use [kapp](https://github.com/k14s/kapp) to deploy the manifests to the kubernetes cluster. `Kapp` ensures that all ressources are properly installed in the right order. It provides an enhanced interface to understand what has really changed in your cluster. If you want to learn more you should check the [homepage](https://get-kapp.io/).

```
$ kapp app-group deploy -g production-app --directory umbrella-state/ --yes
```

:warning: Make sure that you don't use helm for releases. This would be incompatible to the GitOps principles because we can't render that procedure to git. You rollback your application by switching / cherry-pick to a specific commit in git.

### Clean up resources

If you need to delete your app. You only need to call:

```
$ kapp delete -a production-app
```

> This comes handy, if you need to clean up resources when a PR is closed.

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