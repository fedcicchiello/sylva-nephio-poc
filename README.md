# Sylva Nephio interworking
This repository contains the scripts and the documentation of the PoC showing the Sylva-Nephio interworking.

Sylva and Nephio management components are two distinct logical entities so they can in general be located in different clusters.

For the PoC purposes they will coexist on the same Kubernetes cluster created with Sylva on Docker.

It will be enriched by the installation and configuration of nephio operators.

The work will demostrate how Sylva can support effectively Nephio and collaborate in order to provide the workload cluster needed to deploy the free5GC core.

Sylva CRDs will be used to provide the effective interface to the KaaS service requested by Nephio.

## Projects versions
- Sylva v1.0
    - SylvaUnitsOperator commit b98ccdb15948114a9bcc5308bcc03576c829d52f
- Nephio R2

## Pre-requisites
All the resources will be deployed on Docker, so everything runs on a single server/VM.

If you opt for a VM ensure it has at leat 16 vCPUs and 32 GB of RAM.

The suggested OS is ubuntu 22.04 with kernel version >= 5.4

Ensure you have the following packages installed:
- git
- kind
- docker
- kubectl
- kpt
- containerlab
- yq


In order to run the free5GC core you will need the [gtp5g](https://github.com/free5gc/gtp5g) module. You can install it with:
```bash
git clone https://github.com/free5gc/gtp5g.git && cd gtp5g
make clean && make
make install
```

## Steps
The step zero is the bootstrap of a Sylva v1 management cluster on Docker infrastructure.

The first step is the installation of the Nephio management controllers and CRDs on the Sylva management cluster.

The second step is the deployment through the Sylva Units Operator of three workload clusters on Docker: one will play the regional role, the other two the edge role.

The third and last step is the [deployment of the free5GC](https://github.com/nephio-project/docs/blob/v2.0.0/content/en/docs/guides/user-guides/exercise-1-free5gc.md) on the workload clusters.

## Step 0: bootstrapping the Sylva management cluster

### Example values
```bash
---
units:
  # Disabling some units for lightweight deployment testing
  cluster-creator-policy:
    enabled: false
  monitoring:
    enabled: false
  keycloak:
    enabled: false
  flux-webui:
    enabled: false
  capi-rancher-import:
    enabled: false
  kyverno:
    enabled: false
  shared-workload-clusters-settings:
    enabled: false
  harbor:
    enabled: false
  sylva-units-operator:
    kustomization_spec:
      images:
        - name: controller
          newName: fedcicchiello/sylva-units-operator
          newTag: b98ccdb15948114a9bcc5308bcc03576c829d52f
  workload-cluster-operator:
    enabled: false
  rancher-init:
    enabled: false
  rancher:
    enabled: false
  synchronize-secrets:
    enabled: false
  flux-webui:
    enabled: false

cluster:
  k8s_version: v1.27.3
  capi_providers:
    infra_provider: capd
    bootstrap_provider: cabpk

  # CAPD only supports 1 CP machine
  control_plane_replicas: 1

  cluster_services_cidrs:
    - 10.128.0.0/12
  
  cluster_pods_cidrs:
    - 192.168.0.0/16

capd_docker_host: unix:///var/run/docker.sock

cluster_virtual_ip: 172.18.0.200

proxies:
  http_proxy: "your http_proxy"
  https_proxy: "your https_proxy"
  no_proxy: "your no_proxy"

ntp:
  enabled: false
```

## Step 1: Nephio installation
Ensure your kubeconfig is set to point to the Sylva management cluster, then configure `http-proxy.yaml` with your env configuration.
Then install the Nephio management components with:
```bash
./install-nephio.sh
```

## Step 2: Workload clusters deployment
Make sure to have the management cluster kubeconfig at the path `$HOME/.kube/management.yaml`.
Ensure to configure your proxy configuration in `deploy-workload-clusters.sh`.
Then deploy the three workload clusters (a regional and two edge sites) with:
```bash
./deploy-workload-clusters.sh
```

You will find the kubeconfigs of the clusters in `$HOME/.kube/<cluster name>.yaml`

The script will use the [sylva-workload-cluster](https://github.com/fedcicchiello/sylva-kpt-packages/tree/main/sylva-workload-cluster) to configure the `SylvaUnitsRelease` CRD through kpt along with some resources needed for the workload management with Nephio such as a git repository per cluster on gitea, the deployment of configsync, the installation of some CRDs required by Nephio and the configuration of rootsync that will allow each cluster to apply manifests from their repository.

### Sylva workload cluster kpt package
Sylva will be consumed by Nephio through the sylva-workload-cluster kpt package instead of the [nephio-workload-cluster](https://github.com/nephio-project/catalog/tree/main/infra/capi/nephio-workload-cluster) proposed in the Nephio user guide.

## Step 3: Free5GC deployment
Simply run 
```bash
./deploy-free5gc.sh
```
And enjoy the free5Gc deployment!

# Workaround
If you use CAPD with calico as CNI, you can't use Metallb in L2 mode since the broadcast traffic doesn't reach the pods

To work around that you can run a container on the kind network with the same IP as the `cluster_virtual_ip` and `kubectl port-forward` the gitea Service:
```bash
cp $HOME/.kube/management.yaml $HOME/.kube/proxy.yaml
sudo chmod 644 $HOME/.kube/proxy.yaml
docker run -d --rm --network kind --ip 172.18.0.200 --name kubectl -v $HOME/.kube/proxy.yaml:/.kube/config bitnami/kubectl:latest port-forward svc/gitea -n gitea 3000:3000 --address 172.18.0.200
```
