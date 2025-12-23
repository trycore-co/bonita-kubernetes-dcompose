# Bonita Docker Compose - Quick Start Guide

Get Bonita HA cluster up and running in 5 minutes.

## Prerequisites

- Docker Desktop or Docker Engine with Compose
- 8GB RAM available
- Ports 80, 8081, 5435 available
- Access to Bonitasoft Docker registry
- Valid Bonita license file

## Step 1: Navigate to Directory

```bash
cd docker-compose
```

## Step 2: Configure Environment

```bash
cp .env.example .env
```

Verify `CLUSTER_MODE=true` is set (default).

## Step 3: Docker Registry Login

```bash
docker login bonitasoft.jfrog.io
```

## Step 4: Add License File

```bash
cp /path/to/BonitaSubscription-*.lic license.lic
```

## Step 5: Start Services

```bash
docker-compose up -d
```

## Step 6: Monitor Startup

```bash
docker-compose logs -f bonita-runtime-1 bonita-runtime-2
```

Wait for (2-3 minutes):
- `Cluster mode: Activated`
- `Server startup in [XXXX] milliseconds`

Press `Ctrl+C` to exit log view.

## Step 7: Verify Cluster

```bash
docker-compose logs bonita-runtime-1 bonita-runtime-2 | grep -iE "Cluster mode:|Members"
```

## Step 8: Access Bonita

- **URL**: http://localhost
- **Username**: admin
- **Password**: myAdminSecret

## Verify All Services

```bash
docker-compose ps -a
```

All services should show `Up`.

**Note**: `unhealthy` status on runtimes is expected due to authentication requirements on health endpoint.

## Quick Commands

```bash
# View all logs
docker-compose logs -f

# View specific service
docker-compose logs -f bonita-runtime-1

# Check status
docker-compose ps -a

# Restart runtimes
docker-compose restart bonita-runtime-1 bonita-runtime-2

# Stop all
docker-compose stop

# Stop and remove (keeps data)
docker-compose down

# Stop and remove everything
docker-compose down -v
```

## Test Failover

```bash
# Stop one instance
docker-compose stop bonita-runtime-1

# App should still work
curl -I http://localhost/bonita/login.jsp

# Restart
docker-compose start bonita-runtime-1
```

## Troubleshooting

### Database init fails: "cannot execute"

This is caused by Windows line endings in shell scripts. The `.gitattributes` file should prevent this automatically. If you cloned before it existed:

```bash
git add --renormalize .
git checkout -- init-db/
docker-compose down -v
docker-compose up -d
```

### NGINX: "host not found in upstream"

Mismatch between `docker-compose.yml` and `nginx-config/nginx.conf.template`. Ensure both have same runtime instances.

### Cluster shows size:1

- Wait 2-3 minutes for full startup
- Verify `CLUSTER_MODE=true` in `.env`

## Architecture

```
┌─────────────────────────────────────────┐
│         Browser (http://localhost)      │
└─────────────────┬───────────────────────┘
                  │
        ┌─────────▼─────────┐
        │   UI Proxy :80    │  (NGINX LB)
        └────┬──────────┬───┘
             │          │
    ┌────────▼────┐  ┌──▼──────────────┐
    │  UI Builder │  │ Bonita Runtime-1│ ←──┐
    │    :8081    │  │     :8080       │    │ Hazelcast
    └─────────────┘  └───────┬─────────┘    │ (5701)
                             │  ┌───────────┘
                             │  │ Bonita Runtime-2
                             │  │     :8080
                             │  └─────────────────┘
                             ↓
                    ┌────────▼──────┐
                    │   PostgreSQL  │
                    │     :5435     │
                    └───────────────┘
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

**Change these for production!**

## Next Steps

- Read [README.md](README.md) for full configuration
- See [CLUSTERING.md](CLUSTERING.md) for advanced HA setup
- See [NULL_PLATFORM.md](NULL_PLATFORM.md) for production deployment

---

**Last Updated**: December 2024
