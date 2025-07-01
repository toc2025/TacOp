// Tactical PWA Application Logic - Discrete System Utility
// Version: 2.1.4
// Handles authentication, location services, and tactical interface management

class TacticalApp {
    constructor() {
        this.coverMode = true;
        this.authSequence = [];
        this.validSequence = ['status', 'network', 'battery', 'storage'];
        this.tacticalInterface = null;
        this.locationService = null;
        this.websocket = null;
        this.currentUser = null;
        this.currentLocation = null;
        this.sessionTimeout = null;
        this.isAuthenticated = false;
        
        this.init();
    }

    async init() {
        console.log('System Utility v2.1.4 initializing...');
        
        // Register service worker
        await this.registerServiceWorker();
        
        // Initialize cover interface
        this.initializeCoverInterface();
        
        // Setup authentication handlers
        this.setupAuthenticationHandlers();
        
        // Initialize location service (but don't start tracking yet)
        this.locationService = new TacticalLocationService();
        
        // Update system info
        this.updateSystemInfo();
        
        // Setup periodic updates
        this.startPeriodicUpdates();
        
        console.log('System initialization complete');
    }

    async registerServiceWorker() {
        if ('serviceWorker' in navigator) {
            try {
                const registration = await navigator.serviceWorker.register('/service-worker.js');
                console.log('Service Worker registered:', registration.scope);
                
                // Handle service worker updates
                registration.addEventListener('updatefound', () => {
                    const newWorker = registration.installing;
                    newWorker.addEventListener('statechange', () => {
                        if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                            // New version available
                            this.showUpdateNotification();
                        }
                    });
                });
                
            } catch (error) {
                console.error('Service Worker registration failed:', error);
            }
        }
    }

    initializeCoverInterface() {
        // Setup cover page interactions
        const statusItems = document.querySelectorAll('.status-item');
        statusItems.forEach(item => {
            item.addEventListener('click', (e) => {
                this.handleAuthSequence(e.target.closest('.status-item').dataset.auth);
            });
        });

        // Setup tool buttons (non-functional for cover)
        const toolButtons = document.querySelectorAll('.tool-button');
        toolButtons.forEach(button => {
            button.addEventListener('click', () => {
                this.showGenericMessage('Feature not available in current mode');
            });
        });

        // Add subtle visual feedback
        this.addCoverInteractionEffects();
    }

    setupAuthenticationHandlers() {
        // Setup discrete authentication sequence
        let tapCount = 0;
        let tapTimer = null;
        
        // Triple-tap on title for emergency access
        const title = document.querySelector('h1');
        if (title) {
            title.addEventListener('click', () => {
                tapCount++;
                
                if (tapTimer) clearTimeout(tapTimer);
                
                tapTimer = setTimeout(() => {
                    if (tapCount === 3) {
                        this.showEmergencyAccess();
                    }
                    tapCount = 0;
                }, 1000);
            });
        }

        // Konami code alternative authentication
        this.setupKonamiCode();
    }

    handleAuthSequence(authType) {
        if (!this.coverMode) return;

        this.authSequence.push(authType);
        
        // Visual feedback
        this.showAuthFeedback(authType);
        
        // Check if sequence is getting too long
        if (this.authSequence.length > this.validSequence.length) {
            this.authSequence = [authType]; // Reset with current input
        }
        
        // Check if sequence matches
        if (this.authSequence.length === this.validSequence.length) {
            if (this.validateAuthSequence()) {
                this.activateTacticalMode();
            } else {
                this.resetAuthSequence();
            }
        }
    }

    validateAuthSequence() {
        return this.authSequence.every((item, index) => 
            item === this.validSequence[index]
        );
    }

    showAuthFeedback(authType) {
        const feedback = document.getElementById('auth-feedback');
        if (feedback) {
            feedback.textContent = `System check: ${authType}`;
            feedback.classList.add('show');
            
            setTimeout(() => {
                feedback.classList.remove('show');
            }, 1000);
        }
    }

    resetAuthSequence() {
        this.authSequence = [];
        this.showGenericMessage('System diagnostic complete');
    }

    async activateTacticalMode() {
        console.log('Activating tactical interface...');
        
        try {
            // Load tactical interface
            await this.loadTacticalInterface();
            
            // Initialize tactical services
            await this.initializeTacticalServices();
            
            // Switch to tactical mode
            this.coverMode = false;
            this.isAuthenticated = true;
            
            // Hide cover interface
            document.getElementById('cover-interface').classList.remove('active');
            
            // Show tactical interface
            document.getElementById('tactical-interface').classList.add('active');
            
            // Start session timeout
            this.startSessionTimeout();
            
            console.log('Tactical mode activated');
            
        } catch (error) {
            console.error('Failed to activate tactical mode:', error);
            this.showGenericMessage('System error occurred');
            this.resetAuthSequence();
        }
    }

    async loadTacticalInterface() {
        const tacticalContainer = document.getElementById('tactical-interface');
        
        if (!tacticalContainer.innerHTML.trim()) {
            try {
                const response = await fetch('/tactical-interface.html');
                if (!response.ok) throw new Error('Failed to load tactical interface');
                
                const html = await response.text();
                
                // Extract body content from the tactical interface HTML
                const parser = new DOMParser();
                const doc = parser.parseFromString(html, 'text/html');
                const bodyContent = doc.body.innerHTML;
                
                tacticalContainer.innerHTML = bodyContent;
                
                // Execute any scripts in the loaded content
                const scripts = tacticalContainer.querySelectorAll('script');
                scripts.forEach(script => {
                    const newScript = document.createElement('script');
                    newScript.textContent = script.textContent;
                    document.head.appendChild(newScript);
                });
                
            } catch (error) {
                throw new Error('Tactical interface unavailable');
            }
        }
    }

    async initializeTacticalServices() {
        // Initialize WebSocket connection to tactical server
        await this.connectToTacticalServer();
        
        // Start location tracking
        if (this.locationService) {
            await this.locationService.initialize();
        }
        
        // Setup tactical event handlers
        this.setupTacticalEventHandlers();
        
        // Load user profile
        this.currentUser = this.generateUserIdentifier();
    }

    async connectToTacticalServer() {
        try {
            // Initialize the new TacticalLocationClient
            if (!this.locationClient) {
                this.locationClient = new TacticalLocationClient({
                    serverUrl: 'wss://192.168.100.1:8443/tactical-location',
                    apiUrl: 'https://192.168.100.1:3002/api',
                    updateInterval: 30000,
                    batteryOptimized: true,
                    offlineStorage: true
                });

                // Setup event handlers
                this.locationClient.on('connected', () => {
                    console.log('Tactical server connection established');
                    this.updateConnectionStatus(true);
                });

                this.locationClient.on('disconnected', (data) => {
                    console.log('Tactical server connection closed:', data);
                    this.updateConnectionStatus(false);
                });

                this.locationClient.on('locationUpdate', (data) => {
                    this.handleLocationUpdate(data);
                });

                this.locationClient.on('teamUpdate', (data) => {
                    this.updateTeamStatus(data);
                });

                this.locationClient.on('emergencyAlert', (data) => {
                    this.handleEmergencyAlert(data);
                });

                this.locationClient.on('error', (error) => {
                    console.error('Location client error:', error);
                    this.showGenericMessage(`Connection error: ${error.error}`);
                });
            }

            // Connect to the tactical server
            await this.locationClient.connect();
            
        } catch (error) {
            console.error('Failed to connect to tactical server:', error);
            this.showGenericMessage('Failed to connect to tactical server');
        }
    }

    updateConnectionStatus(connected) {
        // Update UI to reflect connection status
        const statusElements = document.querySelectorAll('.network-status');
        statusElements.forEach(element => {
            if (connected) {
                element.textContent = 'ZeroTier: Connected';
                element.classList.add('online');
                element.classList.remove('offline');
            } else {
                element.textContent = 'ZeroTier: Disconnected';
                element.classList.add('offline');
                element.classList.remove('online');
            }
        });
    }

    handleLocationUpdate(locationData) {
        // Update current location in the app
        this.currentLocation = locationData.coordinates;
        
        // Update location display in UI
        this.updateLocationDisplay(locationData.coordinates);
        
        // Store for offline use if needed
        if (this.locationService) {
            this.locationService.lastPosition = {
                coords: locationData.coordinates,
                timestamp: locationData.timestamp
            };
        }
    }

    updateLocationDisplay(coordinates) {
        const locationElement = document.getElementById('current-location');
        if (locationElement && coordinates) {
            const lat = coordinates.latitude.toFixed(6);
            const lng = coordinates.longitude.toFixed(6);
            locationElement.textContent = `${lat}, ${lng}`;
            locationElement.className = 'location-active';
        }
    }

    handleTacticalMessage(message) {
        switch (message.type) {
            case 'team_update':
                this.updateTeamStatus(message.data);
                break;
            case 'mission_update':
                this.updateMissionInfo(message.data);
                break;
            case 'emergency_alert':
                this.handleEmergencyAlert(message.data);
                break;
            case 'system_command':
                this.handleSystemCommand(message.data);
                break;
            default:
                console.log('Unknown tactical message:', message);
        }
    }

    setupTacticalEventHandlers() {
        // Exit tactical mode handler
        const exitBtn = document.getElementById('exit-tactical');
        if (exitBtn) {
            exitBtn.addEventListener('click', () => {
                this.exitTacticalMode();
            });
        }
        
        // Location toggle handler
        const locationToggle = document.getElementById('location-toggle');
        if (locationToggle) {
            locationToggle.addEventListener('click', () => {
                this.toggleLocationTracking();
            });
        }
    }

    exitTacticalMode() {
        if (confirm('Exit tactical mode? This will return to system utility interface.')) {
            this.deactivateTacticalMode();
        }
    }

    deactivateTacticalMode() {
        console.log('Deactivating tactical mode...');
        
        // Stop location tracking using new location client
        if (this.locationClient) {
            this.locationClient.stopTracking();
            this.locationClient.disconnect();
        }
        
        // Stop legacy location service if it exists
        if (this.locationService) {
            this.locationService.stopTracking();
        }
        
        // Clear session timeout
        if (this.sessionTimeout) {
            clearTimeout(this.sessionTimeout);
            this.sessionTimeout = null;
        }
        
        // Reset state
        this.coverMode = true;
        this.isAuthenticated = false;
        this.authSequence = [];
        this.currentUser = null;
        
        // Switch interfaces
        document.getElementById('tactical-interface').classList.remove('active');
        document.getElementById('cover-interface').classList.add('active');
        
        // Clear sensitive data from memory
        this.clearSensitiveData();
        
        console.log('Returned to cover mode');
    }

    toggleLocationTracking() {
        if (this.locationClient) {
            if (this.locationClient.isTracking) {
                this.locationClient.stopTracking();
            } else {
                this.locationClient.startTracking();
            }
            
            // Update button state
            this.updateLocationButton();
        } else if (this.locationService) {
            // Fallback to legacy location service
            if (this.locationService.isTracking) {
                this.locationService.stopTracking();
            } else {
                this.locationService.startTracking();
            }
        }
    }

    updateLocationButton() {
        const btn = document.getElementById('location-toggle');
        if (btn && this.locationClient) {
            if (this.locationClient.isTracking) {
                btn.innerHTML = '<span class="control-icon">📍</span><span>Location ON</span>';
                btn.classList.add('location-active');
            } else {
                btn.innerHTML = '<span class="control-icon">📍</span><span>Location OFF</span>';
                btn.classList.remove('location-active');
            }
        }
    }

    startSessionTimeout() {
        // Auto-logout after 30 minutes of inactivity
        const TIMEOUT_DURATION = 30 * 60 * 1000; // 30 minutes
        
        const resetTimeout = () => {
            if (this.sessionTimeout) {
                clearTimeout(this.sessionTimeout);
            }
            
            this.sessionTimeout = setTimeout(() => {
                console.log('Session timeout - returning to cover mode');
                this.deactivateTacticalMode();
            }, TIMEOUT_DURATION);
        };
        
        // Reset timeout on user activity
        ['click', 'touchstart', 'keypress', 'scroll'].forEach(event => {
            document.addEventListener(event, resetTimeout, { passive: true });
        });
        
        resetTimeout();
    }

    updateSystemInfo() {
        // Update last updated time
        const lastUpdated = document.getElementById('last-updated');
        if (lastUpdated) {
            lastUpdated.textContent = new Date().toLocaleString();
        }
        
        // Update uptime (simulated)
        const uptime = document.getElementById('uptime');
        if (uptime) {
            const hours = Math.floor(Math.random() * 24) + 1;
            const minutes = Math.floor(Math.random() * 60);
            uptime.textContent = `${hours}h ${minutes}m`;
        }
    }

    startPeriodicUpdates() {
        // Update system info every 5 minutes
        setInterval(() => {
            if (this.coverMode) {
                this.updateSystemInfo();
            }
        }, 5 * 60 * 1000);
    }

    generateUserIdentifier() {
        // Generate a session-specific user identifier
        const timestamp = Date.now();
        const random = Math.random().toString(36).substr(2, 9);
        return `user_${timestamp}_${random}`;
    }

    generateDeviceFingerprint() {
        // Generate a device fingerprint for identification
        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d');
        ctx.textBaseline = 'top';
        ctx.font = '14px Arial';
        ctx.fillText('Device fingerprint', 2, 2);
        
        const fingerprint = [
            navigator.userAgent,
            navigator.language,
            screen.width + 'x' + screen.height,
            new Date().getTimezoneOffset(),
            canvas.toDataURL()
        ].join('|');
        
        return btoa(fingerprint).substr(0, 16);
    }

    showGenericMessage(message) {
        // Show non-suspicious system message
        const feedback = document.getElementById('auth-feedback');
        if (feedback) {
            feedback.textContent = message;
            feedback.classList.add('show');
            
            setTimeout(() => {
                feedback.classList.remove('show');
            }, 2000);
        }
    }

    showUpdateNotification() {
        if (confirm('System update available. Install now?')) {
            // Send message to service worker to skip waiting
            if (navigator.serviceWorker.controller) {
                navigator.serviceWorker.controller.postMessage({ type: 'SKIP_WAITING' });
            }
            
            // Reload page after service worker updates
            navigator.serviceWorker.addEventListener('controllerchange', () => {
                window.location.reload();
            });
        }
    }

    setupKonamiCode() {
        // Alternative authentication method
        const konamiCode = [
            'ArrowUp', 'ArrowUp', 'ArrowDown', 'ArrowDown',
            'ArrowLeft', 'ArrowRight', 'ArrowLeft', 'ArrowRight',
            'KeyB', 'KeyA'
        ];
        
        let konamiIndex = 0;
        
        document.addEventListener('keydown', (e) => {
            if (e.code === konamiCode[konamiIndex]) {
                konamiIndex++;
                if (konamiIndex === konamiCode.length) {
                    this.activateTacticalMode();
                    konamiIndex = 0;
                }
            } else {
                konamiIndex = 0;
            }
        });
    }

    showEmergencyAccess() {
        const password = prompt('Emergency access code:');
        if (password === 'TACTICAL_OVERRIDE_2025') {
            this.activateTacticalMode();
        } else if (password !== null) {
            this.showGenericMessage('Invalid access code');
        }
    }

    addCoverInteractionEffects() {
        // Add subtle visual feedback for cover interactions
        const statusItems = document.querySelectorAll('.status-item');
        statusItems.forEach(item => {
            item.addEventListener('mousedown', () => {
                item.style.transform = 'scale(0.98)';
            });
            
            item.addEventListener('mouseup', () => {
                item.style.transform = 'scale(1)';
            });
            
            item.addEventListener('mouseleave', () => {
                item.style.transform = 'scale(1)';
            });
        });
    }

    updateTeamStatus(teamData) {
        // Update team member status in tactical interface
        const teamMembers = document.querySelector('.team-members');
        if (teamMembers && teamData) {
            // Update team member information
            console.log('Team status updated:', teamData);
        }
    }

    updateMissionInfo(missionData) {
        // Update mission information
        if (missionData) {
            const operationName = document.getElementById('operation-name');
            const startTime = document.getElementById('start-time');
            const missionDuration = document.getElementById('mission-duration');
            const areaOperations = document.getElementById('area-operations');
            
            if (operationName) operationName.textContent = missionData.operation || 'TRAINING-ALPHA';
            if (startTime) startTime.textContent = missionData.startTime || '14:30 UTC';
            if (missionDuration) missionDuration.textContent = missionData.duration || '2h 15m';
            if (areaOperations) areaOperations.textContent = missionData.area || 'Sector 7-Alpha';
        }
    }

    handleEmergencyAlert(alertData) {
        // Handle emergency alerts
        if (alertData) {
            const alertMessage = `EMERGENCY ALERT: ${alertData.message || 'Team member needs assistance'}`;
            
            // Show prominent alert
            if (confirm(alertMessage + '\n\nAcknowledge alert?')) {
                // Send acknowledgment
                if (this.websocket && this.websocket.readyState === WebSocket.OPEN) {
                    this.websocket.send(JSON.stringify({
                        type: 'emergency_ack',
                        data: {
                            alertId: alertData.id,
                            userId: this.currentUser,
                            timestamp: Date.now()
                        }
                    }));
                }
            }
        }
    }

    handleSystemCommand(commandData) {
        // Handle system commands from tactical server
        switch (commandData.command) {
            case 'force_logout':
                this.deactivateTacticalMode();
                break;
            case 'update_location_interval':
                if (this.locationService) {
                    this.locationService.updateInterval(commandData.interval);
                }
                break;
            case 'emergency_mode':
                this.activateEmergencyMode();
                break;
            default:
                console.log('Unknown system command:', commandData);
        }
    }

    activateEmergencyMode() {
        // Activate emergency mode
        document.body.classList.add('emergency-mode');
        
        // Force location tracking on
        if (this.locationService) {
            this.locationService.startTracking();
        }
        
        console.log('Emergency mode activated');
    }

    clearSensitiveData() {
        // Clear any sensitive data from memory
        this.currentLocation = null;
        
        // Clear any cached tactical data
        if ('serviceWorker' in navigator && navigator.serviceWorker.controller) {
            navigator.serviceWorker.controller.postMessage({
                type: 'CLEAR_TACTICAL_CACHE'
            });
        }
    }
}

// Tactical Location Service Class
class TacticalLocationService {
    constructor() {
        this.isTracking = false;
        this.watchId = null;
        this.lastPosition = null;
        this.updateInterval = 30000; // 30 seconds default
        this.highAccuracy = true;
    }

    async initialize() {
        // Check if geolocation is available
        if (!navigator.geolocation) {
            throw new Error('Geolocation not supported');
        }
        
        // Request permission
        try {
            const permission = await navigator.permissions.query({ name: 'geolocation' });
            if (permission.state === 'denied') {
                throw new Error('Geolocation permission denied');
            }
        } catch (error) {
            console.warn('Could not check geolocation permission:', error);
        }
        
        console.log('Location service initialized');
    }

    startTracking() {
        if (this.isTracking) return;
        
        console.log('Starting location tracking...');
        
        const options = {
            enableHighAccuracy: this.highAccuracy,
            timeout: 10000,
            maximumAge: this.updateInterval
        };
        
        this.watchId = navigator.geolocation.watchPosition(
            (position) => this.handleLocationUpdate(position),
            (error) => this.handleLocationError(error),
            options
        );
        
        this.isTracking = true;
        this.updateLocationButton();
    }

    stopTracking() {
        if (!this.isTracking) return;
        
        console.log('Stopping location tracking...');
        
        if (this.watchId !== null) {
            navigator.geolocation.clearWatch(this.watchId);
            this.watchId = null;
        }
        
        this.isTracking = false;
        this.updateLocationButton();
    }

    handleLocationUpdate(position) {
        this.lastPosition = position;
        
        const locationData = {
            deviceId: window.tacticalApp.generateDeviceFingerprint(),
            userId: window.tacticalApp.currentUser,
            coordinates: {
                latitude: position.coords.latitude,
                longitude: position.coords.longitude,
                accuracy: position.coords.accuracy,
                heading: position.coords.heading || null,
                speed: position.coords.speed || null,
                altitude: position.coords.altitude || null
            },
            timestamp: Date.now()
        };
        
        // Update current location display
        this.updateLocationDisplay(locationData.coordinates);
        
        // Send to tactical server
        this.transmitLocation(locationData);
        
        // Store current location in app
        if (window.tacticalApp) {
            window.tacticalApp.currentLocation = locationData.coordinates;
        }
    }

    handleLocationError(error) {
        console.error('Location error:', error);
        
        let errorMessage = 'Location unavailable';
        switch (error.code) {
            case error.PERMISSION_DENIED:
                errorMessage = 'Location access denied';
                break;
            case error.POSITION_UNAVAILABLE:
                errorMessage = 'Location unavailable';
                break;
            case error.TIMEOUT:
                errorMessage = 'Location timeout';
                break;
        }
        
        this.updateLocationDisplay(null, errorMessage);
    }

    transmitLocation(locationData) {
        if (window.tacticalApp && window.tacticalApp.websocket) {
            const ws = window.tacticalApp.websocket;
            
            if (ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify({
                    type: 'location_update',
                    data: locationData
                }));
            } else {
                // Store for later transmission when connection is restored
                this.storeOfflineLocation(locationData);
            }
        }
    }

    updateLocationDisplay(coordinates, error = null) {
        const locationElement = document.getElementById('current-location');
        if (locationElement) {
            if (error) {
                locationElement.textContent = error;
                locationElement.className = 'location-error';
            } else if (coordinates) {
                const lat = coordinates.latitude.toFixed(6);
                const lng = coordinates.longitude.toFixed(6);
                locationElement.textContent = `${lat}, ${lng}`;
                locationElement.className = 'location-active';
            }
        }
    }

    updateLocationButton() {
        const btn = document.getElementById('location-toggle');
        if (btn) {
            if (this.isTracking) {
                btn.innerHTML = '<span class="control-icon">📍</span><span>Location ON</span>';
                btn.classList.add('location-active');
            } else {
                btn.innerHTML = '<span class="control-icon">📍</span><span>Location OFF</span>';
                btn.classList.remove('location-active');
            }
        }
    }

    updateInterval(newInterval) {
        this.updateInterval = newInterval;
        
        // Restart tracking with new interval if currently tracking
        if (this.isTracking) {
            this.stopTracking();
            setTimeout(() => this.startTracking(), 1000);
        }
    }

    markWaypoint(coordinates) {
        const waypoint = {
            type: 'waypoint',
            coordinates: coordinates,
            timestamp: Date.now(),
            userId: window.tacticalApp ? window.tacticalApp.currentUser : 'unknown'
        };
        
        // Send waypoint to server
        if (window.tacticalApp && window.tacticalApp.websocket) {
            window.tacticalApp.websocket.send(JSON.stringify({
                type: 'waypoint_marked',
                data: waypoint
            }));
        }
        
        console.log('Waypoint marked:', waypoint);
    }

    async storeOfflineLocation(locationData) {
        // Store location data for offline sync
        try {
            const storedLocations = await this.getStoredLocations();
            storedLocations.push(locationData);
            
            // Keep only last 100 locations to prevent storage bloat
            if (storedLocations.length > 100) {
                storedLocations.splice(0, storedLocations.length - 100);
            }
            
            await this.saveStoredLocations(storedLocations);
            
        } catch (error) {
            console.error('Failed to store offline location:', error);
        }
    }

    async getStoredLocations() {
        return new Promise((resolve) => {
            const stored = localStorage.getItem('tactical-offline-locations');
            resolve(stored ? JSON.parse(stored) : []);
        });
    }

    async saveStoredLocations(locations) {
        localStorage.setItem('tactical-offline-locations', JSON.stringify(locations));
    }
}

// Initialize the application when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.tacticalApp = new TacticalApp();
});

// Handle page visibility changes (security feature)
document.addEventListener('visibilitychange', () => {
    if (document.hidden && window.tacticalApp && !window.tacticalApp.coverMode) {
        // Optionally exit tactical mode when app is hidden
        console.log('App hidden - maintaining tactical mode');
    }
});

// Handle beforeunload to clean up sensitive data
window.addEventListener('beforeunload', () => {
    if (window.tacticalApp) {
        window.tacticalApp.clearSensitiveData();
    }
});

console.log('Tactical PWA Application loaded - System Utility v2.1.4');