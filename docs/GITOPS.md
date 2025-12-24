# GitOps with ArgoCD - Complete Guide

This document provides a comprehensive overview of our GitOps implementation using ArgoCD, Helm charts, and the App of Apps pattern.

## Table of Contents

1. [What is GitOps?](#what-is-gitops)
2. [Architecture Overview](#architecture-overview)
3. [Component Roles](#component-roles)
4. [App of Apps Pattern](#app-of-apps-pattern)
5. [Directory Structure](#directory-structure)
6. [Helm Charts](#helm-charts)
7. [Ansible Integration](#ansible-integration)
8. [ArgoCD Configuration](#argocd-configuration)
9. [Deployment Workflow](#deployment-workflow)
10. [Managing Applications](#managing-applications)
11. [Troubleshooting](#troubleshooting)

---

## What is GitOps?

GitOps is a modern approach to continuous deployment where:

- **Git is the single source of truth** for declarative infrastructure and applications
- **Changes are made via Git** (commits, pull requests)
- **Automated agents** (ArgoCD) ensure the cluster state matches Git
- **Drift detection** automatically identifies and corrects configuration drift

### Traditional vs GitOps Deployment

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRADITIONAL APPROACH                         │
│                                                                 │
│   Developer ──► kubectl apply ──► Kubernetes                    │
│                                                                 │
│   Problems:                                                     │
│   • No audit trail                                              │
│   • Manual process                                              │
│   • Drift goes unnoticed                                        │
│   • "Works on my machine" issues                                │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      GITOPS APPROACH                            │
│                                                                 │
│   Developer ──► Git Push ──► ArgoCD ──► Kubernetes              │
│                                                                 │
│   Benefits:                                                     │
│   • Full audit trail (git history)                              │
│   • Automated deployments                                       │
│   • Self-healing (drift correction)                             │
│   • Easy rollbacks (git revert)                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              GITHUB                                     │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    dpg-infra-gcp Repository                       │  │
│  │                                                                   │  │
│  │   workloads/                                                      │  │
│  │   ├── bootstrap/          ◄── Root Application                    │  │
│  │   ├── network-mesh/       ◄── Ingress, Cert-Manager, Istio        │  │
│  │   ├── cluster-services/   ◄── External-Secrets, Longhorn          │  │
│  │   ├── data-layer/         ◄── PostgreSQL, Redis, Kafka            │  │
│  │   └── dev-platform/       ◄── SonarQube, Keycloak                 │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────┬───────────────────────────────────┘
                                      │
                                      │ Pull (every 3 min)
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         KUBERNETES CLUSTER                              │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    ArgoCD (argocd namespace)                    │   │
│   │                                                                 │   │
│   │   ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐    │   │
│   │   │   Server    │  │    Repo     │  │    Application      │    │   │
│   │   │   (UI/API)  │  │   Server    │  │    Controller       │    │   │
│   │   └─────────────┘  └─────────────┘  └─────────────────────┘    │   │
│   │                           │                    │                │   │
│   │                           │ Clone & Render     │ Apply          │   │
│   │                           ▼                    ▼                │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                     Deployed Applications                       │   │
│   │                                                                 │   │
│   │   ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐    │   │
│   │   │   network   │  │   cluster   │  │     data-layer      │    │   │
│   │   │    mesh     │  │  services   │  │                     │    │   │
│   │   │             │  │             │  │                     │    │   │
│   │   │ • ingress   │  │ • external  │  │ • postgres          │    │   │
│   │   │ • cert-mgr  │  │   secrets   │  │ • redis             │    │   │
│   │   └─────────────┘  └─────────────┘  └─────────────────────┘    │   │
│   └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Component Roles

### 1. Git Repository (Source of Truth)

| Aspect | Description |
|--------|-------------|
| **Role** | Stores all Kubernetes manifests and Helm charts |
| **Location** | `https://github.com/Talhadmr/dpg-infra-gcp.git` |
| **Branch** | `main` (production) |
| **Contents** | Helm charts, values files, ArgoCD Application definitions |

### 2. Ansible (Infrastructure Automation)

| Aspect | Description |
|--------|-------------|
| **Role** | Prepares cluster for GitOps, installs ArgoCD |
| **When Used** | Initial setup, before ArgoCD takes over |
| **Playbooks** | `ansible/cluster/`, `ansible/argocd/` |

**Ansible's responsibilities:**
- Create Kubernetes namespaces
- Install ArgoCD via Helm
- Apply the bootstrap Application
- Configure HAProxy (edge router)

### 3. ArgoCD (GitOps Controller)

| Aspect | Description |
|--------|-------------|
| **Role** | Continuously syncs Git state to cluster |
| **Namespace** | `argocd` |
| **UI** | `https://localhost:8080` (via port-forward) |

**ArgoCD's responsibilities:**
- Monitor Git repository for changes
- Render Helm templates
- Apply manifests to cluster
- Health checking
- Automatic sync and self-healing

### 4. Helm Charts (Application Packages)

| Aspect | Description |
|--------|-------------|
| **Role** | Package applications with configurable values |
| **Location** | `workloads/` directory |
| **Type** | Wrapper charts (depend on upstream charts) |

---

## App of Apps Pattern

The "App of Apps" pattern is a powerful way to manage multiple ArgoCD Applications from a single root Application.

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                    BOOTSTRAP APPLICATION                        │
│                    (workloads/bootstrap)                        │
│                                                                 │
│   When synced, creates ArgoCD Application resources for:        │
│                                                                 │
│   ┌─────────────┐ ┌─────────────┐ ┌─────────────┐              │
│   │ingress-nginx│ │cert-manager │ │external-sec │  ...         │
│   │ Application │ │ Application │ │ Application │              │
│   └──────┬──────┘ └──────┬──────┘ └──────┬──────┘              │
│          │               │               │                      │
└──────────┼───────────────┼───────────────┼──────────────────────┘
           │               │               │
           ▼               ▼               ▼
    ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
    │   Syncs     │ │   Syncs     │ │   Syncs     │
    │  ingress-   │ │    cert-    │ │  external-  │
    │   nginx     │ │   manager   │ │   secrets   │
    │   chart     │ │    chart    │ │    chart    │
    └─────────────┘ └─────────────┘ └─────────────┘
```

### Bootstrap Chart Structure

```
workloads/bootstrap/
├── Chart.yaml              # Chart metadata
├── values.yaml             # Application definitions
└── templates/
    └── applications.yaml   # Jinja2 template for ArgoCD Applications
```

#### Chart.yaml

```yaml
apiVersion: v2
name: bootstrap
description: Root Application (App of Apps) for GitOps workflow
type: application
version: 1.0.0
```

#### values.yaml (Application Registry)

```yaml
# Git repository settings
spec:
  source:
    repoURL: https://github.com/Talhadmr/dpg-infra-gcp.git
    targetRevision: HEAD

# ArgoCD project
project: default

# Sync policy
syncPolicy:
  automated:
    prune: true      # Delete resources not in Git
    selfHeal: true   # Fix drift automatically

# Applications to deploy
applications:
  - name: ingress-nginx
    namespace: network-mesh
    path: workloads/network-mesh/ingress-nginx
    enabled: true
    syncWave: "1"    # Deploy order

  - name: cert-manager
    namespace: network-mesh
    path: workloads/network-mesh/cert-manager
    enabled: true
    syncWave: "1"

  - name: postgres
    namespace: data-layer
    path: workloads/data-layer/postgres
    enabled: true
    syncWave: "3"
```

#### templates/applications.yaml (Generator)

```yaml
{{- range .Values.applications }}
{{- if .enabled }}
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "{{ .syncWave }}"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: {{ $.Values.project }}
  source:
    repoURL: {{ $.Values.spec.source.repoURL }}
    targetRevision: {{ $.Values.spec.source.targetRevision }}
    path: {{ .path }}
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ .namespace }}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
{{- end }}
{{- end }}
```

### Sync Waves

Sync waves control the order of deployment:

| Wave | Applications | Reason |
|------|--------------|--------|
| 1 | ingress-nginx, cert-manager | Networking foundation |
| 2 | external-secrets, istio | Cluster services |
| 3 | postgres, redis, kafka | Data layer |
| 4 | sonarqube, keycloak | Applications |

---

## Directory Structure

```
workloads/
├── bootstrap/                      # 🔴 ROOT APPLICATION
│   ├── Chart.yaml
│   ├── values.yaml                # Enable/disable apps here
│   └── templates/
│       └── applications.yaml      # Generates ArgoCD Applications
│
├── network-mesh/                   # 🟢 NETWORKING LAYER
│   ├── ingress-nginx/
│   │   ├── Chart.yaml            # Dependencies on upstream chart
│   │   └── values.yaml           # NodePort 30080/30443 config
│   ├── cert-manager/
│   │   ├── Chart.yaml
│   │   └── values.yaml
│   └── istio/
│       ├── Chart.yaml
│       └── values.yaml
│
├── cluster-services/               # 🔵 CLUSTER-WIDE SERVICES
│   ├── external-secrets/
│   │   ├── Chart.yaml
│   │   └── values.yaml
│   └── longhorn/
│       ├── Chart.yaml
│       └── values.yaml
│
├── data-layer/                     # 🟡 DATA SERVICES
│   ├── postgres/
│   │   ├── Chart.yaml
│   │   └── values.yaml
│   ├── redis/
│   │   ├── Chart.yaml
│   │   └── values.yaml
│   └── kafka/
│       ├── Chart.yaml
│       └── values.yaml
│
└── dev-platform/                   # 🟣 DEVELOPER TOOLS
    ├── sonarqube/
    │   ├── Chart.yaml
    │   └── values.yaml
    └── keycloak/
        ├── Chart.yaml
        └── values.yaml
```

---

## Helm Charts

### Wrapper Chart Pattern

We use **wrapper charts** that depend on upstream Helm charts. This allows us to:
- Pin specific versions
- Override default values
- Add custom resources

#### Example: ingress-nginx Chart

**Chart.yaml:**
```yaml
apiVersion: v2
name: ingress-nginx
description: NGINX Ingress Controller with NodePort configuration
type: application
version: 1.0.0
appVersion: "1.9.0"
dependencies:
  - name: ingress-nginx
    version: "4.9.0"
    repository: https://kubernetes.github.io/ingress-nginx
```

**values.yaml:**
```yaml
ingress-nginx:
  controller:
    replicaCount: 2
    
    # CRITICAL: NodePort configuration for HAProxy
    service:
      type: NodePort
      nodePorts:
        http: 30080
        https: 30443
      externalTrafficPolicy: Local

    # Ingress class
    ingressClassResource:
      name: nginx
      default: true

    # Metrics
    metrics:
      enabled: true
```

### Why Wrapper Charts?

| Benefit | Description |
|---------|-------------|
| **Version Control** | Pin exact versions of upstream charts |
| **Customization** | Override defaults without forking |
| **Organization** | Group related configurations |
| **GitOps Ready** | All config in Git |

---

## Ansible Integration

Ansible handles the **initial setup** before GitOps takes over.

### Playbook Structure

```
ansible/
├── cluster/
│   ├── playbook.yml       # Create namespaces
│   └── requirements.yml   # Ansible Galaxy requirements
│
├── argocd/
│   ├── install.yml        # Install ArgoCD via Helm
│   ├── bootstrap.yml      # Apply App of Apps
│   ├── values.yml         # ArgoCD Helm values
│   └── requirements.yml
│
└── haproxy/
    ├── playbook.yml       # Configure edge router
    └── templates/
        └── haproxy.cfg.j2
```

### 1. Namespace Creation (`ansible/cluster/playbook.yml`)

```yaml
- name: Prepare Kubernetes Cluster
  hosts: localhost
  connection: local
  vars:
    namespaces:
      - name: argocd
      - name: monitoring
      - name: data-layer
      - name: network-mesh
      - name: cluster-services
      - name: dev-platform

  tasks:
    - name: Create Kubernetes namespaces
      kubernetes.core.k8s:
        state: present
        definition:
          apiVersion: v1
          kind: Namespace
          metadata:
            name: "{{ item.name }}"
            labels:
              app.kubernetes.io/managed-by: ansible
      loop: "{{ namespaces }}"
```

### 2. ArgoCD Installation (`ansible/argocd/install.yml`)

```yaml
- name: Install ArgoCD via Helm
  hosts: localhost
  connection: local
  vars:
    argocd_namespace: argocd
    argocd_chart_version: "5.51.6"

  tasks:
    - name: Add ArgoCD Helm repository
      kubernetes.core.helm_repository:
        name: argo
        repo_url: https://argoproj.github.io/argo-helm

    - name: Deploy ArgoCD via Helm
      kubernetes.core.helm:
        name: argocd
        chart_ref: argo/argo-cd
        chart_version: "{{ argocd_chart_version }}"
        release_namespace: "{{ argocd_namespace }}"
        wait: true
        values: "{{ lookup('file', 'values.yml') | from_yaml }}"

    - name: Wait for ArgoCD Server to be ready
      kubernetes.core.k8s_info:
        kind: Deployment
        namespace: "{{ argocd_namespace }}"
        name: argocd-server
        wait: true
        wait_condition:
          type: Available
          status: "True"
```

### 3. Bootstrap Application (`ansible/argocd/bootstrap.yml`)

```yaml
- name: Apply Bootstrap Application
  hosts: localhost
  connection: local
  vars:
    git_repo_url: "https://github.com/Talhadmr/dpg-infra-gcp.git"

  tasks:
    - name: Create Bootstrap Application
      kubernetes.core.k8s:
        state: present
        definition:
          apiVersion: argoproj.io/v1alpha1
          kind: Application
          metadata:
            name: bootstrap
            namespace: argocd
          spec:
            project: default
            source:
              repoURL: "{{ git_repo_url }}"
              targetRevision: HEAD
              path: workloads/bootstrap
            destination:
              server: https://kubernetes.default.svc
              namespace: argocd
            syncPolicy:
              automated:
                prune: true
                selfHeal: true
```

---

## ArgoCD Configuration

### Helm Values (`ansible/argocd/values.yml`)

```yaml
# Server configuration
server:
  extraArgs:
    - --insecure  # TLS termination at HAProxy
  
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 256Mi

# Controller configuration
controller:
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi

# Repo Server
repoServer:
  resources:
    limits:
      cpu: 500m
      memory: 512Mi

# ApplicationSet controller (for App of Apps)
applicationSet:
  enabled: true

# Configs
configs:
  cm:
    resource.customizations.ignoreDifferences.all: |
      managedFieldsManagers:
        - kube-controller-manager
```

### Accessing ArgoCD UI

```bash
# Port forward to local machine
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Open browser
open https://localhost:8080
# Username: admin
```

---

## Deployment Workflow

### Initial Setup (One-time)

```bash
# 1. Infrastructure (Terraform)
make apply

# 2. Kubernetes cluster (Kubespray)
make deploy

# 3. Configure kubeconfig
make kubeconfig
export KUBECONFIG=$(pwd)/artifacts/kubeconfig

# 4. GitOps setup (Ansible)
make gitops
```

### What `make gitops` Does

```
make gitops
    │
    ├── make haproxy       # Configure HAProxy edge router
    │
    ├── make namespaces    # Create K8s namespaces (Ansible)
    │   └── argocd, monitoring, data-layer, network-mesh, 
    │       cluster-services, dev-platform
    │
    ├── make argocd        # Install ArgoCD via Helm (Ansible)
    │   └── Deploys ArgoCD components to argocd namespace
    │
    └── make bootstrap     # Apply App of Apps (Ansible)
        └── Creates bootstrap Application in ArgoCD
            │
            └── ArgoCD takes over from here!
                │
                ├── Syncs ingress-nginx
                ├── Syncs cert-manager
                ├── Syncs external-secrets
                ├── Syncs postgres
                ├── Syncs redis
                └── ...
```

### Day-2 Operations (GitOps)

After initial setup, all changes go through Git:

```bash
# 1. Make changes to values.yaml
vim workloads/data-layer/postgres/values.yaml

# 2. Commit and push
git add .
git commit -m "Update postgres replicas to 3"
git push origin main

# 3. ArgoCD automatically syncs (or manual sync)
# Changes appear in cluster within 3 minutes
```

---

## Managing Applications

### Enable/Disable Applications

Edit `workloads/bootstrap/values.yaml`:

```yaml
applications:
  - name: kafka
    enabled: false   # Disabled - won't be deployed

  - name: postgres
    enabled: true    # Enabled - will be deployed
```

### Add New Application

1. Create chart directory:
```bash
mkdir -p workloads/data-layer/mongodb
```

2. Create `Chart.yaml`:
```yaml
apiVersion: v2
name: mongodb
version: 1.0.0
dependencies:
  - name: mongodb
    version: "14.0.0"
    repository: https://charts.bitnami.com/bitnami
```

3. Create `values.yaml`:
```yaml
mongodb:
  auth:
    rootPassword: "changeme"
  persistence:
    size: 10Gi
```

4. Register in bootstrap:
```yaml
# workloads/bootstrap/values.yaml
applications:
  - name: mongodb
    namespace: data-layer
    path: workloads/data-layer/mongodb
    enabled: true
    syncWave: "3"
```

5. Push to Git:
```bash
git add .
git commit -m "Add MongoDB to data layer"
git push
```

### Check Application Status

```bash
# List all applications
kubectl get applications -n argocd

# Describe specific application
kubectl describe application postgres -n argocd

# View sync status
kubectl get applications -n argocd -o custom-columns=\
NAME:.metadata.name,\
SYNC:.status.sync.status,\
HEALTH:.status.health.status
```

---

## Troubleshooting

### Application Stuck in "Syncing"

```bash
# Check application events
kubectl describe application <app-name> -n argocd

# Check repo-server logs
kubectl logs -l app.kubernetes.io/name=argocd-repo-server -n argocd

# Force sync
kubectl -n argocd patch application <app-name> \
  --type merge -p '{"operation":{"sync":{}}}'
```

### "App Path Outside Root" Error

This means the path in Application doesn't match repository structure.

**Wrong:**
```yaml
path: ../../workloads/bootstrap  # Relative paths don't work
```

**Correct:**
```yaml
path: workloads/bootstrap  # Path from repo root
```

### Helm Dependency Not Found

```bash
# Update Helm dependencies locally
cd workloads/network-mesh/ingress-nginx
helm dependency update

# Commit Chart.lock
git add Chart.lock
git commit -m "Update helm dependencies"
git push
```

### ArgoCD Can't Access Git Repository

```bash
# Check repo-server logs
kubectl logs -l app.kubernetes.io/name=argocd-repo-server -n argocd

# Verify repository is public or credentials are configured
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
```

### Application Health Unknown

"Unknown" health is normal for resources without health checks. To add custom health checks:

```yaml
# In ArgoCD ConfigMap
configs:
  cm:
    resource.customizations.health.argoproj.io_Application: |
      hs = {}
      hs.status = "Progressing"
      if obj.status ~= nil then
        if obj.status.health ~= nil then
          hs.status = obj.status.health.status
        end
      end
      return hs
```

---

## Summary

| Component | Role | When Used |
|-----------|------|-----------|
| **Git** | Source of truth | Always |
| **Ansible** | Initial setup | One-time |
| **ArgoCD** | Continuous sync | After setup |
| **Helm** | Package apps | Via ArgoCD |
| **Bootstrap** | App of Apps | Manages all apps |

### GitOps Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                    DEVELOPER WORKFLOW                        │
│                                                             │
│   1. Edit values.yaml ──► 2. git push ──► 3. Automatic     │
│                                              Deployment     │
│                                                             │
│   Rollback? Just: git revert <commit> && git push          │
└─────────────────────────────────────────────────────────────┘
```

GitOps provides a declarative, version-controlled, and automated approach to managing Kubernetes workloads. With ArgoCD and the App of Apps pattern, we achieve:

- ✅ **Single source of truth** (Git)
- ✅ **Automated deployments** (ArgoCD sync)
- ✅ **Self-healing** (drift correction)
- ✅ **Easy rollbacks** (git revert)
- ✅ **Audit trail** (git history)
- ✅ **Scalable management** (App of Apps)

