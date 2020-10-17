#!/bin/bash

# performs static code analysis of your Kubernetes object definitions. 
# helm template my-app ./umbrella-chart | kube-score score -

# Validate your Kubernetes configuration files
# kubeval --ignore-missing-schemas .umbrella-state/state.yaml
helm template my-app ./umbrella-chart --output-dir ./.release
kbld -f ./.release/umbrella-chart -f ./app-locks --registry-verify-certs=false > ./.release/state.yaml
# decrypt with sops and pipe to kapp
# kapp deploy -n default -a my-app -f <(sops -d ./.umbrella-state/state.yaml)

# sleep 5