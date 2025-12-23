#!/bin/bash
# ==============================================================================
# Bonita Cluster Verification Script
# ==============================================================================
# This script verifies that the Bonita Runtime cluster is properly configured
# and that both instances have successfully joined the Hazelcast cluster.
#
# Usage: ./scripts/verify-cluster.sh
# ==============================================================================

set -e

echo "================================================================================"
echo "Bonita HA Cluster Status Verification"
echo "================================================================================"
echo ""

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo "ERROR: docker-compose command not found"
    echo "Please install Docker Compose to use this script"
    exit 1
fi

# Check if containers are running
echo "[1/5] Checking container status..."
echo ""

RUNTIME1_STATUS=$(docker-compose ps -q bonita-runtime-1 2>/dev/null)
RUNTIME2_STATUS=$(docker-compose ps -q bonita-runtime-2 2>/dev/null)

if [ -z "$RUNTIME1_STATUS" ]; then
    echo "  ✗ bonita-runtime-1: NOT RUNNING"
    RUNTIME1_RUNNING=false
else
    echo "  ✓ bonita-runtime-1: Running"
    RUNTIME1_RUNNING=true
fi

if [ -z "$RUNTIME2_STATUS" ]; then
    echo "  ✗ bonita-runtime-2: NOT RUNNING"
    RUNTIME2_RUNNING=false
else
    echo "  ✓ bonita-runtime-2: Running"
    RUNTIME2_RUNNING=true
fi

echo ""

if [ "$RUNTIME1_RUNNING" = false ] || [ "$RUNTIME2_RUNNING" = false ]; then
    echo "ERROR: One or more runtime instances are not running"
    echo "Please start the cluster with: docker-compose up -d"
    exit 1
fi

# Check cluster membership logs
echo "[2/5] Checking Hazelcast cluster membership..."
echo ""

echo "  Runtime 1 cluster membership:"
RUNTIME1_MEMBERS=$(docker-compose logs bonita-runtime-1 2>/dev/null | grep -i "Members {size:" | tail -1 || echo "No membership logs found")
echo "    $RUNTIME1_MEMBERS"
echo ""

echo "  Runtime 2 cluster membership:"
RUNTIME2_MEMBERS=$(docker-compose logs bonita-runtime-2 2>/dev/null | grep -i "Members {size:" | tail -1 || echo "No membership logs found")
echo "    $RUNTIME2_MEMBERS"
echo ""

# Verify cluster size
echo "[3/5] Verifying cluster size..."
echo ""

EXPECTED_SIZE="size:2"

if echo "$RUNTIME1_MEMBERS" | grep -q "$EXPECTED_SIZE"; then
    echo "  ✓ Runtime 1 reports cluster size: 2"
else
    echo "  ✗ Runtime 1 does NOT report expected cluster size (expected: 2)"
    CLUSTER_ISSUE=true
fi

if echo "$RUNTIME2_MEMBERS" | grep -q "$EXPECTED_SIZE"; then
    echo "  ✓ Runtime 2 reports cluster size: 2"
else
    echo "  ✗ Runtime 2 does NOT report expected cluster size (expected: 2)"
    CLUSTER_ISSUE=true
fi

echo ""

# Check for Hazelcast errors
echo "[4/5] Checking for Hazelcast errors..."
echo ""

RUNTIME1_ERRORS=$(docker-compose logs bonita-runtime-1 2>/dev/null | grep -i "hazelcast" | grep -iE "error|exception|fail" | wc -l)
RUNTIME2_ERRORS=$(docker-compose logs bonita-runtime-2 2>/dev/null | grep -i "hazelcast" | grep -iE "error|exception|fail" | wc -l)

if [ "$RUNTIME1_ERRORS" -eq 0 ]; then
    echo "  ✓ Runtime 1: No Hazelcast errors found"
else
    echo "  ⚠ Runtime 1: $RUNTIME1_ERRORS potential Hazelcast errors found (check logs)"
fi

if [ "$RUNTIME2_ERRORS" -eq 0 ]; then
    echo "  ✓ Runtime 2: No Hazelcast errors found"
else
    echo "  ⚠ Runtime 2: $RUNTIME2_ERRORS potential Hazelcast errors found (check logs)"
fi

echo ""

# Check connectivity
echo "[5/5] Checking network connectivity between instances..."
echo ""

RUNTIME1_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' bonita-runtime-1 2>/dev/null)
RUNTIME2_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' bonita-runtime-2 2>/dev/null)

echo "  Runtime 1 IP: $RUNTIME1_IP"
echo "  Runtime 2 IP: $RUNTIME2_IP"
echo ""

# Final summary
echo "================================================================================"
echo "Summary"
echo "================================================================================"
echo ""

if [ "${CLUSTER_ISSUE:-false}" = true ]; then
    echo "STATUS: ✗ CLUSTER ISSUES DETECTED"
    echo ""
    echo "The cluster may not be properly configured. Please check:"
    echo "  1. Both containers are fully started (wait 2-3 minutes after docker-compose up)"
    echo "  2. CLUSTER_MODE=true in .env file"
    echo "  3. cluster-config/bonita-platform-sp-cluster-custom.properties is properly mounted"
    echo "  4. Check full logs: docker-compose logs bonita-runtime-1 bonita-runtime-2"
    echo ""
    echo "Common issues:"
    echo "  - Containers still starting up (check with: docker-compose logs -f)"
    echo "  - Network connectivity issues between containers"
    echo "  - Hazelcast port 5701 not accessible"
    echo ""
    exit 1
else
    echo "STATUS: ✓ CLUSTER IS HEALTHY"
    echo ""
    echo "Both Bonita Runtime instances are running and have successfully"
    echo "joined the Hazelcast cluster. The cluster is ready for use."
    echo ""
    echo "Cluster details:"
    echo "  - Cluster size: 2 members"
    echo "  - Runtime 1: $RUNTIME1_IP (bonita-runtime-1)"
    echo "  - Runtime 2: $RUNTIME2_IP (bonita-runtime-2)"
    echo ""
    echo "Access the application at: http://localhost"
    echo ""
fi

echo "================================================================================"
