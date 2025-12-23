# Bonita Platform - Docker Compose HA Deployment

This directory contains a Docker Compose configuration for deploying Bonitasoft Platform (version 10.2) in High Availability mode with 2 runtime instances.

## Architecture Overview

```
                    ┌─→ Bonita Runtime 1 ←──┐
UI Proxy (NGINX) ───┤                       │ (Hazelcast 5701)
                    └─→ Bonita Runtime 2 ←──┘
                 ↗                  ↓
        UI Builder              PostgreSQL
```

The deployment consists of 5 containerized services:

| Service | Image | Ports | Description |
|---------|-------|-------|-------------|
| postgres | `postgres:16.4` | 5435:5432 | Bonita + BDM databases |
| bonita-runtime-1 | `bonita-subscription:10.2.3` | 8080, 5701 | Runtime instance 1 |
| bonita-runtime-2 | `bonita-subscription:10.2.3` | 8080, 5701 | Runtime instance 2 |
| ui-builder | `bonita-ui-builder:1.3.0` | 8081:80 | Low-code UI tool |
| ui-proxy | `bonita-ui-proxy:1.3.0` | 80:80 | NGINX load balancer |

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- Access to Bonitasoft Docker registry (`bonitasoft.jfrog.io`)
- Valid Bonita subscription license
- 8GB+ RAM available

## Quick Start

### 1. Configure Environment

```bash
cp .env.example .env
```

Key settings in `.env`:
- `CLUSTER_MODE=true` (default, required for HA)
- `POSTGRES_PORT=5435` (avoids conflicts with local PostgreSQL)

### 2. Docker Registry Login

```bash
docker login bonitasoft.jfrog.io
```

### 3. Add License File

```bash
cp /path/to/BonitaSubscription-*.lic license.lic
```

The license volume is already configured in `docker-compose.yml`.

### 4. Start Services

```bash
docker-compose up -d
```

### 5. Monitor Startup

```bash
docker-compose logs -f bonita-runtime-1 bonita-runtime-2
```

Wait for (2-3 minutes):
- `Cluster mode: Activated`
- `Server startup in [XXXX] milliseconds`

### 6. Verify Cluster

```bash
docker-compose logs bonita-runtime-1 bonita-runtime-2 | grep -iE "Cluster mode:|Members"
```

### 7. Access Application

- **URL**: http://localhost
- **Credentials**: admin / myAdminSecret

## Configuration

### Key Configuration Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definitions |
| `.env` | Environment variables |
| `cluster-config/bonita-platform-sp-cluster-custom.properties` | Hazelcast TCP/IP discovery |
| `nginx-config/nginx.conf.template` | NGINX load balancing |
| `init-db/01-init-databases.sh` | PostgreSQL initialization |

### Cross-Platform Compatibility

The repository includes a `.gitattributes` file that ensures shell scripts and configuration files maintain Unix line endings (LF) regardless of the operating system. This prevents "cannot execute" errors in Linux containers when developing on Windows.

### Adding/Removing Runtime Instances

**Important**: When changing the number of runtime instances, update THREE files:

1. `docker-compose.yml` - add/remove/comment runtime services
2. `nginx-config/nginx.conf.template` - update upstream servers
3. `cluster-config/bonita-platform-sp-cluster-custom.properties` - update member list

## Troubleshooting

### Database init fails with "cannot execute: required file not found"

**Cause**: Shell scripts have Windows line endings (CRLF instead of LF).

**Solution**: This should be handled automatically by `.gitattributes`. If you cloned before this file existed, run:
```bash
git add --renormalize .
git checkout -- init-db/
```

Or manually fix:
```bash
sed -i 's/\r$//' init-db/*.sh
docker-compose down -v
docker-compose up -d
```

### NGINX fails with "host not found in upstream"

**Cause**: Mismatch between runtime services in `docker-compose.yml` and `nginx-config/nginx.conf.template`.

**Solution**: Ensure both files have the same runtime instances configured.

### Health check shows "unhealthy" but app works

**Cause**: Health endpoint `/bonita/healthz` requires authentication. Docker health check returns 401.

**Status**: This is expected behavior. The application works correctly.

### Cluster not forming (size:1 instead of size:2)

**Causes**:
1. `CLUSTER_MODE=false` in `.env`
2. Runtime still starting (wait 2-3 minutes)
3. Hazelcast config not mounted

## Testing Failover

```bash
docker-compose stop bonita-runtime-1
curl -I http://localhost/bonita/login.jsp  # Should return 200
docker-compose start bonita-runtime-1
```

## Default Credentials

| Component | Username | Password |
|-----------|----------|----------|
| Bonita Admin | admin | myAdminSecret |
| Platform Admin | pflogin | myPfSecret |
| Monitoring | monitoring | myMonitoringSecret |
| PostgreSQL | postgres | testpassword |
| Bonita DB | bonitauser | myDbSecret |
| BDM DB | bizuser | myBdmSecret |

**Change all passwords for production deployments!**

## Related Documentation

- [QUICKSTART.md](QUICKSTART.md) - 5-minute setup guide
- [CLUSTERING.md](CLUSTERING.md) - Detailed HA clustering guide
- [NULL_PLATFORM.md](NULL_PLATFORM.md) - Null Platform deployment guide

---

**Last Updated**: December 2024
