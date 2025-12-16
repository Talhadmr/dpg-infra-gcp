# Kubernetes Cluster on GCP

Terraform + Kubespray setup for deploying a Kubernetes cluster on Google Cloud Platform.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      GCP VPC                            │
│  ┌─────────┐                                            │
│  │ Bastion │◄── Public IP + HAProxy (K8s API LB)        │
│  └────┬────┘    Port 6443 → Masters                     │
│       │                                                 │
│       ▼                                                 │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                  │
│  │master-01│  │master-02│  │master-03│  Control Plane   │
│  └─────────┘  └─────────┘  └─────────┘                  │
│                                                         │
│  ┌─────────┐  ┌─────────┐                               │
│  │worker-01│  │worker-02│  Worker Nodes                 │
│  └─────────┘  └─────────┘                               │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- Terraform
- Python 3
- gcloud CLI (authenticated with OS Login configured)
- jq

### GCP Setup (one-time per developer)

```bash
# Auto-detects your SSH key and configures OS Login
make setup-gcp
```

This will:
- Find your SSH public key (id_ed25519, id_rsa, or id_ecdsa)
- Add it to GCP OS Login
- Grant the required IAM role

## Quick Start

```bash
# 1. Infrastructure
make init
make apply

# 2. Kubernetes
make inventory
make setup-ssh
make setup-kubespray
make deploy

# 3. Setup HAProxy Load Balancer
make renew-certs
make haproxy

# 4. Access cluster
make kubeconfig
export KUBECONFIG=$(pwd)/artifacts/kubeconfig
kubectl get nodes
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
| `make haproxy` | Install HAProxy on bastion to expose K8s API |
| `make renew-certs` | Regenerate API server certs with bastion IP |

### Access

| Command | Description |
|---------|-------------|
| `make ssh-bastion` | SSH to bastion host |
| `make ssh-master` | SSH to master-01 via bastion |
| `make kubeconfig` | Fetch kubeconfig from cluster |

### Utilities

| Command | Description |
|---------|-------------|
| `make setup-gcp` | Configure OS Login (one-time per developer) |
| `make inventory` | Regenerate Ansible inventory |
| `make ping` | Test Ansible connectivity |
| `make clean` | Remove generated files |

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

## Accessing the Cluster

After deploying Kubernetes and HAProxy, the Kubernetes API is exposed through the bastion's public IP:

```bash
# Fetch and configure kubeconfig (auto-updates API server URL)
make kubeconfig

# Use kubectl
export KUBECONFIG=$(pwd)/artifacts/kubeconfig
kubectl get nodes
```

The `make kubeconfig` command automatically configures the kubeconfig to use `https://<bastion-ip>:6443` as the API server.

### HAProxy Stats

HAProxy provides a stats page at `http://<bastion-ip>:8404/stats` for monitoring load balancer health.

### Alternative: SSH to Master

You can also SSH directly to a master and run kubectl there:

```bash
make ssh-master
sudo kubectl get nodes
```

## Directory Structure

```
.
├── terraform/
│   ├── modules/
│   │   ├── vpc/          # VPC, subnets, firewall, NAT
│   │   └── vm/           # Cluster and standalone VMs
│   ├── main.tf
│   ├── variables.tf
│   └── terraform.tfvars
├── ansible/
│   ├── haproxy/          # HAProxy playbook and templates
│   ├── inventory/        # Generated inventory
│   └── kubespray/        # Kubespray (git cloned)
├── tools/
│   └── generate-hosts.py # Inventory generator
├── artifacts/            # Generated files (nodes.json, kubeconfig)
└── Makefile
```

## Notes

- All VMs use OS Login for SSH authentication
- Bastion is the only VM with a public IP
- HAProxy on bastion load balances Kubernetes API (port 6443) to masters
- Cluster nodes are accessed via SSH ProxyJump through bastion
- Kubespray runs in a Python venv (`.venv/`) for version compatibility
- TODO: IP whitelisting for K8s API access (currently open to 0.0.0.0/0)
