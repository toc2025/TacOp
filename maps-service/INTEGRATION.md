# Maps Service Integration Guide

## Overview

The Maps Service provides offline mapping capabilities with tactical overlays and team tracking integration for the Mobile Tactical Deployment Server. This service integrates with the existing location service and PWA interface to provide comprehensive mapping functionality.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   PWA Interface │────│   Maps Service  │────│  OpenMapTiles   │
│                 │    │                 │    │                 │
│ - Tactical UI   │    │ - API Server    │    │ - Vector Tiles  │
│ - Map Controls  │    │ - Tile Cache    │    │ - Style Server  │
│ - Team Display  │    │ - WebSocket     │    │ - MBTiles       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │              ┌─────────────────┐              │
         │              │   PostgreSQL    │              │
         └──────────────│                 │──────────────┘
                        │ - Map Metadata  │
                        │ - Waypoints     │
                        │ - Overlays      │
                        │ - Team Data     │
                        └─────────────────┘
                                 │
                        ┌─────────────────┐
                        │     Redis       │
                        │                 │
                        │ - Tile Cache    │
                        │ - Sessions      │
                        │ - Real-time     │
                        └─────────────────┘
```

## Components

### 1. Core Services

- **Maps Service** (`map-server.js`): Main application server
- **Map Manager** (`map-manager.js`): Tile generation and caching
- **Tactical Maps** (`tactical-maps.js`): Team integration and overlays
- **OpenMapTiles**: Vector tile server for offline mapping

### 2. Database Schema

- **PostgreSQL with PostGIS**: Spatial data storage
- **Tables**: map_metadata, regions, waypoints, tactical_overlays, map_tiles_cache
- **Spatial Indexes**: Optimized for geographic queries

### 3. Frontend Integration

- **Tactical Map Interface**: Full-featured mapping interface
- **PWA Integration**: Embedded maps in tactical interface
- **Real-time Updates**: WebSocket integration for live data

### 4. Data Processing

- **Import Scripts**: OSM data import and processing
- **Optimization**: Tile compression and deduplication
- **Region Generation**: Downloadable map packages
- **Validation**: Data integrity and system health checks

## Installation

### Prerequisites

- Docker and Docker Compose
- Node.js 18+ and npm
- 8GB+ RAM (6GB for maps service)
- 500GB+ storage for map data
- PostgreSQL with PostGIS
- Redis

### Quick Setup

1. **Clone and Navigate**:
   ```bash
   cd maps-service
   ```

2. **Run Setup Script**:
   ```bash
   # On Linux/macOS
   chmod +x setup.sh
   ./setup.sh
   
   # On Windows
   # Use Git Bash or WSL to run the setup script
   ```

3. **Manual Setup** (if script fails):
   ```bash
   # Copy environment template
   cp .env.example .env
   
   # Edit .env with your configuration
   nano .env
   
   # Install dependencies
   npm install
   
   # Create Docker network
   docker network create tactical-network
   
   # Start services
   docker-compose -f docker-compose.maps.yml up -d
   
   # Initialize database
   docker exec -i tactical-maps-postgres psql -U postgres < maps-schema.sql
   ```

### Configuration

1. **Environment Variables** (`.env`):
   ```env
   POSTGRES_PASSWORD=your_secure_password
   MAPS_DB_PASSWORD=your_maps_password
   REDIS_PASSWORD=your_redis_password
   JWT_SECRET=your_jwt_secret
   ```

2. **Map Configuration** (`map-config.json`):
   - Server settings
   - Database connection
   - Storage paths
   - Performance tuning

3. **Tactical Regions** (`regions.json`):
   - Predefined operational areas
   - Download settings
   - Priority levels

## Integration with Existing Services

### 1. Location Service Integration

The maps service integrates with the existing location service to display real-time team positions:

```javascript
// Location data is fetched from location service
const response = await fetch('http://location-service:3001/api/locations');
const locations = await response.json();

// Transformed to GeoJSON for map display
const geoJsonFeatures = locations.map(location => ({
    type: 'Feature',
    geometry: {
        type: 'Point',
        coordinates: [location.longitude, location.latitude]
    },
    properties: {
        callsign: location.callsign,
        status: location.status,
        timestamp: location.timestamp
    }
}));
```

### 2. PWA Interface Integration

The PWA tactical interface now includes the maps service:

```html
<!-- Maps section in tactical-interface.html -->
<iframe id="maps-frame" 
        src="http://localhost:8080/static/tactical-map-interface.html" 
        title="Tactical Maps">
</iframe>
```

### 3. Real-time Updates

WebSocket integration provides live updates:

```javascript
// WebSocket connection for real-time data
const websocket = new WebSocket('ws://localhost:8080/ws');

websocket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    switch (message.type) {
        case 'location_update':
            updateTeamLocation(message.data);
            break;
        case 'waypoint_update':
            refreshWaypoints();
            break;
    }
};
```

## API Endpoints

### Map Tiles
- `GET /tiles/{z}/{x}/{y}.mvt` - Vector map tiles
- `GET /style/{styleName}` - Map style configuration

### Regions
- `GET /api/regions` - List available regions
- `POST /api/regions/{id}/download` - Download region package

### Waypoints
- `GET /api/waypoints` - List waypoints
- `POST /api/waypoints` - Create waypoint
- `PUT /api/waypoints/{id}` - Update waypoint
- `DELETE /api/waypoints/{id}` - Delete waypoint

### Tactical Overlays
- `GET /api/overlays` - List tactical overlays
- `POST /api/overlays` - Create overlay

### Team Locations
- `GET /api/team-locations` - Get team positions (from location service)

### System
- `GET /health` - Service health check
- `GET /api/stats` - System statistics

## Data Management

### Map Data Import

```bash
# Import specific region
./scripts/import-maps.sh import tactical-zone-1 "-122.5,37.7,-122.3,37.9"

# Import all predefined regions
./scripts/import-maps.sh import-all

# Validate imported data
./scripts/validate-maps.sh full
```

### Tile Optimization

```bash
# Optimize all tiles
./scripts/optimize-tiles.sh optimize-all

# Compress specific directory
./scripts/optimize-tiles.sh compress-tiles /path/to/tiles

# Remove duplicates
./scripts/optimize-tiles.sh deduplicate
```

### Region Generation

```bash
# Generate specific region package
./scripts/generate-regions.sh generate tactical-zone-1

# Generate all regions
./scripts/generate-regions.sh generate-all

# List available regions
./scripts/generate-regions.sh list
```

## Security Considerations

### 1. Authentication
- JWT-based authentication for API access
- Integration with existing user management

### 2. Data Protection
- Map data encryption at rest
- Secure tile serving over HTTPS
- Access control for sensitive areas

### 3. Network Security
- Docker network isolation
- Firewall configuration
- VPN integration for remote access

## Performance Optimization

### 1. Caching Strategy
- **Redis**: Fast tile cache (2GB default)
- **Database**: Persistent tile storage
- **Browser**: Client-side caching headers

### 2. Resource Allocation
- **Memory**: 6GB for maps service
- **Storage**: 500GB for map data
- **CPU**: Multi-threaded tile processing

### 3. Network Optimization
- **Compression**: Gzip tile compression
- **CDN**: Optional CDN integration
- **Bandwidth**: Optimized for mobile clients

## Monitoring and Maintenance

### 1. Health Checks
```bash
# System validation
./scripts/validate-maps.sh full

# Service health
curl http://localhost:8080/health

# Statistics
curl http://localhost:8080/api/stats
```

### 2. Log Management
- Service logs: `/var/log/maps-service.log`
- Docker logs: `docker-compose logs -f`
- Access logs: Database audit trail

### 3. Backup Procedures
- Database backups: PostgreSQL dumps
- Map data: File system backups
- Configuration: Version control

## Troubleshooting

### Common Issues

1. **Service Won't Start**:
   ```bash
   # Check Docker status
   docker ps
   
   # Check logs
   docker-compose -f docker-compose.maps.yml logs
   
   # Restart services
   docker-compose -f docker-compose.maps.yml restart
   ```

2. **Database Connection Issues**:
   ```bash
   # Test database connection
   docker exec tactical-maps-postgres pg_isready -U maps_user -d tactical_maps
   
   # Check database logs
   docker logs tactical-maps-postgres
   ```

3. **Tile Loading Problems**:
   ```bash
   # Validate tile cache
   ./scripts/validate-maps.sh mbtiles
   
   # Clear cache
   docker exec tactical-maps-redis redis-cli FLUSHDB
   ```

4. **Memory Issues**:
   ```bash
   # Check memory usage
   docker stats
   
   # Optimize tile cache
   ./scripts/optimize-tiles.sh optimize-cache
   ```

### Performance Tuning

1. **Increase Memory**:
   - Edit `docker-compose.maps.yml`
   - Adjust memory limits for containers

2. **Optimize Database**:
   - Tune PostgreSQL configuration
   - Add spatial indexes
   - Vacuum and analyze regularly

3. **Cache Optimization**:
   - Adjust Redis memory settings
   - Tune cache TTL values
   - Monitor hit rates

## Development

### Local Development Setup

1. **Environment**:
   ```bash
   # Set development mode
   export NODE_ENV=development
   
   # Start in development mode
   npm run dev
   ```

2. **Testing**:
   ```bash
   # Run tests
   npm test
   
   # Validate installation
   ./scripts/validate-maps.sh full
   ```

3. **Debugging**:
   - Enable debug logging in `map-config.json`
   - Use browser developer tools for frontend
   - Monitor WebSocket connections

### Contributing

1. Follow existing code style and patterns
2. Add tests for new functionality
3. Update documentation
4. Validate with test data before production

## Support

For issues and questions:
1. Check logs and validation output
2. Review configuration files
3. Consult troubleshooting section
4. Check Docker container status
5. Verify network connectivity

## License

This maps service is part of the Mobile Tactical Deployment Server project and follows the same licensing terms.