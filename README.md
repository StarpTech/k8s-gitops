<p align="center">
  <img alt="logo" src="https://raw.githubusercontent.com/StarpTech/k8s-gitops/main/workflow-v5.png" />
  <h3 align="center"><a href="https://helm.sh/">Helm</a> + <a href="https://github.com/k14s/kbld">kbld</a>  + <a href="https://github.com/k14s/kapp">kapp</a></h3>
  <p align="center">The GitOps workflow to manage Kubernetes applications at any scale (without server components).</p>
</p>


# Preface

>  Technology should not make our lives harder. Choosing a specific technology should not change the way you do something very basic so drastically that it's harder to use, as opposed to easier to use. That's the whole point of technology. - Chris Short

This guide describes a CI/CD workflow for Kubernetes that enables [GitOps](https://www.weave.works/technologies/gitops/) without relying on server components.

There are many tools to practice GitOps. ArgoCD and FluxCD are the successors of it. Both tools are great but come with a high cost. You need to manage a complex piece of software (kubernetes operator) in your cluster and it couples you to very specific solutions ([CRD's](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)). Additionally, they enforce a [Pull](https://www.weave.works/blog/why-is-a-pull-vs-a-push-pipeline-important) based CD workflow. I can't get used to practicing this flow because it feels cumbersome although I'm aware of the benefits:

- Automated updates of images without a connection to your cluster.
- Two-way synchronization (docker registry, config-repository)
- Out-of-sync detection

In search of something simpler I found the `k14s` tools. They are designed to be single-purpose and composable. They provide the required functionality to template, build, deploy without coupling to full-blown community solutions. Tools like Helm, Kustomize can be easily connected. The result is a predictable pipeline of client tools. The demo in this repository solves:

- [X] The entire release can be described declaratively and stored in git.
- [X] You don't need to run additional software on your cluster.
- [X] You can easily reproduce the state on your local machine.
- [X] The CI/CD lifecycle is sequential. ([Push](https://www.weave.works/blog/why-is-a-pull-vs-a-push-pipeline-important) based pipeline)
- [X] No coupling to specific CD solutions. Tools can be replaced like lego.

According to [Managing Helm releases the GitOps way](https://github.com/fluxcd/helm-operator-get-started) you need three things to apply the GitOps pipeline model. I think we can refute the last point.

## Project structure

We consider each directory as a separate repository. That should reflect a real-world scenario with multiple applications.

```
├── config-repository                   (contains all kubernetes manifests)
│   ├── .release                        (temporary snapshot of the release artifact)
│   │   ├── umbrella-chart
│   │   └── state.yaml
│   ├── app-locks                       (image references to ensure reproducible builds)  
│   │   └── demo-service.kbld.lock.yml
│   ├── umbrella-chart                  (collection of helm charts which describe the infra)
│   │   ├── charts
│   │   │   ├── demo-service
│   │   ├── Chart.lock                  (chart lock file to ensure reproducible install)
│   │   ├── Chart.yaml
│   │   └── values.yaml
├── demo-service-repository             (example application)
│   ├── build.sh                        (build and push the image)
│   ├── Dockerfile                      
│   ├── kbld.yaml                       (defines what image is build and where to push it)
└   └── umbrella-chart                  (describe the preview environment "optional")
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

[Helm](https://helm.sh/) is the package manager for Kubernetes. It provides an interface to manage chart dependencies. Helm guaranteed reproducible builds if you are working with the same helm values. Because all files are checked into git we can reproduce the helm templates at any commit.

### Dependency Management

- `helm dependency build` - Rebuild the charts/ directory based on the Chart.lock file
- `helm dependency list` - List the dependencies for the given chart
- `helm dependency update` - Update charts/ based on the contents of Chart.yaml

Helm allows you to manage a project composed of multiple microservices with a top-level [`umbrella-chart`](https://helm.sh/docs/howto/charts_tips_and_tricks/#complex-charts-with-many-dependencies). You can define [global](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/#global-chart-values) chart values that are accessible in all sub-charts. 

### Chart distribution

#### Chart Repository

In big teams sharing charts can be exhausting tasks. In that situation, you should think about a solution to host your own Chart Repository. You can use [`chartmuseum`](https://github.com/helm/chartmuseum).

#### S3

The simpler approach is to host your charts on S3 and use the helm plugin [`S3`](https://github.com/hypnoglow/helm-s3) to make them manageable with the helm cli.

#### kpt

There is another very interesting approach to share charts or configurations in general. Google has developed a tool called [`kpt`](https://googlecontainertools.github.io/kpt/). One of the features is to sync arbitrary files/subdirectories from a git repository. You can even merge upstream updates. This makes it very easy to share files across teams without working in multiple repositories at the same time. The solution would be to fetch a list of chart repositories and store them to `umbrella/charts/` and call `helm build`. Your `Chart.yaml` dependencies must be prefixed with `file://`.

```sh
# fetch team B order-service subdirectory
kpt pkg get https://github.com/myorg/charts/order-service@VERSION \
  umbrella-chart/charts/order-service

# lock dependencies
helm build

# make changes, merge changes and tag that version in the remote repository
kpt pkg update umbrella-chart/charts/order-service@gNEW_VERSION --strategy=resource-merge
```

#### Distribute configurations with containers

With [`kpt fn`](https://googlecontainertools.github.io/kpt/reference/fn/) you can generate, transform, and validate configuration files from images, starlark scripts, or binary executables. The command below will provide `DIR/` as an input to a container instance of `gcr.io/example.com/my-fn` executing the function in it and store the output in `charts/order-service`. This has great potential to align your tooling with containers.

> DOCKER all the things!

```sh
# run a function using explicit sources and sinks
kpt fn source DIR/ |
  kpt fn run --image gcr.io/example.com/my-fn |
  kpt fn sink charts/order-service/
```


### Advanced templating

Sometimes helm is not enough. This can have several reasons:

- The external chart isn't flexible enough.
- You want to keep base charts simple.
- You want to abstract environments.

In that case, you can use tools like [kustomize](https://github.com/kubernetes-sigs/kustomize) or [ytt](https://github.com/k14s/ytt).

```sh
# this approach allows you to patch specific files because file stucture is preserved
helm template my-app ./umbrella-chart --output-dir .release
# this requires a local kustomize.yaml
kustomize build .release

# or with ytt, this will template all files and update the original files
helm template my-app ./umbrella-chart --output-dir .release
ytt -f .release --ignore-unknown-comments --output-files .release
```

### :heavy_check_mark: Helm solves:

- [X] Build an application composed of multiple components.
- [X] Manage dependencies.
- [X] Distribute configurations.

## The application repository

If you practice CI you will test, build and deploy new images continuously in your CI. Every build produces an immutable image tag that must be replaced in your helm manifests. In order to automate and standardize this process, we use [kbld](https://github.com/k14s/kbld). `kbld` handles the workflow for building and pushing images. In your pipeline you need to run:

```
./demo-service-repository/build.sh
```

This command will build and push the image and outputs a `demo-service.kbld.lock` file. This file must be committed to the `config-repository/app-locks` to ensure that every deployment reference to the correct images. This procedure will trigger the CI in the config-repository and allows you to practice Continues-Deployment.

### Define your application images

Before we can build images, we must create some sources and image destinations so that `kbld` is able to know which images belong to your application. They are managed in the application repository `demo-service-repository/kbld.yaml`. They look like `CRD's` but they aren't applied to your cluster.

## The config repository

The directory `config-repository/.release` refers to the temporary desired state of your cluster. It's generated on your CI pipeline. The folder contains all kubernetes manifest files.

### Release snapshot

This command will prerender your umbrella chart to `config-repository/.release/state.yaml`, builds and push all necessary images and replace all image references in your manifests. It's important to note that no image is built in this step. We reuse all prerendered images references from `app-locks`. The result is a snapshot of your desired cluster state at a particular commit. The CD pipeline will deploy it straight to your cluster.

```sh
$ ./config-repository/render.sh
```

### :heavy_check_mark: kbld solves:

- [X] One way to build, tag and push images.
- [X] Agnostic to how manifests are generated.
- [X] Desired system state versioned in Git.
- [X] Every commit points to a specific image configuration of all maintained applications.

## Deployment

We use [kapp](https://github.com/k14s/kapp) to deploy our resources to kubernetes. `Kapp` ensures that all resources are properly installed in the right order. It provides an enhanced interface to understand what has really changed in your cluster. If you want to learn more you should check the [homepage](https://get-kapp.io/).

```sh
$ ./config-repository/deploy.sh
```

> :information_source: Kapp takes user provided config as the only source of truth, but also allows to explicitly specify that certain fields are cluster controlled. This method guarantees that clusters don't drift, which is better than what basic 3 way merge provides. **Source:** https://github.com/k14s/kapp/issues/58#issuecomment-559214883

### Clean up resources

If you need to delete your app. You only need to call:

```
$ ./config-repository/delete.sh
```

> This comes handy, if you need to clean up resources on dynamic environments.

### :heavy_check_mark: kapp solves:

- [X] One way to diffing, labeling, deployment and deletion
- [X] Agnostic to how manifests are generated.

## Environment Management 

In order to manage multiple environments like development and staging, you can create different branches. Every branch has a different set of image references (stored in `config-repository/app-locks`) and values for your helm charts.

## Secret Management

### sops
You can use [sops](https://github.com/mozilla/sops/) to encrypt yaml files. The files must be encrypted before they are distributed in helm charts.
In the deployment process, you can decrypt them with a single command. Sops support several KMS services (Hashicorp Vault, AWS Secrets Manager, etc).

> :bulb: CI solutions are usually shipped with a secret store. There you can store your certificate to encrypt the secrets.

```sh
# As a chart maintainer I can encrypt my secrets with:
find ./.release -name "*secret*" -exec sops -e -i {} \;

# Before deployment I will decrypt my secrets so kubernetes can read them.
kapp deploy -n default -a my-app -f <(sops -d ./.umbrella-state/state.yaml)
```

## Rollback / Releasing

The big strength of GitOps is that any commit represent a releasable version of your infrastructure setup.

### Controller

Where kubernetes controller really show its strength is `locality`. They are deployed in your cluster and are protected by their environment. We can use that fact and deploy a controller like [`secretgen-controller`](https://github.com/k14s/secretgen-controller) which is responsible to generate secrets on the cluster. `secretgen-controller` works with CRD's. In that way, the procedure to generate the secret is stored in git but you can't run into the situation where you accidentally commit your password. You will never touch the secret.

## Closing words

> The hardest thing [about running on Kubernetes] is gluing all the pieces together. You need to think more holistically about your systems and get a deep understanding of what you’re working with. - Chris Short

:checkered_flag: As you can see the variety of tools is immense. The biggest challenge is to find the right balance for your organization. The proposed solution is highly opinionated but it tries to solve common problems with new and established tools. I placed particular value on a solution that doesn't require server components. I hope this guide will help organization/startups to invest in kubernetes. Feel free to contact me or open an issue.

## Demo

Check out the [demo](./demo) to see how it looks like.

## More

- [Combine helm with kustomize](https://github.com/thomastaylor312/advanced-helm-demos/tree/master/post-render)
- [Skaffold an alternative to (kbld + kapp)](https://github.com/GoogleContainerTools/skaffold)
- [Managing Applications in Production: Helm vs ytt & kapp](https://www.youtube.com/watch?v=WJw1MDFMVuk)

## References

- [k14s-kubernetes-tools](https://tanzu.vmware.com/content/blog/introducing-k14s-kubernetes-tools-simple-and-composable-tools-for-application-deployment)
- [why-is-a-pull-vs-a-push-pipeline-important](https://www.weave.works/blog/why-is-a-pull-vs-a-push-pipeline-important)
- [The best CI/CD tool for kuberneets doesn't exist](https://thenewstack.io/the-best-ci-cd-tool-for-kubernetes-doesnt-exist/)