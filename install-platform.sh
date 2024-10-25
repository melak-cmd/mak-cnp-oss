#!/bin/bash
set -euo pipefail

# Color definitions
GREEN='\033[0;32m'
NC='\033[0m'

# Dump all kubrix variables
env | grep KUBRIX

# Get the hostname of the local machine and convert it to lowercase
CLUSTER_NAME="$(hostname | tr '[:upper:]' '[:lower:]')"

# k3d cluster delete $CLUSTER_NAME || true

if [ "${KUBRIX_CREATE_K3D_CLUSTER}" = "true" ] ; then
  if ! k3d cluster list | grep -q "$CLUSTER_NAME"; then
    # Set DNS fix if needed
    export K3D_FIX_DNS=1

    # Create the K3D cluster
    k3d cluster create "$CLUSTER_NAME" \
      -p "80:80@loadbalancer" \
      -p "443:443@loadbalancer" \
      --k3s-arg '--cluster-init@server:0' \
      --k3s-arg '--etcd-expose-metrics=true@server:0' \
      --agents 2 \
      --wait
    sleep 5
  else
    echo "Cluster $CLUSTER_NAME already exists."
  fi
fi

# Check for pending pods in kube-system namespace
echo -e "${GREEN}Checking for pending pods in the kube-system namespace...${NC}"

while true; do
  PODS=$(kubectl get pods --namespace kube-system --field-selector=status.phase=Pending -o wide)
  
  if [[ -z "$PODS" || "$PODS" == *"No resources found"* ]]; then
    echo "No pending pods found - cluster is ready."
    break
  else
    echo "Waiting for pods to be ready:"
    echo "$PODS"
  fi
  sleep 5
done

# if [[ "${KUBRIX_TARGET_TYPE}" =~ ^KIND.* ]] ; then
#   NAMESPACES="traefik backstage kargo grafana argocd keycloak komoplane kubecost falco minio velero velero-ui vault"
#   for namespace in $NAMESPACES; do
#     mkcert -cert-file ${namespace}-cert.pem -key-file ${namespace}-key.pem ${namespace}-127-0-0-1.nip.io 
#     # Using kubectl create instead of apply to avoid last-applied annotation
#     kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
#     # # kargo needs a special secret name according to its helm chart
#     if [ "${namespace}" = "kargo" ]; then
#       kubectl delete secret kargo-api-ingress-cert -n ${namespace} --ignore-not-found=true
#       kubectl create secret tls kargo-api-ingress-cert -n ${namespace} --cert=${namespace}-cert.pem --key=${namespace}-key.pem 
#     else
#       kubectl delete secret ${namespace}-server-tls -n ${namespace} --ignore-not-found=true
#       kubectl create secret tls ${namespace}-server-tls -n ${namespace} --cert=${namespace}-cert.pem --key=${namespace}-key.pem
#     fi
#     rm ${namespace}-cert.pem ${namespace}-key.pem
#   done
# fi

# helm template sx-argocd argo-cd \
#   --repo https://argoproj.github.io/argo-helm \
#   --namespace argocd \
#   --set configs.cm.application.resourceTrackingMethod=annotation \
#   -f bootstrap-argocd-values.yaml \
#   | kubectl apply -f - 

# # Check for pending pods in kube-system namespace
# echo -e "${GREEN}Checking for pending pods in the argocd namespace...${NC}"

# while true; do
#   PODS=$(kubectl get pods --namespace argocd --field-selector=status.phase=Pending -o wide)
  
#   if [[ -z "$PODS" || "$PODS" == *"No resources found"* ]]; then
#     echo "No pending pods found - cluster is ready."
#     break
#   else
#     echo "Waiting for pods to be ready:"
#     echo "$PODS"
#   fi
#   sleep 5
# done
  
# sleep 10

export ARGOCD_HOSTNAME=$(kubectl get ingress -o jsonpath='{.items[*].spec.rules[*].host}' -n argocd)
INITIAL_ARGOCD_PASSWORD=$( kubectl get secret -n argocd argocd-initial-admin-secret -o=jsonpath={'.data.password'} | base64 -d )
argocd login ${ARGOCD_HOSTNAME} --grpc-web --insecure --username admin --password ${INITIAL_ARGOCD_PASSWORD}
argocd repo add ${KUBRIX_REPO} --username ${KUBRIX_REPO_USERNAME} --password ${KUBRIX_REPO_PASSWORD}

KUBRIX_REPO_BRANCH_SED=$( echo ${KUBRIX_REPO_BRANCH} | sed 's/\//\\\//g' )
KUBRIX_REPO_SED=$( echo ${KUBRIX_REPO} | sed 's/\//\\\//g' )

# bootstrap-app
cat bootstrap-app-$(echo ${KUBRIX_TARGET_TYPE} | awk '{print tolower($0)}').yaml | sed "s/targetRevision:.*/targetRevision: ${KUBRIX_REPO_BRANCH_SED}/g" | sed "s/repoURL:.*/repoURL: ${KUBRIX_REPO_SED}/g" | kubectl apply -n argocd -f -
