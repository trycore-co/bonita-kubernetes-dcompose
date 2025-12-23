# Bonita Deployment on Null Platform - Technical Guide

This document provides specific guidance for deploying Bonita to Null Platform based on the requirements discussed in the infrastructure meeting.

## Executive Summary

The Docker Compose configuration in this directory serves as the foundation for Null Platform deployment. Null Platform will translate each service definition into its native deployment format, handling the Dockerfile build, environment variables, and service orchestration automatically.

## Architecture Translation

### Service Mapping

| Docker Compose Service | Null Platform Component | Notes |
|------------------------|------------------------|-------|
| `postgres` | PostgreSQL Instance | Can be replaced with managed RDS PostgreSQL |
| `bonita-runtime` | Application Service | Main BPM engine, scalable |
| `ui-builder` | Application Service | UI development tool |
| `ui-proxy` | Application Service | NGINX reverse proxy, entry point |

### Service Dependencies

```
ui-proxy (port 80)
    ├── bonita-runtime:8080 (Bonita API)
    └── ui-builder:80 (UI Builder)
            └── bonita-runtime:8080 (API dependency)

bonita-runtime:8080
    └── postgres:5432 (Database)
```

## Null Platform Deployment Steps

### 1. Repository Setup

Create a Git repository containing:
```
bonita-deployment/
├── Dockerfile.bonita-runtime    # FROM bonitasoft.jfrog.io/docker/bonita-subscription:10.2.3
├── Dockerfile.ui-builder        # FROM bonitasoft.jfrog.io/docker/bonita-ui-builder:1.3.0
├── Dockerfile.ui-proxy          # FROM bonitasoft.jfrog.io/docker/bonita-ui-proxy:1.3.0
└── deployment-config.yaml       # Nule-specific configuration (if needed)
```

Example Dockerfile (bonita-runtime):
```dockerfile
FROM bonitasoft.jfrog.io/docker/bonita-subscription:10.2.3

# Optional: Add customizations
# COPY custom-init-scripts/ /opt/custom-init.d/
# COPY license.lic /opt/bonita_lic/license.lic

# Keep original entrypoint
# ENTRYPOINT ["/opt/files/startup.sh"]
```

### 2. Image Registry Configuration

Configure Docker registry credentials in Null Platform:

**Registry**: `bonitasoft.jfrog.io`
- **Username**: `<provided-by-bonita-team>`
- **Password/Token**: `<provided-by-bonita-team>`

Create imagePullSecret named: `bonita-registry-secret`

### 3. Environment Variable Configuration

#### Bonita Runtime Service

Configure in Null Platform application settings:

**Database Configuration (Non-Secret)**
```yaml
TZ: "Europe/Paris"
CLUSTER_MODE: "true"  # Enable for production multi-instance
REMOTE_IP_VALVE_ENABLED: "true"
DB_VENDOR: "postgres"
DB_HOST: "postgres"  # Or RDS endpoint
DB_PORT: "5432"
DB_NAME: "bonita"
DB_USER: "bonitauser"
BIZ_DB_NAME: "bizdata"
BIZ_DB_USER: "bizuser"
```

**Database Configuration (Secret) - Via AWS Secrets Manager**

Create secrets with prefix `bonita/`:
- `bonita/db-password` → Maps to `DB_PASS`
- `bonita/bdm-db-password` → Maps to `BIZ_DB_PASS`

**Credentials (Secret) - Via AWS Secrets Manager**
- `bonita/tenant-username` → Maps to `BONITA_RUNTIME_ADMIN_USERNAME`
- `bonita/tenant-password` → Maps to `BONITA_RUNTIME_ADMIN_PASSWORD`
- `bonita/platform-username` → Maps to `PLATFORM_LOGIN`
- `bonita/platform-password` → Maps to `PLATFORM_PASSWORD`
- `bonita/monitoring-username` → Maps to `MONITORING_USERNAME`
- `bonita/monitoring-password` → Maps to `MONITORING_PASSWORD`

**Connection Pool Settings**
```yaml
BONITA_DS_CONNECTION_POOL_INITIAL_SIZE: "2"
BONITA_DS_CONNECTION_POOL_MAX_TOTAL: "10"
BONITA_DS_CONNECTION_POOL_MIN_IDLE: "2"
BONITA_DS_CONNECTION_POOL_MAX_IDLE: "10"
BDM_DS_CONNECTION_POOL_INITIAL_SIZE: "1"
BDM_DS_CONNECTION_POOL_MAX_TOTAL: "5"
BDM_DS_CONNECTION_POOL_MIN_IDLE: "1"
BDM_DS_CONNECTION_POOL_MAX_IDLE: "5"
```

**Session Configuration**
```yaml
BONITA_RUNTIME_SESSION_DURATION: "3600000"  # 1 hour in milliseconds
BONITA_RUNTIME_CLUSTER_HTTP_SESSION_TIMEOUT: "3600"  # 1 hour in seconds
```

**Logging**
```yaml
ACCESSLOGS_STDOUT_ENABLED: "true"
ACCESSLOGS_FILES_ENABLED: "false"
```

**JVM Options**
```yaml
JAVA_OPTS: "-Djava.awt.headless=true -XX:+UseContainerSupport -XX:InitialRAMPercentage=60 -XX:MaxRAMPercentage=60 -XX:MinRAMPercentage=60 -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/opt/bonita_run/${HOSTNAME}.hprof -XX:+UseG1GC -XX:+UseStringDeduplication -XX:MaxGCPauseMillis=500 -XX:InitiatingHeapOccupancyPercent=45 -Dbonita.client.home=/opt/bonita_lic -Dbonita.csrf.cookie.path=/"
```

**Performance Tuning**
```yaml
BONITA_PLATFORM_PERSISTENCE_USE_SECOND_LEVEL_CACHE: "false"
HTTP_MAX_THREADS: ""  # Leave empty for default, or set based on load testing
```

#### UI Builder Service

```yaml
BONITA_API_URL: "http://bonita-runtime:8080/bonita/API"
BONITA_HEALTHCHECK_USER: "<from-secrets>"
BONITA_HEALTHCHECK_PASSWORD: "<from-secrets>"
BONITA_DEV_MODE: "false"
LOGGING_LEVEL_ROOT: "info"
LOGGING_LEVEL_COM_APPSMITH: "info"
LOGGING_LEVEL_COM_BONITASOFT: "info"
LOGGING_LEVEL_COM_EXTERNAL_PLUGINS: "info"
LOGGING_PATTERN_CONSOLE: "%msg"
```

#### UI Proxy Service

```yaml
BONITA_HOST: "bonita-runtime"
BONITA_PORT: "8080"
UIB_HOST: "ui-builder"
UIB_PORT: "80"
NGINX_ACCESS_LOG_ALL: "1"
NGINX_ERROR_LOG_LEVEL: "error"
```

### 4. AWS Secrets Manager Integration

#### IAM Role Configuration

Create IAM role for Kubernetes service accounts with policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:bonita/*"
    }
  ]
}
```

#### Secret Creation

Create secrets via AWS CLI or console:

```bash
# Database passwords
aws secretsmanager create-secret \
  --name bonita/db-password \
  --secret-string "mySecureDbPassword"

aws secretsmanager create-secret \
  --name bonita/bdm-db-password \
  --secret-string "mySecureBdmPassword"

# Credentials
aws secretsmanager create-secret \
  --name bonita/tenant-password \
  --secret-string "mySecureAdminPassword"

aws secretsmanager create-secret \
  --name bonita/platform-password \
  --secret-string "mySecurePlatformPassword"

aws secretsmanager create-secret \
  --name bonita/monitoring-password \
  --secret-string "mySecureMonitoringPassword"
```

#### Secret Rotation

For password rotation:
1. Update secret in AWS Secrets Manager
2. Secrets are read at container startup
3. Restart Bonita pods to pick up new secrets:
   ```bash
   kubectl rollout restart deployment/bonita-runtime -n bonita
   ```

### 5. Resource Allocation

#### Recommended Resources

**Bonita Runtime (Production)**
```yaml
resources:
  requests:
    cpu: "2"
    memory: "2Gi"
  limits:
    cpu: "2"
    memory: "2Gi"
```

**UI Builder (Production)**
```yaml
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    cpu: "2"
    memory: "4Gi"
```

**UI Proxy**
```yaml
resources:
  requests:
    cpu: "500m"
    memory: "256Mi"
  limits:
    cpu: "1"
    memory: "1Gi"
```

**PostgreSQL** (if not using RDS)
```yaml
resources:
  requests:
    cpu: "1"
    memory: "2Gi"
  limits:
    cpu: "2"
    memory: "4Gi"
```

### 6. Health Checks Configuration

#### Bonita Runtime

**Startup Probe**
```yaml
startupProbe:
  httpGet:
    path: /bonita/healthz
    port: 8080
    httpHeaders:
    - name: Authorization
      value: Basic <base64(monitoring_username:monitoring_password)>
    - name: User-Agent
      value: BonitaHealthCheck/1.0
  initialDelaySeconds: 120
  periodSeconds: 30
  failureThreshold: 20
  timeoutSeconds: 10
```

**Liveness Probe**
```yaml
livenessProbe:
  httpGet:
    path: /bonita/healthz
    port: 8080
    httpHeaders:
    - name: Authorization
      value: Basic <base64(monitoring_username:monitoring_password)>
    - name: User-Agent
      value: BonitaHealthCheck/1.0
  periodSeconds: 15
  timeoutSeconds: 5
  failureThreshold: 10
```

**Readiness Probe**
```yaml
readinessProbe:
  httpGet:
    path: /bonita/healthz
    port: 8080
    httpHeaders:
    - name: Authorization
      value: Basic <base64(monitoring_username:monitoring_password)>
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

#### UI Builder

**Startup Probe**
```yaml
startupProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - /opt/appsmith/healthcheck.sh
  initialDelaySeconds: 120
  periodSeconds: 30
  failureThreshold: 20
```

**Liveness Probe**
```yaml
livenessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - /opt/appsmith/healthcheck.sh
  periodSeconds: 15
  timeoutSeconds: 5
  failureThreshold: 10
```

#### UI Proxy

**Liveness Probe**
```yaml
livenessProbe:
  httpGet:
    path: /nginx_status
    port: 90
  periodSeconds: 15
  timeoutSeconds: 5
  failureThreshold: 3
```

### 7. Networking Configuration

#### Service Exposure

- **External Access**: Only UI Proxy (port 80) should be exposed
- **Internal Services**: bonita-runtime, ui-builder, postgres should be ClusterIP only

#### Service Names (Internal DNS)

In Null Platform, services communicate using internal DNS:
- `bonita-runtime` → Bonita Runtime service
- `ui-builder` → UI Builder service
- `postgres` → PostgreSQL database (or RDS endpoint)

#### Port Configuration

| Service | Internal Port | External Port | Protocol |
|---------|--------------|---------------|----------|
| ui-proxy | 80 | 80 | HTTP |
| bonita-runtime | 8080 | - | HTTP |
| bonita-runtime | 5701 | - | TCP (Hazelcast) |
| ui-builder | 80 | - | HTTP |
| postgres | 5432 | - | TCP |

### 8. Scaling Configuration

#### Horizontal Pod Autoscaling

**Bonita Runtime** (when CLUSTER_MODE=true)
```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80
```

**UI Builder**
```yaml
autoscaling:
  enabled: false  # Typically single instance
  minReplicas: 1
  maxReplicas: 1
```

**UI Proxy**
```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 3
  targetCPUUtilizationPercentage: 70
```

#### Spot Instance Compatibility

All Bonita services are compatible with spot instances:
- Stateless design (state in database)
- Health checks handle pod restarts gracefully
- Hazelcast clustering handles node rotation
- Ensure `CLUSTER_MODE=true` for multi-instance deployments

### 9. Volumes and Persistence

#### License File

**Option 1: Kubernetes Secret**
```bash
kubectl create secret generic bonita-license \
  --from-file=license.lic=/path/to/license.lic \
  -n bonita
```

Mount in deployment:
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

**Option 2: ConfigMap** (if license is not sensitive)
```bash
kubectl create configmap bonita-license \
  --from-file=license.lic=/path/to/license.lic \
  -n bonita
```

#### PostgreSQL Data (if not using RDS)

```yaml
volumeClaimTemplates:
- metadata:
    name: postgres-data
  spec:
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: 50Gi
    storageClassName: gp3
```

### 10. Security Configuration

#### Network Policies

Restrict traffic between services:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: bonita-runtime-policy
spec:
  podSelector:
    matchLabels:
      app: bonita-runtime
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: ui-proxy
    - podSelector:
        matchLabels:
          app: ui-builder
    ports:
    - protocol: TCP
      port: 8080
    - protocol: TCP
      port: 5701  # Hazelcast clustering
```

#### Security Context

**Bonita Runtime**
```yaml
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  runAsNonRoot: true
```

**UI Builder**
```yaml
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  runAsNonRoot: true
```

### 11. Monitoring and Logging

#### CloudWatch Integration

**Logs**
- Configure CloudWatch log groups for each service
- Use Fluent Bit or CloudWatch agent for log forwarding
- Retention: 30 days for dev, 90 days for production

**Metrics**
- CPU/Memory utilization
- Pod restart count
- Health check failures
- Application-specific metrics from `/bonita/healthz`

#### Prometheus Integration (if available)

Bonita exposes metrics at:
- `/bonita/metrics` (if monitoring user configured)

Configure ServiceMonitor:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: bonita-runtime
spec:
  selector:
    matchLabels:
      app: bonita-runtime
  endpoints:
  - port: bonita
    path: /bonita/metrics
    basicAuth:
      username:
        name: bonita-monitoring
        key: username
      password:
        name: bonita-monitoring
        key: password
```

### 12. OCTA Integration

For OCTA authentication integration (to be configured after initial deployment):

1. Contact OCTA team for application registration
2. Provide callback URL: `http://<ui-proxy-url>/bonita/loginservice`
3. Receive OCTA configuration:
   - Client ID
   - Client Secret
   - OCTA domain
   - Authorization endpoint
   - Token endpoint

4. Configure Bonita via custom config script or environment variables
5. Disable native authentication
6. Restart Bonita services

### 13. Deployment Workflow

#### Initial Deployment

1. **Create namespace**
   ```bash
   kubectl create namespace bonita
   ```

2. **Configure secrets** (database, credentials)

3. **Deploy PostgreSQL** (or configure RDS connection)
   ```bash
   # Create configmap for init scripts
   kubectl create configmap postgres-init \
     --from-file=init-db/01-init-databases.sh \
     -n bonita

   # Deploy PostgreSQL
   kubectl apply -f postgres-deployment.yaml -n bonita
   ```

4. **Deploy Bonita Runtime**
   ```bash
   kubectl apply -f bonita-runtime-deployment.yaml -n bonita
   ```

5. **Deploy UI Builder**
   ```bash
   kubectl apply -f ui-builder-deployment.yaml -n bonita
   ```

6. **Deploy UI Proxy**
   ```bash
   kubectl apply -f ui-proxy-deployment.yaml -n bonita
   ```

7. **Configure ingress/load balancer** for external access

#### Verification

```bash
# Check all pods are running
kubectl get pods -n bonita

# Check logs
kubectl logs -f deployment/bonita-runtime -n bonita

# Verify health
kubectl exec -it deployment/bonita-runtime -n bonita -- \
  curl -H "Authorization: Basic ..." http://localhost:8080/bonita/healthz
```

### 14. Rollback Strategy

In case of deployment issues:

```bash
# Rollback to previous version
kubectl rollout undo deployment/bonita-runtime -n bonita

# View rollout history
kubectl rollout history deployment/bonita-runtime -n bonita

# Rollback to specific revision
kubectl rollout undo deployment/bonita-runtime --to-revision=2 -n bonita
```

### 15. Maintenance Windows

For updates and maintenance:

1. **Database schema updates**: Usually handled automatically by Bonita
2. **Application updates**: Rolling update strategy, zero downtime
3. **Certificate renewal**: Automated via cert-manager or AWS ACM
4. **Secret rotation**: Coordinate with application restart

## Common Issues and Solutions

### Issue: Bonita pods keep restarting

**Possible causes:**
1. Database not accessible
2. Insufficient memory
3. License file missing or invalid
4. Health check failing

**Solutions:**
1. Check database connectivity
2. Increase memory limits
3. Verify license file mount
4. Check startup logs

### Issue: Slow startup time

**Solutions:**
1. Increase `startupProbe.failureThreshold`
2. Optimize database connection pool
3. Use faster storage class for volumes
4. Pre-warm cache if possible

### Issue: Inter-service communication failing

**Solutions:**
1. Verify service names match environment variables
2. Check network policies
3. Ensure services are in same namespace
4. Verify port configurations

## Post-Deployment Tasks

1. **Performance testing**: Load test with expected traffic
2. **Security scan**: Run vulnerability scans on deployed images
3. **Backup configuration**: Test backup and restore procedures
4. **Monitoring setup**: Configure alerts and dashboards
5. **Documentation**: Update runbooks with specific configuration
6. **Training**: Handoff to operations team

## Support Contacts

- **Bonita/Traicor Team**: For application-specific issues
- **ITTI Infrastructure Team**: For Null Platform and Kubernetes issues
- **Bonitasoft Support**: For Bonita platform bugs and patches

---

**Last Updated**: 2025-12-18
**Document Version**: 1.0
