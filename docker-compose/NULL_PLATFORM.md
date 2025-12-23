# Bonita Deployment on Null Platform - Technical Guide

This document provides guidance for deploying Bonita to Null Platform based on the Docker Compose HA configuration.

## Service Mapping

| Docker Compose Service | Null Platform Component | Notes |
|------------------------|------------------------|-------|
| `postgres` | PostgreSQL / RDS | Use managed RDS for production |
| `bonita-runtime-1` | Application Service | Scalable, stateless |
| `bonita-runtime-2` | Application Service | Scalable, stateless |
| `ui-builder` | Application Service | Single instance typically |
| `ui-proxy` | Application Service | NGINX load balancer |

## Environment Variables

### Bonita Runtime

**Non-Secret Variables**:
```yaml
TZ: "Europe/Paris"
CLUSTER_MODE: "true"
REMOTE_IP_VALVE_ENABLED: "true"
DB_VENDOR: "postgres"
DB_HOST: "postgres"  # Or RDS endpoint
DB_PORT: "5432"
DB_NAME: "bonita"
DB_USER: "bonitauser"
BIZ_DB_NAME: "bizdata"
BIZ_DB_USER: "bizuser"
```

**Secret Variables** (via AWS Secrets Manager with prefix `bonita/`):
- `bonita/db-password` → `DB_PASS`
- `bonita/bdm-db-password` → `BIZ_DB_PASS`
- `bonita/tenant-password` → `BONITA_RUNTIME_ADMIN_PASSWORD`
- `bonita/platform-password` → `PLATFORM_PASSWORD`
- `bonita/monitoring-password` → `MONITORING_PASSWORD`

### UI Builder

```yaml
BONITA_API_URL: "http://bonita-runtime:8080/bonita/API"
BONITA_HEALTHCHECK_USER: "<from-secrets>"
BONITA_HEALTHCHECK_PASSWORD: "<from-secrets>"
BONITA_DEV_MODE: "false"
```

### UI Proxy

```yaml
UIB_HOST: "ui-builder"
UIB_PORT: "80"
NGINX_ACCESS_LOG_ALL: "1"
```

## Resource Allocation

| Service | CPU Request | Memory Request | CPU Limit | Memory Limit |
|---------|-------------|----------------|-----------|--------------|
| bonita-runtime | 2 | 2Gi | 2 | 2Gi |
| ui-builder | 500m | 512Mi | 2 | 4Gi |
| ui-proxy | 500m | 256Mi | 1 | 1Gi |
| postgres | 1 | 2Gi | 2 | 4Gi |

## Health Checks

### Bonita Runtime

**Important**: Health endpoint requires Basic authentication.

```yaml
startupProbe:
  httpGet:
    path: /bonita/healthz
    port: 8080
    httpHeaders:
    - name: Authorization
      value: Basic <base64(monitoring:password)>
  initialDelaySeconds: 120
  periodSeconds: 30
  failureThreshold: 20

livenessProbe:
  httpGet:
    path: /bonita/healthz
    port: 8080
    httpHeaders:
    - name: Authorization
      value: Basic <base64(monitoring:password)>
  periodSeconds: 15
  failureThreshold: 10

readinessProbe:
  httpGet:
    path: /bonita/healthz
    port: 8080
    httpHeaders:
    - name: Authorization
      value: Basic <base64(monitoring:password)>
  periodSeconds: 10
  failureThreshold: 3
```

### UI Builder

```yaml
livenessProbe:
  exec:
    command: ["/bin/sh", "-c", "/opt/appsmith/healthcheck.sh"]
  periodSeconds: 15
  failureThreshold: 10
```

## Networking

### Port Configuration

| Service | Internal Port | External | Protocol |
|---------|--------------|----------|----------|
| ui-proxy | 80 | Yes | HTTP |
| bonita-runtime | 8080 | No | HTTP |
| bonita-runtime | 5701 | No | TCP (Hazelcast) |
| ui-builder | 80 | No | HTTP |
| postgres | 5432 | No | TCP |

### Service Names (Internal DNS)

Services communicate using Kubernetes/Null Platform DNS:
- `bonita-runtime` or `bonita-runtime-1`, `bonita-runtime-2`
- `ui-builder`
- `postgres` or RDS endpoint

## Scaling

### Horizontal Pod Autoscaling

**Bonita Runtime** (when CLUSTER_MODE=true):
```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 80
```

### Spot Instance Compatibility

All Bonita services are compatible with spot instances:
- Stateless design (state in database)
- Hazelcast clustering handles node rotation
- Health checks handle pod restarts gracefully

## Volumes

### License File

Mount via Kubernetes Secret:
```bash
kubectl create secret generic bonita-license \
  --from-file=license.lic=/path/to/license.lic \
  -n bonita
```

```yaml
volumeMounts:
- name: license
  mountPath: /opt/bonita_lic/license.lic
  subPath: license.lic
  readOnly: true

volumes:
- name: license
  secret:
    secretName: bonita-license
```

## Known Issues

### Health Check Returns 401

The Bonita health endpoint `/bonita/healthz` requires authentication. Kubernetes probes must include Authorization header. In Docker Compose, this causes "unhealthy" status which can be ignored.

### Line Endings

If using Windows for development, ensure shell scripts have Unix line endings (LF not CRLF) before building containers.

## Deployment Workflow

1. **Create namespace**: `kubectl create namespace bonita`
2. **Configure secrets** (AWS Secrets Manager integration)
3. **Deploy PostgreSQL** or configure RDS connection
4. **Deploy Bonita Runtime** (multiple replicas)
5. **Deploy UI Builder** (single replica)
6. **Deploy UI Proxy** (ingress point)
7. **Configure Ingress/Load Balancer** for external access

## Verification

```bash
# Check all pods
kubectl get pods -n bonita

# Check logs
kubectl logs -f deployment/bonita-runtime -n bonita

# Verify cluster
kubectl logs deployment/bonita-runtime -n bonita | grep "Cluster mode:"
```

---

**Last Updated**: December 2024
