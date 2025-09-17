#!/bin/bash

# Redis Enterprise + RDI Status Check Script
# Comprehensive health check for all deployed services

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Status tracking
SERVICES_OK=0
SERVICES_FAILED=0

# Logging functions
success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((SERVICES_OK++))
}

fail() {
    echo -e "${RED}❌ $1${NC}"
    ((SERVICES_FAILED++))
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Function to check if command succeeds
check_service() {
    local name="$1"
    local command="$2"
    
    if eval "$command" >/dev/null 2>&1; then
        success "$name is running"
        return 0
    else
        fail "$name is not accessible"
        return 1
    fi
}

# Function to check web service with response details
check_web_service() {
    local name="$1"
    local url="$2"
    local expected_code="${3:-200}"
    
    if command -v curl >/dev/null 2>&1; then
        response=$(curl -k -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
        if [[ "$response" == "$expected_code" ]]; then
            success "$name is accessible (HTTP $response)"
            return 0
        else
            fail "$name returned HTTP $response (expected $expected_code)"
            return 1
        fi
    else
        warn "curl not available, skipping $name web check"
        return 1
    fi
}

# Main status check function
main() {
    echo -e "${BLUE}"
    echo "██████╗ ███████╗██████╗ ██╗███████╗    ███████╗████████╗ █████╗ ████████╗██╗   ██╗███████╗"
    echo "██╔══██╗██╔════╝██╔══██╗██║██╔════╝    ██╔════╝╚══██╔══╝██╔══██╗╚══██╔══╝██║   ██║██╔════╝"
    echo "██████╔╝█████╗  ██║  ██║██║███████╗    ███████╗   ██║   ███████║   ██║   ██║   ██║███████╗"
    echo "██╔══██╗██╔══╝  ██║  ██║██║╚════██║    ╚════██║   ██║   ██╔══██║   ██║   ██║   ██║╚════██║"
    echo "██║  ██║███████╗██████╔╝██║███████║    ███████║   ██║   ██║  ██║   ██║   ╚██████╔╝███████║"
    echo "╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝╚══════╝    ╚══════╝   ╚═╝   ╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚══════╝"
    echo -e "${NC}"
    echo "Redis Enterprise + RDI Deployment Status Check"
    echo "=============================================="

    # Check Docker containers
    header "Docker Containers"
    if docker ps >/dev/null 2>&1; then
        echo "Container Status:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -6
        echo
        
        # Check individual containers
        containers=("re-n1" "postgres" "redisinsight" "sqlpad" "loadgen")
        for container in "${containers[@]}"; do
            if docker ps | grep -q "$container"; then
                success "$container container is running"
            else
                fail "$container container is not running"
            fi
        done
    else
        fail "Docker is not running or not accessible"
    fi

    # Check Web Services
    header "Web Services"
    check_web_service "Redis Enterprise Web UI" "https://localhost:8443"
    check_web_service "Redis Insight" "http://localhost:5540"
    check_web_service "SQLPad" "http://localhost:3001"

    # Check Redis Enterprise Cluster
    header "Redis Enterprise Cluster"
    if curl -k -u admin@rl.org:redislabs https://localhost:9443/v1/cluster 2>/dev/null | grep -q '"name"'; then
        cluster_name=$(curl -k -s -u admin@rl.org:redislabs https://localhost:9443/v1/cluster 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
        success "Redis Enterprise cluster '$cluster_name' is active"
    else
        fail "Redis Enterprise cluster is not responding"
    fi

    # Check Redis Databases
    header "Redis Databases"
    if check_service "Redis Target DB (port 12000)" "docker exec re-n1 redis-cli -h localhost -p 12000 ping"; then
        info "Redis Target DB ready for data synchronization"
    fi
    
    if check_service "Redis RDI DB (port 12001)" "docker exec re-n1 redis-cli -h localhost -p 12001 ping"; then
        info "Redis RDI DB ready for configuration"
    fi

    # Check database list from Redis Enterprise API
    db_count=$(curl -k -s -u admin@rl.org:redislabs https://localhost:9443/v1/bdbs 2>/dev/null | grep -o '"name":"[^"]*"' | wc -l)
    if [[ "$db_count" -gt 0 ]]; then
        success "Redis Enterprise has $db_count database(s) configured"
        echo "Database names:"
        curl -k -s -u admin@rl.org:redislabs https://localhost:9443/v1/bdbs 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | sed 's/^/  - /'
    else
        warn "No Redis databases found via API"
    fi

    # Check PostgreSQL
    header "PostgreSQL Database"
    if check_service "PostgreSQL" "docker exec postgres pg_isready -U postgres"; then
        # Check logical replication configuration
        wal_level=$(docker exec postgres psql -U postgres -t -c "SHOW wal_level;" 2>/dev/null | xargs)
        if [[ "$wal_level" == "logical" ]]; then
            success "PostgreSQL logical replication is enabled (wal_level=$wal_level)"
        else
            warn "PostgreSQL wal_level is '$wal_level' (expected 'logical')"
        fi

        # Check replication slots
        slot_count=$(docker exec postgres psql -U postgres -t -c "SELECT count(*) FROM pg_replication_slots;" 2>/dev/null | xargs)
        if [[ "$slot_count" -gt 0 ]]; then
            success "PostgreSQL has $slot_count replication slot(s)"
        else
            warn "No PostgreSQL replication slots found"
        fi

        # Check sample data
        track_count=$(docker exec postgres psql -U postgres -d chinook -t -c "SELECT count(*) FROM \"Track\";" 2>/dev/null | xargs)
        if [[ "$track_count" -gt 0 ]]; then
            success "PostgreSQL has $track_count tracks in sample data"
        else
            warn "No sample data found in PostgreSQL"
        fi
    fi

    # Check RDI Installation
    header "RDI (Redis Data Integration)"
    if command -v redis-di >/dev/null 2>&1; then
        rdi_path=$(which redis-di)
        success "RDI CLI is installed at $rdi_path"
        
        # Try to get RDI version
        if redis-di --version >/dev/null 2>&1; then
            rdi_version=$(redis-di --version 2>/dev/null | head -1)
            info "RDI Version: $rdi_version"
        else
            warn "RDI CLI installed but version check failed"
        fi
    elif [[ -f "/opt/rdi/bin/rdi-cli" ]]; then
        success "RDI CLI is installed at /opt/rdi/bin/rdi-cli"
        
        if sudo /opt/rdi/bin/rdi-cli --version >/dev/null 2>&1; then
            rdi_version=$(sudo /opt/rdi/bin/rdi-cli --version 2>/dev/null | head -1)
            info "RDI Version: $rdi_version"
        else
            warn "RDI CLI installed but version check failed"
        fi
    else
        fail "RDI CLI not found"
    fi

    # Check Load Generator
    header "Load Generator"
    if docker exec loadgen python3 --version >/dev/null 2>&1; then
        success "Load generator container ready"
        if [[ -f "scripts/generate_load.py" ]] || docker exec loadgen test -f /scripts/generate_load.py 2>/dev/null; then
            success "Load generation script is available"
            info "Run: docker exec loadgen python3 /scripts/generate_load.py"
        else
            warn "Load generation script not found"
        fi
    else
        fail "Load generator container not accessible"
    fi

    # Network connectivity test
    header "Network Connectivity"
    if docker network ls | grep -q redis_network; then
        success "Redis network is configured"
    else
        warn "Redis network not found"
    fi

    # Summary
    header "Status Summary"
    total_services=$((SERVICES_OK + SERVICES_FAILED))
    
    echo -e "Total Services Checked: $total_services"
    echo -e "${GREEN}Services OK: $SERVICES_OK${NC}"
    echo -e "${RED}Services Failed: $SERVICES_FAILED${NC}"
    echo

    if [[ $SERVICES_FAILED -eq 0 ]]; then
        success "All services are running properly!"
        echo
        info "Next Steps:"
        echo "  1. Access Redis Insight: http://localhost:5540"
        echo "  2. Access SQLPad: http://localhost:3001"
        echo "  3. Configure RDI pipeline: sudo /opt/rdi/bin/rdi-cli"
        echo "  4. Generate test data: docker exec loadgen python3 /scripts/generate_load.py"
        return 0
    else
        fail "Some services have issues that need attention"
        return 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

