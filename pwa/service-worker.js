// Service Worker for Tactical PWA - Discrete System Utility
// Version: 2.1.4
// Provides offline functionality while maintaining operational security

const CACHE_NAME = 'system-utility-v2.1.4';
const TACTICAL_CACHE_NAME = 'tactical-interface-v2.1.4';

// Resources to cache for offline functionality
const STATIC_RESOURCES = [
    '/',
    '/index.html',
    '/styles.css',
    '/app.js',
    '/manifest.json',
    '/icons/16.png',
    '/icons/32.png',
    '/icons/48.png',
    '/icons/128.png',
    '/icons/192.png',
    '/icons/512.png'
];

// Tactical interface resources (cached separately for security)
const TACTICAL_RESOURCES = [
    '/tactical-interface.html'
];

// Network endpoints that should never be cached (security requirement)
const NEVER_CACHE = [
    '/api/auth/',
    '/api/location/',
    '/tactical-location',
    '/api/emergency/',
    '/api/secure/'
];

// Install event - cache static resources
self.addEventListener('install', event => {
    console.log('[SW] Installing service worker...');
    
    event.waitUntil(
        Promise.all([
            // Cache static resources
            caches.open(CACHE_NAME).then(cache => {
                console.log('[SW] Caching static resources');
                return cache.addAll(STATIC_RESOURCES);
            }),
            // Cache tactical interface separately
            caches.open(TACTICAL_CACHE_NAME).then(cache => {
                console.log('[SW] Caching tactical interface');
                return cache.addAll(TACTICAL_RESOURCES);
            })
        ]).then(() => {
            console.log('[SW] Installation complete');
            // Force activation of new service worker
            return self.skipWaiting();
        })
    );
});

// Activate event - clean up old caches
self.addEventListener('activate', event => {
    console.log('[SW] Activating service worker...');
    
    event.waitUntil(
        caches.keys().then(cacheNames => {
            return Promise.all(
                cacheNames.map(cacheName => {
                    // Delete old cache versions
                    if (cacheName !== CACHE_NAME && cacheName !== TACTICAL_CACHE_NAME) {
                        console.log('[SW] Deleting old cache:', cacheName);
                        return caches.delete(cacheName);
                    }
                })
            );
        }).then(() => {
            console.log('[SW] Activation complete');
            // Take control of all clients immediately
            return self.clients.claim();
        })
    );
});

// Fetch event - handle network requests with security considerations
self.addEventListener('fetch', event => {
    const request = event.request;
    const url = new URL(request.url);
    
    // Skip non-GET requests
    if (request.method !== 'GET') {
        return;
    }
    
    // Skip cross-origin requests (except for tactical server)
    if (url.origin !== location.origin && !isTacticalServer(url.origin)) {
        return;
    }
    
    // Never cache sensitive endpoints
    if (shouldNeverCache(url.pathname)) {
        console.log('[SW] Bypassing cache for sensitive endpoint:', url.pathname);
        event.respondWith(fetch(request));
        return;
    }
    
    // Handle different types of requests
    if (isStaticResource(url.pathname)) {
        event.respondWith(handleStaticResource(request));
    } else if (isTacticalResource(url.pathname)) {
        event.respondWith(handleTacticalResource(request));
    } else if (isServiceEndpoint(url.pathname)) {
        event.respondWith(handleServiceEndpoint(request));
    } else {
        event.respondWith(handleGenericRequest(request));
    }
});

// Handle static resources (cover interface)
async function handleStaticResource(request) {
    try {
        const cache = await caches.open(CACHE_NAME);
        const cachedResponse = await cache.match(request);
        
        if (cachedResponse) {
            // Serve from cache, update in background
            fetchAndUpdateCache(request, cache);
            return cachedResponse;
        }
        
        // Not in cache, fetch and cache
        const response = await fetch(request);
        if (response.ok) {
            cache.put(request, response.clone());
        }
        return response;
        
    } catch (error) {
        console.log('[SW] Static resource fetch failed:', error);
        
        // Return cached version if available
        const cache = await caches.open(CACHE_NAME);
        const cachedResponse = await cache.match(request);
        if (cachedResponse) {
            return cachedResponse;
        }
        
        // Return offline fallback
        return new Response('System temporarily unavailable', {
            status: 503,
            statusText: 'Service Unavailable'
        });
    }
}

// Handle tactical interface resources (authenticated access only)
async function handleTacticalResource(request) {
    try {
        const cache = await caches.open(TACTICAL_CACHE_NAME);
        const cachedResponse = await cache.match(request);
        
        // Always try network first for tactical resources
        try {
            const response = await fetch(request);
            if (response.ok) {
                cache.put(request, response.clone());
                return response;
            }
        } catch (networkError) {
            console.log('[SW] Network failed for tactical resource, using cache');
        }
        
        // Fallback to cache if network fails
        if (cachedResponse) {
            return cachedResponse;
        }
        
        // No cache available
        return new Response('Tactical interface unavailable', {
            status: 503,
            statusText: 'Service Unavailable'
        });
        
    } catch (error) {
        console.log('[SW] Tactical resource error:', error);
        return new Response('Access denied', {
            status: 403,
            statusText: 'Forbidden'
        });
    }
}

// Handle service endpoints (reports, maps, comms, files)
async function handleServiceEndpoint(request) {
    try {
        // Always fetch from network for service endpoints
        const response = await fetch(request);
        return response;
        
    } catch (error) {
        console.log('[SW] Service endpoint failed:', error);
        
        // Return appropriate offline response
        return new Response(JSON.stringify({
            error: 'Service temporarily unavailable',
            offline: true,
            timestamp: Date.now()
        }), {
            status: 503,
            statusText: 'Service Unavailable',
            headers: {
                'Content-Type': 'application/json'
            }
        });
    }
}

// Handle generic requests
async function handleGenericRequest(request) {
    try {
        return await fetch(request);
    } catch (error) {
        console.log('[SW] Generic request failed:', error);
        return new Response('Request failed', {
            status: 503,
            statusText: 'Service Unavailable'
        });
    }
}

// Background sync for when connectivity returns
self.addEventListener('sync', event => {
    console.log('[SW] Background sync triggered:', event.tag);
    
    if (event.tag === 'tactical-sync') {
        event.waitUntil(syncTacticalData());
    }
});

// Sync tactical data when connectivity returns
async function syncTacticalData() {
    try {
        // Sync any pending location updates
        const pendingLocations = await getStoredData('pending-locations');
        if (pendingLocations && pendingLocations.length > 0) {
            await syncLocationUpdates(pendingLocations);
            await clearStoredData('pending-locations');
        }
        
        // Sync any pending messages
        const pendingMessages = await getStoredData('pending-messages');
        if (pendingMessages && pendingMessages.length > 0) {
            await syncMessages(pendingMessages);
            await clearStoredData('pending-messages');
        }
        
        console.log('[SW] Tactical data sync completed');
        
    } catch (error) {
        console.log('[SW] Tactical sync failed:', error);
    }
}

// Utility functions
function isStaticResource(pathname) {
    return STATIC_RESOURCES.some(resource => 
        pathname === resource || pathname.endsWith(resource)
    );
}

function isTacticalResource(pathname) {
    return TACTICAL_RESOURCES.some(resource => 
        pathname === resource || pathname.endsWith(resource)
    );
}

function isServiceEndpoint(pathname) {
    return pathname.startsWith('/api/') || 
           pathname.startsWith('/tactical-location');
}

function shouldNeverCache(pathname) {
    return NEVER_CACHE.some(pattern => pathname.startsWith(pattern));
}

function isTacticalServer(origin) {
    // Check if origin is the tactical server
    return origin.includes('192.168.100.1') || 
           origin.includes('tactical.local');
}

async function fetchAndUpdateCache(request, cache) {
    try {
        const response = await fetch(request);
        if (response.ok) {
            cache.put(request, response.clone());
        }
    } catch (error) {
        // Silent fail for background updates
        console.log('[SW] Background update failed:', error);
    }
}

// IndexedDB operations for offline data storage
async function getStoredData(key) {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open('TacticalOfflineDB', 1);
        
        request.onerror = () => reject(request.error);
        
        request.onsuccess = () => {
            const db = request.result;
            const transaction = db.transaction(['offline-data'], 'readonly');
            const store = transaction.objectStore('offline-data');
            const getRequest = store.get(key);
            
            getRequest.onsuccess = () => {
                resolve(getRequest.result ? getRequest.result.data : null);
            };
            
            getRequest.onerror = () => reject(getRequest.error);
        };
        
        request.onupgradeneeded = () => {
            const db = request.result;
            if (!db.objectStoreNames.contains('offline-data')) {
                db.createObjectStore('offline-data', { keyPath: 'key' });
            }
        };
    });
}

async function clearStoredData(key) {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open('TacticalOfflineDB', 1);
        
        request.onsuccess = () => {
            const db = request.result;
            const transaction = db.transaction(['offline-data'], 'readwrite');
            const store = transaction.objectStore('offline-data');
            const deleteRequest = store.delete(key);
            
            deleteRequest.onsuccess = () => resolve();
            deleteRequest.onerror = () => reject(deleteRequest.error);
        };
    });
}

async function syncLocationUpdates(locations) {
    // Sync location updates to tactical server
    try {
        const response = await fetch('/tactical-location', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                type: 'bulk_location_sync',
                data: locations
            })
        });
        
        if (!response.ok) {
            throw new Error('Location sync failed');
        }
        
        console.log('[SW] Location updates synced:', locations.length);
        
    } catch (error) {
        console.log('[SW] Location sync error:', error);
        throw error;
    }
}

async function syncMessages(messages) {
    // Sync pending messages
    try {
        for (const message of messages) {
            const response = await fetch('/api/comms/sync', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(message)
            });
            
            if (!response.ok) {
                console.log('[SW] Message sync failed for:', message.id);
            }
        }
        
        console.log('[SW] Messages synced:', messages.length);
        
    } catch (error) {
        console.log('[SW] Message sync error:', error);
        throw error;
    }
}

// Message handling for communication with main app
self.addEventListener('message', event => {
    const { type, data } = event.data;
    
    switch (type) {
        case 'SKIP_WAITING':
            self.skipWaiting();
            break;
            
        case 'GET_VERSION':
            event.ports[0].postMessage({
                version: CACHE_NAME,
                tactical: TACTICAL_CACHE_NAME
            });
            break;
            
        case 'CLEAR_CACHE':
            clearAllCaches().then(() => {
                event.ports[0].postMessage({ success: true });
            });
            break;
            
        case 'STORE_OFFLINE_DATA':
            storeOfflineData(data.key, data.value).then(() => {
                event.ports[0].postMessage({ success: true });
            });
            break;
            
        default:
            console.log('[SW] Unknown message type:', type);
    }
});

async function clearAllCaches() {
    const cacheNames = await caches.keys();
    await Promise.all(
        cacheNames.map(cacheName => caches.delete(cacheName))
    );
    console.log('[SW] All caches cleared');
}

async function storeOfflineData(key, value) {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open('TacticalOfflineDB', 1);
        
        request.onsuccess = () => {
            const db = request.result;
            const transaction = db.transaction(['offline-data'], 'readwrite');
            const store = transaction.objectStore('offline-data');
            const putRequest = store.put({ key, data: value, timestamp: Date.now() });
            
            putRequest.onsuccess = () => resolve();
            putRequest.onerror = () => reject(putRequest.error);
        };
        
        request.onupgradeneeded = () => {
            const db = request.result;
            if (!db.objectStoreNames.contains('offline-data')) {
                db.createObjectStore('offline-data', { keyPath: 'key' });
            }
        };
    });
}

console.log('[SW] Service Worker loaded - System Utility v2.1.4');