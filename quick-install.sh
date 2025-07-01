#!/bin/bash
# Mobile Tactical Deployment Server - Quick Installation Script
# Version: 1.0.0
# One-liner installation for rapid tactical deployment

set -euo pipefail

# Configuration
REPO_URL="https://github.com/tactical-ops/tacop.git"
REPO_BRANCH="main"
INSTALL_DIR="/opt/tactical-server"
LOG_FILE="/var/log/tactical-quick-install.log"
SCRIPT_VERSION="1.0.0"

# Default parameters
ZEROTIER_NETWORK_ID=""
ADMIN_EMAIL=""
DOMAIN_NAME="tactical.local"
SKIP_HARDWARE_CHECK=false
DEVELOPMENT_MODE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ASCII Art Banner
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
████████╗ █████╗  ██████╗ ████████╗██╗ ██████╗ █████╗ ██╗     
╚══██╔══╝██╔══██╗██╔════╝ ╚══██╔══╝██║██╔════╝██╔══██╗██║     
   ██║   ███████║██║         ██║   ██║██║     ███████║██║     
   ██║   ██╔══██║██║         ██║   ██║██║     ██╔══██║██║     
   ██║   ██║  ██║╚██████╗    ██║   ██║╚██████╗██║  ██║███████╗
   ╚═╝   ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝
                                                               
    ██████╗ ██████╗ ███████╗██████╗  █████╗ ████████╗██╗ ██████╗ ███╗   ██╗███████╗
   ██╔═══██╗██╔══██╗██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝
   ██║   ██║██████╔╝█████╗  ██████╔╝███████║   ██║   ██║██║   ██║██╔██╗ ██║███████╗
   ██║   ██║██╔═══╝ ██╔══╝  ██╔══██╗██╔══██║   ██║   ██║██║   ██║██║╚██╗██║╚════██║
   ╚██████╔╝██║     ███████╗██║  ██║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║███████║
    ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
EOF
    echo -e "${NC}"
    echo -e "${GREEN}Mobile Tactical Deployment Server - Quick Install v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}Deploy a complete tactical server in under 10 minutes${NC}"
    echo ""
}

# Logging functions
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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

progress() {
    echo -e "${PURPLE}[PROGRESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Use: sudo $0"
    fi
}

# Validate system requirements
validate_system() {
    progress "Validating system requirements..."
    
    # Check if Raspberry Pi (unless skipped)
    if [[ "$SKIP_HARDWARE_CHECK" == false ]]; then
        if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
            warning "Not running on Raspberry Pi - performance may vary"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                error "Installation cancelled"
            fi
        else
            success "Raspberry Pi detected"
        fi
    fi
    
    # Check RAM (minimum 4GB, recommended 8GB+)
    local ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $ram_gb -lt 4 ]]; then
        error "Insufficient RAM: ${ram_gb}GB (minimum 4GB required)"
    elif [[ $ram_gb -lt 8 ]]; then
        warning "Limited RAM: ${ram_gb}GB (8GB+ recommended for optimal performance)"
    else
        success "RAM check passed: ${ram_gb}GB available"
    fi
    
    # Check storage (minimum 32GB, recommended 64GB+)
    local storage_gb=$(df -BG / | awk 'NR==2{print $2}' | sed 's/G//')
    if [[ $storage_gb -lt 32 ]]; then
        error "Insufficient storage: ${storage_gb}GB (minimum 32GB required)"
    elif [[ $storage_gb -lt 64 ]]; then
        warning "Limited storage: ${storage_gb}GB (64GB+ recommended)"
    else
        success "Storage check passed: ${storage_gb}GB available"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        error "No internet connectivity - required for installation"
    fi
    
    success "System validation completed"
}

# Install prerequisites
install_prerequisites() {
    progress "Installing prerequisites..."
    
    # Update package lists
    apt-get update -qq
    
    # Install essential packages
    apt-get install -y -qq \
        curl \
        wget \
        git \
        unzip \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common
    
    success "Prerequisites installed"
}

# Clone repository
clone_repository() {
    progress "Cloning tactical server repository..."
    
    # Remove existing installation if present
    if [[ -d "$INSTALL_DIR" ]]; then
        warning "Existing installation found at $INSTALL_DIR"
        read -p "Remove and reinstall? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
        else
            error "Installation cancelled"
        fi
    fi
    
    # Clone repository
    git clone --branch "$REPO_BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
    
    # Set permissions
    chown -R root:root "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR/deployment/install-tactical-server.sh"
    
    success "Repository cloned to $INSTALL_DIR"
}

# Prepare installation parameters
prepare_installation() {
    progress "Preparing installation parameters..."
    
    # Create installation command
    local install_cmd="$INSTALL_DIR/deployment/install-tactical-server.sh"
    
    # Add parameters
    if [[ -n "$ZEROTIER_NETWORK_ID" ]]; then
        install_cmd="$install_cmd --zerotier-network $ZEROTIER_NETWORK_ID"
    fi
    
    if [[ -n "$ADMIN_EMAIL" ]]; then
        install_cmd="$install_cmd --admin-email $ADMIN_EMAIL"
    fi
    
    if [[ "$DOMAIN_NAME" != "tactical.local" ]]; then
        install_cmd="$install_cmd --domain $DOMAIN_NAME"
    fi
    
    echo "$install_cmd" > /tmp/tactical-install-command
    success "Installation parameters prepared"
}

# Execute main installation
execute_installation() {
    progress "Executing main installation script..."
    
    local install_cmd=$(cat /tmp/tactical-install-command)
    
    info "Running: $install_cmd"
    
    # Execute installation with real-time output
    if $install_cmd; then
        success "Main installation completed successfully"
    else
        error "Main installation failed - check logs for details"
    fi
    
    # Cleanup
    rm -f /tmp/tactical-install-command
}

# Post-installation setup
post_installation() {
    progress "Performing post-installation setup..."
    
    # Create quick access scripts
    create_management_scripts
    
    # Setup automatic updates (optional)
    setup_auto_updates
    
    # Create desktop shortcuts (if GUI available)
    create_shortcuts
    
    success "Post-installation setup completed"
}

# Create management scripts
create_management_scripts() {
    local bin_dir="/usr/local/bin"
    
    # Create tactical command
    cat > "$bin_dir/tactical" << 'EOF'
#!/bin/bash
# Tactical Server Management Command

case "$1" in
    status)
        cd /opt/tactical-server && ./health-check.sh
        ;;
    start)
        systemctl start tactical-server
        ;;
    stop)
        systemctl stop tactical-server
        ;;
    restart)
        systemctl restart tactical-server
        ;;
    logs)
        cd /opt/tactical-server && docker-compose logs -f
        ;;
    backup)
        cd /opt/tactical-server && ./backup-data.sh
        ;;
    update)
        cd /opt/tactical-server && git pull && docker-compose pull && docker-compose up -d
        ;;
    *)
        echo "Usage: tactical {status|start|stop|restart|logs|backup|update}"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$bin_dir/tactical"
    
    info "Created 'tactical' management command"
}

# Setup automatic updates
setup_auto_updates() {
    if [[ "$DEVELOPMENT_MODE" == false ]]; then
        # Create update script
        cat > /etc/cron.weekly/tactical-update << 'EOF'
#!/bin/bash
# Weekly tactical server updates
cd /opt/tactical-server
git pull origin main
docker-compose pull
docker-compose up -d
EOF
        
        chmod +x /etc/cron.weekly/tactical-update
        info "Automatic weekly updates configured"
    fi
}

# Create desktop shortcuts
create_shortcuts() {
    local desktop_dir="/home/pi/Desktop"
    
    if [[ -d "$desktop_dir" ]]; then
        # Create tactical interface shortcut
        cat > "$desktop_dir/Tactical-Interface.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Tactical Interface
Comment=Access Tactical Server Interface
Exec=chromium-browser --app=https://tactical.local
Icon=applications-internet
Terminal=false
Categories=Network;
EOF
        
        chmod +x "$desktop_dir/Tactical-Interface.desktop"
        chown pi:pi "$desktop_dir/Tactical-Interface.desktop"
        
        info "Desktop shortcuts created"
    fi
}

# Display installation results
show_results() {
    local install_end_time=$(date +%s)
    local install_duration=$((install_end_time - install_start_time))
    local minutes=$((install_duration / 60))
    local seconds=$((install_duration % 60))
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                 INSTALLATION COMPLETED                       ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📊 Installation Summary:${NC}"
    echo -e "   ⏱️  Total Time: ${minutes}m ${seconds}s"
    echo -e "   🎯 Target: Under 10 minutes"
    
    if [[ $install_duration -le 600 ]]; then
        echo -e "   ✅ ${GREEN}Target achieved!${NC}"
    else
        echo -e "   ⚠️  ${YELLOW}Exceeded target time${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}🌐 Access Information:${NC}"
    echo -e "   🏠 Main Interface: ${GREEN}https://$DOMAIN_NAME${NC}"
    echo -e "   📱 Mobile PWA: ${GREEN}https://$DOMAIN_NAME${NC} (Add to home screen)"
    echo -e "   🗺️  Maps Service: ${GREEN}https://$DOMAIN_NAME:8080${NC}"
    echo -e "   💬 Communications: ${GREEN}https://$DOMAIN_NAME:3000${NC}"
    echo -e "   📝 Knowledge Base: ${GREEN}https://$DOMAIN_NAME:3001${NC}"
    echo -e "   📁 File Manager: ${GREEN}https://$DOMAIN_NAME:8081${NC}"
    
    if [[ -n "$ZEROTIER_NETWORK_ID" ]]; then
        echo ""
        echo -e "${CYAN}🔗 ZeroTier Network:${NC}"
        echo -e "   🆔 Network ID: ${GREEN}$ZEROTIER_NETWORK_ID${NC}"
        echo -e "   📱 Mobile Setup: Install ZeroTier app and join network"
    fi
    
    echo ""
    echo -e "${CYAN}🛠️  Management Commands:${NC}"
    echo -e "   📊 Status: ${GREEN}tactical status${NC}"
    echo -e "   🔄 Restart: ${GREEN}tactical restart${NC}"
    echo -e "   📋 Logs: ${GREEN}tactical logs${NC}"
    echo -e "   💾 Backup: ${GREEN}tactical backup${NC}"
    echo -e "   🔄 Update: ${GREEN}tactical update${NC}"
    
    echo ""
    echo -e "${CYAN}📚 Next Steps:${NC}"
    echo -e "   1. 📱 Install ZeroTier on team devices"
    echo -e "   2. 🔗 Join devices to network: $ZEROTIER_NETWORK_ID"
    echo -e "   3. 📱 Install PWA from: https://$DOMAIN_NAME"
    echo -e "   4. 🗺️  Upload map data to: /mnt/secure_storage/maps/"
    echo -e "   5. 👥 Configure team members in Outline"
    
    echo ""
    echo -e "${CYAN}📖 Documentation:${NC}"
    echo -e "   📋 Installation Logs: ${GREEN}/var/log/tactical-server-install.log${NC}"
    echo -e "   📚 Full Documentation: ${GREEN}$INSTALL_DIR/README.md${NC}"
    echo -e "   🆘 Support: ${GREEN}https://github.com/tactical-ops/tacop/issues${NC}"
    
    echo ""
    echo -e "${GREEN}🎉 Tactical server is ready for deployment!${NC}"
    echo ""
}

# Show help
show_help() {
    cat << EOF
Mobile Tactical Deployment Server - Quick Install

Usage: $0 [OPTIONS]

Options:
  --zerotier-network ID     ZeroTier network ID to join
  --admin-email EMAIL       Administrator email address
  --domain DOMAIN           Domain name (default: tactical.local)
  --skip-hardware-check     Skip Raspberry Pi hardware validation
  --development             Enable development mode
  --help                    Show this help message

Examples:
  # Basic installation
  curl -sSL https://raw.githubusercontent.com/tactical-ops/tacop/main/quick-install.sh | bash

  # With ZeroTier network
  curl -sSL https://raw.githubusercontent.com/tactical-ops/tacop/main/quick-install.sh | bash -s -- --zerotier-network 1234567890abcdef

  # Custom domain and email
  curl -sSL https://raw.githubusercontent.com/tactical-ops/tacop/main/quick-install.sh | bash -s -- --domain my-tactical.local --admin-email admin@tactical.ops

  # Development installation
  curl -sSL https://raw.githubusercontent.com/tactical-ops/tacop/main/quick-install.sh | bash -s -- --development --skip-hardware-check

Repository: https://github.com/tactical-ops/tacop
Documentation: https://github.com/tactical-ops/tacop/blob/main/README.md
EOF
}

# Main installation function
main() {
    local install_start_time=$(date +%s)
    
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
            --skip-hardware-check)
                SKIP_HARDWARE_CHECK=true
                shift
                ;;
            --development)
                DEVELOPMENT_MODE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Show banner
    show_banner
    
    # Start installation
    log "Starting tactical server quick installation..."
    
    # Execute installation steps
    check_root
    validate_system
    install_prerequisites
    clone_repository
    prepare_installation
    execute_installation
    post_installation
    
    # Show results
    show_results
    
    success "Quick installation completed successfully!"
}

# Trap errors and cleanup
trap 'error "Installation failed at line $LINENO"' ERR

# Run main installation
main "$@"