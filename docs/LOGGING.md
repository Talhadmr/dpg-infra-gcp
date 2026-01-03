# Logging Stack - ELK (Elasticsearch, Logstash, Kibana)

This guide explains how to deploy and configure the ELK stack for centralized logging.

## Overview

The ELK stack consists of:
- **Elasticsearch**: Log storage and search engine
- **Logstash**: Log processing and transformation
- **Kibana**: Log visualization and analysis

## Architecture

```
┌─────────────┐
│  Logstash   │ ◄─── Receives logs from Beats/Fluentd
└──────┬──────┘
       │
       ▼
┌─────────────┐
│Elasticsearch│ ◄─── Stores processed logs
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Kibana    │ ◄─── Visualizes and searches logs
└─────────────┘
```

## Prerequisites

1. Kubernetes cluster running
2. ArgoCD installed and configured
3. `observability` namespace created
4. Sufficient storage for Elasticsearch (recommended: 50Gi+)

## Deployment

### Step 1: Enable Logging Stack

```bash
# Enable ELK Stack
make enable-logging

# Or enable everything (monitoring + logging)
make observability
```

### Step 2: Update Helm Dependencies

```bash
make helm-deps
```

This will download the required Helm charts:
- `elasticsearch` chart
- `logstash` chart
- `kibana` chart

### Step 3: Deploy via ArgoCD

```bash
# Push changes to git repository
git add workloads/bootstrap/values.yaml
git commit -m "Enable ELK stack"
git push

# Apply bootstrap (or wait for ArgoCD auto-sync)
make bootstrap
```

### Step 4: Verify Deployment

```bash
# Check Elasticsearch
kubectl get pods -n observability -l app=elasticsearch-master

# Check Logstash
kubectl get pods -n observability -l app=logstash

# Check Kibana
kubectl get pods -n observability -l app=kibana

# Check all logging components
kubectl get all -n observability
```

## Accessing Services

### Elasticsearch API

```bash
# Port forward
kubectl port-forward svc/elasticsearch-master -n observability 9200:9200

# Test connection
curl http://localhost:9200

# Check cluster health
curl http://localhost:9200/_cluster/health
```

### Kibana UI

```bash
# Port forward
kubectl port-forward svc/kibana-kibana -n observability 5601:5601

# Open browser
open http://localhost:5601
```

**Note**: On first access, Kibana may take a few minutes to initialize.

## Configuration

### Elasticsearch Configuration

Edit `workloads/observability/elasticsearch/values.yaml`:

```yaml
# Cluster configuration
clusterName: "elasticsearch"
replicas: 1  # Increase for production

# Resources
resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 2000m
    memory: 4Gi

# Storage
volumeClaimTemplate:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 50Gi  # Adjust based on log volume
```

### Logstash Configuration

Edit `workloads/observability/logstash/values.yaml`:

```yaml
# Pipeline configuration
logstashPipeline:
  logstash.conf: |
    input {
      beats {
        port => 5044
      }
      # Add other inputs as needed
    }
    filter {
      # Add filters for log parsing
      if [fields][log_type] == "application" {
        grok {
          match => { "message" => "%{TIMESTAMP_ISO8601:timestamp} %{LOGLEVEL:level} %{GREEDYDATA:message}" }
        }
      }
    }
    output {
      elasticsearch {
        hosts => ["elasticsearch-master:9200"]
        index => "logs-%{+YYYY.MM.dd}"
      }
    }
```

### Kibana Configuration

Edit `workloads/observability/kibana/values.yaml`:

```yaml
# Elasticsearch connection
elasticsearchHosts: "http://elasticsearch-master:9200"

# Resources
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1000m
    memory: 2Gi
```

### Enable Ingress (Production)

For production, enable Ingress:

```yaml
# Kibana ingress
ingress:
  enabled: true
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - kibana.yourdomain.com
  tls:
    - secretName: kibana-tls
      hosts:
        - kibana.yourdomain.com
```

## Collecting Logs

### Option 1: Filebeat (Recommended)

Deploy Filebeat as DaemonSet to collect logs from all nodes:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: filebeat
  namespace: observability
spec:
  selector:
    matchLabels:
      app: filebeat
  template:
    metadata:
      labels:
        app: filebeat
    spec:
      containers:
      - name: filebeat
        image: docker.elastic.co/beats/filebeat:8.11.0
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
```

### Option 2: Fluentd

Deploy Fluentd as DaemonSet:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: observability
spec:
  selector:
    matchLabels:
      app: fluentd
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1-debian-elasticsearch
        env:
        - name: FLUENT_ELASTICSEARCH_HOST
          value: "elasticsearch-master.observability.svc.cluster.local"
        - name: FLUENT_ELASTICSEARCH_PORT
          value: "9200"
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
```

### Option 3: Application Logs

For application-specific logs, configure your applications to send logs directly to Logstash:

```yaml
# In your application deployment
env:
- name: LOGSTASH_HOST
  value: "logstash.observability.svc.cluster.local"
- name: LOGSTASH_PORT
  value: "5044"
```

## Creating Index Patterns in Kibana

1. Open Kibana UI
2. Go to **Management** > **Stack Management** > **Index Patterns**
3. Click **Create index pattern**
4. Enter pattern: `logs-*`
5. Select time field: `@timestamp`
6. Click **Create index pattern**

## Resource Requirements

### Minimum Requirements

- **Elasticsearch**: 1000m CPU, 2Gi Memory, 50Gi Storage
- **Logstash**: 500m CPU, 1Gi Memory
- **Kibana**: 500m CPU, 1Gi Memory

### Production Recommendations

- **Elasticsearch**: 2000m CPU, 4Gi Memory, 200Gi+ Storage (per node)
- **Logstash**: 1000m CPU, 2Gi Memory (scale horizontally)
- **Kibana**: 1000m CPU, 2Gi Memory

## Troubleshooting

### Elasticsearch Not Starting

```bash
# Check Elasticsearch logs
kubectl logs -n observability -l app=elasticsearch-master

# Check PVC status
kubectl get pvc -n observability

# Check resource usage
kubectl top pods -n observability
```

### Logstash Not Receiving Logs

```bash
# Check Logstash logs
kubectl logs -n observability -l app=logstash

# Verify Logstash service
kubectl get svc -n observability | grep logstash

# Test connection from a pod
kubectl run -it --rm test --image=curlimages/curl --restart=Never -- \
  curl logstash.observability.svc.cluster.local:5044
```

### Kibana Cannot Connect to Elasticsearch

```bash
# Verify Elasticsearch service
kubectl get svc -n observability | grep elasticsearch

# Check Elasticsearch health
kubectl port-forward svc/elasticsearch-master -n observability 9200:9200
curl http://localhost:9200/_cluster/health

# Check Kibana logs
kubectl logs -n observability -l app=kibana
```

### High Storage Usage

```bash
# Check index sizes
kubectl port-forward svc/elasticsearch-master -n observability 9200:9200
curl http://localhost:9200/_cat/indices?v

# Set up index lifecycle management
# Configure in Elasticsearch to automatically delete old indices
```

## Index Lifecycle Management

To manage log retention and prevent storage issues:

1. **Create Index Lifecycle Policy**:

```bash
curl -X PUT "localhost:9200/_ilm/policy/logs-policy" -H 'Content-Type: application/json' -d'
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "50GB",
            "max_age": "7d"
          }
        }
      },
      "delete": {
        "min_age": "30d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}'
```

2. **Apply to index template**:

```bash
curl -X PUT "localhost:9200/_index_template/logs-template" -H 'Content-Type: application/json' -d'
{
  "index_patterns": ["logs-*"],
  "template": {
    "settings": {
      "index.lifecycle.name": "logs-policy"
    }
  }
}'
```

## Best Practices

1. **Storage Planning**: Estimate log volume and plan storage accordingly
2. **Index Rotation**: Set up index lifecycle management to prevent storage exhaustion
3. **Resource Limits**: Always set resource limits
4. **Security**: Enable Elasticsearch security in production
5. **Backup**: Regularly backup Elasticsearch indices
6. **Monitoring**: Monitor Elasticsearch cluster health and performance
7. **Scaling**: Scale Elasticsearch horizontally for high log volumes

## Additional Resources

- [Elasticsearch Documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
- [Logstash Documentation](https://www.elastic.co/guide/en/logstash/current/index.html)
- [Kibana Documentation](https://www.elastic.co/guide/en/kibana/current/index.html)
- [Filebeat Documentation](https://www.elastic.co/guide/en/beats/filebeat/current/index.html)

