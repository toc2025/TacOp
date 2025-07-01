// Tactical Location Tracking WebSocket Server
// Version: 1.0.0
// Handles real-time GPS tracking through encrypted WebSocket connections

const WebSocket = require('ws');
const https = require('https');
const fs = require('fs');
const crypto = require('crypto');
const { Pool } = require('pg');

class TacticalLocationServer {
    constructor(config) {
        this.config = config;
        this.clients = new Map();
        this.locations = new Map();
        this.db = null;
        this.server = null;
        this.wss = null;
        this.encryptionKey = crypto.randomBytes(32);
        this.maxClients = config.maxClients || 5;
        
        this.init();
    }

    async init() {
        console.log('🚀 Initializing Tactical Location Server...');
        
        try {
            // Initialize database connection
            await this.initDatabase();
            
            // Create HTTPS server with SSL certificates
            await this.createSecureServer();
            
            // Initialize WebSocket server
            this.initWebSocketServer();
            
            // Setup cleanup handlers
            this.setupCleanupHandlers();
            
            console.log(`✅ Tactical Location Server running on port ${this.config.port}`);
            console.log(`🔒 SSL/TLS encryption enabled`);
            console.log(`👥 Maximum concurrent clients: ${this.maxClients}`);
            
        } catch (error) {
            console.error('❌ Failed to initialize server:', error);
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

        // Initialize database schema
        await this.initDatabaseSchema();
    }

    async initDatabaseSchema() {
        console.log('📋 Initializing database schema...');
        
        const schemaSQL = fs.readFileSync('./location-schema.sql', 'utf8');
        
        try {
            await this.db.query(schemaSQL);
            console.log('✅ Database schema initialized');
        } catch (error) {
            console.error('❌ Schema initialization failed:', error);
            throw error;
        }
    }

    async createSecureServer() {
        console.log('🔐 Creating secure HTTPS server...');
        
        const options = {
            cert: fs.readFileSync(this.config.ssl.cert),
            key: fs.readFileSync(this.config.ssl.key),
            // Enhanced security options
            secureProtocol: 'TLSv1_3_method',
            ciphers: [
                'ECDHE+AESGCM',
                'ECDHE+CHACHA20',
                'DHE+AESGCM',
                'DHE+CHACHA20',
                '!aNULL',
                '!MD5',
                '!DSS'
            ].join(':'),
            honorCipherOrder: true
        };

        this.server = https.createServer(options);
        
        this.server.listen(this.config.port, () => {
            console.log(`🌐 HTTPS server listening on port ${this.config.port}`);
        });
    }

    initWebSocketServer() {
        console.log('🔌 Initializing WebSocket server...');
        
        this.wss = new WebSocket.Server({
            server: this.server,
            path: '/tactical-location',
            verifyClient: (info) => this.verifyClient(info),
            maxPayload: 16 * 1024 // 16KB max payload
        });

        this.wss.on('connection', (ws, request) => {
            this.handleNewConnection(ws, request);
        });

        this.wss.on('error', (error) => {
            console.error('❌ WebSocket server error:', error);
        });

        // Setup periodic cleanup
        setInterval(() => {
            this.cleanupStaleConnections();
        }, 30000); // Every 30 seconds

        console.log('✅ WebSocket server initialized');
    }

    verifyClient(info) {
        // Basic verification - in production, implement proper authentication
        const origin = info.origin;
        const userAgent = info.req.headers['user-agent'];
        
        // Check if connection limit reached
        if (this.clients.size >= this.maxClients) {
            console.log(`⚠️  Connection rejected: Maximum clients (${this.maxClients}) reached`);
            return false;
        }

        // Log connection attempt
        console.log(`🔍 Connection attempt from ${info.req.socket.remoteAddress}`);
        
        return true;
    }

    handleNewConnection(ws, request) {
        const clientId = this.generateClientId();
        const clientInfo = {
            id: clientId,
            ws: ws,
            authenticated: false,
            deviceId: null,
            userId: null,
            lastSeen: Date.now(),
            location: null,
            batteryOptimized: true,
            updateInterval: 30000 // Default 30 seconds
        };

        this.clients.set(clientId, clientInfo);
        
        console.log(`👤 New client connected: ${clientId} (${this.clients.size}/${this.maxClients})`);

        // Setup message handlers
        ws.on('message', (data) => {
            this.handleMessage(clientId, data);
        });

        ws.on('close', (code, reason) => {
            this.handleDisconnection(clientId, code, reason);
        });

        ws.on('error', (error) => {
            console.error(`❌ Client ${clientId} error:`, error);
            this.handleDisconnection(clientId, 1006, 'Connection error');
        });

        // Send welcome message
        this.sendToClient(clientId, {
            type: 'welcome',
            data: {
                clientId: clientId,
                serverTime: Date.now(),
                maxUpdateInterval: 1000, // 1 second minimum
                batteryOptimization: true
            }
        });
    }

    async handleMessage(clientId, data) {
        const client = this.clients.get(clientId);
        if (!client) return;

        try {
            const message = JSON.parse(data.toString());
            client.lastSeen = Date.now();

            switch (message.type) {
                case 'authentication':
                    await this.handleAuthentication(clientId, message.data);
                    break;
                
                case 'location_update':
                    await this.handleLocationUpdate(clientId, message.data);
                    break;
                
                case 'waypoint_marked':
                    await this.handleWaypointMarked(clientId, message.data);
                    break;
                
                case 'emergency_alert':
                    await this.handleEmergencyAlert(clientId, message.data);
                    break;
                
                case 'ping':
                    this.sendToClient(clientId, { type: 'pong', data: { timestamp: Date.now() } });
                    break;
                
                default:
                    console.log(`⚠️  Unknown message type from ${clientId}: ${message.type}`);
            }
        } catch (error) {
            console.error(`❌ Error processing message from ${clientId}:`, error);
            this.sendToClient(clientId, {
                type: 'error',
                data: { message: 'Invalid message format' }
            });
        }
    }

    async handleAuthentication(clientId, authData) {
        const client = this.clients.get(clientId);
        if (!client) return;

        console.log(`🔐 Authentication attempt from ${clientId}`);

        try {
            // Validate authentication data
            if (!authData.userId || !authData.deviceId) {
                throw new Error('Missing required authentication fields');
            }

            // Store device information
            await this.storeDeviceInfo(authData);

            // Update client info
            client.authenticated = true;
            client.userId = authData.userId;
            client.deviceId = authData.deviceId;

            console.log(`✅ Client ${clientId} authenticated as ${authData.userId}`);

            // Send authentication success
            this.sendToClient(clientId, {
                type: 'authentication_success',
                data: {
                    userId: authData.userId,
                    deviceId: authData.deviceId,
                    serverTime: Date.now()
                }
            });

            // Broadcast team update to other clients
            this.broadcastTeamUpdate();

        } catch (error) {
            console.error(`❌ Authentication failed for ${clientId}:`, error);
            
            this.sendToClient(clientId, {
                type: 'authentication_failed',
                data: { message: error.message }
            });
        }
    }

    async handleLocationUpdate(clientId, locationData) {
        const client = this.clients.get(clientId);
        if (!client || !client.authenticated) {
            console.log(`⚠️  Unauthorized location update from ${clientId}`);
            return;
        }

        try {
            // Decrypt location data if encrypted
            const decryptedData = this.decryptLocationData(locationData);
            
            // Validate location data
            if (!this.validateLocationData(decryptedData)) {
                throw new Error('Invalid location data');
            }

            // Store location in database (temporary)
            await this.storeLocationUpdate(client.userId, decryptedData);

            // Update client's current location
            client.location = decryptedData.coordinates;

            // Broadcast location update to team members
            this.broadcastLocationUpdate(client.userId, decryptedData);

            console.log(`📍 Location update from ${client.userId}: ${decryptedData.coordinates.latitude.toFixed(6)}, ${decryptedData.coordinates.longitude.toFixed(6)}`);

        } catch (error) {
            console.error(`❌ Location update error for ${clientId}:`, error);
            
            this.sendToClient(clientId, {
                type: 'location_error',
                data: { message: error.message }
            });
        }
    }

    async handleWaypointMarked(clientId, waypointData) {
        const client = this.clients.get(clientId);
        if (!client || !client.authenticated) return;

        try {
            // Store waypoint in database
            await this.storeWaypoint(client.userId, waypointData);

            // Broadcast waypoint to team
            this.broadcastToTeam({
                type: 'waypoint_added',
                data: {
                    userId: client.userId,
                    waypoint: waypointData,
                    timestamp: Date.now()
                }
            }, clientId);

            console.log(`📌 Waypoint marked by ${client.userId}`);

        } catch (error) {
            console.error(`❌ Waypoint error for ${clientId}:`, error);
        }
    }

    async handleEmergencyAlert(clientId, alertData) {
        const client = this.clients.get(clientId);
        if (!client || !client.authenticated) return;

        console.log(`🚨 EMERGENCY ALERT from ${client.userId}`);

        try {
            // Store emergency alert
            await this.storeEmergencyAlert(client.userId, alertData);

            // Broadcast emergency alert to all team members
            this.broadcastToTeam({
                type: 'emergency_alert',
                data: {
                    userId: client.userId,
                    location: client.location,
                    message: alertData.message || 'Emergency assistance required',
                    timestamp: Date.now(),
                    alertId: this.generateAlertId()
                }
            });

            console.log(`🚨 Emergency alert broadcasted from ${client.userId}`);

        } catch (error) {
            console.error(`❌ Emergency alert error for ${clientId}:`, error);
        }
    }

    handleDisconnection(clientId, code, reason) {
        const client = this.clients.get(clientId);
        if (client) {
            console.log(`👋 Client ${clientId} disconnected: ${code} - ${reason}`);
            
            // Broadcast team update
            if (client.authenticated) {
                this.broadcastTeamUpdate();
            }
            
            this.clients.delete(clientId);
        }
    }

    // Utility Methods

    generateClientId() {
        return `client_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }

    generateAlertId() {
        return `alert_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
    }

    encryptLocationData(data) {
        const cipher = crypto.createCipher('aes-256-gcm', this.encryptionKey);
        let encrypted = cipher.update(JSON.stringify(data), 'utf8', 'hex');
        encrypted += cipher.final('hex');
        return {
            encrypted: encrypted,
            tag: cipher.getAuthTag().toString('hex')
        };
    }

    decryptLocationData(encryptedData) {
        // If data is not encrypted, return as-is (for development)
        if (!encryptedData.encrypted) {
            return encryptedData;
        }

        try {
            const decipher = crypto.createDecipher('aes-256-gcm', this.encryptionKey);
            decipher.setAuthTag(Buffer.from(encryptedData.tag, 'hex'));
            let decrypted = decipher.update(encryptedData.encrypted, 'hex', 'utf8');
            decrypted += decipher.final('utf8');
            return JSON.parse(decrypted);
        } catch (error) {
            console.error('❌ Decryption failed:', error);
            throw new Error('Failed to decrypt location data');
        }
    }

    validateLocationData(data) {
        if (!data.coordinates) return false;
        if (typeof data.coordinates.latitude !== 'number') return false;
        if (typeof data.coordinates.longitude !== 'number') return false;
        if (Math.abs(data.coordinates.latitude) > 90) return false;
        if (Math.abs(data.coordinates.longitude) > 180) return false;
        return true;
    }

    sendToClient(clientId, message) {
        const client = this.clients.get(clientId);
        if (client && client.ws.readyState === WebSocket.OPEN) {
            try {
                client.ws.send(JSON.stringify(message));
            } catch (error) {
                console.error(`❌ Failed to send message to ${clientId}:`, error);
            }
        }
    }

    broadcastToTeam(message, excludeClientId = null) {
        let sentCount = 0;
        
        this.clients.forEach((client, clientId) => {
            if (client.authenticated && clientId !== excludeClientId) {
                this.sendToClient(clientId, message);
                sentCount++;
            }
        });

        console.log(`📡 Broadcasted message to ${sentCount} team members`);
    }

    broadcastTeamUpdate() {
        const teamMembers = [];
        
        this.clients.forEach((client) => {
            if (client.authenticated) {
                teamMembers.push({
                    userId: client.userId,
                    deviceId: client.deviceId,
                    location: client.location,
                    lastSeen: client.lastSeen,
                    online: true
                });
            }
        });

        this.broadcastToTeam({
            type: 'team_update',
            data: {
                members: teamMembers,
                timestamp: Date.now()
            }
        });
    }

    broadcastLocationUpdate(userId, locationData) {
        this.broadcastToTeam({
            type: 'location_update',
            data: {
                userId: userId,
                coordinates: locationData.coordinates,
                timestamp: locationData.timestamp,
                accuracy: locationData.coordinates.accuracy
            }
        });
    }

    cleanupStaleConnections() {
        const now = Date.now();
        const staleTimeout = 5 * 60 * 1000; // 5 minutes

        this.clients.forEach((client, clientId) => {
            if (now - client.lastSeen > staleTimeout) {
                console.log(`🧹 Cleaning up stale connection: ${clientId}`);
                client.ws.terminate();
                this.clients.delete(clientId);
            }
        });
    }

    // Database Methods

    async storeDeviceInfo(authData) {
        const query = `
            INSERT INTO devices (device_id, user_id, device_fingerprint, last_seen, created_at)
            VALUES ($1, $2, $3, NOW(), NOW())
            ON CONFLICT (device_id) 
            DO UPDATE SET 
                user_id = EXCLUDED.user_id,
                last_seen = NOW()
        `;
        
        await this.db.query(query, [
            authData.deviceId,
            authData.userId,
            authData.deviceFingerprint || null
        ]);
    }

    async storeLocationUpdate(userId, locationData) {
        const query = `
            INSERT INTO location_updates (
                user_id, 
                latitude, 
                longitude, 
                accuracy, 
                heading, 
                speed, 
                altitude,
                timestamp,
                created_at
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
        `;
        
        const coords = locationData.coordinates;
        await this.db.query(query, [
            userId,
            coords.latitude,
            coords.longitude,
            coords.accuracy || null,
            coords.heading || null,
            coords.speed || null,
            coords.altitude || null,
            new Date(locationData.timestamp)
        ]);
    }

    async storeWaypoint(userId, waypointData) {
        const query = `
            INSERT INTO waypoints (
                user_id,
                latitude,
                longitude,
                name,
                description,
                created_at
            ) VALUES ($1, $2, $3, $4, $5, NOW())
        `;
        
        await this.db.query(query, [
            userId,
            waypointData.coordinates.latitude,
            waypointData.coordinates.longitude,
            waypointData.name || 'Waypoint',
            waypointData.description || null
        ]);
    }

    async storeEmergencyAlert(userId, alertData) {
        const query = `
            INSERT INTO emergency_alerts (
                user_id,
                message,
                latitude,
                longitude,
                created_at
            ) VALUES ($1, $2, $3, $4, NOW())
        `;
        
        const client = Array.from(this.clients.values()).find(c => c.userId === userId);
        const location = client?.location;
        
        await this.db.query(query, [
            userId,
            alertData.message || 'Emergency assistance required',
            location?.latitude || null,
            location?.longitude || null
        ]);
    }

    setupCleanupHandlers() {
        // Graceful shutdown handlers
        process.on('SIGTERM', () => this.shutdown('SIGTERM'));
        process.on('SIGINT', () => this.shutdown('SIGINT'));
        process.on('uncaughtException', (error) => {
            console.error('❌ Uncaught exception:', error);
            this.shutdown('UNCAUGHT_EXCEPTION');
        });
    }

    async shutdown(signal) {
        console.log(`🛑 Shutting down server (${signal})...`);
        
        // Close WebSocket connections
        this.clients.forEach((client, clientId) => {
            client.ws.close(1001, 'Server shutting down');
        });
        
        // Close WebSocket server
        if (this.wss) {
            this.wss.close();
        }
        
        // Close HTTPS server
        if (this.server) {
            this.server.close();
        }
        
        // Close database connections
        if (this.db) {
            await this.db.end();
        }
        
        console.log('✅ Server shutdown complete');
        process.exit(0);
    }
}

module.exports = TacticalLocationServer;