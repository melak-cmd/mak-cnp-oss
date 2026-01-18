#!/bin/bash
set -e

export CNP_REPO_BRANCH=$( git rev-parse --abbrev-ref HEAD )
export CNP_BOOTSTRAP_MAX_WAIT_TIME=1800

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

if [[ $( docker network ls | grep kind ) ]] ; then
  echo "kind network already exists"
else
  docker network create -d=bridge --subnet=172.19.0.0/24 kind
fi

echo $CNP_REPO_BRANCH