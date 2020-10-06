# performs static code analysis of your Kubernetes object definitions. 
# helm template my-app ./umbrella-chart | kube-score score -

helm template my-app ./umbrella-chart --output-dir ./temp-release
kbld -f ./temp-release/umbrella-chart -f umbrella-chart/kbld-sources.yaml --lock-output .umbrella-state/kbld.lock.yml --registry-verify-certs=false > .umbrella-state/state.yaml

# Validate your Kubernetes configuration files
# kubeval --ignore-missing-schemas .umbrella-state/state.yaml

kapp deploy -n default -a my-app -c -f ./.umbrella-state/state.yaml

# decrypt with sops and pipe to kapp
# kapp deploy -n default -a my-app -f <(sops -d ./.umbrella-state/state.yaml)