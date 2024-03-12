#! /bin/bash

set -ex

HTTP_PROXY="http://163.162.95.56:3128"
HTTPS_PROXY="http://163.162.95.56:3128"
NO_PROXY="tim.local,sylva,127.0.0.1,localhost,cattle-system.svc,192.168.0.0/16,10.0.0.0/8,163.162.0.0/16,tim.it,telecomitalia.it,cluster.local,local.,svc,163.162.196.17,100.64.0.0/10,172.18.0.0/16"
export PROXY_CONF="http-proxy.yaml"
export GITEA_URL="http://172.18.0.100:3000"
export ACCESSIBLE_GITEA_URL="http://163.162.196.17:3000"

REPO_PKG="https://github.com/nephio-project/catalog.git/distros/sandbox/repository@v2.0.0"
VLANINDEX_PKG="https://github.com/nephio-project/catalog.git/infra/capi/vlanindex@v2.0.0"
WORKLOAD_CRDS_PKG="https://github.com/nephio-project/catalog.git/nephio/core/workload-crds@v2.0.0"
CONFIGSYNC_PKG="https://github.com/nephio-project/catalog.git/nephio/core/configsync@v2.0.0"
ROOTSYNC_PKG="https://github.com/nephio-project/catalog.git/nephio/optional/rootsync@v2.0.0"

for CLUSTER in edge01; do
    export KUBECONFIG="$HOME/.kube/management.yaml"

    mkdir -p "${CLUSTER}/mgmt" && pushd "${CLUSTER}"
    pushd mgmt

    # deploy the cluster with Sylva
    # kpt pkg get --for-deployment https://scm.code.telecomitalia.it/11625365/sylva-kpt-packages.git/sylva-workload-cluster@v1.0.0 "${CLUSTER}-sylva"
    # kpt fn eval "${CLUSTER}-sylva" -i gcr.io/kpt-fn/apply-setters:v0.1.1 -- clusterName="${CLUSTER}" sylvaCoreBranch="fc/fix-capd" httpProxy="${HTTP_PROXY}" httpsProxy="${HTTPS_PROXY}" noProxy="${NO_PROXY}"
    # kpt live init "${CLUSTER}-sylva"
    # kpt live apply --reconcile-timeout 15m --output=table "${CLUSTER}-sylva"

    mkdir -p repo && mkdir -p vlanindex

    # create the cluster's repo
    kpt pkg get --for-deployment "${REPO_PKG}" "repo/${CLUSTER}"
    kpt fn render "repo/${CLUSTER}"
    CLUSTER="${CLUSTER}" yq -i '.spec.git.repo = strenv(GITEA_URL) + "/nephio/" + strenv(CLUSTER) + ".git"' "repo/${CLUSTER}/repo-porch.yaml"
    kpt live init "repo/${CLUSTER}"
    kpt live apply --reconcile-timeout 15m --output=table "repo/${CLUSTER}"

    # get token to access repo
    REPO_TOKEN=$(kubectl get secret "${CLUSTER}-access-token-configsync" -oyaml | yq .data.token | base64 -d)

    # create the cluster's vlanindex
    kpt pkg get --for-deployment "${VLANINDEX_PKG}" "vlanindex/${CLUSTER}"
    kpt fn render "vlanindex/${CLUSTER}"
    kpt live init "vlanindex/${CLUSTER}"
    kpt live apply --reconcile-timeout 15m --output=table "vlanindex/${CLUSTER}"

    popd

    clusterctl get kubeconfig "${CLUSTER}" -n "${CLUSTER}" > "$HOME/.kube/${CLUSTER}.yaml"
    export KUBECONFIG="$HOME/.kube/${CLUSTER}.yaml"

    # deploy workload-crds on the workload cluster
    kpt pkg get --for-deployment "${WORKLOAD_CRDS_PKG}"
    kpt fn render "workload-crds"
    kpt live init "workload-crds"
    kpt live apply --reconcile-timeout 15m --output=table "workload-crds"

    # install configsync on the workload cluster
    kpt pkg get --for-deployment "${CONFIGSYNC_PKG}"
    kpt fn render "configsync"
    yq -i 'select(.kind == "Deployment" and .metadata.name == "config-management-operator").spec.template.spec.containers[0].env = load("../" + strenv(PROXY_CONF)).env' "configsync/config-management-operator.yaml"
    kpt live init "configsync"
    kpt live apply --reconcile-timeout 15m --output=table "configsync"

    # create the Secret with the token to access the cluster's repo
    kubectl -n config-management-system create secret generic "${CLUSTER}-access-token-configsync" --from-literal username=nephio --from-literal password="${REPO_TOKEN}" --from-literal token="${REPO_TOKEN}"

    mkdir rootsync

    # configure the cluster to sync with its repo
    kpt pkg get --for-deployment "${ROOTSYNC_PKG}" "rootsync/${CLUSTER}"
    kpt fn render "rootsync/${CLUSTER}"
    CLUSTER="${CLUSTER}" yq -i '.spec.git.repo = strenv(ACCESSIBLE_GITEA_URL) + "/nephio/" + strenv(CLUSTER) + ".git"' "rootsync/${CLUSTER}/rootsync.yaml"
    kpt live init "rootsync/${CLUSTER}"
    kpt live apply --reconcile-timeout 15m --output=table "rootsync/${CLUSTER}"

    popd
done

# TODOs below:

# launch the scripts to configure cluster inter-networking
# export E2EDIR=${E2EDIR:-$HOME/test-infra/e2e}
# export LIBDIR=${LIBDIR:-$HOME/test-infra/e2e/lib}
# export TESTDIR=${TESTDIR:-$HOME/test-infra/e2e/tests/free5gc}
# https://github.com/nephio-project/test-infra/blob/v2.0.0/e2e/provision/hacks/inter-connect_workers.sh

# ./test-infra/e2e/provision/hacks/vlan-interfaces.sh

# kubectl apply -f test-infra/e2e/tests/free5gc/002-network.yaml

# kubectl apply -f test-infra/e2e/tests/free5gc/002-secret.yaml

# ./test-infra/e2e/provision/hacks/network-topo.sh

# after the script: deploy free5GC Operator
# kubectl apply -f test-infra/e2e/tests/free5gc/004-free5gc-operator.yaml

# kubectl apply -f test-infra/e2e/tests/free5gc/005-edge-free5gc-upf.yaml
# kubectl apply -f test-infra/e2e/tests/free5gc/006-regional-free5gc-amf.yaml
# kubectl apply -f test-infra/e2e/tests/free5gc/006-regional-free5gc-smf.yaml
