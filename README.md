# Kubernetes Cluster on GCP

Terraform + Kubespray + ArgoCD setup for deploying a production-ready Kubernetes cluster on Google Cloud Platform with GitOps workflow.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           GCP VPC                                   │
│                                                                     │
│  ┌─────────────┐                                                    │
│  │   Bastion   │◄── Static Public IP                                │
│  │  (HAProxy)  │    • Port 6443 → Masters (K8s API)                 │
│  │             │    • Port 80   → Workers:30080 (HTTP Ingress)      │
│  │             │    • Port 443  → Workers:30443 (HTTPS Ingress)     │
│  └──────┬──────┘                                                    │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    Control Plane                            │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐                      │    │
│  │  │master-01│  │master-02│  │master-03│                      │    │
│  │  └─────────┘  └─────────┘  └─────────┘                      │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    Worker Nodes                              │    │
│  │  ┌─────────┐  ┌─────────┐                                   │    │
│  │  │worker-01│  │worker-02│  ← NGINX Ingress (NodePort)       │    │
│  │  └─────────┘  └─────────┘                                   │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Terraform >= 1.0
- Python 3.8+
- gcloud CLI (authenticated)
- Helm 3
- kubectl
- jq

### GCP Setup (one-time per developer)

```bash
# Auto-detects your SSH key and configures OS Login
make setup-gcp
```

## Quick Start

### Full Deployment (Infrastructure + K8s + GitOps)

```bash
# Complete setup in one command
make full-setup
```

Or step by step:

```bash
# 1. Infrastructure
make init
make apply

# 2. Kubernetes Cluster
make inventory
make setup-ssh
make setup-kubespray
make deploy

# 3. Edge Router (HAProxy)
make renew-certs
make haproxy

# 4. GitOps (ArgoCD)
make kubeconfig
export KUBECONFIG=$(pwd)/artifacts/kubeconfig
make gitops
```

## Makefile Commands

### Infrastructure

| Command | Description |
|---------|-------------|
| `make init` | Initialize Terraform |
| `make plan` | Preview changes |
| `make apply` | Create/update infrastructure |
| `make destroy` | Destroy all resources |

### Kubernetes

| Command | Description |
|---------|-------------|
| `make setup-kubespray` | Download Kubespray and create Python venv |
| `make deploy` | Deploy Kubernetes cluster |
| `make reset` | Reset/destroy Kubernetes (keeps VMs) |
| `make kubeconfig` | Fetch kubeconfig from cluster |

### Edge Router (HAProxy)

| Command | Description |
|---------|-------------|
| `make haproxy` | Install/update HAProxy on bastion |
| `make renew-certs` | Regenerate API server certs with bastion IP |

### GitOps (ArgoCD)

| Command | Description |
|---------|-------------|
| `make namespaces` | Create Kubernetes namespaces |
| `make argocd` | Install ArgoCD via Helm |
| `make bootstrap` | Apply App of Apps manifest |
| `make gitops` | Full GitOps setup (HAProxy + namespaces + ArgoCD + bootstrap) |
| `make helm-deps` | Update Helm dependencies for all workloads |

### Access

| Command | Description |
|---------|-------------|
| `make ssh-bastion` | SSH to bastion host |
| `make ssh-master` | SSH to master-01 via bastion |
| `make setup-gcp` | Configure OS Login (one-time per developer) |
| `make ping` | Test Ansible connectivity |

## GitOps Workflow

This project implements the **App of Apps** pattern with ArgoCD for GitOps-based deployments.

### Workloads Structure

```
workloads/
├── bootstrap/               # Root Application
├── network-mesh/
│   ├── ingress-nginx/       # NGINX Ingress (NodePort 30080/30443)
│   ├── cert-manager/        # Certificate management
│   └── istio/               # Service mesh (optional)
├── cluster-services/
│   ├── external-secrets/    # External secrets operator
│   └── longhorn/            # Distributed storage
├── data-layer/
│   ├── postgres/            # PostgreSQL
│   ├── redis/               # Redis
│   └── kafka/               # Kafka
└── dev-platform/
    ├── sonarqube/           # Code quality
    └── keycloak/            # Identity management
```

### Enabling/Disabling Workloads

Edit `workloads/bootstrap/values.yaml`:

```yaml
applications:
  - name: ingress-nginx
    enabled: true     # Will be deployed
    
  - name: kafka
    enabled: false    # Will NOT be deployed
```

### Accessing ArgoCD

```bash
# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Open https://localhost:8080
```

## Traffic Flow

```
Internet → Bastion (HAProxy)
                │
    ┌───────────┼───────────┐
    │           │           │
    ▼           ▼           ▼
  :80         :443        :6443
    │           │           │
    ▼           ▼           │
Workers:30080 Workers:30443 │
    │           │           │
    └─────┬─────┘           │
          ▼                 ▼
    NGINX Ingress     K8s API Server
          │
          ▼
      Services
```

## Configuration

Edit `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "europe-west3"
zone       = "europe-west3-a"

cluster_nodes = {
  master_count = 3
  worker_count = 2
  machine_type = "e2-standard-2"
}
```

## HAProxy Stats

Monitor load balancer health at `http://<bastion-ip>:8404/stats`

## Directory Structure

```
.
├── terraform/
│   ├── modules/
│   │   ├── vpc/              # VPC, subnets, firewall, NAT
│   │   └── vm/               # Cluster and standalone VMs
│   └── terraform.tfvars
├── ansible/
│   ├── argocd/               # ArgoCD installation playbooks
│   ├── cluster/              # Namespace management
│   ├── haproxy/              # HAProxy configuration
│   ├── inventory/            # Generated inventory
│   └── kubespray/            # Kubespray (git cloned)
├── workloads/                # Helm charts (App of Apps)
├── tools/
│   └── generate-hosts.py     # Inventory generator
├── artifacts/                # Generated files
├── docs/                     # Documentation
└── Makefile
```

## Cost Optimization

To reduce GCP costs, you can schedule automatic shutdown of cluster VMs:

```bash
# Run the scheduler script (one-time setup)
./tools/scheduler-cron.sh
```

This creates a GCP resource policy that:
- **Stops all VMs** (bastion, masters, workers) at **22:00 Istanbul time** daily
- Uses GCP's native instance scheduling (no external cron needed)

To start the cluster again:
```bash
# Start all instances manually
gcloud compute instances start bastion master-01 master-02 master-03 worker-01 worker-02 --zone=europe-west3-a
```

## Notes

- All VMs use OS Login for SSH authentication
- Bastion has a static public IP and runs HAProxy as an edge router
- NGINX Ingress uses NodePort (30080/30443) behind HAProxy
- ArgoCD manages all workloads via GitOps
- Kubespray runs in a Python venv (`.venv/`) for version compatibility
- TODO: IP whitelisting for external access (currently open to 0.0.0.0/0)

## Documentation

- [Development Notes](docs/DEVELOPMENT_NOTES.md) - Detailed architecture and troubleshooting
- [Workloads README](workloads/README.md) - GitOps and Helm charts documentation


## deleting a namespace with zombie process 
kubectl get namespace {namespacce name} -o json | tr -d "\n" | sed "s/\"kubernetes\"//g" | kubectl replace --raw /api/v1/namespaces/{namespacce name}/finalize -f -

