#![allow(dead_code)]
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::RwLock;
use log::{info, debug, warn};
use serde::{Deserialize, Serialize};
use crate::error::{GccBuildError, Result as GccResult};
use crate::commands::CommandExecutor;
use crate::files::FileOperations;
use crate::config::GccVersion;

/// Central cache for GCC prerequisites (GMP, MPFR, MPC)
#[derive(Clone)]
pub struct PrerequisiteCache {
    cache_dir: PathBuf,
    state: Arc<RwLock<CacheState>>,
    command_executor: CommandExecutor,
    file_ops: FileOperations,
}

#[derive(Default, Serialize, Deserialize)]
struct CacheState {
    prerequisites: Vec<PrerequisiteInfo>,
    downloads_in_progress: Vec<String>,
}

#[derive(Clone, Serialize, Deserialize)]
struct PrerequisiteInfo {
    name: String,
    version: String,
    tarball_path: PathBuf,
    extracted_path: PathBuf,
    checksum: String,
    download_url: String,
    size_bytes: u64,
}

impl PrerequisiteCache {
    pub fn new(
        cache_dir: PathBuf,
        command_executor: CommandExecutor,
        file_ops: FileOperations,
    ) -> Self {
        Self {
            cache_dir,
            state: Arc::new(RwLock::new(CacheState::default())),
            command_executor,
            file_ops,
        }
    }
    
    /// Initialize the cache directory and load state
    pub async fn init(&self) -> GccResult<()> {
        // Create cache directory
        tokio::fs::create_dir_all(&self.cache_dir).await
            .map_err(|e| GccBuildError::directory_operation(
                "create prerequisite cache",
                self.cache_dir.display().to_string(),
                e.to_string()
            ))?;
        
        // Load existing state if available
        let state_file = self.cache_dir.join("cache_state.json");
        if state_file.exists() {
            let content = tokio::fs::read_to_string(&state_file).await?;
            if let Ok(state) = serde_json::from_str::<CacheState>(&content) {
                *self.state.write().await = state;
                info!("Loaded prerequisite cache with {} entries", 
                      self.state.read().await.prerequisites.len());
            }
        }
        
        Ok(())
    }
    
    /// Get prerequisites for a GCC version
    pub async fn get_prerequisites(
        &self,
        gcc_version: &GccVersion,
        source_dir: &Path,
    ) -> GccResult<()> {
        info!("🔍 Checking prerequisite cache for GCC {}", gcc_version);
        
        // Read the prerequisites script to determine what's needed
        let script_path = source_dir.join("contrib/download_prerequisites");
        if !script_path.exists() {
            return Err(GccBuildError::file_operation(
                "find prerequisites script",
                script_path.display().to_string(),
                "Script not found".to_string()
            ));
        }
        
        // Parse required prerequisites from the script
        let script_content = tokio::fs::read_to_string(&script_path).await?;
        let required = self.parse_prerequisites(&script_content)?;
        
        // Check cache and download missing prerequisites
        for (name, version, url) in required {
            if !self.is_cached(&name, &version).await {
                self.download_prerequisite(&name, &version, &url).await?;
            }
            
            // Create symlink in source directory
            self.link_prerequisite(&name, &version, source_dir).await?;
        }
        
        // Save cache state
        self.save_state().await?;
        
        Ok(())
    }
    
    /// Parse prerequisites from download script
    fn parse_prerequisites(&self, script: &str) -> GccResult<Vec<(String, String, String)>> {
        let mut prerequisites = Vec::new();
        
        // Look for patterns like: GMP=gmp-6.2.1
        let patterns = [
            (r"GMP=gmp-(\d+\.\d+\.\d+)", "gmp"),
            (r"MPFR=mpfr-(\d+\.\d+\.\d+)", "mpfr"),
            (r"MPC=mpc-(\d+\.\d+\.\d+)", "mpc"),
            (r"ISL=isl-(\d+\.\d+\.\d+)", "isl"),
        ];
        
        for (pattern, name) in patterns {
            let re = regex::Regex::new(pattern).unwrap();
            if let Some(caps) = re.captures(script) {
                let version = caps[1].to_string();
                let url = self.construct_download_url(name, &version);
                prerequisites.push((name.to_string(), version, url));
            }
        }
        
        if prerequisites.is_empty() {
            // Fallback to default versions if parsing fails
            prerequisites.push(("gmp".to_string(), "6.2.1".to_string(), 
                              "https://ftp.gnu.org/gnu/gmp/gmp-6.2.1.tar.xz".to_string()));
            prerequisites.push(("mpfr".to_string(), "4.1.0".to_string(),
                              "https://ftp.gnu.org/gnu/mpfr/mpfr-4.1.0.tar.xz".to_string()));
            prerequisites.push(("mpc".to_string(), "1.2.1".to_string(),
                              "https://ftp.gnu.org/gnu/mpc/mpc-1.2.1.tar.gz".to_string()));
        }
        
        Ok(prerequisites)
    }
    
    /// Construct download URL for a prerequisite
    fn construct_download_url(&self, name: &str, version: &str) -> String {
        match name {
            "gmp" => format!("https://ftp.gnu.org/gnu/gmp/gmp-{}.tar.xz", version),
            "mpfr" => format!("https://ftp.gnu.org/gnu/mpfr/mpfr-{}.tar.xz", version),
            "mpc" => format!("https://ftp.gnu.org/gnu/mpc/mpc-{}.tar.gz", version),
            "isl" => format!("https://libisl.sourceforge.io/isl-{}.tar.xz", version),
            _ => format!("https://ftp.gnu.org/gnu/{}/{}-{}.tar.xz", name, name, version),
        }
    }
    
    /// Check if prerequisite is cached
    async fn is_cached(&self, name: &str, version: &str) -> bool {
        let state = self.state.read().await;
        state.prerequisites.iter().any(|p| p.name == name && p.version == version)
    }
    
    /// Download a prerequisite
    async fn download_prerequisite(
        &self,
        name: &str,
        version: &str,
        url: &str,
    ) -> GccResult<()> {
        // Check if already downloading
        {
            let mut state = self.state.write().await;
            if state.downloads_in_progress.contains(&name.to_string()) {
                debug!("Download already in progress for {}", name);
                // Wait for download to complete
                drop(state);
                while self.state.read().await.downloads_in_progress.contains(&name.to_string()) {
                    tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
                }
                return Ok(());
            }
            state.downloads_in_progress.push(name.to_string());
        }
        
        info!("📥 Downloading {} {} from cache", name, version);
        
        let filename = url.split('/').last().unwrap();
        let tarball_path = self.cache_dir.join(filename);
        
        // Download with retry
        let retry_count = 3;
        for attempt in 1..=retry_count {
            match self.command_executor.execute_with_output(
                "curl",
                ["-fSL", "-o", tarball_path.to_str().unwrap(), url]
            ).await {
                Ok(_) => break,
                Err(e) if attempt < retry_count => {
                    warn!("Download attempt {} failed: {}", attempt, e);
                    tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
                }
                Err(e) => return Err(e),
            }
        }
        
        // Calculate checksum
        let checksum = self.file_ops.calculate_checksum(&tarball_path)?;
        
        // Extract to cache
        let extracted_path = self.cache_dir.join(format!("{}-{}", name, version));
        if !extracted_path.exists() {
            info!("📦 Extracting {} to cache", name);
            self.extract_tarball(&tarball_path, &extracted_path).await?;
        }
        
        // Get file size
        let metadata = tokio::fs::metadata(&tarball_path).await?;
        
        // Update state
        {
            let mut state = self.state.write().await;
            state.prerequisites.push(PrerequisiteInfo {
                name: name.to_string(),
                version: version.to_string(),
                tarball_path,
                extracted_path,
                checksum,
                download_url: url.to_string(),
                size_bytes: metadata.len(),
            });
            state.downloads_in_progress.retain(|n| n != name);
        }
        
        info!("✅ Cached {} {} for future use", name, version);
        Ok(())
    }
    
    /// Extract tarball to directory
    async fn extract_tarball(&self, tarball: &Path, _target: &Path) -> GccResult<()> {
        let tar_cmd = if tarball.to_string_lossy().ends_with(".tar.xz") {
            vec!["tar", "-xJf", tarball.to_str().unwrap(), "-C", self.cache_dir.to_str().unwrap()]
        } else {
            vec!["tar", "-xzf", tarball.to_str().unwrap(), "-C", self.cache_dir.to_str().unwrap()]
        };
        
        self.command_executor.execute(&tar_cmd[0], &tar_cmd[1..]).await?;
        Ok(())
    }
    
    /// Create symlink to prerequisite in source directory
    async fn link_prerequisite(
        &self,
        name: &str,
        version: &str,
        source_dir: &Path,
    ) -> GccResult<()> {
        let state = self.state.read().await;
        let prereq = state.prerequisites.iter()
            .find(|p| p.name == name && p.version == version)
            .ok_or_else(|| GccBuildError::configuration(
                format!("Prerequisite {} {} not found in cache", name, version)
            ))?;
        
        let link_path = source_dir.join(name);
        
        // Remove existing link/directory
        if link_path.exists() {
            if link_path.is_symlink() {
                tokio::fs::remove_file(&link_path).await?;
            } else if link_path.is_dir() {
                tokio::fs::remove_dir_all(&link_path).await?;
            }
        }
        
        // Create symlink
        #[cfg(unix)]
        {
            use std::os::unix::fs::symlink;
            symlink(&prereq.extracted_path, &link_path)
                .map_err(|e| GccBuildError::file_operation(
                    "create symlink",
                    link_path.display().to_string(),
                    e.to_string()
                ))?;
        }
        
        #[cfg(windows)]
        {
            // On Windows, copy instead of symlink
            self.command_executor.execute(
                "xcopy",
                ["/E", "/I", "/Q", 
                 prereq.extracted_path.to_str().unwrap(),
                 link_path.to_str().unwrap()]
            ).await?;
        }
        
        debug!("Linked {} -> {}", link_path.display(), prereq.extracted_path.display());
        Ok(())
    }
    
    /// Save cache state to disk
    async fn save_state(&self) -> GccResult<()> {
        let state_file = self.cache_dir.join("cache_state.json");
        let state = self.state.read().await;
        let json = serde_json::to_string_pretty(&*state)?;
        tokio::fs::write(&state_file, json).await?;
        Ok(())
    }
    
    /// Get cache statistics
    pub async fn get_stats(&self) -> CacheStats {
        let state = self.state.read().await;
        let total_size: u64 = state.prerequisites.iter()
            .map(|p| p.size_bytes)
            .sum();
        
        CacheStats {
            total_prerequisites: state.prerequisites.len(),
            total_size_mb: total_size / 1_000_000,
            unique_versions: state.prerequisites.iter()
                .map(|p| &p.name)
                .collect::<std::collections::HashSet<_>>()
                .len(),
        }
    }
    
    /// Clean up old prerequisites
    pub async fn cleanup_old(&self, keep_latest: usize) -> GccResult<()> {
        let mut state = self.state.write().await;
        
        // Group by name
        let mut by_name: std::collections::HashMap<String, Vec<PrerequisiteInfo>> = 
            std::collections::HashMap::new();
        
        for prereq in state.prerequisites.drain(..) {
            by_name.entry(prereq.name.clone()).or_default().push(prereq);
        }
        
        // Keep only latest versions
        for (_name, mut versions) in by_name {
            versions.sort_by(|a, b| b.version.cmp(&a.version));
            let to_keep = versions.into_iter().take(keep_latest);
            state.prerequisites.extend(to_keep);
        }
        
        info!("Cleaned up prerequisite cache, kept {} entries", state.prerequisites.len());
        Ok(())
    }
}

#[derive(Debug)]
pub struct CacheStats {
    pub total_prerequisites: usize,
    pub total_size_mb: u64,
    pub unique_versions: usize,
}