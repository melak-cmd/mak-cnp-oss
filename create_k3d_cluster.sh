#!/bin/bash

# Get the hostname of the local machine and convert it to lowercase
CLUSTER_NAME="$(hostname | tr '[:upper:]' '[:lower:]')"

# Define the infrastructure taint
TAINT_KEY="node-type"
TAINT_VALUE="infrastructure"
TAINT_EFFECT="NoSchedule"

# Create the K3D cluster with the specified infrastructure taint
echo "Creating K3D cluster '$CLUSTER_NAME' with taint '$TAINT_KEY=$TAINT_VALUE:$TAINT_EFFECT'..."
k3d cluster create "$CLUSTER_NAME" \
    -p "80:80@loadbalancer" \
    -p "443:443@loadbalancer" \
    --k3s-arg '--cluster-init@server:0' \
    --k3s-arg '--etcd-expose-metrics=true@server:0' \
    --k3s-arg "--kubelet-arg=--register-with-taints=${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}@agent:*" \
    --agents 2 \
    --wait

# Check if the cluster was created successfully
if [ $? -eq 0 ]; then
    echo "Cluster '$CLUSTER_NAME' created successfully."
else
    echo "Failed to create cluster '$CLUSTER_NAME'."
    exit 1
fi

# Define an array of namespaces to process
namespaces=("argocd" "grafana")

# Loop through each namespace
for namespace in "${namespaces[@]}"; do
    # Create the namespace if it doesn't already exist
    echo "Processing namespace '${namespace}'..."
    if kubectl get namespace "${namespace}" >/dev/null 2>&1; then
        echo "Namespace '${namespace}' already exists."
    else
        echo "Creating namespace '${namespace}'..."
        if kubectl create namespace "${namespace}"; then
            echo "Namespace '${namespace}' created successfully."
        else
            echo "Failed to create namespace '${namespace}'."
            exit 1
        fi
    fi

    # Define certificate file names and domain
    cert_file="${namespace}-cert.pem"
    key_file="${namespace}-key.pem"
    domain="${namespace}-127-0-0-1.nip.io"

    # Generate certificates
    echo "Generating certificates for '${domain}'..."
    if mkcert -cert-file "${cert_file}" -key-file "${key_file}" "${domain}"; then
        echo "Certificates generated successfully for '${domain}'."
    else
        echo "Failed to generate certificates for '${domain}'."
        exit 1
    fi

    # Create a TLS secret in the namespace
    echo "Creating TLS secret '${namespace}-server-tls'..."
    if kubectl create secret tls "${namespace}-server-tls" -n "${namespace}" \
        --cert="${cert_file}" --key="${key_file}"; then
        echo "TLS secret '${namespace}-server-tls' created successfully."
    else
        echo "Failed to create TLS secret '${namespace}-server-tls'."
        exit 1
    fi

    # Clean up the generated certificate files
    echo "Cleaning up certificate files for '${namespace}'..."
    rm -f "${cert_file}" "${key_file}"
    echo "Clean up completed for '${namespace}'."
done

kubectl wait --namespace kube-system   --for=condition=ready pod   --selector=k8s-app=kube-dns   --timeout=90s
  
helm template argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 7.6.5 --namespace argocd  \
| kubectl create -f -

kubectl wait --namespace argocd  --for=condition=ready pod   --selector=app.kubernetes.io/component=server   --timeout=90s

echo "All operations completed successfully."