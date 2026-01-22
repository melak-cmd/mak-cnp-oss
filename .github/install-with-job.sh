#!/usr/bin/env bash
set -euo pipefail

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# source "${SCRIPT_DIR}/../scripts/utils.sh"

# Config (from the manifest)
MANIFEST_URL="https://raw.githubusercontent.com/${REPO}/refs/heads/${UPSTREAM_BRANCH:=$REPO_BRANCH}/install-manifests.yaml"
NAMESPACE="cnp-install"
JOB_NAME="cnp-install-job"

echo "Applying installation manifest from ${MANIFEST_URL}..."

curl -H "Authorization: token ${REPO_PASSWORD}" \
  -H 'Accept: application/vnd.github.v3.raw' \
  -O \
  -L ${MANIFEST_URL}