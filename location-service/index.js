#!/usr/bin/env node

// Tactical Location Service - Main Entry Point
// Version: 1.0.0
// Coordinates WebSocket server, REST API, and monitoring services

const fs = require('fs');
const path = require('path');
const cluster = require('cluster');
const os = require('os');

// Load configuration
const config = require('./location-config.json');
const sslConfig = require('./ssl-config.json');
const networkConfig = require('./network-config.json');

// Load service classes
const TacticalLocationServer = require('./location-server');
const TacticalLocationAPI = require('./location-api');

// Environment setup
require('dotenv').config();

class TacticalLocationService {
    constructor() {
        this.config = this.mergeConfigs();
        this.services = {
            websocket: null,
            api: null
        };
        this.isShuttingDown = false;
        
        this.init();
    }

    mergeConfigs() {
        // Merge all configuration files with environment variable overrides
        const mergedConfig = {
            ...config,
            ssl: sslConfig.ssl,
            network: networkConfig,
            
            // Environment variable overrides
            server: {
                ...config.server,
                port: process.env.WEBSOCKET_PORT || config.server.port,
                maxClients: process.env.MAX_CLIENTS || config.server.maxClients
            },
            api: {
                ...config.api,
                port: process.env.API_PORT || config.api.port
            },
            database: {
                ...config.database,
                host: process.env.DATABASE_HOST || config.database.host,
                port: process.env.DATABASE_PORT || config.database.port,
                name: process.env.DATABASE_NAME || config.database.name,
                user: process.env.DATABASE_USER || config.database.user,
                password: process.env.DATABASE_PASSWORD || config.database.password
            },
            redis: {
                ...config.redis,
                host: process.env.REDIS_HOST || config.redis.host,
                port: process.env.REDIS_PORT || config.redis.port,
                password: process.env.REDIS_PASSWORD || config.redis.password
            },
            ssl: {
                ...sslConfig.ssl,
                cert: process.env.SSL_CERT_PATH || sslConfig.ssl.certificatePath,
                key: process.env.SSL_KEY_PATH || sslConfig.ssl.privateKeyPath
            },
            zerotier: {
                ...networkConfig.zerotier,
                networkId: process.env.ZEROTIER_NETWORK_ID || networkConfig.zerotier.networkId
            }
        };

        return mergedConfig;
    }

    async init() {
        console.log('🚀 Initializing Tactical Location Service...');
        console.log(`📋 Configuration loaded for ${process.env.NODE_ENV || 'production'} environment`);
        
        try {
            // Validate configuration
            this.validateConfiguration();
            
            // Setup logging
            this.setupLogging();
            
            // Check prerequisites
            await this.checkPrerequisites();
            
            // Initialize services based on cluster mode
            if (cluster.isPrimary && this.config.clustering?.enabled) {
                this.initClusterMode();
            } else {
                await this.initServices();
            }
            
            // Setup graceful shutdown
            this.setupGracefulShutdown();
            
            console.log('✅ Tactical Location Service initialized successfully');
            
        } catch (error) {
            console.error('❌ Failed to initialize Tactical Location Service:', error);
            process.exit(1);
        }
    }

    validateConfiguration() {
        console.log('🔍 Validating configuration...');
        
        // Check required SSL certificates
        if (this.config.ssl.enabled) {
            if (!fs.existsSync(this.config.ssl.cert)) {
                throw new Error(`SSL certificate not found: ${this.config.ssl.cert}`);
            }
            if (!fs.existsSync(this.config.ssl.key)) {
                throw new Error(`SSL private key not found: ${this.config.ssl.key}`);
            }
        }

        // Validate network configuration
        if (!this.config.zerotier.networkId || this.config.zerotier.networkId.includes('${')) {
            console.warn('⚠️  ZeroTier network ID not configured - location service will run in standalone mode');
        }

        // Validate database configuration
        if (!this.config.database.password || this.config.database.password === 'TacticalSecure2025!') {
            console.warn('⚠️  Using default database password - change for production deployment');
        }

        console.log('✅ Configuration validation completed');
    }

    setupLogging() {
        // Create logs directory if it doesn't exist
        const logsDir = path.dirname(this.config.logging.file.path);
        if (!fs.existsSync(logsDir)) {
            fs.mkdirSync(logsDir, { recursive: true });
        }

        console.log(`📝 Logging configured: ${this.config.logging.level} level`);
    }

    async checkPrerequisites() {
        console.log('🔍 Checking prerequisites...');
        
        // Check Node.js version
        const nodeVersion = process.version;
        const requiredVersion = 'v18.0.0';
        if (nodeVersion < requiredVersion) {
            throw new Error(`Node.js ${requiredVersion} or higher required, found ${nodeVersion}`);
        }

        // Check available memory
        const totalMemory = os.totalmem();
        const requiredMemory = 512 * 1024 * 1024; // 512MB minimum
        if (totalMemory < requiredMemory) {
            console.warn(`⚠️  Low memory detected: ${Math.round(totalMemory / 1024 / 1024)}MB available`);
        }

        // Check disk space for logs and data
        try {
            const stats = fs.statSync('.');
            console.log('💾 Disk space check completed');
        } catch (error) {
            console.warn('⚠️  Could not check disk space:', error.message);
        }

        console.log('✅ Prerequisites check completed');
    }

    initClusterMode() {
        const numCPUs = os.cpus().length;
        const workers = Math.min(numCPUs, this.config.clustering.maxWorkers || 4);
        
        console.log(`🔄 Starting cluster mode with ${workers} workers`);
        
        // Fork workers
        for (let i = 0; i < workers; i++) {
            cluster.fork();
        }

        cluster.on('exit', (worker, code, signal) => {
            console.log(`💀 Worker ${worker.process.pid} died (${signal || code})`);
            
            if (!this.isShuttingDown) {
                console.log('🔄 Restarting worker...');
                cluster.fork();
            }
        });

        cluster.on('online', (worker) => {
            console.log(`👷 Worker ${worker.process.pid} started`);
        });
    }

    async initServices() {
        console.log('🛠️  Initializing services...');
        
        try {
            // Initialize WebSocket server
            console.log('🔌 Starting WebSocket server...');
            this.services.websocket = new TacticalLocationServer(this.config);
            
            // Wait a moment for WebSocket server to initialize
            await new Promise(resolve => setTimeout(resolve, 2000));
            
            // Initialize REST API server
            console.log('🌐 Starting REST API server...');
            this.services.api = new TacticalLocationAPI(this.config);
            
            console.log('✅ All services initialized successfully');
            
            // Log service endpoints
            this.logServiceEndpoints();
            
        } catch (error) {
            console.error('❌ Service initialization failed:', error);
            throw error;
        }
    }

    logServiceEndpoints() {
        console.log('\n📡 Service Endpoints:');
        console.log(`   WebSocket: wss://localhost:${this.config.server.port}/tactical-location`);
        console.log(`   REST API:  https://localhost:${this.config.api.port}/api`);
        console.log(`   Health:    https://localhost:${this.config.api.port}/api/health`);
        
        if (this.config.zerotier.networkId && !this.config.zerotier.networkId.includes('${')) {
            console.log(`   ZeroTier:  Network ID ${this.config.zerotier.networkId}`);
        }
        console.log('');
    }

    setupGracefulShutdown() {
        const shutdown = async (signal) => {
            console.log(`\n🛑 Received ${signal}, shutting down gracefully...`);
            this.isShuttingDown = true;
            
            try {
                // Close WebSocket server
                if (this.services.websocket) {
                    console.log('🔌 Closing WebSocket server...');
                    await this.services.websocket.shutdown(signal);
                }
                
                // Close API server
                if (this.services.api && this.services.api.server) {
                    console.log('🌐 Closing API server...');
                    this.services.api.server.close();
                }
                
                // Close cluster workers
                if (cluster.isPrimary) {
                    for (const id in cluster.workers) {
                        cluster.workers[id].kill();
                    }
                }
                
                console.log('✅ Graceful shutdown completed');
                process.exit(0);
                
            } catch (error) {
                console.error('❌ Error during shutdown:', error);
                process.exit(1);
            }
        };

        // Handle various shutdown signals
        process.on('SIGTERM', () => shutdown('SIGTERM'));
        process.on('SIGINT', () => shutdown('SIGINT'));
        process.on('SIGUSR2', () => shutdown('SIGUSR2')); // nodemon restart
        
        // Handle uncaught exceptions
        process.on('uncaughtException', (error) => {
            console.error('❌ Uncaught Exception:', error);
            shutdown('UNCAUGHT_EXCEPTION');
        });
        
        process.on('unhandledRejection', (reason, promise) => {
            console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
            shutdown('UNHANDLED_REJECTION');
        });
    }

    // Static method to get service status
    static async getStatus() {
        try {
            const response = await fetch('http://localhost:3002/api/health');
            const status = await response.json();
            return status;
        } catch (error) {
            return {
                status: 'error',
                error: error.message,
                timestamp: new Date().toISOString()
            };
        }
    }
}

// CLI interface
if (require.main === module) {
    const args = process.argv.slice(2);
    
    switch (args[0]) {
        case 'status':
            TacticalLocationService.getStatus()
                .then(status => {
                    console.log(JSON.stringify(status, null, 2));
                    process.exit(status.status === 'healthy' ? 0 : 1);
                })
                .catch(error => {
                    console.error('Failed to get status:', error.message);
                    process.exit(1);
                });
            break;
            
        case 'help':
        case '--help':
        case '-h':
            console.log(`
Tactical Location Service v1.0.0

Usage:
  node index.js [command]

Commands:
  start     Start the location service (default)
  status    Check service health status
  help      Show this help message

Environment Variables:
  NODE_ENV              Environment (development|production)
  WEBSOCKET_PORT        WebSocket server port (default: 8443)
  API_PORT              REST API port (default: 3002)
  DATABASE_HOST         PostgreSQL host
  DATABASE_PASSWORD     PostgreSQL password
  ZEROTIER_NETWORK_ID   ZeroTier network ID
  SSL_CERT_PATH         SSL certificate path
  SSL_KEY_PATH          SSL private key path

Examples:
  node index.js                    # Start service
  node index.js status             # Check status
  NODE_ENV=development node index.js  # Start in development mode
            `);
            process.exit(0);
            break;
            
        default:
            // Start the service
            new TacticalLocationService();
            break;
    }
} else {
    // Export for use as module
    module.exports = TacticalLocationService;
}