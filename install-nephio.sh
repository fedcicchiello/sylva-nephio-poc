#! /bin/bash

set -ex

DEMO_MODE="false" # DEMO_MODE is true if deploying Nephio into a sandbox, e.g. a VM, otherwise the target is a Sylva management cluster
NEPHIO_DIR="./nephio-install"
NEPHIO_KPT_PACKAGES="./nephio-kpt-packages.txt"
export PROXY_CONF="http-proxy.yaml"
ONLY_GET_PKGS="false" # set ONLY_GET_PKGS to true if you just want to get kpt packages and render them locally without applying anything
SYLVA_MGMT_VIP="163.162.114.133"
export GITEA_URL="http://${SYLVA_MGMT_VIP}:3000"
export METALLB_SHARING_KEY="cluster-external-ip"

if [[ "${DEMO_MODE}" == true ]]; then
    NEPHIO_KPT_PACKAGES="./nephio-kpt-packages-demo.txt"
fi

install_kpt_package() {
    if [[ $# != 2 ]]; then
        echo "Usage: $0 <package name> <package location>"
        exit 1
    fi

    PKG_NAME=$1
    PKG_URL=$2

    kpt pkg get --for-deployment "${PKG_URL}" "{PKG_NAME}"
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
            if [[ "${DEMO_MODE}" != "true" ]]; then
                yq -i '.metadata.labels = {"pod-security.kubernetes.io/enforce": "privileged", "pod-security.kubernetes.io/enforce-version": "latest"}' "${PKG_NAME}/namespace.yaml"
                # configure gitea URL and credentials
                for file in "${PKG_NAME}/app/controller/deployment-controller.yaml" "${PKG_NAME}/app/controller/deployment-token-controller.yaml"; do
                    yq -i '(.spec.template.spec.containers[1].env[] | select(.name == "GIT_URL").value) = strenv(GITEA_URL)' "${file}"
                    yq -i '.spec.template.spec.containers[1].env += {"name": "GIT_SECRET_NAME", "value": "gitea-admin"}' "${file}"
                done
            fi
            ;;
        "mgmt"|"mgmt-staging")
            if [[ "${DEMO_MODE}" != "true" ]]; then
                yq -i '.spec.git.repo = strenv(GITEA_URL) + "/nephio/" + strenv(PKG_NAME) + ".git"' "${PKG_NAME}/repo-porch.yaml"
            fi
            ;;
        "webui")
            yq -i '.metadata.labels = {"pod-security.kubernetes.io/enforce": "privileged", "pod-security.kubernetes.io/enforce-version": "latest"}' "${PKG_NAME}/0-namespace.yaml"
            if [[ "${DEMO_MODE}" != "true" ]]; then
                # customize webui Service
                yq -i '.metadata.annotations["metallb.universe.tf/loadBalancerIPs"] = strenv(SYLVA_MGMT_VIP)' "${PKG_NAME}/service.yaml"
                yq -i '.metadata.annotations["metallb.universe.tf/allow-shared-ip"] = strenv(METALLB_SHARING_KEY)' "${PKG_NAME}/service.yaml"
            fi
            ;;
        "gitea")
            yq -i '.metadata.annotations["metallb.universe.tf/loadBalancerIPs"] = strenv(SYLVA_MGMT_VIP)' "${PKG_NAME}/service-gitea.yaml"
            yq -i '.metadata.annotations["metallb.universe.tf/allow-shared-ip"] = strenv(METALLB_SHARING_KEY)' "${PKG_NAME}/service-gitea.yaml"
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

if [[ ${DEMO_MODE} == "true" ]]; then
    ./create-kind-cluster.sh
fi

pushd "${NEPHIO_DIR}"

while read -r line; do
    IFS=" "
    read -a columns <<< "${line}"
    install_kpt_package "${columns[0]}" "${columns[1]}"
done < "../${NEPHIO_KPT_PACKAGES}"

popd
