#! /bin/bash

set -ex

export HTTP_PROXY="http://163.162.95.56:3128"
export HTTPS_PROXY="http://163.162.95.56:3128"
export NO_PROXY="tim.local,sylva,127.0.0.1,localhost,cattle-system.svc,192.168.0.0/16,10.0.0.0/8,163.162.0.0/16,tim.it,telecomitalia.it,cluster.local,local.,svc,163.162.196.17,100.64.0.0/10,172.18.0.0/16"
export SYLVA_CORE_BRANCH="fc/fix-capd"

SYLVA_WKLD_CLUSTER_PKG="https://github.com/fedcicchiello/sylva-kpt-packages.git/sylva-workload-cluster@v0.0.2"

export KUBECONFIG="$HOME/.kube/management.yaml"

for CLUSTER in regional edge01 edge02; do
    export SITE_TYPE=""
    case "${CLUSTER}" in
      regional)
        SITE_TYPE="regional"
        ;;
      *)
        SITE_TYPE="edge"
        ;;
    esac

    # deploy the cluster with Sylva
    kpt pkg get --for-deployment "${SYLVA_WKLD_CLUSTER_PKG}" "${CLUSTER}"
    CLUSTER="${CLUSTER}" yq -i '.namespace = strenv(CLUSTER)' "${CLUSTER}/set-namespace.yaml"
    CLUSTER="${CLUSTER}" yq -i '.data.clusterName = strenv(CLUSTER)' "${CLUSTER}/apply-setters.yaml"
    yq -i '.data.sylvaCoreBranch = strenv(SYLVA_CORE_BRANCH)' "${CLUSTER}/apply-setters.yaml"
    yq -i '.data.httpProxy = strenv(HTTP_PROXY)' "${CLUSTER}/apply-setters.yaml"
    yq -i '.data.httpsProxy = strenv(HTTPS_PROXY)' "${CLUSTER}/apply-setters.yaml"
    yq -i '.data.noProxy = strenv(NO_PROXY)' "${CLUSTER}/apply-setters.yaml"
    kpt fn render "${CLUSTER}"
    kpt fn eval --image gcr.io/kpt-fn/set-labels:v0.2.0 "${CLUSTER}" -- "nephio.org/site-type=${SITE_TYPE}" "nephio.org/region=us-west1"
    kpt live init "${CLUSTER}"
    kpt live apply --reconcile-timeout 15m --output=table "${CLUSTER}"

    # add annotations + labels to CAPI cluster
    # TODO enhance sylvaunitsoperator to propagate labels and annotations to rendered resources
    kubectl annotate cluster "${CLUSTER}" -n "${CLUSTER}" nephio.org/cluster-name=${CLUSTER}
    kubectl label cluster "${CLUSTER}" -n "${CLUSTER}" nephio.org/site-type=${SITE_TYPE}
    kubectl label cluster "${CLUSTER}" -n "${CLUSTER}" nephio.org/region=us-west1

    clusterctl get kubeconfig "${CLUSTER}" -n "${CLUSTER}" > "$HOME/.kube/${CLUSTER}.yaml"
done

echo "Run the command below to setup your kubectl"
echo "export KUBECONFIG=${HOME}/.kube/management.yaml:${HOME}/.kube/regional.yaml:${HOME}/.kube/edge01.yaml:${HOME}/.kube/edge02.yaml"
