use std::collections::HashMap;
use std::path::PathBuf;
use std::process;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use log::{info, debug, warn};
use serde::{Deserialize, Serialize};
use crate::config::GccVersion;
use crate::error::{GccBuildError, Result as GccResult};

/// Dynamic memory profiler for GCC builds
#[derive(Clone)]
pub struct MemoryProfiler {
    profiles: Arc<RwLock<ProfileData>>,
    profile_file: PathBuf,
    monitoring_interval: Duration,
}

#[derive(Default, Serialize, Deserialize)]
struct ProfileData {
    build_profiles: HashMap<String, BuildProfile>,
    system_baseline: Option<SystemMemory>,
}

#[derive(Serialize, Deserialize, Clone)]
struct BuildProfile {
    gcc_version: String,
    config_hash: String,
    memory_phases: Vec<MemoryPhase>,
    peak_memory_mb: u64,
    total_duration: Duration,
    build_settings: BuildSettings,
    last_updated: chrono::DateTime<chrono::Local>,
}

#[derive(Serialize, Deserialize, Clone)]
struct MemoryPhase {
    phase_name: String,
    start_memory_mb: u64,
    peak_memory_mb: u64,
    end_memory_mb: u64,
    duration: Duration,
    parallel_jobs: usize,
}

#[derive(Serialize, Deserialize, Clone)]
struct BuildSettings {
    optimization_level: String,
    enable_multilib: bool,
    static_build: bool,
    parallel_jobs: usize,
}

#[derive(Serialize, Deserialize, Clone)]
struct SystemMemory {
    total_mb: u64,
    available_mb: u64,
    cached_mb: u64,
    timestamp: chrono::DateTime<chrono::Local>,
}

impl MemoryProfiler {
    pub fn new(profile_dir: PathBuf) -> Self {
        let profile_file = profile_dir.join("memory_profiles.json");
        
        Self {
            profiles: Arc::new(RwLock::new(ProfileData::default())),
            profile_file,
            monitoring_interval: Duration::from_secs(30),
        }
    }
    
    /// Initialize profiler and load existing data
    pub async fn init(&self) -> GccResult<()> {
        // Create profile directory
        if let Some(parent) = self.profile_file.parent() {
            tokio::fs::create_dir_all(parent).await
                .map_err(|e| GccBuildError::directory_operation(
                    "create profile directory",
                    parent.display().to_string(),
                    e.to_string()
                ))?;
        }
        
        // Load existing profiles
        if self.profile_file.exists() {
            let content = tokio::fs::read_to_string(&self.profile_file).await?;
            if let Ok(data) = serde_json::from_str::<ProfileData>(&content) {
                *self.profiles.write().await = data;
                info!("📊 Loaded {} memory profiles", 
                      self.profiles.read().await.build_profiles.len());
            }
        }
        
        // Record system baseline
        self.record_system_baseline().await?;
        
        Ok(())
    }
    
    /// Record system memory baseline
    async fn record_system_baseline(&self) -> GccResult<()> {
        let baseline = self.get_current_memory().await?;
        self.profiles.write().await.system_baseline = Some(baseline);
        debug!("Recorded system memory baseline: {} MB available", baseline.available_mb);
        Ok(())
    }
    
    /// Start profiling a build
    pub async fn start_build_profile(
        &self,
        gcc_version: &GccVersion,
        config_hash: String,
        build_settings: BuildSettings,
    ) -> GccResult<BuildProfileSession> {
        let profile_key = format!("gcc-{}-{}", gcc_version, &config_hash[..8]);
        
        info!("🔍 Starting memory profile for {}", profile_key);
        
        Ok(BuildProfileSession {
            profiler: self.clone(),
            profile_key,
            gcc_version: gcc_version.clone(),
            config_hash,
            build_settings,
            start_time: Instant::now(),
            phases: Vec::new(),
            peak_memory: 0,
            current_phase: None,
        })
    }
    
    /// Get memory usage estimate for a build
    pub async fn estimate_memory_usage(
        &self,
        gcc_version: &GccVersion,
        config_hash: &str,
        parallel_jobs: usize,
    ) -> GccResult<MemoryEstimate> {
        let profiles = self.profiles.read().await;
        
        // Try exact match first
        let profile_key = format!("gcc-{}-{}", gcc_version, &config_hash[..8]);
        if let Some(profile) = profiles.build_profiles.get(&profile_key) {
            let adjusted_memory = self.adjust_for_parallelism(
                profile.peak_memory_mb,
                profile.build_settings.parallel_jobs,
                parallel_jobs
            );
            
            return Ok(MemoryEstimate {
                estimated_peak_mb: adjusted_memory,
                confidence: 0.9,
                based_on: EstimateSource::ExactMatch,
                similar_builds: 1,
            });
        }
        
        // Find similar builds
        let similar = self.find_similar_builds(&profiles, gcc_version, &config_hash).await;
        
        if !similar.is_empty() {
            let avg_memory: u64 = similar.iter()
                .map(|p| p.peak_memory_mb)
                .sum::<u64>() / similar.len() as u64;
            
            let adjusted_memory = self.adjust_for_parallelism(
                avg_memory,
                similar[0].build_settings.parallel_jobs,
                parallel_jobs
            );
            
            let confidence = if similar.len() >= 3 { 0.8 } else { 0.6 };
            
            return Ok(MemoryEstimate {
                estimated_peak_mb: adjusted_memory,
                confidence,
                based_on: EstimateSource::SimilarBuilds,
                similar_builds: similar.len(),
            });
        }
        
        // Fallback to heuristics
        let base_memory = self.estimate_base_memory(gcc_version);
        let adjusted_memory = self.adjust_for_parallelism(base_memory, 1, parallel_jobs);
        
        Ok(MemoryEstimate {
            estimated_peak_mb: adjusted_memory,
            confidence: 0.4,
            based_on: EstimateSource::Heuristics,
            similar_builds: 0,
        })
    }
    
    /// Find similar builds for estimation
    async fn find_similar_builds(
        &self,
        profiles: &ProfileData,
        gcc_version: &GccVersion,
        config_hash: &str,
    ) -> Vec<&BuildProfile> {
        let mut similar = Vec::new();
        
        for profile in profiles.build_profiles.values() {
            let similarity = self.calculate_similarity(&profile, gcc_version, config_hash);
            if similarity > 0.7 {
                similar.push(profile);
            }
        }
        
        // Sort by recency and similarity
        similar.sort_by(|a, b| b.last_updated.cmp(&a.last_updated));
        similar.truncate(5); // Keep top 5 similar builds
        
        similar
    }
    
    /// Calculate similarity score between builds
    fn calculate_similarity(
        &self,
        profile: &BuildProfile,
        gcc_version: &GccVersion,
        config_hash: &str,
    ) -> f64 {
        let mut score = 0.0;
        
        // Version similarity (major.minor match = 0.5, major match = 0.3)
        if profile.gcc_version == gcc_version.to_string() {
            score += 0.5;
        } else if profile.gcc_version.starts_with(&gcc_version.major.to_string()) {
            score += 0.3;
        }
        
        // Config similarity (more similar configs get higher scores)
        let config_similarity = self.calculate_config_similarity(&profile.config_hash, config_hash);
        score += config_similarity * 0.3;
        
        // Recency bonus (more recent builds are more relevant)
        let days_old = chrono::Local::now()
            .signed_duration_since(profile.last_updated)
            .num_days() as f64;
        let recency_bonus = (30.0 - days_old.min(30.0)) / 30.0 * 0.2;
        score += recency_bonus;
        
        score
    }
    
    /// Calculate config hash similarity
    fn calculate_config_similarity(&self, hash1: &str, hash2: &str) -> f64 {
        let bytes1 = hash1.as_bytes();
        let bytes2 = hash2.as_bytes();
        let min_len = bytes1.len().min(bytes2.len());
        
        if min_len == 0 {
            return 0.0;
        }
        
        let matching_bytes = bytes1.iter()
            .zip(bytes2.iter())
            .take(min_len)
            .filter(|(a, b)| a == b)
            .count();
        
        matching_bytes as f64 / min_len as f64
    }
    
    /// Adjust memory estimate for different parallelism
    fn adjust_for_parallelism(&self, base_memory: u64, base_jobs: usize, target_jobs: usize) -> u64 {
        if base_jobs == 0 || target_jobs == 0 {
            return base_memory;
        }
        
        // Memory usage increases sublinearly with parallelism
        let ratio = (target_jobs as f64 / base_jobs as f64).sqrt();
        (base_memory as f64 * ratio) as u64
    }
    
    /// Estimate base memory usage for a GCC version
    fn estimate_base_memory(&self, gcc_version: &GccVersion) -> u64 {
        // Base estimates in MB based on GCC version
        let base = match gcc_version.major {
            10 => 2500,
            11 => 2800,
            12 => 3200,
            13 => 3500,
            14 => 3800,
            15 => 4000,
            _ => 3000, // Default
        };
        
        base
    }
    
    /// Get current system memory info
    async fn get_current_memory(&self) -> GccResult<SystemMemory> {
        let info = sys_info::mem_info()
            .map_err(|e| GccBuildError::system_requirements(
                format!("Failed to get memory info: {}", e)
            ))?;
        
        Ok(SystemMemory {
            total_mb: info.total / 1024,
            available_mb: info.avail / 1024,
            cached_mb: info.free / 1024, // Approximation
            timestamp: chrono::Local::now(),
        })
    }
    
    /// Save profiles to disk
    async fn save_profiles(&self) -> GccResult<()> {
        let profiles = self.profiles.read().await;
        let json = serde_json::to_string_pretty(&*profiles)?;
        tokio::fs::write(&self.profile_file, json).await?;
        Ok(())
    }
    
    /// Get profiler statistics
    pub async fn get_stats(&self) -> ProfilerStats {
        let profiles = self.profiles.read().await;
        
        let total_profiles = profiles.build_profiles.len();
        let avg_memory = if total_profiles > 0 {
            profiles.build_profiles.values()
                .map(|p| p.peak_memory_mb)
                .sum::<u64>() / total_profiles as u64
        } else {
            0
        };
        
        let recent_profiles = profiles.build_profiles.values()
            .filter(|p| {
                chrono::Local::now()
                    .signed_duration_since(p.last_updated)
                    .num_days() < 30
            })
            .count();
        
        ProfilerStats {
            total_profiles,
            recent_profiles,
            average_peak_memory_mb: avg_memory,
            oldest_profile: profiles.build_profiles.values()
                .map(|p| p.last_updated)
                .min(),
            newest_profile: profiles.build_profiles.values()
                .map(|p| p.last_updated)
                .max(),
        }
    }
}

/// Build profiling session
pub struct BuildProfileSession {
    profiler: MemoryProfiler,
    profile_key: String,
    gcc_version: GccVersion,
    config_hash: String,
    build_settings: BuildSettings,
    start_time: Instant,
    phases: Vec<MemoryPhase>,
    peak_memory: u64,
    current_phase: Option<(String, Instant, u64)>,
}

impl BuildProfileSession {
    /// Start a new phase
    pub async fn start_phase(&mut self, phase_name: &str) -> GccResult<()> {
        // End current phase if any
        if let Some((name, start, start_mem)) = self.current_phase.take() {
            let current_mem = self.profiler.get_current_memory().await?.available_mb;
            let duration = start.elapsed();
            
            self.phases.push(MemoryPhase {
                phase_name: name,
                start_memory_mb: start_mem,
                peak_memory_mb: current_mem, // We should track this during the phase
                end_memory_mb: current_mem,
                duration,
                parallel_jobs: self.build_settings.parallel_jobs,
            });
        }
        
        let current_mem = self.profiler.get_current_memory().await?.available_mb;
        self.current_phase = Some((phase_name.to_string(), Instant::now(), current_mem));
        
        debug!("Started memory profiling phase: {}", phase_name);
        Ok(())
    }
    
    /// Update peak memory for current phase
    pub async fn update_peak_memory(&mut self) -> GccResult<()> {
        let current_mem = self.profiler.get_current_memory().await?.available_mb;
        self.peak_memory = self.peak_memory.max(current_mem);
        Ok(())
    }
    
    /// Finish profiling and save
    pub async fn finish(mut self) -> GccResult<()> {
        // End current phase
        if let Some((name, start, start_mem)) = self.current_phase.take() {
            let current_mem = self.profiler.get_current_memory().await?.available_mb;
            let duration = start.elapsed();
            
            self.phases.push(MemoryPhase {
                phase_name: name,
                start_memory_mb: start_mem,
                peak_memory_mb: current_mem,
                end_memory_mb: current_mem,
                duration,
                parallel_jobs: self.build_settings.parallel_jobs,
            });
        }
        
        // Create build profile
        let profile = BuildProfile {
            gcc_version: self.gcc_version.to_string(),
            config_hash: self.config_hash,
            memory_phases: self.phases,
            peak_memory_mb: self.peak_memory,
            total_duration: self.start_time.elapsed(),
            build_settings: self.build_settings,
            last_updated: chrono::Local::now(),
        };
        
        // Save profile
        {
            let mut profiles = self.profiler.profiles.write().await;
            profiles.build_profiles.insert(self.profile_key.clone(), profile);
        }
        
        self.profiler.save_profiles().await?;
        
        info!("💾 Memory profile saved for {}", self.profile_key);
        Ok(())
    }
}

#[derive(Debug)]
pub struct MemoryEstimate {
    pub estimated_peak_mb: u64,
    pub confidence: f64, // 0.0 to 1.0
    pub based_on: EstimateSource,
    pub similar_builds: usize,
}

#[derive(Debug)]
pub enum EstimateSource {
    ExactMatch,
    SimilarBuilds,
    Heuristics,
}

#[derive(Debug)]
pub struct ProfilerStats {
    pub total_profiles: usize,
    pub recent_profiles: usize,
    pub average_peak_memory_mb: u64,
    pub oldest_profile: Option<chrono::DateTime<chrono::Local>>,
    pub newest_profile: Option<chrono::DateTime<chrono::Local>>,
}