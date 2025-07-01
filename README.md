# Mobile Tactical Deployment Server

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/Version-1.0.0-blue.svg)](https://github.com/tactical-ops/tacop)
[![Platform](https://img.shields.io/badge/Platform-Raspberry%20Pi%205-red.svg)](https://www.raspberrypi.org/)

A complete tactical deployment server designed for rapid field operations using Raspberry Pi 5 hardware. Provides secure, self-contained networking infrastructure with integrated mapping, communications, file management, and collaborative report writing capabilities.

## 🚀 Quick Start (1-Liner Installation)

Deploy a complete tactical server in under 10 minutes:

```bash
curl -sSL https://raw.githubusercontent.com/tactical-ops/tacop/main/quick-install.sh | bash -s -- --zerotier-network YOUR_NETWORK_ID
```

## ✨ Features

### Core Capabilities
- **🔐 ZeroTier VPN Integration** - Self-hosted controller with encrypted team communications
- **📝 Collaborative Report Writing** - Real-time multi-user document editing with Outline
- **📍 Real-time GPS Tracking** - WebSocket-based location services with discrete PWA
- **🗺️ Tactical Mapping** - OpenMapTiles integration with offline capabilities
- **💬 Team Communications** - Mattermost for secure team messaging
- **📁 File Management** - Secure file sharing with FileBrowser
- **⚡ 10-Minute Deployment** - Automated installation from fresh hardware

### Security Features
- **🛡️ Hardware Encryption** - AES-256 encrypted storage with biometric access
- **🔥 Firewall Protection** - UFW with tactical-specific rules
- **🚫 Intrusion Detection** - Fail2Ban with custom filters
- **🔒 SSH Hardening** - Key-based authentication with security policies
- **📱 Discrete PWA** - Non-descriptive mobile interface for operational security

### Network Architecture
- **📡 Self-Hosted ZeroTier** - Complete network autonomy
- **🌐 MikroTik Integration** - RouterOS configuration for tactical access points
- **🔄 Load Balancing** - Nginx reverse proxy with SSL termination
- **📊 Performance Monitoring** - Real-time health checks and metrics

## 📋 Requirements

### Hardware
- **Raspberry Pi 5** (16GB RAM recommended)
- **1TB Encrypted SSD** (hardware encryption preferred)
- **MikroTik RBmAPL-2nD** access point (optional)
- **64GB+ SD Card** (Class 10 or better)

### Software
- **Raspberry Pi OS Lite** (64-bit)
- **Docker & Docker Compose** (installed automatically)
- **Internet connection** (for initial setup only)

## 🛠️ Installation

### Method 1: Quick Installation (Recommended)

```bash
# Basic installation
curl -sSL https://raw.githubusercontent.com/tactical-ops/tacop/main/quick-install.sh | bash

# With ZeroTier network
curl -sSL https://raw.githubusercontent.com/tactical-ops/tacop/main/quick-install.sh | bash -s -- --zerotier-network YOUR_NETWORK_ID

# With custom domain
curl -sSL https://raw.githubusercontent.com/tactical-ops/tacop/main/quick-install.sh | bash -s -- --domain tactical.local --admin-email admin@tactical.local
```

### Method 2: Manual Installation

```bash
# Clone repository
git clone https://github.com/tactical-ops/tacop.git
cd tacop

# Run installation script
sudo ./deployment/install-tactical-server.sh --zerotier-network YOUR_NETWORK_ID
```

### Method 3: Development Setup

```bash
# Clone repository
git clone https://github.com/tactical-ops/tacop.git
cd tacop

# Install dependencies
npm install

# Start development environment
docker-compose -f deployment/docker-compose.yml up -d
```

## 🌐 Service Endpoints

After installation, access services at:

| Service | URL | Description |
|---------|-----|-------------|
| **Main Interface** | `https://tactical.local` | Primary tactical interface |
| **Location Service** | `wss://tactical.local:8443` | Real-time GPS tracking |
| **Maps Service** | `https://tactical.local:8080` | Tactical mapping interface |
| **Team Communications** | `https://tactical.local:3000` | Mattermost messaging |
| **Knowledge Base** | `https://tactical.local:3001` | Outline collaborative docs |
| **File Management** | `https://tactical.local:8081` | FileBrowser interface |

## 📱 Mobile Device Setup

### 1. Install ZeroTier
```bash
# Android/iOS: Install ZeroTier app from app store
# Join network with ID provided during installation
```

### 2. Install Tactical PWA
1. Navigate to `https://tactical.local` on mobile device
2. Add to home screen when prompted
3. App appears as "System Utility" for discretion

### 3. Authentication Sequence
- Tap status items in order: **Status → Network → Battery → Storage**
- Alternative: Triple-tap title for emergency access
- Konami code support for advanced users

## 🔧 Configuration

### Environment Variables
```bash
# Core Configuration
ZEROTIER_NETWORK_ID=your_network_id
DOMAIN_NAME=tactical.local
ADMIN_EMAIL=admin@tactical.local

# Database Configuration
POSTGRES_PASSWORD=auto_generated
REDIS_PASSWORD=auto_generated

# Security Configuration
JWT_SECRET=auto_generated
SSL_CERT_PATH=/mnt/secure_storage/ssl/tactical.crt
SSL_KEY_PATH=/mnt/secure_storage/ssl/tactical.key
```

### Service Configuration
```bash
# Location Service
WEBSOCKET_PORT=8443
API_PORT=3002
UPDATE_INTERVAL=30000

# Maps Service
MAPS_PORT=8080
OPENMAPTILES_URL=http://openmaptiles

# Team Limits
MAX_TEAM_MEMBERS=5
MAX_CONCURRENT_USERS=5
```

## 🗺️ MikroTik Configuration

Configure MikroTik access point for tactical networking:

```bash
# Deploy tactical configuration
./scripts/mikrotik-setup.sh deploy --ip 192.168.88.1 --password admin

# Backup current configuration
./scripts/mikrotik-setup.sh backup

# Reset to defaults
./scripts/mikrotik-setup.sh reset
```

## 📊 Monitoring & Maintenance

### Health Checks
```bash
# Check all services
./deployment/health-check.sh

# Check specific service
curl https://tactical.local:3002/api/health
```

### Backup & Recovery
```bash
# Create backup
./deployment/backup-data.sh

# Restore from backup
./deployment/restore-backup.sh backup_file.tar.gz

# Automated daily backups (configured automatically)
```

### Log Monitoring
```bash
# View service logs
docker-compose -f deployment/docker-compose.yml logs -f

# View installation logs
tail -f /var/log/tactical-server-install.log

# View health check logs
tail -f /var/log/tactical-health.log
```

## 🔒 Security Considerations

### Operational Security
- PWA appears as generic "System Utility"
- Discrete authentication sequences
- No tactical branding in mobile interface
- Automatic session timeouts

### Network Security
- All communications encrypted via ZeroTier
- SSL/TLS for all web services
- Firewall rules for tactical ports only
- Intrusion detection and prevention

### Data Security
- Hardware-encrypted storage
- No client-side data persistence
- Secure credential generation
- Regular security updates

## 🚨 Emergency Procedures

### Emergency Access
- Triple-tap PWA title for emergency access
- Emergency code: `TACTICAL_OVERRIDE_2025`
- Direct SSH access via tactical user

### Service Recovery
```bash
# Restart all services
sudo systemctl restart tactical-server

# Emergency service restart
docker-compose -f deployment/docker-compose.yml restart

# Factory reset (preserves data)
./deployment/install-tactical-server.sh --reset
```

## 📚 Documentation

- **[Installation Guide](INSTALL.md)** - Detailed setup instructions
- **[API Documentation](docs/API.md)** - Service API references
- **[Security Guide](docs/SECURITY.md)** - Security best practices
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[Development Guide](docs/DEVELOPMENT.md)** - Development setup and contribution

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/tactical-ops/tacop/issues)
- **Discussions**: [GitHub Discussions](https://github.com/tactical-ops/tacop/discussions)
- **Security**: Report security issues to security@tactical-ops.dev

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Mobile PWA    │    │  MikroTik AP    │    │ Raspberry Pi 5  │
│                 │    │                 │    │                 │
│ • Discrete UI   │◄──►│ • TacticalNet   │◄──►│ • ZeroTier      │
│ • GPS Tracking  │    │ • 192.168.100.x │    │ • Docker Stack  │
│ • Offline Maps  │    │ • QoS/Security  │    │ • Encrypted SSD │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │  ZeroTier VPN   │
                    │                 │
                    │ • End-to-End    │
                    │   Encryption    │
                    │ • Self-Hosted   │
                    │ • Team Network  │
                    └─────────────────┘
```

## 🎯 Roadmap

- [ ] **v1.1**: Enhanced biometric integration
- [ ] **v1.2**: Multi-node clustering support
- [ ] **v1.3**: AI-powered threat detection
- [ ] **v1.4**: Satellite communication integration
- [ ] **v2.0**: Quantum-safe cryptography

---

**⚡ Deploy in 10 minutes. Secure by design. Tactical by nature.**

Made with ❤️ for tactical operations worldwide.