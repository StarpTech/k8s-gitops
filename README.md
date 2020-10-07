<p align="center">
  <img alt="logo" src="https://raw.githubusercontent.com/StarpTech/k8s-gitops/main/logo.png" />
  <h3 align="center"><a href="https://helm.sh/">Helm</a> + <a href="https://github.com/k14s/kbld">kbld</a>  + <a href="https://github.com/k14s/kapp">kapp</a></h3>
  <p align="center">The GitOps workflow to manage Kubernetes application at any scale (without server components).</p>
</p>


# Preface

<p align="center">
  <img alt="logo" src="https://raw.githubusercontent.com/StarpTech/k8s-gitops/main/workflow.png" />
</p>

This guide describes a CI/CD workflow for Kubernetes that enables [GitOps](https://www.weave.works/technologies/gitops/) without relying on server components.

There are many tools to practice GitOps. ArgoCD and FluxCD are the successor of it. Both tools are great but comes with a high cost. You need to manage a complex piece of software (kubernetes operator) in your cluster and it couples you to very specific solutions ([CRD's](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)). Additionally, they enfore a [Pull](https://www.weave.works/blog/why-is-a-pull-vs-a-push-pipeline-important) based CD workflow. I can't get used to practice this flow because it feels cumbersome although I'm aware of the benefits:

- Automated updates of images without a connection to you cluster.
- Two-way synchronization (docker registry, config-repository)
- Out-of-sync detection

In search of something simpler I found the `k14s` tools. They are designed to be single-purpose and composable. They provide the required functionality to template, build, deploy without coupling to full-blown community solutions. Tools like Helm, Kustomize can be easily connected. The result is a predictable pipeline of client tools. The demo in this repository solves:

- [X] The entire release can be described declaratively and stored in git.
- [X] You can create branches to derive your config and deploy them in your CI.
- [X] You don't need to run additional software on your cluster.
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

[Helm](https://helm.sh/) is the package manager for Kubernetes. It provides an interface to manage chart dependencies. Helm guaranteed reproducable builds if you are working with the same helm values. Because all files are checked into git we can reproduce the helm templates at any commit.

### Dependency Management

- `helm dependency build` - Rebuild the charts/ directory based on the Chart.lock file
- `helm dependency list` - List the dependencies for the given chart
- `helm dependency update` - Update charts/ based on the contents of Chart.yaml

Helm allows you to manage a project composed of multiple microservices with a top-level [`umbrella-chart`](https://helm.sh/docs/howto/charts_tips_and_tricks/#complex-charts-with-many-dependencies). You can define [global](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/#global-chart-values) chart values which are accessible in all sub-charts. 

### Chart distribution

In big teams sharing charts can be an exhauasting tasks. In that situation you should think about a solution to host your own Chart Repository. You can use [`chartmuseum`](https://github.com/helm/chartmuseum). The simpler approach is to host your charts on S3 and use the helm plugin [`S3`](https://github.com/hypnoglow/helm-s3) to make them managable with the helm cli.

#### kpt

There is another very interesting approach to share charts or configurations in general. Google has developed a tool called [`kpt`](https://googlecontainertools.github.io/kpt/). One of the features is to sync arbitrary files / subdirectories from a git repository. You can even merge upstream updates. This make it very easy to share files across teams without working in multiple repositories at the same time. The solution would be to fetch a list of chart repositories and store them to `umbrella/charts/` and call `helm build`. Your `Chart.yaml` dependencies must be prefixed with `file://`.

```sh
# fetch team B order-service subdirectory
kpt pkg get https://github.com/myorg/charts/order-service@VERSION \
  umbrella-chart/charts/order-service

# lock dependencies
helm build

# make changes, merge changes and tag that version in the remote repository
kpt pkg update umbrella-chart/charts/order-service@gNEW_VERSION --strategy=resource-merge
```

### Advanced templating

Sometimes helm is not enough. This can have several reasons:

- The external chart isn't flexible enough.
- You want to keep base charts simple.
- You want to abstract environments.

In that case you can use tools like [kustomize](https://github.com/kubernetes-sigs/kustomize) or [ytt](https://github.com/k14s/ytt).

```sh
# this approach allows you to patch specific files because file stucture is preserved
helm template my-app ./umbrella-chart --output-dir ./temp-release
# this requires a local kustomize.yaml
kustomize build ./temp-release

# or with ytt, this will template all files and update the original files
helm template my-app ./umbrella-chart --output-dir ./temp-release
ytt -f ./temp-release --ignore-unknown-comments --output-files ./temp-release
```

### :heavy_check_mark: Helm solves:

- [X] Build an application composed of multiple components.
- [X] Manage dependencies.
- [X] Distribute configurations.

## The umbrella-state

The directory `umbrella-state` refers to the single-source-of truth of the desired state of your cluster at a particular commit. The folder contains all kubernetes manifests and `.lock` files. The folder must be commited to git.

### :heavy_check_mark: The umbrella-state solves:

- [X] Desired system state versioned in Git.
- [X] Single-source of truth.

## Build, Test and Push your images

If you practice CI you will test, build and deploy new images continuously in your CI. The image tag must be replaced in your helm manifests. In order to automate and standardize this process we use [kbld](https://github.com/k14s/kbld). `kbld` handles the workflow for building and pushing images. It integrates with helm and kustomize really well because it doesn't care how manifests are generated.


### Define your application images

Before we can build images, we must create some sources and image destinations so that `kbld` is able to know which images belong to your application. For the sake of simplicity, we put them in `umbrella-chart/kbld-sources.yaml`. They look like `CRD's` but they aren't applied to your cluster.

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

This command will prerender your umbrella chart to `.umbrella-state/state.yaml`, builds and push all necessary images and replace all references in your manifests. The result is a snapshot of your desired cluster state. The `kbld.lock.yml` represents a lock file of all tagged images. This is useful to ensure that the exact same images are used on subsequent deployments.

```sh
# template chart, build / push images to registry and replace images references with immutables tags
$ helm template my-app ./umbrella-chart | kbld -f - -f umbrella-chart/kbld-sources.yaml --lock-output .umbrella-state/kbld.lock.yml --registry-verify-certs=false > ./.umbrella-state/state.yaml
```

#### Update the state in your CI

Every change in the artifact directory `.umbrella-state/` must be commited to git. This means you can reproduce the state at any commit by triggering you CI pipeline. `[ci skip]` is necessary to avoid rescheduling your CI if you commit `.umbrella-state/` in your CI pipeline.

```sh
git add .umbrella-state/* && git commit -m "[ci skip] New Release"
```

> :bulb: As shown in the [Chart distribution](#chart-distribution) section. You could use [`kpt`](https://googlecontainertools.github.io/kpt/) to share the state of your repository. This might be useful if you want to point to a specific infrastructure setup. Maybe the production setup which can adjusted afterwards with [kustomize](https://github.com/kubernetes-sigs/kustomize) or [ytt](https://github.com/k14s/ytt)?

### :heavy_check_mark: kbld / umbrella-state solves:

- [X] One way to build, tag and push images.
- [X] Agnostic to how manifests are generated.
- [X] Desired system state versioned in Git.
- [X] Single-source of truth.

## Deployment

We use [kapp](https://github.com/k14s/kapp) to deploy `.umbrella-state/state.yaml` to the kubernetes cluster. `Kapp` ensures that all ressources are properly installed in the right order. It provides an enhanced interface to understand what has really changed in your cluster. If you want to learn more you should check the [homepage](https://get-kapp.io/).

```sh
# deploy it on your cluster
$ kapp deploy --yes -n default -a my-app -f ./.umbrella-state/state.yaml
```

> :warning: Make sure that you don't use helm for releases. This would be incompatible with the GitOps principles because releases aren't stored in git. You rollback your application by switching / cherry-pick to a specific git tag.

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

- **Monorepo**: Put your infrastucture code along your code. You can create different branches for different environments.
- **Multiple repositories**: Create a config-repository which reflect the state of your environment. In that case you don't need to rebuild your container for config changes and there is no "leading" application repository.
- **Preview deployments**: Manage a local umbrella-chart which describes the preview-environment. You could also create a config-repository.

## Secret Management

You can use [sops](https://github.com/mozilla/sops/) to encrypt yaml files. The files must be encrypted before they are distributed in helm charts.
In the deployment process you can decrypt them with a single command. Sops support several KMS services (Hashicorp Vault, AWS Secrets Manager, etc).

```sh
# As a chart maintainer I can encrypt my secrets with:
find ./temp-release -name "*secret*" -exec sops -e -i {} \;

# Before deployment I will decrypt my secrets so kubernetes can read them.
kapp deploy -n default -a my-app -f <(sops -d ./.umbrella-state/state.yaml)
```

> :bulb: Another approach is to enrich secrets in the pipeline process and pass them to the template tool. CI solutions are usually shipped with a secret store.

## Closing words

:checkered_flag: As you can see the variety of tools is immense. The biggest challenge is to find the right balance for your organization. The proposed solution is highly opinionated but it tries to solve common problems with new and established tools. I placed particular value on a solution that doesn't require server components. I hope this guide will help organization/startups to invest in kubernetes. Feel free to contact me or open an issue.

## Demo

Checkout the [demo](./demo) to see how it looks like.

## More

- [Combine helm with kustomize](https://github.com/thomastaylor312/advanced-helm-demos/tree/master/post-render)
- [kpt](https://googlecontainertools.github.io/kpt/)
- [skaffold an alternative to (kbld + kapp)](https://github.com/GoogleContainerTools/skaffold)

## References

- [k14s-kubernetes-tools](https://tanzu.vmware.com/content/blog/introducing-k14s-kubernetes-tools-simple-and-composable-tools-for-application-deployment)
- [why-is-a-pull-vs-a-push-pipeline-important](https://www.weave.works/blog/why-is-a-pull-vs-a-push-pipeline-important)

## Credits

The logo is provided by [icons8.de](https://icons8.de)