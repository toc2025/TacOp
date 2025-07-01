#!/bin/bash

# Optimize Tiles Script for Tactical Deployment Server
# This script optimizes map tiles for better performance and storage efficiency

set -e

# Configuration
MAPS_DIR="/mnt/secure_storage/maps"
TILES_DIR="$MAPS_DIR/tiles"
CACHE_DIR="$MAPS_DIR/cache"
TEMP_DIR="$MAPS_DIR/temp"
LOG_FILE="/var/log/tile-optimization.log"

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

# Check dependencies
check_dependencies() {
    local deps=("docker" "sqlite3" "gzip" "find")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "Required dependency not found: $dep"
            exit 1
        fi
    done
    
    log "All dependencies satisfied"
}

# Create necessary directories
setup_directories() {
    mkdir -p "$TEMP_DIR" "$CACHE_DIR"
    log "Optimization directories ready"
}

# Optimize MBTiles database
optimize_mbtiles() {
    local mbtiles_file="$1"
    local backup_suffix="${2:-backup}"
    
    if [[ ! -f "$mbtiles_file" ]]; then
        error "MBTiles file not found: $mbtiles_file"
        return 1
    fi
    
    log "Optimizing MBTiles: $(basename "$mbtiles_file")"
    
    # Create backup
    local backup_file="${mbtiles_file}.${backup_suffix}"
    cp "$mbtiles_file" "$backup_file"
    info "Created backup: $(basename "$backup_file")"
    
    # Get original size
    local original_size=$(stat -f%z "$mbtiles_file" 2>/dev/null || stat -c%s "$mbtiles_file")
    
    # Optimize database
    sqlite3 "$mbtiles_file" << EOF
-- Remove duplicate tiles
CREATE TEMP TABLE tile_hashes AS
SELECT tile_id, hex(md5(tile_data)) as hash
FROM images;

DELETE FROM images 
WHERE tile_id NOT IN (
    SELECT MIN(tile_id) 
    FROM tile_hashes 
    GROUP BY hash
);

-- Update map table to reference deduplicated tiles
UPDATE map SET tile_id = (
    SELECT MIN(i.tile_id)
    FROM images i
    JOIN tile_hashes th ON i.tile_id = th.tile_id
    WHERE th.hash = (
        SELECT hex(md5(tile_data))
        FROM images
        WHERE tile_id = map.tile_id
    )
);

-- Vacuum and analyze
VACUUM;
ANALYZE;

-- Update metadata
UPDATE metadata SET value = datetime('now') WHERE name = 'optimized';
INSERT OR REPLACE INTO metadata (name, value) VALUES ('optimization_date', datetime('now'));
EOF

    if [[ $? -eq 0 ]]; then
        local new_size=$(stat -f%z "$mbtiles_file" 2>/dev/null || stat -c%s "$mbtiles_file")
        local saved_bytes=$((original_size - new_size))
        local saved_percent=$(( (saved_bytes * 100) / original_size ))
        
        log "Optimization complete: $(basename "$mbtiles_file")"
        info "Size reduction: $(numfmt --to=iec $saved_bytes) (${saved_percent}%)"
        
        # Remove backup if optimization was successful and significant
        if [[ $saved_percent -gt 5 ]]; then
            rm "$backup_file"
            info "Backup removed (significant optimization achieved)"
        else
            warn "Minimal optimization achieved, backup retained"
        fi
        
        return 0
    else
        error "Optimization failed for $(basename "$mbtiles_file")"
        # Restore from backup
        mv "$backup_file" "$mbtiles_file"
        warn "Restored from backup"
        return 1
    fi
}

# Compress individual tile files
compress_tiles() {
    local tiles_dir="$1"
    local compression_level="${2:-6}"
    
    if [[ ! -d "$tiles_dir" ]]; then
        error "Tiles directory not found: $tiles_dir"
        return 1
    fi
    
    log "Compressing tiles in: $(basename "$tiles_dir")"
    
    local compressed_count=0
    local total_saved=0
    
    # Find and compress uncompressed tiles
    find "$tiles_dir" -name "*.mvt" -o -name "*.pbf" | while read -r tile_file; do
        if [[ ! -f "${tile_file}.gz" ]]; then
            local original_size=$(stat -f%z "$tile_file" 2>/dev/null || stat -c%s "$tile_file")
            
            # Compress tile
            gzip -c -"$compression_level" "$tile_file" > "${tile_file}.gz"
            
            if [[ $? -eq 0 ]]; then
                local compressed_size=$(stat -f%z "${tile_file}.gz" 2>/dev/null || stat -c%s "${tile_file}.gz")
                local saved=$((original_size - compressed_size))
                
                # Replace original with compressed version if significant savings
                if [[ $saved -gt $((original_size / 10)) ]]; then
                    mv "${tile_file}.gz" "$tile_file"
                    compressed_count=$((compressed_count + 1))
                    total_saved=$((total_saved + saved))
                else
                    rm "${tile_file}.gz"
                fi
            fi
        fi
    done
    
    log "Compressed $compressed_count tiles, saved $(numfmt --to=iec $total_saved)"
}

# Remove duplicate tiles across regions
deduplicate_tiles() {
    log "Starting tile deduplication process"
    
    local temp_hashes="$TEMP_DIR/tile_hashes.txt"
    local duplicates_found=0
    local space_saved=0
    
    # Generate hash list for all tiles
    find "$TILES_DIR" -name "*.mvt" -o -name "*.pbf" | while read -r tile_file; do
        local hash=$(md5sum "$tile_file" | cut -d' ' -f1)
        echo "$hash:$tile_file" >> "$temp_hashes"
    done
    
    # Sort by hash to group duplicates
    sort "$temp_hashes" > "${temp_hashes}.sorted"
    
    # Process duplicates
    local current_hash=""
    local first_file=""
    
    while IFS=':' read -r hash file_path; do
        if [[ "$hash" == "$current_hash" ]]; then
            # Duplicate found - create hard link
            if [[ -f "$first_file" && -f "$file_path" ]]; then
                local file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path")
                
                # Create hard link to save space
                ln -f "$first_file" "$file_path"
                
                duplicates_found=$((duplicates_found + 1))
                space_saved=$((space_saved + file_size))
            fi
        else
            current_hash="$hash"
            first_file="$file_path"
        fi
    done < "${temp_hashes}.sorted"
    
    # Cleanup
    rm -f "$temp_hashes" "${temp_hashes}.sorted"
    
    log "Deduplication complete: $duplicates_found duplicates, $(numfmt --to=iec $space_saved) saved"
}

# Optimize tile cache in database
optimize_tile_cache() {
    log "Optimizing tile cache in database"
    
    # Connect to database and optimize cache
    docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps << EOF
-- Remove old, rarely accessed tiles
DELETE FROM map_tiles_cache 
WHERE accessed_at < CURRENT_TIMESTAMP - INTERVAL '30 days'
AND access_count < 5;

-- Update statistics
ANALYZE map_tiles_cache;

-- Vacuum to reclaim space
VACUUM map_tiles_cache;

-- Log optimization
INSERT INTO map_access_logs (action, resource, metadata)
VALUES ('cache_optimization', 'tile_cache', 
        json_build_object('timestamp', CURRENT_TIMESTAMP, 'action', 'optimize'));
EOF

    if [[ $? -eq 0 ]]; then
        log "Database tile cache optimization complete"
    else
        error "Database tile cache optimization failed"
        return 1
    fi
}

# Generate tile statistics
generate_statistics() {
    local output_file="$MAPS_DIR/tile_statistics.json"
    
    log "Generating tile statistics"
    
    # Count tiles by zoom level
    local stats_temp="$TEMP_DIR/tile_stats.tmp"
    
    # Get MBTiles statistics
    for mbtiles_file in "$TILES_DIR"/*.mbtiles; do
        if [[ -f "$mbtiles_file" ]]; then
            local region_name=$(basename "$mbtiles_file" .mbtiles)
            
            sqlite3 "$mbtiles_file" << EOF > "$stats_temp"
SELECT 
    '$region_name' as region,
    zoom_level,
    COUNT(*) as tile_count,
    MIN(tile_column) as min_x,
    MAX(tile_column) as max_x,
    MIN(tile_row) as min_y,
    MAX(tile_row) as max_y
FROM map 
GROUP BY zoom_level 
ORDER BY zoom_level;
EOF
        fi
    done
    
    # Get database cache statistics
    docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -t << EOF >> "$stats_temp"
SELECT 
    'cache' as region,
    z as zoom_level,
    COUNT(*) as tile_count,
    MIN(x) as min_x,
    MAX(x) as max_x,
    MIN(y) as min_y,
    MAX(y) as max_y
FROM map_tiles_cache 
GROUP BY z 
ORDER BY z;
EOF

    # Convert to JSON format
    cat > "$output_file" << EOF
{
    "generated": "$(date -Iseconds)",
    "statistics": [
EOF

    local first_line=true
    while IFS='|' read -r region zoom tiles min_x max_x min_y max_y; do
        if [[ "$first_line" == true ]]; then
            first_line=false
        else
            echo "," >> "$output_file"
        fi
        
        cat >> "$output_file" << EOF
        {
            "region": "$region",
            "zoom_level": $zoom,
            "tile_count": $tiles,
            "bounds": {
                "min_x": $min_x,
                "max_x": $max_x,
                "min_y": $min_y,
                "max_y": $max_y
            }
        }
EOF
    done < "$stats_temp"
    
    cat >> "$output_file" << EOF
    ]
}
EOF

    rm -f "$stats_temp"
    log "Statistics generated: $output_file"
}

# Clean up temporary files and old backups
cleanup() {
    log "Cleaning up temporary files"
    
    # Remove old backups (older than 7 days)
    find "$TILES_DIR" -name "*.backup" -mtime +7 -delete
    find "$TILES_DIR" -name "*.old" -mtime +7 -delete
    
    # Clean temp directory
    rm -rf "$TEMP_DIR"/*
    
    # Clean up old log files
    find /var/log -name "tile-optimization.log.*" -mtime +30 -delete
    
    log "Cleanup complete"
}

# Main optimization function
optimize_all() {
    log "Starting comprehensive tile optimization"
    
    setup_directories
    
    # Optimize all MBTiles files
    for mbtiles_file in "$TILES_DIR"/*.mbtiles; do
        if [[ -f "$mbtiles_file" ]]; then
            optimize_mbtiles "$mbtiles_file"
        fi
    done
    
    # Compress loose tiles
    for region_dir in "$TILES_DIR"/*/; do
        if [[ -d "$region_dir" ]]; then
            compress_tiles "$region_dir"
        fi
    done
    
    # Deduplicate tiles
    deduplicate_tiles
    
    # Optimize database cache
    optimize_tile_cache
    
    # Generate statistics
    generate_statistics
    
    # Cleanup
    cleanup
    
    log "Tile optimization complete"
}

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  optimize-all            - Run complete optimization process"
    echo "  optimize-mbtiles FILE   - Optimize specific MBTiles file"
    echo "  compress-tiles DIR      - Compress tiles in directory"
    echo "  deduplicate            - Remove duplicate tiles"
    echo "  optimize-cache         - Optimize database tile cache"
    echo "  generate-stats         - Generate tile statistics"
    echo "  cleanup                - Clean up temporary files"
    echo ""
    echo "Options:"
    echo "  -h, --help             - Show this help message"
    echo "  --compression-level N  - Set compression level (1-9, default: 6)"
    echo ""
    echo "Examples:"
    echo "  $0 optimize-all"
    echo "  $0 optimize-mbtiles /path/to/region.mbtiles"
    echo "  $0 compress-tiles /path/to/tiles --compression-level 9"
}

# Parse command line arguments
COMPRESSION_LEVEL=6

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        --compression-level)
            COMPRESSION_LEVEL="$2"
            shift 2
            ;;
        optimize-all)
            check_dependencies
            optimize_all
            exit 0
            ;;
        optimize-mbtiles)
            if [[ $# -lt 2 ]]; then
                error "optimize-mbtiles command requires file path"
                usage
                exit 1
            fi
            check_dependencies
            optimize_mbtiles "$2"
            exit $?
            ;;
        compress-tiles)
            if [[ $# -lt 2 ]]; then
                error "compress-tiles command requires directory path"
                usage
                exit 1
            fi
            check_dependencies
            compress_tiles "$2" "$COMPRESSION_LEVEL"
            exit $?
            ;;
        deduplicate)
            check_dependencies
            setup_directories
            deduplicate_tiles
            exit 0
            ;;
        optimize-cache)
            check_dependencies
            optimize_tile_cache
            exit $?
            ;;
        generate-stats)
            check_dependencies
            setup_directories
            generate_statistics
            exit 0
            ;;
        cleanup)
            cleanup
            exit 0
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