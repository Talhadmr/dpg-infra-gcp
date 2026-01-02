# External Secrets Operator

This chart installs the External Secrets Operator and configures a ClusterSecretStore for GCP Secret Manager integration using **Keyless Authentication (VM Identity)**.

## What This Chart Does

- Installs External Secrets Operator (ESO) via Helm
- Creates a ClusterSecretStore named `gcp-secret-store` that all services can use
- Configures GCP Secret Manager provider with **Application Default Credentials (ADC)**
- Uses VM instance identity for authentication (no service account keys required)

## Keyless Authentication Architecture

This implementation uses **VM Identity** pattern:

1. **Terraform** creates a service account (`k8s-cluster-sa`) and attaches it to all VM instances (masters and workers)
2. **Service Account** has `roles/secretmanager.secretAccessor` IAM role
3. **VM Instances** run with `cloud-platform` scope, enabling automatic credential discovery
4. **External Secrets Operator** uses Application Default Credentials (ADC) to authenticate
5. **No JSON keys** are generated or stored - authentication is automatic via instance metadata

## Prerequisites

### Infrastructure Setup (Terraform)

The service account and IAM permissions are automatically created by Terraform:

```bash
# Service account is created in terraform/modules/vm/main.tf
# IAM binding is configured automatically
# All VMs (masters and workers) are attached to the service account

terraform apply
```

The Terraform module:
- Creates `k8s-cluster-sa` service account
- Grants `roles/secretmanager.secretAccessor` permission
- Attaches service account to all cluster VMs with `cloud-platform` scope

### GCP Secret Manager

Create secrets in GCP Secret Manager:

```bash
export PROJECT_ID="dpg-project-481018"

# Create a secret
echo -n "your-secret-value" | gcloud secrets create my-secret-name \
  --data-file=- \
  --replication-policy="automatic" \
  --project=${PROJECT_ID}
```

## Configuration

Update `values.yaml`:

```yaml
gcp:
  enabled: true
  gcpProjectId: "dpg-project-481018"
```

## Installation

### Via ArgoCD (Recommended)

The chart will be automatically installed when you deploy the bootstrap application via ArgoCD.

### Manual Installation

```bash
# Add Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Build dependencies
cd workloads/cluster-services/external-secrets
helm dependency build

# Install
helm install external-secrets . \
  -n cluster-services \
  --create-namespace \
  -f values.yaml
```

## Verification

```bash
# Check ClusterSecretStore
kubectl get clustersecretstore gcp-secret-store
kubectl describe clustersecretstore gcp-secret-store

# Check External Secrets Operator pods
kubectl get pods -n cluster-services | grep external-secrets

# Verify service account is attached to VMs
terraform output k8s_cluster_service_account_email
```

## Usage

After installation, all services can create ExternalSecret resources that reference the `gcp-secret-store` ClusterSecretStore:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-service-secrets
  namespace: my-namespace
spec:
  secretStoreRef:
    name: gcp-secret-store
    kind: ClusterSecretStore
  target:
    name: my-service-secrets
  data:
    - secretKey: password
      remoteRef:
        key: my-secret-name-in-gcp
```

## Example: Test Secret

A sample ExternalSecret is provided in `workloads/bootstrap/templates/example-secret.yaml`:

```bash
# First, create the secret in GCP
echo -n "test-value" | gcloud secrets create argocd-private-repo-creds \
  --data-file=- \
  --replication-policy="automatic" \
  --project=dpg-project-481018

# Apply the example ExternalSecret
kubectl apply -f workloads/bootstrap/templates/example-secret.yaml

# Check status
kubectl get externalsecret test-gcp-access -n default
kubectl get secret test-gcp-access -n default
```

## Service-Specific Secrets

Each service should manage its own ExternalSecret resources in its own chart templates directory. For example:

```
workloads/
├── data-layer/
│   └── postgres/
│       └── templates/
│           └── externalsecret-db-credentials.yaml
└── argocd/
    └── templates/
        └── externalsecret-repo-credentials.yaml
```

## Troubleshooting

### Check External Secrets Operator logs

```bash
kubectl logs -n cluster-services -l app.kubernetes.io/name=external-secrets
```

### Check ClusterSecretStore status

```bash
kubectl describe clustersecretstore gcp-secret-store
```

### Verify VM service account attachment

```bash
# SSH to a node and check metadata
gcloud compute ssh master-01 --zone=europe-west3-a --command="curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"
```

### Verify IAM permissions

```bash
# Check service account permissions
gcloud projects get-iam-policy dpg-project-481018 \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:k8s-cluster-sa@dpg-project-481018.iam.gserviceaccount.com"
```

## Advantages of Keyless Authentication

- **No key management**: No JSON keys to generate, store, or rotate
- **Automatic rotation**: Credentials are automatically managed by GCP
- **Better security**: Keys cannot be leaked or stolen
- **Simpler operations**: No need to manage service account keys
- **Zero-touch**: Works automatically after Terraform apply

## Architecture Notes

- The service account is created at the infrastructure level (Terraform)
- All cluster VMs (masters and workers) use the same service account
- External Secrets Operator uses ADC which automatically discovers credentials from the VM metadata server
- The ClusterSecretStore has no `auth` block - it relies on ADC

