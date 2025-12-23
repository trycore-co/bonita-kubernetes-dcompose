# Bonita Enterprise High Availability Clustering Guide

Complete guide for deploying and managing Bonita Enterprise in High Availability mode with Docker Compose.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Quick Start](#quick-start)
3. [Configuration Details](#configuration-details)
4. [Verification and Monitoring](#verification-and-monitoring)
5. [Failover Testing](#failover-testing)
6. [Performance Tuning](#performance-tuning)
7. [Scaling Beyond 2 Instances](#scaling-beyond-2-instances)
8. [Troubleshooting](#troubleshooting)
9. [Production Checklist](#production-checklist)

## Architecture Overview

### HA Components

```
┌─────────────────┐
│   UI Proxy      │  ← Entry point (port 80)
│   (NGINX LB)    │     Load balancing with ip_hash
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼──┐  ┌──▼───┐
│ RT-1 │  │ RT-2 │  ← Bonita Runtime instances
└──┬───┘  └───┬──┘     Port 8080 (HTTP), 5701 (Hazelcast)
   │  ◄─────► │        Hazelcast cluster communication
   └──┬───────┘
      │
  ┌───▼────┐
  │  PSQL  │          ← Shared database
  └────────┘             State persistence
```

### Key Design Principles

1. **Stateless Runtime**: All state in PostgreSQL + Hazelcast
2. **Shared Database**: Both instances connect to same PostgreSQL
3. **Session Replication**: Hazelcast replicates sessions across nodes
4. **Sticky Sessions**: NGINX `ip_hash` keeps clients on same backend
5. **Automatic Failover**: If one node fails, NGINX routes to healthy node

## Quick Start

```bash
# 1. Navigate to docker-compose directory
cd docker-compose

# 2. Copy environment template
cp .env.example .env

# 3. Verify CLUSTER_MODE=true (default)
grep CLUSTER_MODE .env

# 4. Start cluster
docker-compose up -d

# 5. Wait for startup (2-3 minutes)
docker-compose logs -f bonita-runtime-1 bonita-runtime-2 | grep "Server startup"

# 6. Verify cluster formed
./scripts/verify-cluster.sh

# 7. Access application
open http://localhost
```

## Configuration Details

### Hazelcast Clustering

**Configuration File**: `cluster-config/bonita-platform-sp-cluster-custom.properties`

Key settings:
- `bonita.cluster.group.name`: Cluster identifier (all members must match)
- `bonita.platform.cluster.hazelcast.tcpip.enabled=true`: Use TCP/IP discovery
- `bonita.platform.cluster.hazelcast.tcpip.members`: Static member list

### NGINX Load Balancing

**Template**: `nginx-config/nginx.conf.template`

Upstream configuration:
```nginx
upstream bonita_runtime {
    ip_hash;  # Sticky sessions
    server bonita-runtime-1:8080 max_fails=3 fail_timeout=30s;
    server bonita-runtime-2:8080 max_fails=3 fail_timeout=30s;
}
```

**Strategies**:
- `ip_hash`: Client IP determines backend (current)
- `least_conn`: Least connections
- `round_robin`: Sequential distribution (default if no directive)

### Java Options

Each runtime includes:
```
-Dhazelcast.local.publicAddress=bonita-runtime-X
```

This ensures Hazelcast advertises correct hostname for cluster communication.

## Verification and Monitoring

### Cluster Status Script

```bash
./scripts/verify-cluster.sh
```

Expected output:
```
===============================================================================
Bonita HA Cluster Status Verification
===============================================================================

[1/5] Checking container status...
  ✓ bonita-runtime-1: Running
  ✓ bonita-runtime-2: Running

[2/5] Checking Hazelcast cluster membership...
  Runtime 1: Members {size:2, ver:2} [Member [172.18.0.3]:5701 ...]
  Runtime 2: Members {size:2, ver:2} [Member [172.18.0.4]:5701 ...]

[3/5] Verifying cluster size...
  ✓ Runtime 1 reports cluster size: 2
  ✓ Runtime 2 reports cluster size: 2

STATUS: ✓ CLUSTER IS HEALTHY
```

### Manual Verification

**Check cluster membership logs**:
```bash
docker-compose logs bonita-runtime-1 bonita-runtime-2 | grep "Members {size:"
```

**Check Hazelcast connectivity**:
```bash
docker-compose logs bonita-runtime-1 bonita-runtime-2 | grep "hazelcast" | grep -i "member"
```

**Monitor health checks**:
```bash
watch docker-compose ps
```

### Monitoring Endpoints

- **NGINX Status**: http://localhost:90/nginx_status (internal)
- **Cluster Status**: Via logs (no HTTP endpoint)

## Failover Testing

### Test 1: Stop Primary Instance

```bash
# Stop runtime-1
docker-compose stop bonita-runtime-1

# Verify runtime-2 serves requests
curl -I http://localhost/bonita/login.jsp
# Should return 200 OK

# Check NGINX routes to runtime-2
docker-compose logs ui-proxy | tail -20

# Restart runtime-1
docker-compose start bonita-runtime-1

# Wait for rejoin (check logs)
docker-compose logs bonita-runtime-1 | grep "Members {size:2"
```

### Test 2: Rolling Restart

```bash
# Restart instances one at a time
docker-compose restart bonita-runtime-1
# Wait for healthy
sleep 60

docker-compose restart bonita-runtime-2
# Application remains available throughout
```

### Test 3: Session Persistence

```bash
# Login to application
# Note your session cookie (JSESSIONID)

# Stop the instance you're connected to
docker-compose stop bonita-runtime-1  # (or -2)

# Refresh page - session should persist
# (May require re-login depending on Hazelcast sync timing)
```

## Performance Tuning

### Connection Pools

Adjust in `.env`:
```bash
# Per-instance settings (multiply by number of instances)
BONITA_POOL_MAX_TOTAL=20    # Max connections to Bonita DB
BDM_POOL_MAX_TOTAL=10       # Max connections to BDM DB
```

**Rule of thumb**:
- Total pool max should not exceed PostgreSQL max_connections
- Default PostgreSQL max_connections=100
- With 2 runtimes: max 40 connections per instance

### JVM Heap Size

Current: 60% of container RAM (default)

To adjust, modify `JAVA_OPTS` in docker-compose.yml:
```
-XX:InitialRAMPercentage=50
-XX:MaxRAMPercentage=70
```

### HTTP Thread Pool

```bash
# In .env
HTTP_MAX_THREADS=200  # Increase for high concurrency
```

### Resource Limits

Recommended per runtime instance:
```yaml
resources:
  limits:
    cpus: '2'
    memory: 2G
  reservations:
    cpus: '1'
    memory: 1G
```

Add to docker-compose.yml under `deploy` for each runtime.

## Scaling Beyond 2 Instances

### Add Third Instance

**Step 1**: Edit `docker-compose.yml`

Add new service (copy bonita-runtime-2, rename to bonita-runtime-3):
```yaml
bonita-runtime-3:
  # ... same config as runtime-2
  container_name: bonita-runtime-3
  environment:
    - JAVA_OPTS=... -Dhazelcast.local.publicAddress=bonita-runtime-3 ...
```

**Step 2**: Update Hazelcast member list

Edit `cluster-config/bonita-platform-sp-cluster-custom.properties`:
```properties
bonita.platform.cluster.hazelcast.tcpip.members=bonita-runtime-1:5701,bonita-runtime-2:5701,bonita-runtime-3:5701
```

**Step 3**: Update NGINX load balancer

Edit `nginx-config/nginx.conf.template`:
```nginx
upstream bonita_runtime {
    ip_hash;
    server bonita-runtime-1:8080 max_fails=3 fail_timeout=30s;
    server bonita-runtime-2:8080 max_fails=3 fail_timeout=30s;
    server bonita-runtime-3:8080 max_fails=3 fail_timeout=30s;
}
```

**Step 4**: Restart all services

```bash
docker-compose down
docker-compose up -d
./scripts/verify-cluster.sh  # Should show size:3
```

## Troubleshooting

### Issue: Cluster Size Shows 1 Instead of 2

**Symptoms**:
```
Members {size:1, ver:1} [Member [172.18.0.3]:5701 - <uuid> this]
```

**Causes & Solutions**:

1. **Containers still starting**
   ```bash
   # Wait 2-3 minutes
   docker-compose logs -f bonita-runtime-1 bonita-runtime-2
   # Look for "Server startup in [XXXX] milliseconds"
   ```

2. **CLUSTER_MODE not enabled**
   ```bash
   grep CLUSTER_MODE .env  # Should be 'true'
   docker-compose config | grep CLUSTER_MODE
   ```

3. **Cluster config not mounted**
   ```bash
   docker-compose exec bonita-runtime-1 ls -la /opt/custom-config.d/
   # Should show bonita-platform-sp-cluster-custom.properties
   ```

4. **Hazelcast port 5701 blocked**
   ```bash
   docker-compose exec bonita-runtime-1 nc -zv bonita-runtime-2 5701
   # Should connect successfully
   ```

5. **Wrong Hazelcast member list**
   ```bash
   docker-compose exec bonita-runtime-1 cat /opt/custom-config.d/bonita-platform-sp-cluster-custom.properties | grep tcpip.members
   # Should list both runtime-1:5701 and runtime-2:5701
   ```

### Issue: One Instance Keeps Restarting

**Check logs**:
```bash
docker-compose logs bonita-runtime-X | grep -iE "error|exception|fatal"
```

**Common causes**:
- Insufficient memory (needs ~2GB per instance)
- Database connection issues
- Port conflicts

**Solutions**:
```bash
# Check resources
docker stats bonita-runtime-1 bonita-runtime-2

# Increase memory limit
docker-compose down
# Edit docker-compose.yml, add under each runtime:
# deploy:
#   resources:
#     limits:
#       memory: 3G

docker-compose up -d
```

### Issue: Load Balancing Not Working

**Test backend connectivity**:
```bash
# From inside ui-proxy container
docker-compose exec ui-proxy curl -I http://bonita-runtime-1:8080/bonita/
docker-compose exec ui-proxy curl -I http://bonita-runtime-2:8080/bonita/
# Both should return 302 or 200
```

**Check NGINX config**:
```bash
docker-compose exec ui-proxy cat /etc/nginx/conf.d/default.conf | grep -A 5 "upstream bonita_runtime"
# Should show both backends
```

**Check NGINX logs**:
```bash
docker-compose logs ui-proxy | grep -i error
```

### Issue: Sessions Lost on Failover

**Possible causes**:
- Hazelcast session replication not working
- Session timeout too short
- Sticky sessions not configured

**Solutions**:
```bash
# Verify session configuration
docker-compose config | grep SESSION_DURATION

# Check Hazelcast logs for replication
docker-compose logs bonita-runtime-1 bonita-runtime-2 | grep -i "session"

# Ensure ip_hash in NGINX (sticky sessions)
docker-compose exec ui-proxy cat /etc/nginx/conf.d/default.conf | grep ip_hash
```

## Production Checklist

### Pre-Deployment

- [ ] **License file**: Mounted in both runtime instances
- [ ] **Credentials**: All default passwords changed in `.env`
- [ ] **Database**: Production PostgreSQL (not Docker container)
- [ ] **Resources**: Sufficient RAM (6GB+ for 2 instances)
- [ ] **Secrets**: Use AWS Secrets Manager or Vault
- [ ] **Monitoring**: CloudWatch/Prometheus configured
- [ ] **Backups**: Database backup strategy in place
- [ ] **HTTPS**: TLS termination at load balancer
- [ ] **OCTA**: Authentication configured

### Post-Deployment

- [ ] **Cluster verification**: Run `./scripts/verify-cluster.sh`
- [ ] **Failover test**: Stop one instance, verify application works
- [ ] **Load test**: Simulate production traffic
- [ ] **Session persistence**: Verify sessions survive failover
- [ ] **Monitoring alerts**: Configure alerts for cluster issues
- [ ] **Documentation**: Update runbooks with specific configuration
- [ ] **Training**: Handoff to operations team

### Monitoring Metrics

Monitor these metrics in production:

- Cluster size (should always equal number of instances)
- Instance health (all healthy)
- Response times (per backend)
- Error rates (4xx, 5xx)
- Database connections (pool utilization)
- Memory usage (JVM heap)
- CPU usage
- Session counts
- Hazelcast network traffic

### Maintenance Windows

For updates:
1. Deploy to runtime-2 first (rolling update)
2. Wait for health checks to pass
3. Deploy to runtime-1
4. Verify cluster reformed

Zero-downtime deployment with proper health checks.

## Additional Resources

- **README.md**: Full deployment guide
- **NULL_PLATFORM.md**: Production deployment on Null Platform
- **QUICKSTART.md**: 5-minute getting started
- **Bonita Documentation**: https://documentation.bonitasoft.com/bonita/latest/clustering
- **Hazelcast Documentation**: https://docs.hazelcast.com/hazelcast/latest/

---

**For support**: Contact Bonitasoft support or ITTI infrastructure team
