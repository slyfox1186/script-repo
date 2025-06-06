use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};
use tokio::fs;
use log::{info, debug, warn};
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use crate::config::GccVersion;
use crate::error::{GccBuildError, Result as GccResult};
use crate::commands::CommandExecutor;

/// Full GCC build artifact caching system
/// Caches complete GCC installations to avoid redundant builds
#[derive(Clone)]
pub struct ArtifactCache {
    cache_dir: PathBuf,
    index: CacheIndex,
    max_cache_size_gb: u64,
    max_age_days: u64,
    executor: CommandExecutor,
}

#[derive(Serialize, Deserialize, Default, Clone)]
struct CacheIndex {
    artifacts: HashMap<String, ArtifactEntry>,
    total_size_bytes: u64,
    last_cleanup: Option<SystemTime>,
}

#[derive(Serialize, Deserialize, Clone)]
struct ArtifactEntry {
    gcc_version: String,
    config_hash: String,
    install_path: PathBuf,
    size_bytes: u64,
    created_at: SystemTime,
    last_accessed: SystemTime,
    build_time_seconds: u64,
    verification_hash: String,
    build_config: BuildConfig,
}

#[derive(Serialize, Deserialize, Clone)]
struct BuildConfig {
    optimization_level: String,
    enable_multilib: bool,
    static_build: bool,
    target_architectures: Vec<String>,
    configure_args: Vec<String>,
}

impl ArtifactCache {
    pub fn new(cache_dir: PathBuf, max_cache_size_gb: u64) -> Self {
        Self {
            cache_dir,
            index: CacheIndex::default(),
            max_cache_size_gb,
            max_age_days: 90, // Keep artifacts for 90 days
            executor: CommandExecutor::new(false, false),
        }
    }
    
    /// Initialize cache and load index
    pub async fn init(&mut self) -> GccResult<()> {
        // Create cache directory
        fs::create_dir_all(&self.cache_dir).await
            .map_err(|e| GccBuildError::directory_operation(
                "create artifact cache",
                self.cache_dir.display().to_string(),
                e.to_string()
            ))?;
        
        // Load existing index
        let index_path = self.cache_dir.join("index.json");
        if index_path.exists() {
            let content = fs::read_to_string(&index_path).await?;
            if let Ok(index) = serde_json::from_str::<CacheIndex>(&content) {
                self.index = index;
                info!("📦 Loaded artifact cache with {} entries ({:.1} GB)", 
                      self.index.artifacts.len(),
                      self.index.total_size_bytes as f64 / 1_000_000_000.0);
            }
        }
        
        // Perform cleanup if needed
        self.cleanup_if_needed().await?;
        
        Ok(())
    }
    
    /// Check if a build artifact exists in cache
    pub async fn get_artifact(
        &mut self,
        gcc_version: &GccVersion,
        config_hash: &str,
    ) -> GccResult<Option<PathBuf>> {
        let cache_key = self.generate_cache_key(gcc_version, config_hash);
        
        if let Some(entry) = self.index.artifacts.get_mut(&cache_key) {
            // Verify artifact still exists and is valid
            if entry.install_path.exists() && self.verify_artifact(entry).await? {
                // Update access time
                entry.last_accessed = SystemTime::now();
                self.save_index().await?;
                
                info!("🎯 Cache HIT for GCC {} (saved ~{}min build time)", 
                      gcc_version, entry.build_time_seconds / 60);
                
                return Ok(Some(entry.install_path.clone()));
            } else {
                // Remove invalid entry
                warn!("🗑️ Removing invalid cache entry for {}", cache_key);
                self.remove_artifact(&cache_key).await?;
            }
        }
        
        debug!("📦 Cache MISS for GCC {}", gcc_version);
        Ok(None)
    }
    
    /// Store a completed GCC build in cache
    pub async fn store_artifact(
        &mut self,
        gcc_version: &GccVersion,
        config_hash: String,
        source_path: &Path,
        build_time_seconds: u64,
        build_config: BuildConfig,
    ) -> GccResult<()> {
        let cache_key = self.generate_cache_key(gcc_version, &config_hash);
        let install_path = self.cache_dir.join(&cache_key);
        
        info!("💾 Storing GCC {} build artifact in cache...", gcc_version);
        
        // Create cache entry directory
        fs::create_dir_all(&install_path).await?;
        
        // Copy the entire GCC installation
        let copy_start = std::time::Instant::now();
        self.copy_installation(source_path, &install_path).await?;
        let copy_duration = copy_start.elapsed();
        
        // Calculate size and verification hash
        let size_bytes = self.calculate_directory_size(&install_path).await?;
        let verification_hash = self.calculate_verification_hash(&install_path).await?;
        
        // Create cache entry
        let entry = ArtifactEntry {
            gcc_version: gcc_version.to_string(),
            config_hash,
            install_path: install_path.clone(),
            size_bytes,
            created_at: SystemTime::now(),
            last_accessed: SystemTime::now(),
            build_time_seconds,
            verification_hash,
            build_config,
        };
        
        // Update index
        self.index.artifacts.insert(cache_key, entry);
        self.index.total_size_bytes += size_bytes;
        self.save_index().await?;
        
        info!("✅ Cached GCC {} ({:.1} GB, copied in {:?})", 
              gcc_version, 
              size_bytes as f64 / 1_000_000_000.0,
              copy_duration);
        
        // Clean up if cache is too large
        if self.index.total_size_bytes > self.max_cache_size_gb * 1_000_000_000 {
            self.evict_old_artifacts().await?;
        }
        
        Ok(())
    }
    
    /// Copy GCC installation efficiently
    async fn copy_installation(&self, source: &Path, dest: &Path) -> GccResult<()> {
        // Use rsync for efficient copying with hard links where possible
        let result = self.executor.execute("rsync", [
            "-a",           // Archive mode
            "-H",           // Preserve hard links
            "--stats",      // Show statistics
            &format!("{}/", source.display()), // Source with trailing slash
            &dest.display().to_string(),       // Destination
        ]).await;
        
        if result.is_err() {
            // Fallback to cp if rsync not available
            warn!("rsync failed, falling back to cp");
            self.executor.execute("cp", [
                "-r",
                &source.display().to_string(),
                &dest.display().to_string(),
            ]).await?;
        }
        
        Ok(())
    }
    
    /// Calculate directory size recursively
    async fn calculate_directory_size(&self, path: &Path) -> GccResult<u64> {
        let path = path.to_path_buf();
        tokio::task::spawn_blocking(move || {
            use std::fs;
            fn dir_size(path: &std::path::Path) -> std::io::Result<u64> {
                let mut total = 0;
                for entry in fs::read_dir(path)? {
                    let entry = entry?;
                    let metadata = entry.metadata()?;
                    if metadata.is_file() {
                        total += metadata.len();
                    } else if metadata.is_dir() {
                        total += dir_size(&entry.path())?;
                    }
                }
                Ok(total)
            }
            dir_size(&path)
        })
        .await
        .map_err(|e| GccBuildError::io_error("join", e.to_string()))?
        .map_err(|e| GccBuildError::io_error("dir_size", e.to_string()))
    }
    
    /// Calculate verification hash for integrity checking
    async fn calculate_verification_hash(&self, path: &Path) -> GccResult<String> {
        let mut hasher = Sha256::new();
        
        // Hash key files for verification (not the entire installation)
        let key_files = [
            "bin/gcc",
            "bin/g++",
            "lib/gcc",
            "include",
        ];
        
        for file in &key_files {
            let file_path = path.join(file);
            if file_path.exists() {
                if file_path.is_file() {
                    let content = fs::read(&file_path).await?;
                    hasher.update(&content);
                } else {
                    // For directories, hash the structure
                    hasher.update(file_path.display().to_string().as_bytes());
                }
            }
        }
        
        Ok(format!("{:x}", hasher.finalize()))
    }
    
    /// Verify artifact integrity
    async fn verify_artifact(&self, entry: &ArtifactEntry) -> GccResult<bool> {
        if !entry.install_path.exists() {
            return Ok(false);
        }
        
        // Quick verification - check if key executables exist
        let gcc_bin = entry.install_path.join("bin/gcc");
        let gpp_bin = entry.install_path.join("bin/g++");
        
        if !gcc_bin.exists() || !gpp_bin.exists() {
            return Ok(false);
        }
        
        // Optional: Full hash verification (expensive)
        // let current_hash = self.calculate_verification_hash(&entry.install_path).await?;
        // Ok(current_hash == entry.verification_hash)
        
        Ok(true)
    }
    
    /// Generate cache key for a build configuration
    fn generate_cache_key(&self, gcc_version: &GccVersion, config_hash: &str) -> String {
        format!("gcc-{}-{}", gcc_version, &config_hash[..16])
    }
    
    /// Remove artifact from cache
    async fn remove_artifact(&mut self, cache_key: &str) -> GccResult<()> {
        if let Some(entry) = self.index.artifacts.remove(cache_key) {
            self.index.total_size_bytes = self.index.total_size_bytes
                .saturating_sub(entry.size_bytes);
            
            if entry.install_path.exists() {
                fs::remove_dir_all(&entry.install_path).await?;
            }
            
            self.save_index().await?;
        }
        Ok(())
    }
    
    /// Evict old artifacts when cache is full
    async fn evict_old_artifacts(&mut self) -> GccResult<()> {
        info!("🧹 Cache size exceeded, evicting old artifacts...");
        
        // Sort by last access time (oldest first) - clone keys to avoid borrow issues
        let mut entries: Vec<_> = self.index.artifacts.iter()
            .map(|(k, v)| (k.clone(), v.last_accessed))
            .collect();
        entries.sort_by_key(|(_, last_accessed)| *last_accessed);
        
        let target_size = (self.max_cache_size_gb * 1_000_000_000) * 80 / 100; // Target 80% of max
        let mut current_size = self.index.total_size_bytes;
        
        for (cache_key, _) in entries {
            if current_size <= target_size {
                break;
            }
            
            if let Some(entry) = self.index.artifacts.get(&cache_key) {
                current_size = current_size.saturating_sub(entry.size_bytes);
                info!("🗑️ Evicting old artifact: {}", cache_key);
            }
            
            self.remove_artifact(&cache_key).await?;
        }
        
        info!("✅ Cache cleanup completed ({:.1} GB freed)", 
              (self.index.total_size_bytes - current_size) as f64 / 1_000_000_000.0);
        
        Ok(())
    }
    
    /// Cleanup old artifacts if needed
    async fn cleanup_if_needed(&mut self) -> GccResult<()> {
        let should_cleanup = match self.index.last_cleanup {
            Some(last) => last.elapsed().unwrap_or(Duration::ZERO) > Duration::from_secs(86400), // 1 day
            None => true,
        };
        
        if should_cleanup {
            self.cleanup_expired_artifacts().await?;
            self.index.last_cleanup = Some(SystemTime::now());
            self.save_index().await?;
        }
        
        Ok(())
    }
    
    /// Remove expired artifacts
    async fn cleanup_expired_artifacts(&mut self) -> GccResult<()> {
        let expiry_threshold = SystemTime::now() - Duration::from_secs(self.max_age_days * 86400);
        let mut expired_keys = Vec::new();
        
        for (key, entry) in &self.index.artifacts {
            if entry.created_at < expiry_threshold {
                expired_keys.push(key.clone());
            }
        }
        
        if !expired_keys.is_empty() {
            info!("🧹 Removing {} expired artifacts", expired_keys.len());
            for key in expired_keys {
                self.remove_artifact(&key).await?;
            }
        }
        
        Ok(())
    }
    
    /// Save cache index
    async fn save_index(&self) -> GccResult<()> {
        let index_path = self.cache_dir.join("index.json");
        let json = serde_json::to_string_pretty(&self.index)?;
        fs::write(index_path, json).await?;
        Ok(())
    }
    
    /// Get cache statistics
    pub fn get_stats(&self) -> CacheStats {
        let total_entries = self.index.artifacts.len();
        let total_size_gb = self.index.total_size_bytes as f64 / 1_000_000_000.0;
        
        let total_saved_time: u64 = self.index.artifacts.values()
            .map(|e| e.build_time_seconds)
            .sum();
        
        let avg_artifact_size = if total_entries > 0 {
            self.index.total_size_bytes / total_entries as u64
        } else {
            0
        };
        
        CacheStats {
            total_artifacts: total_entries,
            total_size_gb,
            max_size_gb: self.max_cache_size_gb,
            utilization_percent: (total_size_gb / self.max_cache_size_gb as f64 * 100.0).min(100.0),
            total_saved_time_hours: total_saved_time as f64 / 3600.0,
            average_artifact_size_mb: avg_artifact_size as f64 / 1_000_000.0,
        }
    }
    
    /// List all cached artifacts
    pub fn list_artifacts(&self) -> Vec<ArtifactSummary> {
        self.index.artifacts.iter()
            .map(|(key, entry)| ArtifactSummary {
                cache_key: key.clone(),
                gcc_version: entry.gcc_version.clone(),
                size_mb: entry.size_bytes as f64 / 1_000_000.0,
                age_days: entry.created_at.elapsed()
                    .unwrap_or(Duration::ZERO)
                    .as_secs() as f64 / 86400.0,
                last_used_days: entry.last_accessed.elapsed()
                    .unwrap_or(Duration::ZERO)
                    .as_secs() as f64 / 86400.0,
                build_time_minutes: entry.build_time_seconds as f64 / 60.0,
            })
            .collect()
    }
}

#[derive(Debug)]
pub struct CacheStats {
    pub total_artifacts: usize,
    pub total_size_gb: f64,
    pub max_size_gb: u64,
    pub utilization_percent: f64,
    pub total_saved_time_hours: f64,
    pub average_artifact_size_mb: f64,
}

#[derive(Debug)]
pub struct ArtifactSummary {
    pub cache_key: String,
    pub gcc_version: String,
    pub size_mb: f64,
    pub age_days: f64,
    pub last_used_days: f64,
    pub build_time_minutes: f64,
}

impl BuildConfig {
    pub fn from_args(
        optimization_level: String,
        enable_multilib: bool,
        static_build: bool,
        target_architectures: Vec<String>,
        configure_args: Vec<String>,
    ) -> Self {
        Self {
            optimization_level,
            enable_multilib,
            static_build,
            target_architectures,
            configure_args,
        }
    }
    
    pub fn generate_hash(&self) -> String {
        let mut hasher = Sha256::new();
        hasher.update(&self.optimization_level);
        hasher.update(&self.enable_multilib.to_string());
        hasher.update(&self.static_build.to_string());
        hasher.update(&self.target_architectures.join(","));
        hasher.update(&self.configure_args.join(" "));
        format!("{:x}", hasher.finalize())
    }
}