#!/bin/bash

# Import Maps Script for Tactical Deployment Server
# This script imports map data into the OpenMapTiles system

set -e

# Configuration
MAPS_DIR="/mnt/secure_storage/maps"
DATA_DIR="$MAPS_DIR/data"
TILES_DIR="$MAPS_DIR/tiles"
IMPORT_DIR="$MAPS_DIR/import"
LOG_FILE="/var/log/map-import.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root or with sudo
check_permissions() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Create necessary directories
setup_directories() {
    log "Setting up directories..."
    
    mkdir -p "$MAPS_DIR" "$DATA_DIR" "$TILES_DIR" "$IMPORT_DIR"
    mkdir -p "$MAPS_DIR/cache" "$MAPS_DIR/temp" "$MAPS_DIR/backup"
    
    # Set proper permissions
    chown -R 1000:1000 "$MAPS_DIR"
    chmod -R 755 "$MAPS_DIR"
    
    log "Directories created successfully"
}

# Download OpenStreetMap data for specified region
download_osm_data() {
    local region="$1"
    local bbox="$2"
    
    log "Downloading OSM data for region: $region"
    
    if [[ -z "$bbox" ]]; then
        error "Bounding box not specified for region $region"
        return 1
    fi
    
    local output_file="$IMPORT_DIR/${region}.osm.pbf"
    
    # Use Overpass API to download data
    local overpass_query="[out:xml][timeout:3600];(relation[\"boundary\"=\"administrative\"]($bbox);way(r);node(w););out meta;"
    
    # Alternative: Download from Geofabrik (for larger regions)
    case "$region" in
        "san-francisco")
            wget -O "$output_file" "https://download.geofabrik.de/north-america/us/california/norcal-latest.osm.pbf"
            ;;
        "tactical-zone-1")
            # Custom tactical zone - use Overpass API
            curl -X POST \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "data=$overpass_query" \
                "https://overpass-api.de/api/interpreter" \
                -o "$output_file"
            ;;
        *)
            warn "Unknown region: $region. Please add download configuration."
            return 1
            ;;
    esac
    
    if [[ -f "$output_file" ]]; then
        log "Downloaded OSM data: $output_file"
        return 0
    else
        error "Failed to download OSM data for $region"
        return 1
    fi
}

# Import OSM data into PostgreSQL
import_osm_to_postgres() {
    local osm_file="$1"
    local region_name="$2"
    
    log "Importing OSM data to PostgreSQL: $osm_file"
    
    # Use osm2pgsql to import data
    docker run --rm \
        --network tactical-network \
        -v "$IMPORT_DIR:/data" \
        -v "$(pwd)/osm2pgsql.style:/style.style" \
        openmaptiles/import-osm \
        osm2pgsql \
        --create \
        --database tactical_maps \
        --username maps_user \
        --host postgres \
        --port 5432 \
        --style /style.style \
        --multi-geometry \
        --hstore \
        --slim \
        --drop \
        "/data/$(basename "$osm_file")"
    
    if [[ $? -eq 0 ]]; then
        log "Successfully imported OSM data for $region_name"
        
        # Update map metadata in database
        docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -c "
            INSERT INTO map_metadata (name, description, file_path, status, metadata)
            VALUES ('$region_name', 'Imported OSM data for $region_name', '$osm_file', 'active', 
                    '{\"source\": \"openstreetmap\", \"import_date\": \"$(date -Iseconds)\"}')
            ON CONFLICT (name) DO UPDATE SET
                updated_at = CURRENT_TIMESTAMP,
                file_path = EXCLUDED.file_path,
                metadata = EXCLUDED.metadata;
        "
    else
        error "Failed to import OSM data for $region_name"
        return 1
    fi
}

# Generate vector tiles from imported data
generate_tiles() {
    local region_name="$1"
    local min_zoom="${2:-0}"
    local max_zoom="${3:-14}"
    
    log "Generating tiles for $region_name (zoom $min_zoom-$max_zoom)"
    
    # Use TileServer GL to generate tiles
    docker run --rm \
        --network tactical-network \
        -v "$TILES_DIR:/tiles" \
        -v "$(pwd)/tactical-style.json:/style.json" \
        openmaptiles/generate-tiles \
        generate-tiles \
        --database postgresql://maps_user:${MAPS_DB_PASSWORD}@postgres:5432/tactical_maps \
        --style /style.json \
        --output "/tiles/${region_name}.mbtiles" \
        --min-zoom "$min_zoom" \
        --max-zoom "$max_zoom" \
        --bbox-query "SELECT ST_AsText(bounds) FROM regions WHERE name = '$region_name'"
    
    if [[ $? -eq 0 ]]; then
        log "Successfully generated tiles for $region_name"
        
        # Update database with tile information
        local tile_file="$TILES_DIR/${region_name}.mbtiles"
        local file_size=$(stat -f%z "$tile_file" 2>/dev/null || stat -c%s "$tile_file" 2>/dev/null || echo "0")
        
        docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -c "
            UPDATE map_metadata 
            SET file_size = $file_size,
                metadata = metadata || '{\"tiles_generated\": \"$(date -Iseconds)\", \"min_zoom\": $min_zoom, \"max_zoom\": $max_zoom}'
            WHERE name = '$region_name';
        "
    else
        error "Failed to generate tiles for $region_name"
        return 1
    fi
}

# Import custom tactical overlays
import_tactical_overlays() {
    local overlays_file="$1"
    
    if [[ ! -f "$overlays_file" ]]; then
        warn "Tactical overlays file not found: $overlays_file"
        return 0
    fi
    
    log "Importing tactical overlays from: $overlays_file"
    
    # Import GeoJSON overlays into database
    docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -c "
        CREATE TEMP TABLE temp_overlays (data jsonb);
        \copy temp_overlays FROM '$overlays_file' CSV QUOTE e'\x01' DELIMITER e'\x02';
        
        INSERT INTO tactical_overlays (name, description, geometry, overlay_type, style, metadata)
        SELECT 
            data->>'name',
            data->>'description',
            ST_SetSRID(ST_GeomFromGeoJSON(data->'geometry'), 4326),
            data->>'type',
            COALESCE(data->'style', '{}'),
            data->'properties'
        FROM temp_overlays
        WHERE data IS NOT NULL;
    "
    
    log "Imported tactical overlays successfully"
}

# Validate imported data
validate_import() {
    local region_name="$1"
    
    log "Validating import for $region_name"
    
    # Check database records
    local map_count=$(docker exec tactical-maps-postgres psql -U maps_user -d tactical_maps -t -c "
        SELECT COUNT(*) FROM map_metadata WHERE name = '$region_name' AND status = 'active';
    " | tr -d ' ')
    
    if [[ "$map_count" -eq 0 ]]; then
        error "No map metadata found for $region_name"
        return 1
    fi
    
    # Check tile file exists
    local tile_file="$TILES_DIR/${region_name}.mbtiles"
    if [[ ! -f "$tile_file" ]]; then
        error "Tile file not found: $tile_file"
        return 1
    fi
    
    # Check tile file size
    local file_size=$(stat -f%z "$tile_file" 2>/dev/null || stat -c%s "$tile_file" 2>/dev/null || echo "0")
    if [[ "$file_size" -lt 1024 ]]; then
        error "Tile file appears to be empty or corrupted: $tile_file"
        return 1
    fi
    
    log "Import validation successful for $region_name"
    return 0
}

# Main import function
import_region() {
    local region_name="$1"
    local bbox="$2"
    local min_zoom="${3:-0}"
    local max_zoom="${4:-14}"
    
    log "Starting import for region: $region_name"
    
    # Download OSM data
    if ! download_osm_data "$region_name" "$bbox"; then
        error "Failed to download data for $region_name"
        return 1
    fi
    
    # Import to PostgreSQL
    local osm_file="$IMPORT_DIR/${region_name}.osm.pbf"
    if ! import_osm_to_postgres "$osm_file" "$region_name"; then
        error "Failed to import data for $region_name"
        return 1
    fi
    
    # Generate tiles
    if ! generate_tiles "$region_name" "$min_zoom" "$max_zoom"; then
        error "Failed to generate tiles for $region_name"
        return 1
    fi
    
    # Validate import
    if ! validate_import "$region_name"; then
        error "Import validation failed for $region_name"
        return 1
    fi
    
    log "Successfully imported region: $region_name"
    return 0
}

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  setup                    - Setup directories and permissions"
    echo "  import REGION BBOX       - Import specific region with bounding box"
    echo "  import-all              - Import all predefined regions"
    echo "  validate REGION         - Validate imported region"
    echo ""
    echo "Options:"
    echo "  -h, --help              - Show this help message"
    echo "  --min-zoom ZOOM         - Minimum zoom level (default: 0)"
    echo "  --max-zoom ZOOM         - Maximum zoom level (default: 14)"
    echo ""
    echo "Examples:"
    echo "  $0 setup"
    echo "  $0 import tactical-zone-1 \"-122.5,37.7,-122.3,37.9\""
    echo "  $0 import-all"
    echo "  $0 validate tactical-zone-1"
}

# Parse command line arguments
MIN_ZOOM=0
MAX_ZOOM=14

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
        setup)
            check_permissions
            setup_directories
            exit 0
            ;;
        import)
            if [[ $# -lt 3 ]]; then
                error "Import command requires region name and bounding box"
                usage
                exit 1
            fi
            check_permissions
            setup_directories
            import_region "$2" "$3" "$MIN_ZOOM" "$MAX_ZOOM"
            exit $?
            ;;
        import-all)
            check_permissions
            setup_directories
            
            # Import predefined regions
            import_region "tactical-zone-1" "-122.5,37.7,-122.3,37.9" 0 18
            import_region "tactical-zone-2" "-122.7,37.5,-122.5,37.7" 0 18
            import_region "base-operations" "-122.4,37.75,-122.35,37.8" 0 20
            
            exit 0
            ;;
        validate)
            if [[ $# -lt 2 ]]; then
                error "Validate command requires region name"
                usage
                exit 1
            fi
            validate_import "$2"
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