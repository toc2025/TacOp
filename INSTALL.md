# Mobile Tactical Deployment Server - Installation Guide

This comprehensive guide covers all installation methods and configuration options for the Mobile Tactical Deployment Server.

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Installation](#quick-installation)
- [Manual Installation](#manual-installation)
- [Development Setup](#development-setup)
- [Configuration](#configuration)
- [Post-Installation](#post-installation)
- [Troubleshooting](#troubleshooting)

## 🔧 Prerequisites

### Hardware Requirements

#### Minimum Requirements
- **Raspberry Pi 4** (4GB RAM)
- **32GB SD Card** (Class 10)
- **Internet connection** (for initial setup)

#### Recommended Configuration
- **Raspberry Pi 5** (16GB RAM)
- **64GB+ SD Card** (Class 10 or better)
- **1TB Encrypted SSD** (hardware encryption)
- **MikroTik RBmAPL-2nD** access point
- **Uninterruptible Power Supply (UPS)**

### Software Requirements

#### Operating System
- **Raspberry Pi OS Lite** (64-bit) - Latest version
- **Ubuntu Server 22.04 LTS** (ARM64) - Alternative

#### Network Requirements
- **Internet access** during installation
- **Static IP capability** (recommended)
- **Port availability**: 22, 80, 443, 3000-3002, 8080-8081, 8443, 9993

## 🚀 Quick Installation

### Method 1: One-Liner Installation (Recommended)

```bash
# Basic installation
curl -sSL https://raw.githubusercontent.com/tactical-ops/tacop/main/quick-install.sh | sudo bash

# With ZeroTier network
curl -sSL https://raw.githubusercontent.com/tactical-ops/tacop/main/quick-install.sh | sudo bash -s -- --zerotier-network YOUR_NETWORK_ID

# Full configuration
curl -sSL https://raw.githubusercontent.com/tactical-ops/tacop/main/quick-install.sh | sudo bash -s -- \
  --zerotier-network YOUR_NETWORK_ID \
  --admin-email admin@tactical.local \
  --domain tactical.local
```

### Method 2: Download and Execute

```bash
# Download script
wget https://raw.githubusercontent.com/tactical-ops/tacop/main/quick-install.sh

# Make executable
chmod +x quick-install.sh

# Execute with options
sudo ./quick-install.sh --zerotier-network YOUR_NETWORK_ID
```

### Quick Installation Options

| Option | Description | Example |
|--------|-------------|---------|
| `--zerotier-network ID` | ZeroTier network to join | `--zerotier-network 1234567890abcdef` |
| `--admin-email EMAIL` | Administrator email | `--admin-email admin@tactical.ops` |
| `--domain DOMAIN` | Custom domain name | `--domain my-tactical.local` |
| `--skip-hardware-check` | Skip Raspberry Pi validation | `--skip-hardware-check` |
| `--development` | Development mode | `--development` |

## 🛠️ Manual Installation

### Step 1: System Preparation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Git
sudo apt install -y git curl wget

# Create tactical user
sudo useradd -m -s /bin/bash tactical
sudo usermod -aG sudo tactical
```

### Step 2: Clone Repository

```bash
# Clone to installation directory
sudo git clone https://github.com/tactical-ops/tacop.git /opt/tactical-server

# Set permissions
sudo chown -R tactical:tactical /opt/tactical-server
sudo chmod +x /opt/tactical-server/deployment/install-tactical-server.sh
```

### Step 3: Configure Installation

```bash
# Navigate to deployment directory
cd /opt/tactical-server/deployment

# Copy environment template
sudo cp .env.production.template .env.production

# Edit configuration (optional)
sudo nano .env.production
```

### Step 4: Execute Installation

```bash
# Run installation script
sudo ./install-tactical-server.sh \
  --zerotier-network YOUR_NETWORK_ID \
  --admin-email admin@tactical.local \
  --domain tactical.local
```

### Manual Installation Options

| Option | Description | Default |
|--------|-------------|---------|
| `--zerotier-network ID` | ZeroTier network ID | None |
| `--admin-email EMAIL` | Administrator email | Prompted |
| `--domain DOMAIN` | Domain name | `tactical.local` |
| `--help` | Show help message | - |

## 💻 Development Setup

### Prerequisites for Development

```bash
# Install Node.js and npm
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo pip3 install docker-compose
```

### Development Installation

```bash
# Clone repository
git clone https://github.com/tactical-ops/tacop.git
cd tacop

# Install dependencies
npm install

# Copy development environment
cp deployment/.env.development.template deployment/.env.development

# Edit development configuration
nano deployment/.env.development

# Start development environment
docker-compose -f deployment/docker-compose.yml -f deployment/docker-compose.dev.yml up -d
```

### Development Commands

```bash
# Start services
npm run dev:start

# Stop services
npm run dev:stop

# View logs
npm run dev:logs

# Rebuild services
npm run dev:rebuild

# Run tests
npm test

# Lint code
npm run lint
```

## ⚙️ Configuration

### Environment Variables

#### Core Configuration
```bash
# Network Configuration
ZEROTIER_NETWORK_ID=your_network_id
DOMAIN_NAME=tactical.local
SERVER_IP=192.168.100.1

# Database Configuration
POSTGRES_PASSWORD=auto_generated_secure_password
LOCATION_DB_PASSWORD=auto_generated_secure_password
MAPS_DB_PASSWORD=auto_generated_secure_password
OUTLINE_DB_PASSWORD=auto_generated_secure_password
MATTERMOST_DB_PASSWORD=auto_generated_secure_password

# Redis Configuration
REDIS_PASSWORD=auto_generated_secure_password

# Security Configuration
JWT_SECRET=auto_generated_jwt_secret
OUTLINE_SECRET_KEY=auto_generated_outline_secret
MATTERMOST_SECRET=auto_generated_mattermost_secret

# SSL Configuration
SSL_CERT_PATH=/mnt/secure_storage/ssl/tactical.crt
SSL_KEY_PATH=/mnt/secure_storage/ssl/tactical.key

# Storage Configuration
DATA_PATH=/mnt/secure_storage/data
MAPS_PATH=/mnt/secure_storage/maps
LOGS_PATH=/mnt/secure_storage/logs

# Service Configuration
NODE_ENV=production
LOG_LEVEL=info

# Admin Configuration
ADMIN_EMAIL=admin@tactical.local
```

#### Service-Specific Configuration

**Location Service**
```bash
WEBSOCKET_PORT=8443
API_PORT=3002
MAX_CLIENTS=5
UPDATE_INTERVAL_MS=30000
```

**Maps Service**
```bash
MAPS_PORT=8080
OPENMAPTILES_URL=http://openmaptiles
TILE_CACHE_GB=2
MAX_ZOOM=18
```

**Team Configuration**
```bash
MAX_TEAM_MEMBERS=5
DEFAULT_ROLES=commander,team_leader,operator,support
EMERGENCY_MODE_ENABLED=true
```

### Service Configuration Files

#### Location Service Configuration
```json
{
  "server": {
    "port": 8443,
    "maxClients": 5,
    "ssl": {
      "enabled": true,
      "certificatePath": "/certs/tactical.crt",
      "privateKeyPath": "/certs/tactical.key"
    }
  },
  "database": {
    "host": "postgresql",
    "port": 5432,
    "name": "tactical_location",
    "user": "tactical",
    "password": "${DATABASE_PASSWORD}"
  },
  "redis": {
    "host": "redis",
    "port": 6379,
    "password": "${REDIS_PASSWORD}"
  },
  "tracking": {
    "updateInterval": 30000,
    "highAccuracy": true,
    "batteryOptimized": true
  }
}
```

#### Maps Service Configuration
```json
{
  "server": {
    "port": 8080,
    "host": "0.0.0.0"
  },
  "database": {
    "host": "postgresql",
    "port": 5432,
    "database": "tactical_maps",
    "user": "maps_user",
    "password": "${MAPS_DB_PASSWORD}"
  },
  "tiles": {
    "maxZoom": 18,
    "cacheSize": "2GB",
    "format": "mvt"
  },
  "storage": {
    "mapsPath": "/mnt/secure_storage/maps",
    "tilesPath": "/mnt/secure_storage/maps/tiles",
    "dataPath": "/mnt/secure_storage/maps/data"
  }
}
```

### Security Configuration

#### Firewall Rules
```bash
# SSH access
ufw allow 22/tcp

# Web services
ufw allow 80/tcp
ufw allow 443/tcp

# Tactical services
ufw allow 3000/tcp  # Mattermost
ufw allow 3001/tcp  # Outline
ufw allow 3002/tcp  # Location API
ufw allow 8080/tcp  # Maps service
ufw allow 8081/tcp  # FileBrowser
ufw allow 8443/tcp  # Location WebSocket

# ZeroTier
ufw allow 9993/udp
```

#### SSL/TLS Configuration
```nginx
# SSL protocols and ciphers
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS;
ssl_prefer_server_ciphers on;

# Security headers
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header X-Frame-Options DENY always;
add_header X-Content-Type-Options nosniff always;
add_header X-XSS-Protection "1; mode=block" always;
```

## 📱 Post-Installation

### Mobile Device Setup

#### 1. Install ZeroTier
- **Android**: Install from Google Play Store
- **iOS**: Install from App Store
- **Join Network**: Use network ID from installation

#### 2. Install Tactical PWA
1. Navigate to `https://tactical.local` on mobile device
2. Tap browser menu → "Add to Home Screen"
3. App appears as "System Utility" for discretion

#### 3. Authentication
- **Primary**: Tap status items in sequence: Status → Network → Battery → Storage
- **Emergency**: Triple-tap title, enter code: `TACTICAL_OVERRIDE_2025`
- **Advanced**: Konami code support

### MikroTik Configuration

#### Automatic Configuration
```bash
# Deploy tactical configuration
./scripts/mikrotik-setup.sh deploy --ip 192.168.88.1 --password admin

# Verify configuration
./scripts/mikrotik-setup.sh verify
```

#### Manual Configuration
1. Connect to MikroTik via Winbox or SSH
2. Import configuration: `/import tactical-config.rsc`
3. Verify wireless network: SSID "TacticalNet"

### Service Verification

#### Health Checks
```bash
# Check all services
./deployment/health-check.sh

# Check specific services
curl -k https://tactical.local/health
curl -k https://tactical.local:3002/api/health
curl -k https://tactical.local:8080/health
```

#### Service Status
```bash
# Docker services
docker-compose -f deployment/docker-compose.yml ps

# System services
systemctl status tactical-server

# ZeroTier status
zerotier-cli info
zerotier-cli listnetworks
```

### Initial Configuration

#### 1. Outline Setup
1. Navigate to `https://tactical.local:3001`
2. Create admin account
3. Set up team workspace
4. Configure document templates

#### 2. Mattermost Setup
1. Navigate to `https://tactical.local:3000`
2. Create admin account
3. Set up team channels
4. Configure notifications

#### 3. Maps Setup
1. Upload map tiles to `/mnt/secure_storage/maps/tiles/`
2. Configure regions in maps service
3. Test map rendering

## 🔧 Troubleshooting

### Common Issues

#### Installation Fails
```bash
# Check logs
tail -f /var/log/tactical-server-install.log

# Check system resources
free -h
df -h

# Check network connectivity
ping 8.8.8.8
```

#### Services Won't Start
```bash
# Check Docker status
systemctl status docker

# Check service logs
docker-compose -f deployment/docker-compose.yml logs

# Restart services
docker-compose -f deployment/docker-compose.yml restart
```

#### ZeroTier Issues
```bash
# Check ZeroTier status
zerotier-cli info

# Check network membership
zerotier-cli listnetworks

# Restart ZeroTier
systemctl restart zerotier-one
```

#### SSL Certificate Issues
```bash
# Regenerate certificates
./deployment/generate-ssl-certificates.sh

# Check certificate validity
openssl x509 -in /mnt/secure_storage/ssl/tactical.crt -text -noout
```

### Performance Optimization

#### Memory Optimization
```bash
# Increase swap space
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

#### Storage Optimization
```bash
# Clean Docker images
docker system prune -a

# Clean logs
sudo journalctl --vacuum-time=7d

# Optimize database
docker-compose exec postgresql vacuumdb -U postgres -d tactical_location
```

### Recovery Procedures

#### Service Recovery
```bash
# Stop all services
docker-compose -f deployment/docker-compose.yml down

# Remove containers and volumes
docker-compose -f deployment/docker-compose.yml down -v

# Restart installation
sudo ./deployment/install-tactical-server.sh --reset
```

#### Data Recovery
```bash
# Restore from backup
./deployment/restore-backup.sh backup_file.tar.gz

# Manual database restore
docker-compose exec -T postgresql psql -U postgres -d tactical_location < backup.sql
```

## 📞 Support

### Getting Help
- **Documentation**: [GitHub Wiki](https://github.com/tactical-ops/tacop/wiki)
- **Issues**: [GitHub Issues](https://github.com/tactical-ops/tacop/issues)
- **Discussions**: [GitHub Discussions](https://github.com/tactical-ops/tacop/discussions)

### Reporting Issues
When reporting issues, include:
- Installation method used
- Hardware specifications
- Operating system version
- Error messages and logs
- Steps to reproduce

### Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and contribution guidelines.

---

**Need immediate assistance? Check the [troubleshooting section](#troubleshooting) or create an issue on GitHub.**