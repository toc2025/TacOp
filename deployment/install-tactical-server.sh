#!/bin/bash
# Mobile Tactical Deployment Server - Master Installation Script
# Version: 1.0.0
# Target: 10-minute deployment from fresh Raspberry Pi 5

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/tactical-server-install.log"
INSTALL_START_TIME=$(date +%s)
ZEROTIER_NETWORK_ID=""
ADMIN_EMAIL=""
DOMAIN_NAME="tactical.local"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Progress tracking
TOTAL_STEPS=12
CURRENT_STEP=0

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo -e "${BLUE}[PROGRESS]${NC} Step $CURRENT_STEP/$TOTAL_STEPS ($percentage%) - $1" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Use: sudo $0"
    fi
}

# System validation
validate_system() {
    progress "Validating system requirements"
    
    # Check if Raspberry Pi 5
    if ! grep -q "Raspberry Pi 5" /proc/cpuinfo 2>/dev/null; then
        warning "Not running on Raspberry Pi 5 - performance may vary"
    fi
    
    # Check RAM (minimum 8GB recommended)
    local ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $ram_gb -lt 8 ]]; then
        warning "Less than 8GB RAM detected ($ram_gb GB) - performance may be limited"
    else
        log "RAM check passed: ${ram_gb}GB available"
    fi
    
    # Check storage (minimum 64GB)
    local storage_gb=$(df -BG / | awk 'NR==2{print $2}' | sed 's/G//')
    if [[ $storage_gb -lt 64 ]]; then
        error "Insufficient storage: ${storage_gb}GB (minimum 64GB required)"
    else
        log "Storage check passed: ${storage_gb}GB available"
    fi
    
    # Check network connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        error "No internet connectivity - required for installation"
    fi
    
    log "System validation completed successfully"
}

# Update system packages
update_system() {
    progress "Updating system packages"
    
    export DEBIAN_FRONTEND=noninteractive
    
    # Update package lists
    apt-get update -qq
    
    # Upgrade system packages
    apt-get upgrade -y -qq
    
    # Install essential packages
    apt-get install -y -qq \
        curl \
        wget \
        git \
        unzip \
        htop \
        nano \
        ufw \
        fail2ban \
        openssl \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        build-essential \
        python3 \
        python3-pip \
        jq \
        rsync \
        cron
    
    log "System packages updated successfully"
}

# Configure security hardening
configure_security() {
    progress "Configuring security hardening"
    
    # Configure UFW firewall
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (current session)
    ufw allow ssh
    
    # Allow tactical server ports
    ufw allow 80/tcp comment "HTTP"
    ufw allow 443/tcp comment "HTTPS"
    ufw allow 8080/tcp comment "Maps Service"
    ufw allow 8443/tcp comment "Location WebSocket"
    ufw allow 3000/tcp comment "Mattermost"
    ufw allow 9993/udp comment "ZeroTier"
    
    # Enable firewall
    ufw --force enable
    
    # Configure Fail2Ban
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    
    # Create tactical-specific jail
    cat > /etc/fail2ban/jail.d/tactical.conf << 'EOF'
[tactical-ssh]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600

[tactical-nginx]
enabled = true
port = http,https
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 5
bantime = 600
findtime = 600
EOF
    
    # Restart Fail2Ban
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    # SSH hardening
    sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    
    # Create tactical user if not exists
    if ! id "tactical" &>/dev/null; then
        useradd -m -s /bin/bash tactical
        usermod -aG sudo tactical
        log "Created tactical user"
    fi
    
    log "Security hardening completed"
}

# Install Docker and Docker Compose
install_docker() {
    progress "Installing Docker and Docker Compose"
    
    # Remove old Docker versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index
    apt-get update -qq
    
    # Install Docker Engine
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Add tactical user to docker group
    usermod -aG docker tactical
    
    # Verify Docker installation
    docker --version
    docker compose version
    
    log "Docker installation completed"
}

# Install ZeroTier
install_zerotier() {
    progress "Installing ZeroTier VPN"
    
    # Install ZeroTier
    curl -s https://install.zerotier.com | bash
    
    # Start and enable ZeroTier service
    systemctl start zerotier-one
    systemctl enable zerotier-one
    
    # Get ZeroTier address
    local zt_address=$(zerotier-cli info | cut -d' ' -f3)
    log "ZeroTier installed - Node ID: $zt_address"
    
    # Join network if provided
    if [[ -n "$ZEROTIER_NETWORK_ID" ]]; then
        zerotier-cli join "$ZEROTIER_NETWORK_ID"
        log "Joined ZeroTier network: $ZEROTIER_NETWORK_ID"
    else
        warning "No ZeroTier network ID provided - manual network join required"
    fi
}

# Setup storage directories
setup_storage() {
    progress "Setting up storage directories"
    
    # Create secure storage directory
    mkdir -p /mnt/secure_storage/{maps,ssl,data,backups,logs}
    mkdir -p /mnt/secure_storage/maps/{tiles,data,cache,postgres,redis}
    mkdir -p /mnt/secure_storage/data/{postgresql,redis,outline,mattermost,filebrowser}
    
    # Set permissions
    chown -R tactical:tactical /mnt/secure_storage
    chmod -R 755 /mnt/secure_storage
    
    # Create tactical deployment directory
    mkdir -p /opt/tactical-server
    cp -r "$SCRIPT_DIR"/* /opt/tactical-server/
    chown -R tactical:tactical /opt/tactical-server
    
    log "Storage directories created"
}

# Generate SSL certificates
generate_ssl_certificates() {
    progress "Generating SSL certificates"
    
    local ssl_dir="/mnt/secure_storage/ssl"
    
    # Generate self-signed certificate for tactical.local
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$ssl_dir/tactical.key" \
        -out "$ssl_dir/tactical.crt" \
        -subj "/C=US/ST=State/L=City/O=Tactical/OU=Operations/CN=$DOMAIN_NAME" \
        -addext "subjectAltName=DNS:$DOMAIN_NAME,DNS:localhost,IP:127.0.0.1,IP:192.168.100.1"
    
    # Set proper permissions
    chmod 600 "$ssl_dir/tactical.key"
    chmod 644 "$ssl_dir/tactical.crt"
    chown tactical:tactical "$ssl_dir"/*
    
    log "SSL certificates generated"
}

# Configure environment variables
configure_environment() {
    progress "Configuring environment variables"
    
    # Generate secure passwords
    local postgres_password=$(openssl rand -base64 32)
    local redis_password=$(openssl rand -base64 32)
    local jwt_secret=$(openssl rand -base64 64)
    local outline_secret=$(openssl rand -base64 32)
    local mattermost_secret=$(openssl rand -base64 32)
    
    # Create production environment file
    cat > /opt/tactical-server/.env.production << EOF
# Tactical Server Production Environment
# Generated: $(date)

# Network Configuration
ZEROTIER_NETWORK_ID=${ZEROTIER_NETWORK_ID}
DOMAIN_NAME=${DOMAIN_NAME}
SERVER_IP=192.168.100.1

# Database Configuration
POSTGRES_PASSWORD=${postgres_password}
LOCATION_DB_PASSWORD=${postgres_password}
MAPS_DB_PASSWORD=${postgres_password}
OUTLINE_DB_PASSWORD=${postgres_password}
MATTERMOST_DB_PASSWORD=${postgres_password}

# Redis Configuration
REDIS_PASSWORD=${redis_password}

# Security Configuration
JWT_SECRET=${jwt_secret}
OUTLINE_SECRET_KEY=${outline_secret}
MATTERMOST_SECRET=${mattermost_secret}

# SSL Configuration
SSL_CERT_PATH=/mnt/secure_storage/ssl/tactical.crt
SSL_KEY_PATH=/mnt/secure_storage/ssl/tactical.key

# Storage Configuration
DATA_PATH=/mnt/secure_storage/data
MAPS_PATH=/mnt/secure_storage/maps
LOGS_PATH=/mnt/secure_storage/logs

# Service Configuration
NODE_ENV=production
LOG_LEVEL=info

# Admin Configuration
ADMIN_EMAIL=${ADMIN_EMAIL}
EOF
    
    # Set secure permissions
    chmod 600 /opt/tactical-server/.env.production
    chown tactical:tactical /opt/tactical-server/.env.production
    
    log "Environment configuration completed"
}

# Deploy Docker services
deploy_services() {
    progress "Deploying Docker services"
    
    cd /opt/tactical-server
    
    # Create Docker network
    docker network create tactical-network --subnet=172.20.0.0/16 || true
    
    # Pull all required images
    info "Pulling Docker images..."
    docker compose -f docker-compose.yml --env-file .env.production pull
    
    # Start services in dependency order
    info "Starting core services..."
    docker compose -f docker-compose.yml --env-file .env.production up -d postgresql redis
    
    # Wait for databases to be ready
    sleep 30
    
    info "Starting application services..."
    docker compose -f docker-compose.yml --env-file .env.production up -d
    
    log "Docker services deployed"
}

# Initialize databases
initialize_databases() {
    progress "Initializing databases"
    
    cd /opt/tactical-server
    
    # Wait for PostgreSQL to be fully ready
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if docker compose exec -T postgresql pg_isready -U postgres >/dev/null 2>&1; then
            break
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        error "PostgreSQL failed to start within timeout"
    fi
    
    # Initialize databases
    docker compose exec -T postgresql psql -U postgres -c "CREATE DATABASE IF NOT EXISTS tactical_location;"
    docker compose exec -T postgresql psql -U postgres -c "CREATE DATABASE IF NOT EXISTS tactical_maps;"
    docker compose exec -T postgresql psql -U postgres -c "CREATE DATABASE IF NOT EXISTS outline;"
    docker compose exec -T postgresql psql -U postgres -c "CREATE DATABASE IF NOT EXISTS mattermost;"
    
    log "Databases initialized"
}

# Configure system services
configure_system_services() {
    progress "Configuring system services"
    
    # Create systemd service for tactical server
    cat > /etc/systemd/system/tactical-server.service << 'EOF'
[Unit]
Description=Tactical Server Docker Compose
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/tactical-server
ExecStart=/usr/bin/docker compose -f docker-compose.yml --env-file .env.production up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml --env-file .env.production down
TimeoutStartSec=0
User=tactical
Group=tactical

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable tactical server service
    systemctl daemon-reload
    systemctl enable tactical-server.service
    
    # Create health check cron job
    cat > /etc/cron.d/tactical-health << 'EOF'
# Tactical Server Health Check - Every 5 minutes
*/5 * * * * tactical /opt/tactical-server/health-check.sh >> /var/log/tactical-health.log 2>&1
EOF
    
    # Create backup cron job
    cat > /etc/cron.d/tactical-backup << 'EOF'
# Tactical Server Backup - Daily at 2 AM
0 2 * * * tactical /opt/tactical-server/backup-data.sh >> /var/log/tactical-backup.log 2>&1
EOF
    
    log "System services configured"
}

# Verify installation
verify_installation() {
    progress "Verifying installation"
    
    cd /opt/tactical-server
    
    # Check Docker services
    local failed_services=()
    local services=("postgresql" "redis" "zerotier-controller" "nginx" "location-service" "maps-service" "outline" "mattermost" "filebrowser")
    
    for service in "${services[@]}"; do
        if ! docker compose ps "$service" | grep -q "Up"; then
            failed_services+=("$service")
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        warning "Some services failed to start: ${failed_services[*]}"
        info "Check logs with: docker compose logs [service-name]"
    else
        log "All services are running successfully"
    fi
    
    # Test network connectivity
    if curl -k -s https://localhost/health >/dev/null; then
        log "Web interface is accessible"
    else
        warning "Web interface may not be ready yet"
    fi
    
    # Display service URLs
    info "Service URLs:"
    info "  Main Interface: https://$DOMAIN_NAME"
    info "  Location Service: https://$DOMAIN_NAME:8443"
    info "  Maps Service: https://$DOMAIN_NAME:8080"
    info "  Mattermost: https://$DOMAIN_NAME:3000"
    info "  Outline: https://$DOMAIN_NAME:3001"
    info "  FileBrowser: https://$DOMAIN_NAME:8081"
}

# Performance optimization
optimize_performance() {
    progress "Optimizing system performance"
    
    # Optimize Docker daemon
    cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 64000,
            "Soft": 64000
        }
    }
}
EOF
    
    # Restart Docker to apply changes
    systemctl restart docker
    
    # Optimize system parameters
    cat >> /etc/sysctl.conf << 'EOF'

# Tactical Server Optimizations
vm.max_map_count=262144
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
net.core.netdev_max_backlog=5000
EOF
    
    # Apply sysctl changes
    sysctl -p
    
    log "Performance optimization completed"
}

# Main installation function
main() {
    log "Starting Tactical Server installation..."
    log "Target deployment time: 10 minutes"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --zerotier-network)
                ZEROTIER_NETWORK_ID="$2"
                shift 2
                ;;
            --admin-email)
                ADMIN_EMAIL="$2"
                shift 2
                ;;
            --domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --zerotier-network ID    ZeroTier network ID to join"
                echo "  --admin-email EMAIL      Administrator email address"
                echo "  --domain DOMAIN          Domain name (default: tactical.local)"
                echo "  --help                   Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Prompt for required information if not provided
    if [[ -z "$ZEROTIER_NETWORK_ID" ]]; then
        read -p "Enter ZeroTier Network ID (optional): " ZEROTIER_NETWORK_ID
    fi
    
    if [[ -z "$ADMIN_EMAIL" ]]; then
        read -p "Enter administrator email: " ADMIN_EMAIL
    fi
    
    # Execute installation steps
    check_root
    validate_system
    update_system
    configure_security
    install_docker
    install_zerotier
    setup_storage
    generate_ssl_certificates
    configure_environment
    deploy_services
    initialize_databases
    configure_system_services
    optimize_performance
    verify_installation
    
    # Calculate installation time
    local install_end_time=$(date +%s)
    local install_duration=$((install_end_time - INSTALL_START_TIME))
    local minutes=$((install_duration / 60))
    local seconds=$((install_duration % 60))
    
    log "Installation completed successfully!"
    log "Total installation time: ${minutes}m ${seconds}s"
    
    if [[ $install_duration -le 600 ]]; then
        log "✅ Target deployment time achieved (under 10 minutes)"
    else
        warning "⚠️  Installation took longer than target (10 minutes)"
    fi
    
    # Display final information
    echo
    echo "=========================================="
    echo "  TACTICAL SERVER INSTALLATION COMPLETE"
    echo "=========================================="
    echo
    echo "Services Status:"
    docker compose -f /opt/tactical-server/docker-compose.yml ps
    echo
    echo "Access URLs:"
    echo "  Main Interface: https://$DOMAIN_NAME"
    echo "  ZeroTier Network: $ZEROTIER_NETWORK_ID"
    echo
    echo "Next Steps:"
    echo "1. Configure ZeroTier network authorization"
    echo "2. Access the tactical interface"
    echo "3. Configure team member devices"
    echo
    echo "Logs: $LOG_FILE"
    echo "Configuration: /opt/tactical-server"
    echo
}

# Trap errors and cleanup
trap 'error "Installation failed at step $CURRENT_STEP"' ERR

# Run main installation
main "$@"