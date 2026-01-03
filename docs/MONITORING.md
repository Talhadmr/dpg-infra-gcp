# Monitoring Stack - Prometheus & Grafana

This guide explains how to deploy and configure the monitoring stack using Prometheus and Grafana.

## Overview

The monitoring stack consists of:
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Alertmanager**: Alert routing and notification
- **Node Exporter**: Node-level metrics
- **Kube State Metrics**: Kubernetes cluster metrics

## Architecture

```
┌─────────────┐
│  Prometheus │ ◄─── Metrics from cluster
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Grafana   │ ◄─── Visualizes Prometheus data
└─────────────┘
```

## Prerequisites

1. Kubernetes cluster running
2. ArgoCD installed and configured
3. `observability` namespace created

## Deployment

### Step 1: Enable Monitoring Stack

```bash
# Enable Prometheus and Grafana
make enable-monitoring

# Or enable everything (monitoring + logging)
make observability
```

### Step 2: Update Helm Dependencies

```bash
make helm-deps
```

This will download the required Helm charts:
- `kube-prometheus-stack` for Prometheus
- `grafana` chart for Grafana

### Step 3: Deploy via ArgoCD

```bash
# Push changes to git repository
git add workloads/bootstrap/values.yaml
git commit -m "Enable monitoring stack"
git push

# Apply bootstrap (or wait for ArgoCD auto-sync)
make bootstrap
```

### Step 4: Verify Deployment

```bash
# Check Prometheus
kubectl get pods -n observability -l app.kubernetes.io/name=prometheus

# Check Grafana
kubectl get pods -n observability -l app.kubernetes.io/name=grafana

# Check all monitoring components
kubectl get all -n observability
```

## Accessing Services

### Prometheus UI

```bash
# Port forward
kubectl port-forward svc/kube-prometheus-stack-prometheus -n observability 9090:9090

# Open browser
open http://localhost:9090
```

### Grafana UI

```bash
# Port forward
kubectl port-forward svc/grafana -n observability 3000:80

# Open browser
open http://localhost:3000

# Default credentials
# Username: admin
# Password: admin (change in production!)
```

**Important**: Change the default Grafana password after first login!

## Configuration

### Prometheus Configuration

Edit `workloads/observability/prometheus/values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    retention: 30d  # How long to keep metrics
    storageSpec:
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: 50Gi  # Adjust based on needs
```

### Grafana Configuration

Edit `workloads/observability/grafana/values.yaml`:

```yaml
adminUser: admin
adminPassword: your-secure-password  # Change this!

# Add datasources
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://kube-prometheus-stack-prometheus.observability:9090
        isDefault: true
```

### Enable Ingress (Production)

For production, enable Ingress:

```yaml
# Grafana ingress
ingress:
  enabled: true
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - grafana.yourdomain.com
  tls:
    - secretName: grafana-tls
      hosts:
        - grafana.yourdomain.com
```

## Default Dashboards

The `kube-prometheus-stack` includes pre-configured dashboards for:
- Kubernetes Cluster Overview
- Node Exporter Metrics
- Pod Metrics
- Deployment Metrics
- Service Metrics

These are automatically imported into Grafana.

## Alerting

### Alertmanager Configuration

Alertmanager is included in the Prometheus stack. Configure alerts in `workloads/observability/prometheus/values.yaml`:

```yaml
alertmanager:
  enabled: true
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: 10Gi
```

### Access Alertmanager

```bash
kubectl port-forward svc/kube-prometheus-stack-alertmanager -n observability 9093:9093
open http://localhost:9093
```

## Resource Requirements

### Minimum Requirements

- **Prometheus**: 500m CPU, 2Gi Memory, 50Gi Storage
- **Grafana**: 100m CPU, 128Mi Memory, 10Gi Storage
- **Alertmanager**: 100m CPU, 256Mi Memory, 10Gi Storage

### Production Recommendations

- **Prometheus**: 2000m CPU, 4Gi Memory, 200Gi+ Storage
- **Grafana**: 500m CPU, 512Mi Memory, 20Gi Storage
- **Alertmanager**: 500m CPU, 512Mi Memory, 20Gi Storage

## Troubleshooting

### Prometheus Not Collecting Metrics

```bash
# Check Prometheus targets
kubectl port-forward svc/kube-prometheus-stack-prometheus -n observability 9090:9090
# Navigate to Status > Targets in Prometheus UI

# Check ServiceMonitors
kubectl get servicemonitors -n observability

# Check Prometheus logs
kubectl logs -n observability -l app.kubernetes.io/name=prometheus
```

### Grafana Cannot Connect to Prometheus

```bash
# Verify Prometheus service
kubectl get svc -n observability | grep prometheus

# Check Grafana datasource configuration
kubectl get configmap grafana -n observability -o yaml
```

### Storage Issues

```bash
# Check PVC status
kubectl get pvc -n observability

# Check storage class
kubectl get storageclass
```

## Monitoring Custom Applications

To monitor your applications:

1. **Create ServiceMonitor**:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: observability
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      path: /metrics
```

2. **Add Prometheus annotations** to your Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

## Best Practices

1. **Retention Policy**: Set appropriate retention based on storage capacity
2. **Resource Limits**: Always set resource limits to prevent resource exhaustion
3. **Security**: Change default passwords, enable TLS in production
4. **Backup**: Regularly backup Grafana dashboards and Prometheus data
5. **Scaling**: Monitor Prometheus resource usage and scale as needed

## Additional Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [kube-prometheus-stack Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)

