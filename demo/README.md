# demo

## Build app

TBuild and push the image.

```
$ ./demo-service-repository/build.sh
```

## Deploy app

The image is deployed to yyour cluster.

```
$ ./config-repository/render.sh
$ ./config-repository/deploy.sh
```

## Delete resources

All resources are deleted.

```
$ delete.sh
```
