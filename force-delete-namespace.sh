#! /bin/bash

if [[ "$#" != 1 ]]; then
    echo "Usage: $0 <Namespace name>"
    exit 1
fi

NAMESPACE=$1

kubectl proxy &
kubectl get ns "${NAMESPACE}" | jq '.spec = {"finalizers": []}' > temp.json
curl -k -H "Content-Type: application/json" -X PUT --data-binary @temp.json "127.0.0.1:8001/api/v1/namespaces/${NAMESPACE}/finalize"
