#!/bin/bash

# Validate Maps Script for Tactical Deployment Server
# This script validates map data integrity and system health

set -e

# Configuration
MAPS_DIR="/mnt/secure_storage/maps"
LOG_FILE="/var/log/map-validation.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# Validate database connectivity and schema
validate_database() {
    log "Validating database connectivity and schema"
    
    # Test database connection
    if ! docker exec tactical-maps-postgres pg_isready -U maps_user -d tactical_maps > /dev/null 2>&1; then
        error "Database connection failed"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    info "Database connection: OK"
    
    # Check required tables exist
    local required_tables=("map_metadata" "regions" "waypoints" "tactical_overlays" "map_tiles_cache")
    
    for table in "${required_tables[@]}"; do
        local table_exists=$(docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -t -c "
            SELECT EXISTS (
                SELECT FROM information_schema.tables 
                WHERE table_schema = 'public' 
                AND table_name = '$table'
            );
        " | tr -d ' ')
        
        if [[ "$table_exists" != "t" ]]; then
            error "Required table missing: $table"
            ((VALIDATION_ERRORS++))
        else
            info "Table exists: $table"
        fi
    done
    
    # Check PostGIS extension
    local postgis_exists=$(docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -t -c "
        SELECT EXISTS (
            SELECT FROM pg_extension 
            WHERE extname = 'postgis'
        );
    " | tr -d ' ')
    
    if [[ "$postgis_exists" != "t" ]]; then
        error "PostGIS extension not installed"
        ((VALIDATION_ERRORS++))
    else
        info "PostGIS extension: OK"
    fi
}

# Validate Redis connectivity
validate_redis() {
    log "Validating Redis connectivity"
    
    if ! docker exec tactical-maps-redis redis-cli ping > /dev/null 2>&1; then
        error "Redis connection failed"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    info "Redis connection: OK"
    
    # Check Redis memory usage
    local memory_info=$(docker exec tactical-maps-redis redis-cli info memory | grep used_memory_human)
    info "Redis memory usage: $memory_info"
}

# Validate map files and directories
validate_file_system() {
    log "Validating file system structure"
    
    # Check required directories
    local required_dirs=("$MAPS_DIR" "$MAPS_DIR/tiles" "$MAPS_DIR/data" "$MAPS_DIR/cache")
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            error "Required directory missing: $dir"
            ((VALIDATION_ERRORS++))
        else
            info "Directory exists: $dir"
            
            # Check permissions
            if [[ ! -w "$dir" ]]; then
                warn "Directory not writable: $dir"
                ((VALIDATION_WARNINGS++))
            fi
        fi
    done
    
    # Check disk space
    local available_space=$(df "$MAPS_DIR" | awk 'NR==2 {print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    info "Available disk space: ${available_gb}GB"
    
    if [[ $available_gb -lt 50 ]]; then
        warn "Low disk space: ${available_gb}GB available"
        ((VALIDATION_WARNINGS++))
    fi
    
    if [[ $available_gb -lt 10 ]]; then
        error "Critical disk space: ${available_gb}GB available"
        ((VALIDATION_ERRORS++))
    fi
}

# Validate MBTiles files
validate_mbtiles() {
    log "Validating MBTiles files"
    
    local mbtiles_count=0
    local corrupted_count=0
    
    for mbtiles_file in "$MAPS_DIR/tiles"/*.mbtiles; do
        if [[ -f "$mbtiles_file" ]]; then
            ((mbtiles_count++))
            
            # Check file integrity
            if ! sqlite3 "$mbtiles_file" "PRAGMA integrity_check;" | grep -q "ok"; then
                error "Corrupted MBTiles file: $(basename "$mbtiles_file")"
                ((corrupted_count++))
                ((VALIDATION_ERRORS++))
            else
                info "MBTiles file OK: $(basename "$mbtiles_file")"
                
                # Check metadata
                local metadata_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM metadata;")
                local tiles_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM map;")
                
                info "  Metadata entries: $metadata_count"
                info "  Tiles count: $tiles_count"
                
                if [[ $tiles_count -eq 0 ]]; then
                    warn "MBTiles file contains no tiles: $(basename "$mbtiles_file")"
                    ((VALIDATION_WARNINGS++))
                fi
            fi
        fi
    done
    
    info "MBTiles validation complete: $mbtiles_count files, $corrupted_count corrupted"
}

# Validate map services
validate_services() {
    log "Validating map services"
    
    # Check maps service health
    if curl -f -s "http://localhost:8080/health" > /dev/null 2>&1; then
        info "Maps service: OK"
        
        # Get service statistics
        local stats=$(curl -s "http://localhost:8080/api/stats" 2>/dev/null || echo "{}")
        info "Service statistics: $stats"
    else
        error "Maps service health check failed"
        ((VALIDATION_ERRORS++))
    fi
    
    # Check OpenMapTiles service
    if curl -f -s "http://localhost:8081/health" > /dev/null 2>&1; then
        info "OpenMapTiles service: OK"
    else
        warn "OpenMapTiles service health check failed"
        ((VALIDATION_WARNINGS++))
    fi
    
    # Check Nginx proxy
    if curl -f -s "http://localhost:8082/health" > /dev/null 2>&1; then
        info "Nginx proxy: OK"
    else
        warn "Nginx proxy health check failed"
        ((VALIDATION_WARNINGS++))
    fi
}

# Validate map data consistency
validate_data_consistency() {
    log "Validating map data consistency"
    
    # Check for orphaned records
    local orphaned_tiles=$(docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -t -c "
        SELECT COUNT(*) FROM map_tiles_cache 
        WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '30 days'
        AND access_count = 0;
    " | tr -d ' ')
    
    if [[ $orphaned_tiles -gt 1000 ]]; then
        warn "Large number of unused tiles in cache: $orphaned_tiles"
        ((VALIDATION_WARNINGS++))
    fi
    
    # Check for expired waypoints
    local expired_waypoints=$(docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -t -c "
        SELECT COUNT(*) FROM waypoints 
        WHERE expires_at IS NOT NULL 
        AND expires_at < CURRENT_TIMESTAMP 
        AND status = 'active';
    " | tr -d ' ')
    
    if [[ $expired_waypoints -gt 0 ]]; then
        warn "Expired waypoints still active: $expired_waypoints"
        ((VALIDATION_WARNINGS++))
    fi
    
    # Check for invalid geometries
    local invalid_geometries=$(docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -t -c "
        SELECT COUNT(*) FROM tactical_overlays 
        WHERE NOT ST_IsValid(geometry);
    " | tr -d ' ')
    
    if [[ $invalid_geometries -gt 0 ]]; then
        error "Invalid geometries found: $invalid_geometries"
        ((VALIDATION_ERRORS++))
    fi
}

# Validate region packages
validate_region_packages() {
    log "Validating region packages"
    
    local package_count=0
    local invalid_packages=0
    
    for package_file in "$MAPS_DIR/data"/*.tar.gz; do
        if [[ -f "$package_file" ]]; then
            ((package_count++))
            
            # Test archive integrity
            if ! tar -tzf "$package_file" > /dev/null 2>&1; then
                error "Corrupted region package: $(basename "$package_file")"
                ((invalid_packages++))
                ((VALIDATION_ERRORS++))
            else
                info "Region package OK: $(basename "$package_file")"
                
                # Check for required files
                local has_metadata=$(tar -tzf "$package_file" | grep -c "metadata.json" || echo "0")
                local has_style=$(tar -tzf "$package_file" | grep -c "style.json" || echo "0")
                local tile_count=$(tar -tzf "$package_file" | grep -c "\.mvt$" || echo "0")
                
                if [[ $has_metadata -eq 0 ]]; then
                    warn "Package missing metadata: $(basename "$package_file")"
                    ((VALIDATION_WARNINGS++))
                fi
                
                if [[ $has_style -eq 0 ]]; then
                    warn "Package missing style: $(basename "$package_file")"
                    ((VALIDATION_WARNINGS++))
                fi
                
                if [[ $tile_count -eq 0 ]]; then
                    warn "Package contains no tiles: $(basename "$package_file")"
                    ((VALIDATION_WARNINGS++))
                fi
                
                info "  Tiles: $tile_count"
            fi
        fi
    done
    
    info "Region package validation complete: $package_count packages, $invalid_packages invalid"
}

# Validate configuration files
validate_configuration() {
    log "Validating configuration files"
    
    # Check map configuration
    if [[ -f "map-config.json" ]]; then
        if jq empty map-config.json > /dev/null 2>&1; then
            info "Map configuration: OK"
        else
            error "Invalid JSON in map-config.json"
            ((VALIDATION_ERRORS++))
        fi
    else
        error "Map configuration file missing: map-config.json"
        ((VALIDATION_ERRORS++))
    fi
    
    # Check tactical style
    if [[ -f "tactical-style.json" ]]; then
        if jq empty tactical-style.json > /dev/null 2>&1; then
            info "Tactical style: OK"
        else
            error "Invalid JSON in tactical-style.json"
            ((VALIDATION_ERRORS++))
        fi
    else
        error "Tactical style file missing: tactical-style.json"
        ((VALIDATION_ERRORS++))
    fi
    
    # Check regions configuration
    if [[ -f "regions.json" ]]; then
        if jq empty regions.json > /dev/null 2>&1; then
            info "Regions configuration: OK"
        else
            error "Invalid JSON in regions.json"
            ((VALIDATION_ERRORS++))
        fi
    else
        error "Regions configuration file missing: regions.json"
        ((VALIDATION_ERRORS++))
    fi
}

# Performance validation
validate_performance() {
    log "Validating system performance"
    
    # Check memory usage
    local memory_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    info "Memory usage: ${memory_usage}%"
    
    if (( $(echo "$memory_usage > 90" | bc -l) )); then
        error "High memory usage: ${memory_usage}%"
        ((VALIDATION_ERRORS++))
    elif (( $(echo "$memory_usage > 80" | bc -l) )); then
        warn "High memory usage: ${memory_usage}%"
        ((VALIDATION_WARNINGS++))
    fi
    
    # Check CPU load
    local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    info "CPU load (1min): $cpu_load"
    
    # Check disk I/O
    local disk_usage=$(iostat -x 1 1 | tail -n +4 | awk '{sum+=$10} END {print sum/NR}' 2>/dev/null || echo "0")
    info "Average disk utilization: ${disk_usage}%"
}

# Generate validation report
generate_report() {
    local report_file="$MAPS_DIR/validation_report_$(date +%Y%m%d_%H%M%S).json"
    
    log "Generating validation report: $report_file"
    
    cat > "$report_file" << EOF
{
    "validation": {
        "timestamp": "$(date -Iseconds)",
        "errors": $VALIDATION_ERRORS,
        "warnings": $VALIDATION_WARNINGS,
        "status": "$([ $VALIDATION_ERRORS -eq 0 ] && echo "PASS" || echo "FAIL")"
    },
    "system": {
        "hostname": "$(hostname)",
        "uptime": "$(uptime -p)",
        "memory_usage": "$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')%",
        "disk_usage": "$(df $MAPS_DIR | awk 'NR==2 {print $5}')"
    },
    "services": {
        "maps_service": "$(curl -f -s http://localhost:8080/health > /dev/null 2>&1 && echo "OK" || echo "FAIL")",
        "openmaptiles": "$(curl -f -s http://localhost:8081/health > /dev/null 2>&1 && echo "OK" || echo "FAIL")",
        "nginx": "$(curl -f -s http://localhost:8082/health > /dev/null 2>&1 && echo "OK" || echo "FAIL")",
        "database": "$(docker exec tactical-maps-postgres pg_isready -U maps_user -d tactical_maps > /dev/null 2>&1 && echo "OK" || echo "FAIL")",
        "redis": "$(docker exec tactical-maps-redis redis-cli ping > /dev/null 2>&1 && echo "OK" || echo "FAIL")"
    }
}
EOF

    info "Validation report generated: $report_file"
}

# Main validation function
run_full_validation() {
    log "Starting comprehensive map validation"
    
    validate_database
    validate_redis
    validate_file_system
    validate_mbtiles
    validate_services
    validate_data_consistency
    validate_region_packages
    validate_configuration
    validate_performance
    
    generate_report
    
    log "Validation complete: $VALIDATION_ERRORS errors, $VALIDATION_WARNINGS warnings"
    
    if [[ $VALIDATION_ERRORS -eq 0 ]]; then
        log "✅ All validations passed"
        return 0
    else
        error "❌ Validation failed with $VALIDATION_ERRORS errors"
        return 1
    fi
}

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  full                   - Run complete validation"
    echo "  database              - Validate database only"
    echo "  redis                 - Validate Redis only"
    echo "  filesystem            - Validate file system only"
    echo "  mbtiles               - Validate MBTiles files only"
    echo "  services              - Validate services only"
    echo "  consistency           - Validate data consistency only"
    echo "  packages              - Validate region packages only"
    echo "  config                - Validate configuration only"
    echo "  performance           - Validate performance only"
    echo ""
    echo "Options:"
    echo "  -h, --help            - Show this help message"
    echo "  --report-only         - Generate report without validation"
    echo ""
    echo "Examples:"
    echo "  $0 full"
    echo "  $0 database"
    echo "  $0 services"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        --report-only)
            generate_report
            exit 0
            ;;
        full)
            run_full_validation
            exit $?
            ;;
        database)
            validate_database
            exit $?
            ;;
        redis)
            validate_redis
            exit $?
            ;;
        filesystem)
            validate_file_system
            exit $?
            ;;
        mbtiles)
            validate_mbtiles
            exit $?
            ;;
        services)
            validate_services
            exit $?
            ;;
        consistency)
            validate_data_consistency
            exit $?
            ;;
        packages)
            validate_region_packages
            exit $?
            ;;
        config)
            validate_configuration
            exit $?
            ;;
        performance)
            validate_performance
            exit $?
            ;;
        *)
            error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
done

# Show usage if no command provided
usage
exit 1