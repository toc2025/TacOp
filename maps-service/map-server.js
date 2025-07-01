const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const { Pool } = require('pg');
const Redis = require('redis');
const winston = require('winston');
const path = require('path');
const fs = require('fs').promises;
require('dotenv').config();

const MapManager = require('./map-manager');
const TacticalMaps = require('./tactical-maps');
const config = require('./map-config.json');

class MapServer {
    constructor() {
        this.app = express();
        this.server = null;
        this.db = null;
        this.redis = null;
        this.mapManager = null;
        this.tacticalMaps = null;
        this.logger = this.setupLogger();
        
        this.setupDatabase();
        this.setupRedis();
        this.setupMiddleware();
        this.setupRoutes();
        this.setupErrorHandling();
    }

    setupLogger() {
        return winston.createLogger({
            level: config.logging.level,
            format: winston.format.combine(
                winston.format.timestamp(),
                winston.format.errors({ stack: true }),
                winston.format.json()
            ),
            transports: [
                new winston.transports.Console({
                    format: winston.format.combine(
                        winston.format.colorize(),
                        winston.format.simple()
                    )
                }),
                new winston.transports.File({
                    filename: config.logging.file,
                    maxsize: config.logging.maxSize,
                    maxFiles: config.logging.maxFiles
                })
            ]
        });
    }

    async setupDatabase() {
        try {
            this.db = new Pool({
                host: config.database.host,
                port: config.database.port,
                database: config.database.database,
                user: config.database.user,
                password: process.env.MAPS_DB_PASSWORD || config.database.password,
                ssl: config.database.ssl,
                ...config.database.pool
            });

            // Test connection
            const client = await this.db.connect();
            await client.query('SELECT NOW()');
            client.release();
            
            this.logger.info('Database connection established');
        } catch (error) {
            this.logger.error('Database connection failed:', error);
            throw error;
        }
    }

    async setupRedis() {
        try {
            this.redis = Redis.createClient({
                host: config.redis.host,
                port: config.redis.port,
                password: process.env.REDIS_PASSWORD || config.redis.password,
                db: config.redis.db,
                keyPrefix: config.redis.keyPrefix
            });

            await this.redis.connect();
            this.logger.info('Redis connection established');
        } catch (error) {
            this.logger.error('Redis connection failed:', error);
            throw error;
        }
    }

    setupMiddleware() {
        // Security middleware
        this.app.use(helmet({
            contentSecurityPolicy: {
                directives: {
                    defaultSrc: ["'self'"],
                    styleSrc: ["'self'", "'unsafe-inline'"],
                    scriptSrc: ["'self'"],
                    imgSrc: ["'self'", "data:", "blob:"],
                    connectSrc: ["'self'", "ws:", "wss:"]
                }
            }
        }));

        // CORS configuration
        this.app.use(cors({
            origin: config.security.cors.origin,
            credentials: config.security.cors.credentials,
            methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
            allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With']
        }));

        // Compression
        this.app.use(compression({
            level: config.performance.compression.level,
            threshold: config.performance.compression.threshold
        }));

        // Body parsing
        this.app.use(express.json({ limit: '10mb' }));
        this.app.use(express.urlencoded({ extended: true, limit: '10mb' }));

        // Request logging
        this.app.use((req, res, next) => {
            this.logger.info(`${req.method} ${req.path}`, {
                ip: req.ip,
                userAgent: req.get('User-Agent'),
                timestamp: new Date().toISOString()
            });
            next();
        });

        // Rate limiting middleware
        this.app.use(this.rateLimitMiddleware());
    }

    rateLimitMiddleware() {
        const requests = new Map();
        
        return (req, res, next) => {
            const key = req.ip;
            const now = Date.now();
            const windowMs = config.security.rateLimiting.windowMs;
            const max = config.security.rateLimiting.max;

            if (!requests.has(key)) {
                requests.set(key, { count: 1, resetTime: now + windowMs });
                return next();
            }

            const record = requests.get(key);
            
            if (now > record.resetTime) {
                record.count = 1;
                record.resetTime = now + windowMs;
                return next();
            }

            if (record.count >= max) {
                return res.status(429).json({
                    error: 'Too many requests',
                    retryAfter: Math.ceil((record.resetTime - now) / 1000)
                });
            }

            record.count++;
            next();
        };
    }

    setupRoutes() {
        // Initialize map components
        this.mapManager = new MapManager(this.db, this.redis, this.logger, config);
        this.tacticalMaps = new TacticalMaps(this.db, this.redis, this.logger, config);

        // Health check
        this.app.get('/health', (req, res) => {
            res.json({
                status: 'healthy',
                timestamp: new Date().toISOString(),
                version: config.server.version,
                uptime: process.uptime()
            });
        });

        // Map tiles endpoint
        this.app.get('/tiles/:z/:x/:y.mvt', async (req, res) => {
            try {
                const { z, x, y } = req.params;
                const tile = await this.mapManager.getTile(parseInt(z), parseInt(x), parseInt(y));
                
                if (!tile) {
                    return res.status(404).json({ error: 'Tile not found' });
                }

                res.set({
                    'Content-Type': 'application/x-protobuf',
                    'Content-Encoding': 'gzip',
                    'Cache-Control': `max-age=${config.tiles.cacheHeaders.maxAge}`,
                    'Access-Control-Allow-Origin': '*'
                });

                res.send(tile);
            } catch (error) {
                this.logger.error('Error serving tile:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        // Map style endpoint
        this.app.get('/style/:styleName', async (req, res) => {
            try {
                const { styleName } = req.params;
                const style = await this.mapManager.getStyle(styleName);
                
                if (!style) {
                    return res.status(404).json({ error: 'Style not found' });
                }

                res.json(style);
            } catch (error) {
                this.logger.error('Error serving style:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        // Regions API
        this.app.get('/api/regions', async (req, res) => {
            try {
                const regions = await this.mapManager.getRegions();
                res.json(regions);
            } catch (error) {
                this.logger.error('Error fetching regions:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        this.app.post('/api/regions/:regionId/download', async (req, res) => {
            try {
                const { regionId } = req.params;
                const { userId, deviceId } = req.body;
                
                const downloadId = await this.mapManager.initiateRegionDownload(regionId, userId, deviceId);
                res.json({ downloadId, status: 'initiated' });
            } catch (error) {
                this.logger.error('Error initiating download:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        // Waypoints API
        this.app.get('/api/waypoints', async (req, res) => {
            try {
                const { teamId, missionId, bounds } = req.query;
                const waypoints = await this.tacticalMaps.getWaypoints({ teamId, missionId, bounds });
                res.json(waypoints);
            } catch (error) {
                this.logger.error('Error fetching waypoints:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        this.app.post('/api/waypoints', async (req, res) => {
            try {
                const waypoint = await this.tacticalMaps.createWaypoint(req.body);
                res.status(201).json(waypoint);
            } catch (error) {
                this.logger.error('Error creating waypoint:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        this.app.put('/api/waypoints/:id', async (req, res) => {
            try {
                const { id } = req.params;
                const waypoint = await this.tacticalMaps.updateWaypoint(id, req.body);
                res.json(waypoint);
            } catch (error) {
                this.logger.error('Error updating waypoint:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        this.app.delete('/api/waypoints/:id', async (req, res) => {
            try {
                const { id } = req.params;
                await this.tacticalMaps.deleteWaypoint(id);
                res.status(204).send();
            } catch (error) {
                this.logger.error('Error deleting waypoint:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        // Tactical overlays API
        this.app.get('/api/overlays', async (req, res) => {
            try {
                const { teamId, missionId, bounds } = req.query;
                const overlays = await this.tacticalMaps.getTacticalOverlays({ teamId, missionId, bounds });
                res.json(overlays);
            } catch (error) {
                this.logger.error('Error fetching overlays:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        this.app.post('/api/overlays', async (req, res) => {
            try {
                const overlay = await this.tacticalMaps.createTacticalOverlay(req.body);
                res.status(201).json(overlay);
            } catch (error) {
                this.logger.error('Error creating overlay:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        // Team locations integration
        this.app.get('/api/team-locations', async (req, res) => {
            try {
                const { teamId, bounds } = req.query;
                const locations = await this.tacticalMaps.getTeamLocations({ teamId, bounds });
                res.json(locations);
            } catch (error) {
                this.logger.error('Error fetching team locations:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        // Map statistics
        this.app.get('/api/stats', async (req, res) => {
            try {
                const stats = await this.mapManager.getStatistics();
                res.json(stats);
            } catch (error) {
                this.logger.error('Error fetching statistics:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        // Static files
        this.app.use('/static', express.static(path.join(__dirname, 'static')));
    }

    setupErrorHandling() {
        // 404 handler
        this.app.use((req, res) => {
            res.status(404).json({ error: 'Not found' });
        });

        // Global error handler
        this.app.use((error, req, res, next) => {
            this.logger.error('Unhandled error:', error);
            res.status(500).json({ error: 'Internal server error' });
        });

        // Graceful shutdown
        process.on('SIGTERM', () => this.shutdown());
        process.on('SIGINT', () => this.shutdown());
    }

    async start() {
        try {
            // Ensure storage directories exist
            await this.ensureDirectories();
            
            // Start server
            this.server = this.app.listen(config.server.port, config.server.host, () => {
                this.logger.info(`Maps server started on ${config.server.host}:${config.server.port}`);
            });

            // Start background tasks
            this.startBackgroundTasks();
            
        } catch (error) {
            this.logger.error('Failed to start server:', error);
            throw error;
        }
    }

    async ensureDirectories() {
        const directories = [
            config.storage.mapsPath,
            config.storage.tilesPath,
            config.storage.dataPath,
            config.storage.cachePath
        ];

        for (const dir of directories) {
            try {
                await fs.mkdir(dir, { recursive: true });
                this.logger.info(`Ensured directory exists: ${dir}`);
            } catch (error) {
                this.logger.error(`Failed to create directory ${dir}:`, error);
                throw error;
            }
        }
    }

    startBackgroundTasks() {
        // Cleanup expired data every hour
        setInterval(async () => {
            try {
                await this.mapManager.cleanupExpiredData();
                this.logger.info('Completed cleanup of expired data');
            } catch (error) {
                this.logger.error('Error during cleanup:', error);
            }
        }, 3600000); // 1 hour

        // Update cache statistics every 5 minutes
        setInterval(async () => {
            try {
                await this.mapManager.updateCacheStatistics();
            } catch (error) {
                this.logger.error('Error updating cache statistics:', error);
            }
        }, 300000); // 5 minutes
    }

    async shutdown() {
        this.logger.info('Shutting down maps server...');
        
        if (this.server) {
            this.server.close();
        }
        
        if (this.db) {
            await this.db.end();
        }
        
        if (this.redis) {
            await this.redis.quit();
        }
        
        this.logger.info('Maps server shutdown complete');
        process.exit(0);
    }
}

// Start server if run directly
if (require.main === module) {
    const server = new MapServer();
    server.start().catch(error => {
        console.error('Failed to start maps server:', error);
        process.exit(1);
    });
}

module.exports = MapServer;