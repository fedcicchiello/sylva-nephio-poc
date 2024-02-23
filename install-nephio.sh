#! /bin/bash

set -ex

NEPHIO_DIR="./nephio-install"
NEPHIO_KPT_PACKAGES="./nephio-kpt-packages.txt"
export PROXY_CONF="http-proxy.yaml"
STANDALONE_CLUSTER="false"
ONLY_GET_PKGS="false"
SYLVA_MGMT_VIP="163.162.114.133"
export GITEA_URL="https://gitea.sylva"

install_kpt_package() {
    if [[ $# != 2 ]]; then
        echo "Usage: $0 <package name> <package location>"
        exit 1
    fi

    PKG_NAME=$1
    PKG_URL=$2

    kpt pkg get --for-deployment "${PKG_URL}"
    kpt fn render "${PKG_NAME}"
    case "${PKG_NAME}" in
        "network-config")
            yq -i '.metadata.labels = {"pod-security.kubernetes.io/enforce": "privileged", "pod-security.kubernetes.io/enforce-version": "latest"}' "${PKG_NAME}/namespace.yaml"
            ;;
        "resource-backend")
            yq -i '.metadata.labels = {"pod-security.kubernetes.io/enforce": "privileged", "pod-security.kubernetes.io/enforce-version": "latest"}' "${PKG_NAME}/namespace.yaml"
            ;;
        "configsync")
            yq -i 'select(.kind == "Namespace").metadata.labels = {"pod-security.kubernetes.io/enforce": "privileged", "pod-security.kubernetes.io/enforce-version": "latest"}' "${PKG_NAME}/config-management-operator.yaml"
            # configure http proxy -> TODO: understand if this is required
            yq -i 'select(.kind == "Deployment" and .metadata.name == "config-management-operator").spec.template.spec.containers[0].env = load("../" + strenv(PROXY_CONF)).env' "${PKG_NAME}/config-management-operator.yaml"
            ;;
        "porch")
            yq -i '.metadata.labels = {"pod-security.kubernetes.io/enforce": "privileged", "pod-security.kubernetes.io/enforce-version": "latest"}' "${PKG_NAME}/1-namespace.yaml"
            # configure http proxy
            yq -i 'select(.kind == "Deployment" and .metadata.name == "porch-server").spec.template.spec.containers[0].env += load("../" + strenv(PROXY_CONF)).env' "${PKG_NAME}/3-porch-server.yaml"
            ;;
        "nephio-operator")
            if [[ "${STANDALONE_CLUSTER}" != "true" ]]; then
                yq -i '.metadata.labels = {"pod-security.kubernetes.io/enforce": "privileged", "pod-security.kubernetes.io/enforce-version": "latest"}' "${PKG_NAME}/namespace.yaml"
                # configure gitea URL and credentials
                for file in "${PKG_NAME}/app/controller/deployment-controller.yaml" "${PKG_NAME}/app/controller/deployment-token-controller.yaml"; do
                    yq -i '(.spec.template.spec.containers[1].env[] | select(.name == "GIT_URL").value) = strenv(GITEA_URL)' "${file}"
                    yq -i '.spec.template.spec.containers[1].env += {"name": "GIT_SECRET_NAME", "value": "gitea-admin"}' "${file}"
                done
            fi
            ;;
        "webui")
            yq -i '.metadata.labels = {"pod-security.kubernetes.io/enforce": "privileged", "pod-security.kubernetes.io/enforce-version": "latest"}' "${PKG_NAME}/0-namespace.yaml"
            if [[ "${STANDALONE_CLUSTER}" != "true" ]]; then
                # customize webui Service
                yq -i '.metadata.annotations["metallb.universe.tf/loadBalancerIPs"] = strenv(SYLVA_MGMT_VIP)' "${PKG_NAME}/service.yaml"
            fi
            ;;
    esac
    if [[ ${ONLY_GET_PKGS} != "true" ]]; then
        kpt live init "${PKG_NAME}"
        kpt live apply "${PKG_NAME}" --reconcile-timeout 15m --output=table
    fi
}

if [ ! -d "${NEPHIO_DIR}" ]; then
    mkdir "${NEPHIO_DIR}"
fi

if [[ ${STANDALONE_CLUSTER} == "true" ]]; then
    ./create-kind-cluster.sh
fi

pushd "${NEPHIO_DIR}"

while read -r line; do
    IFS=" "
    read -a columns <<< "${line}"
    install_kpt_package "${columns[0]}" "${columns[1]}"
done < "../${NEPHIO_KPT_PACKAGES}"

popd
