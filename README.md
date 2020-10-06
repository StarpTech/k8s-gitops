<p align="center">
  <img alt="logo" src="https://raw.githubusercontent.com/StarpTech/k8s-gitops/main/logo.png" />
  <h3 align="center"><a href="https://helm.sh/">Helm</a> + <a href="https://github.com/k14s/kbld">kbld</a>  + <a href="https://github.com/k14s/kapp">kapp</a></h3>
  <p align="center">The GitOps workflow to manage Kubernetes application at any scale (without server components).</p>
</p>

# Preface

This guide describes a CI/CD workflow for Kubernetes that enables [GitOps](https://www.weave.works/technologies/gitops/) without relying on server components.

There are many tools to practice GitOps. ArgoCD and FluxCD are the successor of it. Both tools are great but comes with a high cost. You need to manage a complex piece of software (kubernetes operator) in your cluster and it couples you to very specific solutions (CRD's). Additionally, they enfore a [Pull](https://www.weave.works/blog/why-is-a-pull-vs-a-push-pipeline-important) based CD workflow. I can't get used to practice this flow because it feels cumbersome although I'm aware of the benefits:

- Automated updates of images without a connection to you cluster.
- Two-way synchronization (docker registry, config-repository)
- Out-of-sync detection

In search of something simpler I found the `k14s` tools. They are designed to be single-purpose and composable. They provide the required functionality to template, build, deploy without coupling to full-blown community solutions. Tools like Helm, Kustomize can be easily connected. The result is a predictable pipeline of client tools. The demo in this repository solves:

- [X] The entire release can be described declaratively and stored in git.
- [X] You can create branches to derivate your config and deploy them in your CI.
- [X] You don't need to manage additional state on your cluster.
- [X] You can easily reproduce the state on your local machine.
- [X] The CI/CD lifecycle is sequential. ([Push](https://www.weave.works/blog/why-is-a-pull-vs-a-push-pipeline-important) based pipeline)

According to [Managing Helm releases the GitOps way](https://github.com/fluxcd/helm-operator-get-started) you need three things to apply the GitOps pipeline model. I think we can refute the last point.

## Project structure
```
├── umbrella-chart
│   ├── charts
│   │   └── demo-service
│   ├── Chart.lock
|   ├── values.yaml
|   ├── kbld-sources.yaml
│   └── Chart.yaml
├── .umbrella-state
│   ├── kbld.lock.yml
|   └── state.yaml (snapshot of the release artifact)
```

## Prerequisites

- [helm](https://helm.sh/) - Package manager
- [kbld](https://github.com/k14s/kbld) - Image building and image pushing
- [kapp](https://github.com/k14s/kapp) - Deployment tool
- [kpt](https://googlecontainertools.github.io/kpt/reference/pkg/) - Fetch, update, and sync configuration files using git
- [kubeval](https://github.com/instrumenta/kubeval) (optional) - Validate your Kubernetes configuration files
- [kube-score](https://github.com/zegl/kube-score) (optional) - Static code analysis
- [sops](https://github.com/mozilla/sops/) (optional) - Secret encryption

## Helm introduction

[Helm](https://helm.sh/) is the package manager for Kubernetes. It provides an interface to manage chart dependencies.

### Dependency Management

- `helm dependency build` - Rebuild the charts/ directory based on the Chart.lock file
- `helm dependency list` - List the dependencies for the given chart
- `helm dependency update` - Update charts/ based on the contents of Chart.yaml

Helm allows you to manage a project composed of multiple microservices with a top-level [`umbrella-chart`](https://helm.sh/docs/howto/charts_tips_and_tricks/#complex-charts-with-many-dependencies). You can define [global](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/#global-chart-values) chart values which are accessible in all sub-charts. 

### Chart distribution

In big teams sharing charts can be an exhauasting tasks. In that situation you should think about a solution to host your own Chart Repository. You can use [`chartmuseum`](https://github.com/helm/chartmuseum). The simpler approach is to host your charts on S3 and use the helm plugin [`S3`](https://github.com/hypnoglow/helm-s3) to make them managable in the cli.

There is another very interesting approach to share charts or configurations in general. Google has developed a tool called `kpt`. One of the features is to sync arbitrary files / subdirectories from a git repository. You can even merge upstream updates. This make it very easy to share files across teams without working in multiple repositories at the same time.

```sh
# fetch staging subdirectory
kpt pkg get https://github.com/starptech/examples/staging@git-VERSION \
  my-staging
# just for demo purpose
kubectl apply -R -f my-cockroachdb

# make changes, merge changes and tag that version in the remote repository
kpt pkg update my-cockroachdb@NEW_VERSION --strategy=resource-merge
```

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

You must create some sources and image destinations so that `kbld` is able to know which images belong to your application. For the sake of simplicity we put them in `umbrella-chart/kbld-sources.yaml`.

```yaml
#! where to find demo-service source
---
apiVersion: kbld.k14s.io/v1alpha1
kind: Sources
sources:
- image: demo-service
  path: demo-service
---
#! where to push demo-service image
---
apiVersion: kbld.k14s.io/v1alpha1
kind: ImageDestinations
destinations:
- image: demo-service
  newImage: docker.io/hk/demo-service

```

### Release snapshot

This command will prerender your umbrella chart to `.umbrella-state/state.yaml`, builds and push all necessary images and replace all references in your manifests. The result is a snapshot of your release. The `kbld.lock.yml` represents a lock file of all tagged images. This is useful to ensure that the exact same image is used for the deployment.

```sh
# template chart, build / push images to registry and replace images references with immutables tags
$ helm template my-app ./umbrella-chart | kbld -f - -f umbrella-chart/kbld-sources.yaml --lock-output .umbrella-state/kbld.lock.yml --registry-verify-certs=false > ./.umbrella-state/state.yaml
```

#### Update the state in git

The artifact directory `.umbrella-state/` must be commited to git. This means you can reproduce the state at any commit. `[ci skip]` is necessary to avoid retriggering your CI.

```sh
git add .umbrella-state/* && git commit -m "[ci skip] New Release"
```

### :heavy_check_mark: kbld / umbrella-state solves:

- [X] One way to build, tag and push images.
- [X] Agnostic to how manifests are generated.
- [X] Desired system state versioned in Git.
- [X] Single-source of truth.

## Deployment

We use [kapp](https://github.com/k14s/kapp) to deploy the manifests to the kubernetes cluster. `Kapp` ensures that all ressources are properly installed in the right order. It provides an enhanced interface to understand what has really changed in your cluster. If you want to learn more you should check the [homepage](https://get-kapp.io/).

```sh
# deploy it on your cluster
$ kapp deploy --yes -n default -a my-app -f ./.umbrella-state/state.yaml
```

> :warning: Make sure that you don't use helm for releases. This would be incompatible with the GitOps principles because we can't store it in git. You rollback your application by switching / cherry-pick to a specific commit in git.

> :information_source: Kapp takes user provided config as the only source of truth, but also allows to explicitly specify that certain fields are cluster controlled. This method guarantees that clusters don't drift, which is better than what basic 3 way merge provides. **Source:** https://github.com/k14s/kapp/issues/58#issuecomment-559214883

### Clean up resources

If you need to delete your app. You only need to call:

```
$ kapp delete -a my-app --yes
```

> This comes handy, if you need to clean up resources on dynamic environments.

### :heavy_check_mark: kapp solves:

- [X] One way to diffing, labeling, deployment and deletion
- [X] Agnostic to how manifests are generated.

## Environment Management

Here are some ideas how you can deal with multiple environments:

- Monorepo: Put your infrastucture code along your code. You can create different branches for different environments.
- Multiple repositories: Create a config-repository which reflect the state of your environment. In that case you don't need to retrigger your CI for config changes and there is no "leading" application repository.
- Preview deployments: Manage a local umbrella-chart which describes the environment of your preview-deployment. You could also create a config-repository for preview-deployments.

## Secret Management

You can use [sops](https://github.com/mozilla/sops/) to encrypt yaml files. The files must be encrypted before they are distributed in helm charts.
In the deployment process you can decrypt them with a single command. Sops support several KMS services (Hashicorp Vault, AWS Secrets Manager, etc).

```sh
# As a chart maintainer I can encrypt my secrets with:
find ./temp-release -name "*secret*" -exec sops -e -i {} \;

# Before deployment I will decrypt my secrets so kubernetes can read them.
kapp deploy -n default -a my-app -f <(sops -d ./.umbrella-state/state.yaml)
```

## :checkered_flag: Result

> Done! You have an automated CI/CD GitOps workflow to manage an microservice architecture at any size and **without** relying on server components like a kubernetes operator.

## Demo

Checkout the [demo](./demo) to see how it looks like.

## More

- [Combine helm with kustomize](https://github.com/thomastaylor312/advanced-helm-demos/tree/master/post-render)
- [kpt an alternative (kapp)](https://googlecontainertools.github.io/kpt/)
- [skaffold an alternative to (kbld + kapp)](https://github.com/GoogleContainerTools/skaffold)

## References

- [k14s-kubernetes-tools](https://tanzu.vmware.com/content/blog/introducing-k14s-kubernetes-tools-simple-and-composable-tools-for-application-deployment)
- [why-is-a-pull-vs-a-push-pipeline-important](https://www.weave.works/blog/why-is-a-pull-vs-a-push-pipeline-important)

## Credits

The logo is provided by [icons8.de](https://icons8.de)