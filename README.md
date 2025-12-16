# Kubernetes Cluster on GCP

Terraform + Kubespray setup for deploying a Kubernetes cluster on Google Cloud Platform.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      GCP VPC                            │
│  ┌─────────┐                                            │
│  │ Bastion │◄── Public IP (SSH entry point)             │
│  └────┬────┘                                            │
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
- gcloud CLI (authenticated)
- jq

## Quick Start

```bash
# 1. Infrastructure
make init
make apply

# 2. Kubernetes
make setup-kubespray
make deploy

# 3. Access cluster
make kubeconfig
make kubectl  # Terminal 1: opens tunnel

# Terminal 2:
export KUBECONFIG=$(pwd)/kubeconfig/config
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

### Access

| Command | Description |
|---------|-------------|
| `make ssh-bastion` | SSH to bastion host |
| `make ssh-master` | SSH to master-01 via bastion |
| `make kubeconfig` | Fetch kubeconfig from cluster |
| `make kubectl` | Open SSH tunnel for kubectl access |

### Utilities

| Command | Description |
|---------|-------------|
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

Since cluster nodes have private IPs only, you need an SSH tunnel:

```bash
# Terminal 1: Start tunnel
make kubectl

# Terminal 2: Use kubectl
export KUBECONFIG=$(pwd)/kubeconfig/config
kubectl get nodes
```

Alternatively, SSH to master and run kubectl there:

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
│   ├── inventory/        # Generated inventory
│   └── kubespray/        # Kubespray (git cloned)
├── tools/
│   └── generate-hosts.py # Inventory generator
├── kubeconfig/           # Fetched kubeconfig
├── artifacts/            # Terraform outputs
└── Makefile
```

## Notes

- All VMs use OS Login for SSH authentication
- Bastion is the only VM with a public IP
- Cluster nodes are accessed via SSH ProxyJump through bastion
- Kubespray runs in a Python venv (`.venv/`) for version compatibility

