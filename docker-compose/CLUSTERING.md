# Bonita Enterprise High Availability Clustering Guide

Complete guide for deploying and managing Bonita Enterprise in High Availability mode with Docker Compose.

## Architecture Overview

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

## Configuration Files

When modifying the cluster, you must update **three files**:

| File | What to Update |
|------|----------------|
| `docker-compose.yml` | Add/remove runtime service definitions |
| `nginx-config/nginx.conf.template` | Add/remove servers in upstream block |
| `cluster-config/bonita-platform-sp-cluster-custom.properties` | Add/remove Hazelcast members |

### Hazelcast Configuration

**File**: `cluster-config/bonita-platform-sp-cluster-custom.properties`

```properties
bonita.cluster.group.name=bonita-docker-cluster
bonita.platform.cluster.hazelcast.tcpip.enabled=true
bonita.platform.cluster.hazelcast.tcpip.members=bonita-runtime-1:5701,bonita-runtime-2:5701
```

### NGINX Load Balancer

**File**: `nginx-config/nginx.conf.template`

```nginx
upstream bonita_runtime {
    ip_hash;  # Sticky sessions
    server bonita-runtime-1:8080 max_fails=3 fail_timeout=30s;
    server bonita-runtime-2:8080 max_fails=3 fail_timeout=30s;
}
```

**Load Balancing Strategies**:
- `ip_hash`: Client IP determines backend (recommended)
- `least_conn`: Least connections
- No directive: Round-robin

## Verifying Cluster Status

### Check Cluster Mode Activated

```bash
docker-compose logs bonita-runtime-1 bonita-runtime-2 | grep "Cluster mode:"
```

Expected output:
```
Cluster mode: Activated
Cluster mode: Activated
```

### Check Hazelcast Members

```bash
docker-compose logs bonita-runtime-1 bonita-runtime-2 | grep "Members {size:"
```

Expected output:
```
Members {size:2, ver:2} [Member [...] this, Member [...]]
```

### Container Status

```bash
docker-compose ps -a
```

**Note**: `unhealthy` status on runtimes is expected. The health endpoint requires authentication which Docker health check doesn't provide. The application works correctly.

## Failover Testing

### Test 1: Stop Primary Instance

```bash
# Stop runtime-1
docker-compose stop bonita-runtime-1

# Verify app still works via runtime-2
curl -I http://localhost/bonita/login.jsp
# Should return 200 OK

# Restart
docker-compose start bonita-runtime-1

# Wait for rejoin
docker-compose logs bonita-runtime-1 | grep "Members {size:2"
```

### Test 2: Rolling Restart

```bash
docker-compose restart bonita-runtime-1
sleep 90
docker-compose restart bonita-runtime-2
# Application remains available throughout
```

## Scaling Beyond 2 Instances

### Add Third Instance

**Step 1**: Edit `docker-compose.yml`

Copy `bonita-runtime-2` section as `bonita-runtime-3`:
```yaml
bonita-runtime-3:
  image: ${BONITA_IMAGE_REPOSITORY:-bonitasoft.jfrog.io/docker/bonita-subscription}:${BONITA_IMAGE_TAG:-10.2.3}
  container_name: bonita-runtime-3
  # ... same config as runtime-2
  environment:
    # ... same environment
    - JAVA_OPTS=... -Dhazelcast.local.publicAddress=bonita-runtime-3 ...
```

**Step 2**: Update Hazelcast member list

Edit `cluster-config/bonita-platform-sp-cluster-custom.properties`:
```properties
bonita.platform.cluster.hazelcast.tcpip.members=bonita-runtime-1:5701,bonita-runtime-2:5701,bonita-runtime-3:5701
```

**Step 3**: Update NGINX

Edit `nginx-config/nginx.conf.template`:
```nginx
upstream bonita_runtime {
    ip_hash;
    server bonita-runtime-1:8080 max_fails=3 fail_timeout=30s;
    server bonita-runtime-2:8080 max_fails=3 fail_timeout=30s;
    server bonita-runtime-3:8080 max_fails=3 fail_timeout=30s;
}
```

**Step 4**: Restart

```bash
docker-compose down
docker-compose up -d
```

## Troubleshooting

### Cluster Size Shows 1 Instead of 2

**Causes & Solutions**:

1. **Containers still starting**: Wait 2-3 minutes
   ```bash
   docker-compose logs -f bonita-runtime-1 bonita-runtime-2
   ```

2. **CLUSTER_MODE not enabled**:
   ```bash
   grep CLUSTER_MODE .env  # Should be 'true'
   ```

3. **Cluster config not mounted**:
   ```bash
   docker-compose exec bonita-runtime-1 ls -la /opt/custom-config.d/
   ```

4. **Hazelcast port 5701 blocked**:
   ```bash
   docker-compose exec bonita-runtime-1 nc -zv bonita-runtime-2 5701
   ```

### NGINX "host not found in upstream"

**Cause**: `nginx.conf.template` references a runtime that doesn't exist in `docker-compose.yml`.

**Solution**: Ensure both files have matching runtime definitions. Comment out missing runtimes in nginx config.

### One Instance Keeps Restarting

```bash
# Check logs
docker-compose logs bonita-runtime-X | grep -iE "error|exception|fatal"

# Check resources
docker stats bonita-runtime-1 bonita-runtime-2
```

**Common causes**:
- Insufficient memory (needs ~2GB per instance)
- Database connection issues
- License file missing

### Health Check Shows Unhealthy

This is **expected behavior**. The `/bonita/healthz` endpoint requires authentication. Docker's health check returns 401 (Unauthorized), causing "unhealthy" status.

The application works correctly. Verify via:
```bash
curl -I http://localhost/bonita/login.jsp  # Should return 200
```

## Performance Tuning

### Connection Pools

Adjust in `.env`:
```bash
BONITA_POOL_MAX_TOTAL=20    # Max connections to Bonita DB per instance
BDM_POOL_MAX_TOTAL=10       # Max connections to BDM DB per instance
```

**Rule of thumb**: Total pool max across all instances < PostgreSQL max_connections (default 100)

### JVM Heap Size

Current: 60% of container RAM. To adjust, modify `JAVA_OPTS` in docker-compose.yml:
```
-XX:InitialRAMPercentage=50
-XX:MaxRAMPercentage=70
```

### Resource Limits

Recommended per runtime instance:
- CPU: 2 cores
- Memory: 2GB minimum

## Production Checklist

### Pre-Deployment

- [ ] License file mounted in both runtime instances
- [ ] All default passwords changed in `.env`
- [ ] `CLUSTER_MODE=true` verified
- [ ] Resource limits configured
- [ ] External PostgreSQL (not Docker) for production
- [ ] HTTPS/TLS at load balancer

### Post-Deployment

- [ ] Cluster verification: Both runtimes show `Cluster mode: Activated`
- [ ] Failover test: Stop one instance, verify app works
- [ ] Session persistence verified
- [ ] Monitoring configured

---

**Last Updated**: December 2024
