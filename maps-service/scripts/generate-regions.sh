#!/bin/bash

# Generate Regions Script for Tactical Deployment Server
# This script creates downloadable map regions based on tactical requirements

set -e

# Configuration
MAPS_DIR="/mnt/secure_storage/maps"
REGIONS_DIR="$MAPS_DIR/regions"
DATA_DIR="$MAPS_DIR/data"
LOG_FILE="/var/log/region-generation.log"

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

# Setup directories
setup_directories() {
    mkdir -p "$REGIONS_DIR" "$DATA_DIR"
    log "Region directories ready"
}

# Generate region package
generate_region_package() {
    local region_name="$1"
    local min_zoom="${2:-0}"
    local max_zoom="${3:-14}"
    
    log "Generating region package: $region_name"
    
    # Get region bounds from database
    local bounds_query="SELECT ST_AsText(bounds) FROM regions WHERE name = '$region_name'"
    local bounds=$(docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -t -c "$bounds_query" | tr -d ' ')
    
    if [[ -z "$bounds" ]]; then
        error "Region not found in database: $region_name"
        return 1
    fi
    
    # Parse bounds (assuming POLYGON format)
    local bbox=$(echo "$bounds" | sed -n 's/.*POLYGON((\([^)]*\)).*/\1/p' | tr ',' '\n' | awk '{print $1, $2}' | sort -n | awk 'NR==1{minx=$1; miny=$2} {maxx=$1; maxy=$2} END{print minx","miny","maxx","maxy}')
    
    if [[ -z "$bbox" ]]; then
        error "Could not parse bounds for region: $region_name"
        return 1
    fi
    
    info "Region bounds: $bbox"
    
    # Create region directory
    local region_dir="$REGIONS_DIR/$region_name"
    mkdir -p "$region_dir"
    
    # Generate tiles for region
    generate_region_tiles "$region_name" "$bbox" "$min_zoom" "$max_zoom" "$region_dir"
    
    # Create region metadata
    create_region_metadata "$region_name" "$region_dir"
    
    # Package region
    package_region "$region_name" "$region_dir"
    
    log "Region package generated: $region_name"
}

# Generate tiles for specific region
generate_region_tiles() {
    local region_name="$1"
    local bbox="$2"
    local min_zoom="$3"
    local max_zoom="$4"
    local output_dir="$5"
    
    info "Generating tiles for region: $region_name (zoom $min_zoom-$max_zoom)"
    
    # Parse bounding box
    IFS=',' read -r min_lon min_lat max_lon max_lat <<< "$bbox"
    
    local tiles_dir="$output_dir/tiles"
    mkdir -p "$tiles_dir"
    
    # Generate tiles using TileServer
    docker run --rm \
        --network tactical-network \
        -v "$tiles_dir:/output" \
        -v "$(pwd)/tactical-style.json:/style.json" \
        openmaptiles/generate-tiles \
        generate-tiles \
        --database postgresql://maps_user:${MAPS_DB_PASSWORD}@postgres:5432/tactical_maps \
        --style /style.json \
        --output "/output/${region_name}.mbtiles" \
        --min-zoom "$min_zoom" \
        --max-zoom "$max_zoom" \
        --bbox "$min_lon,$min_lat,$max_lon,$max_lat"
    
    if [[ $? -eq 0 ]]; then
        info "Tiles generated successfully for $region_name"
        
        # Extract tiles to directory structure for offline use
        extract_tiles_from_mbtiles "$tiles_dir/${region_name}.mbtiles" "$tiles_dir"
        
        return 0
    else
        error "Failed to generate tiles for $region_name"
        return 1
    fi
}

# Extract tiles from MBTiles to directory structure
extract_tiles_from_mbtiles() {
    local mbtiles_file="$1"
    local output_dir="$2"
    
    info "Extracting tiles from MBTiles: $(basename "$mbtiles_file")"
    
    # Use mb-util or custom extraction
    docker run --rm \
        -v "$(dirname "$mbtiles_file"):/data" \
        -v "$output_dir:/output" \
        openmaptiles/mb-util \
        "/data/$(basename "$mbtiles_file")" "/output/extracted" \
        --image_format=pbf
    
    if [[ $? -eq 0 ]]; then
        info "Tiles extracted successfully"
        
        # Organize tiles in z/x/y structure
        if [[ -d "$output_dir/extracted" ]]; then
            mv "$output_dir/extracted"/* "$output_dir/"
            rmdir "$output_dir/extracted"
        fi
        
        return 0
    else
        error "Failed to extract tiles from MBTiles"
        return 1
    fi
}

# Create region metadata file
create_region_metadata() {
    local region_name="$1"
    local region_dir="$2"
    
    info "Creating metadata for region: $region_name"
    
    # Get region details from database
    local metadata_query="
        SELECT json_build_object(
            'id', id,
            'name', name,
            'description', description,
            'bounds', ST_AsGeoJSON(bounds),
            'min_zoom', min_zoom,
            'max_zoom', max_zoom,
            'priority', priority,
            'estimated_size_mb', estimated_size_mb,
            'features', features,
            'metadata', metadata,
            'created_at', created_at,
            'updated_at', updated_at
        ) FROM regions WHERE name = '$region_name'
    "
    
    local region_metadata=$(docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -t -c "$metadata_query" | tr -d ' ')
    
    if [[ -z "$region_metadata" ]]; then
        error "Could not retrieve metadata for region: $region_name"
        return 1
    fi
    
    # Create metadata file
    cat > "$region_dir/metadata.json" << EOF
{
    "region": $region_metadata,
    "package": {
        "generated_at": "$(date -Iseconds)",
        "version": "1.0.0",
        "format": "mvt",
        "tile_scheme": "xyz",
        "coordinate_system": "EPSG:3857"
    },
    "files": {
        "tiles": "tiles/",
        "style": "style.json",
        "fonts": "fonts/",
        "sprites": "sprites/"
    }
}
EOF

    # Copy tactical style
    cp "$(pwd)/tactical-style.json" "$region_dir/style.json"
    
    # Create fonts and sprites directories (placeholder)
    mkdir -p "$region_dir/fonts" "$region_dir/sprites"
    
    info "Metadata created for region: $region_name"
}

# Package region into downloadable archive
package_region() {
    local region_name="$1"
    local region_dir="$2"
    
    info "Packaging region: $region_name"
    
    local package_file="$DATA_DIR/${region_name}.tar.gz"
    
    # Create compressed archive
    tar -czf "$package_file" -C "$REGIONS_DIR" "$region_name"
    
    if [[ $? -eq 0 ]]; then
        local package_size=$(stat -f%z "$package_file" 2>/dev/null || stat -c%s "$package_file")
        
        info "Region packaged: $(basename "$package_file") ($(numfmt --to=iec $package_size))"
        
        # Update database with package information
        docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -c "
            UPDATE regions 
            SET metadata = metadata || json_build_object(
                'package_file', '$package_file',
                'package_size', $package_size,
                'packaged_at', '$(date -Iseconds)'
            )
            WHERE name = '$region_name'
        "
        
        # Clean up temporary region directory
        rm -rf "$region_dir"
        
        return 0
    else
        error "Failed to package region: $region_name"
        return 1
    fi
}

# Generate all predefined regions
generate_all_regions() {
    log "Generating all predefined regions"
    
    # Get list of regions from database
    local regions_query="SELECT name, min_zoom, max_zoom FROM regions WHERE status = 'active' ORDER BY priority DESC"
    
    docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -t -c "$regions_query" | while IFS='|' read -r name min_zoom max_zoom; do
        # Trim whitespace
        name=$(echo "$name" | tr -d ' ')
        min_zoom=$(echo "$min_zoom" | tr -d ' ')
        max_zoom=$(echo "$max_zoom" | tr -d ' ')
        
        if [[ -n "$name" ]]; then
            generate_region_package "$name" "$min_zoom" "$max_zoom"
        fi
    done
    
    log "All regions generated"
}

# Validate region package
validate_region_package() {
    local region_name="$1"
    
    info "Validating region package: $region_name"
    
    local package_file="$DATA_DIR/${region_name}.tar.gz"
    
    if [[ ! -f "$package_file" ]]; then
        error "Package file not found: $package_file"
        return 1
    fi
    
    # Test archive integrity
    if ! tar -tzf "$package_file" > /dev/null 2>&1; then
        error "Package archive is corrupted: $package_file"
        return 1
    fi
    
    # Check for required files
    local required_files=("metadata.json" "style.json" "tiles/")
    
    for required_file in "${required_files[@]}"; do
        if ! tar -tzf "$package_file" | grep -q "$region_name/$required_file"; then
            error "Required file missing from package: $required_file"
            return 1
        fi
    done
    
    # Check tile count
    local tile_count=$(tar -tzf "$package_file" | grep -c "\.mvt$" || echo "0")
    
    if [[ "$tile_count" -eq 0 ]]; then
        error "No tiles found in package: $package_file"
        return 1
    fi
    
    info "Region package validation successful: $region_name ($tile_count tiles)"
    return 0
}

# List available regions
list_regions() {
    log "Available regions:"
    
    docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -c "
        SELECT 
            name,
            description,
            min_zoom || '-' || max_zoom as zoom_range,
            estimated_size_mb || ' MB' as estimated_size,
            CASE WHEN preload THEN 'Yes' ELSE 'No' END as preload,
            status
        FROM regions 
        ORDER BY priority DESC, name;
    "
}

# Clean up old region packages
cleanup_old_packages() {
    local retention_days="${1:-30}"
    
    log "Cleaning up region packages older than $retention_days days"
    
    find "$DATA_DIR" -name "*.tar.gz" -mtime +$retention_days -delete
    find "$REGIONS_DIR" -type d -mtime +$retention_days -exec rm -rf {} +
    
    log "Cleanup complete"
}

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  generate REGION         - Generate specific region package"
    echo "  generate-all           - Generate all predefined regions"
    echo "  validate REGION        - Validate region package"
    echo "  list                   - List available regions"
    echo "  cleanup [DAYS]         - Clean up old packages (default: 30 days)"
    echo ""
    echo "Options:"
    echo "  -h, --help             - Show this help message"
    echo "  --min-zoom ZOOM        - Minimum zoom level (default: from database)"
    echo "  --max-zoom ZOOM        - Maximum zoom level (default: from database)"
    echo ""
    echo "Examples:"
    echo "  $0 generate tactical-zone-1"
    echo "  $0 generate-all"
    echo "  $0 validate tactical-zone-1"
    echo "  $0 list"
    echo "  $0 cleanup 7"
}

# Parse command line arguments
MIN_ZOOM=""
MAX_ZOOM=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        --min-zoom)
            MIN_ZOOM="$2"
            shift 2
            ;;
        --max-zoom)
            MAX_ZOOM="$2"
            shift 2
            ;;
        generate)
            if [[ $# -lt 2 ]]; then
                error "Generate command requires region name"
                usage
                exit 1
            fi
            setup_directories
            generate_region_package "$2" "$MIN_ZOOM" "$MAX_ZOOM"
            exit $?
            ;;
        generate-all)
            setup_directories
            generate_all_regions
            exit 0
            ;;
        validate)
            if [[ $# -lt 2 ]]; then
                error "Validate command requires region name"
                usage
                exit 1
            fi
            validate_region_package "$2"
            exit $?
            ;;
        list)
            list_regions
            exit 0
            ;;
        cleanup)
            local days="${2:-30}"
            cleanup_old_packages "$days"
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