# DPG Infrastructure on GCP

Self-managed Kubernetes cluster infrastructure on Google Cloud Platform using Terraform and Kubespray.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        GCP VPC                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                 Subnet (10.10.10.0/24)                │  │
│  │                                                       │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │  │
│  │  │  master-01  │  │  master-02  │  │  master-03  │   │  │
│  │  │  (control)  │  │  (control)  │  │  (control)  │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘   │  │
│  │                                                       │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │  │
│  │  │  worker-01  │  │  worker-02  │  │  worker-03  │   │  │
│  │  │  (worker)   │  │  (worker)   │  │  (worker)   │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘   │  │
│  │                                                       │  │
│  │  ┌─────────────┐  (Optional standalone VMs)          │  │
│  │  │  bastion    │                                     │  │
│  │  │ (standalone)│                                     │  │
│  │  └─────────────┘                                     │  │
│  └───────────────────────────────────────────────────────┘  │
│                           │                                  │
│                      Cloud NAT                               │
│                           │                                  │
│                       Internet                               │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

```
.
├── terraform/
│   ├── main.tf                    # Root module - calls VPC and VM modules
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Output values
│   ├── providers.tf               # Provider configuration
│   ├── terraform.tfvars.example   # Example variable values
│   └── modules/
│       ├── vpc/                   # VPC, subnet, firewall, NAT
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── vm/                    # Compute instances
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── ansible/
│   └── kubespray/
│       ├── inventory/
│       │   └── inventory.ini      # Generated Kubespray inventory
│       └── group_vars/
│           └── k8s-cluster.yml    # Kubernetes cluster configuration
├── artifacts/
│   └── nodes.json                 # Terraform output for inventory generation
└── tools/
    └── generate-hosts.py          # Terraform → Kubespray inventory converter
```

## Prerequisites

- Terraform >= 1.5.0
- Google Cloud SDK (`gcloud`)
- Python 3.x
- Ansible (for Kubespray)

## Quick Start

### 1. GCP Authentication

```bash
# Create service account
gcloud iam service-accounts create tf-lab --display-name="Terraform lab SA"

# Grant editor role
gcloud projects add-iam-policy-binding $YOUR_PROJECT_ID \
  --member="serviceAccount:tf-lab@$YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/editor"

# Create key file
gcloud iam service-accounts keys create ./tf-lab-sa.json \
  --iam-account="tf-lab@$YOUR_PROJECT_ID.iam.gserviceaccount.com"

# Set credentials
export GOOGLE_APPLICATION_CREDENTIALS="./tf-lab-sa.json"
```

### 2. Configure Terraform

```bash
cd terraform

# Copy example config
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

### 3. Deploy Infrastructure

```bash
# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply
```

### 4. Generate Kubespray Inventory

```bash
# Export node information
terraform output -json all_nodes > ../artifacts/nodes.json

# Generate inventory
python3 ../tools/generate-hosts.py \
  -i ../artifacts/nodes.json \
  -o ../ansible/kubespray/inventory/inventory.ini \
  --ansible-user debian \
  --become
```

### 5. Deploy Kubernetes with Kubespray

```bash
cd ../ansible/kubespray

# Clone kubespray
git clone https://github.com/kubernetes-sigs/kubespray.git kubespray-repo

# Copy inventory and group_vars
cp -r inventory/ kubespray-repo/inventory/mycluster/
cp group_vars/* kubespray-repo/inventory/mycluster/group_vars/k8s_cluster/

# Install dependencies
pip install -r kubespray-repo/requirements.txt

# Run playbook (via IAP tunnel or bastion)
ansible-playbook -i kubespray-repo/inventory/mycluster/inventory.ini \
  kubespray-repo/cluster.yml -b
```

## Configuration

### Cluster Nodes

Configure Kubernetes cluster nodes in `terraform.tfvars`:

```hcl
cluster_nodes = {
  enabled      = true
  master_count = 3          # Number of control-plane nodes
  worker_count = 3          # Number of worker nodes
  machine_type = "e2-standard-2"
  disk_size_gb = 20
  disk_type    = "pd-standard"
  image        = "projects/debian-cloud/global/images/family/debian-12"
}
```

Node names are generated automatically:
- Masters: `master-01`, `master-02`, `master-03`, ...
- Workers: `worker-01`, `worker-02`, `worker-03`, ...

### Standalone VMs

Add VMs outside the Kubernetes cluster:

```hcl
standalone_vms = [
  {
    name         = "bastion"
    machine_type = "e2-small"
    disk_size_gb = 10
  },
  {
    name         = "monitoring"
    machine_type = "e2-medium"
    disk_size_gb = 50
    labels = {
      purpose = "monitoring"
    }
  },
  {
    name = "jump-server"
    # Uses standalone_defaults for unspecified values
  }
]

standalone_defaults = {
  machine_type = "e2-medium"
  disk_size_gb = 20
  disk_type    = "pd-standard"
  image        = "projects/debian-cloud/global/images/family/debian-12"
}
```

### VPC Configuration

```hcl
vpc_config = {
  name           = "dpg-lab"
  subnet_cidr    = "10.10.10.0/24"
  enable_nat     = true       # Cloud NAT for outbound access
  enable_iap_ssh = true       # IAP SSH firewall rule
}
```

## SSH Access via IAP

```bash
# SSH to a node via IAP tunnel
gcloud compute ssh master-01 --tunnel-through-iap --zone=europe-west3-a

# Or use IAP tunnel for Ansible
gcloud compute start-iap-tunnel master-01 22 --local-host-port=localhost:2222 --zone=europe-west3-a
```

## Outputs

| Output | Description |
|--------|-------------|
| `cluster_nodes` | All cluster nodes with IP and role |
| `master_nodes` | Control-plane nodes only |
| `worker_nodes` | Worker nodes only |
| `standalone_nodes` | Standalone VMs |
| `all_nodes` | Combined output for inventory generation |

## Kubernetes Stack

- **Version**: v1.30.5
- **Container Runtime**: containerd
- **CNI**: Calico
- **etcd**: Stacked (runs on control-plane nodes)
