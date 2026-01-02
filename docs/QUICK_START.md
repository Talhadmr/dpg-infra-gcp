# Quick Start Guide - External Secrets & ArgoCD Private Repo

This is a condensed guide to get External Secrets Operator and ArgoCD private repository access working quickly.

## Prerequisites Checklist

- [ ] GCP project with billing enabled
- [ ] `gcloud` CLI authenticated
- [ ] GitHub Personal Access Token (PAT) with `repo` scope
- [ ] Terraform, kubectl, helm installed

## Step 1: Deploy Infrastructure (5 minutes)

```bash
# Initialize and apply Terraform
make init
make apply

# This automatically:
# - Creates k8s-cluster-sa service account
# - Grants Secret Manager access
# - Attaches service account to all VMs
```

## Step 2: Deploy Kubernetes Cluster (15-20 minutes)

```bash
# Generate inventory and deploy
make inventory
make setup-ssh
make setup-kubespray
make deploy
make kubeconfig
export KUBECONFIG=$(pwd)/artifacts/kubeconfig
```

## Step 3: Store GitHub PAT in GCP Secret Manager (2 minutes)

```bash
# Create secret using Makefile
make setup-gcp-secret SECRET_NAME=argocd-private-repo-creds

# When prompted, paste your GitHub PAT token
```

## Step 4: Setup GitOps with ArgoCD (5 minutes)

```bash
# Install ArgoCD and External Secrets Operator
make gitops

# Wait for External Secrets Operator to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=external-secrets \
  -n cluster-services \
  --timeout=120s
```

## Step 5: Configure ArgoCD for Private Repository (3 minutes)

```bash
# Apply the example ExternalSecret (creates argocd-repo-credentials secret)
kubectl apply -f workloads/bootstrap/templates/example-secret.yaml

# Wait for ExternalSecret to sync
kubectl wait --for=condition=Ready externalsecret/argocd-repo-credentials -n argocd --timeout=60s

# Create ArgoCD Repository CR (replace YOUR_USERNAME and YOUR_REPO)
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Repository
metadata:
  name: private-repo
  namespace: argocd
spec:
  type: git
  url: https://github.com/YOUR_USERNAME/YOUR_PRIVATE_REPO.git
  passwordRef:
    secret:
      name: argocd-repo-credentials
      key: password
  usernameRef:
    secret:
      name: argocd-repo-credentials
      key: username
EOF

# Verify repository connection
kubectl get repository private-repo -n argocd
```

## Step 6: Update Bootstrap to Use Private Repo (1 minute)

```bash
# Update workloads/bootstrap/values.yaml
# Change repoURL to your private repository

# Then apply bootstrap
make bootstrap
```

## Verification

```bash
# Check External Secrets Operator
make verify-external-secrets

# Check ArgoCD repository
kubectl describe repository private-repo -n argocd

# Check ArgoCD applications
kubectl get applications -n argocd

# Test secret access from cluster
make test-secret-access SECRET_NAME=argocd-private-repo-creds
```

## Troubleshooting Quick Fixes

**External Secrets not syncing:**
```bash
kubectl logs -n cluster-services -l app.kubernetes.io/name=external-secrets
kubectl describe clustersecretstore gcp-secret-store
```

**ArgoCD cannot access repository:**
```bash
kubectl describe repository private-repo -n argocd
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server
```

**VM cannot access GCP Secret Manager:**
```bash
# Verify service account
terraform output k8s_cluster_service_account_email

# Check IAM permissions
gcloud projects get-iam-policy dpg-project-481018 \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:k8s-cluster-sa@dpg-project-481018.iam.gserviceaccount.com"
```

## Next Steps

- See [External Secrets Setup Guide](EXTERNAL_SECRETS_SETUP.md) for detailed instructions
- See [ArgoCD Private Repository Guide](ARGOCD_PRIVATE_REPO.md) for advanced configuration
- Create additional ExternalSecret resources for other services

## Total Time: ~30 minutes

This setup provides:
- ✅ Keyless authentication to GCP Secret Manager
- ✅ External Secrets Operator syncing secrets automatically
- ✅ ArgoCD accessing private GitHub repositories
- ✅ Zero JSON key management

