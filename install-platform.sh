#!/bin/bash

# set -x  # Enable debugging, printing each command before execution.

# Define color codes
RED='\033[0;31m'    # Red
GREEN='\033[0;32m'  # Green
YELLOW='\033[0;33m' # Yellow
NC='\033[0m'        # No Color

# Get the hostname of the local machine and convert it to lowercase
CLUSTER_NAME="$(hostname | tr '[:upper:]' '[:lower:]')"

# Check if a cluster with the same name already exists
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo -e "${YELLOW}A cluster with the name '$CLUSTER_NAME' already exists. Skipping creation.${NC}"
else
  if [ "${CREATE_K3D_CLUSTER}" == true ]; then
    # Set this to avoid DNS issues
    export K3D_FIX_DNS=1
    
    # Create a K3D cluster
    echo -e "${GREEN}Creating cluster '$CLUSTER_NAME'...${NC}"
    k3d cluster create "$CLUSTER_NAME" \
      -p "80:80@loadbalancer" \
      -p "443:443@loadbalancer" \
      --k3s-arg '--cluster-init@server:0' \
      --k3s-arg '--etcd-expose-metrics=true@server:0' \
      --agents 2 \
      --wait
  fi
fi

# Wait for the kube-dns pod to be ready
echo -e "${GREEN}Waiting for kube-dns pod to be ready...${NC}"
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=k8s-app=kube-dns \
  --timeout=90s

# Install ArgoCD using Helm chart
echo -e "${GREEN}Installing ArgoCD with Helm chart...${NC}"
helm install mak-argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version 7.1.3 \
  --namespace argocd \
  --create-namespace \
  --set configs.cm.application.resourceTrackingMethod=annotation \
  -f https://raw.githubusercontent.com/${CURRENT_REPOSITORY}/${CURRENT_BRANCH}/bootstrap-argocd-values.yaml \
  --wait

# Prepare variables for sed replacements
CURRENT_BRANCH_SED=$( echo ${CURRENT_BRANCH} | sed 's/\//\\\//g' )
CURRENT_REPOSITORY_SED=$( echo ${CURRENT_REPOSITORY} | sed 's/\//\\\//g' )

# Bootstrap application
echo -e "${GREEN}Bootstrapping application...${NC}"
curl -L https://raw.githubusercontent.com/${CURRENT_REPOSITORY}/${CURRENT_BRANCH}/bootstrap-app-$(echo ${TARGET_TYPE} | awk '{print tolower($0)}').yaml | \
sed "s/targetRevision: main/targetRevision: ${CURRENT_BRANCH_SED}/g" | \
sed "s/melak-cmd\/mak-cnp-oss/${CURRENT_REPOSITORY_SED}/g" | \
kubectl apply -n argocd -f -

# Create app list
URL=https://raw.githubusercontent.com/${CURRENT_REPOSITORY}/${CURRENT_BRANCH}/platform-apps/target-chart/values-$(echo ${TARGET_TYPE} | awk '{print tolower($0)}').yaml

# Optional: You can use this URL for further processing if needed
echo -e "${GREEN}App list URL: ${URL}${NC}"
exit
# Check if the TARGET_TYPE matches
if [[ "${TARGET_TYPE}" =~ ^KIND.* ]]; then
  # Create mkcert certs in all namespaces with ingress
  for namespace in backstage kargo grafana argocd keycloak komoplane kubecost falco minio velero velero-ui vault; do
    kubectl create namespace "${namespace}"
    mkcert -cert-file "${namespace}-cert.pem" -key-file "${namespace}-key.pem" "${namespace}-127-0-0-1.nip.io"
    
    # Special secret name for kargo
    if [ "${namespace}" = "kargo" ]; then
      kubectl create secret tls kargo-api-ingress-cert -n "${namespace}" --cert="${namespace}-cert.pem" --key="${namespace}-key.pem"
    else
      kubectl create secret tls "${namespace}-server-tls" -n "${namespace}" --cert="${namespace}-cert.pem" --key="${namespace}-key.pem"
    fi

    # Additional secret for minio
    if [ "${namespace}" = "minio" ]; then
      mkcert -cert-file "${namespace}-console-cert.pem" -key-file "${namespace}-console-key.pem" minio-console-127-0-0-1.nip.io
      kubectl create secret tls minio-console-tls -n "${namespace}" --cert="${namespace}-console-cert.pem" --key="${namespace}-console-key.pem"
      rm "${namespace}-console-cert.pem" "${namespace}-console-key.pem"
    fi

    rm "${namespace}-cert.pem" "${namespace}-key.pem"
  done

  # Do not install kind nginx-controller and metrics-server on k3d cluster
  if [[ ${CREATE_K3D_CLUSTER} != true ]]; then
    # Install nginx ingress-controller
    echo -e "${GREEN}Installing NGINX ingress-controller...${NC}"
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=90s

    # Install metrics-server
    echo -e "${GREEN}Installing metrics-server...${NC}"
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
    helm repo update
    helm upgrade --install --set args={--kubelet-insecure-tls} metrics-server metrics-server/metrics-server --namespace kube-system
  fi
fi