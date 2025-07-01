# Mobile Tactical Deployment Server

Complete automated installation and deployment system for the Mobile Tactical Deployment Server, designed for 10-minute deployment on Raspberry Pi 5.

## Overview

This deployment system provides a complete tactical server stack with:

- **Location Tracking Service** - Real-time GPS tracking with WebSocket support
- **Maps Service** - Offline maps with OpenMapTiles integration
- **Team Communications** - Mattermost chat platform
- **Knowledge Base** - Outline wiki for tactical documentation
- **File Sharing** - FileBrowser for secure file management
- **Network Security** - ZeroTier VPN with firewall protection

## System Requirements

### Hardware
- **Raspberry Pi 5** (8GB RAM recommended)
- **64GB+ microSD card** (Class 10 or better)
- **Ethernet connection** (for initial setup)
- **Power supply** (official Raspberry Pi 5 power adapter)

### Software
- **Raspberry Pi OS** (64-bit, latest version)
- **Internet connection** (for installation only)

## Quick Start

### 1. Prepare Raspberry Pi 5

```bash
# Flash Raspberry Pi OS to microSD card
# Enable SSH and configure WiFi if needed
# Boot and update system
sudo apt update && sudo apt upgrade -y
```

### 2. Download Deployment System

```bash
# Clone or download the tactical server deployment
git clone <repository-url>
cd TacOp/deployment

# Make scripts executable
chmod +x *.sh
```

### 3. Run Installation

```bash
# Run the master installation script
sudo ./install-tactical-server.sh \
  --zerotier-network YOUR_NETWORK_ID \
  --admin-email admin@tactical.local \
  --domain tactical.local
```

### 4. Access Services

After installation (target: 10 minutes), access services at:

- **Main Interface**: https://tactical.local
- **Team Chat**: https://chat.tactical.local
- **Knowledge Base**: https://docs.tactical.local
- **File Browser**: https://files.tactical.local
- **Maps Service**: https://maps.tactical.local

## Installation Options

### Command Line Arguments

```bash
sudo ./install-tactical-server.sh [OPTIONS]

Options:
  --zerotier-network ID    ZeroTier network ID to join
  --admin-email EMAIL      Administrator email address
  --domain DOMAIN          Domain name (default: tactical.local)
  --help                   Show help message
```

### Interactive Installation

Run without arguments for interactive setup:

```bash
sudo ./install-tactical-server.sh
```

## Architecture

### Service Stack

| Service | RAM | Storage | Port | Description |
|---------|-----|---------|------|-------------|
| PostgreSQL | 1GB | 50GB | 5432 | Main database with PostGIS |
| Redis | 2GB | - | 6379 | Cache and session storage |
| ZeroTier | 1GB | 100MB | 9993 | VPN controller |
| Location Service | 512MB | - | 8443/3002 | GPS tracking WebSocket/API |
| Maps Service | 1GB | - | 8080 | Tactical maps management |
| OpenMapTiles | 6GB | 500GB | 8082 | Vector tile server |
| Outline | 2GB | 100GB | 3001 | Knowledge base |
| Mattermost | 1GB | 50GB | 3000 | Team communications |
| FileBrowser | 512MB | 10GB | 8081 | File management |
| Nginx | 512MB | - | 80/443 | Reverse proxy |

**Total**: 15GB RAM, 932GB Storage

### Network Configuration

- **ZeroTier VPN**: 192.168.100.0/24 subnet
- **SSL/TLS**: Automatic certificate generation
- **Firewall**: UFW with tactical-specific rules
- **Security**: Fail2Ban, SSH hardening, security headers

## Configuration Files

### Environment Variables
- `.env.production` - Production environment configuration
- `tactical-config.json` - Master server configuration
- `network-config.json` - Network and ZeroTier settings
- `security-config.json` - Security hardening configuration

### Service Configurations
- `docker-compose.yml` - Complete service orchestration
- `nginx/` - Reverse proxy and SSL configuration
- `redis/redis.conf` - Redis optimization for Raspberry Pi 5
- `filebrowser/filebrowser.json` - File browser settings

### Database Setup
- `init-databases.sql` - Database initialization
- `setup-users.sql` - User permissions setup
- Integration with existing location and maps schemas

## Management Scripts

### Health Monitoring
```bash
# Run health check
./health-check.sh

# Continuous monitoring
./monitor-services.sh start

# Check monitoring status
./monitor-services.sh status
```

### Backup and Recovery
```bash
# Create backup
./backup-data.sh

# Backup with custom retention
./backup-data.sh --retention-days 14 --backup-email admin@tactical.local
```

### Service Management
```bash
# Check service status
docker compose ps

# View service logs
docker compose logs [service-name]

# Restart specific service
docker compose restart [service-name]

# Stop all services
docker compose down

# Start all services
docker compose up -d
```

## Security Features

### Network Security
- **UFW Firewall** with tactical-specific rules
- **Fail2Ban** protection against brute force attacks
- **SSH Hardening** with key-based authentication only
- **ZeroTier VPN** for secure remote access

### Application Security
- **SSL/TLS** encryption for all web services
- **Security Headers** (HSTS, CSP, X-Frame-Options)
- **Rate Limiting** on all API endpoints
- **JWT Authentication** for API access

### Data Protection
- **Database Isolation** with separate users and permissions
- **Automatic Backups** with integrity verification
- **Log Rotation** and secure log management
- **Session Management** with automatic timeouts

## Troubleshooting

### Installation Issues

**Problem**: Installation fails during Docker setup
```bash
# Check Docker installation
docker --version
systemctl status docker

# Restart Docker service
sudo systemctl restart docker
```

**Problem**: Services fail to start
```bash
# Check service logs
docker compose logs [service-name]

# Check system resources
free -h
df -h
```

### Network Issues

**Problem**: Cannot access web interface
```bash
# Check Nginx status
docker compose logs nginx

# Verify SSL certificates
openssl x509 -in /mnt/secure_storage/ssl/tactical.crt -text -noout
```

**Problem**: ZeroTier connection issues
```bash
# Check ZeroTier status
zerotier-cli info
zerotier-cli listnetworks

# Restart ZeroTier
sudo systemctl restart zerotier-one
```

### Performance Issues

**Problem**: High memory usage
```bash
# Check memory usage by service
docker stats

# Restart memory-intensive services
docker compose restart openmaptiles
```

**Problem**: Slow response times
```bash
# Check system load
htop
iostat -x 1

# Review Nginx access logs
tail -f /mnt/secure_storage/logs/nginx/access.log
```

## Maintenance

### Regular Tasks

**Daily**
- Monitor service health via automated checks
- Review security logs for anomalies
- Verify backup completion

**Weekly**
- Update system packages (automatic)
- Review disk space usage
- Check ZeroTier network status

**Monthly**
- Review and rotate SSL certificates if needed
- Audit user access and permissions
- Performance optimization review

### Updates

**System Updates**
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Update Docker images
docker compose pull
docker compose up -d
```

**Configuration Updates**
```bash
# Apply configuration changes
docker compose down
docker compose up -d
```

## Integration with Existing Components

### PWA Integration
- Static files served by Nginx
- Service worker for offline functionality
- WebSocket connections for real-time updates

### Location Service Integration
- Existing schemas automatically imported
- WebSocket endpoints proxied through Nginx
- Redis integration for session management

### Maps Service Integration
- OpenMapTiles server for vector tiles
- Tactical overlays and waypoint support
- Offline map download capabilities

## Performance Optimization

### Raspberry Pi 5 Specific
- ARM64 optimized Docker images
- Memory allocation tuned for 8GB RAM
- Storage optimization for microSD cards
- CPU governor settings for performance

### Service Optimization
- Redis configured for tactical workloads
- PostgreSQL tuned for spatial queries
- Nginx optimized for static file serving
- Docker resource limits enforced

## Support and Documentation

### Log Files
- Installation: `/var/log/tactical-server-install.log`
- Health Checks: `/var/log/tactical-health.log`
- Monitoring: `/var/log/tactical-monitor.log`
- Backups: `/var/log/tactical-backup.log`
- Service Logs: `/mnt/secure_storage/logs/`

### Configuration Locations
- Deployment: `/opt/tactical-server/`
- Data Storage: `/mnt/secure_storage/`
- SSL Certificates: `/mnt/secure_storage/ssl/`
- Backups: `/mnt/secure_storage/backups/`

### Service URLs
- Main Interface: `https://tactical.local`
- Location WebSocket: `wss://tactical.local/tactical-location`
- Location API: `https://tactical.local/api/location`
- Maps API: `https://tactical.local/api/maps`
- Map Tiles: `https://tactical.local/tiles`

## License

This deployment system is part of the Mobile Tactical Deployment Server project. See individual service licenses for specific terms.

## Contributing

For issues, improvements, or contributions to the deployment system, please follow the project's contribution guidelines.

---

**Target Deployment Time**: 10 minutes from fresh Raspberry Pi 5
**System Capacity**: 5 team members, 932GB storage, 15GB RAM allocation
**Network**: ZeroTier VPN with 192.168.100.0/24 subnet