#!/bin/bash
set -e  # Exit on non-zero exit code from commands

echo "$(date): Running post-start.sh" >> ~/.status.log

# Docker can take a couple seconds to come up. Wait for it to be ready before
# proceeding with bootstrap. https://github.com/devcontainers/features/issues/977#issuecomment-2148230117
iterations=10
while ! docker ps &>/dev/null; do
  if [[ $iterations -eq 0 ]]; then
    echo "Timeout waiting for the Docker daemon to start."
    exit 1
  fi

  iterations=$((iterations - 1))
  echo 'Docker is not ready. Waiting 10 seconds and trying again.'
  sleep 10
done

# fix for https://github.com/kubernetes-sigs/kind/issues/2488
# but using the microsoft devcontainer docker-in-docker image should also work,
# but I didn't find it
if [[ $( docker network ls | grep kind ) ]] ; then
  echo "kind network already exists"
else
  docker network create -d=bridge --subnet=172.19.0.0/24 kind
fi

export REPO_BRANCH=$( git rev-parse --abbrev-ref HEAD )
export BOOTSTRAP_MAX_WAIT_TIME=1800

echo $REPO_BRANCH >> ~/.status.log

export REPO=$( git config --get remote.origin.url)

# install mkcert
if [ ! -x /usr/local/bin/mkcert ]; then
  curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
  chmod +x mkcert-v*-linux-amd64
  sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert
fi

# create kind cluster by ourselves
if [[ $( kind get clusters | grep devcontainer-cluster ) ]] ; then
  echo "kind cluster 'devcontainer-cluster' already exists"
  echo "wait 10 seconds for starting up ..."
  sleep 10
  echo "wait time over .."
  echo "export kubeconfig"
  kind export kubeconfig --name devcontainer-cluster
  echo "wait until KinD cluster is available"
  iterations=10
  while ! kubectl cluster-info &>/dev/null; do
    if [[ $iterations -eq 0 ]]; then
      echo "Timeout waiting for KinD cluster to start."
      exit 1
    fi
    iterations=$((iterations - 1))
    echo 'KinD cluster is not ready. Waiting 10 seconds and trying again.'
    sleep 10
  done
else
  kind create cluster --name devcontainer-cluster --config .devcontainer/kind-config.yaml
fi

# here we can add some NodePort objects if we want to open ports before the apps are installed

if [[ ${TARGET_TYPE} == "kind-delivery" ]] ; then
  kubectl create namespace kargo --dry-run=client -o yaml | kubectl apply -f - --server-side=true
  kubectl apply -f .devcontainer/kargo-nodeport.yaml

elif  [[ ${TARGET_TYPE} == "kind-observability" ]] ; then
  kubectl create namespace grafana --dry-run=client -o yaml | kubectl apply -f - --server-side=true
  kubectl apply -f .devcontainer/grafana-nodeport.yaml

elif  [[ ${TARGET_TYPE} == "kind-security" ]] ; then
  kubectl create namespace falco --dry-run=client -o yaml | kubectl apply -f - --server-side=true
  kubectl apply -f .devcontainer/falco-nodeport.yaml
fi

# always install ArgoCD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f .devcontainer/argocd-nodeport.yaml

kubectl create namespace cnp-install --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic cnp-install-secrets -n cnp-install \
  --from-literal TARGET_TYPE=${TARGET_TYPE} \
  --from-literal CLUSTER_TYPE=${CLUSTER_TYPE} \
  --from-literal BACKSTAGE_GITHUB_TOKEN=${BACKSTAGE_GITHUB_TOKEN} \
  --from-literal REPO_PASSWORD=${REPO_PASSWORD} \
  --from-literal REPO_USERNAME=${REPO_USERNAME} \
  --from-literal REPO_BRANCH=${REPO_BRANCH} \
  --from-literal REPO=${REPO} \
  --from-literal BOOTSTRAP_MAX_WAIT_TIME=${BOOTSTRAP_MAX_WAIT_TIME} \
  --from-literal INSTALLER=true \
  --dry-run=client -o yaml | kubectl apply -f -
bash .github/install-with-job.sh

echo "$(date): Finished post-start.sh" >> ~/.status.log

