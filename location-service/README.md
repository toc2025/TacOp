# Tactical Location Service

Real-time GPS location tracking service for tactical operations with encrypted WebSocket connections, battery optimization, and zero client data storage.

## Features

- **Real-time Location Tracking**: WebSocket-based GPS tracking with sub-second updates
- **Battery Optimization**: Adaptive update intervals based on movement and battery level
- **Encrypted Communications**: AES-256 encryption for all location data transmission
- **ZeroTier Integration**: Secure VPN network for tactical team connectivity
- **Zero Data Storage**: Automatic cleanup ensures no persistent client data
- **Emergency Alerts**: Instant emergency broadcasting to all team members
- **Waypoint Management**: Mark and share tactical waypoints
- **Team Status**: Real-time team member status and location monitoring
- **Offline Support**: Queue location updates when connection is lost

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Mobile PWA    │◄──►│  Location Server │◄──►│   PostgreSQL    │
│  (HTML5 GPS)    │    │   (WebSocket)    │    │   (Temporary)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         │              ┌──────────────────┐             │
         └─────────────►│   REST API       │◄────────────┘
                        │   (Management)   │
                        └──────────────────┘
                                 │
                        ┌──────────────────┐
                        │   ZeroTier VPN   │
                        │ (192.168.100.0/24)│
                        └──────────────────┘
```

## Quick Start

### Prerequisites

- Node.js 18+ 
- PostgreSQL 15+
- Redis 7+
- SSL certificates
- ZeroTier network (optional)

### Installation

```bash
# Clone and install dependencies
git clone <repository>
cd location-service
npm install

# Setup database and certificates
npm run setup

# Start the service
npm start
```

### Docker Deployment

```bash
# Start all services
docker-compose -f docker-compose.location.yml up -d

# Development mode with hot reload
docker-compose -f docker-compose.location.yml -f docker-compose.location.dev.yml up
```

## Configuration

### Environment Variables

```bash
# Core Configuration
NODE_ENV=production
WEBSOCKET_PORT=8443
API_PORT=3002

# Database
DATABASE_HOST=localhost
DATABASE_NAME=tactical_location
DATABASE_USER=tactical
DATABASE_PASSWORD=your_secure_password

# Redis Cache
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=your_redis_password

# SSL/TLS
SSL_CERT_PATH=./certs/tactical.crt
SSL_KEY_PATH=./certs/tactical.key

# ZeroTier Network
ZEROTIER_NETWORK_ID=your_network_id

# Security
MAX_CLIENTS=5
JWT_SECRET=your_jwt_secret
```

### Configuration Files

- [`location-config.json`](location-config.json) - Main service configuration
- [`ssl-config.json`](ssl-config.json) - SSL/TLS security settings  
- [`network-config.json`](network-config.json) - ZeroTier and network configuration

## API Reference

### WebSocket API

Connect to: `wss://192.168.100.1:8443/tactical-location`

#### Authentication
```javascript
{
  "type": "authentication",
  "data": {
    "userId": "user_123",
    "deviceId": "device_abc",
    "timestamp": 1640995200000
  }
}
```

#### Location Update
```javascript
{
  "type": "location_update", 
  "data": {
    "coordinates": {
      "latitude": 34.052235,
      "longitude": -118.243683,
      "accuracy": 10,
      "heading": 45,
      "speed": 5.5
    },
    "timestamp": 1640995200000,
    "batteryLevel": 0.85
  }
}
```

#### Emergency Alert
```javascript
{
  "type": "emergency_alert",
  "data": {
    "message": "Emergency assistance required",
    "location": {
      "latitude": 34.052235,
      "longitude": -118.243683
    },
    "timestamp": 1640995200000
  }
}
```

### REST API

Base URL: `https://192.168.100.1:3002/api`

#### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Service health check |
| POST | `/devices/register` | Register new device |
| GET | `/locations/current` | Get current team locations |
| GET | `/locations/history/:userId` | Get location history |
| POST | `/waypoints` | Create waypoint |
| GET | `/waypoints` | List waypoints |
| POST | `/alerts/emergency` | Create emergency alert |
| GET | `/team/status` | Get team status |

#### Example: Get Current Locations

```bash
curl -X GET https://192.168.100.1:3002/api/locations/current \
  -H "X-Device-ID: device_abc" \
  -H "X-User-ID: user_123"
```

Response:
```json
{
  "success": true,
  "locations": [
    {
      "user_id": "user_123",
      "latitude": 34.052235,
      "longitude": -118.243683,
      "accuracy": 10,
      "timestamp": "2024-01-01T12:00:00Z"
    }
  ],
  "count": 1
}
```

## Client Integration

### PWA Integration

```javascript
// Initialize location client
const locationClient = new TacticalLocationClient({
  serverUrl: 'wss://192.168.100.1:8443/tactical-location',
  apiUrl: 'https://192.168.100.1:3002/api',
  batteryOptimized: true,
  offlineStorage: true
});

// Connect and start tracking
await locationClient.connect();
locationClient.startTracking();

// Handle events
locationClient.on('connected', () => {
  console.log('Connected to tactical server');
});

locationClient.on('locationUpdate', (data) => {
  console.log('Location updated:', data);
});

locationClient.on('emergencyAlert', (alert) => {
  console.log('Emergency alert:', alert);
});
```

### Battery Optimization

The service automatically adjusts update intervals based on:

- **Battery Level**: Slower updates when battery < 50%
- **Movement Detection**: Reduced frequency when stationary
- **Background Mode**: Lower update rate when app is hidden
- **Emergency Mode**: Override optimizations for critical situations

## Security Features

### Encryption
- **Transport**: WSS (WebSocket Secure) with TLS 1.3
- **Application**: AES-256-GCM for location data
- **Key Rotation**: Automatic encryption key rotation

### Authentication
- **Device Fingerprinting**: Unique device identification
- **Manual Authorization**: Admin approval for new devices
- **Session Management**: Automatic timeout and cleanup

### Data Protection
- **Zero Persistence**: No permanent client data storage
- **Automatic Cleanup**: Location data deleted after 24 hours
- **Secure Deletion**: Cryptographic erasure of sensitive data

## Monitoring and Logging

### Health Checks

```bash
# Check service status
npm run health

# Or via API
curl https://192.168.100.1:3002/api/health
```

### Logs

- **Application**: `./logs/location-service.log`
- **Network**: `./logs/network.log`
- **Security**: `./logs/security.log`

### Metrics

- Active connections
- Location update frequency
- Battery levels
- Network latency
- Error rates

## Deployment

### Production Deployment

1. **Server Setup**
   ```bash
   # Install on Raspberry Pi 5
   curl -fsSL https://get.docker.com | sh
   sudo usermod -aG docker $USER
   ```

2. **SSL Certificates**
   ```bash
   # Generate self-signed certificates
   npm run setup:certs
   
   # Or use Let's Encrypt
   certbot certonly --standalone -d tactical.local
   ```

3. **Database Setup**
   ```bash
   # Initialize PostgreSQL
   npm run setup:db
   ```

4. **Start Services**
   ```bash
   # Production deployment
   docker-compose -f docker-compose.location.yml up -d
   ```

### ZeroTier Network Setup

1. **Create Network**
   ```bash
   # On tactical server
   zerotier-cli controller create-network
   ```

2. **Configure Network**
   ```bash
   # Set network settings
   zerotier-cli controller set-network <network-id> \
     name="TacticalOps" \
     subnet="192.168.100.0/24" \
     private=true
   ```

3. **Join Devices**
   ```bash
   # On each device
   zerotier-cli join <network-id>
   ```

## Troubleshooting

### Common Issues

**Connection Failed**
```bash
# Check WebSocket server
netstat -tlnp | grep 8443

# Check SSL certificates
openssl x509 -in ./certs/tactical.crt -text -noout
```

**Database Connection**
```bash
# Test PostgreSQL connection
psql -h localhost -U tactical -d tactical_location -c "SELECT NOW();"
```

**Location Not Updating**
```bash
# Check browser permissions
# Chrome: Settings > Privacy > Site Settings > Location
# Firefox: Preferences > Privacy & Security > Permissions > Location
```

### Debug Mode

```bash
# Enable verbose logging
NODE_ENV=development LOG_LEVEL=debug npm start
```

### Performance Tuning

```bash
# Optimize PostgreSQL
echo "shared_buffers = 256MB" >> /etc/postgresql/15/main/postgresql.conf
echo "effective_cache_size = 1GB" >> /etc/postgresql/15/main/postgresql.conf

# Optimize Redis
echo "maxmemory 512mb" >> /etc/redis/redis.conf
echo "maxmemory-policy allkeys-lru" >> /etc/redis/redis.conf
```

## Development

### Setup Development Environment

```bash
# Install dependencies
npm install

# Start in development mode
npm run dev

# Run tests
npm test

# Run with coverage
npm run test:coverage
```

### Testing

```bash
# Unit tests
npm test

# Integration tests
npm run test:integration

# Load testing
npm run test:load
```

### Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

- **Documentation**: [Wiki](https://github.com/tactical-ops/location-service/wiki)
- **Issues**: [GitHub Issues](https://github.com/tactical-ops/location-service/issues)
- **Security**: security@tactical-ops.local

---

**Tactical Location Service v1.0.0** - Built for tactical operations requiring secure, real-time location tracking with zero data persistence.