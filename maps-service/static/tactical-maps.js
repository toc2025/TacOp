/**
 * Tactical Maps Interface
 * Interactive mapping system for tactical operations
 */

class TacticalMapsInterface {
    constructor() {
        this.map = null;
        this.teamLocations = new Map();
        this.waypoints = new Map();
        this.tacticalOverlays = new Map();
        this.measurementMode = null;
        this.followMode = false;
        this.nightVision = false;
        this.websocket = null;
        this.currentLocation = null;
        this.measurementPoints = [];
        
        // API endpoints
        this.apiBase = window.location.origin;
        this.mapsApiBase = `${this.apiBase}/api`;
        this.locationApiBase = 'http://localhost:3001/api';
        
        this.init();
    }

    async init() {
        try {
            await this.initializeMap();
            await this.loadInitialData();
            this.setupEventListeners();
            this.startRealTimeUpdates();
            this.hideLoadingOverlay();
            this.updateStatus('map-status', 'Ready');
        } catch (error) {
            console.error('Failed to initialize tactical maps:', error);
            this.updateStatus('map-status', 'Error');
        }
    }

    async initializeMap() {
        // Initialize MapLibre GL map
        this.map = new maplibregl.Map({
            container: 'map',
            style: `${this.mapsApiBase}/style/tactical`,
            center: [-122.4, 37.77], // Default to San Francisco
            zoom: 12,
            pitch: 0,
            bearing: 0,
            antialias: true
        });

        // Add map controls
        this.map.addControl(new maplibregl.NavigationControl(), 'bottom-right');
        this.map.addControl(new maplibregl.ScaleControl(), 'bottom-left');
        this.map.addControl(new maplibregl.GeolocateControl({
            positionOptions: {
                enableHighAccuracy: true
            },
            trackUserLocation: true,
            showUserHeading: true
        }), 'bottom-right');

        // Wait for map to load
        await new Promise((resolve) => {
            this.map.on('load', resolve);
        });

        // Add data sources
        this.addDataSources();
        this.addMapLayers();
        this.setupMapEventHandlers();
    }

    addDataSources() {
        // Team locations source
        this.map.addSource('team-locations', {
            type: 'geojson',
            data: {
                type: 'FeatureCollection',
                features: []
            }
        });

        // Waypoints source
        this.map.addSource('waypoints', {
            type: 'geojson',
            data: {
                type: 'FeatureCollection',
                features: []
            }
        });

        // Tactical overlays source
        this.map.addSource('tactical-overlays', {
            type: 'geojson',
            data: {
                type: 'FeatureCollection',
                features: []
            }
        });

        // Measurement source
        this.map.addSource('measurements', {
            type: 'geojson',
            data: {
                type: 'FeatureCollection',
                features: []
            }
        });
    }

    addMapLayers() {
        // Team location layers
        this.map.addLayer({
            id: 'team-locations-circle',
            type: 'circle',
            source: 'team-locations',
            paint: {
                'circle-radius': [
                    'case',
                    ['==', ['get', 'status'], 'active'], 12,
                    ['==', ['get', 'status'], 'inactive'], 8,
                    6
                ],
                'circle-color': [
                    'case',
                    ['==', ['get', 'status'], 'active'], '#00ff00',
                    ['==', ['get', 'status'], 'inactive'], '#ffaa00',
                    '#ff0000'
                ],
                'circle-stroke-color': '#ffffff',
                'circle-stroke-width': 2,
                'circle-opacity': 0.9
            }
        });

        this.map.addLayer({
            id: 'team-locations-label',
            type: 'symbol',
            source: 'team-locations',
            layout: {
                'text-field': ['get', 'callsign'],
                'text-font': ['Open Sans Bold'],
                'text-size': 12,
                'text-anchor': 'top',
                'text-offset': [0, 1.5]
            },
            paint: {
                'text-color': '#ffffff',
                'text-halo-color': '#000000',
                'text-halo-width': 2
            }
        });

        // Waypoint layers
        this.map.addLayer({
            id: 'waypoints-circle',
            type: 'circle',
            source: 'waypoints',
            paint: {
                'circle-radius': [
                    'case',
                    ['==', ['get', 'waypoint_type'], 'objective'], 10,
                    ['==', ['get', 'waypoint_type'], 'hazard'], 8,
                    6
                ],
                'circle-color': [
                    'case',
                    ['==', ['get', 'waypoint_type'], 'objective'], '#00ff00',
                    ['==', ['get', 'waypoint_type'], 'hazard'], '#ff0000',
                    ['==', ['get', 'waypoint_type'], 'checkpoint'], '#0000ff',
                    '#ffff00'
                ],
                'circle-stroke-color': '#000000',
                'circle-stroke-width': 2
            }
        });

        this.map.addLayer({
            id: 'waypoints-label',
            type: 'symbol',
            source: 'waypoints',
            layout: {
                'text-field': ['get', 'name'],
                'text-font': ['Open Sans Regular'],
                'text-size': 10,
                'text-anchor': 'top',
                'text-offset': [0, 1]
            },
            paint: {
                'text-color': '#ffff00',
                'text-halo-color': '#000000',
                'text-halo-width': 2
            }
        });

        // Tactical overlay layers
        this.map.addLayer({
            id: 'tactical-overlays-fill',
            type: 'fill',
            source: 'tactical-overlays',
            filter: ['==', '$type', 'Polygon'],
            paint: {
                'fill-color': [
                    'case',
                    ['==', ['get', 'overlay_type'], 'restricted'], '#ff000040',
                    ['==', ['get', 'overlay_type'], 'objective'], '#00ff0040',
                    ['==', ['get', 'overlay_type'], 'patrol'], '#0000ff40',
                    '#ffffff40'
                ],
                'fill-outline-color': [
                    'case',
                    ['==', ['get', 'overlay_type'], 'restricted'], '#ff0000',
                    ['==', ['get', 'overlay_type'], 'objective'], '#00ff00',
                    ['==', ['get', 'overlay_type'], 'patrol'], '#0000ff',
                    '#ffffff'
                ]
            }
        });

        this.map.addLayer({
            id: 'tactical-overlays-line',
            type: 'line',
            source: 'tactical-overlays',
            filter: ['==', '$type', 'LineString'],
            paint: {
                'line-color': [
                    'case',
                    ['==', ['get', 'overlay_type'], 'route'], '#ffff00',
                    ['==', ['get', 'overlay_type'], 'boundary'], '#ff0000',
                    '#ffffff'
                ],
                'line-width': 3,
                'line-dasharray': [2, 2]
            }
        });

        // Measurement layers
        this.map.addLayer({
            id: 'measurements-line',
            type: 'line',
            source: 'measurements',
            paint: {
                'line-color': '#ff00ff',
                'line-width': 2,
                'line-dasharray': [5, 5]
            }
        });

        this.map.addLayer({
            id: 'measurements-points',
            type: 'circle',
            source: 'measurements',
            paint: {
                'circle-radius': 4,
                'circle-color': '#ff00ff',
                'circle-stroke-color': '#ffffff',
                'circle-stroke-width': 1
            }
        });
    }

    setupMapEventHandlers() {
        // Mouse move for coordinates display
        this.map.on('mousemove', (e) => {
            const coords = e.lngLat;
            document.getElementById('cursor-coords').textContent = 
                `${coords.lat.toFixed(6)}, ${coords.lng.toFixed(6)}`;
        });

        // Zoom change
        this.map.on('zoom', () => {
            const zoom = this.map.getZoom();
            document.getElementById('zoom-level').textContent = zoom.toFixed(1);
            
            // Update scale
            const scale = this.calculateScale(zoom);
            document.getElementById('map-scale').textContent = `1:${scale.toLocaleString()}`;
        });

        // Click handlers for interactive features
        this.map.on('click', 'team-locations-circle', (e) => {
            this.showTeamLocationPopup(e);
        });

        this.map.on('click', 'waypoints-circle', (e) => {
            this.showWaypointPopup(e);
        });

        // Map click for adding waypoints or measurements
        this.map.on('click', (e) => {
            if (this.measurementMode) {
                this.addMeasurementPoint(e.lngLat);
            }
        });

        // Change cursor on hover
        this.map.on('mouseenter', 'team-locations-circle', () => {
            this.map.getCanvas().style.cursor = 'pointer';
        });

        this.map.on('mouseleave', 'team-locations-circle', () => {
            this.map.getCanvas().style.cursor = '';
        });
    }

    setupEventListeners() {
        // Control button event listeners
        document.getElementById('toggle-team-locations').addEventListener('click', () => {
            this.toggleLayer('team-locations');
        });

        document.getElementById('toggle-waypoints').addEventListener('click', () => {
            this.toggleLayer('waypoints');
        });

        document.getElementById('toggle-tactical-overlays').addEventListener('click', () => {
            this.toggleLayer('tactical-overlays');
        });

        document.getElementById('add-waypoint').addEventListener('click', () => {
            this.enableWaypointMode();
        });

        document.getElementById('measure-distance').addEventListener('click', () => {
            this.enableMeasurementMode('distance');
        });

        document.getElementById('measure-area').addEventListener('click', () => {
            this.enableMeasurementMode('area');
        });

        document.getElementById('center-team').addEventListener('click', () => {
            this.centerOnTeam();
        });

        document.getElementById('follow-mode').addEventListener('click', () => {
            this.toggleFollowMode();
        });

        document.getElementById('night-vision').addEventListener('click', () => {
            this.toggleNightVision();
        });

        document.getElementById('refresh-data').addEventListener('click', () => {
            this.refreshAllData();
        });

        // Waypoint form handlers
        document.getElementById('waypoint-form-element').addEventListener('submit', (e) => {
            e.preventDefault();
            this.submitWaypoint();
        });

        document.getElementById('cancel-waypoint').addEventListener('click', () => {
            this.hideWaypointForm();
        });

        // Update time
        setInterval(() => {
            this.updateCurrentTime();
        }, 1000);
    }

    async loadInitialData() {
        try {
            // Load team locations
            await this.loadTeamLocations();
            
            // Load waypoints
            await this.loadWaypoints();
            
            // Load tactical overlays
            await this.loadTacticalOverlays();
            
            this.updateStatus('connection-status', 'Connected');
        } catch (error) {
            console.error('Failed to load initial data:', error);
            this.updateStatus('connection-status', 'Error');
        }
    }

    async loadTeamLocations() {
        try {
            const response = await fetch(`${this.mapsApiBase}/team-locations`);
            const data = await response.json();
            
            this.map.getSource('team-locations').setData(data);
            this.updateTeamPanel(data.features);
        } catch (error) {
            console.error('Failed to load team locations:', error);
        }
    }

    async loadWaypoints() {
        try {
            const response = await fetch(`${this.mapsApiBase}/waypoints`);
            const waypoints = await response.json();
            
            const geojson = {
                type: 'FeatureCollection',
                features: waypoints.map(wp => ({
                    type: 'Feature',
                    geometry: wp.location,
                    properties: {
                        id: wp.id,
                        name: wp.name,
                        description: wp.description,
                        waypoint_type: wp.waypoint_type,
                        symbol: wp.symbol,
                        color: wp.color,
                        created_by: wp.created_by,
                        team_id: wp.team_id
                    }
                }))
            };
            
            this.map.getSource('waypoints').setData(geojson);
        } catch (error) {
            console.error('Failed to load waypoints:', error);
        }
    }

    async loadTacticalOverlays() {
        try {
            const response = await fetch(`${this.mapsApiBase}/overlays`);
            const overlays = await response.json();
            
            const geojson = {
                type: 'FeatureCollection',
                features: overlays.map(overlay => ({
                    type: 'Feature',
                    geometry: overlay.geometry,
                    properties: {
                        id: overlay.id,
                        name: overlay.name,
                        description: overlay.description,
                        overlay_type: overlay.overlay_type,
                        style: overlay.style,
                        created_by: overlay.created_by,
                        team_id: overlay.team_id
                    }
                }))
            };
            
            this.map.getSource('tactical-overlays').setData(geojson);
        } catch (error) {
            console.error('Failed to load tactical overlays:', error);
        }
    }

    startRealTimeUpdates() {
        // WebSocket connection for real-time updates
        const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${wsProtocol}//${window.location.host}/ws`;
        
        this.websocket = new WebSocket(wsUrl);
        
        this.websocket.onopen = () => {
            console.log('WebSocket connected');
            this.updateStatus('connection-status', 'Connected (Live)');
        };
        
        this.websocket.onmessage = (event) => {
            const message = JSON.parse(event.data);
            this.handleRealTimeUpdate(message);
        };
        
        this.websocket.onclose = () => {
            console.log('WebSocket disconnected');
            this.updateStatus('connection-status', 'Disconnected');
            
            // Attempt to reconnect after 5 seconds
            setTimeout(() => {
                this.startRealTimeUpdates();
            }, 5000);
        };
        
        this.websocket.onerror = (error) => {
            console.error('WebSocket error:', error);
            this.updateStatus('connection-status', 'Error');
        };

        // Periodic data refresh as fallback
        setInterval(() => {
            this.loadTeamLocations();
        }, 30000); // Every 30 seconds
    }

    handleRealTimeUpdate(message) {
        switch (message.type) {
            case 'location_update':
                this.updateTeamLocation(message.data);
                break;
            case 'waypoint_update':
                this.handleWaypointUpdate(message);
                break;
            case 'overlay_update':
                this.handleOverlayUpdate(message);
                break;
            case 'emergency_alert':
                this.handleEmergencyAlert(message.data);
                break;
        }
    }

    updateTeamLocation(locationData) {
        // Update team location on map
        this.loadTeamLocations();
    }

    handleWaypointUpdate(message) {
        // Refresh waypoints when updated
        this.loadWaypoints();
    }

    handleOverlayUpdate(message) {
        // Refresh overlays when updated
        this.loadTacticalOverlays();
    }

    handleEmergencyAlert(alertData) {
        // Show emergency alert
        alert(`EMERGENCY ALERT from ${alertData.userId}\nLocation: ${alertData.location?.lat}, ${alertData.location?.lng}`);
        
        // Flash the map or show visual indicator
        this.flashEmergencyIndicator();
    }

    toggleLayer(layerType) {
        const button = document.getElementById(`toggle-${layerType}`);
        const isVisible = button.classList.contains('active');
        
        const layerIds = this.getLayerIds(layerType);
        
        layerIds.forEach(layerId => {
            this.map.setLayoutProperty(layerId, 'visibility', isVisible ? 'none' : 'visible');
        });
        
        button.classList.toggle('active');
    }

    getLayerIds(layerType) {
        switch (layerType) {
            case 'team-locations':
                return ['team-locations-circle', 'team-locations-label'];
            case 'waypoints':
                return ['waypoints-circle', 'waypoints-label'];
            case 'tactical-overlays':
                return ['tactical-overlays-fill', 'tactical-overlays-line'];
            default:
                return [];
        }
    }

    enableWaypointMode() {
        this.map.getCanvas().style.cursor = 'crosshair';
        
        // Add click handler for waypoint placement
        const clickHandler = (e) => {
            this.showWaypointForm(e.lngLat);
            this.map.off('click', clickHandler);
            this.map.getCanvas().style.cursor = '';
        };
        
        this.map.on('click', clickHandler);
    }

    showWaypointForm(coordinates) {
        const form = document.getElementById('waypoint-form');
        const coordsInput = document.getElementById('waypoint-coordinates');
        
        coordsInput.value = `${coordinates.lat.toFixed(6)}, ${coordinates.lng.toFixed(6)}`;
        form.style.display = 'block';
        
        // Store coordinates for form submission
        this.pendingWaypointCoords = coordinates;
    }

    hideWaypointForm() {
        document.getElementById('waypoint-form').style.display = 'none';
        document.getElementById('waypoint-form-element').reset();
        this.pendingWaypointCoords = null;
    }

    async submitWaypoint() {
        const name = document.getElementById('waypoint-name').value;
        const type = document.getElementById('waypoint-type').value;
        const description = document.getElementById('waypoint-description').value;
        
        if (!this.pendingWaypointCoords) {
            alert('No coordinates selected');
            return;
        }
        
        const waypointData = {
            name,
            description,
            location: {
                type: 'Point',
                coordinates: [this.pendingWaypointCoords.lng, this.pendingWaypointCoords.lat]
            },
            waypointType: type,
            createdBy: 'current_user', // TODO: Get from auth
            teamId: 'current_team' // TODO: Get from context
        };
        
        try {
            const response = await fetch(`${this.mapsApiBase}/waypoints`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(waypointData)
            });
            
            if (response.ok) {
                this.hideWaypointForm();
                this.loadWaypoints(); // Refresh waypoints
            } else {
                alert('Failed to create waypoint');
            }
        } catch (error) {
            console.error('Error creating waypoint:', error);
            alert('Error creating waypoint');
        }
    }

    enableMeasurementMode(type) {
        this.measurementMode = type;
        this.measurementPoints = [];
        this.map.getCanvas().style.cursor = 'crosshair';
        
        // Update button state
        document.querySelectorAll('.control-btn').forEach(btn => btn.classList.remove('active'));
        document.getElementById(`measure-${type}`).classList.add('active');
        
        // Show measurement display
        document.getElementById('measurement-display').style.display = 'block';
        document.getElementById('measurement-result').textContent = `Click to start ${type} measurement`;
    }

    addMeasurementPoint(coordinates) {
        this.measurementPoints.push([coordinates.lng, coordinates.lat]);
        
        if (this.measurementMode === 'distance') {
            this.updateDistanceMeasurement();
        } else if (this.measurementMode === 'area') {
            this.updateAreaMeasurement();
        }
        
        this.updateMeasurementDisplay();
    }

    updateDistanceMeasurement() {
        if (this.measurementPoints.length >= 2) {
            const line = {
                type: 'FeatureCollection',
                features: [{
                    type: 'Feature',
                    geometry: {
                        type: 'LineString',
                        coordinates: this.measurementPoints
                    }
                }]
            };
            
            this.map.getSource('measurements').setData(line);
            
            // Calculate total distance
            let totalDistance = 0;
            for (let i = 1; i < this.measurementPoints.length; i++) {
                totalDistance += this.calculateDistance(
                    this.measurementPoints[i - 1],
                    this.measurementPoints[i]
                );
            }
            
            document.getElementById('measurement-result').textContent = 
                `Distance: ${this.formatDistance(totalDistance)}`;
        }
    }

    updateAreaMeasurement() {
        if (this.measurementPoints.length >= 3) {
            // Close the polygon
            const closedPoints = [...this.measurementPoints, this.measurementPoints[0]];
            
            const polygon = {
                type: 'FeatureCollection',
                features: [{
                    type: 'Feature',
                    geometry: {
                        type: 'Polygon',
                        coordinates: [closedPoints]
                    }
                }]
            };
            
            this.map.getSource('measurements').setData(polygon);
            
            // Calculate area
            const area = this.calculatePolygonArea(this.measurementPoints);
            document.getElementById('measurement-result').textContent = 
                `Area: ${this.formatArea(area)}`;
        }
    }

    centerOnTeam() {
        const teamSource = this.map.getSource('team-locations');
        const data = teamSource._data;
        
        if (data.features.length > 0) {
            const bounds = new maplibregl.LngLatBounds();
            
            data.features.forEach(feature => {
                bounds.extend(feature.geometry.coordinates);
            });
            
            this.map.fitBounds(bounds, { padding: 50 });
        }
    }

    toggleFollowMode() {
        this.followMode = !this.followMode;
        const button = document.getElementById('follow-mode');
        
        if (this.followMode) {
            button.classList.add('active');
            this.startFollowMode();
        } else {
            button.classList.remove('active');
            this.stopFollowMode();
        }
    }

    toggleNightVision() {
        this.nightVision = !this.nightVision;
        const button = document.getElementById('night-vision');
        
        if (this.nightVision) {
            button.classList.add('active');
            // Apply night vision filter
            this.map.setPaintProperty('background', 'background-color', '#001100');
        } else {
            button.classList.remove('active');
            // Remove night vision filter
            this.map.setPaintProperty('background', 'background-color', '#1a1a1a');
        }
    }

    async refreshAllData() {
        this.updateStatus('map-status', 'Refreshing...');
        
        try {
            await Promise.all([
                this.loadTeamLocations(),
                this.loadWaypoints(),
                this.loadTacticalOverlays()
            ]);
            
            this.updateStatus('map-status', 'Ready');
        } catch (error) {
            console.error('Failed to refresh data:', error);
            this.updateStatus('map-status', 'Error');
        }
    }

    updateTeamPanel(teamFeatures) {
        const panel = document.getElementById('team-members');
        panel.innerHTML = '';
        
        teamFeatures.forEach(feature => {
            const props = feature.properties;
            const memberDiv = document.createElement('div');
            memberDiv.className = `team-member ${props.status}`;
            
            memberDiv.innerHTML = `
                <div class="member-indicator ${props.status}"></div>
                <div class="member-info">
                    <div class="member-name">${props.callsign}</div>
                    <div class="member-coords">${feature.geometry.coordinates[1].toFixed(4)}, ${feature.geometry.coordinates[0].toFixed(4)}</div>
                    <div class="member-time">${this.formatTimestamp(props.timestamp)}</div>
                </div>
            `;
            
            panel.appendChild(memberDiv);
        });
    }

    showTeamLocationPopup(e) {
        const feature = e.features[0];
        const props = feature.properties;
        
        const popup = new maplibregl.Popup()
            .setLngLat(e.lngLat)
            .setHTML(`
                <div class="popup-content">
                    <h4>${props.callsign}</h4>
                    <p><strong>Status:</strong> ${props.status}</p>
                    <p><strong>Team:</strong> ${props.teamId}</p>
                    <p><strong>Last Update:</strong> ${this.formatTimestamp(props.timestamp)}</p>
                    <p><strong>Accuracy:</strong> ${props.accuracy}m</p>
                </div>
            `)
            .addTo(this.map);
    }

    showWaypointPopup(e) {
        const feature = e.features[0];
        const props = feature.properties;
        
        const popup = new maplibregl.Popup()
            .setLngLat(e.lngLat)
            .setHTML(`
                <div class="popup-content">
                    <h4>${props.name}</h4>
                    <p><strong>Type:</strong> ${props.waypoint_type}</p>
                    <p><strong>Description:</strong> ${props.description || 'None'}</p>
                    <p><strong>Created by:</strong> ${props.created_by}</p>
                    <button onclick="tacticalMaps.deleteWaypoint('${props.id}')">Delete</button>
                </div>
            `)
            .addTo(this.map);
    }

    async deleteWaypoint(waypointId) {
        if (confirm('Delete this waypoint?')) {
            try {
                const response = await fetch(`${this.mapsApiBase}/waypoints/${waypointId}`, {
                    method: 'DELETE'
                });
                
                if (response.ok) {
                    this.loadWaypoints(); // Refresh waypoints
                } else {
                    alert('Failed to delete waypoint');
                }
            } catch (error) {
                console.error('Error deleting waypoint:', error);
                alert('Error deleting waypoint');
            }
        }
    }

    // Utility functions
    calculateDistance(coord1, coord2) {
        const R = 6371000; // Earth's radius in meters
        const lat1 = coord1[1] * Math.PI / 180;
        const lat2 = coord2[1] * Math.PI / 180;
        const deltaLat = (coord2[1] - coord1[1]) * Math.PI / 180;
        const deltaLng = (coord2[0] - coord1[0]) * Math.PI / 180;
        
        const a = Math.sin(deltaLat / 2) * Math.sin(deltaLat / 2) +
                  Math.cos(lat1) * Math.cos(lat2) *
                  Math.sin(deltaLng / 2) * Math.sin(deltaLng / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        
        return R * c;
    }

    calculatePolygonArea(coordinates) {
        // Shoelace formula for polygon area
        let area = 0;
        const n = coordinates.length;
        
        for (let i = 0; i < n; i++) {
            const j = (i + 1) % n;
            area += coordinates[i][0] * coordinates[j][1];
            area -= coordinates[j][0] * coordinates[i][1];
        }
        
        return Math.abs(area) / 2;
    }

    calculateScale(zoom) {
        // Approximate scale calculation
        const earthCircumference = 40075017; // meters
        const tileSize = 512;
        return earthCircumference * Math.cos(this.map.getCenter().lat * Math.PI / 180) / (tileSize * Math.pow(2, zoom));
    }

    formatDistance(meters) {
        if (meters < 1000) {
            return `${meters.toFixed(1)}m`;
        } else {
            return `${(meters / 1000).toFixed(2)}km`;
        }
    }

    formatArea(squareMeters) {
        if (squareMeters < 10000) {
            return `${squareMeters.toFixed(1)}m²`;
        } else {
            return `${(squareMeters / 10000).toFixed(2)}ha`;
        }
    }

    formatTimestamp(timestamp) {
        const date = new Date(timestamp);
        const now = new Date();
        const diff = now - date;
        
        if (diff < 60000) {
            return 'Just now';
        } else if (diff < 3600000) {
            return `${Math.floor(diff / 60000)}m ago`;
        } else {
            return date.toLocaleTimeString();
        }
    }

    updateCurrentTime() {
        const now = new Date();
        document.getElementById('current-time').textContent =
            now.toLocaleTimeString('en-US', {
                hour12: false,
                timeZone: 'UTC',
                timeZoneName: 'short'
            });
    }

    updateStatus(elementId, status) {
        const element = document.getElementById(elementId);
        if (element) {
            element.textContent = status;
        }
    }

    hideLoadingOverlay() {
        const overlay = document.getElementById('loading-overlay');
        if (overlay) {
            overlay.style.display = 'none';
        }
    }

    flashEmergencyIndicator() {
        // Flash the map border red for emergency alert
        const mapContainer = document.querySelector('.map-container');
        mapContainer.style.border = '3px solid #ff0000';
        mapContainer.style.boxShadow = '0 0 20px #ff0000';
        
        setTimeout(() => {
            mapContainer.style.border = '';
            mapContainer.style.boxShadow = '';
        }, 3000);
    }

    startFollowMode() {
        // Implementation for following team members
        console.log('Follow mode enabled');
    }

    stopFollowMode() {
        // Implementation for stopping follow mode
        console.log('Follow mode disabled');
    }

    updateMeasurementDisplay() {
        // Update the measurement display with current points
        const display = document.getElementById('measurement-display');
        if (this.measurementPoints.length > 0) {
            display.style.display = 'block';
        }
    }
}

// Initialize the tactical maps interface when the page loads
let tacticalMaps;
document.addEventListener('DOMContentLoaded', () => {
    tacticalMaps = new TacticalMapsInterface();
});

// Make tacticalMaps available globally for popup callbacks
window.tacticalMaps = tacticalMaps;