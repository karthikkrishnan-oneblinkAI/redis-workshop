#!/bin/bash

# Redis Workshop Start Script
# Simple deployment script for Redis Enterprise + RDI workshop
# Runs as regular user with NO sudo requirements

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Configuration variables
export DOMAIN=${DOMAIN:-"localhost"}
export PASSWORD=${PASSWORD:-"redislabs"}
export RE_USER=${RE_USER:-"admin@rl.org"}
export HOST_IP=$(hostname -I | awk '{print $1}')
export HOSTNAME=$(hostname -s)
export RDI_VERSION=${RDI_VERSION:-"1.14.0"}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking workshop prerequisites..."
    
    # Check if running as root (should not be)
    if [ "$EUID" -eq 0 ]; then
        error "This script should NOT be run as root or with sudo"
        echo "Please run as a regular user: ./start.sh"
        exit 1
    fi
    
    # Check if user is in docker group
    if ! groups | grep -q docker; then
        error "Current user is not in the docker group"
        echo "The system administrator needs to run the admin setup first:"
        echo "  sudo ./admin-setup.sh"
        echo "Then you may need to log out and log back in, or run: newgrp docker"
        exit 1
    fi
    
    # Check Docker
    if ! command_exists docker; then
        error "Docker is not installed. System admin needs to run: sudo ./admin-setup.sh"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command_exists docker-compose; then
        error "Docker Compose is not installed. System admin needs to run: sudo ./admin-setup.sh"
        exit 1
    fi
    
    # Test Docker access
    if ! docker ps >/dev/null 2>&1; then
        error "Cannot access Docker. Please check:"
        echo "1. System admin has run: sudo ./admin-setup.sh"
        echo "2. Docker service is running"
        echo "3. You've logged out and back in after admin setup"
        echo "4. Or try: newgrp docker"
        exit 1
    fi
    
    log "All prerequisites met - ready to deploy!"
}

# Function to wait for service to be ready
wait_for_service() {
    local url=$1
    local expected_code=$2
    local timeout=${3:-300}
    local interval=5
    local count=0
    
    log "Waiting for service at $url to respond with code $expected_code..."
    
    while [ $count -lt $((timeout / interval)) ]; do
        if curl -k -s -o /dev/null -w "%{http_code}" "$url" | grep -q "$expected_code"; then
            log "Service is ready!"
            return 0
        fi
        sleep $interval
        count=$((count + 1))
        echo -n "."
    done
    
    error "Service at $url did not become ready within $timeout seconds"
    return 1
}

# Function to create Docker Compose configuration
create_docker_compose() {
    log "Creating Docker Compose configuration..."
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Redis Enterprise Node
  re-n1:
    image: redislabs/redis:latest
    hostname: re-n1
    container_name: re-n1
    privileged: true
    ports:
      - "8443:8443"    # Redis Enterprise Web UI
      - "9443:9443"    # Redis Enterprise REST API
      - "12000:12000"  # Database port
      - "12001:12001"  # RDI database port
    networks:
      redis_network:
        ipv4_address: 172.16.22.21
    volumes:
      - re-n1-data:/opt/redislabs/persist
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
    sysctls:
      net.core.somaxconn: 1024
    ulimits:
      nproc: 65535
      nofile:
        soft: 65535
        hard: 65535
      memlock: -1

  # PostgreSQL Source Database
  postgres:
    image: postgres:13
    hostname: postgres
    container_name: postgres
    environment:
      POSTGRES_DB: chinook
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    networks:
      - redis_network
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./init-postgres.sql:/docker-entrypoint-initdb.d/init-postgres.sql

  # Redis Insight
  redisinsight:
    image: redislabs/redisinsight:latest
    hostname: redisinsight
    container_name: redisinsight
    ports:
      - "5540:5540"
    networks:
      - redis_network
    volumes:
      - redisinsight-data:/db

  # SQLPad for PostgreSQL management
  sqlpad:
    image: sqlpad/sqlpad:latest
    hostname: sqlpad
    container_name: sqlpad
    environment:
      SQLPAD_ADMIN: admin@rl.org
      SQLPAD_ADMIN_PASSWORD: redislabs
      SQLPAD_APP_LOG_LEVEL: info
      SQLPAD_WEB_LOG_LEVEL: warn
      SQLPAD_SEED_DATA_PATH: /etc/sqlpad/seed-data
      SQLPAD_CONNECTIONS__postgres__name: PostgreSQL Chinook
      SQLPAD_CONNECTIONS__postgres__driver: postgres
      SQLPAD_CONNECTIONS__postgres__host: postgres
      SQLPAD_CONNECTIONS__postgres__database: chinook
      SQLPAD_CONNECTIONS__postgres__username: postgres
      SQLPAD_CONNECTIONS__postgres__password: postgres
    ports:
      - "3001:3000"
    networks:
      - redis_network

  # Load Generator
  loadgen:
    image: python:3.9-slim
    hostname: loadgen
    container_name: loadgen
    command: tail -f /dev/null
    networks:
      - redis_network
    volumes:
      - ./scripts:/scripts
    depends_on:
      - postgres

networks:
  redis_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.16.22.0/24

volumes:
  re-n1-data:
  postgres-data:
  redisinsight-data:
EOF

    log "Docker Compose configuration created"
}

# Function to create PostgreSQL initialization script
create_postgres_init() {
    log "Creating PostgreSQL initialization script..."
    
    mkdir -p scripts
    
    cat > init-postgres.sql << 'EOF'
-- Enable logical replication for RDI
ALTER SYSTEM SET wal_level = logical;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders = 10;

-- Create sample Track table
CREATE TABLE IF NOT EXISTS "Track" (
    "TrackId" SERIAL PRIMARY KEY,
    "Name" VARCHAR(200) NOT NULL,
    "AlbumId" INTEGER NOT NULL,
    "MediaTypeId" INTEGER NOT NULL,
    "GenreId" INTEGER NOT NULL,
    "Composer" VARCHAR(220),
    "Milliseconds" INTEGER NOT NULL,
    "Bytes" INTEGER,
    "UnitPrice" NUMERIC(10,2) NOT NULL
);

-- Insert sample data
INSERT INTO "Track" ("Name", "AlbumId", "MediaTypeId", "GenreId", "Composer", "Milliseconds", "Bytes", "UnitPrice")
VALUES 
    ('Master of Puppets', 1, 1, 2, 'Metallica', 515000, 8000000, 0.99),
    ('Enter Sandman', 1, 1, 2, 'Metallica', 331000, 5000000, 0.99),
    ('One', 1, 1, 2, 'Metallica', 446000, 7000000, 0.99);

-- NOTE: Logical replication slot creation moved to post-restart script
EOF

    log "PostgreSQL initialization script created"
}

# Function to create load generation script
create_load_generator() {
    log "Creating load generation script..."
    
    cat > scripts/generate_load.py << 'EOF'
#!/usr/bin/env python3
import psycopg2
import time
import random
from datetime import datetime

def generate_track_data():
    """Generate random track data"""
    genres = [1, 2, 3, 4, 5]  # Various genre IDs
    media_types = [1, 2, 3]   # Various media type IDs
    albums = [1, 2, 3, 4, 5]  # Various album IDs
    
    track_names = [
        "Metal Thunder", "Rock Anthem", "Jazz Fusion", "Classical Symphony",
        "Electronic Beat", "Country Road", "Blues Night", "Reggae Sunshine",
        "Hip Hop Flow", "Pop Sensation", "Folk Tale", "Punk Energy"
    ]
    
    composers = [
        "Unknown Artist", "Famous Band", "Solo Artist", "Orchestra",
        "DJ Producer", "Country Singer", "Blues Master", "Reggae King"
    ]
    
    return {
        'name': f"{random.choice(track_names)} {random.randint(1, 1000)}",
        'album_id': random.choice(albums),
        'media_type_id': random.choice(media_types),
        'genre_id': random.choice(genres),
        'composer': random.choice(composers),
        'milliseconds': random.randint(120000, 600000),  # 2-10 minutes
        'bytes': random.randint(2000000, 10000000),      # 2-10MB
        'unit_price': round(random.uniform(0.69, 1.29), 2)
    }

def main():
    try:
        # Connect to PostgreSQL
        conn = psycopg2.connect(
            host="postgres",
            database="chinook",
            user="postgres",
            password="postgres"
        )
        cur = conn.cursor()
        
        print(f"🎵 Starting load generation at {datetime.now()}")
        
        while True:
            # Generate and insert a new track
            track = generate_track_data()
            
            cur.execute("""
                INSERT INTO "Track" ("Name", "AlbumId", "MediaTypeId", "GenreId", "Composer", "Milliseconds", "Bytes", "UnitPrice")
                VALUES (%(name)s, %(album_id)s, %(media_type_id)s, %(genre_id)s, %(composer)s, %(milliseconds)s, %(bytes)s, %(unit_price)s)
                RETURNING "TrackId"
            """, track)
            
            track_id = cur.fetchone()[0]
            conn.commit()
            
            print(f"✅ Inserted track ID {track_id}: {track['name']}")
            
            # Wait before next insert
            time.sleep(random.randint(5, 15))
            
    except KeyboardInterrupt:
        print("\n🛑 Load generation stopped by user")
    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        if 'conn' in locals():
            conn.close()

if __name__ == "__main__":
    main()
EOF

    chmod +x scripts/generate_load.py
    log "Load generation script created"
}

# Function to start services
start_services() {
    log "Starting Docker services..."
    docker-compose up -d
    
    log "Waiting for services to become ready..."
    
    # Wait for Redis Enterprise
    log "Waiting for Redis Enterprise to be ready..."
    local bootstrap_ready=false
    local count=0
    local max_attempts=60  # 5 minutes
    
    while [ $count -lt $max_attempts ] && [ "$bootstrap_ready" = "false" ]; do
        # Check for either 200 (ready) or 401 (ready but needs auth) response
        response=$(curl -k -s -o /dev/null -w "%{http_code}" "https://localhost:9443/v1/bootstrap" 2>/dev/null || echo "000")
        if [[ "$response" == "200" ]] || [[ "$response" == "401" ]]; then
            bootstrap_ready=true
            log "Redis Enterprise bootstrap endpoint is responding (HTTP $response)"
        else
            sleep 5
            count=$((count + 1))
            echo -n "."
        fi
    done
    
    if [ "$bootstrap_ready" = "false" ]; then
        error "Redis Enterprise bootstrap endpoint did not become ready within $((max_attempts * 5)) seconds"
        return 1
    fi
    
    # Wait for PostgreSQL initial startup
    sleep 15
    
    # Check if PostgreSQL container is running (might have crashed due to wal_level)
    if ! docker ps | grep -q postgres; then
        log "PostgreSQL container stopped (likely due to wal_level), restarting..."
        docker-compose restart postgres
        sleep 10
    fi
    
    # Wait for PostgreSQL to be ready
    until docker exec postgres pg_isready -U postgres > /dev/null 2>&1; do
        log "Waiting for PostgreSQL to become ready..."
        sleep 2
    done
    log "PostgreSQL is ready"
    
    # Now create the logical replication components that require restart
    log "Setting up logical replication..."
    docker exec postgres psql -U postgres -d chinook -c "
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'rdi_slot') THEN
                PERFORM pg_create_logical_replication_slot('rdi_slot', 'pgoutput');
            END IF;
        END
        \$\$;
        
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'rdi_publication') THEN
                CREATE PUBLICATION rdi_publication FOR ALL TABLES;
            END IF;
        END
        \$\$;
    "
    
    log "All services are running"
}

# Function to configure Redis Enterprise
configure_redis_enterprise() {
    log "Configuring Redis Enterprise cluster..."
    
    # Fix Redis Enterprise permissions first
    docker exec --user root re-n1 mkdir -p /opt/redislabs/persist
    docker exec --user root re-n1 chown -R redislabs:redislabs /opt/redislabs/persist
    docker exec --user root re-n1 chmod 755 /opt/redislabs/persist
    
    # Create cluster configuration with correct paths
    cat > create_cluster.json << EOF
{
    "action": "create_cluster",
    "cluster": {
        "name": "re-cluster1.ps-redislabs.org"
    },
    "node": {
        "paths": {
            "persistent_path": "/var/opt/redislabs/persist",
            "ephemeral_path": "/var/opt/redislabs/tmp"
        }
    },
    "credentials": {
        "username": "$RE_USER",
        "password": "$PASSWORD"
    },
    "license": ""
}
EOF

    # Create cluster
    docker cp create_cluster.json re-n1:/tmp/create_cluster.json
    docker exec re-n1 curl -k -v --silent --fail \
        -H 'Content-Type: application/json' \
        -d @/tmp/create_cluster.json \
        https://re-n1:9443/v1/bootstrap/create_cluster

    # Wait longer for cluster creation and verify
    sleep 30
    
    # Verify cluster was created successfully
    if curl -k -u $RE_USER:$PASSWORD https://localhost:9443/v1/cluster | grep -q '"name"'; then
        log "Redis Enterprise cluster configured successfully"
    else
        error "Redis Enterprise cluster creation failed"
        return 1
    fi
}

# Function to create Redis databases
create_redis_databases() {
    log "Creating Redis databases..."
    
    # Create target database for synced data
    cat > create_target_db.json << EOF
{
    "name": "target-db",
    "type": "redis",
    "memory_size": 100000000,
    "port": 12000
}
EOF

    # Create RDI database with noeviction policy
    cat > create_rdi_db.json << EOF
{
    "name": "rdi-db", 
    "type": "redis",
    "memory_size": 100000000,
    "port": 12001,
    "eviction_policy": "noeviction"
}
EOF

    # Create the databases
    docker cp create_target_db.json re-n1:/tmp/create_target_db.json
    docker cp create_rdi_db.json re-n1:/tmp/create_rdi_db.json
    
    docker exec re-n1 curl -sk -u $RE_USER:$PASSWORD \
        -H "Content-type: application/json" \
        -d @/tmp/create_target_db.json \
        -X POST https://localhost:9443/v1/bdbs

    sleep 5

    docker exec re-n1 curl -sk -u $RE_USER:$PASSWORD \
        -H "Content-type: application/json" \
        -d @/tmp/create_rdi_db.json \
        -X POST https://localhost:9443/v1/bdbs

    # Verify RDI database has correct eviction policy
    sleep 5
    rdi_policy=$(docker exec re-n1 curl -sk -u $RE_USER:$PASSWORD https://localhost:9443/v1/bdbs | jq -r '.[] | select(.port == 12001) | .eviction_policy')
    if [ "$rdi_policy" = "noeviction" ]; then
        log "RDI database eviction policy correctly set to noeviction"
    else
        warn "RDI database eviction policy is '$rdi_policy', RDI operator may fail"
    fi

    log "Redis databases created"
}

# Function to install RDI
install_rdi() {
    log "Installing RDI (Redis Data Integration)..."
    
    # Create RDI installation directory
    mkdir -p rdi_install
    cd rdi_install
    
    # Download RDI if not exists
    if [ ! -f "rdi-installation-$RDI_VERSION.tar.gz" ]; then
        log "Downloading RDI version $RDI_VERSION..."
        curl -O https://redis-enterprise-software-downloads.s3.amazonaws.com/redis-di/rdi-installation-$RDI_VERSION.tar.gz
    fi
    
    # Extract RDI and find the correct directory
    tar -xzf rdi-installation-$RDI_VERSION.tar.gz
    
    # Find the actual extracted directory name - handle nested structure
    if [ -d "rdi_install/$RDI_VERSION" ]; then
        EXTRACTED_DIR="rdi_install/$RDI_VERSION"
    else
        EXTRACTED_DIR=$(find . -name "install.sh" -type f | head -1 | xargs dirname)
        if [ -z "$EXTRACTED_DIR" ]; then
            error "Could not find install.sh in RDI package"
            return 1
        fi
    fi
    
    log "Found RDI directory: $EXTRACTED_DIR"
    cd "$EXTRACTED_DIR"
    
    # Verify install.sh exists
    if [ ! -f "install.sh" ]; then
        error "install.sh not found in RDI package"
        ls -la
        return 1
    fi
    
    # Create RDI configuration
    cat > silent.toml << EOF
title = "RDI Silent Installer Config"

nameservers = ["8.8.8.8", "8.8.4.4"]
high_availability = false
scaffold = false
deploy = false
db_index = 5
deploy_directory = "/opt/rdi/config"

[rdi.database]
host = "172.16.22.21"
port = 12001
use_existing_rdi = true
password = "$PASSWORD"
ssl = false

[sources.default]
username = "postgres"
password = "postgres"
ssl = false

[targets.default]
username = ""
password = ""
ssl = false
EOF

    # Install RDI with retry logic
    local retries=3
    local count=0
    local success=false
    
    while [ $count -lt $retries ] && [ "$success" = "false" ]; do
        log "RDI installation attempt $((count + 1)) of $retries..."
        
        # Try to install RDI (admin setup should have created compatibility files)
        if bash install.sh -f silent.toml; then
            success=true
            log "RDI installed successfully"
        else
            warn "RDI installation attempt $((count + 1)) failed"
            count=$((count + 1))
            sleep 5
        fi
    done
    
    if [ "$success" = "false" ]; then
        warn "RDI installation failed after $retries attempts"
        echo "Note: Core Redis services are still running without RDI"
        return 1
    fi
    
    cd ../..
    log "RDI installation completed"
}

# Function to display service information
display_services() {
    log "Deployment completed successfully! 🎉"
    echo
    echo -e "${BLUE}📋 Service Access Information:${NC}"
    echo "=================================="
    echo "🔴 Redis Enterprise Web UI:  https://localhost:8443"
    echo "   Username: $RE_USER"
    echo "   Password: $PASSWORD"
    echo
    echo "🔍 Redis Insight:            http://localhost:5540"
    echo "💾 PostgreSQL (SQLPad):      http://localhost:3001"
    echo "   Username: admin@rl.org"
    echo "   Password: redislabs"
    echo
    echo "📊 Direct Database Access:"
    echo "   PostgreSQL: localhost:5432 (postgres/postgres)"
    echo "   Redis Target DB: localhost:12000"
    echo "   Redis RDI DB: localhost:12001"
    echo
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo "1. Access Redis Insight and add your Redis databases"
    echo "2. Configure RDI pipeline using: /opt/rdi/bin/rdi-cli"
    echo "3. Generate test data: docker exec loadgen python3 /scripts/generate_load.py"
    echo
    echo -e "${BLUE}🛠️  Useful Commands:${NC}"
    echo "• Stop all services: docker-compose down"
    echo "• View logs: docker-compose logs [service-name]"
    echo "• Restart services: docker-compose restart"
    echo
    echo -e "${GREEN}✅ All services are running and ready!${NC}"
}

# Main deployment function
main() {
    log "🚀 Starting Redis Workshop Deployment"
    echo
    info "Welcome to the Redis Enterprise + RDI Workshop!"
    echo "This script will deploy all necessary services in Docker containers."
    echo
    
    # Check prerequisites first
    check_prerequisites
    
    # Create necessary files
    create_docker_compose
    create_postgres_init
    create_load_generator
    
    # Deploy services
    start_services
    configure_redis_enterprise
    create_redis_databases
    
    # Install RDI (may fail if additional permissions needed)
    if ! install_rdi; then
        warn "RDI installation failed, but core services are running"
        echo "You can continue with the workshop using Redis Enterprise and PostgreSQL"
    fi
    
    # Display service information
    display_services
}

# Script entry point
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
