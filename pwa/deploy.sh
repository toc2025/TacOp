#!/bin/bash

# Tactical PWA Deployment Script
# Version: 2.1.4
# Deploys discrete PWA to tactical server

set -e

# Configuration
PWA_DIR="/opt/tactical-pwa"
NGINX_SITES="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
TACTICAL_DOMAIN="tactical.local"
BACKUP_DIR="/opt/tactical-backups/pwa-$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking deployment prerequisites..."
    
    # Check if nginx is installed
    if ! command -v nginx &> /dev/null; then
        error "Nginx is not installed. Please install nginx first."
    fi
    
    # Check if tactical server is running
    if ! systemctl is-active --quiet nginx; then
        warn "Nginx is not running. Starting nginx..."
        systemctl start nginx
    fi
    
    # Check if PWA directory exists
    if [ ! -d "$(dirname "$0")" ]; then
        error "PWA source directory not found"
    fi
    
    # Check if SSL certificates exist
    if [ ! -f "/opt/tactical-services/certs/tactical.crt" ]; then
        warn "SSL certificates not found. PWA will use HTTP only."
    fi
    
    log "Prerequisites check completed"
}

# Backup existing PWA if it exists
backup_existing() {
    if [ -d "$PWA_DIR" ]; then
        log "Backing up existing PWA installation..."
        mkdir -p "$(dirname "$BACKUP_DIR")"
        cp -r "$PWA_DIR" "$BACKUP_DIR"
        log "Backup created at: $BACKUP_DIR"
    fi
}

# Deploy PWA files
deploy_pwa_files() {
    log "Deploying PWA files..."
    
    # Create PWA directory
    mkdir -p "$PWA_DIR"
    
    # Copy PWA files
    local source_dir="$(dirname "$0")"
    cp -r "$source_dir"/* "$PWA_DIR/"
    
    # Set proper permissions
    chown -R www-data:www-data "$PWA_DIR"
    chmod -R 755 "$PWA_DIR"
    chmod 644 "$PWA_DIR"/*.html "$PWA_DIR"/*.js "$PWA_DIR"/*.css "$PWA_DIR"/*.json
    
    # Create icons directory if it doesn't exist
    mkdir -p "$PWA_DIR/icons"
    
    log "PWA files deployed successfully"
}

# Configure Nginx
configure_nginx() {
    log "Configuring Nginx for PWA..."
    
    # Create Nginx site configuration
    cat > "$NGINX_SITES/tactical-pwa" << EOF
# Tactical PWA - Discrete System Utility
# Serves PWA with proper headers and security

server {
    listen 80;
    server_name $TACTICAL_DOMAIN 192.168.100.1;
    
    # Redirect HTTP to HTTPS if SSL is available
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $TACTICAL_DOMAIN 192.168.100.1;
    
    # SSL Configuration
    ssl_certificate /opt/tactical-services/certs/tactical.crt;
    ssl_certificate_key /opt/tactical-services/certs/tactical.key;
    ssl_protocols TLSv1.3 TLSv1.2;
    ssl_ciphers ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS;
    ssl_prefer_server_ciphers off;
    
    # Security Headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' wss: ws:; frame-src 'self'";
    
    # PWA Root
    root $PWA_DIR;
    index index.html;
    
    # PWA Manifest and Service Worker
    location /manifest.json {
        add_header Content-Type application/manifest+json;
        add_header Cache-Control "public, max-age=3600";
    }
    
    location /service-worker.js {
        add_header Content-Type application/javascript;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Service-Worker-Allowed "/";
    }
    
    # PWA Icons
    location /icons/ {
        add_header Cache-Control "public, max-age=86400";
        expires 1d;
    }
    
    # Static Assets
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
        add_header Cache-Control "public, max-age=3600";
        expires 1h;
    }
    
    # Main PWA Interface
    location / {
        try_files \$uri \$uri/ /index.html;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }
    
    # Tactical Interface (authenticated access only)
    location /tactical-interface.html {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        # Additional security headers for tactical interface
        add_header X-Robots-Tag "noindex, nofollow, nosnippet, noarchive";
    }
    
    # API Proxy to Tactical Services
    location /api/reports/ {
        proxy_pass http://localhost:3001/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /api/comms/ {
        proxy_pass http://localhost:8065/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /api/maps/ {
        proxy_pass http://localhost:8080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /api/files/ {
        proxy_pass http://localhost:8095/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # WebSocket for Location Tracking
    location /tactical-location {
        proxy_pass http://localhost:8443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Deny access to sensitive files
    location ~ /\. {
        deny all;
    }
    
    location ~ \.(md|txt|sh)$ {
        deny all;
    }
}

# Fallback HTTP server (if SSL not available)
server {
    listen 8080;
    server_name $TACTICAL_DOMAIN 192.168.100.1;
    
    root $PWA_DIR;
    index index.html;
    
    # Basic PWA serving without SSL
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location /manifest.json {
        add_header Content-Type application/manifest+json;
    }
    
    location /service-worker.js {
        add_header Content-Type application/javascript;
        add_header Cache-Control "no-cache";
    }
}
EOF
    
    # Enable the site
    ln -sf "$NGINX_SITES/tactical-pwa" "$NGINX_ENABLED/tactical-pwa"
    
    # Test Nginx configuration
    if nginx -t; then
        log "Nginx configuration is valid"
    else
        error "Nginx configuration test failed"
    fi
    
    # Reload Nginx
    systemctl reload nginx
    
    log "Nginx configured successfully"
}

# Generate QR codes for easy mobile access
generate_qr_codes() {
    log "Generating QR codes for mobile access..."
    
    # Check if qrencode is available
    if command -v qrencode &> /dev/null; then
        local qr_dir="$PWA_DIR/qr-codes"
        mkdir -p "$qr_dir"
        
        # Generate QR code for PWA URL
        qrencode -o "$qr_dir/pwa-install.png" "https://192.168.100.1/"
        
        # Generate QR code for ZeroTier network (if network ID exists)
        if [ -f "/opt/tactical-network-id" ]; then
            local network_id=$(cat /opt/tactical-network-id)
            qrencode -o "$qr_dir/zerotier-join.png" "zerotier-one://network/$network_id"
        fi
        
        log "QR codes generated in $qr_dir"
    else
        warn "qrencode not installed. Skipping QR code generation."
        info "Install qrencode with: apt install qrencode"
    fi
}

# Validate deployment
validate_deployment() {
    log "Validating PWA deployment..."
    
    # Check if PWA files exist
    local required_files=("index.html" "manifest.json" "service-worker.js" "app.js" "styles.css")
    for file in "${required_files[@]}"; do
        if [ ! -f "$PWA_DIR/$file" ]; then
            error "Required file missing: $file"
        fi
    done
    
    # Check if Nginx site is enabled
    if [ ! -L "$NGINX_ENABLED/tactical-pwa" ]; then
        error "Nginx site not enabled"
    fi
    
    # Test HTTP response
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ | grep -q "200"; then
        log "HTTP endpoint responding correctly"
    else
        warn "HTTP endpoint not responding (this may be normal if only HTTPS is configured)"
    fi
    
    # Test HTTPS response if SSL is available
    if [ -f "/opt/tactical-services/certs/tactical.crt" ]; then
        if curl -k -s -o /dev/null -w "%{http_code}" https://localhost/ | grep -q "200"; then
            log "HTTPS endpoint responding correctly"
        else
            warn "HTTPS endpoint not responding"
        fi
    fi
    
    log "Deployment validation completed"
}

# Display access information
display_access_info() {
    local local_ip=$(hostname -I | awk '{print $1}')
    
    echo
    echo "======================================================"
    echo "  TACTICAL PWA DEPLOYMENT COMPLETE"
    echo "======================================================"
    echo
    echo "PWA Access Information:"
    echo "  Primary URL: https://192.168.100.1/"
    echo "  Alternative: https://$TACTICAL_DOMAIN/"
    echo "  Local IP: https://$local_ip/"
    echo "  HTTP Fallback: http://192.168.100.1:8080/"
    echo
    echo "Installation Instructions:"
    echo "  1. Connect mobile device to ZeroTier network"
    echo "  2. Open PWA URL in mobile browser"
    echo "  3. Tap 'Add to Home Screen' (iOS) or 'Install' (Android)"
    echo "  4. PWA will appear as 'System Utility' on device"
    echo
    echo "Authentication Sequence:"
    echo "  Tap status items in order: Battery → Network → Storage → Memory"
    echo "  Alternative: Triple-tap title, enter: TACTICAL_OVERRIDE_2025"
    echo
    echo "Files Location:"
    echo "  PWA Directory: $PWA_DIR"
    echo "  Nginx Config: $NGINX_SITES/tactical-pwa"
    echo "  Backup: $BACKUP_DIR"
    echo
    if [ -d "$PWA_DIR/qr-codes" ]; then
        echo "QR Codes:"
        echo "  PWA Install: $PWA_DIR/qr-codes/pwa-install.png"
        echo "  ZeroTier Join: $PWA_DIR/qr-codes/zerotier-join.png"
        echo
    fi
    echo "Next Steps:"
    echo "  1. Test PWA installation on mobile devices"
    echo "  2. Verify authentication sequences work"
    echo "  3. Test tactical interface functionality"
    echo "  4. Configure team member access"
    echo
    echo "Support: Check deployment logs for any issues"
    echo "======================================================"
}

# Main deployment function
main() {
    log "Starting Tactical PWA deployment..."
    
    check_root
    check_prerequisites
    backup_existing
    deploy_pwa_files
    configure_nginx
    generate_qr_codes
    validate_deployment
    display_access_info
    
    log "Tactical PWA deployment completed successfully!"
}

# Handle command line arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "backup")
        backup_existing
        ;;
    "validate")
        validate_deployment
        ;;
    "info")
        display_access_info
        ;;
    "help"|"-h"|"--help")
        echo "Tactical PWA Deployment Script"
        echo
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  deploy    - Full PWA deployment (default)"
        echo "  backup    - Backup existing PWA installation"
        echo "  validate  - Validate current deployment"
        echo "  info      - Display access information"
        echo "  help      - Show this help message"
        echo
        ;;
    *)
        error "Unknown command: $1. Use '$0 help' for usage information."
        ;;
esac