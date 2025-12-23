# Bonita Platform - Docker Compose Deployment

This directory contains a Docker Compose configuration for deploying Bonitasoft Platform (version 10.2) with all necessary components.

## Architecture Overview

The deployment consists of 4 containerized services:

1. **PostgreSQL Database** (`postgres:16.4`)
   - Bonita platform database
   - Business Data Model (BDM) database

2. **Bonita Runtime Engine** (`bonita-subscription:10.2.3`)
   - Core BPM engine and process execution
   - REST API endpoints
   - Hazelcast clustering support
   - Exposed on port 8080

3. **UI Builder** (`bonita-ui-builder:1.3.0`)
   - Low-code UI development tool
   - Based on Appsmith
   - Connects to Bonita API
   - Exposed on port 8081 (internal)

4. **UI Proxy** (`bonita-ui-proxy:1.3.0`)
   - NGINX reverse proxy
   - Routes requests to Bonita Runtime and UI Builder
   - Main entry point for users
   - Exposed on port 80

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- Access to Bonitasoft private Docker registry (`bonitasoft.jfrog.io`)
- Valid Bonita subscription license (optional for initial testing)

## Quick Start

### 1. Configure Environment Variables

Copy the example environment file and adjust values for your environment:

```bash
cp .env.example .env
```

Edit `.env` and configure at minimum:
- Database passwords
- Bonita admin credentials
- Image registry credentials (if using private images)

### 2. Docker Registry Authentication

Login to the Bonitasoft Docker registry:

```bash
docker login bonitasoft.jfrog.io
Username: <your-username>
Password: <your-token>
```

### 3. Start the Stack

Launch all services:

```bash
docker-compose up -d
```

Monitor the startup logs:

```bash
docker-compose logs -f bonita-runtime
```

Wait for the message: `Server startup in [XXXX] milliseconds`

### 4. Access Bonita

Open your browser and navigate to:

```
http://localhost
```

Login with the credentials from your `.env` file (default: admin / myAdminSecret)

## Configuration

### Environment Variables

All configuration is managed through environment variables in the `.env` file. Key sections include:

#### Docker Images
- `BONITA_IMAGE_TAG`: Bonita Runtime version
- `UI_BUILDER_IMAGE_TAG`: UI Builder version
- `UI_PROXY_IMAGE_TAG`: UI Proxy version

#### Database Configuration
- `DB_PASSWORD`: Bonita database password
- `BDM_DB_PASSWORD`: Business Data Model database password
- Connection pool settings for both databases

#### Credentials
- `TENANT_USERNAME` / `TENANT_PASSWORD`: Bonita portal admin
- `PLATFORM_USERNAME` / `PLATFORM_PASSWORD`: Platform admin
- `MONITORING_USERNAME` / `MONITORING_PASSWORD`: Health check user

#### Runtime Settings
- `TIMEZONE`: Container timezone (e.g., Europe/Paris)
- `CLUSTER_MODE`: Enable clustering for multi-instance deployments
- `SESSION_DURATION_MS`: User session timeout in milliseconds

See `.env.example` for complete list of available variables.

### License File (Optional)

For production use, mount your Bonita license file:

1. Copy your license file to this directory:
   ```bash
   cp /path/to/BonitaSubscription-X.X-*.lic license.lic
   ```

2. Uncomment the license volume mount in `docker-compose.yml`:
   ```yaml
   volumes:
     - ./license.lic:/opt/bonita_lic/license.lic:ro
   ```

3. Restart the services:
   ```bash
   docker-compose restart bonita-runtime
   ```

### Custom Scripts

You can add custom initialization or configuration scripts:

#### Init Scripts (executed before Tomcat starts)
1. Create directory: `mkdir custom-init-scripts`
2. Add your scripts: `custom-init-scripts/my-script.sh`
3. Uncomment the volume mount in `docker-compose.yml`

#### Config Scripts (executed during setup)
1. Create directory: `mkdir custom-config-scripts`
2. Add your scripts: `custom-config-scripts/my-config.sh`
3. Uncomment the volume mount in `docker-compose.yml`

## Management Commands

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f bonita-runtime
docker-compose logs -f ui-builder
docker-compose logs -f ui-proxy
docker-compose logs -f postgres
```

### Check Service Health

```bash
docker-compose ps
```

### Restart Services

```bash
# All services
docker-compose restart

# Specific service
docker-compose restart bonita-runtime
```

### Stop Services

```bash
# Stop but keep data
docker-compose stop

# Stop and remove containers (keeps volumes)
docker-compose down

# Stop and remove everything including data
docker-compose down -v
```

### Scale Bonita Runtime (Clustering)

1. Enable cluster mode in `.env`:
   ```
   CLUSTER_MODE=true
   ```

2. Scale the runtime service:
   ```bash
   docker-compose up -d --scale bonita-runtime=2
   ```

Note: You'll need to configure a load balancer to distribute traffic when scaling.

## Health Checks

All services include health checks:

- **PostgreSQL**: `pg_isready` command
- **Bonita Runtime**: HTTP GET to `/bonita/healthz` endpoint
- **UI Builder**: Custom healthcheck script
- **UI Proxy**: HTTP GET to `/nginx_status` endpoint

Check health status:

```bash
docker inspect bonita-runtime | grep -A 10 Health
```

## Troubleshooting

### Bonita Runtime won't start

1. Check database connectivity:
   ```bash
   docker-compose exec bonita-runtime ping postgres
   ```

2. Verify database initialization:
   ```bash
   docker-compose exec postgres psql -U postgres -c "\l"
   ```
   You should see `bonita` and `bizdata` databases.

3. Check Bonita logs:
   ```bash
   docker-compose logs bonita-runtime | grep -i error
   ```

### Database connection errors

Ensure the database is ready before Bonita starts:
```bash
docker-compose up -d postgres
# Wait for healthy status
docker-compose up -d bonita-runtime
```

### UI Builder not accessible

Check that UI Builder can reach Bonita API:
```bash
docker-compose exec ui-builder curl http://bonita-runtime:8080/bonita/API/system/session
```

### Port conflicts

If ports 80, 8080, or 5432 are already in use, change them in `.env`:
```
UI_PROXY_PORT=8000
BONITA_PORT=8081
POSTGRES_PORT=5433
```

## Translation to Null Platform

This Docker Compose configuration can be deployed to Null Platform. Key considerations:

### Service Separation

Null Platform deploys each service separately. You'll need to create:

1. **PostgreSQL Service** (or use managed PostgreSQL)
2. **Bonita Runtime Service**
3. **UI Builder Service**
4. **UI Proxy Service**

### Environment Variables

In Null Platform:
- All variables from `.env` should be configured in the application settings
- Secrets (passwords, tokens) should use Nule's secret management
- Service-to-service communication uses internal DNS (e.g., `bonita-runtime:8080`)

### Health Checks

Null Platform supports the health check configuration from docker-compose:
- Use the `healthcheck` definitions for liveness and readiness probes
- Startup probe delays are defined in the compose file

### Volumes

For Null Platform deployment:
- License file: Mount via secret or volume claim
- PostgreSQL data: Use persistent volume claims
- Custom scripts: Use ConfigMaps

### Networking

Services communicate through Nule's internal network:
- Remove port mappings for internal services
- Only expose UI Proxy (port 80) externally
- Inter-service URLs use service names (e.g., `http://bonita-runtime:8080`)

### Resource Limits

Add resource limits in Null Platform based on your needs:
```yaml
resources:
  limits:
    cpu: 2
    memory: 2Gi
  requests:
    cpu: 1
    memory: 1Gi
```

Recommended resources:
- **Bonita Runtime**: 2 CPU, 2-4Gi memory
- **UI Builder**: 2 CPU, 4Gi memory
- **UI Proxy**: 500m CPU, 256Mi memory
- **PostgreSQL**: 1 CPU, 2Gi memory

### Image Pull Secrets

Configure Docker registry credentials in Null Platform:
1. Create image pull secret with `bonitasoft.jfrog.io` credentials
2. Reference the secret in each service deployment

### Scaling

For production deployments:
1. Enable `CLUSTER_MODE=true` for Bonita Runtime
2. Scale Bonita Runtime to multiple replicas
3. Configure load balancing through UI Proxy or external load balancer
4. Ensure session persistence is configured properly

## High Availability Clustering

This Docker Compose configuration supports Bonita Enterprise clustering with 2 runtime instances for high availability.

### Architecture

```
                    ┌─→ Bonita Runtime 1 ←──┐
UI Proxy (NGINX) ───┤                       │ (Hazelcast 5701)
                    └─→ Bonita Runtime 2 ←──┘
                 ↗                  ↓
        UI Builder              PostgreSQL
```

### Configuration

The HA setup is **enabled by default** in this docker-compose configuration:

1. **Two Runtime Instances**: `bonita-runtime-1` and `bonita-runtime-2`
2. **Hazelcast Clustering**: TCP/IP discovery with static member list
3. **Load Balancing**: NGINX UI Proxy distributes traffic using `ip_hash` (sticky sessions)
4. **Shared Database**: Both instances connect to the same PostgreSQL

### Cluster Configuration Files

- **cluster-config/bonita-platform-sp-cluster-custom.properties**: Hazelcast TCP/IP discovery settings
- **nginx-config/nginx.conf.template**: NGINX load balancing configuration
- **.env**: Set `CLUSTER_MODE=true` (default)

### Verifying Cluster Status

After starting the services, verify the cluster is properly formed:

```bash
# Use the verification script
./scripts/verify-cluster.sh

# Or manually check logs
docker-compose logs bonita-runtime-1 bonita-runtime-2 | grep "Members {size:"
```

Expected output:
```
Members {size:2, ver:2} [
    Member [172.18.0.3]:5701 - <uuid> this
    Member [172.18.0.4]:5701 - <uuid>
]
```

### Testing Failover

Test high availability by stopping one instance:

```bash
# Stop runtime-1
docker-compose stop bonita-runtime-1

# Verify application still works
curl http://localhost/bonita/login.jsp

# Runtime-2 continues serving requests

# Restart runtime-1
docker-compose start bonita-runtime-1

# Wait for it to rejoin cluster
docker-compose logs bonita-runtime-1 | grep "Members {size:"
```

### Load Balancing Strategy

The UI Proxy uses **ip_hash** for sticky sessions:
- Same client IP always goes to same backend
- Bonita sessions are also stored in database for failover
- Hazelcast replicates session data between instances

To change strategy, edit `nginx-config/nginx.conf.template`:
- `ip_hash`: Sticky by client IP (current)
- `least_conn`: Least connections
- Remove directive: Round-robin

### Performance Monitoring

Monitor cluster performance:

```bash
# Check both instances are healthy
docker-compose ps

# Monitor resource usage
docker stats bonita-runtime-1 bonita-runtime-2

# Watch cluster logs in real-time
docker-compose logs -f bonita-runtime-1 bonita-runtime-2
```

### Common Issues

**Cluster not forming (size:1 instead of size:2)**
- Wait 2-3 minutes for full startup
- Check CLUSTER_MODE=true in .env
- Verify cluster-config/ is mounted: `docker-compose config`
- Check Hazelcast port 5701 connectivity

**One instance keeps restarting**
- Check resource limits (needs ~2GB RAM per instance)
- Review logs: `docker-compose logs bonita-runtime-X`
- Verify database connection

**Load balancing not working**
- Verify nginx-config template is mounted
- Check UI Proxy logs: `docker-compose logs ui-proxy`
- Test direct access: `curl http://bonita-runtime-1:8080/bonita/` (from within network)

### Scaling Beyond 2 Instances

To add more instances:

1. Edit `docker-compose.yml`: Add `bonita-runtime-3`, etc.
2. Update `cluster-config/bonita-platform-sp-cluster-custom.properties`: Add to `tcpip.members`
3. Update `nginx-config/nginx.conf.template`: Add server to upstream
4. Adjust Java options: Add `-Dhazelcast.local.publicAddress=bonita-runtime-3`

See `CLUSTERING.md` for detailed scaling guide.

## Security Considerations

### Production Deployment Checklist

- [ ] Change all default passwords in `.env`
- [ ] Use strong, randomly generated passwords
- [ ] Enable HTTPS/TLS termination at load balancer
- [ ] Configure OCTA authentication (replace native login)
- [ ] Restrict database access to Bonita services only
- [ ] Enable audit logging
- [ ] Configure backup strategy for PostgreSQL
- [ ] Review and harden NGINX configuration
- [ ] Implement network policies to isolate services
- [ ] Use secrets management (AWS Secrets Manager, Vault, etc.)
- [ ] Enable monitoring and alerting
- [ ] Configure log aggregation

### AWS Secrets Manager Integration

For integration with AWS Secrets Manager (as discussed in requirements):

1. Store secrets with prefix `bonita/`:
   - `bonita/db-password`
   - `bonita/bdm-db-password`
   - `bonita/tenant-password`
   - `bonita/platform-password`

2. Use IAM roles for secret access (no access keys)

3. Update application startup to fetch secrets from Secrets Manager

4. Secret rotation should be coordinated with application restarts

## Monitoring

### Key Metrics to Monitor

- Bonita Runtime health: `/bonita/healthz`
- Database connections: Check pool utilization
- Memory usage: JVM heap size
- Response times: API endpoint performance
- Error rates: Application logs

### Integration Points

- CloudWatch: For AWS deployments
- Prometheus: Metrics scraping
- Grafana: Dashboards
- ELK Stack: Log aggregation

## Backup and Recovery

### Database Backup

```bash
# Backup all databases
docker-compose exec postgres pg_dumpall -U postgres > backup.sql

# Restore
docker-compose exec -T postgres psql -U postgres < backup.sql
```

### Volume Backup

```bash
# Backup PostgreSQL data
docker run --rm \
  -v kubernetes_example_postgres_data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/postgres-data-$(date +%Y%m%d).tar.gz /data
```

## Performance Tuning

### JVM Settings

Adjust `JAVA_OPTS` in `.env`:
- Heap size: Controlled by `XX:MaxRAMPercentage=60`
- GC tuning: Already optimized for G1GC
- Heap dumps: Automatically generated on OOM

### Database Connection Pools

Tune pool sizes based on load:
```
BONITA_POOL_MAX_TOTAL=20
BDM_POOL_MAX_TOTAL=10
```

### HTTP Thread Pool

Increase concurrent request handling:
```
HTTP_MAX_THREADS=200
```

## Support

For issues with:
- **Docker Compose setup**: Check this README and troubleshooting section
- **Bonita Platform**: Contact Bonitasoft support with subscription
- **Null Platform deployment**: Contact ITTI infrastructure team

## License

This deployment configuration is for Bonitasoft Enterprise/Subscription edition. Ensure you have a valid license before production deployment.

---

**Note**: This is a simplified deployment example. For production use, additional security hardening, monitoring, and high availability configurations are recommended.
