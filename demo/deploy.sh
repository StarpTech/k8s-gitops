helm template my-app ./umbrella-chart --output-dir ./temp-release
kbld -f ./temp-release -f umbrella-chart/kbld-sources.yaml --lock-output .umbrella-state/kbld.lock.yml --registry-verify-certs=false > .umbrella-state/state.yaml
kapp deploy -n default -a my-app -f ./.umbrella-state/state.yaml
# decrypt with sops and pipe to kapp
#kapp deploy -n default -a my-app -f <(sops -d ./.umbrella-state/state.yaml)