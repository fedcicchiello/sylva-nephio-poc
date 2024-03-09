# sylva-workload-cluster

## Description
Manage the lifecycle of a Sylva workload cluster.

For the moment the only configuration supported is `kubeadm-capd`.

Note: to be used only on Sylva management clusters.

## Usage

### Fetch the package
`kpt pkg get REPO_URI[.git]/PKG_PATH[@VERSION] sylva-workload-cluster`
Details: https://kpt.dev/reference/cli/pkg/get/

### View package content
`kpt pkg tree sylva-workload-cluster`
Details: https://kpt.dev/reference/cli/pkg/tree/

### Apply the package
```
kpt live init sylva-workload-cluster
kpt live apply sylva-workload-cluster --reconcile-timeout=2m --output=table
```
Details: https://kpt.dev/reference/cli/live/
