-- Maps Service Database Schema
-- Mobile Tactical Deployment Server

-- Enable PostGIS extension for spatial data
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Map metadata table
CREATE TABLE IF NOT EXISTS map_metadata (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    bounds GEOMETRY(POLYGON, 4326) NOT NULL,
    min_zoom INTEGER DEFAULT 0,
    max_zoom INTEGER DEFAULT 18,
    tile_format VARCHAR(10) DEFAULT 'mvt',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    file_path TEXT,
    file_size BIGINT,
    checksum VARCHAR(64),
    status VARCHAR(20) DEFAULT 'active',
    priority INTEGER DEFAULT 5,
    metadata JSONB
);

-- Create spatial index on bounds
CREATE INDEX IF NOT EXISTS idx_map_metadata_bounds ON map_metadata USING GIST (bounds);
CREATE INDEX IF NOT EXISTS idx_map_metadata_status ON map_metadata (status);
CREATE INDEX IF NOT EXISTS idx_map_metadata_priority ON map_metadata (priority DESC);

-- Regions table for downloadable map areas
CREATE TABLE IF NOT EXISTS regions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    bounds GEOMETRY(POLYGON, 4326) NOT NULL,
    min_zoom INTEGER DEFAULT 0,
    max_zoom INTEGER DEFAULT 18,
    priority INTEGER DEFAULT 5,
    estimated_size_mb INTEGER,
    preload BOOLEAN DEFAULT FALSE,
    features JSONB,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active'
);

-- Create spatial index on regions bounds
CREATE INDEX IF NOT EXISTS idx_regions_bounds ON regions USING GIST (bounds);
CREATE INDEX IF NOT EXISTS idx_regions_name ON regions (name);
CREATE INDEX IF NOT EXISTS idx_regions_priority ON regions (priority DESC);

-- Waypoints table for tactical markers
CREATE TABLE IF NOT EXISTS waypoints (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    location GEOMETRY(POINT, 4326) NOT NULL,
    waypoint_type VARCHAR(50) DEFAULT 'general',
    symbol VARCHAR(50),
    color VARCHAR(7) DEFAULT '#FFFF00',
    created_by VARCHAR(100),
    team_id VARCHAR(50),
    mission_id VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'active',
    metadata JSONB
);

-- Create spatial index on waypoints location
CREATE INDEX IF NOT EXISTS idx_waypoints_location ON waypoints USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_waypoints_type ON waypoints (waypoint_type);
CREATE INDEX IF NOT EXISTS idx_waypoints_team ON waypoints (team_id);
CREATE INDEX IF NOT EXISTS idx_waypoints_mission ON waypoints (mission_id);
CREATE INDEX IF NOT EXISTS idx_waypoints_status ON waypoints (status);

-- Tactical overlays table for operational areas
CREATE TABLE IF NOT EXISTS tactical_overlays (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    geometry GEOMETRY NOT NULL,
    overlay_type VARCHAR(50) NOT NULL,
    style JSONB,
    created_by VARCHAR(100),
    team_id VARCHAR(50),
    mission_id VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'active',
    metadata JSONB
);

-- Create spatial index on tactical overlays geometry
CREATE INDEX IF NOT EXISTS idx_tactical_overlays_geometry ON tactical_overlays USING GIST (geometry);
CREATE INDEX IF NOT EXISTS idx_tactical_overlays_type ON tactical_overlays (overlay_type);
CREATE INDEX IF NOT EXISTS idx_tactical_overlays_team ON tactical_overlays (team_id);
CREATE INDEX IF NOT EXISTS idx_tactical_overlays_mission ON tactical_overlays (mission_id);

-- Map tiles cache table
CREATE TABLE IF NOT EXISTS map_tiles_cache (
    id SERIAL PRIMARY KEY,
    z INTEGER NOT NULL,
    x INTEGER NOT NULL,
    y INTEGER NOT NULL,
    tile_data BYTEA,
    content_type VARCHAR(50) DEFAULT 'application/x-protobuf',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    accessed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    access_count INTEGER DEFAULT 1,
    size_bytes INTEGER,
    checksum VARCHAR(64)
);

-- Create unique index on tile coordinates
CREATE UNIQUE INDEX IF NOT EXISTS idx_map_tiles_cache_zxy ON map_tiles_cache (z, x, y);
CREATE INDEX IF NOT EXISTS idx_map_tiles_cache_accessed ON map_tiles_cache (accessed_at);

-- Map downloads table for tracking region downloads
CREATE TABLE IF NOT EXISTS map_downloads (
    id SERIAL PRIMARY KEY,
    region_id INTEGER REFERENCES regions(id) ON DELETE CASCADE,
    user_id VARCHAR(100),
    device_id VARCHAR(100),
    status VARCHAR(20) DEFAULT 'pending',
    progress INTEGER DEFAULT 0,
    total_tiles INTEGER,
    downloaded_tiles INTEGER DEFAULT 0,
    file_path TEXT,
    file_size BIGINT,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_map_downloads_region ON map_downloads (region_id);
CREATE INDEX IF NOT EXISTS idx_map_downloads_user ON map_downloads (user_id);
CREATE INDEX IF NOT EXISTS idx_map_downloads_status ON map_downloads (status);

-- Map usage statistics
CREATE TABLE IF NOT EXISTS map_usage_stats (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(100),
    device_id VARCHAR(100),
    region_name VARCHAR(255),
    zoom_level INTEGER,
    tile_requests INTEGER DEFAULT 1,
    data_transferred BIGINT DEFAULT 0,
    session_duration INTEGER,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_map_usage_stats_user ON map_usage_stats (user_id);
CREATE INDEX IF NOT EXISTS idx_map_usage_stats_timestamp ON map_usage_stats (timestamp);
CREATE INDEX IF NOT EXISTS idx_map_usage_stats_region ON map_usage_stats (region_name);

-- Map access logs for security auditing
CREATE TABLE IF NOT EXISTS map_access_logs (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(100),
    device_id VARCHAR(100),
    ip_address INET,
    action VARCHAR(50) NOT NULL,
    resource VARCHAR(255),
    status_code INTEGER,
    user_agent TEXT,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_map_access_logs_user ON map_access_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_map_access_logs_timestamp ON map_access_logs (timestamp);
CREATE INDEX IF NOT EXISTS idx_map_access_logs_action ON map_access_logs (action);

-- Functions for automatic timestamp updates
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for automatic timestamp updates
CREATE TRIGGER update_map_metadata_updated_at BEFORE UPDATE ON map_metadata
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_regions_updated_at BEFORE UPDATE ON regions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_waypoints_updated_at BEFORE UPDATE ON waypoints
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tactical_overlays_updated_at BEFORE UPDATE ON tactical_overlays
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to clean up expired waypoints and overlays
CREATE OR REPLACE FUNCTION cleanup_expired_data()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER := 0;
BEGIN
    -- Delete expired waypoints
    DELETE FROM waypoints 
    WHERE expires_at IS NOT NULL AND expires_at < CURRENT_TIMESTAMP;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    -- Delete expired tactical overlays
    DELETE FROM tactical_overlays 
    WHERE expires_at IS NOT NULL AND expires_at < CURRENT_TIMESTAMP;
    GET DIAGNOSTICS deleted_count = deleted_count + ROW_COUNT;
    
    -- Clean up old tile cache entries (older than 7 days and not accessed recently)
    DELETE FROM map_tiles_cache 
    WHERE accessed_at < CURRENT_TIMESTAMP - INTERVAL '7 days'
    AND access_count < 5;
    GET DIAGNOSTICS deleted_count = deleted_count + ROW_COUNT;
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function to get map statistics
CREATE OR REPLACE FUNCTION get_map_statistics()
RETURNS TABLE (
    total_maps INTEGER,
    total_regions INTEGER,
    total_waypoints INTEGER,
    total_overlays INTEGER,
    cache_size_mb NUMERIC,
    storage_used_gb NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        (SELECT COUNT(*)::INTEGER FROM map_metadata WHERE status = 'active'),
        (SELECT COUNT(*)::INTEGER FROM regions WHERE status = 'active'),
        (SELECT COUNT(*)::INTEGER FROM waypoints WHERE status = 'active'),
        (SELECT COUNT(*)::INTEGER FROM tactical_overlays WHERE status = 'active'),
        (SELECT ROUND((SUM(size_bytes) / 1024.0 / 1024.0)::NUMERIC, 2) FROM map_tiles_cache),
        (SELECT ROUND((SUM(file_size) / 1024.0 / 1024.0 / 1024.0)::NUMERIC, 2) FROM map_metadata WHERE file_size IS NOT NULL);
END;
$$ LANGUAGE plpgsql;

-- Insert default regions from configuration
INSERT INTO regions (name, description, bounds, min_zoom, max_zoom, priority, estimated_size_mb, preload, features, metadata)
VALUES 
    ('global', 'Global Coverage', ST_MakeEnvelope(-180, -85, 180, 85, 4326), 0, 10, 1, 2000, true, 
     '{"teamTracking": false, "waypoints": false}', 
     '{"operationType": "global", "terrain": "mixed"}'),
    ('tactical_zone_1', 'Tactical Zone Alpha', ST_MakeEnvelope(-122.5, 37.7, -122.3, 37.9, 4326), 0, 18, 10, 150, true,
     '{"teamTracking": true, "waypoints": true, "tacticalOverlays": true, "measurements": true}',
     '{"operationType": "urban", "terrain": "mixed", "population": "high"}'),
    ('base_operations', 'Base Operations Area', ST_MakeEnvelope(-122.4, 37.75, -122.35, 37.8, 4326), 0, 20, 10, 80, true,
     '{"teamTracking": true, "waypoints": true, "tacticalOverlays": true, "measurements": true, "detailedBuildings": true}',
     '{"operationType": "base", "terrain": "flat", "population": "controlled"}')
ON CONFLICT (name) DO NOTHING;

-- Create database user for maps service
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'maps_user') THEN
        CREATE ROLE maps_user WITH LOGIN PASSWORD 'tactical_maps_2024!';
    END IF;
END
$$;

-- Grant permissions to maps user
GRANT CONNECT ON DATABASE tactical_maps TO maps_user;
GRANT USAGE ON SCHEMA public TO maps_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO maps_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO maps_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO maps_user;

-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO maps_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO maps_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO maps_user;

COMMIT;