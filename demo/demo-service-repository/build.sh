#!/bin/bash

# Build, Push image
kbld -f ./image.yaml --lock-output demo-service.kbld.lock.yml --registry-verify-certs=false
# (simulate) Commit lock file to config repository
mv demo-service.kbld.lock.yml ./../config-repository/app-locks