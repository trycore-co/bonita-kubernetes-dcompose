# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Deployment configurations for Bonitasoft Platform (version 2025.2) with two deployment options:

1. **Kubernetes/Helm** (`helm/`): Production-ready Helm charts
2. **Docker Compose** (`docker-compose/`): HA deployment for development/testing

## Architecture

```
                    ┌─→ Bonita Runtime 1 ←──┐
UI Proxy (NGINX) ───┤                       │ (Hazelcast 5701)
                    └─→ Bonita Runtime 2 ←──┘
                 ↗                  ↓
        UI Builder              PostgreSQL
```

**Components:**
- **PostgreSQL 16.4**: Two databases - `bonita` (bonitauser) and `bizdata` (bizuser)
- **Bonita Runtime 2025.2-u5**: BPM engine with Hazelcast clustering (port 8080, 5701)
- **UI Builder 1.3.11**: Low-code UI development based on Appsmith (internal port 8090)
- **UI Proxy 1.3.9**: NGINX reverse proxy and load balancer (external port 80, internal 8082)

## Common Commands

### Docker Compose Deployment

```bash
cd docker-compose
cp .env.example .env
docker login bonitasoft.jfrog.io
docker-compose up -d

# Check status
docker-compose ps -a
docker-compose logs -f bonita-runtime-1 bonita-runtime-2

# Verify cluster (look for "Cluster mode: Activated" and "Members {size:2")
docker-compose logs bonita-runtime-1 bonita-runtime-2 | grep -iE "Cluster mode:|Members"

# Test failover
docker-compose stop bonita-runtime-1
curl http://localhost/bonita/login.jsp
docker-compose start bonita-runtime-1

# Cleanup
docker-compose down -v
```

### Kubernetes/Helm Deployment

```bash
# Setup
kubectl create ns bonita
kubectl -n bonita create configmap db-scripts --from-file=db_scripts/
kubectl -n bonita apply -f postgresql.yaml

# Secrets
kubectl create secret docker-registry imagepullsecret \
  --docker-server=bonitasoft.jfrog.io \
  --docker-username=<user> --docker-password=<token> -n bonita
kubectl -n bonita create secret generic bonita-license --from-file=license.lic

# Deploy
helm dependency build helm/bonita-custom
helm upgrade --install bonita-test -n bonita helm/bonita-custom -f helm/values-test.yaml

# Access (requires port 80 available)
sudo -E kubectl --namespace bonita port-forward service/bonita-test-ui-proxy 80:80

# Scale
kubectl -n bonita scale --replicas=2 deployment/bonita-test-engine

# Verify cluster
kubectl -n bonita logs --tail=-1 --selector app=runtime | grep Members | jq .message

# Cleanup
kubectl delete ns bonita
```

## Key Configuration Files

| File | Purpose |
|------|---------|
| `docker-compose/.env` | Environment variables (CLUSTER_MODE, credentials, ports) |
| `docker-compose/docker-compose.yml` | Service definitions (runtime-1, runtime-2, ui-proxy, ui-builder, postgres) |
| `docker-compose/cluster-config/bonita-platform-sp-cluster-custom.properties` | Hazelcast TCP/IP discovery |
| `docker-compose/nginx-config/nginx.conf.template` | NGINX load balancing (ip_hash sticky sessions) |
| `docker-compose/init-db/01-init-databases.sh` | PostgreSQL initialization script |
| `helm/bonita/values.yaml` | Default Helm values with documentation |
| `helm/values-test.yaml` | Test environment overrides |
| `helm/bonita-custom/Chart.yaml` | Bonita chart dependency (version 10.2.0) |

## Important Notes

- **License Required**: Bonita Enterprise requires a valid subscription license (`license.lic`)
- **Cluster Mode**: Set `CLUSTER_MODE=true` in `.env` for HA with multiple runtime instances
- **Health Checks**: Healthcheck uses `curl -u user:pass` format. Runtime should show `healthy` after startup (~2 min). Previous versions used Base64 header substitution which failed in `CMD-SHELL` context.
- **Cross-Platform**: `.gitattributes` ensures shell scripts maintain Unix line endings (LF) on all platforms
- **NGINX Config**: When changing runtime instances, update both `docker-compose.yml` AND `nginx-config/nginx.conf.template`
- **Default Credentials**: admin / myAdminSecret (change for production)
- **PostgreSQL Port**: Default mapped to 5435 externally to avoid conflicts

## Troubleshooting

**Database init script fails with "cannot execute":**
```bash
# Re-normalize line endings (if cloned before .gitattributes existed)
git add --renormalize .
git checkout -- docker-compose/init-db/
```

**NGINX fails with "host not found in upstream":**
- Ensure runtime service names in `nginx.conf.template` match `docker-compose.yml`
- Comment out `bonita-runtime-2` in nginx config if running single instance

**Cluster not forming (size:1):**
- Verify `CLUSTER_MODE=true` in `.env`
- Wait 2-3 minutes for full startup
- Check `cluster-config/` is mounted correctly
