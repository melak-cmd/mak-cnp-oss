#!/bin/bash

argocd admin app generate-spec argocd  --repo https://argoproj.github.io/argo-helm --helm-chart argo-cd --revision 7.6.5 --values-literal-file argocd-values.yaml --dest-namespace argocd --dest-server https://kubernetes.default.svc --sync-policy auto --self-heal --auto-prune | kubectl -n argocd apply -f -

argocd admin app generate-spec crossplane  --repo https://charts.crossplane.io/stable --helm-chart crossplane --revision 1.17.1 --values-literal-file crossplane-values.yaml --dest-namespace crossplane --dest-server https://kubernetes.default.svc --sync-policy auto --self-heal --auto-prune --sync-option "CreateNamespace=true" | kubectl -n argocd apply -f -

echo "All operations completed successfully."