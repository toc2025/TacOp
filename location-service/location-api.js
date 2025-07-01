// Tactical Location Service REST API
// Version: 1.0.0
// RESTful API endpoints for location management

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { Pool } = require('pg');
const crypto = require('crypto');

class TacticalLocationAPI {
    constructor(config) {
        this.config = config;
        this.app = express();
        this.db = null;
        
        this.init();
    }

    async init() {
        console.log('🚀 Initializing Tactical Location API...');
        
        try {
            // Initialize database connection
            await this.initDatabase();
            
            // Setup middleware
            this.setupMiddleware();
            
            // Setup routes
            this.setupRoutes();
            
            // Start server
            this.startServer();
            
            console.log(`✅ Location API server running on port ${this.config.apiPort}`);
            
        } catch (error) {
            console.error('❌ Failed to initialize API server:', error);
            process.exit(1);
        }
    }

    async initDatabase() {
        console.log('🗄️  Connecting to PostgreSQL database...');
        
        this.db = new Pool({
            host: this.config.database.host,
            port: this.config.database.port,
            database: this.config.database.name,
            user: this.config.database.user,
            password: this.config.database.password,
            max: 10,
            idleTimeoutMillis: 30000,
            connectionTimeoutMillis: 2000,
        });

        // Test connection
        try {
            const client = await this.db.connect();
            await client.query('SELECT NOW()');
            client.release();
            console.log('✅ Database connection established');
        } catch (error) {
            throw new Error(`Database connection failed: ${error.message}`);
        }
    }

    setupMiddleware() {
        console.log('🔧 Setting up middleware...');
        
        // Security middleware
        this.app.use(helmet({
            contentSecurityPolicy: {
                directives: {
                    defaultSrc: ["'self'"],
                    scriptSrc: ["'self'", "'unsafe-inline'"],
                    styleSrc: ["'self'", "'unsafe-inline'"],
                    imgSrc: ["'self'", "data:", "https:"],
                    connectSrc: ["'self'", "wss:", "ws:"]
                }
            }
        }));

        // CORS configuration
        this.app.use(cors({
            origin: [
                'https://tactical.local',
                'https://192.168.100.1',
                'http://localhost:3000'
            ],
            credentials: true,
            methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
            allowedHeaders: ['Content-Type', 'Authorization', 'X-Device-ID', 'X-User-ID']
        }));

        // Rate limiting
        const limiter = rateLimit({
            windowMs: 15 * 60 * 1000, // 15 minutes
            max: 100, // Limit each IP to 100 requests per windowMs
            message: {
                error: 'Too many requests from this IP, please try again later.'
            },
            standardHeaders: true,
            legacyHeaders: false,
        });
        this.app.use('/api/', limiter);

        // Body parsing
        this.app.use(express.json({ limit: '10mb' }));
        this.app.use(express.urlencoded({ extended: true, limit: '10mb' }));

        // Request logging
        this.app.use((req, res, next) => {
            console.log(`📡 ${req.method} ${req.path} - ${req.ip}`);
            next();
        });

        // Authentication middleware
        this.app.use('/api/', this.authenticateRequest.bind(this));
    }

    authenticateRequest(req, res, next) {
        // Skip authentication for health check
        if (req.path === '/health') {
            return next();
        }

        const deviceId = req.headers['x-device-id'];
        const userId = req.headers['x-user-id'];

        if (!deviceId || !userId) {
            return res.status(401).json({
                error: 'Authentication required',
                message: 'Missing device ID or user ID headers'
            });
        }

        // Store authentication info in request
        req.auth = { deviceId, userId };
        next();
    }

    setupRoutes() {
        console.log('🛣️  Setting up API routes...');

        // Health check endpoint
        this.app.get('/api/health', this.getHealth.bind(this));

        // Device management
        this.app.post('/api/devices/register', this.registerDevice.bind(this));
        this.app.get('/api/devices', this.getDevices.bind(this));
        this.app.put('/api/devices/:deviceId', this.updateDevice.bind(this));

        // Location endpoints
        this.app.get('/api/locations/current', this.getCurrentLocations.bind(this));
        this.app.get('/api/locations/history/:userId', this.getLocationHistory.bind(this));
        this.app.post('/api/locations/update', this.updateLocation.bind(this));
        this.app.delete('/api/locations/cleanup', this.cleanupLocations.bind(this));

        // Team management
        this.app.get('/api/team/status', this.getTeamStatus.bind(this));
        this.app.get('/api/team/members', this.getTeamMembers.bind(this));
        this.app.put('/api/team/member/:userId/status', this.updateMemberStatus.bind(this));

        // Waypoint management
        this.app.get('/api/waypoints', this.getWaypoints.bind(this));
        this.app.post('/api/waypoints', this.createWaypoint.bind(this));
        this.app.put('/api/waypoints/:waypointId', this.updateWaypoint.bind(this));
        this.app.delete('/api/waypoints/:waypointId', this.deleteWaypoint.bind(this));

        // Emergency alerts
        this.app.get('/api/alerts', this.getAlerts.bind(this));
        this.app.post('/api/alerts/emergency', this.createEmergencyAlert.bind(this));
        this.app.put('/api/alerts/:alertId/acknowledge', this.acknowledgeAlert.bind(this));

        // Statistics and analytics
        this.app.get('/api/stats/overview', this.getStatsOverview.bind(this));
        this.app.get('/api/stats/locations', this.getLocationStats.bind(this));

        // Error handling middleware
        this.app.use(this.errorHandler.bind(this));
    }

    // Health Check
    async getHealth(req, res) {
        try {
            // Test database connection
            const dbResult = await this.db.query('SELECT NOW() as timestamp');
            
            res.json({
                status: 'healthy',
                timestamp: new Date().toISOString(),
                database: 'connected',
                dbTimestamp: dbResult.rows[0].timestamp,
                version: '1.0.0'
            });
        } catch (error) {
            res.status(503).json({
                status: 'unhealthy',
                error: error.message,
                timestamp: new Date().toISOString()
            });
        }
    }

    // Device Management
    async registerDevice(req, res) {
        try {
            const { deviceId, userId, deviceInfo } = req.body;

            if (!deviceId || !userId) {
                return res.status(400).json({
                    error: 'Missing required fields',
                    required: ['deviceId', 'userId']
                });
            }

            const query = `
                INSERT INTO devices (device_id, user_id, device_info, registered_at, last_seen)
                VALUES ($1, $2, $3, NOW(), NOW())
                ON CONFLICT (device_id) 
                DO UPDATE SET 
                    user_id = EXCLUDED.user_id,
                    device_info = EXCLUDED.device_info,
                    last_seen = NOW()
                RETURNING *
            `;

            const result = await this.db.query(query, [
                deviceId,
                userId,
                JSON.stringify(deviceInfo || {})
            ]);

            console.log(`📱 Device registered: ${deviceId} for user ${userId}`);

            res.status(201).json({
                success: true,
                device: result.rows[0],
                message: 'Device registered successfully'
            });

        } catch (error) {
            console.error('❌ Device registration error:', error);
            res.status(500).json({
                error: 'Device registration failed',
                message: error.message
            });
        }
    }

    async getDevices(req, res) {
        try {
            const query = `
                SELECT device_id, user_id, device_info, registered_at, last_seen,
                       CASE WHEN last_seen > NOW() - INTERVAL '5 minutes' THEN true ELSE false END as online
                FROM devices
                ORDER BY last_seen DESC
            `;

            const result = await this.db.query(query);

            res.json({
                success: true,
                devices: result.rows,
                count: result.rows.length
            });

        } catch (error) {
            console.error('❌ Get devices error:', error);
            res.status(500).json({
                error: 'Failed to retrieve devices',
                message: error.message
            });
        }
    }

    // Location Management
    async getCurrentLocations(req, res) {
        try {
            const query = `
                SELECT DISTINCT ON (user_id) 
                    user_id, latitude, longitude, accuracy, heading, speed, altitude, timestamp
                FROM location_updates
                WHERE timestamp > NOW() - INTERVAL '1 hour'
                ORDER BY user_id, timestamp DESC
            `;

            const result = await this.db.query(query);

            res.json({
                success: true,
                locations: result.rows,
                count: result.rows.length,
                timestamp: new Date().toISOString()
            });

        } catch (error) {
            console.error('❌ Get current locations error:', error);
            res.status(500).json({
                error: 'Failed to retrieve current locations',
                message: error.message
            });
        }
    }

    async getLocationHistory(req, res) {
        try {
            const { userId } = req.params;
            const { limit = 100, offset = 0, since } = req.query;

            let query = `
                SELECT latitude, longitude, accuracy, heading, speed, altitude, timestamp
                FROM location_updates
                WHERE user_id = $1
            `;
            const params = [userId];

            if (since) {
                query += ` AND timestamp > $${params.length + 1}`;
                params.push(new Date(since));
            }

            query += ` ORDER BY timestamp DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
            params.push(parseInt(limit), parseInt(offset));

            const result = await this.db.query(query, params);

            res.json({
                success: true,
                history: result.rows,
                count: result.rows.length,
                userId: userId
            });

        } catch (error) {
            console.error('❌ Get location history error:', error);
            res.status(500).json({
                error: 'Failed to retrieve location history',
                message: error.message
            });
        }
    }

    async updateLocation(req, res) {
        try {
            const { userId, coordinates, timestamp } = req.body;

            if (!userId || !coordinates) {
                return res.status(400).json({
                    error: 'Missing required fields',
                    required: ['userId', 'coordinates']
                });
            }

            const query = `
                INSERT INTO location_updates (
                    user_id, latitude, longitude, accuracy, heading, speed, altitude, timestamp, created_at
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
                RETURNING id
            `;

            const result = await this.db.query(query, [
                userId,
                coordinates.latitude,
                coordinates.longitude,
                coordinates.accuracy || null,
                coordinates.heading || null,
                coordinates.speed || null,
                coordinates.altitude || null,
                new Date(timestamp || Date.now())
            ]);

            res.json({
                success: true,
                locationId: result.rows[0].id,
                message: 'Location updated successfully'
            });

        } catch (error) {
            console.error('❌ Update location error:', error);
            res.status(500).json({
                error: 'Failed to update location',
                message: error.message
            });
        }
    }

    async cleanupLocations(req, res) {
        try {
            const { olderThan = '24 hours' } = req.query;

            const query = `
                DELETE FROM location_updates 
                WHERE created_at < NOW() - INTERVAL '${olderThan}'
            `;

            const result = await this.db.query(query);

            console.log(`🧹 Cleaned up ${result.rowCount} old location records`);

            res.json({
                success: true,
                deletedCount: result.rowCount,
                message: `Cleaned up locations older than ${olderThan}`
            });

        } catch (error) {
            console.error('❌ Location cleanup error:', error);
            res.status(500).json({
                error: 'Failed to cleanup locations',
                message: error.message
            });
        }
    }

    // Team Management
    async getTeamStatus(req, res) {
        try {
            const query = `
                SELECT 
                    d.user_id,
                    d.device_id,
                    d.last_seen,
                    CASE WHEN d.last_seen > NOW() - INTERVAL '5 minutes' THEN true ELSE false END as online,
                    l.latitude,
                    l.longitude,
                    l.timestamp as last_location_update
                FROM devices d
                LEFT JOIN LATERAL (
                    SELECT latitude, longitude, timestamp
                    FROM location_updates lu
                    WHERE lu.user_id = d.user_id
                    ORDER BY timestamp DESC
                    LIMIT 1
                ) l ON true
                ORDER BY d.last_seen DESC
            `;

            const result = await this.db.query(query);

            res.json({
                success: true,
                teamStatus: result.rows,
                onlineCount: result.rows.filter(member => member.online).length,
                totalCount: result.rows.length,
                timestamp: new Date().toISOString()
            });

        } catch (error) {
            console.error('❌ Get team status error:', error);
            res.status(500).json({
                error: 'Failed to retrieve team status',
                message: error.message
            });
        }
    }

    // Waypoint Management
    async getWaypoints(req, res) {
        try {
            const { userId, limit = 50 } = req.query;

            let query = `
                SELECT id, user_id, latitude, longitude, name, description, created_at
                FROM waypoints
            `;
            const params = [];

            if (userId) {
                query += ` WHERE user_id = $1`;
                params.push(userId);
            }

            query += ` ORDER BY created_at DESC LIMIT $${params.length + 1}`;
            params.push(parseInt(limit));

            const result = await this.db.query(query, params);

            res.json({
                success: true,
                waypoints: result.rows,
                count: result.rows.length
            });

        } catch (error) {
            console.error('❌ Get waypoints error:', error);
            res.status(500).json({
                error: 'Failed to retrieve waypoints',
                message: error.message
            });
        }
    }

    async createWaypoint(req, res) {
        try {
            const { latitude, longitude, name, description } = req.body;
            const { userId } = req.auth;

            if (!latitude || !longitude) {
                return res.status(400).json({
                    error: 'Missing required fields',
                    required: ['latitude', 'longitude']
                });
            }

            const query = `
                INSERT INTO waypoints (user_id, latitude, longitude, name, description, created_at)
                VALUES ($1, $2, $3, $4, $5, NOW())
                RETURNING *
            `;

            const result = await this.db.query(query, [
                userId,
                latitude,
                longitude,
                name || 'Waypoint',
                description || null
            ]);

            console.log(`📌 Waypoint created by ${userId}: ${name || 'Waypoint'}`);

            res.status(201).json({
                success: true,
                waypoint: result.rows[0],
                message: 'Waypoint created successfully'
            });

        } catch (error) {
            console.error('❌ Create waypoint error:', error);
            res.status(500).json({
                error: 'Failed to create waypoint',
                message: error.message
            });
        }
    }

    // Emergency Alerts
    async getAlerts(req, res) {
        try {
            const { limit = 20, status = 'all' } = req.query;

            let query = `
                SELECT id, user_id, message, latitude, longitude, status, created_at, acknowledged_at
                FROM emergency_alerts
            `;
            const params = [];

            if (status !== 'all') {
                query += ` WHERE status = $1`;
                params.push(status);
            }

            query += ` ORDER BY created_at DESC LIMIT $${params.length + 1}`;
            params.push(parseInt(limit));

            const result = await this.db.query(query, params);

            res.json({
                success: true,
                alerts: result.rows,
                count: result.rows.length
            });

        } catch (error) {
            console.error('❌ Get alerts error:', error);
            res.status(500).json({
                error: 'Failed to retrieve alerts',
                message: error.message
            });
        }
    }

    async createEmergencyAlert(req, res) {
        try {
            const { message, latitude, longitude } = req.body;
            const { userId } = req.auth;

            const query = `
                INSERT INTO emergency_alerts (user_id, message, latitude, longitude, status, created_at)
                VALUES ($1, $2, $3, $4, 'active', NOW())
                RETURNING *
            `;

            const result = await this.db.query(query, [
                userId,
                message || 'Emergency assistance required',
                latitude || null,
                longitude || null
            ]);

            console.log(`🚨 Emergency alert created by ${userId}`);

            res.status(201).json({
                success: true,
                alert: result.rows[0],
                message: 'Emergency alert created successfully'
            });

        } catch (error) {
            console.error('❌ Create emergency alert error:', error);
            res.status(500).json({
                error: 'Failed to create emergency alert',
                message: error.message
            });
        }
    }

    // Statistics
    async getStatsOverview(req, res) {
        try {
            const queries = await Promise.all([
                this.db.query('SELECT COUNT(*) as total_devices FROM devices'),
                this.db.query('SELECT COUNT(*) as online_devices FROM devices WHERE last_seen > NOW() - INTERVAL \'5 minutes\''),
                this.db.query('SELECT COUNT(*) as total_locations FROM location_updates WHERE timestamp > NOW() - INTERVAL \'24 hours\''),
                this.db.query('SELECT COUNT(*) as total_waypoints FROM waypoints'),
                this.db.query('SELECT COUNT(*) as active_alerts FROM emergency_alerts WHERE status = \'active\'')
            ]);

            const stats = {
                devices: {
                    total: parseInt(queries[0].rows[0].total_devices),
                    online: parseInt(queries[1].rows[0].online_devices)
                },
                locations: {
                    updates24h: parseInt(queries[2].rows[0].total_locations)
                },
                waypoints: {
                    total: parseInt(queries[3].rows[0].total_waypoints)
                },
                alerts: {
                    active: parseInt(queries[4].rows[0].active_alerts)
                },
                timestamp: new Date().toISOString()
            };

            res.json({
                success: true,
                stats: stats
            });

        } catch (error) {
            console.error('❌ Get stats overview error:', error);
            res.status(500).json({
                error: 'Failed to retrieve statistics',
                message: error.message
            });
        }
    }

    // Error handling
    errorHandler(error, req, res, next) {
        console.error('❌ API Error:', error);

        if (error.type === 'entity.parse.failed') {
            return res.status(400).json({
                error: 'Invalid JSON payload',
                message: 'Request body contains invalid JSON'
            });
        }

        res.status(500).json({
            error: 'Internal server error',
            message: 'An unexpected error occurred'
        });
    }

    startServer() {
        this.app.listen(this.config.apiPort, () => {
            console.log(`🌐 Location API server listening on port ${this.config.apiPort}`);
        });
    }
}

module.exports = TacticalLocationAPI;