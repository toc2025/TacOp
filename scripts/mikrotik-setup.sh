#!/bin/bash
# MikroTik RouterOS Configuration Deployment Script
# Version: 1.0.0
# Configures MikroTik RBmAPL-2nD for tactical deployment

set -euo pipefail

# Configuration
MIKROTIK_IP="192.168.88.1"  # Default MikroTik IP
MIKROTIK_USER="admin"
MIKROTIK_PASSWORD=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/mikrotik-config.rsc"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if sshpass is available for password authentication
    if ! command -v sshpass >/dev/null 2>&1; then
        warning "sshpass not found. Install with: sudo apt-get install sshpass"
        warning "You will need to manually enter SSH password"
    fi
    
    # Check if configuration file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found: $CONFIG_FILE"
    fi
    
    log "Prerequisites check completed"
}

# Test MikroTik connectivity
test_connectivity() {
    log "Testing connectivity to MikroTik at $MIKROTIK_IP..."
    
    if ping -c 3 "$MIKROTIK_IP" >/dev/null 2>&1; then
        log "MikroTik is reachable"
    else
        error "Cannot reach MikroTik at $MIKROTIK_IP. Check network connection."
    fi
}

# Deploy configuration to MikroTik
deploy_config() {
    log "Deploying configuration to MikroTik..."
    
    # Create temporary script with proper line endings
    local temp_script="/tmp/mikrotik-config-$(date +%s).rsc"
    
    # Convert line endings and copy to temp file
    sed 's/\r$//' "$CONFIG_FILE" > "$temp_script"
    
    # Upload and execute configuration
    if command -v sshpass >/dev/null 2>&1 && [[ -n "$MIKROTIK_PASSWORD" ]]; then
        # Use sshpass for automated deployment
        log "Uploading configuration file..."
        sshpass -p "$MIKROTIK_PASSWORD" scp -o StrictHostKeyChecking=no \
            "$temp_script" "$MIKROTIK_USER@$MIKROTIK_IP:tactical-config.rsc"
        
        log "Executing configuration..."
        sshpass -p "$MIKROTIK_PASSWORD" ssh -o StrictHostKeyChecking=no \
            "$MIKROTIK_USER@$MIKROTIK_IP" "/import tactical-config.rsc"
    else
        # Manual deployment
        info "Manual deployment required:"
        info "1. Copy the configuration file to MikroTik:"
        info "   scp $temp_script $MIKROTIK_USER@$MIKROTIK_IP:tactical-config.rsc"
        info "2. SSH to MikroTik and import:"
        info "   ssh $MIKROTIK_USER@$MIKROTIK_IP"
        info "   /import tactical-config.rsc"
        
        read -p "Press Enter when configuration has been applied manually..."
    fi
    
    # Cleanup
    rm -f "$temp_script"
    
    log "Configuration deployment completed"
}

# Verify configuration
verify_config() {
    log "Verifying MikroTik configuration..."
    
    # Wait for MikroTik to reboot and apply configuration
    info "Waiting for MikroTik to apply configuration (60 seconds)..."
    sleep 60
    
    # Test new IP address
    local new_ip="192.168.100.1"
    if ping -c 3 "$new_ip" >/dev/null 2>&1; then
        log "MikroTik is accessible at new IP: $new_ip"
        
        # Test wireless network
        info "Tactical wireless network should now be available:"
        info "  SSID: TacticalNet"
        info "  Password: TacticalSecure2025!"
        info "  Gateway: 192.168.100.1"
        info "  DHCP Range: 192.168.100.10-192.168.100.50"
        
    else
        warning "Cannot reach MikroTik at new IP: $new_ip"
        warning "Configuration may need manual verification"
    fi
}

# Backup current configuration
backup_config() {
    log "Creating backup of current MikroTik configuration..."
    
    local backup_file="mikrotik-backup-$(date +%Y%m%d_%H%M%S).backup"
    
    if command -v sshpass >/dev/null 2>&1 && [[ -n "$MIKROTIK_PASSWORD" ]]; then
        sshpass -p "$MIKROTIK_PASSWORD" ssh -o StrictHostKeyChecking=no \
            "$MIKROTIK_USER@$MIKROTIK_IP" "/system backup save name=$backup_file"
        
        sshpass -p "$MIKROTIK_PASSWORD" scp -o StrictHostKeyChecking=no \
            "$MIKROTIK_USER@$MIKROTIK_IP:$backup_file" "./backups/"
        
        log "Backup saved to: ./backups/$backup_file"
    else
        info "Manual backup recommended before applying configuration"
        info "SSH to MikroTik and run: /system backup save name=$backup_file"
    fi
}

# Reset MikroTik to defaults
reset_mikrotik() {
    warning "This will reset MikroTik to factory defaults!"
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        log "Resetting MikroTik to defaults..."
        
        if command -v sshpass >/dev/null 2>&1 && [[ -n "$MIKROTIK_PASSWORD" ]]; then
            sshpass -p "$MIKROTIK_PASSWORD" ssh -o StrictHostKeyChecking=no \
                "$MIKROTIK_USER@$MIKROTIK_IP" "/system reset-configuration no-defaults=yes"
        else
            info "Manual reset required:"
            info "SSH to MikroTik and run: /system reset-configuration no-defaults=yes"
        fi
        
        log "Reset initiated. MikroTik will reboot."
    else
        log "Reset cancelled"
    fi
}

# Show help
show_help() {
    cat << EOF
MikroTik RouterOS Configuration Deployment Script

Usage: $0 [OPTIONS] [COMMAND]

Commands:
  deploy    Deploy tactical configuration (default)
  backup    Backup current configuration
  reset     Reset MikroTik to factory defaults
  verify    Verify current configuration
  help      Show this help message

Options:
  --ip IP           MikroTik IP address (default: 192.168.88.1)
  --user USER       SSH username (default: admin)
  --password PASS   SSH password (optional, will prompt if not provided)
  --config FILE     Configuration file (default: mikrotik-config.rsc)

Examples:
  $0 deploy                                    # Deploy with defaults
  $0 --ip 192.168.1.1 --password admin deploy # Deploy to custom IP
  $0 backup                                    # Backup current config
  $0 reset                                     # Reset to defaults

Note: Install 'sshpass' for automated deployment:
  sudo apt-get install sshpass
EOF
}

# Main function
main() {
    local command="deploy"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ip)
                MIKROTIK_IP="$2"
                shift 2
                ;;
            --user)
                MIKROTIK_USER="$2"
                shift 2
                ;;
            --password)
                MIKROTIK_PASSWORD="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            deploy|backup|reset|verify|help)
                command="$1"
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
    
    # Prompt for password if not provided
    if [[ -z "$MIKROTIK_PASSWORD" && "$command" != "help" ]]; then
        read -s -p "Enter MikroTik password for user '$MIKROTIK_USER': " MIKROTIK_PASSWORD
        echo
    fi
    
    # Create backups directory
    mkdir -p "./backups"
    
    # Execute command
    case $command in
        deploy)
            check_prerequisites
            test_connectivity
            backup_config
            deploy_config
            verify_config
            ;;
        backup)
            test_connectivity
            backup_config
            ;;
        reset)
            test_connectivity
            reset_mikrotik
            ;;
        verify)
            verify_config
            ;;
        help)
            show_help
            ;;
        *)
            error "Unknown command: $command"
            ;;
    esac
    
    log "MikroTik setup completed successfully"
}

# Run main function
main "$@"