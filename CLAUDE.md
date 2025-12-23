# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains deployment configurations for Bonitasoft (version 10.2/2024.3) with two deployment options:

1. **Kubernetes/Helm Deployment** (`helm/`): Production-ready Helm charts for Kubernetes clusters
2. **Docker Compose Deployment** (`docker-compose/`): High Availability deployment for development, testing, and Null Platform translation

## Architecture

The deployment consists of three main components:

1. **PostgreSQL Database**: StatefulSet running PostgreSQL 16.4 with initialization scripts that create two databases:
   - `bonita` database (owned by `bonitauser`) - for Bonita platform data
   - `bizdata` database (owned by `bizuser`) - for Business Data Model (BDM)

2. **Bonita Helm Chart** (`helm/bonita/`): Base Helm chart that defines all Kubernetes resources for Bonita deployment including:
   - Main Bonita Runtime deployment with Hazelcast clustering support
   - UI Builder deployment for custom UI development
   - UI Proxy deployment for routing requests
   - ConfigMaps for environment variables, scripts, and configurations
   - Services for Bonita (port 8080) and Hazelcast (port 5701)
   - Optional ingress, HPA (Horizontal Pod Autoscaler), and RBAC resources

3. **Bonita-Custom Chart** (`helm/bonita-custom/`): Extension chart that depends on the base Bonita chart (defined in `Chart.yaml`). This is the deployment chart for this specific example.

## Common Commands

### Local Development with Minikube

Start Minikube cluster:
```bash
minikube start --kubernetes-version 1.30.9
```

### Database Setup

Create namespace and deploy PostgreSQL:
```bash
kubectl create ns bonita
kubectl -n bonita create configmap db-scripts --from-file=db_scripts/
kubectl -n bonita apply -f postgresql.yaml
```

Test PostgreSQL connection:
```bash
kubectl -n bonita run psql-client --image postgres:16.4 --rm --tty -i --command -- /bin/bash
# Inside the container:
export PGPASSWORD=testpassword
psql -h postgres-db -p 5432 -U postgres postgres
```

### Bonita Deployment

Set up required secrets:
```bash
# Docker registry credentials
kubectl create secret docker-registry imagepullsecret \
  --docker-server=bonitasoft.jfrog.io \
  --docker-username=<username> \
  --docker-password=<token> \
  -n bonita

# Bonita license
kubectl -n bonita create secret generic bonita-license --from-file=license.lic
```

Build dependencies and deploy:
```bash
helm dependency build helm/bonita-custom
helm upgrade --install bonita-test -n bonita helm/bonita-custom -f helm/values-test.yaml
```

### Monitoring and Scaling

Check startup completion:
```bash
kubectl -n bonita logs --tail=-1 --selector app=runtime | grep "Server startup in" | jq .message
```

Get deployment status:
```bash
kubectl -n bonita get deployment --selector app=runtime
```

Scale deployment:
```bash
kubectl -n bonita scale --current-replicas=1 --replicas=2 deployment/bonita-test-engine
```

Verify cluster membership (Hazelcast):
```bash
kubectl -n bonita logs --tail=-1 --selector app=runtime | grep Members | jq .message
```

### Access Application

Port-forward to access locally (requires port 80 available):
```bash
sudo -E kubectl --namespace bonita port-forward service/bonita-test-ui-proxy 80:80
```

Open http://127.0.0.1 and login with credentials from `helm/values-test.yaml` (default: admin / myAdminSecret)

### Cleanup

Delete entire namespace:
```bash
kubectl delete ns bonita
```

## Configuration

### Helm Values Structure

The `helm/values-test.yaml` file configures all deployment settings including:
- Database connections (datasources.bonita and datasources.bdm)
- Credentials (tenant, platform, monitoring)
- Image versions and pull secrets
- Resource limits/requests
- UI Builder and UI Proxy settings
- Timezone and cluster mode

### Key Files

- `helm/bonita/values.yaml`: Default values and parameter documentation for the base chart
- `helm/values-test.yaml`: Test environment configuration overrides
- `postgresql.yaml`: PostgreSQL StatefulSet and Service definitions
- `db_scripts/init-users-dbs.sh`: Database initialization script
- `helm/bonita-custom/Chart.yaml`: Defines dependency on base Bonita chart (version 10.2.0)

## Important Notes

- Bonita requires a valid subscription license file to run
- The deployment uses Hazelcast for clustering when `clusterMode: true`
- PostgreSQL credentials are hardcoded in scripts and values files for testing purposes only
- UI Builder is enabled by default (`uib.enabled: true`) for custom UI development
- Service account with appropriate RBAC permissions is created when `serviceAccount.create: true`
- The project uses Bonita version 10.2.3 with UI Builder/Proxy version 1.3.0

## Docker Compose Deployment

The `docker-compose/` directory provides a **High Availability deployment** with 2 Bonita Runtime instances in cluster mode for development, testing, and Null Platform translation.

### HA Architecture

```
                    ┌─→ Bonita Runtime 1 ←──┐
UI Proxy (NGINX) ───┤                       │ (Hazelcast 5701)
                    └─→ Bonita Runtime 2 ←──┘
                 ↗                  ↓
        UI Builder              PostgreSQL
```

**Key Features:**
- **2 Runtime Instances**: Automatic failover and load balancing
- **Hazelcast Clustering**: TCP/IP discovery for session replication
- **NGINX Load Balancing**: ip_hash strategy for sticky sessions
- **Shared Database**: Both instances connect to PostgreSQL
- **Cluster Mode**: Enabled by default (`CLUSTER_MODE=true`)

### Quick Start with Docker Compose

```bash
cd docker-compose
cp .env.example .env
docker login bonitasoft.jfrog.io
docker-compose up -d

# Verify cluster status
./scripts/verify-cluster.sh
```

Access at http://localhost (default credentials: admin / myAdminSecret)

### Key Files

**Service Configuration:**
- `docker-compose/docker-compose.yml`: Complete service definitions for bonita-runtime-1, bonita-runtime-2, ui-proxy, ui-builder, and postgres
- `docker-compose/.env.example`: All configurable environment variables with clustering settings

**Clustering Configuration:**
- `docker-compose/cluster-config/bonita-platform-sp-cluster-custom.properties`: Hazelcast TCP/IP discovery configuration
- `docker-compose/nginx-config/nginx.conf.template`: NGINX load balancing configuration
- `docker-compose/scripts/verify-cluster.sh`: Cluster status verification script

**Documentation:**
- `docker-compose/README.md`: Comprehensive deployment and configuration guide with HA section
- `docker-compose/CLUSTERING.md`: **Complete HA clustering guide** (architecture, failover testing, performance tuning, troubleshooting)
- `docker-compose/NULL_PLATFORM.md`: Technical guide for Null Platform deployment
- `docker-compose/QUICKSTART.md`: 5-minute quick start guide with cluster verification
- `docker-compose/init-db/`: PostgreSQL initialization scripts

### Verifying HA Cluster

After starting the cluster, verify both instances joined successfully:

```bash
# Automated verification
./scripts/verify-cluster.sh

# Manual verification - look for "Members {size:2"
docker-compose logs bonita-runtime-1 bonita-runtime-2 | grep "Members {size:"
```

Expected output: `Members {size:2, ver:2} [Member [...] this, Member [...]]`

### Testing Failover

Test high availability by stopping one instance:

```bash
# Stop runtime-1
docker-compose stop bonita-runtime-1

# Application continues working via runtime-2
curl http://localhost/bonita/login.jsp

# Restart runtime-1
docker-compose start bonita-runtime-1
```

### Null Platform Translation

The Docker Compose HA configuration is designed for easy translation to Null Platform:
- **Service Separation**: Each service (bonita-runtime-1, bonita-runtime-2, ui-proxy, ui-builder, postgres) maps directly to a Null Platform application
- **Environment Variables**: All configuration via environment variables (no ConfigMaps), compatible with Null Platform settings
- **TCP/IP Discovery**: Hazelcast uses static member list (works with Null Platform service DNS)
- **Secrets Integration**: Compatible with AWS Secrets Manager (prefix: `bonita/`)
- **Health Checks**: All services include health checks that map to Kubernetes liveness/readiness probes
- **Stateless Design**: Runtime instances are stateless and compatible with spot instances
- **Scaling**: Add more runtime instances by replicating service configuration (see CLUSTERING.md)

See `docker-compose/NULL_PLATFORM.md` for detailed migration guide and `docker-compose/CLUSTERING.md` for advanced HA configuration, scaling beyond 2 instances, and production deployment checklist.

## Docker Compose Deployment Status

### Current Status (December 18, 2024)

**Environment**: Docker Compose HA Cluster (2 Bonita Runtime instances)

**Setup Completed**:
- ✅ Docker registry authentication (bonitasoft.jfrog.io)
- ✅ Environment variables configured (.env file)
- ✅ PostgreSQL port adjusted to 5435 (avoiding local conflicts)
- ✅ Cluster configuration files created (Hazelcast TCP/IP discovery)
- ✅ NGINX load balancer configuration ready
- ✅ Docker images downloaded (bonita-subscription:10.2.3)
- ✅ Volume mount configuration adjusted (removed read-only flag for cluster-config)

**Pending**: Non-production license file required to start cluster

### License Request

**Support Ticket**: #391867
**Subject**: Non-production license for Bonita Enterprise
**Opened by**: Jonathan Segura Gomez
**Date**: December 18, 2024 14:23:01
**Status**: Logged
**Priority**: Low
**Expected Response**: 24 hours

**License Requirements**:
- Type: Non-Production
- Version: Bonita 10.2.3 / 2024.3
- Duration: 30 days minimum
- Purpose: HA cluster configuration and testing before Null Platform deployment
- Environment: Docker Compose (2-instance cluster)

**Next Steps** (when license is received):

1. Copy license file to `docker-compose/` directory:
   ```bash
   cp BonitaSubscription-*.lic docker-compose/license.lic
   ```

2. Uncomment license volume mounts in `docker-compose.yml` (lines 98 and ~165):
   ```yaml
   # Change from:
   # - ./license.lic:/opt/bonita_lic/license.lic:ro

   # To:
   - ./license.lic:/opt/bonita_lic/license.lic:ro
   ```

3. Start the HA cluster:
   ```bash
   cd docker-compose
   docker-compose up -d
   ```

4. Monitor startup (2-3 minutes):
   ```bash
   docker-compose logs -f bonita-runtime-1 bonita-runtime-2
   ```

5. Verify cluster formation:
   ```bash
   ./scripts/verify-cluster.sh
   ```

6. Access Bonita portal:
   - URL: http://localhost
   - Default credentials: admin / myAdminSecret

7. Obtain Request Key from portal (if needed for production license later)

### Platform Compatibility Notes

**Apple Silicon (ARM64) Compatibility**:
- Bonita images are linux/amd64 architecture
- Docker Desktop on Apple Silicon uses Rosetta 2 emulation
- Performance may be slightly reduced compared to native amd64 systems
- This is acceptable for development/testing purposes
- Production deployment on Null Platform (AWS) uses native amd64 instances

**Verified Configuration**:
- Docker version: 28.5.1
- Docker Compose version: 2.40.2
- Host platform: darwin/arm64 (macOS Apple Silicon)
- Container platform: linux/amd64 (emulated)
