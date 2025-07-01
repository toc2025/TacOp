const axios = require('axios');
const turf = require('@turf/turf');

class TacticalMaps {
    constructor(db, redis, logger, config) {
        this.db = db;
        this.redis = redis;
        this.logger = logger;
        this.config = config;
        this.locationServiceUrl = 'http://location-service:3001';
    }

    /**
     * Get waypoints with optional filtering
     */
    async getWaypoints(filters = {}) {
        try {
            let query = `
                SELECT id, name, description, 
                       ST_AsGeoJSON(location) as location,
                       waypoint_type, symbol, color, created_by, team_id, mission_id,
                       created_at, updated_at, expires_at, status, metadata
                FROM waypoints 
                WHERE status = 'active'
            `;
            const params = [];
            let paramIndex = 1;

            // Add filters
            if (filters.teamId) {
                query += ` AND team_id = $${paramIndex}`;
                params.push(filters.teamId);
                paramIndex++;
            }

            if (filters.missionId) {
                query += ` AND mission_id = $${paramIndex}`;
                params.push(filters.missionId);
                paramIndex++;
            }

            if (filters.bounds) {
                const bounds = JSON.parse(filters.bounds);
                query += ` AND ST_Within(location, ST_MakeEnvelope($${paramIndex}, $${paramIndex + 1}, $${paramIndex + 2}, $${paramIndex + 3}, 4326))`;
                params.push(bounds[0], bounds[1], bounds[2], bounds[3]);
                paramIndex += 4;
            }

            if (filters.waypointType) {
                query += ` AND waypoint_type = $${paramIndex}`;
                params.push(filters.waypointType);
                paramIndex++;
            }

            query += ' ORDER BY created_at DESC';

            const result = await this.db.query(query, params);
            
            return result.rows.map(row => ({
                ...row,
                location: JSON.parse(row.location)
            }));
        } catch (error) {
            this.logger.error('Error getting waypoints:', error);
            throw error;
        }
    }

    /**
     * Create a new waypoint
     */
    async createWaypoint(waypointData) {
        try {
            const {
                name, description, location, waypointType = 'general',
                symbol, color = '#FFFF00', createdBy, teamId, missionId,
                expiresAt, metadata = {}
            } = waypointData;

            // Validate location
            if (!location || !location.coordinates || location.coordinates.length !== 2) {
                throw new Error('Invalid location coordinates');
            }

            const result = await this.db.query(`
                INSERT INTO waypoints (
                    name, description, location, waypoint_type, symbol, color,
                    created_by, team_id, mission_id, expires_at, metadata
                )
                VALUES ($1, $2, ST_SetSRID(ST_MakePoint($3, $4), 4326), $5, $6, $7, $8, $9, $10, $11, $12)
                RETURNING id, name, description, 
                          ST_AsGeoJSON(location) as location,
                          waypoint_type, symbol, color, created_by, team_id, mission_id,
                          created_at, updated_at, expires_at, status, metadata
            `, [
                name, description, location.coordinates[0], location.coordinates[1],
                waypointType, symbol, color, createdBy, teamId, missionId,
                expiresAt, JSON.stringify(metadata)
            ]);

            const waypoint = {
                ...result.rows[0],
                location: JSON.parse(result.rows[0].location)
            };

            // Broadcast waypoint creation to team members
            await this.broadcastWaypointUpdate('created', waypoint);

            this.logger.info(`Created waypoint: ${waypoint.id}`);
            return waypoint;
        } catch (error) {
            this.logger.error('Error creating waypoint:', error);
            throw error;
        }
    }

    /**
     * Update an existing waypoint
     */
    async updateWaypoint(waypointId, updateData) {
        try {
            const {
                name, description, location, waypointType,
                symbol, color, expiresAt, metadata
            } = updateData;

            let query = 'UPDATE waypoints SET updated_at = CURRENT_TIMESTAMP';
            const params = [];
            let paramIndex = 1;

            if (name !== undefined) {
                query += `, name = $${paramIndex}`;
                params.push(name);
                paramIndex++;
            }

            if (description !== undefined) {
                query += `, description = $${paramIndex}`;
                params.push(description);
                paramIndex++;
            }

            if (location && location.coordinates) {
                query += `, location = ST_SetSRID(ST_MakePoint($${paramIndex}, $${paramIndex + 1}), 4326)`;
                params.push(location.coordinates[0], location.coordinates[1]);
                paramIndex += 2;
            }

            if (waypointType !== undefined) {
                query += `, waypoint_type = $${paramIndex}`;
                params.push(waypointType);
                paramIndex++;
            }

            if (symbol !== undefined) {
                query += `, symbol = $${paramIndex}`;
                params.push(symbol);
                paramIndex++;
            }

            if (color !== undefined) {
                query += `, color = $${paramIndex}`;
                params.push(color);
                paramIndex++;
            }

            if (expiresAt !== undefined) {
                query += `, expires_at = $${paramIndex}`;
                params.push(expiresAt);
                paramIndex++;
            }

            if (metadata !== undefined) {
                query += `, metadata = $${paramIndex}`;
                params.push(JSON.stringify(metadata));
                paramIndex++;
            }

            query += ` WHERE id = $${paramIndex} AND status = 'active'`;
            params.push(waypointId);

            query += ` RETURNING id, name, description, 
                       ST_AsGeoJSON(location) as location,
                       waypoint_type, symbol, color, created_by, team_id, mission_id,
                       created_at, updated_at, expires_at, status, metadata`;

            const result = await this.db.query(query, params);

            if (result.rows.length === 0) {
                throw new Error('Waypoint not found or already deleted');
            }

            const waypoint = {
                ...result.rows[0],
                location: JSON.parse(result.rows[0].location)
            };

            // Broadcast waypoint update to team members
            await this.broadcastWaypointUpdate('updated', waypoint);

            this.logger.info(`Updated waypoint: ${waypointId}`);
            return waypoint;
        } catch (error) {
            this.logger.error('Error updating waypoint:', error);
            throw error;
        }
    }

    /**
     * Delete a waypoint
     */
    async deleteWaypoint(waypointId) {
        try {
            const result = await this.db.query(`
                UPDATE waypoints 
                SET status = 'deleted', updated_at = CURRENT_TIMESTAMP
                WHERE id = $1 AND status = 'active'
                RETURNING team_id, mission_id
            `, [waypointId]);

            if (result.rows.length === 0) {
                throw new Error('Waypoint not found or already deleted');
            }

            // Broadcast waypoint deletion to team members
            await this.broadcastWaypointUpdate('deleted', { 
                id: waypointId, 
                teamId: result.rows[0].team_id,
                missionId: result.rows[0].mission_id
            });

            this.logger.info(`Deleted waypoint: ${waypointId}`);
        } catch (error) {
            this.logger.error('Error deleting waypoint:', error);
            throw error;
        }
    }

    /**
     * Get tactical overlays with optional filtering
     */
    async getTacticalOverlays(filters = {}) {
        try {
            let query = `
                SELECT id, name, description, 
                       ST_AsGeoJSON(geometry) as geometry,
                       overlay_type, style, created_by, team_id, mission_id,
                       created_at, updated_at, expires_at, status, metadata
                FROM tactical_overlays 
                WHERE status = 'active'
            `;
            const params = [];
            let paramIndex = 1;

            // Add filters
            if (filters.teamId) {
                query += ` AND team_id = $${paramIndex}`;
                params.push(filters.teamId);
                paramIndex++;
            }

            if (filters.missionId) {
                query += ` AND mission_id = $${paramIndex}`;
                params.push(filters.missionId);
                paramIndex++;
            }

            if (filters.bounds) {
                const bounds = JSON.parse(filters.bounds);
                query += ` AND ST_Intersects(geometry, ST_MakeEnvelope($${paramIndex}, $${paramIndex + 1}, $${paramIndex + 2}, $${paramIndex + 3}, 4326))`;
                params.push(bounds[0], bounds[1], bounds[2], bounds[3]);
                paramIndex += 4;
            }

            if (filters.overlayType) {
                query += ` AND overlay_type = $${paramIndex}`;
                params.push(filters.overlayType);
                paramIndex++;
            }

            query += ' ORDER BY created_at DESC';

            const result = await this.db.query(query, params);
            
            return result.rows.map(row => ({
                ...row,
                geometry: JSON.parse(row.geometry)
            }));
        } catch (error) {
            this.logger.error('Error getting tactical overlays:', error);
            throw error;
        }
    }

    /**
     * Create a new tactical overlay
     */
    async createTacticalOverlay(overlayData) {
        try {
            const {
                name, description, geometry, overlayType,
                style = {}, createdBy, teamId, missionId,
                expiresAt, metadata = {}
            } = overlayData;

            // Validate geometry
            if (!geometry || !geometry.type || !geometry.coordinates) {
                throw new Error('Invalid geometry');
            }

            // Convert GeoJSON to PostGIS geometry
            const geomQuery = 'ST_SetSRID(ST_GeomFromGeoJSON($1), 4326)';

            const result = await this.db.query(`
                INSERT INTO tactical_overlays (
                    name, description, geometry, overlay_type, style,
                    created_by, team_id, mission_id, expires_at, metadata
                )
                VALUES ($1, $2, ${geomQuery}, $3, $4, $5, $6, $7, $8, $9)
                RETURNING id, name, description, 
                          ST_AsGeoJSON(geometry) as geometry,
                          overlay_type, style, created_by, team_id, mission_id,
                          created_at, updated_at, expires_at, status, metadata
            `, [
                name, description, JSON.stringify(geometry), overlayType,
                JSON.stringify(style), createdBy, teamId, missionId,
                expiresAt, JSON.stringify(metadata)
            ]);

            const overlay = {
                ...result.rows[0],
                geometry: JSON.parse(result.rows[0].geometry)
            };

            // Broadcast overlay creation to team members
            await this.broadcastOverlayUpdate('created', overlay);

            this.logger.info(`Created tactical overlay: ${overlay.id}`);
            return overlay;
        } catch (error) {
            this.logger.error('Error creating tactical overlay:', error);
            throw error;
        }
    }

    /**
     * Get team locations from location service
     */
    async getTeamLocations(filters = {}) {
        try {
            const cacheKey = `team-locations:${JSON.stringify(filters)}`;
            
            // Check cache first
            const cached = await this.redis.get(cacheKey);
            if (cached) {
                return JSON.parse(cached);
            }

            // Fetch from location service
            const response = await axios.get(`${this.locationServiceUrl}/api/locations`, {
                params: filters,
                timeout: 5000
            });

            const locations = response.data;

            // Transform to GeoJSON format for map display
            const geoJsonFeatures = locations.map(location => ({
                type: 'Feature',
                geometry: {
                    type: 'Point',
                    coordinates: [location.longitude, location.latitude]
                },
                properties: {
                    id: location.id,
                    callsign: location.callsign,
                    teamId: location.team_id,
                    status: location.status,
                    accuracy: location.accuracy,
                    timestamp: location.timestamp,
                    metadata: location.metadata
                }
            }));

            const result = {
                type: 'FeatureCollection',
                features: geoJsonFeatures
            };

            // Cache for 30 seconds
            await this.redis.setEx(cacheKey, 30, JSON.stringify(result));

            return result;
        } catch (error) {
            this.logger.error('Error getting team locations:', error);
            // Return empty collection on error
            return {
                type: 'FeatureCollection',
                features: []
            };
        }
    }

    /**
     * Calculate distance between two points
     */
    calculateDistance(point1, point2) {
        try {
            const from = turf.point([point1.longitude, point1.latitude]);
            const to = turf.point([point2.longitude, point2.latitude]);
            return turf.distance(from, to, { units: 'meters' });
        } catch (error) {
            this.logger.error('Error calculating distance:', error);
            return null;
        }
    }

    /**
     * Calculate bearing between two points
     */
    calculateBearing(point1, point2) {
        try {
            const from = turf.point([point1.longitude, point1.latitude]);
            const to = turf.point([point2.longitude, point2.latitude]);
            return turf.bearing(from, to);
        } catch (error) {
            this.logger.error('Error calculating bearing:', error);
            return null;
        }
    }

    /**
     * Calculate area of a polygon
     */
    calculateArea(geometry) {
        try {
            if (geometry.type !== 'Polygon') {
                throw new Error('Geometry must be a polygon');
            }
            
            const polygon = turf.polygon(geometry.coordinates);
            return turf.area(polygon);
        } catch (error) {
            this.logger.error('Error calculating area:', error);
            return null;
        }
    }

    /**
     * Check if point is within tactical overlay
     */
    async isPointInOverlay(point, overlayId) {
        try {
            const result = await this.db.query(`
                SELECT ST_Within(
                    ST_SetSRID(ST_MakePoint($1, $2), 4326),
                    geometry
                ) as within
                FROM tactical_overlays 
                WHERE id = $3 AND status = 'active'
            `, [point.longitude, point.latitude, overlayId]);

            return result.rows.length > 0 ? result.rows[0].within : false;
        } catch (error) {
            this.logger.error('Error checking point in overlay:', error);
            return false;
        }
    }

    /**
     * Get nearby waypoints for a location
     */
    async getNearbyWaypoints(location, radiusMeters = 1000, teamId = null) {
        try {
            let query = `
                SELECT id, name, description, 
                       ST_AsGeoJSON(location) as location,
                       waypoint_type, symbol, color, created_by, team_id, mission_id,
                       ST_Distance(location, ST_SetSRID(ST_MakePoint($1, $2), 4326)) as distance,
                       created_at, updated_at, expires_at, status, metadata
                FROM waypoints 
                WHERE status = 'active'
                AND ST_DWithin(location, ST_SetSRID(ST_MakePoint($1, $2), 4326), $3)
            `;
            const params = [location.longitude, location.latitude, radiusMeters];

            if (teamId) {
                query += ' AND team_id = $4';
                params.push(teamId);
            }

            query += ' ORDER BY distance ASC';

            const result = await this.db.query(query, params);
            
            return result.rows.map(row => ({
                ...row,
                location: JSON.parse(row.location),
                distance: parseFloat(row.distance)
            }));
        } catch (error) {
            this.logger.error('Error getting nearby waypoints:', error);
            throw error;
        }
    }

    /**
     * Broadcast waypoint updates to team members
     */
    async broadcastWaypointUpdate(action, waypoint) {
        try {
            if (!waypoint.teamId) return;

            const message = {
                type: 'waypoint_update',
                action,
                waypoint,
                timestamp: new Date().toISOString()
            };

            // Publish to Redis for real-time updates
            await this.redis.publish(`team:${waypoint.teamId}:waypoints`, JSON.stringify(message));
            
            this.logger.debug(`Broadcasted waypoint ${action}: ${waypoint.id}`);
        } catch (error) {
            this.logger.error('Error broadcasting waypoint update:', error);
        }
    }

    /**
     * Broadcast overlay updates to team members
     */
    async broadcastOverlayUpdate(action, overlay) {
        try {
            if (!overlay.teamId) return;

            const message = {
                type: 'overlay_update',
                action,
                overlay,
                timestamp: new Date().toISOString()
            };

            // Publish to Redis for real-time updates
            await this.redis.publish(`team:${overlay.teamId}:overlays`, JSON.stringify(message));
            
            this.logger.debug(`Broadcasted overlay ${action}: ${overlay.id}`);
        } catch (error) {
            this.logger.error('Error broadcasting overlay update:', error);
        }
    }

    /**
     * Generate tactical route between waypoints
     */
    async generateTacticalRoute(waypoints, options = {}) {
        try {
            if (waypoints.length < 2) {
                throw new Error('At least 2 waypoints required for route generation');
            }

            const coordinates = waypoints.map(wp => [
                wp.location.coordinates[0],
                wp.location.coordinates[1]
            ]);

            // Create a simple route (in production, integrate with routing service)
            const route = {
                type: 'Feature',
                geometry: {
                    type: 'LineString',
                    coordinates
                },
                properties: {
                    waypoints: waypoints.map(wp => wp.id),
                    distance: this.calculateRouteDistance(coordinates),
                    estimatedTime: this.estimateRouteTime(coordinates, options.speed || 5), // 5 km/h default
                    routeType: options.routeType || 'tactical',
                    created: new Date().toISOString()
                }
            };

            return route;
        } catch (error) {
            this.logger.error('Error generating tactical route:', error);
            throw error;
        }
    }

    /**
     * Calculate total route distance
     */
    calculateRouteDistance(coordinates) {
        let totalDistance = 0;
        
        for (let i = 0; i < coordinates.length - 1; i++) {
            const from = turf.point(coordinates[i]);
            const to = turf.point(coordinates[i + 1]);
            totalDistance += turf.distance(from, to, { units: 'meters' });
        }
        
        return totalDistance;
    }

    /**
     * Estimate route time based on speed
     */
    estimateRouteTime(coordinates, speedKmh) {
        const distanceKm = this.calculateRouteDistance(coordinates) / 1000;
        return (distanceKm / speedKmh) * 3600; // seconds
    }

    /**
     * Get tactical situation awareness data
     */
    async getTacticalSituation(bounds, teamId) {
        try {
            const [waypoints, overlays, teamLocations] = await Promise.all([
                this.getWaypoints({ bounds: JSON.stringify(bounds), teamId }),
                this.getTacticalOverlays({ bounds: JSON.stringify(bounds), teamId }),
                this.getTeamLocations({ teamId, bounds: JSON.stringify(bounds) })
            ]);

            return {
                waypoints,
                overlays,
                teamLocations,
                timestamp: new Date().toISOString()
            };
        } catch (error) {
            this.logger.error('Error getting tactical situation:', error);
            throw error;
        }
    }
}

module.exports = TacticalMaps;