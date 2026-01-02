# External Secrets Operator - Complete Setup Guide

This guide walks you through setting up External Secrets Operator with GCP Secret Manager using **Keyless Authentication (VM Identity)**.

## Overview

The setup uses **Application Default Credentials (ADC)** pattern:
- Service account is attached to VM instances at infrastructure level
- No JSON keys are generated or stored
- External Secrets Operator automatically discovers credentials via VM metadata server
- Zero-touch authentication after initial Terraform deployment

## Prerequisites

- GCP project with billing enabled
- `gcloud` CLI installed and authenticated
- Terraform >= 1.5.0
- kubectl configured to access your cluster

## Step-by-Step Setup

### Step 1: Create Secret in GCP Secret Manager

First, create the secret that ArgoCD will use for private repository access:

```bash
export PROJECT_ID="dpg-project-481018"

# Create GitHub PAT token secret
echo -n "YOUR_GITHUB_PAT_TOKEN" | gcloud secrets create argocd-private-repo-creds \
  --data-file=- \
  --replication-policy="automatic" \
  --project=${PROJECT_ID}

# Verify secret was created
gcloud secrets list --project=${PROJECT_ID} | grep argocd-private-repo-creds
```

**Note:** Replace `YOUR_GITHUB_PAT_TOKEN` with your actual GitHub Personal Access Token.

### Step 2: Deploy Infrastructure with Service Account

The Terraform configuration automatically:
- Creates `k8s-cluster-sa` service account
- Grants `roles/secretmanager.secretAccessor` permission
- Attaches service account to all VM instances

```bash
# Initialize Terraform
make init

# Review changes
make plan

# Apply infrastructure (creates service account and attaches to VMs)
make apply
```

**Verify service account was created:**
```bash
terraform output k8s_cluster_service_account_email
```

### Step 3: Deploy Kubernetes Cluster

```bash
# Generate inventory
make inventory

# Test SSH connectivity
make setup-ssh

# Setup Kubespray
make setup-kubespray

# Deploy Kubernetes cluster
make deploy

# Fetch kubeconfig
make kubeconfig
export KUBECONFIG=$(pwd)/artifacts/kubeconfig
```

### Step 4: Install External Secrets Operator

```bash
# Install External Secrets Operator via ArgoCD (recommended)
make gitops

# Or manually:
make namespaces
make argocd
# Wait for external-secrets to be deployed by ArgoCD
```

**Verify installation:**
```bash
# Check External Secrets Operator pods
kubectl get pods -n cluster-services | grep external-secrets

# Check ClusterSecretStore
kubectl get clustersecretstore gcp-secret-store
kubectl describe clustersecretstore gcp-secret-store
```

### Step 5: Configure ArgoCD for Private Repository

#### Option A: Using External Secrets (Recommended)

The example ExternalSecret in `workloads/bootstrap/templates/example-secret.yaml` will create a secret that ArgoCD can use.

**Create ArgoCD Repository Secret:**

```bash
# Apply the example ExternalSecret (creates test-gcp-access secret)
kubectl apply -f workloads/bootstrap/templates/example-secret.yaml

# Verify secret was created
kubectl get secret test-gcp-access -n default
kubectl get externalsecret test-gcp-access -n default
```

**Create ArgoCD Repository CR:**

```bash
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
      name: test-gcp-access
      key: credentials
  usernameRef:
    secret:
      name: test-gcp-access
      key: credentials
EOF
```

#### Option B: Manual Secret Creation

If you prefer to create the secret manually:

```bash
# Get the secret value from GCP
SECRET_VALUE=$(gcloud secrets versions access latest --secret=argocd-private-repo-creds --project=dpg-project-481018)

# Create Kubernetes secret for ArgoCD
kubectl create secret generic argocd-repo-credentials \
  --from-literal=type=git \
  --from-literal=url=https://github.com/YOUR_USERNAME/YOUR_PRIVATE_REPO.git \
  --from-literal=password="${SECRET_VALUE}" \
  --from-literal=username="${SECRET_VALUE}" \
  -n argocd

# Label it for ArgoCD
kubectl label secret argocd-repo-credentials \
  -n argocd \
  argocd.argoproj.io/secret-type=repository

# Create Repository CR
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
```

### Step 6: Update Bootstrap Application

Update `workloads/bootstrap/values.yaml` to use your private repository:

```yaml
spec:
  source:
    repoURL: https://github.com/YOUR_USERNAME/YOUR_PRIVATE_REPO.git
    targetRevision: HEAD
    path: workloads
```

Then apply the bootstrap:

```bash
make bootstrap
```

### Step 7: Verify Everything Works

```bash
# Check ArgoCD repository connection
kubectl get repository private-repo -n argocd
kubectl describe repository private-repo -n argocd

# Check ExternalSecret status
kubectl get externalsecret -A

# Check ArgoCD applications
kubectl get applications -n argocd

# View ArgoCD logs if needed
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server
```

## Troubleshooting

### External Secrets Operator Not Syncing

```bash
# Check operator logs
kubectl logs -n cluster-services -l app.kubernetes.io/name=external-secrets

# Check ClusterSecretStore status
kubectl describe clustersecretstore gcp-secret-store

# Verify VM has service account attached
gcloud compute instances describe master-01 --zone=europe-west3-a --format="get(serviceAccounts)"
```

### ArgoCD Cannot Access Private Repository

```bash
# Check repository status
kubectl describe repository private-repo -n argocd

# Check ArgoCD repo server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server

# Verify secret exists
kubectl get secret argocd-repo-credentials -n argocd
```

### VM Cannot Access GCP Secret Manager

```bash
# Verify service account has correct permissions
gcloud projects get-iam-policy dpg-project-481018 \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:k8s-cluster-sa@dpg-project-481018.iam.gserviceaccount.com"

# Test from a VM
gcloud compute ssh master-01 --zone=europe-west3-a --command="gcloud secrets versions access latest --secret=argocd-private-repo-creds"
```

## Makefile Commands

Use these commands for External Secrets setup:

```bash
# Setup GCP Secret Manager secret
make setup-gcp-secret SECRET_NAME=argocd-private-repo-creds

# Verify External Secrets setup
make verify-external-secrets

# Test secret access
make test-secret-access SECRET_NAME=argocd-private-repo-creds
```

## Next Steps

After setup is complete:

1. Create additional secrets in GCP Secret Manager as needed
2. Create ExternalSecret resources in your service charts
3. Each service manages its own ExternalSecret templates
4. Secrets are automatically synced from GCP to Kubernetes

## Security Best Practices

- **Rotate PAT tokens regularly**: Update the secret in GCP Secret Manager
- **Use least privilege**: Only grant necessary IAM roles
- **Monitor access**: Review GCP audit logs for Secret Manager access
- **Separate secrets**: Use different secrets for different services when possible

