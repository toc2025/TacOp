#!/bin/bash
# Tactical Server Backup Script
# Creates compressed backups of all critical data

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/mnt/secure_storage/backups"
LOG_FILE="/var/log/tactical-backup.log"
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="tactical_backup_${TIMESTAMP}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Create backup directory
create_backup_dir() {
    mkdir -p "$BACKUP_DIR/$BACKUP_NAME"
    log "Created backup directory: $BACKUP_DIR/$BACKUP_NAME"
}

# Backup databases
backup_databases() {
    log "Starting database backup..."
    
    cd "$SCRIPT_DIR"
    
    # PostgreSQL databases
    local databases=("tactical_location" "tactical_maps" "outline" "mattermost")
    
    for db in "${databases[@]}"; do
        log "Backing up database: $db"
        
        if docker compose exec -T postgresql pg_dump -U postgres -d "$db" | gzip > "$BACKUP_DIR/$BACKUP_NAME/${db}.sql.gz"; then
            success "Database $db backed up successfully"
        else
            error "Failed to backup database $db"
        fi
    done
    
    # Redis data
    log "Backing up Redis data..."
    if docker compose exec -T redis redis-cli BGSAVE; then
        # Wait for background save to complete
        sleep 5
        
        # Copy Redis dump
        docker cp "$(docker compose ps -q redis):/data/dump.rdb" "$BACKUP_DIR/$BACKUP_NAME/redis_dump.rdb"
        success "Redis data backed up successfully"
    else
        error "Failed to backup Redis data"
    fi
}

# Backup configuration files
backup_configs() {
    log "Backing up configuration files..."
    
    local config_dir="$BACKUP_DIR/$BACKUP_NAME/configs"
    mkdir -p "$config_dir"
    
    # Copy deployment configurations
    cp -r "$SCRIPT_DIR"/*.json "$config_dir/" 2>/dev/null || true
    cp -r "$SCRIPT_DIR"/*.yml "$config_dir/" 2>/dev/null || true
    cp -r "$SCRIPT_DIR"/*.yaml "$config_dir/" 2>/dev/null || true
    cp -r "$SCRIPT_DIR"/nginx "$config_dir/" 2>/dev/null || true
    cp -r "$SCRIPT_DIR"/redis "$config_dir/" 2>/dev/null || true
    cp -r "$SCRIPT_DIR"/filebrowser "$config_dir/" 2>/dev/null || true
    
    # Copy environment file (without sensitive data)
    if [[ -f "$SCRIPT_DIR/.env.production" ]]; then
        grep -v "PASSWORD\|SECRET\|KEY" "$SCRIPT_DIR/.env.production" > "$config_dir/env.production.template" || true
    fi
    
    # Copy service configurations
    cp -r ../location-service/*.json "$config_dir/" 2>/dev/null || true
    cp -r ../maps-service/*.json "$config_dir/" 2>/dev/null || true
    cp -r ../pwa/manifest.json "$config_dir/" 2>/dev/null || true
    
    success "Configuration files backed up"
}

# Backup SSL certificates
backup_ssl() {
    log "Backing up SSL certificates..."
    
    local ssl_dir="$BACKUP_DIR/$BACKUP_NAME/ssl"
    mkdir -p "$ssl_dir"
    
    if [[ -d "/mnt/secure_storage/ssl" ]]; then
        cp -r /mnt/secure_storage/ssl/* "$ssl_dir/" 2>/dev/null || true
        success "SSL certificates backed up"
    else
        warning "SSL directory not found"
    fi
}

# Backup application data
backup_app_data() {
    log "Backing up application data..."
    
    local data_dir="$BACKUP_DIR/$BACKUP_NAME/data"
    mkdir -p "$data_dir"
    
    # Backup critical application data (excluding large files)
    if [[ -d "/mnt/secure_storage/data" ]]; then
        # Create selective backup excluding large database files
        rsync -av --exclude="postgresql/data" --exclude="*.log" /mnt/secure_storage/data/ "$data_dir/" || true
        success "Application data backed up"
    else
        warning "Application data directory not found"
    fi
}

# Backup logs (recent only)
backup_logs() {
    log "Backing up recent logs..."
    
    local logs_dir="$BACKUP_DIR/$BACKUP_NAME/logs"
    mkdir -p "$logs_dir"
    
    # Copy recent log files (last 7 days)
    find /var/log -name "tactical-*" -mtime -7 -exec cp {} "$logs_dir/" \; 2>/dev/null || true
    find /mnt/secure_storage/logs -name "*.log" -mtime -7 -exec cp {} "$logs_dir/" \; 2>/dev/null || true
    
    success "Recent logs backed up"
}

# Create backup archive
create_archive() {
    log "Creating backup archive..."
    
    cd "$BACKUP_DIR"
    
    if tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"; then
        # Remove uncompressed backup directory
        rm -rf "$BACKUP_NAME"
        
        # Calculate archive size
        local size=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
        success "Backup archive created: ${BACKUP_NAME}.tar.gz ($size)"
        
        # Create checksum
        sha256sum "${BACKUP_NAME}.tar.gz" > "${BACKUP_NAME}.tar.gz.sha256"
        success "Checksum created: ${BACKUP_NAME}.tar.gz.sha256"
    else
        error "Failed to create backup archive"
        return 1
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups (retention: $RETENTION_DAYS days)..."
    
    cd "$BACKUP_DIR"
    
    # Remove backups older than retention period
    find . -name "tactical_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    find . -name "tactical_backup_*.tar.gz.sha256" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    
    # Count remaining backups
    local backup_count=$(find . -name "tactical_backup_*.tar.gz" | wc -l)
    success "Cleanup completed. Remaining backups: $backup_count"
}

# Verify backup integrity
verify_backup() {
    log "Verifying backup integrity..."
    
    cd "$BACKUP_DIR"
    
    if [[ -f "${BACKUP_NAME}.tar.gz.sha256" ]]; then
        if sha256sum -c "${BACKUP_NAME}.tar.gz.sha256"; then
            success "Backup integrity verified"
        else
            error "Backup integrity check failed"
            return 1
        fi
    else
        warning "Checksum file not found, skipping integrity check"
    fi
}

# Send backup notification
send_notification() {
    local status=$1
    local message=$2
    
    # Log the notification
    if [[ "$status" == "success" ]]; then
        success "$message"
    else
        error "$message"
    fi
    
    # Send email notification if configured
    if [[ -n "${BACKUP_EMAIL:-}" ]] && command -v mail >/dev/null 2>&1; then
        local subject="Tactical Server Backup - $status"
        echo "$message" | mail -s "$subject" "$BACKUP_EMAIL"
        log "Notification sent to $BACKUP_EMAIL"
    fi
}

# Main backup function
main() {
    local start_time=$(date +%s)
    
    log "Starting tactical server backup: $BACKUP_NAME"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --retention-days)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            --backup-email)
                BACKUP_EMAIL="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --retention-days DAYS    Number of days to keep backups (default: 7)"
                echo "  --backup-email EMAIL     Email address for backup notifications"
                echo "  --help                   Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check if backup directory exists
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        log "Created backup directory: $BACKUP_DIR"
    fi
    
    # Perform backup steps
    if create_backup_dir && \
       backup_databases && \
       backup_configs && \
       backup_ssl && \
       backup_app_data && \
       backup_logs && \
       create_archive && \
       verify_backup; then
        
        # Cleanup old backups
        cleanup_old_backups
        
        # Calculate backup time
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        
        send_notification "success" "Backup completed successfully in ${minutes}m ${seconds}s"
        
        # Display backup information
        cd "$BACKUP_DIR"
        local size=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
        log "Backup file: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
        log "Backup size: $size"
        log "Backup duration: ${minutes}m ${seconds}s"
        
        exit 0
    else
        send_notification "failed" "Backup failed - check logs for details"
        exit 1
    fi
}

# Run main function
main "$@"