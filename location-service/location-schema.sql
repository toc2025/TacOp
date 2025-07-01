-- Tactical Location Service Database Schema
-- Version: 1.0.0
-- PostgreSQL 15+ compatible schema for temporary location storage

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop existing tables if they exist (for clean reinstall)
DROP TABLE IF EXISTS emergency_alerts CASCADE;
DROP TABLE IF EXISTS waypoints CASCADE;
DROP TABLE IF EXISTS location_updates CASCADE;
DROP TABLE IF EXISTS team_members CASCADE;
DROP TABLE IF EXISTS devices CASCADE;

-- Create devices table for device registration and authentication
CREATE TABLE devices (
    id SERIAL PRIMARY KEY,
    device_id VARCHAR(255) UNIQUE NOT NULL,
    user_id VARCHAR(255) NOT NULL,
    device_fingerprint TEXT,
    device_info JSONB DEFAULT '{}',
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create team members table for user profiles and status
CREATE TABLE team_members (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) UNIQUE NOT NULL,
    callsign VARCHAR(100),
    role VARCHAR(100) DEFAULT 'operator',
    status VARCHAR(50) DEFAULT 'active',
    permissions JSONB DEFAULT '{}',
    last_activity TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create location updates table for temporary GPS tracking
CREATE TABLE location_updates (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    device_id VARCHAR(255),
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    accuracy DECIMAL(8, 2),
    heading DECIMAL(5, 2),
    speed DECIMAL(8, 2),
    altitude DECIMAL(8, 2),
    altitude_accuracy DECIMAL(8, 2),
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    battery_level DECIMAL(3, 2),
    is_moving BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create waypoints table for marked locations
CREATE TABLE waypoints (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT 'Waypoint',
    description TEXT,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    waypoint_type VARCHAR(50) DEFAULT 'manual',
    metadata JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create emergency alerts table for distress signals
CREATE TABLE emergency_alerts (
    id SERIAL PRIMARY KEY,
    alert_id VARCHAR(255) UNIQUE NOT NULL DEFAULT gen_random_uuid()::text,
    user_id VARCHAR(255) NOT NULL,
    message TEXT NOT NULL DEFAULT 'Emergency assistance required',
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    status VARCHAR(50) DEFAULT 'active',
    priority VARCHAR(20) DEFAULT 'high',
    acknowledged_by VARCHAR(255),
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    resolved_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance optimization
CREATE INDEX idx_devices_device_id ON devices(device_id);
CREATE INDEX idx_devices_user_id ON devices(user_id);
CREATE INDEX idx_devices_last_seen ON devices(last_seen);
CREATE INDEX idx_devices_active ON devices(is_active);

CREATE INDEX idx_team_members_user_id ON team_members(user_id);
CREATE INDEX idx_team_members_status ON team_members(status);
CREATE INDEX idx_team_members_last_activity ON team_members(last_activity);

CREATE INDEX idx_location_updates_user_id ON location_updates(user_id);
CREATE INDEX idx_location_updates_timestamp ON location_updates(timestamp);
CREATE INDEX idx_location_updates_created_at ON location_updates(created_at);
CREATE INDEX idx_location_updates_user_timestamp ON location_updates(user_id, timestamp);

-- Spatial index for location queries (if PostGIS is available)
-- CREATE INDEX idx_location_updates_coords ON location_updates USING GIST(ST_Point(longitude, latitude));

CREATE INDEX idx_waypoints_user_id ON waypoints(user_id);
CREATE INDEX idx_waypoints_active ON waypoints(is_active);
CREATE INDEX idx_waypoints_created_at ON waypoints(created_at);

CREATE INDEX idx_emergency_alerts_user_id ON emergency_alerts(user_id);
CREATE INDEX idx_emergency_alerts_status ON emergency_alerts(status);
CREATE INDEX idx_emergency_alerts_created_at ON emergency_alerts(created_at);
CREATE INDEX idx_emergency_alerts_alert_id ON emergency_alerts(alert_id);

-- Create triggers for automatic timestamp updates
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_devices_updated_at BEFORE UPDATE ON devices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_team_members_updated_at BEFORE UPDATE ON team_members
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_waypoints_updated_at BEFORE UPDATE ON waypoints
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_emergency_alerts_updated_at BEFORE UPDATE ON emergency_alerts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create function for automatic data cleanup (no persistent client data)
CREATE OR REPLACE FUNCTION cleanup_old_location_data()
RETURNS void AS $$
BEGIN
    -- Delete location updates older than 24 hours
    DELETE FROM location_updates 
    WHERE created_at < NOW() - INTERVAL '24 hours';
    
    -- Delete resolved emergency alerts older than 7 days
    DELETE FROM emergency_alerts 
    WHERE status = 'resolved' 
    AND resolved_at < NOW() - INTERVAL '7 days';
    
    -- Update device last_seen status
    UPDATE devices 
    SET is_active = false 
    WHERE last_seen < NOW() - INTERVAL '1 hour';
    
    -- Log cleanup operation
    RAISE NOTICE 'Location data cleanup completed at %', NOW();
END;
$$ LANGUAGE plpgsql;

-- Create function to get current team status
CREATE OR REPLACE FUNCTION get_team_status()
RETURNS TABLE (
    user_id VARCHAR(255),
    callsign VARCHAR(100),
    device_id VARCHAR(255),
    is_online BOOLEAN,
    last_seen TIMESTAMP WITH TIME ZONE,
    current_latitude DECIMAL(10, 8),
    current_longitude DECIMAL(11, 8),
    last_location_update TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        tm.user_id,
        tm.callsign,
        d.device_id,
        (d.last_seen > NOW() - INTERVAL '5 minutes') as is_online,
        d.last_seen,
        l.latitude as current_latitude,
        l.longitude as current_longitude,
        l.timestamp as last_location_update
    FROM team_members tm
    LEFT JOIN devices d ON tm.user_id = d.user_id
    LEFT JOIN LATERAL (
        SELECT latitude, longitude, timestamp
        FROM location_updates lu
        WHERE lu.user_id = tm.user_id
        ORDER BY timestamp DESC
        LIMIT 1
    ) l ON true
    WHERE tm.status = 'active'
    ORDER BY d.last_seen DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql;

-- Create function to get location history for a user
CREATE OR REPLACE FUNCTION get_location_history(
    p_user_id VARCHAR(255),
    p_limit INTEGER DEFAULT 100,
    p_since TIMESTAMP WITH TIME ZONE DEFAULT NULL
)
RETURNS TABLE (
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    accuracy DECIMAL(8, 2),
    heading DECIMAL(5, 2),
    speed DECIMAL(8, 2),
    altitude DECIMAL(8, 2),
    timestamp TIMESTAMP WITH TIME ZONE,
    battery_level DECIMAL(3, 2),
    is_moving BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        lu.latitude,
        lu.longitude,
        lu.accuracy,
        lu.heading,
        lu.speed,
        lu.altitude,
        lu.timestamp,
        lu.battery_level,
        lu.is_moving
    FROM location_updates lu
    WHERE lu.user_id = p_user_id
    AND (p_since IS NULL OR lu.timestamp > p_since)
    ORDER BY lu.timestamp DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Create function to calculate distance between two points
CREATE OR REPLACE FUNCTION calculate_distance(
    lat1 DECIMAL(10, 8),
    lon1 DECIMAL(11, 8),
    lat2 DECIMAL(10, 8),
    lon2 DECIMAL(11, 8)
)
RETURNS DECIMAL(10, 2) AS $$
DECLARE
    earth_radius CONSTANT DECIMAL := 6371000; -- Earth radius in meters
    dlat DECIMAL;
    dlon DECIMAL;
    a DECIMAL;
    c DECIMAL;
BEGIN
    dlat := radians(lat2 - lat1);
    dlon := radians(lon2 - lon1);
    
    a := sin(dlat/2) * sin(dlat/2) + 
         cos(radians(lat1)) * cos(radians(lat2)) * 
         sin(dlon/2) * sin(dlon/2);
    
    c := 2 * atan2(sqrt(a), sqrt(1-a));
    
    RETURN earth_radius * c;
END;
$$ LANGUAGE plpgsql;

-- Create scheduled job for automatic cleanup (requires pg_cron extension)
-- SELECT cron.schedule('location-cleanup', '0 */6 * * *', 'SELECT cleanup_old_location_data();');

-- Insert default team member roles and permissions
INSERT INTO team_members (user_id, callsign, role, permissions) VALUES
('admin', 'Command', 'commander', '{"admin": true, "view_all": true, "manage_alerts": true}'),
('alpha-1', 'Alpha-1', 'team_leader', '{"view_team": true, "manage_waypoints": true, "send_alerts": true}'),
('alpha-2', 'Alpha-2', 'operator', '{"view_team": true, "send_alerts": true}'),
('bravo-1', 'Bravo-1', 'operator', '{"view_team": true, "send_alerts": true}'),
('charlie-1', 'Charlie-1', 'support', '{"view_team": true}')
ON CONFLICT (user_id) DO NOTHING;

-- Create view for active team locations
CREATE OR REPLACE VIEW active_team_locations AS
SELECT 
    tm.user_id,
    tm.callsign,
    tm.role,
    d.device_id,
    d.last_seen,
    (d.last_seen > NOW() - INTERVAL '5 minutes') as is_online,
    l.latitude,
    l.longitude,
    l.accuracy,
    l.heading,
    l.speed,
    l.timestamp as location_timestamp,
    l.battery_level
FROM team_members tm
LEFT JOIN devices d ON tm.user_id = d.user_id AND d.is_active = true
LEFT JOIN LATERAL (
    SELECT latitude, longitude, accuracy, heading, speed, timestamp, battery_level
    FROM location_updates lu
    WHERE lu.user_id = tm.user_id
    ORDER BY timestamp DESC
    LIMIT 1
) l ON true
WHERE tm.status = 'active'
ORDER BY d.last_seen DESC NULLS LAST;

-- Create view for recent emergency alerts
CREATE OR REPLACE VIEW recent_emergency_alerts AS
SELECT 
    ea.alert_id,
    ea.user_id,
    tm.callsign,
    ea.message,
    ea.latitude,
    ea.longitude,
    ea.status,
    ea.priority,
    ea.acknowledged_by,
    ea.acknowledged_at,
    ea.created_at,
    EXTRACT(EPOCH FROM (NOW() - ea.created_at)) as seconds_ago
FROM emergency_alerts ea
LEFT JOIN team_members tm ON ea.user_id = tm.user_id
WHERE ea.created_at > NOW() - INTERVAL '24 hours'
ORDER BY ea.created_at DESC;

-- Grant permissions for tactical user
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tactical') THEN
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO tactical;
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO tactical;
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO tactical;
    END IF;
END
$$;

-- Create database statistics and monitoring
CREATE OR REPLACE FUNCTION get_location_service_stats()
RETURNS JSON AS $$
DECLARE
    result JSON;
BEGIN
    SELECT json_build_object(
        'total_devices', (SELECT COUNT(*) FROM devices),
        'active_devices', (SELECT COUNT(*) FROM devices WHERE is_active = true),
        'online_devices', (SELECT COUNT(*) FROM devices WHERE last_seen > NOW() - INTERVAL '5 minutes'),
        'total_team_members', (SELECT COUNT(*) FROM team_members WHERE status = 'active'),
        'location_updates_24h', (SELECT COUNT(*) FROM location_updates WHERE created_at > NOW() - INTERVAL '24 hours'),
        'total_waypoints', (SELECT COUNT(*) FROM waypoints WHERE is_active = true),
        'active_alerts', (SELECT COUNT(*) FROM emergency_alerts WHERE status = 'active'),
        'database_size', pg_size_pretty(pg_database_size(current_database())),
        'last_updated', NOW()
    ) INTO result;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Add comments for documentation
COMMENT ON TABLE devices IS 'Device registration and authentication tracking';
COMMENT ON TABLE team_members IS 'Team member profiles and operational status';
COMMENT ON TABLE location_updates IS 'Temporary GPS location tracking data (auto-cleanup after 24h)';
COMMENT ON TABLE waypoints IS 'User-marked waypoints and points of interest';
COMMENT ON TABLE emergency_alerts IS 'Emergency distress signals and alerts';

COMMENT ON FUNCTION cleanup_old_location_data() IS 'Automatic cleanup of temporary location data - no persistent client storage';
COMMENT ON FUNCTION get_team_status() IS 'Real-time team status with current locations';
COMMENT ON FUNCTION calculate_distance(DECIMAL, DECIMAL, DECIMAL, DECIMAL) IS 'Calculate distance between two GPS coordinates in meters';

-- Final setup message
DO $$
BEGIN
    RAISE NOTICE '=== Tactical Location Service Database Schema Initialized ===';
    RAISE NOTICE 'Version: 1.0.0';
    RAISE NOTICE 'Features: Device tracking, Location updates, Waypoints, Emergency alerts';
    RAISE NOTICE 'Security: Automatic data cleanup, No persistent client storage';
    RAISE NOTICE 'Performance: Optimized indexes, Efficient queries';
    RAISE NOTICE '============================================================';
END
$$;