-- Tactical Server Database Initialization
-- Creates all required databases for tactical services

-- Create databases
CREATE DATABASE tactical_location;
CREATE DATABASE tactical_maps;
CREATE DATABASE outline;
CREATE DATABASE mattermost;

-- Create database users
DO $$
BEGIN
    -- Create tactical user for location service
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'tactical') THEN
        CREATE ROLE tactical WITH LOGIN PASSWORD 'PLACEHOLDER_LOCATION_PASSWORD';
    END IF;
    
    -- Create maps_user for maps service
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'maps_user') THEN
        CREATE ROLE maps_user WITH LOGIN PASSWORD 'PLACEHOLDER_MAPS_PASSWORD';
    END IF;
    
    -- Create outline user
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'outline') THEN
        CREATE ROLE outline WITH LOGIN PASSWORD 'PLACEHOLDER_OUTLINE_PASSWORD';
    END IF;
    
    -- Create mattermost user
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'mattermost') THEN
        CREATE ROLE mattermost WITH LOGIN PASSWORD 'PLACEHOLDER_MATTERMOST_PASSWORD';
    END IF;
END
$$;

-- Grant database permissions
GRANT ALL PRIVILEGES ON DATABASE tactical_location TO tactical;
GRANT ALL PRIVILEGES ON DATABASE tactical_maps TO maps_user;
GRANT ALL PRIVILEGES ON DATABASE outline TO outline;
GRANT ALL PRIVILEGES ON DATABASE mattermost TO mattermost;

-- Enable required extensions
\c tactical_location;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\c tactical_maps;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

\c outline;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\c mattermost;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Log completion
\echo 'Database initialization completed successfully'