#! /bin/bash

set -e

NEPHIO_DIR="./nephio-install"
NEPHIO_KPT_PACKAGES="./nephio-kpt-packages.txt"
PROXY_CONF="http-proxy.yaml"

install_kpt_package() {
    if [[ $# != 2 ]]; then
        echo "Usage: $0 <package name> <package location>"
        exit 1
    fi

    PKG_NAME=$1
    PKG_URL=$2

    kpt pkg get --for-deployment "${PKG_URL}"
    kpt fn render "${PKG_NAME}"
    if [[ "${PKG_NAME}" == "configsync" ]]; then
        # configure http proxy
        yq -i 'select(.kind == "Deployment" and .metadata.name == "config-management-operator").spec.template.spec.containers[0].env = load("../" + strenv(PROXY_CONF)).env' "${PKG_NAME}/config-management-operator.yaml"
    elif [[ "${PKG_NAME}" == "porch" ]]; then
        yq -i 'select(.kind == "Deployment" and .metadata.name == "porch-server").spec.template.spec.containers[0].env += load("../" + strenv(PROXY_CONF)).env' "${PKG_NAME}/3-porch-server.yaml"
    fi
    kpt live init "${PKG_NAME}"
    kpt live apply "${PKG_NAME}" --reconcile-timeout 15m --output=table
}

if [ ! -d "${NEPHIO_DIR}" ]; then
    mkdir "${NEPHIO_DIR}"
fi

./create-kind-cluster.sh

pushd "${NEPHIO_DIR}"

while read -r line; do
    IFS=" "
    read -a columns <<< "${line}"
    install_kpt_package "${columns[0]}" "${columns[1]}"
done < "../${NEPHIO_KPT_PACKAGES}"

popd
