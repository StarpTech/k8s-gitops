#!/bin/bash

./render.sh
kapp deploy -n default -a my-app -c -f ./.release/state.yaml

# sleep 5