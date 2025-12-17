# Workloads - GitOps with ArgoCD

This directory contains Helm charts for all Kubernetes workloads managed via ArgoCD using the **App of Apps** pattern.

## Directory Structure

```
workloads/
├── bootstrap/               # Root Application (App of Apps)
│   ├── Chart.yaml
│   ├── templates/
│   │   └── applications.yaml
│   └── values.yaml
│
├── network-mesh/            # Networking Layer
│   ├── ingress-nginx/       # NGINX Ingress Controller (NodePort 30080/30443)
│   ├── cert-manager/        # Certificate Management
│   └── istio/               # Service Mesh (optional)
│
├── cluster-services/        # Cluster-wide Services
│   ├── external-secrets/    # External Secrets Operator
│   └── longhorn/            # Distributed Storage
│
├── data-layer/              # Data Services
│   ├── postgres/            # PostgreSQL Database
│   ├── redis/               # Redis Cache
│   └── kafka/               # Message Broker
│
└── dev-platform/            # Developer Tools
    ├── sonarqube/           # Code Quality
    └── keycloak/            # Identity Management
```

## App of Apps Pattern

The `bootstrap/` chart is the root application that deploys all other applications. When you apply the bootstrap Application to ArgoCD, it automatically creates ArgoCD Application resources for each enabled workload.

### Enabling/Disabling Workloads

Edit `bootstrap/values.yaml` to enable or disable specific workloads:

```yaml
applications:
  - name: ingress-nginx
    enabled: true      # Will be deployed
    
  - name: istio
    enabled: false     # Will NOT be deployed
```

## Traffic Flow

```
                    ┌─────────────┐
     Internet ─────►│   Bastion   │
                    │  (HAProxy)  │
                    └──────┬──────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
         ▼                 ▼                 ▼
    Port 80           Port 443         Port 6443
         │                 │                 │
         ▼                 ▼                 ▼
   NodePort 30080    NodePort 30443    K8s API
         │                 │                 │
         └────────┬────────┘                 │
                  ▼                          │
           ┌──────────────┐         ┌───────────────┐
           │ Ingress NGINX│         │ Control Plane │
           └──────────────┘         └───────────────┘
                  │
                  ▼
           ┌──────────────┐
           │  Services    │
           └──────────────┘
```

## Sync Waves

Applications are deployed in order using ArgoCD sync waves:

| Wave | Applications |
|------|-------------|
| 1    | ingress-nginx, cert-manager |
| 2    | istio, external-secrets, longhorn |
| 3    | postgres, redis, kafka |
| 4    | sonarqube, keycloak |

## Usage

### Initial Deployment

```bash
# From project root
make gitops
```

This will:
1. Configure HAProxy on bastion
2. Create namespaces
3. Install ArgoCD
4. Apply the bootstrap Application

### Update Helm Dependencies

Before deploying, update Helm chart dependencies:

```bash
make helm-deps
```

### Manual Bootstrap (if needed)

```bash
export KUBECONFIG=$(pwd)/artifacts/kubeconfig

# Apply bootstrap application
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bootstrap
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR_ORG/dpg-infra-gcp.git
    targetRevision: HEAD
    path: workloads/bootstrap
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

## Accessing ArgoCD UI

```bash
# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Open https://localhost:8080
# Username: admin
```

## Customizing Workloads

Each workload has its own `values.yaml` that can be customized:

### Example: Enable Ingress for ArgoCD

```yaml
# workloads/network-mesh/ingress-nginx/values.yaml
ingress-nginx:
  controller:
    service:
      type: NodePort
      nodePorts:
        http: 30080
        https: 30443
```

### Example: Configure PostgreSQL

```yaml
# workloads/data-layer/postgres/values.yaml
postgresql:
  auth:
    postgresPassword: "your-secure-password"
    database: "myapp"
```

## Security Notes

⚠️ **Important**: Before production deployment:

1. Change all default passwords in `values.yaml` files
2. Enable TLS/SSL where applicable
3. Configure proper resource limits
4. Enable network policies
5. Set up proper RBAC

