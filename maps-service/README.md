# Maps Service - Mobile Tactical Deployment Server

## Overview
The Maps Service provides offline mapping capabilities with tactical overlays and team tracking integration using OpenMapTiles vector tile server.

## Architecture
- **OpenMapTiles Server**: Vector tile server for offline mapping
- **Map Data Management**: Tile generation, optimization, and region management
- **Tactical Interface**: Interactive maps with team location overlay
- **Database Integration**: PostgreSQL for map metadata and waypoints
- **Docker Integration**: Containerized deployment with resource allocation

## Resource Allocation
- **Memory**: 6GB RAM allocation for map server
- **Storage**: 500GB in `/mnt/secure_storage/maps/`
- **Zoom Levels**: 0-18 for tactical operations
- **Tile Format**: Vector tiles (MVT) with OpenMapTiles schema

## Components

### Core Services
- `map-server.js` - Main map server application
- `map-manager.js` - Map data management system
- `tactical-maps.js` - Tactical map interface integration

### Configuration
- `map-config.json` - Map server configuration
- `tactical-style.json` - Custom tactical map styling
- `regions.json` - Predefined tactical regions
- `docker-compose.maps.yml` - Docker container configuration

### Database
- `maps-schema.sql` - Database schema for map metadata
- Map metadata tables and waypoint storage

### Processing Tools
- `scripts/import-maps.sh` - Import tactical map data
- `scripts/optimize-tiles.sh` - Map tile optimization
- `scripts/generate-regions.sh` - Create downloadable regions
- `scripts/validate-maps.sh` - Map data validation

## Integration Points
- **Location Service**: Real-time team location overlay
- **PWA Interface**: Map display in tactical interface
- **PostgreSQL**: Map metadata and waypoint storage
- **Docker Stack**: Integration with existing services

## Setup Instructions
1. Run `docker-compose -f docker-compose.maps.yml up -d`
2. Import initial map data using `scripts/import-maps.sh`
3. Configure tactical regions with `scripts/generate-regions.sh`
4. Integrate with PWA interface for map display

## Security Features
- Secure map data storage with encryption at rest
- Access control for sensitive map areas
- Secure tile serving over HTTPS
- Audit logging for map access