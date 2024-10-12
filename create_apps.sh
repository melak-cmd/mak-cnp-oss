#!/bin/bash

# Function to generate and apply ArgoCD application specifications
generate_and_apply_spec() {
    local app_name="$1"
    local repo_url="$2"
    local helm_chart="$3"
    local revision="$4"
    local values_file="$5"
    local dest_namespace="$6"
    local sync_options="$7"

    argocd admin app generate-spec "$app_name" \
        --repo "$repo_url" \
        --helm-chart "$helm_chart" \
        --revision "$revision" \
        --values-literal-file "$values_file" \
        --dest-namespace "$dest_namespace" \
        --dest-server https://kubernetes.default.svc \
        --sync-policy auto \
        --self-heal \
        --auto-prune \
        $sync_options | kubectl -n "$dest_namespace" apply -f -
}

# Generate and apply specs for each application
generate_and_apply_spec "argocd" "https://argoproj.github.io/argo-helm" "argo-cd" "7.6.5" "argocd-values.yaml" "argocd" "--sync-option CreateNamespace=true"
# generate_and_apply_spec "crossplane" "https://charts.crossplane.io/stable" "crossplane" "1.17.1" "crossplane-values.yaml" "crossplane" "--sync-option CreateNamespace=true"
# generate_and_apply_spec "grafana" "https://grafana.github.io/helm-charts" "grafana" "8.5.2" "grafana-values.yaml" "grafana" "--sync-option CreateNamespace=true"

echo "All operations completed successfully."10