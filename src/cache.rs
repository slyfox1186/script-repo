use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::{Duration, Instant};
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use log::{debug, info};
use crate::config::GccVersion;
use crate::error::{GccBuildError, Result as GccResult};

/// In-memory cache for GCC version resolution and other frequently accessed data
#[derive(Clone)]
pub struct VersionCache {
    inner: Arc<RwLock<CacheInner>>,
}

struct CacheInner {
    /// Cached version resolutions
    versions: HashMap<String, CachedVersion>,
    /// Cached FTP directory listings
    listings: HashMap<String, CachedListing>,
    /// Global statistics
    stats: CacheStats,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct CachedVersion {
    version: GccVersion,
    resolved_at: DateTime<Local>,
    ttl: Duration,
}

#[derive(Clone, Debug)]
struct CachedListing {
    content: String,
    fetched_at: Instant,
    ttl: Duration,
}

#[derive(Default, Debug)]
struct CacheStats {
    hits: u64,
    misses: u64,
    evictions: u64,
}

impl VersionCache {
    /// Create a new version cache
    pub fn new() -> Self {
        Self {
            inner: Arc::new(RwLock::new(CacheInner {
                versions: HashMap::new(),
                listings: HashMap::new(),
                stats: CacheStats::default(),
            })),
        }
    }
    
    /// Get a resolved version from cache
    pub fn get_version(&self, key: &str) -> Option<GccVersion> {
        let now = Local::now();
        let mut inner = self.inner.write().unwrap();
        
        // Single lookup with entry API
        if let Some(cached) = inner.versions.get(key) {
            if cached.resolved_at.timestamp() + cached.ttl.as_secs() as i64 > now.timestamp() {
                let result = cached.version.clone();
                inner.stats.hits += 1;
                debug!("Cache hit for version key: {}", key);
                return Some(result);
            } else {
                // Expired, remove it
                inner.versions.remove(key);
                inner.stats.evictions += 1;
                inner.stats.misses += 1;
                return None;
            }
        }
        inner.stats.misses += 1;
        None
    }
    
    /// Store a resolved version in cache
    pub fn put_version(&self, key: String, version: GccVersion, ttl: Duration) {
        let mut inner = self.inner.write().unwrap();
        
        inner.versions.insert(key.clone(), CachedVersion {
            version,
            resolved_at: Local::now(),
            ttl,
        });
        
        debug!("Cached version for key: {} (TTL: {:?})", key, ttl);
    }
    
    /// Get cached FTP listing
    pub fn get_listing(&self, url: &str) -> Option<String> {
        let mut inner = self.inner.write().unwrap();
        
        // Single lookup
        if let Some(cached) = inner.listings.get(url) {
            if cached.fetched_at.elapsed() < cached.ttl {
                let result = cached.content.clone();
                inner.stats.hits += 1;
                debug!("Cache hit for listing: {}", url);
                return Some(result);
            } else {
                // Expired
                inner.listings.remove(url);
                inner.stats.evictions += 1;
                inner.stats.misses += 1;
                return None;
            }
        }
        inner.stats.misses += 1;
        None
    }
    
    /// Store FTP listing in cache
    pub fn put_listing(&self, url: String, content: String, ttl: Duration) {
        let mut inner = self.inner.write().unwrap();
        
        inner.listings.insert(url.clone(), CachedListing {
            content,
            fetched_at: Instant::now(),
            ttl,
        });
        
        debug!("Cached listing for: {} (TTL: {:?})", url, ttl);
    }
    
    /// Get cache statistics
    pub fn get_stats(&self) -> CacheStatistics {
        let inner = self.inner.read().unwrap();
        CacheStatistics {
            version_entries: inner.versions.len(),
            listing_entries: inner.listings.len(),
            total_hits: inner.stats.hits,
            total_misses: inner.stats.misses,
            total_evictions: inner.stats.evictions,
            hit_rate: if inner.stats.hits + inner.stats.misses > 0 {
                (inner.stats.hits as f64 / (inner.stats.hits + inner.stats.misses) as f64) * 100.0
            } else {
                0.0
            },
        }
    }
    
    /// Clear all cache entries
    pub fn clear(&self) {
        let mut inner = self.inner.write().unwrap();
        inner.versions.clear();
        inner.listings.clear();
        info!("Cache cleared");
    }
    
    /// Persist cache to disk (for future sessions)
    pub async fn persist(&self, path: &std::path::Path) -> GccResult<()> {
        let inner = self.inner.read().unwrap();
        
        let persisted = PersistedCache {
            versions: inner.versions.clone(),
            saved_at: Local::now(),
        };
        
        let json = serde_json::to_string_pretty(&persisted)
            .map_err(|e| GccBuildError::file_operation("serialize cache", path.display().to_string(), e.to_string()))?;
        
        tokio::fs::write(path, json).await
            .map_err(|e| GccBuildError::file_operation("write cache", path.display().to_string(), e.to_string()))?;
        
        info!("Cache persisted to {}", path.display());
        Ok(())
    }
    
    /// Load cache from disk
    pub async fn load(&self, path: &std::path::Path) -> GccResult<()> {
        if !path.exists() {
            return Ok(());
        }
        
        let json = tokio::fs::read_to_string(path).await
            .map_err(|e| GccBuildError::file_operation("read cache", path.display().to_string(), e.to_string()))?;
        
        let persisted: PersistedCache = serde_json::from_str(&json)
            .map_err(|e| GccBuildError::file_operation("deserialize cache", path.display().to_string(), e.to_string()))?;
        
        let mut inner = self.inner.write().unwrap();
        
        // Only load non-expired entries
        let now = Local::now();
        for (key, cached) in persisted.versions {
            if cached.resolved_at.timestamp() + cached.ttl.as_secs() as i64 > now.timestamp() {
                inner.versions.insert(key, cached);
            }
        }
        
        info!("Cache loaded from {} ({} valid entries)", path.display(), inner.versions.len());
        Ok(())
    }
}

#[derive(Serialize, Deserialize)]
struct PersistedCache {
    versions: HashMap<String, CachedVersion>,
    saved_at: DateTime<Local>,
}

#[derive(Debug)]
pub struct CacheStatistics {
    pub version_entries: usize,
    pub listing_entries: usize,
    pub total_hits: u64,
    pub total_misses: u64,
    pub total_evictions: u64,
    pub hit_rate: f64,
}

lazy_static::lazy_static! {
    /// Global cache instance
    pub static ref VERSION_CACHE: VersionCache = VersionCache::new();
}

/// Helper to get latest GCC version with caching
pub async fn get_cached_latest_version(major: u8) -> Option<GccVersion> {
    let key = format!("latest_gcc_{}", major);
    VERSION_CACHE.get_version(&key)
}

/// Helper to store latest GCC version in cache
pub fn cache_latest_version(major: u8, version: GccVersion) {
    let key = format!("latest_gcc_{}", major);
    // Cache for 24 hours
    VERSION_CACHE.put_version(key, version, Duration::from_secs(86400));
}