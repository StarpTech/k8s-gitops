# k8s-gitops

This guide describe a GitOps workflow without relying on more tools than absolutly necessary. We use established software like [`helm`](https://helm.sh/) and [`skaffold`](https://skaffold.dev/) to provide a modern [Push based](https://www.weave.works/blog/why-is-a-pull-vs-a-push-pipeline-important) CI/CD workflow.


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

## Structure
```
├── umbrella-chart
│   ├── charts
│   │   ├── order-service
│   │   └── user-service
│   ├── Chart.lock
|   ├── values.yaml
│   └── Chart.yaml
```

## The release "state"

Helm guaranteed reproducable builds if you are working with the same `values.yaml` and `Chart.lock`. Because all files are checked into git we can reproduce the release at any commit.

## Deploy

Now you can deploy your chart in your CI.

```
$ helm upgrade production ./umbrella-chart --atomic --create-namespace --wait --namespace production
```

This command will install your chart under the namespace `production` and will wait until all resources are in a ready state before marking the release as successful.

## Automate the build, test, deploy process

Until now we can template and release automated. This is not the full story. If you practice CI you will test, build and deploy new images continuously. The image tag must be replaced in your helm chart. In order to automate and standardize this process we use [skaffold](https://skaffold.dev/). Skaffold handles the workflow for building, pushing and deploying your application. It provides built-in helm support.

Skaffold works with a single `skaffold.yaml`. You can find more information [here](https://skaffold.dev/docs/pipeline-stages/deployers/helm/) how helm is configured properly. In the example below you can see an example setup based on our conditions in the previous steps.

```yaml
deploy:
  helm:
    releases:
    - name: my-release
      chartPath: ./umbrella-chart
      namespace: production
      artifactOverrides:
        image: gcr.io/my-project/my-image # no tag present!
        # Skaffold continuously tags your image, so no need to put one here.

profiles:
  - name: app
    build:
      artifacts:
        - image: eu.gcr.io/doctama/order-service
          context: order-service
        - image: eu.gcr.io/doctama/user-service
          context: user-service
```

If you run `skaffold run -p app` skaffold will build, test and deploy your images. Images are tagged based on your [tagging](https://skaffold.dev/docs/pipeline-stages/taggers/) strategy and your helm chart is used to create a new helm release.
Skaffold waits until your deployment was successfully. It provides additional commands to debug and monitor your application.

> Done! You have a versioned and standarzied flow how to manage a microservice applicationa at any size.

## Useful tools

- [helm-diff](https://github.com/databus23/helm-diff) Calculate the diff between your local and latest deployed version.
- [helm-s3](https://github.com/hypnoglow/helm-s3) Share private Helm Charts with S3.