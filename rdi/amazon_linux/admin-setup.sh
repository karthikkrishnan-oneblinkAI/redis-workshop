#!/bin/bash

# Redis Enterprise + RDI Admin Setup Script for Amazon Linux
# This script sets up the system prerequisites and prepares the environment
# for Redis workshop deployment. Must be run by system administrators with sudo.

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install system prerequisites
install_system_prerequisites() {
    log "Installing system prerequisites for Amazon Linux..."
    
    # Check if running as root or with sudo
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run with sudo privileges"
        echo "Usage: sudo $0"
        exit 1
    fi
    
    # Update system
    log "Updating system packages..."
    yum update -y
    
    # Install essential packages
    log "Installing essential packages..."
    yum install -y \
        docker \
        git \
        jq \
        wget \
        gettext \
        tar \
        gzip \
        python3 \
        python3-pip \
        curl \
        unzip
    
    # Install Docker Compose
    log "Installing Docker Compose..."
    if ! command_exists docker-compose; then
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        
        # Verify installation
        if docker-compose --version; then
            log "Docker Compose installed successfully"
        else
            error "Docker Compose installation failed"
            exit 1
        fi
    else
        log "Docker Compose already installed"
    fi
    
    log "System prerequisites installed successfully"
}

# Function to configure Docker service
configure_docker() {
    log "Configuring Docker service..."
    
    # Configure Docker daemon for better performance
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Verify Docker is running
    if systemctl is-active --quiet docker; then
        log "Docker service is running"
    else
        error "Failed to start Docker service"
        exit 1
    fi
}

# Function to setup user permissions for all users
setup_user_permissions() {
    log "Setting up user permissions..."
    
    # Add ec2-user to docker group (default Amazon Linux user)
    if id "ec2-user" &>/dev/null; then
        usermod -aG docker ec2-user
        log "Added ec2-user to docker group"
    fi
    
    # Add any other existing users to docker group
    for user_home in /home/*; do
        if [ -d "$user_home" ]; then
            username=$(basename "$user_home")
            if id "$username" &>/dev/null && [ "$username" != "ec2-user" ]; then
                usermod -aG docker "$username"
                log "Added $username to docker group"
            fi
        fi
    done
    
    # Create workshop directory structure
    mkdir -p /opt/redis-workshop
    chmod 755 /opt/redis-workshop
    
    # Create a shared directory for workshop files
    mkdir -p /home/ec2-user/redis-workshop
    chown ec2-user:ec2-user /home/ec2-user/redis-workshop
    chmod 755 /home/ec2-user/redis-workshop
    
    log "User permissions configured"
}

# Function to setup RDI compatibility
setup_rdi_compatibility() {
    log "Setting up RDI compatibility for Amazon Linux..."
    
    # Check if redhat-release already exists
    if [ -f /etc/redhat-release ]; then
        warn "File /etc/redhat-release already exists"
        info "Current content: $(cat /etc/redhat-release)"
    else
        # Create fake RHEL release file for RDI compatibility
        log "Creating /etc/redhat-release for RDI compatibility..."
        echo "Red Hat Enterprise Linux release 9.0 (Plow)" > /etc/redhat-release
        chmod 644 /etc/redhat-release
        chown root:root /etc/redhat-release
        log "RDI compatibility file created"
    fi
}

# Function to install Python dependencies for load generator
install_python_deps() {
    log "Installing Python dependencies..."
    
    # Install psycopg2 for PostgreSQL connectivity
    pip3 install psycopg2-binary --break-system-packages 2>/dev/null || pip3 install psycopg2-binary
    
    log "Python dependencies installed"
}

# Function to pre-download Docker images
predownload_images() {
    log "Pre-downloading Docker images for faster deployment..."
    
    # Start Docker if not running
    if ! systemctl is-active --quiet docker; then
        systemctl start docker
    fi
    
    # Pre-download commonly used images
    local images=(
        "redislabs/redis:latest"
        "postgres:13"
        "redislabs/redisinsight:latest"
        "sqlpad/sqlpad:latest"
        "python:3.9-slim"
    )
    
    for image in "${images[@]}"; do
        log "Downloading $image..."
        docker pull "$image" &
    done
    
    # Wait for all downloads to complete
    wait
    log "Docker images pre-downloaded"
}

# Function to create documentation
create_documentation() {
    log "Creating system documentation..."
    
    cat > /home/ec2-user/WORKSHOP_SETUP.md << 'EOF'
# Redis Enterprise + RDI Workshop Setup

## System Configuration

This system has been configured for Redis Enterprise + RDI workshop deployment.

### Pre-installed Components
- Docker and Docker Compose
- Git, jq, wget, curl
- Python 3 with psycopg2
- Pre-downloaded Docker images

### System Modifications
- Users added to docker group for container access
- RDI compatibility file created (`/etc/redhat-release`)
- Docker daemon configured for optimal performance

### Workshop Deployment
Users can now run the workshop deployment with:
```bash
./start.sh
```

No sudo privileges required for workshop participants.

### Troubleshooting
- If Docker permission errors occur, users may need to log out and back in
- Alternatively, run: `newgrp docker`

### Support
For issues with the workshop environment, contact your system administrator.
EOF

    chown ec2-user:ec2-user /home/ec2-user/WORKSHOP_SETUP.md
    log "Documentation created at /home/ec2-user/WORKSHOP_SETUP.md"
}

# Function to verify installation
verify_installation() {
    log "Verifying system setup..."
    
    local errors=0
    
    # Check Docker
    if systemctl is-active --quiet docker; then
        log "✅ Docker service is running"
    else
        error "❌ Docker service is not running"
        errors=$((errors + 1))
    fi
    
    # Check Docker Compose
    if command_exists docker-compose; then
        log "✅ Docker Compose is installed: $(docker-compose --version)"
    else
        error "❌ Docker Compose is not installed"
        errors=$((errors + 1))
    fi
    
    # Check RDI compatibility
    if [ -f /etc/redhat-release ]; then
        log "✅ RDI compatibility file exists"
    else
        error "❌ RDI compatibility file missing"
        errors=$((errors + 1))
    fi
    
    # Check Python dependencies
    if python3 -c "import psycopg2" 2>/dev/null; then
        log "✅ Python PostgreSQL driver available"
    else
        warn "⚠️  Python PostgreSQL driver not available"
    fi
    
    # Check Docker images
    local image_count=$(docker images -q | wc -l)
    if [ "$image_count" -gt 0 ]; then
        log "✅ Docker images available: $image_count images"
    else
        warn "⚠️  No Docker images pre-downloaded"
    fi
    
    if [ $errors -eq 0 ]; then
        log "All critical components verified successfully"
        return 0
    else
        error "Setup verification failed with $errors errors"
        return 1
    fi
}

# Function to display completion summary
display_completion() {
    log "Admin setup completed! 🎉"
    echo
    info "📋 Setup Summary:"
    echo "=================================="
    echo "✅ System packages installed and updated"
    echo "✅ Docker and Docker Compose configured"
    echo "✅ User permissions configured for workshop"
    echo "✅ RDI compatibility enabled for Amazon Linux"
    echo "✅ Python dependencies installed"
    echo "✅ Docker images pre-downloaded"
    echo "✅ Documentation created"
    echo
    info "🚀 Next Steps:"
    echo "1. Workshop participants can now run: ./start.sh"
    echo "2. No sudo privileges required for workshop deployment"
    echo "3. All services will run in Docker containers"
    echo
    info "📝 Notes:"
    echo "• Users may need to log out/in for Docker group membership"
    echo "• Workshop files will be created in user home directories"
    echo "• System is ready for VS Code terminal usage"
    echo
    log "✅ System is ready for Redis Enterprise + RDI workshops!"
}

# Main function
main() {
    log "🔧 Starting Redis Enterprise + RDI Admin Setup"
    echo
    
    # Display system information
    info "System Information:"
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
    echo "User: $(whoami)"
    echo "Date: $(date)"
    echo
    
    # Run setup steps
    install_system_prerequisites
    configure_docker
    setup_user_permissions
    setup_rdi_compatibility
    install_python_deps
    predownload_images
    create_documentation
    
    # Verify everything is working
    if verify_installation; then
        display_completion
    else
        error "Setup completed with some issues. Please review the errors above."
        exit 1
    fi
}

# Script entry point
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
