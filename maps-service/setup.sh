#!/bin/bash

# Maps Service Setup Script
# Mobile Tactical Deployment Server

set -e

# Colors for output
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
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root for security reasons"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    # Check for required commands
    local required_commands=("docker" "docker-compose" "node" "npm")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command not found: $cmd"
            exit 1
        else
            info "$cmd: $(command -v "$cmd")"
        fi
    done
    
    # Check Docker version
    local docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    info "Docker version: $docker_version"
    
    # Check available memory
    local available_memory=$(free -g | awk 'NR==2{print $7}')
    if [[ $available_memory -lt 8 ]]; then
        warn "Available memory is ${available_memory}GB. Recommended: 8GB+"
    else
        info "Available memory: ${available_memory}GB"
    fi
    
    # Check available disk space
    local available_space=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available_space -lt 500 ]]; then
        warn "Available disk space is ${available_space}GB. Recommended: 500GB+"
    else
        info "Available disk space: ${available_space}GB"
    fi
    
    log "System requirements check complete"
}

# Setup directories
setup_directories() {
    log "Setting up directories..."
    
    # Create maps storage directories
    sudo mkdir -p /mnt/secure_storage/maps/{tiles,data,cache,regions,import,backup}
    sudo mkdir -p /mnt/secure_storage/maps/{postgres,redis}
    
    # Set proper ownership
    sudo chown -R $USER:$USER /mnt/secure_storage/maps
    
    # Create local directories
    mkdir -p logs data static/fonts static/sprites
    
    log "Directories created successfully"
}

# Setup environment
setup_environment() {
    log "Setting up environment configuration..."
    
    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            cp .env.example .env
            info "Created .env file from template"
            
            # Generate random passwords
            local postgres_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
            local maps_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
            local redis_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
            local jwt_secret=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-50)
            
            # Update .env file with generated passwords
            sed -i "s/secure_postgres_password_2024!/$postgres_password/" .env
            sed -i "s/tactical_maps_2024!/$maps_password/" .env
            sed -i "s/redis_tactical_2024!/$redis_password/" .env
            sed -i "s/your_jwt_secret_key_here_change_this_in_production/$jwt_secret/" .env
            
            info "Generated secure passwords and updated .env file"
        else
            error ".env.example file not found"
            exit 1
        fi
    else
        info ".env file already exists"
    fi
}

# Install Node.js dependencies
install_dependencies() {
    log "Installing Node.js dependencies..."
    
    if [[ -f package.json ]]; then
        npm install
        info "Dependencies installed successfully"
    else
        error "package.json not found"
        exit 1
    fi
}

# Make scripts executable
setup_scripts() {
    log "Setting up scripts..."
    
    # Make all scripts executable
    chmod +x scripts/*.sh
    chmod +x setup.sh
    
    info "Scripts made executable"
}

# Create Docker network
setup_network() {
    log "Setting up Docker network..."
    
    # Create tactical network if it doesn't exist
    if ! docker network ls | grep -q "tactical-network"; then
        docker network create tactical-network
        info "Created tactical-network"
    else
        info "tactical-network already exists"
    fi
}

# Initialize database
init_database() {
    log "Initializing database..."
    
    # Start PostgreSQL container
    docker-compose -f docker-compose.maps.yml up -d postgres
    
    # Wait for PostgreSQL to be ready
    info "Waiting for PostgreSQL to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if docker exec tactical-maps-postgres pg_isready -U postgres > /dev/null 2>&1; then
            info "PostgreSQL is ready"
            break
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            error "PostgreSQL failed to start within timeout"
            exit 1
        fi
        
        sleep 2
        ((attempt++))
    done
    
    # Run database schema
    info "Applying database schema..."
    docker exec -i tactical-maps-postgres psql -U postgres < maps-schema.sql
    
    log "Database initialized successfully"
}

# Start services
start_services() {
    log "Starting maps services..."
    
    # Start all services
    docker-compose -f docker-compose.maps.yml up -d
    
    # Wait for services to be ready
    info "Waiting for services to be ready..."
    sleep 30
    
    # Check service health
    local services=("maps-service" "openmaptiles" "redis")
    
    for service in "${services[@]}"; do
        local container_name="tactical-${service}"
        if docker ps | grep -q "$container_name"; then
            info "$service: Running"
        else
            warn "$service: Not running"
        fi
    done
    
    log "Services started"
}

# Import initial map data
import_initial_data() {
    log "Importing initial map data..."
    
    # Run initial setup
    ./scripts/import-maps.sh setup
    
    # Import predefined regions (this may take a while)
    info "This may take several minutes..."
    ./scripts/import-maps.sh import-all
    
    # Generate region packages
    ./scripts/generate-regions.sh generate-all
    
    log "Initial map data imported"
}

# Validate installation
validate_installation() {
    log "Validating installation..."
    
    # Run validation script
    ./scripts/validate-maps.sh full
    
    if [[ $? -eq 0 ]]; then
        log "✅ Installation validation passed"
    else
        error "❌ Installation validation failed"
        exit 1
    fi
}

# Display completion message
show_completion() {
    log "🎉 Maps service setup complete!"
    echo ""
    info "Services are running on:"
    info "  Maps Service:    http://localhost:8080"
    info "  OpenMapTiles:    http://localhost:8081"
    info "  Nginx Proxy:     http://localhost:8082"
    info "  Tactical Maps:   http://localhost:8080/static/tactical-map-interface.html"
    echo ""
    info "Useful commands:"
    info "  View logs:       docker-compose -f docker-compose.maps.yml logs -f"
    info "  Stop services:   docker-compose -f docker-compose.maps.yml down"
    info "  Restart:         docker-compose -f docker-compose.maps.yml restart"
    info "  Validate:        ./scripts/validate-maps.sh full"
    echo ""
    info "Configuration files:"
    info "  Environment:     .env"
    info "  Map config:      map-config.json"
    info "  Regions:         regions.json"
    info "  Style:           tactical-style.json"
    echo ""
    warn "Remember to:"
    warn "  1. Backup your .env file (contains passwords)"
    warn "  2. Configure firewall rules for production"
    warn "  3. Set up SSL certificates for HTTPS"
    warn "  4. Review and customize tactical regions"
}

# Main setup function
main() {
    echo "🗺️  Mobile Tactical Deployment Server - Maps Service Setup"
    echo "========================================================"
    echo ""
    
    check_root
    check_requirements
    setup_directories
    setup_environment
    install_dependencies
    setup_scripts
    setup_network
    init_database
    start_services
    
    # Ask if user wants to import initial data (can take a long time)
    echo ""
    read -p "Import initial map data? This may take 30+ minutes (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        import_initial_data
    else
        info "Skipping initial data import. You can run it later with:"
        info "  ./scripts/import-maps.sh import-all"
    fi
    
    validate_installation
    show_completion
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --skip-data         Skip initial data import"
        echo "  --validate-only     Only run validation"
        echo ""
        echo "This script sets up the Maps Service for the Mobile Tactical Deployment Server."
        exit 0
        ;;
    --skip-data)
        SKIP_DATA=true
        ;;
    --validate-only)
        validate_installation
        exit 0
        ;;
esac

# Run main setup
main "$@"