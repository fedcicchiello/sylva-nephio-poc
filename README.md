# Sylva Nephio interworking
This repository contains all the development to demonstrate Sylva-Nephio interworking.

Sylva and Nephio management components are two distinct logical entities so they can in general be located in different clusters.

For the demo purposes they will coexist on the same Kubernetes cluster created with Sylva on vSphere.

It will be enriched by the installation and configuration of nephio operators.

The work will demostrate how Sylva can support effectively Nephio and collaborate in order to provide the workload cluster needed to deploy the free5GC core.

Sylva CRDs will be used to provide the effective interface to the KaaS service requested by Nephio.

## Projects versions
- Sylva v1.0
    - SylvaUnitsOperator commit 1cf45df7a39c1ab000e97ce01d6d290195d117d9
    - WorkloadClusterOperator commit b253fe19c706c78b3fa26df79e414b267eaed093
- Nephio R2

## Steps
The first step is to install Nephio on a VM in order to practice with kpt.

The second step is to install Nephio management controllers and CRDs on the Sylva management cluster.

The third and last step is to [deploy the free5GC](https://github.com/nephio-project/docs/blob/v2.0.0/content/en/docs/guides/user-guides/exercise-1-free5gc.md) on workload clusters provided by Sylva with all the requirements satisfied.

A forth optional step would be the deployment of the [OAI core](https://github.com/nephio-project/docs/blob/v2.0.0/content/en/docs/guides/user-guides/exercise-2-oai.md).

### Step 1: Nephio demo

#### Nephio (demo env based on docker) pre-requisites
- OS: ubuntu 22.04 with kernel version >= 5.4
- VM min specs: 16 vCPUs, 32 GB of RAM
- git
- kind
- docker
- ca-certificates
- kubectl
- kpt

#### Nephio demo env instructions
Follow the [install-on-single-vm guide](https://github.com/nephio-project/docs/blob/v2.0.0/content/en/docs/guides/install-guides/install-on-single-vm.md) from Nephio.

An overview of the components installed is available at [explore-sandbox](https://github.com/nephio-project/docs/blob/v2.0.0/content/en/docs/guides/install-guides/explore-sandbox.md).

#### Customizations
The only customization needed to have a working setup is the injection of http proxy configuration inside `porch` and `configsync` made by [install-nephio.sh](./install-nephio.sh).

#### Workload cluster requirements
[gtp5g](https://github.com/free5gc/gtp5g), installation instructions:
```bash
git clone https://github.com/free5gc/gtp5g.git && cd gtp5g
make clean && make
make install
# enable QoS
echo 1 >  /proc/gtp5g/qos
```

### Step 2: Building the Sylva/Nephio management cluster

#### Sylva workload cluster kpt package
Sylva will be consumed by Nephio through a kpt package that will substitute the ones configuring CAPI-CAPD resources on the upstream docs.

The idea is to develop a kpt package to manage a `SylvaUnitsRelease` composed of many layers of `valuesFrom` like the one shown below.

Sylva CRDs example:
```yaml
apiVersion: 
kind: SylvaUnitsRelease/SylvaUnitsReleaseTemplate
metadata:
    name: example
    namespace: test
spec:
    clusterType: workload
    sylvaUnitsSource:
        type: git
        url: https://gitlab.com/sylva-projects/sylva-core.git/charts/sylva-units
        tag: 1.0.0
    valuesFrom:
        - layerName: networkAllocation
          type: ConfigMap
          name: workload-cluster-networking
          valuesKey: values
        - layerName: serverAllocation
          type: Secret
          name: workload-cluster-bmh
          valuesKey: values
        - layerName: flavor
          type: ConfigMap
          name: workload-cluster-flavor
          valuesKey: values
        - layerName: base
          type: ConfigMap
          name: workload-cluster-base
          valuesKey: values
    values:
    interval: 30m
    suspend: false
```

In order to properly fill dynamic configurations such as network allocation or servers allocations a bunch of functions will be provided to abstract the underlying complex resources from a simple set of user provided parameters.

# Values for testing the sylva kpt package
`capd_no_proxy="tim.local,sylva,127.0.0.1,localhost,cattle-system.svc,192.168.0.0/16,10.0.0.0/8,163.162.0.0/16,tim.it,telecomitalia.it,cluster.local,local.,svc,163.162.196.17,100.64.0.0/10,172.18.0.0/16`
`kpt fn eval -i gcr.io/kpt-fn/apply-setters:v0.1.1 -- clusterName=regional httpProxy=${http_proxy} httpsProxy=${https_proxy} noProxy=${capd_no_proxy} sylvaCoreBranch="fc/fix-capd"`
