# ArgoCD Private Repository Setup

This guide explains how to configure ArgoCD to access private GitHub repositories using External Secrets Operator and GCP Secret Manager.

## Architecture

```
GitHub Private Repo
        │
        ▼
GCP Secret Manager (stores PAT token)
        │
        ▼
External Secrets Operator (syncs via VM Identity)
        │
        ▼
Kubernetes Secret (argocd-repo-credentials)
        │
        ▼
ArgoCD Repository CR (references the secret)
        │
        ▼
ArgoCD Applications (use the repository)
```

## Prerequisites

1. External Secrets Operator installed and configured
2. GCP Secret Manager secret created with GitHub PAT token
3. ClusterSecretStore `gcp-secret-store` available

## Step-by-Step Setup

### Step 1: Create GitHub Personal Access Token

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token with these scopes:
   - `repo` (Full control of private repositories)
   - `read:packages` (if using GitHub Packages)
3. Copy the token (you won't see it again)

### Step 2: Store PAT in GCP Secret Manager

```bash
# Using Makefile (recommended)
make setup-gcp-secret SECRET_NAME=argocd-private-repo-creds

# Or manually
export PROJECT_ID="dpg-project-481018"
echo -n "YOUR_GITHUB_PAT_TOKEN" | gcloud secrets create argocd-private-repo-creds \
  --data-file=- \
  --replication-policy="automatic" \
  --project=${PROJECT_ID}
```

### Step 3: Create ExternalSecret for ArgoCD

Create an ExternalSecret that fetches the PAT token from GCP:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-repo-credentials
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd
    app.kubernetes.io/part-of: gitops
    argocd.argoproj.io/secret-type: repository
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-store
    kind: ClusterSecretStore
  target:
    name: argocd-repo-credentials
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        type: "{{ .type | b64enc }}"
        url: "{{ .url | b64enc }}"
        password: "{{ .password | b64enc }}"
        username: "{{ .username | b64enc }}"
  data:
    - secretKey: password
      remoteRef:
        key: argocd-private-repo-creds
    - secretKey: username
      remoteRef:
        key: argocd-private-repo-creds
    - secretKey: type
      remoteRef:
        key: argocd-private-repo-creds
        property: type
      extract:
        key: argocd-private-repo-creds
        property: type
    - secretKey: url
      remoteRef:
        key: argocd-private-repo-creds
        property: url
      extract:
        key: argocd-private-repo-creds
        property: url
EOF
```

**Wait for ExternalSecret to sync:**
```bash
kubectl wait --for=condition=Ready externalsecret/argocd-repo-credentials -n argocd --timeout=60s

# Verify secret was created
kubectl get secret argocd-repo-credentials -n argocd
```

### Step 4: Create ArgoCD Repository CR

Create an ArgoCD Repository resource that uses the secret:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Repository
metadata:
  name: private-repo
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd
    app.kubernetes.io/part-of: gitops
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
  insecure: false
  enableLfs: false
EOF
```

**Replace:**
- `YOUR_USERNAME` with your GitHub username
- `YOUR_PRIVATE_REPO` with your private repository name

### Step 5: Verify Repository Connection

```bash
# Check repository status
kubectl get repository private-repo -n argocd
kubectl describe repository private-repo -n argocd

# Check ArgoCD repo server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=50
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

Or update the existing bootstrap application:

```bash
kubectl patch application bootstrap -n argocd --type merge -p '{"spec":{"source":{"repoURL":"https://github.com/YOUR_USERNAME/YOUR_PRIVATE_REPO.git"}}}'
```

## Alternative: Using Helm Template

You can also create the ExternalSecret and Repository as Helm templates. Create these files:

**`workloads/argocd/templates/externalsecret-repo-credentials.yaml`:**
```yaml
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-repo-credentials
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd
    argocd.argoproj.io/secret-type: repository
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-store
    kind: ClusterSecretStore
  target:
    name: argocd-repo-credentials
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        type: "git"
        url: "{{ .Values.repository.url | b64enc }}"
        password: "{{ .password | b64enc }}"
        username: "{{ .username | b64enc }}"
  data:
    - secretKey: password
      remoteRef:
        key: {{ .Values.repository.patSecretName }}
    - secretKey: username
      remoteRef:
        key: {{ .Values.repository.patSecretName }}
```

**`workloads/argocd/templates/repository.yaml`:**
```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Repository
metadata:
  name: {{ .Values.repository.name }}
  namespace: argocd
spec:
  type: git
  url: {{ .Values.repository.url }}
  passwordRef:
    secret:
      name: argocd-repo-credentials
      key: password
  usernameRef:
    secret:
      name: argocd-repo-credentials
      key: username
```

## Troubleshooting

### Repository Connection Failed

```bash
# Check repository status
kubectl describe repository private-repo -n argocd

# Check if secret exists
kubectl get secret argocd-repo-credentials -n argocd

# Check ExternalSecret status
kubectl get externalsecret argocd-repo-credentials -n argocd
kubectl describe externalsecret argocd-repo-credentials -n argocd

# Check ArgoCD repo server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=100
```

### ExternalSecret Not Syncing

```bash
# Check External Secrets Operator logs
kubectl logs -n cluster-services -l app.kubernetes.io/name=external-secrets

# Verify ClusterSecretStore
kubectl describe clustersecretstore gcp-secret-store

# Check if secret exists in GCP
gcloud secrets list --project=dpg-project-481018 | grep argocd-private-repo-creds
```

### PAT Token Issues

```bash
# Test token manually
gcloud secrets versions access latest --secret=argocd-private-repo-creds --project=dpg-project-481018

# Update token if needed
echo -n "NEW_TOKEN" | gcloud secrets versions add argocd-private-repo-creds \
  --data-file=- \
  --project=dpg-project-481018
```

## Best Practices

1. **Use separate PAT tokens** for different repositories when possible
2. **Rotate tokens regularly** - update in GCP Secret Manager, ExternalSecret will auto-sync
3. **Use minimal scopes** - only grant necessary permissions to PAT tokens
4. **Monitor access** - review GitHub audit logs and GCP audit logs
5. **Use Repository CRs** - prefer Repository resources over inline credentials in Applications

## Security Notes

- PAT tokens are stored encrypted in GCP Secret Manager
- Tokens are synced to Kubernetes secrets (encrypted at rest)
- External Secrets Operator refreshes secrets every hour by default
- VM Identity ensures no keys are stored on disk
- All access is logged in GCP audit logs

