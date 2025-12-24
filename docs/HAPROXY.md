# HAProxy - Edge Router & Load Balancer

This document explains the HAProxy implementation in our Kubernetes infrastructure project.

## Table of Contents

1. [Why HAProxy?](#why-haproxy)
2. [Architecture](#architecture)
3. [Installation Location](#installation-location)
4. [Configuration Details](#configuration-details)
5. [Traffic Flow](#traffic-flow)
6. [Deployment](#deployment)
7. [Monitoring](#monitoring)
8. [Troubleshooting](#troubleshooting)

---

## Why HAProxy?

### The Problem

Our Kubernetes cluster runs on GCP with the following constraints:

1. **No Public IPs on Cluster Nodes**: For security, only the bastion host has a public IP. Master and worker nodes are private.

2. **No Cloud Load Balancer**: We're not using GKE, so we don't have access to GCP's native LoadBalancer service type.

3. **MetalLB Limitations**: MetalLB requires Layer 2 or BGP networking capabilities that aren't available in standard GCP VPCs.

4. **Need External Access**: We need to expose:
   - Kubernetes API (port 6443) for `kubectl` access
   - HTTP/HTTPS traffic (ports 80/443) for web applications via Ingress

### The Solution: HAProxy as Edge Router

HAProxy on the bastion host acts as an **edge router** that:
- Receives all external traffic on the bastion's public IP
- Load balances traffic to appropriate backend servers
- Provides health checking and automatic failover

```
┌─────────────────────────────────────────────────────────────┐
│                     INTERNET                                │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                BASTION (HAProxy)                            │
│                Public IP: 34.x.x.x                          │
│                                                             │
│   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐    │
│   │ :6443   │   │  :80    │   │  :443   │   │  :8404  │    │
│   │ K8s API │   │  HTTP   │   │  HTTPS  │   │  Stats  │    │
│   └────┬────┘   └────┬────┘   └────┬────┘   └─────────┘    │
└────────┼─────────────┼─────────────┼────────────────────────┘
         │             │             │
         ▼             ▼             ▼
    ┌─────────┐   ┌─────────┐   ┌─────────┐
    │ Masters │   │ Workers │   │ Workers │
    │  :6443  │   │ :30080  │   │ :30443  │
    └─────────┘   └─────────┘   └─────────┘
```

---

## Architecture

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| HAProxy | Bastion VM | Load balancer & reverse proxy |
| Ansible Playbook | `ansible/haproxy/` | Automated deployment |
| Jinja2 Template | `ansible/haproxy/templates/` | Dynamic configuration |

### Why Bastion?

The bastion host is the ideal location for HAProxy because:

1. **Single Point of Entry**: It's the only VM with a public IP
2. **Security**: Acts as a DMZ between internet and private network
3. **Simplicity**: No additional infrastructure needed
4. **Cost**: No extra VM or cloud load balancer costs

---

## Installation Location

### File Structure

```
ansible/
└── haproxy/
    ├── playbook.yml              # Ansible playbook
    └── templates/
        └── haproxy.cfg.j2        # HAProxy configuration template
```

### Terraform Firewall Rules

HAProxy requires specific firewall rules (defined in `terraform/modules/vpc/main.tf`):

```hcl
# Allow K8s API access (port 6443)
resource "google_compute_firewall" "allow_k8s_api" {
  name          = "allow-k8s-api"
  network       = google_compute_network.vpc.name
  source_ranges = ["0.0.0.0/0"]  # TODO: Restrict to specific IPs
  target_tags   = ["bastion"]
  
  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}

# Allow HTTP/HTTPS Ingress (ports 80, 443)
resource "google_compute_firewall" "allow_ingress_http" {
  name          = "allow-ingress-http"
  network       = google_compute_network.vpc.name
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["bastion"]
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

# Allow HAProxy Stats (port 8404)
resource "google_compute_firewall" "allow_haproxy_stats" {
  name          = "allow-haproxy-stats"
  network       = google_compute_network.vpc.name
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["bastion"]
  
  allow {
    protocol = "tcp"
    ports    = ["8404"]
  }
}
```

---

## Configuration Details

### HAProxy Configuration Template

The configuration is generated from a Jinja2 template that dynamically includes backend servers from Ansible inventory.

#### Global Settings

```
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    user haproxy
    group haproxy
    daemon

    # TLS settings (modern security)
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
```

#### Default Settings

```
defaults
    log     global
    mode    tcp              # Layer 4 (TCP) mode for all frontends
    option  tcplog
    option  dontlognull
    timeout connect 5000     # 5 seconds to connect
    timeout client  50000    # 50 seconds client timeout
    timeout server  50000    # 50 seconds server timeout
```

### Frontend/Backend Definitions

#### 1. Kubernetes API (Port 6443)

```
frontend kubernetes_api
    bind *:6443
    mode tcp
    default_backend kubernetes_masters

backend kubernetes_masters
    mode tcp
    balance roundrobin
    option tcp-check
    server master-01 10.10.10.x:6443 check fall 3 rise 2
    server master-02 10.10.10.x:6443 check fall 3 rise 2
    server master-03 10.10.10.x:6443 check fall 3 rise 2
```

**Purpose**: Allows `kubectl` commands from local machine to reach the K8s API.

#### 2. HTTP Ingress (Port 80 → NodePort 30080)

```
frontend http_ingress
    bind *:80
    mode tcp
    default_backend ingress_http

backend ingress_http
    mode tcp
    balance roundrobin
    option tcp-check
    server worker-01 10.10.10.x:30080 check fall 3 rise 2
    server worker-02 10.10.10.x:30080 check fall 3 rise 2
```

**Purpose**: Routes HTTP traffic to NGINX Ingress Controller running on worker nodes.

#### 3. HTTPS Ingress (Port 443 → NodePort 30443)

```
frontend https_ingress
    bind *:443
    mode tcp
    default_backend ingress_https

backend ingress_https
    mode tcp
    balance roundrobin
    option tcp-check
    server worker-01 10.10.10.x:30443 check fall 3 rise 2
    server worker-02 10.10.10.x:30443 check fall 3 rise 2
```

**Purpose**: Routes HTTPS traffic (TLS passthrough) to NGINX Ingress Controller.

#### 4. Stats Dashboard (Port 8404)

```
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if LOCALHOST
```

**Purpose**: Provides a web UI for monitoring HAProxy health and statistics.

### Health Check Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `check` | enabled | Enable health checks |
| `fall 3` | 3 failures | Mark server as down after 3 failed checks |
| `rise 2` | 2 successes | Mark server as up after 2 successful checks |

---

## Traffic Flow

### Kubernetes API Access

```
Developer's Machine
        │
        │ kubectl get pods
        ▼
┌───────────────────┐
│ Bastion:6443      │
│ (HAProxy)         │
└─────────┬─────────┘
          │ roundrobin
          ▼
┌─────────────────────────────────┐
│  master-01:6443  ◄──┐           │
│  master-02:6443  ◄──┼── K8s API │
│  master-03:6443  ◄──┘           │
└─────────────────────────────────┘
```

### Web Application Access

```
User Browser
        │
        │ https://myapp.example.com
        ▼
┌───────────────────┐
│ Bastion:443       │
│ (HAProxy)         │
└─────────┬─────────┘
          │ roundrobin
          ▼
┌─────────────────────────────────┐
│  worker-01:30443 ◄──┐           │
│  worker-02:30443 ◄──┴── NGINX   │
│                       Ingress   │
└─────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────┐
│  Kubernetes Services            │
│  (based on Ingress rules)       │
└─────────────────────────────────┘
```

---

## Deployment

### Using Makefile

```bash
# Deploy or update HAProxy configuration
make haproxy
```

### Manual Deployment

```bash
# Run the Ansible playbook
ansible-playbook -i ansible/inventory/inventory.ini \
    ansible/haproxy/playbook.yml \
    --become --become-user=root
```

### What the Playbook Does

1. **Installs HAProxy** via apt package manager
2. **Generates Configuration** from Jinja2 template using inventory data
3. **Validates Configuration** before applying
4. **Restarts HAProxy** service

```yaml
# ansible/haproxy/playbook.yml
- name: Install and Configure HAProxy on Bastion
  hosts: bastion
  become: true
  vars:
    haproxy_stats_port: 8404
    haproxy_api_port: 6443

  tasks:
    - name: Install HAProxy
      ansible.builtin.apt:
        name: haproxy
        state: present
        update_cache: true

    - name: Create HAProxy configuration
      ansible.builtin.template:
        src: templates/haproxy.cfg.j2
        dest: /etc/haproxy/haproxy.cfg
        validate: haproxy -c -f %s  # Validate before applying
      notify: Restart HAProxy

    - name: Ensure HAProxy is enabled and started
      ansible.builtin.systemd:
        name: haproxy
        enabled: true
        state: started

  handlers:
    - name: Restart HAProxy
      ansible.builtin.systemd:
        name: haproxy
        state: restarted
```

---

## Monitoring

### Stats Dashboard

Access the HAProxy stats dashboard at:

```
http://<bastion-public-ip>:8404/stats
```

### Dashboard Features

- **Backend Health**: Green (UP), Red (DOWN), Yellow (transitioning)
- **Connection Stats**: Current, total, and max connections
- **Traffic Stats**: Bytes in/out, request rate
- **Response Times**: Average, max response times
- **Error Rates**: 4xx, 5xx errors per backend

### Command Line Monitoring

```bash
# SSH to bastion
make ssh-bastion

# Check HAProxy status
sudo systemctl status haproxy

# View HAProxy logs
sudo journalctl -u haproxy -f

# Check socket stats
echo "show stat" | sudo socat stdio /run/haproxy/admin.sock
```

---

## Troubleshooting

### Common Issues

#### 1. HAProxy Won't Start

```bash
# Check configuration syntax
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

# Check for port conflicts
sudo netstat -tlnp | grep -E '6443|80|443|8404'
```

#### 2. Backend Servers Marked as DOWN

```bash
# Check if backend is reachable from bastion
nc -zv <master-ip> 6443
nc -zv <worker-ip> 30080

# Check HAProxy logs
sudo journalctl -u haproxy | grep -i "down\|error"
```

#### 3. Connection Timeout

```bash
# Verify firewall rules
gcloud compute firewall-rules list --filter="name~haproxy OR name~k8s-api"

# Check internal firewall on bastion
sudo iptables -L -n
```

#### 4. TLS Certificate Errors (K8s API)

If you see certificate errors when using `kubectl`:

```bash
# Regenerate K8s API certificates to include bastion IP
make renew-certs

# Then update HAProxy
make haproxy
```

### Useful Commands

```bash
# Reload HAProxy without dropping connections
sudo systemctl reload haproxy

# Check backend health
echo "show servers state" | sudo socat stdio /run/haproxy/admin.sock

# Disable a backend server for maintenance
echo "disable server kubernetes_masters/master-01" | sudo socat stdio /run/haproxy/admin.sock

# Re-enable a backend server
echo "enable server kubernetes_masters/master-01" | sudo socat stdio /run/haproxy/admin.sock
```

---

## Security Considerations

### Current State (Development)

- All ports are open to `0.0.0.0/0`
- Stats page has no authentication

### Production Recommendations

1. **IP Whitelisting**: Restrict `source_ranges` in firewall rules
2. **Stats Authentication**: Add username/password to stats page
3. **TLS on Stats**: Enable HTTPS for stats dashboard
4. **Rate Limiting**: Add rate limiting for DDoS protection
5. **Logging**: Enable detailed logging for audit trails

### Example: Securing Stats Page

```
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats auth admin:YourSecurePassword123!  # Add authentication
    stats admin if LOCALHOST
```

---

## Summary

| Feature | Implementation |
|---------|----------------|
| **Load Balancing** | Roundrobin across backends |
| **Health Checks** | TCP checks every 2 seconds |
| **Failover** | Automatic (3 failures = down) |
| **Protocol** | Layer 4 TCP (TLS passthrough) |
| **Monitoring** | Stats dashboard on port 8404 |
| **Configuration** | Ansible + Jinja2 templates |

HAProxy provides a simple, reliable, and cost-effective solution for exposing our private Kubernetes cluster to the internet without requiring cloud-native load balancers or complex networking setups.

