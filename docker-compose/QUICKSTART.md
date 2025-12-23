# Bonita Docker Compose - Quick Start Guide

Get Bonita up and running in 5 minutes for development and testing.

## Prerequisites

- Docker Desktop or Docker Engine with Compose
- 8GB RAM available
- Ports 80, 8080, 5432 available
- Access to Bonitasoft Docker registry

## Step 1: Clone and Navigate

```bash
cd docker-compose
```

## Step 2: Configure Environment

Create `.env` from template:

```bash
cp .env.example .env
```

**Minimum required changes** (edit `.env`):
- Update passwords if desired (optional for testing)
- Keep defaults for local testing

## Step 3: Docker Registry Login

Login to Bonitasoft registry:

```bash
docker login bonitasoft.jfrog.io
```

Enter credentials provided by Bonita team.

## Step 4: Start Services

```bash
docker-compose up -d
```

This will:
1. Pull required images (may take a few minutes first time)
2. Create network and volumes
3. Initialize PostgreSQL databases
4. Start all services

## Step 5: Monitor Startup

Watch Bonita startup logs:

```bash
docker-compose logs -f bonita-runtime
```

Wait for message: `Server startup in [XXXX] milliseconds`

Press `Ctrl+C` to exit log view.

## Step 6: Access Bonita

Open browser to:

```
http://localhost
```

**Login credentials** (from `.env`):
- Username: `admin`
- Password: `myAdminSecret`

## Verify All Services

Check service status:

```bash
docker-compose ps
```

All services should show `Up (healthy)`.

## Quick Commands

```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f bonita-runtime-1

# Restart services
docker-compose restart bonita-runtime-1 bonita-runtime-2

# Stop all services
docker-compose stop

# Stop and remove (keeps data)
docker-compose down

# Stop and remove including data
docker-compose down -v

# Verify HA cluster status
./scripts/verify-cluster.sh
```

## Troubleshooting

### Services won't start

```bash
# Check if ports are available
lsof -i :80
lsof -i :8080
lsof -i :5432

# Check Docker resources
docker system df
docker system prune  # Clean up if needed
```

### Database initialization failed

```bash
# Remove volume and restart
docker-compose down -v
docker-compose up -d
```

### Can't access http://localhost

```bash
# Check UI Proxy status
docker-compose logs ui-proxy

# Try direct access to Bonita (note: ports not published in HA mode)
docker-compose logs ui-proxy | grep -i error
```

### Need to reset everything

```bash
# Complete cleanup
docker-compose down -v
rm -rf .env
cp .env.example .env
# Edit .env if needed
docker-compose up -d
```

## What's Next?

### Development

1. Create processes in Bonita Studio
2. Deploy to this runtime
3. Test in UI Builder

### Add License File

```bash
# Copy your license
cp /path/to/license.lic ./license.lic

# Edit docker-compose.yml - uncomment license volume in both runtime services

# Restart
docker-compose restart bonita-runtime-1 bonita-runtime-2
```

### Connect to Database

```bash
# Access PostgreSQL
docker-compose exec postgres psql -U bonitauser -d bonita

# Or use your favorite DB client:
# Host: localhost
# Port: 5432
# Database: bonita
# User: bonitauser
# Password: myDbSecret
```

### High Availability Clustering

**Clustering is enabled by default!** This setup includes:
- 2 Bonita Runtime instances (bonita-runtime-1, bonita-runtime-2)
- Hazelcast clustering for session replication
- NGINX load balancing with sticky sessions

Verify cluster status:
```bash
./scripts/verify-cluster.sh
```

Test failover:
```bash
# Stop one instance
docker-compose stop bonita-runtime-1

# Application should still work via runtime-2
curl http://localhost/bonita/login.jsp

# Restart
docker-compose start bonita-runtime-1
```

See [CLUSTERING.md](CLUSTERING.md) for detailed HA guide.

## Architecture

```
┌─────────────────────────────────────────┐
│         Browser (http://localhost)      │
└─────────────────┬───────────────────────┘
                  │
        ┌─────────▼─────────┐
        │   UI Proxy :80    │  (NGINX)
        └────┬──────────┬───┘
             │          │
    ┌────────▼────┐  ┌──▼──────────────┐
    │  UI Builder │  │ Bonita Runtime-1│ ←┐
    │    :8081    │  │                 │  │ Hazelcast
    └─────────────┘  └───┬─────────────┘  │ (5701)
                         │  ┌─────────────┘
                         │  │ Bonita Runtime-2│
                         │  └─────────────────┘
                         ↓
                    ┌────▼──────┐
                    │ PostgreSQL│
                    │   :5432   │
                    └───────────┘
```

## Resource Usage

Expected resource consumption (HA mode with 2 runtimes):
- **RAM**: ~6-8GB total (2GB per runtime instance)
- **CPU**: 4-6 cores during startup, 2-3 cores idle
- **Disk**: ~6GB for images + database

## Default URLs

- **Main Portal**: http://localhost (via UI Proxy load balancer)
- **UI Builder** (direct): http://localhost:8081
- **Cluster Status**: `./scripts/verify-cluster.sh`

Note: In HA mode, runtime ports (8080) are not published externally. Access via UI Proxy on port 80.

## Default Credentials

| Component | Username | Password |
|-----------|----------|----------|
| Bonita Admin | admin | myAdminSecret |
| Platform Admin | pflogin | myPfSecret |
| Monitoring | monitoring | myMonitoringSecret |
| PostgreSQL | postgres | testpassword |
| Bonita DB | bonitauser | myDbSecret |
| BDM DB | bizuser | myBdmSecret |

**⚠️ Change these passwords for production deployments!**

## Next Steps

- Read full [README.md](README.md) for detailed configuration and HA guide
- See [NULL_PLATFORM.md](NULL_PLATFORM.md) for production deployment on Null Platform
- See [CLUSTERING.md](CLUSTERING.md) for advanced clustering configuration
- Check Bonita documentation: https://documentation.bonitasoft.com/

## Getting Help

- Check `docker-compose logs` for error messages
- Review [README.md](README.md) troubleshooting section
- Contact Bonita support for platform issues

---

**Happy Bonita Development! 🚀**
