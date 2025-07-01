// Tactical Location Client Handler
// Version: 1.0.0
// Client-side location tracking with HTML5 Geolocation API integration

class TacticalLocationClient {
    constructor(config = {}) {
        this.config = {
            serverUrl: config.serverUrl || 'wss://192.168.100.1:8443/tactical-location',
            apiUrl: config.apiUrl || 'https://192.168.100.1/api',
            updateInterval: config.updateInterval || 30000, // 30 seconds default
            highAccuracy: config.highAccuracy !== false,
            maxAge: config.maxAge || 30000,
            timeout: config.timeout || 10000,
            batteryOptimized: config.batteryOptimized !== false,
            offlineStorage: config.offlineStorage !== false,
            ...config
        };

        // State management
        this.isConnected = false;
        this.isTracking = false;
        this.websocket = null;
        this.watchId = null;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 10;
        this.reconnectDelay = 1000;
        this.lastPosition = null;
        this.offlineQueue = [];
        this.batteryLevel = 1.0;
        this.isMoving = false;
        this.lastMovementTime = Date.now();

        // Event handlers
        this.eventHandlers = {
            connected: [],
            disconnected: [],
            locationUpdate: [],
            error: [],
            teamUpdate: [],
            emergencyAlert: []
        };

        // Initialize
        this.init();
    }

    async init() {
        console.log('🚀 Initializing Tactical Location Client...');
        
        try {
            // Check geolocation support
            if (!navigator.geolocation) {
                throw new Error('Geolocation not supported by this browser');
            }

            // Request geolocation permission
            await this.requestLocationPermission();

            // Initialize battery monitoring if available
            this.initBatteryMonitoring();

            // Load offline queue from storage
            this.loadOfflineQueue();

            // Setup visibility change handler for battery optimization
            this.setupVisibilityHandler();

            console.log('✅ Tactical Location Client initialized');

        } catch (error) {
            console.error('❌ Failed to initialize location client:', error);
            this.emit('error', { type: 'initialization', error: error.message });
        }
    }

    async requestLocationPermission() {
        try {
            const permission = await navigator.permissions.query({ name: 'geolocation' });
            
            if (permission.state === 'denied') {
                throw new Error('Geolocation permission denied');
            }

            if (permission.state === 'prompt') {
                // Try to get position to trigger permission prompt
                await new Promise((resolve, reject) => {
                    navigator.geolocation.getCurrentPosition(resolve, reject, {
                        enableHighAccuracy: false,
                        timeout: 5000,
                        maximumAge: 60000
                    });
                });
            }

            console.log('✅ Geolocation permission granted');

        } catch (error) {
            console.warn('⚠️  Geolocation permission issue:', error.message);
            throw error;
        }
    }

    async initBatteryMonitoring() {
        try {
            if ('getBattery' in navigator) {
                const battery = await navigator.getBattery();
                this.batteryLevel = battery.level;

                battery.addEventListener('levelchange', () => {
                    this.batteryLevel = battery.level;
                    this.adjustUpdateInterval();
                });

                battery.addEventListener('chargingchange', () => {
                    this.adjustUpdateInterval();
                });

                console.log(`🔋 Battery monitoring enabled (${Math.round(this.batteryLevel * 100)}%)`);
            }
        } catch (error) {
            console.warn('⚠️  Battery monitoring not available:', error.message);
        }
    }

    setupVisibilityHandler() {
        document.addEventListener('visibilitychange', () => {
            if (document.hidden) {
                // App is in background - optimize for battery
                this.adjustUpdateInterval(true);
            } else {
                // App is active - resume normal operation
                this.adjustUpdateInterval(false);
            }
        });
    }

    adjustUpdateInterval(isBackground = false) {
        if (!this.config.batteryOptimized) return;

        let newInterval = this.config.updateInterval;

        // Battery level adjustments
        if (this.batteryLevel < 0.2) {
            newInterval *= 4; // 4x slower when battery < 20%
        } else if (this.batteryLevel < 0.5) {
            newInterval *= 2; // 2x slower when battery < 50%
        }

        // Background adjustments
        if (isBackground) {
            newInterval *= 2; // 2x slower in background
        }

        // Movement-based adjustments
        const timeSinceMovement = Date.now() - this.lastMovementTime;
        if (timeSinceMovement > 300000) { // 5 minutes without movement
            newInterval *= 3; // 3x slower when stationary
        }

        // Apply limits
        newInterval = Math.max(1000, Math.min(300000, newInterval)); // 1s to 5min

        if (newInterval !== this.currentUpdateInterval) {
            this.currentUpdateInterval = newInterval;
            console.log(`⚡ Update interval adjusted to ${newInterval}ms (battery: ${Math.round(this.batteryLevel * 100)}%)`);
            
            if (this.isTracking) {
                this.restartTracking();
            }
        }
    }

    // WebSocket Connection Management
    async connect() {
        if (this.isConnected || this.websocket) {
            console.log('⚠️  Already connected or connecting');
            return;
        }

        try {
            console.log(`🔌 Connecting to tactical server: ${this.config.serverUrl}`);
            
            this.websocket = new WebSocket(this.config.serverUrl);
            
            this.websocket.onopen = () => {
                console.log('✅ Connected to tactical server');
                this.isConnected = true;
                this.reconnectAttempts = 0;
                this.emit('connected');
                
                // Send authentication
                this.authenticate();
                
                // Process offline queue
                this.processOfflineQueue();
            };

            this.websocket.onmessage = (event) => {
                this.handleServerMessage(JSON.parse(event.data));
            };

            this.websocket.onclose = (event) => {
                console.log(`🔌 Disconnected from tactical server: ${event.code} - ${event.reason}`);
                this.isConnected = false;
                this.websocket = null;
                this.emit('disconnected', { code: event.code, reason: event.reason });
                
                // Attempt reconnection
                this.scheduleReconnect();
            };

            this.websocket.onerror = (error) => {
                console.error('❌ WebSocket error:', error);
                this.emit('error', { type: 'websocket', error: error.message });
            };

        } catch (error) {
            console.error('❌ Connection failed:', error);
            this.emit('error', { type: 'connection', error: error.message });
            this.scheduleReconnect();
        }
    }

    disconnect() {
        console.log('🔌 Disconnecting from tactical server...');
        
        if (this.websocket) {
            this.websocket.close(1000, 'Client disconnect');
            this.websocket = null;
        }
        
        this.isConnected = false;
        this.stopTracking();
    }

    scheduleReconnect() {
        if (this.reconnectAttempts >= this.maxReconnectAttempts) {
            console.error('❌ Maximum reconnection attempts reached');
            this.emit('error', { type: 'reconnect', error: 'Maximum reconnection attempts reached' });
            return;
        }

        const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts); // Exponential backoff
        this.reconnectAttempts++;

        console.log(`🔄 Scheduling reconnection attempt ${this.reconnectAttempts} in ${delay}ms`);
        
        setTimeout(() => {
            if (!this.isConnected) {
                this.connect();
            }
        }, delay);
    }

    authenticate() {
        if (!this.isConnected) return;

        const authData = {
            type: 'authentication',
            data: {
                userId: this.generateUserId(),
                deviceId: this.generateDeviceFingerprint(),
                timestamp: Date.now(),
                version: '1.0.0',
                capabilities: {
                    gps: true,
                    battery: 'getBattery' in navigator,
                    offline: this.config.offlineStorage
                }
            }
        };

        this.sendMessage(authData);
    }

    handleServerMessage(message) {
        switch (message.type) {
            case 'welcome':
                console.log('👋 Welcome message received from server');
                break;
                
            case 'authentication_success':
                console.log('✅ Authentication successful');
                break;
                
            case 'authentication_failed':
                console.error('❌ Authentication failed:', message.data.message);
                this.emit('error', { type: 'authentication', error: message.data.message });
                break;
                
            case 'team_update':
                console.log('👥 Team update received');
                this.emit('teamUpdate', message.data);
                break;
                
            case 'location_update':
                this.emit('locationUpdate', message.data);
                break;
                
            case 'emergency_alert':
                console.log('🚨 Emergency alert received');
                this.emit('emergencyAlert', message.data);
                break;
                
            case 'system_command':
                this.handleSystemCommand(message.data);
                break;
                
            case 'pong':
                // Heartbeat response
                break;
                
            default:
                console.log('❓ Unknown message type:', message.type);
        }
    }

    handleSystemCommand(command) {
        switch (command.command) {
            case 'update_interval':
                this.config.updateInterval = command.interval;
                this.adjustUpdateInterval();
                break;
                
            case 'high_accuracy':
                this.config.highAccuracy = command.enabled;
                if (this.isTracking) {
                    this.restartTracking();
                }
                break;
                
            case 'emergency_mode':
                this.activateEmergencyMode();
                break;
                
            default:
                console.log('❓ Unknown system command:', command.command);
        }
    }

    // Location Tracking
    startTracking() {
        if (this.isTracking) {
            console.log('⚠️  Location tracking already active');
            return;
        }

        console.log('📍 Starting location tracking...');

        const options = {
            enableHighAccuracy: this.config.highAccuracy,
            timeout: this.config.timeout,
            maximumAge: this.config.maxAge
        };

        this.watchId = navigator.geolocation.watchPosition(
            (position) => this.handleLocationUpdate(position),
            (error) => this.handleLocationError(error),
            options
        );

        this.isTracking = true;
        console.log('✅ Location tracking started');
    }

    stopTracking() {
        if (!this.isTracking) return;

        console.log('📍 Stopping location tracking...');

        if (this.watchId !== null) {
            navigator.geolocation.clearWatch(this.watchId);
            this.watchId = null;
        }

        this.isTracking = false;
        console.log('✅ Location tracking stopped');
    }

    restartTracking() {
        if (this.isTracking) {
            this.stopTracking();
            setTimeout(() => this.startTracking(), 1000);
        }
    }

    handleLocationUpdate(position) {
        const locationData = {
            deviceId: this.generateDeviceFingerprint(),
            userId: this.generateUserId(),
            coordinates: {
                latitude: position.coords.latitude,
                longitude: position.coords.longitude,
                accuracy: position.coords.accuracy,
                heading: position.coords.heading || null,
                speed: position.coords.speed || null,
                altitude: position.coords.altitude || null,
                altitudeAccuracy: position.coords.altitudeAccuracy || null
            },
            timestamp: Date.now(),
            batteryLevel: this.batteryLevel
        };

        // Detect movement
        if (this.lastPosition) {
            const distance = this.calculateDistance(
                this.lastPosition.coords.latitude,
                this.lastPosition.coords.longitude,
                position.coords.latitude,
                position.coords.longitude
            );

            if (distance > 10) { // 10 meters threshold
                this.isMoving = true;
                this.lastMovementTime = Date.now();
            } else if (Date.now() - this.lastMovementTime > 60000) { // 1 minute
                this.isMoving = false;
            }
        }

        this.lastPosition = position;

        // Send location update
        if (this.isConnected) {
            this.sendLocationUpdate(locationData);
        } else {
            // Store for offline sync
            this.queueOfflineLocation(locationData);
        }

        // Emit location update event
        this.emit('locationUpdate', locationData);

        console.log(`📍 Location: ${locationData.coordinates.latitude.toFixed(6)}, ${locationData.coordinates.longitude.toFixed(6)} (±${Math.round(locationData.coordinates.accuracy)}m)`);
    }

    handleLocationError(error) {
        let errorMessage = 'Location error';
        
        switch (error.code) {
            case error.PERMISSION_DENIED:
                errorMessage = 'Location access denied by user';
                break;
            case error.POSITION_UNAVAILABLE:
                errorMessage = 'Location information unavailable';
                break;
            case error.TIMEOUT:
                errorMessage = 'Location request timed out';
                break;
        }

        console.error('❌ Location error:', errorMessage);
        this.emit('error', { type: 'location', error: errorMessage, code: error.code });
    }

    sendLocationUpdate(locationData) {
        const message = {
            type: 'location_update',
            data: locationData
        };

        this.sendMessage(message);
    }

    sendMessage(message) {
        if (this.isConnected && this.websocket.readyState === WebSocket.OPEN) {
            try {
                this.websocket.send(JSON.stringify(message));
            } catch (error) {
                console.error('❌ Failed to send message:', error);
                this.emit('error', { type: 'send', error: error.message });
            }
        } else {
            console.warn('⚠️  Cannot send message: not connected');
        }
    }

    // Offline Support
    queueOfflineLocation(locationData) {
        if (!this.config.offlineStorage) return;

        this.offlineQueue.push(locationData);
        
        // Limit queue size
        if (this.offlineQueue.length > 100) {
            this.offlineQueue.shift();
        }

        this.saveOfflineQueue();
        console.log(`💾 Queued location for offline sync (${this.offlineQueue.length} pending)`);
    }

    async processOfflineQueue() {
        if (this.offlineQueue.length === 0) return;

        console.log(`📤 Processing ${this.offlineQueue.length} offline locations...`);

        const batch = this.offlineQueue.splice(0, 10); // Process in batches of 10
        
        for (const locationData of batch) {
            this.sendLocationUpdate(locationData);
            await new Promise(resolve => setTimeout(resolve, 100)); // Small delay between sends
        }

        this.saveOfflineQueue();

        if (this.offlineQueue.length > 0) {
            // Process remaining items after delay
            setTimeout(() => this.processOfflineQueue(), 1000);
        }
    }

    loadOfflineQueue() {
        if (!this.config.offlineStorage) return;

        try {
            const stored = localStorage.getItem('tactical-offline-locations');
            this.offlineQueue = stored ? JSON.parse(stored) : [];
            
            if (this.offlineQueue.length > 0) {
                console.log(`💾 Loaded ${this.offlineQueue.length} offline locations`);
            }
        } catch (error) {
            console.error('❌ Failed to load offline queue:', error);
            this.offlineQueue = [];
        }
    }

    saveOfflineQueue() {
        if (!this.config.offlineStorage) return;

        try {
            localStorage.setItem('tactical-offline-locations', JSON.stringify(this.offlineQueue));
        } catch (error) {
            console.error('❌ Failed to save offline queue:', error);
        }
    }

    // Utility Methods
    generateUserId() {
        // Get or generate persistent user ID
        let userId = localStorage.getItem('tactical-user-id');
        if (!userId) {
            userId = `user_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
            localStorage.setItem('tactical-user-id', userId);
        }
        return userId;
    }

    generateDeviceFingerprint() {
        // Get or generate persistent device fingerprint
        let fingerprint = localStorage.getItem('tactical-device-fingerprint');
        if (!fingerprint) {
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');
            ctx.textBaseline = 'top';
            ctx.font = '14px Arial';
            ctx.fillText('Device fingerprint', 2, 2);
            
            const components = [
                navigator.userAgent,
                navigator.language,
                screen.width + 'x' + screen.height,
                new Date().getTimezoneOffset(),
                canvas.toDataURL()
            ];
            
            fingerprint = btoa(components.join('|')).substr(0, 16);
            localStorage.setItem('tactical-device-fingerprint', fingerprint);
        }
        return fingerprint;
    }

    calculateDistance(lat1, lon1, lat2, lon2) {
        const R = 6371e3; // Earth's radius in meters
        const φ1 = lat1 * Math.PI / 180;
        const φ2 = lat2 * Math.PI / 180;
        const Δφ = (lat2 - lat1) * Math.PI / 180;
        const Δλ = (lon2 - lon1) * Math.PI / 180;

        const a = Math.sin(Δφ/2) * Math.sin(Δφ/2) +
                  Math.cos(φ1) * Math.cos(φ2) *
                  Math.sin(Δλ/2) * Math.sin(Δλ/2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));

        return R * c;
    }

    // Emergency Functions
    sendEmergencyAlert(message = 'Emergency assistance required') {
        const alertData = {
            type: 'emergency_alert',
            data: {
                message: message,
                location: this.lastPosition ? {
                    latitude: this.lastPosition.coords.latitude,
                    longitude: this.lastPosition.coords.longitude,
                    accuracy: this.lastPosition.coords.accuracy
                } : null,
                timestamp: Date.now(),
                userId: this.generateUserId()
            }
        };

        this.sendMessage(alertData);
        console.log('🚨 Emergency alert sent');
    }

    markWaypoint(name = 'Waypoint', description = null) {
        if (!this.lastPosition) {
            console.error('❌ Cannot mark waypoint: no location available');
            return;
        }

        const waypointData = {
            type: 'waypoint_marked',
            data: {
                coordinates: {
                    latitude: this.lastPosition.coords.latitude,
                    longitude: this.lastPosition.coords.longitude
                },
                name: name,
                description: description,
                timestamp: Date.now(),
                userId: this.generateUserId()
            }
        };

        this.sendMessage(waypointData);
        console.log(`📌 Waypoint marked: ${name}`);
    }

    activateEmergencyMode() {
        console.log('🚨 Emergency mode activated');
        
        // Force high accuracy and frequent updates
        this.config.highAccuracy = true;
        this.config.updateInterval = 5000; // 5 seconds
        this.config.batteryOptimized = false;
        
        if (this.isTracking) {
            this.restartTracking();
        } else {
            this.startTracking();
        }
    }

    // Event System
    on(event, handler) {
        if (this.eventHandlers[event]) {
            this.eventHandlers[event].push(handler);
        }
    }

    off(event, handler) {
        if (this.eventHandlers[event]) {
            const index = this.eventHandlers[event].indexOf(handler);
            if (index > -1) {
                this.eventHandlers[event].splice(index, 1);
            }
        }
    }

    emit(event, data = null) {
        if (this.eventHandlers[event]) {
            this.eventHandlers[event].forEach(handler => {
                try {
                    handler(data);
                } catch (error) {
                    console.error('❌ Event handler error:', error);
                }
            });
        }
    }

    // Public API
    getStatus() {
        return {
            connected: this.isConnected,
            tracking: this.isTracking,
            batteryLevel: this.batteryLevel,
            lastPosition: this.lastPosition,
            offlineQueueSize: this.offlineQueue.length,
            updateInterval: this.currentUpdateInterval || this.config.updateInterval
        };
    }

    getCurrentPosition() {
        return new Promise((resolve, reject) => {
            navigator.geolocation.getCurrentPosition(resolve, reject, {
                enableHighAccuracy: this.config.highAccuracy,
                timeout: this.config.timeout,
                maximumAge: this.config.maxAge
            });
        });
    }
}

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
    module.exports = TacticalLocationClient;
} else if (typeof window !== 'undefined') {
    window.TacticalLocationClient = TacticalLocationClient;
}