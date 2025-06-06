use std::collections::HashMap;
use std::path::{Path, PathBuf};
use log::{info, debug, warn};
use crate::error::{GccBuildError, Result as GccResult};
use crate::commands::CommandExecutor;
use crate::config::Config;

/// Build cache integration using ccache and sccache
pub struct BuildCache {
    cache_type: CacheType,
    cache_dir: PathBuf,
    max_size_gb: u64,
    executor: CommandExecutor,
    env_vars: HashMap<String, String>,
}

#[derive(Debug, Clone)]
enum CacheType {
    Ccache,
    Sccache,
    None,
}

impl BuildCache {
    pub fn new(config: &Config, executor: CommandExecutor) -> GccResult<Self> {
        let cache_type = Self::detect_cache_type(&executor);
        let cache_dir = config.build_dir.join("cache");
        
        // Default to 10GB cache size
        let max_size_gb = 10;
        
        let mut instance = Self {
            cache_type,
            cache_dir,
            max_size_gb,
            executor,
            env_vars: HashMap::new(),
        };
        
        instance.setup_environment()?;
        
        Ok(instance)
    }
    
    /// Detect available cache type
    fn detect_cache_type(executor: &CommandExecutor) -> CacheType {
        if executor.command_exists("sccache") {
            info!("🚀 Using sccache for build acceleration");
            CacheType::Sccache
        } else if executor.command_exists("ccache") {
            info!("🚀 Using ccache for build acceleration");
            CacheType::Ccache
        } else {
            warn!("⚠️ No build cache found. Install ccache or sccache for faster builds");
            CacheType::None
        }
    }
    
    /// Setup cache environment
    fn setup_environment(&mut self) -> GccResult<()> {
        match &self.cache_type {
            CacheType::Ccache => {
                // Set ccache environment variables
                self.env_vars.insert("CCACHE_DIR".to_string(), 
                                   self.cache_dir.to_string_lossy().to_string());
                self.env_vars.insert("CCACHE_MAXSIZE".to_string(), 
                                   format!("{}G", self.max_size_gb));
                self.env_vars.insert("CCACHE_COMPRESS".to_string(), "1".to_string());
                self.env_vars.insert("CCACHE_COMPRESSLEVEL".to_string(), "6".to_string());
                
                // Use ccache for C/C++ compilation
                self.env_vars.insert("CC".to_string(), "ccache gcc".to_string());
                self.env_vars.insert("CXX".to_string(), "ccache g++".to_string());
                
                // Enable ccache statistics
                self.env_vars.insert("CCACHE_STATS".to_string(), "1".to_string());
            }
            CacheType::Sccache => {
                // Set sccache environment variables
                self.env_vars.insert("SCCACHE_DIR".to_string(), 
                                   self.cache_dir.to_string_lossy().to_string());
                self.env_vars.insert("SCCACHE_CACHE_SIZE".to_string(), 
                                   format!("{}G", self.max_size_gb));
                
                // Use sccache for compilation
                self.env_vars.insert("CC".to_string(), "sccache gcc".to_string());
                self.env_vars.insert("CXX".to_string(), "sccache g++".to_string());
                self.env_vars.insert("RUSTC_WRAPPER".to_string(), "sccache".to_string());
            }
            CacheType::None => {
                // No caching available
            }
        }
        
        Ok(())
    }
    
    /// Initialize the cache
    pub async fn init(&self) -> GccResult<()> {
        if matches!(self.cache_type, CacheType::None) {
            return Ok(());
        }
        
        // Create cache directory
        tokio::fs::create_dir_all(&self.cache_dir).await
            .map_err(|e| GccBuildError::directory_operation(
                "create cache directory",
                self.cache_dir.display().to_string(),
                e.to_string()
            ))?;
        
        match &self.cache_type {
            CacheType::Ccache => {
                // Configure ccache
                self.executor.execute("ccache", ["--set-config", &format!("max_size={}G", self.max_size_gb)]).await?;
                self.executor.execute("ccache", ["--set-config", "compression=true"]).await?;
                self.executor.execute("ccache", ["--set-config", "compression_level=6"]).await?;
                
                // Clear old statistics
                self.executor.execute("ccache", ["--zero-stats"]).await?;
                
                info!("✅ ccache initialized with {}GB cache", self.max_size_gb);
            }
            CacheType::Sccache => {
                // sccache doesn't need explicit initialization
                info!("✅ sccache initialized with {}GB cache", self.max_size_gb);
            }
            CacheType::None => {}
        }
        
        Ok(())
    }
    
    /// Get environment variables for build process
    pub fn get_env_vars(&self) -> &HashMap<String, String> {
        &self.env_vars
    }
    
    /// Get cache statistics
    pub async fn get_stats(&self) -> GccResult<CacheStats> {
        match &self.cache_type {
            CacheType::Ccache => {
                let output = self.executor.execute_with_output("ccache", ["--show-stats"]).await?;
                self.parse_ccache_stats(&output)
            }
            CacheType::Sccache => {
                let output = self.executor.execute_with_output("sccache", ["--show-stats"]).await?;
                self.parse_sccache_stats(&output)
            }
            CacheType::None => Ok(CacheStats::default()),
        }
    }
    
    /// Parse ccache statistics
    fn parse_ccache_stats(&self, output: &str) -> GccResult<CacheStats> {
        let mut stats = CacheStats::default();
        
        for line in output.lines() {
            let line = line.trim();
            if line.contains("cache hit") {
                if let Some(num) = extract_number(line) {
                    stats.hits = num;
                }
            } else if line.contains("cache miss") {
                if let Some(num) = extract_number(line) {
                    stats.misses = num;
                }
            } else if line.contains("cache size") {
                if let Some(size) = extract_size(line) {
                    stats.size_mb = size;
                }
            } else if line.contains("files in cache") {
                if let Some(num) = extract_number(line) {
                    stats.files = num;
                }
            }
        }
        
        stats.hit_rate = if stats.hits + stats.misses > 0 {
            (stats.hits as f64 / (stats.hits + stats.misses) as f64) * 100.0
        } else {
            0.0
        };
        
        Ok(stats)
    }
    
    /// Parse sccache statistics
    fn parse_sccache_stats(&self, output: &str) -> GccResult<CacheStats> {
        let mut stats = CacheStats::default();
        
        for line in output.lines() {
            let line = line.trim();
            if line.contains("Cache hits") {
                if let Some(num) = extract_number(line) {
                    stats.hits = num;
                }
            } else if line.contains("Cache misses") {
                if let Some(num) = extract_number(line) {
                    stats.misses = num;
                }
            } else if line.contains("Cache size") {
                if let Some(size) = extract_size(line) {
                    stats.size_mb = size;
                }
            }
        }
        
        stats.hit_rate = if stats.hits + stats.misses > 0 {
            (stats.hits as f64 / (stats.hits + stats.misses) as f64) * 100.0
        } else {
            0.0
        };
        
        Ok(stats)
    }
    
    /// Show cache statistics
    pub async fn show_stats(&self) -> GccResult<()> {
        let stats = self.get_stats().await?;
        
        if matches!(self.cache_type, CacheType::None) {
            info!("No build cache available");
            return Ok(());
        }
        
        info!("📊 Build Cache Statistics:");
        info!("  • Cache type: {:?}", self.cache_type);
        info!("  • Cache hits: {}", stats.hits);
        info!("  • Cache misses: {}", stats.misses);
        info!("  • Hit rate: {:.1}%", stats.hit_rate);
        info!("  • Cache size: {:.1} MB", stats.size_mb);
        info!("  • Files cached: {}", stats.files);
        
        if stats.hit_rate > 0.0 {
            let saved_time = estimate_time_saved(stats.hits, stats.hit_rate);
            info!("  • Estimated time saved: {:.1} minutes", saved_time);
        }
        
        Ok(())
    }
    
    /// Clear the cache
    pub async fn clear(&self) -> GccResult<()> {
        match &self.cache_type {
            CacheType::Ccache => {
                self.executor.execute("ccache", ["--clear"]).await?;
                info!("🧹 ccache cleared");
            }
            CacheType::Sccache => {
                self.executor.execute("sccache", ["--zero-stats"]).await?;
                // sccache doesn't have a clear command, remove directory
                if self.cache_dir.exists() {
                    tokio::fs::remove_dir_all(&self.cache_dir).await?;
                    tokio::fs::create_dir_all(&self.cache_dir).await?;
                }
                info!("🧹 sccache cleared");
            }
            CacheType::None => {
                info!("No cache to clear");
            }
        }
        
        Ok(())
    }
    
    /// Warm up cache with common compilation patterns
    pub async fn warmup(&self, source_dir: &Path) -> GccResult<()> {
        if matches!(self.cache_type, CacheType::None) {
            return Ok(());
        }
        
        info!("🔥 Warming up build cache...");
        
        // Find common source files to pre-compile
        let common_files = [
            "gcc/tree.c",
            "gcc/rtl.c", 
            "gcc/gimple.c",
            "gcc/fold-const.c",
            "gcc/expr.c",
        ];
        
        for file in common_files {
            let file_path = source_dir.join(file);
            if file_path.exists() {
                debug!("Pre-compiling {}", file);
                
                // Compile to object file (will be cached)
                let obj_file = format!("{}.o", file_path.to_string_lossy());
                let result = self.executor.execute(
                    "gcc",
                    ["-c", "-O2", "-o", &obj_file, file_path.to_str().unwrap()]
                ).await;
                
                // Clean up object file
                if std::path::Path::new(&obj_file).exists() {
                    let _ = tokio::fs::remove_file(&obj_file).await;
                }
                
                if result.is_err() {
                    debug!("Failed to pre-compile {}, continuing...", file);
                }
            }
        }
        
        info!("✅ Cache warmup completed");
        Ok(())
    }
}

#[derive(Debug, Default)]
pub struct CacheStats {
    pub hits: u64,
    pub misses: u64,
    pub hit_rate: f64,
    pub size_mb: f64,
    pub files: u64,
}

/// Extract number from a line like "cache hit (direct)     123"
fn extract_number(line: &str) -> Option<u64> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    for part in parts.iter().rev() {
        if let Ok(num) = part.parse::<u64>() {
            return Some(num);
        }
    }
    None
}

/// Extract size in MB from a line like "cache size           1.2 GB"
fn extract_size(line: &str) -> Option<f64> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    for (i, part) in parts.iter().enumerate() {
        if let Ok(size) = part.parse::<f64>() {
            if i + 1 < parts.len() {
                let unit = parts[i + 1].to_lowercase();
                return Some(match unit.as_str() {
                    "kb" => size / 1024.0,
                    "mb" => size,
                    "gb" => size * 1024.0,
                    _ => size,
                });
            }
        }
    }
    None
}

/// Estimate time saved by cache hits
fn estimate_time_saved(hits: u64, hit_rate: f64) -> f64 {
    // Assume each cache hit saves about 30 seconds of compilation time
    let seconds_per_hit = 30.0;
    let total_seconds_saved = hits as f64 * seconds_per_hit;
    total_seconds_saved / 60.0 // Convert to minutes
}