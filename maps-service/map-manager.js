const fs = require('fs').promises;
const path = require('path');
const sharp = require('sharp');
const { createReadStream, createWriteStream } = require('fs');
const archiver = require('archiver');
const unzipper = require('unzipper');
const crypto = require('crypto');

class MapManager {
    constructor(db, redis, logger, config) {
        this.db = db;
        this.redis = redis;
        this.logger = logger;
        this.config = config;
        this.tileCache = new Map();
        this.downloadQueue = new Map();
    }

    /**
     * Get a map tile from cache or generate it
     */
    async getTile(z, x, y, format = 'mvt') {
        const tileKey = `tile:${z}:${x}:${y}:${format}`;
        
        try {
            // Check Redis cache first
            const cachedTile = await this.redis.get(tileKey);
            if (cachedTile) {
                await this.updateTileAccess(z, x, y);
                return Buffer.from(cachedTile, 'base64');
            }

            // Check database cache
            const dbTile = await this.getTileFromDatabase(z, x, y);
            if (dbTile) {
                // Cache in Redis
                await this.redis.setEx(tileKey, this.config.redis.ttl, dbTile.toString('base64'));
                await this.updateTileAccess(z, x, y);
                return dbTile;
            }

            // Generate tile if not cached
            const tile = await this.generateTile(z, x, y, format);
            if (tile) {
                // Cache in both Redis and database
                await this.cacheTile(z, x, y, tile, format);
                return tile;
            }

            return null;
        } catch (error) {
            this.logger.error(`Error getting tile ${z}/${x}/${y}:`, error);
            throw error;
        }
    }

    /**
     * Generate a map tile
     */
    async generateTile(z, x, y, format) {
        try {
            // This would integrate with OpenMapTiles or similar tile server
            // For now, return a placeholder implementation
            const tileSize = this.config.tiles.tileSize;
            const buffer = await sharp({
                create: {
                    width: tileSize,
                    height: tileSize,
                    channels: 4,
                    background: { r: 26, g: 26, b: 26, alpha: 1 }
                }
            })
            .png()
            .toBuffer();

            return buffer;
        } catch (error) {
            this.logger.error(`Error generating tile ${z}/${x}/${y}:`, error);
            throw error;
        }
    }

    /**
     * Get tile from database cache
     */
    async getTileFromDatabase(z, x, y) {
        try {
            const result = await this.db.query(
                'SELECT tile_data FROM map_tiles_cache WHERE z = $1 AND x = $2 AND y = $3',
                [z, x, y]
            );

            return result.rows.length > 0 ? result.rows[0].tile_data : null;
        } catch (error) {
            this.logger.error('Error getting tile from database:', error);
            return null;
        }
    }

    /**
     * Cache a tile in database and Redis
     */
    async cacheTile(z, x, y, tileData, format) {
        try {
            const checksum = crypto.createHash('sha256').update(tileData).digest('hex');
            const contentType = format === 'mvt' ? 'application/x-protobuf' : 'image/png';

            // Cache in database
            await this.db.query(`
                INSERT INTO map_tiles_cache (z, x, y, tile_data, content_type, size_bytes, checksum)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                ON CONFLICT (z, x, y) DO UPDATE SET
                    tile_data = EXCLUDED.tile_data,
                    content_type = EXCLUDED.content_type,
                    size_bytes = EXCLUDED.size_bytes,
                    checksum = EXCLUDED.checksum,
                    accessed_at = CURRENT_TIMESTAMP,
                    access_count = map_tiles_cache.access_count + 1
            `, [z, x, y, tileData, contentType, tileData.length, checksum]);

            // Cache in Redis
            const tileKey = `tile:${z}:${x}:${y}:${format}`;
            await this.redis.setEx(tileKey, this.config.redis.ttl, tileData.toString('base64'));

        } catch (error) {
            this.logger.error('Error caching tile:', error);
        }
    }

    /**
     * Update tile access statistics
     */
    async updateTileAccess(z, x, y) {
        try {
            await this.db.query(`
                UPDATE map_tiles_cache 
                SET accessed_at = CURRENT_TIMESTAMP, access_count = access_count + 1
                WHERE z = $1 AND x = $2 AND y = $3
            `, [z, x, y]);
        } catch (error) {
            this.logger.error('Error updating tile access:', error);
        }
    }

    /**
     * Get map style configuration
     */
    async getStyle(styleName = 'tactical') {
        try {
            const styleKey = `style:${styleName}`;
            
            // Check Redis cache
            const cachedStyle = await this.redis.get(styleKey);
            if (cachedStyle) {
                return JSON.parse(cachedStyle);
            }

            // Load from file
            const stylePath = path.join(__dirname, `${styleName}-style.json`);
            const styleData = await fs.readFile(stylePath, 'utf8');
            const style = JSON.parse(styleData);

            // Update tile source URLs
            if (style.sources && style.sources.openmaptiles) {
                style.sources.openmaptiles.tiles = [`${this.getBaseUrl()}/tiles/{z}/{x}/{y}.mvt`];
            }

            // Cache in Redis
            await this.redis.setEx(styleKey, 3600, JSON.stringify(style));

            return style;
        } catch (error) {
            this.logger.error(`Error getting style ${styleName}:`, error);
            throw error;
        }
    }

    /**
     * Get available regions
     */
    async getRegions() {
        try {
            const result = await this.db.query(`
                SELECT id, name, description, 
                       ST_AsGeoJSON(bounds) as bounds,
                       min_zoom, max_zoom, priority, estimated_size_mb,
                       preload, features, metadata, status
                FROM regions 
                WHERE status = 'active'
                ORDER BY priority DESC, name
            `);

            return result.rows.map(row => ({
                ...row,
                bounds: JSON.parse(row.bounds)
            }));
        } catch (error) {
            this.logger.error('Error getting regions:', error);
            throw error;
        }
    }

    /**
     * Initiate region download
     */
    async initiateRegionDownload(regionId, userId, deviceId) {
        try {
            // Get region details
            const regionResult = await this.db.query(
                'SELECT * FROM regions WHERE id = $1 AND status = $2',
                [regionId, 'active']
            );

            if (regionResult.rows.length === 0) {
                throw new Error('Region not found');
            }

            const region = regionResult.rows[0];

            // Create download record
            const downloadResult = await this.db.query(`
                INSERT INTO map_downloads (region_id, user_id, device_id, status, total_tiles)
                VALUES ($1, $2, $3, 'pending', $4)
                RETURNING id
            `, [regionId, userId, deviceId, this.estimateTileCount(region)]);

            const downloadId = downloadResult.rows[0].id;

            // Start download process
            this.processRegionDownload(downloadId, region);

            return downloadId;
        } catch (error) {
            this.logger.error('Error initiating region download:', error);
            throw error;
        }
    }

    /**
     * Process region download
     */
    async processRegionDownload(downloadId, region) {
        try {
            await this.db.query(
                'UPDATE map_downloads SET status = $1, started_at = CURRENT_TIMESTAMP WHERE id = $2',
                ['processing', downloadId]
            );

            const bounds = JSON.parse(region.bounds);
            const tiles = this.generateTileList(bounds, region.min_zoom, region.max_zoom);
            
            let downloadedTiles = 0;
            const downloadPath = path.join(this.config.storage.dataPath, `region_${region.id}_${downloadId}.zip`);
            
            // Create zip archive
            const output = createWriteStream(downloadPath);
            const archive = archiver('zip', { zlib: { level: this.config.storage.compressionLevel } });
            
            archive.pipe(output);

            for (const tile of tiles) {
                try {
                    const tileData = await this.getTile(tile.z, tile.x, tile.y);
                    if (tileData) {
                        archive.append(tileData, { name: `${tile.z}/${tile.x}/${tile.y}.mvt` });
                        downloadedTiles++;
                        
                        // Update progress every 100 tiles
                        if (downloadedTiles % 100 === 0) {
                            await this.updateDownloadProgress(downloadId, downloadedTiles, tiles.length);
                        }
                    }
                } catch (error) {
                    this.logger.error(`Error downloading tile ${tile.z}/${tile.x}/${tile.y}:`, error);
                }
            }

            await archive.finalize();

            // Get file size
            const stats = await fs.stat(downloadPath);
            
            // Update download record
            await this.db.query(`
                UPDATE map_downloads 
                SET status = 'completed', downloaded_tiles = $1, file_path = $2, 
                    file_size = $3, completed_at = CURRENT_TIMESTAMP
                WHERE id = $4
            `, [downloadedTiles, downloadPath, stats.size, downloadId]);

            this.logger.info(`Region download completed: ${downloadId}`);
        } catch (error) {
            this.logger.error(`Error processing region download ${downloadId}:`, error);
            
            await this.db.query(
                'UPDATE map_downloads SET status = $1, error_message = $2 WHERE id = $3',
                ['failed', error.message, downloadId]
            );
        }
    }

    /**
     * Update download progress
     */
    async updateDownloadProgress(downloadId, downloaded, total) {
        const progress = Math.round((downloaded / total) * 100);
        
        await this.db.query(
            'UPDATE map_downloads SET progress = $1, downloaded_tiles = $2 WHERE id = $3',
            [progress, downloaded, downloadId]
        );
    }

    /**
     * Generate list of tiles for a region
     */
    generateTileList(bounds, minZoom, maxZoom) {
        const tiles = [];
        
        for (let z = minZoom; z <= maxZoom; z++) {
            const minTileX = this.lonToTileX(bounds[0], z);
            const maxTileX = this.lonToTileX(bounds[2], z);
            const minTileY = this.latToTileY(bounds[3], z);
            const maxTileY = this.latToTileY(bounds[1], z);
            
            for (let x = minTileX; x <= maxTileX; x++) {
                for (let y = minTileY; y <= maxTileY; y++) {
                    tiles.push({ z, x, y });
                }
            }
        }
        
        return tiles;
    }

    /**
     * Estimate tile count for a region
     */
    estimateTileCount(region) {
        const bounds = JSON.parse(region.bounds);
        return this.generateTileList(bounds, region.min_zoom, region.max_zoom).length;
    }

    /**
     * Convert longitude to tile X coordinate
     */
    lonToTileX(lon, zoom) {
        return Math.floor((lon + 180) / 360 * Math.pow(2, zoom));
    }

    /**
     * Convert latitude to tile Y coordinate
     */
    latToTileY(lat, zoom) {
        return Math.floor((1 - Math.log(Math.tan(lat * Math.PI / 180) + 1 / Math.cos(lat * Math.PI / 180)) / Math.PI) / 2 * Math.pow(2, zoom));
    }

    /**
     * Import map data from file
     */
    async importMapData(filePath, metadata = {}) {
        try {
            const stats = await fs.stat(filePath);
            const checksum = await this.calculateFileChecksum(filePath);
            
            const result = await this.db.query(`
                INSERT INTO map_metadata (name, description, file_path, file_size, checksum, metadata)
                VALUES ($1, $2, $3, $4, $5, $6)
                RETURNING id
            `, [
                metadata.name || path.basename(filePath),
                metadata.description || 'Imported map data',
                filePath,
                stats.size,
                checksum,
                JSON.stringify(metadata)
            ]);

            this.logger.info(`Imported map data: ${filePath}`);
            return result.rows[0].id;
        } catch (error) {
            this.logger.error('Error importing map data:', error);
            throw error;
        }
    }

    /**
     * Calculate file checksum
     */
    async calculateFileChecksum(filePath) {
        return new Promise((resolve, reject) => {
            const hash = crypto.createHash('sha256');
            const stream = createReadStream(filePath);
            
            stream.on('data', data => hash.update(data));
            stream.on('end', () => resolve(hash.digest('hex')));
            stream.on('error', reject);
        });
    }

    /**
     * Clean up expired data
     */
    async cleanupExpiredData() {
        try {
            const result = await this.db.query('SELECT cleanup_expired_data()');
            const deletedCount = result.rows[0].cleanup_expired_data;
            
            this.logger.info(`Cleaned up ${deletedCount} expired records`);
            return deletedCount;
        } catch (error) {
            this.logger.error('Error cleaning up expired data:', error);
            throw error;
        }
    }

    /**
     * Get map statistics
     */
    async getStatistics() {
        try {
            const result = await this.db.query('SELECT * FROM get_map_statistics()');
            const stats = result.rows[0];
            
            // Add Redis cache statistics
            const cacheInfo = await this.redis.info('memory');
            const cacheStats = this.parseCacheInfo(cacheInfo);
            
            return {
                ...stats,
                cache: cacheStats,
                timestamp: new Date().toISOString()
            };
        } catch (error) {
            this.logger.error('Error getting statistics:', error);
            throw error;
        }
    }

    /**
     * Parse Redis cache info
     */
    parseCacheInfo(info) {
        const lines = info.split('\r\n');
        const stats = {};
        
        lines.forEach(line => {
            const [key, value] = line.split(':');
            if (key && value) {
                stats[key] = isNaN(value) ? value : Number(value);
            }
        });
        
        return {
            usedMemory: stats.used_memory,
            usedMemoryHuman: stats.used_memory_human,
            maxMemory: stats.maxmemory,
            keyCount: stats.db0 ? stats.db0.split(',')[0].split('=')[1] : 0
        };
    }

    /**
     * Update cache statistics
     */
    async updateCacheStatistics() {
        try {
            const stats = await this.getStatistics();
            await this.redis.setEx('cache:stats', 300, JSON.stringify(stats));
        } catch (error) {
            this.logger.error('Error updating cache statistics:', error);
        }
    }

    /**
     * Get base URL for tile requests
     */
    getBaseUrl() {
        return `http://${this.config.server.host}:${this.config.server.port}`;
    }

    /**
     * Optimize tile storage
     */
    async optimizeTileStorage() {
        try {
            // Remove least accessed tiles when storage is full
            const storageStats = await this.getStorageUsage();
            const maxStorageBytes = this.config.storage.maxStorageGB * 1024 * 1024 * 1024;
            
            if (storageStats.used > maxStorageBytes * 0.9) {
                await this.db.query(`
                    DELETE FROM map_tiles_cache 
                    WHERE id IN (
                        SELECT id FROM map_tiles_cache 
                        ORDER BY access_count ASC, accessed_at ASC 
                        LIMIT 1000
                    )
                `);
                
                this.logger.info('Optimized tile storage by removing least accessed tiles');
            }
        } catch (error) {
            this.logger.error('Error optimizing tile storage:', error);
        }
    }

    /**
     * Get storage usage statistics
     */
    async getStorageUsage() {
        try {
            const result = await this.db.query(`
                SELECT 
                    COUNT(*) as tile_count,
                    SUM(size_bytes) as total_size,
                    AVG(size_bytes) as avg_size
                FROM map_tiles_cache
            `);
            
            return {
                tileCount: parseInt(result.rows[0].tile_count),
                used: parseInt(result.rows[0].total_size || 0),
                average: parseInt(result.rows[0].avg_size || 0)
            };
        } catch (error) {
            this.logger.error('Error getting storage usage:', error);
            return { tileCount: 0, used: 0, average: 0 };
        }
    }
}

module.exports = MapManager;