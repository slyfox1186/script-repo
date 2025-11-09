#![allow(dead_code)]
use crate::config::{Config, GccVersion};
use crate::error::{GccBuildError, Result as GccResult};
use log::{debug, info};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// Auto-tuning system for optimal build configuration based on system capabilities
#[derive(Clone)]
pub struct AutoTuner {
    system_profile: SystemProfile,
    tuning_rules: TuningRules,
    optimization_cache: HashMap<String, OptimizedConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SystemProfile {
    cpu_cores: usize,
    cpu_threads: usize,
    cpu_architecture: String,
    cpu_features: Vec<String>,
    total_memory_gb: f64,
    available_memory_gb: f64,
    disk_type: DiskType,
    disk_space_gb: f64,
    network_bandwidth_mbps: Option<f64>,
    system_load: f64,
    platform: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
enum DiskType {
    Hdd,
    Ssd,
    NvMe,
    Unknown,
}

#[derive(Debug, Clone)]
struct TuningRules {
    memory_rules: MemoryTuningRules,
    cpu_rules: CpuTuningRules,
    disk_rules: DiskTuningRules,
    gcc_rules: GccTuningRules,
}

#[derive(Debug, Clone)]
struct MemoryTuningRules {
    min_memory_per_job_gb: f64,
    memory_safety_margin: f64,
    swap_penalty_factor: f64,
}

#[derive(Debug, Clone)]
struct CpuTuningRules {
    max_cpu_utilization: f64,
    hyperthreading_efficiency: f64,
    load_adjustment_factor: f64,
}

#[derive(Debug, Clone)]
struct DiskTuningRules {
    parallel_io_factor: f64,
    temp_space_multiplier: f64,
}

#[derive(Debug, Clone)]
struct GccTuningRules {
    optimization_presets: HashMap<String, OptimizationPreset>,
    version_specific_adjustments: HashMap<String, VersionAdjustments>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OptimizedConfig {
    pub parallel_jobs: usize,
    pub optimization_level: String,
    pub memory_limit_mb: Option<u64>,
    pub temp_dir: Option<PathBuf>,
    pub configure_args: Vec<String>,
    pub make_args: Vec<String>,
    pub environment_vars: HashMap<String, String>,
    pub rationale: String,
}

#[derive(Debug, Clone)]
struct OptimizationPreset {
    base_flags: Vec<String>,
    memory_multiplier: f64,
    cpu_multiplier: f64,
}

#[derive(Debug, Clone)]
struct VersionAdjustments {
    memory_overhead_factor: f64,
    compilation_time_factor: f64,
    special_flags: Vec<String>,
}

impl AutoTuner {
    pub async fn new() -> GccResult<Self> {
        let system_profile = Self::profile_system().await?;
        let tuning_rules = Self::create_tuning_rules();

        info!(
            "🎯 Auto-tuner initialized for {} cores, {:.1}GB RAM, {:?} storage",
            system_profile.cpu_cores, system_profile.total_memory_gb, system_profile.disk_type
        );

        Ok(Self {
            system_profile,
            tuning_rules,
            optimization_cache: HashMap::new(),
        })
    }

    /// Generate optimized configuration for a specific GCC build
    pub async fn optimize_config(
        &mut self,
        gcc_version: &GccVersion,
        base_config: &Config,
    ) -> GccResult<OptimizedConfig> {
        let cache_key = format!("{}-{:?}", gcc_version, base_config.optimization_level);

        // Check cache first
        if let Some(cached) = self.optimization_cache.get(&cache_key) {
            debug!("🎯 Using cached optimization for {}", cache_key);
            return Ok(cached.clone());
        }

        info!("🔧 Auto-tuning configuration for GCC {}", gcc_version);

        // Generate optimized configuration
        let optimized = self
            .generate_optimized_config(gcc_version, base_config)
            .await?;

        // Cache the result
        self.optimization_cache.insert(cache_key, optimized.clone());

        info!(
            "✅ Optimized: {} jobs, {} optimization, {:.1}GB memory limit",
            optimized.parallel_jobs,
            optimized.optimization_level,
            optimized.memory_limit_mb.unwrap_or(0) as f64 / 1024.0
        );

        Ok(optimized)
    }

    /// Generate optimized configuration
    async fn generate_optimized_config(
        &self,
        gcc_version: &GccVersion,
        base_config: &Config,
    ) -> GccResult<OptimizedConfig> {
        let mut rationale = Vec::new();

        // Optimize parallel jobs
        let parallel_jobs = self
            .optimize_parallel_jobs(gcc_version, &mut rationale)
            .await?;

        // Optimize memory settings
        let memory_limit_mb = self
            .optimize_memory_limit(parallel_jobs, &mut rationale)
            .await;

        // Optimize compilation flags
        let (optimization_level, configure_args) = self
            .optimize_compilation_flags(gcc_version, base_config, &mut rationale)
            .await?;

        // Optimize make arguments
        let make_args = self.optimize_make_args(parallel_jobs, &mut rationale).await;

        // Optimize environment
        let environment_vars = self
            .optimize_environment(gcc_version, &mut rationale)
            .await?;

        // Optimize temporary directory
        let temp_dir = self.optimize_temp_directory(&mut rationale).await?;

        Ok(OptimizedConfig {
            parallel_jobs,
            optimization_level,
            memory_limit_mb,
            temp_dir,
            configure_args,
            make_args,
            environment_vars,
            rationale: rationale.join("; "),
        })
    }

    /// Optimize parallel job count based on system capabilities
    async fn optimize_parallel_jobs(
        &self,
        gcc_version: &GccVersion,
        rationale: &mut Vec<String>,
    ) -> GccResult<usize> {
        let profile = &self.system_profile;
        let rules = &self.tuning_rules;

        // Start with logical CPU count
        let mut jobs = profile.cpu_threads;

        // Apply hyperthreading efficiency
        if profile.cpu_threads > profile.cpu_cores {
            let efficiency = rules.cpu_rules.hyperthreading_efficiency;
            jobs = ((profile.cpu_cores as f64) * (1.0 + efficiency)).round() as usize;
            rationale.push(format!("Hyperthreading efficiency: {:.1}", efficiency));
        }

        // Memory constraint
        let memory_per_job = rules.memory_rules.min_memory_per_job_gb;
        let max_jobs_by_memory = (profile.available_memory_gb / memory_per_job) as usize;
        if max_jobs_by_memory < jobs {
            jobs = max_jobs_by_memory.max(1);
            rationale.push(format!("Memory limited to {} jobs", jobs));
        }

        // GCC version specific adjustments
        if let Some(adjustments) = rules
            .gcc_rules
            .version_specific_adjustments
            .get(&gcc_version.major.to_string())
        {
            let factor = adjustments.memory_overhead_factor;
            if factor > 1.0 {
                jobs = ((jobs as f64) / factor).ceil() as usize;
                rationale.push(format!(
                    "GCC {} overhead adjustment: -{:.0}%",
                    gcc_version.major,
                    (factor - 1.0) * 100.0
                ));
            }
        }

        // System load adjustment
        if profile.system_load > 1.0 {
            let adjustment = rules.cpu_rules.load_adjustment_factor;
            jobs = ((jobs as f64) * adjustment).max(1.0) as usize;
            rationale.push(format!(
                "High load adjustment: -{:.0}%",
                (1.0 - adjustment) * 100.0
            ));
        }

        // Disk I/O consideration for non-Ssd storage
        if let DiskType::Hdd = profile.disk_type {
            let io_factor = rules.disk_rules.parallel_io_factor;
            jobs = ((jobs as f64) * io_factor).max(1.0) as usize;
            rationale.push("Hdd I/O limitation applied".to_string());
        }

        // Never exceed CPU count or go below 1
        jobs = jobs.min(profile.cpu_threads).max(1);

        rationale.push(format!("Optimal jobs: {}", jobs));
        Ok(jobs)
    }

    /// Optimize memory limit
    async fn optimize_memory_limit(
        &self,
        parallel_jobs: usize,
        rationale: &mut Vec<String>,
    ) -> Option<u64> {
        let profile = &self.system_profile;
        let rules = &self.tuning_rules;

        // Calculate safe memory limit
        let safety_margin = rules.memory_rules.memory_safety_margin;
        let usable_memory = profile.available_memory_gb * (1.0 - safety_margin);
        let memory_per_job = usable_memory / parallel_jobs as f64;

        if memory_per_job < 2.0 {
            // If less than 2GB per job, set explicit limit
            let limit_mb = (memory_per_job * 1024.0) as u64;
            rationale.push(format!("Memory limit: {}MB per job", limit_mb));
            Some(limit_mb * parallel_jobs as u64)
        } else {
            rationale.push("Sufficient memory available".to_string());
            None
        }
    }

    /// Optimize compilation flags
    async fn optimize_compilation_flags(
        &self,
        _gcc_version: &GccVersion,
        base_config: &Config,
        rationale: &mut Vec<String>,
    ) -> GccResult<(String, Vec<String>)> {
        let profile = &self.system_profile;
        let _rules = &self.tuning_rules;

        let mut optimization_level = base_config.optimization_level.clone();
        let mut configure_args = Vec::new();

        // Detect and use CPU-specific optimizations
        if profile.cpu_features.contains(&"avx2".to_string()) {
            configure_args.push("--with-arch=native".to_string());
            rationale.push("Native CPU optimizations enabled".to_string());
        }

        // Memory-aware optimizations
        if profile.total_memory_gb < 8.0 {
            configure_args.push("--disable-libstdcxx-pch".to_string());
            rationale.push("Disabled PCH for low memory".to_string());
        }

        // Disk space optimizations
        if profile.disk_space_gb < 50.0 {
            configure_args.push("--disable-multilib".to_string());
            rationale.push("Disabled multilib for disk space".to_string());
        }

        // Platform-specific optimizations
        if profile.platform.contains("linux") {
            configure_args.push("--with-system-zlib".to_string());
            rationale.push("Using system zlib".to_string());
        }

        // Optimization level adjustment based on available resources
        if optimization_level == "O3" && profile.total_memory_gb < 16.0 {
            optimization_level = crate::cli::OptimizationLevel::O2;
            rationale.push("Reduced optimization level for memory".to_string());
        }

        Ok((optimization_level.to_string(), configure_args))
    }

    /// Optimize make arguments
    async fn optimize_make_args(
        &self,
        parallel_jobs: usize,
        rationale: &mut Vec<String>,
    ) -> Vec<String> {
        let mut make_args = vec![format!("-j{}", parallel_jobs)];

        // Add load balancing
        make_args.push(format!("-l{}", parallel_jobs + 2));
        rationale.push("Load balancing enabled".to_string());

        // Silent mode for cleaner logs
        make_args.push("-s".to_string());

        make_args
    }

    /// Optimize environment variables
    async fn optimize_environment(
        &self,
        gcc_version: &GccVersion,
        rationale: &mut Vec<String>,
    ) -> GccResult<HashMap<String, String>> {
        let profile = &self.system_profile;
        let mut env_vars = HashMap::new();

        // Memory management
        env_vars.insert("MALLOC_ARENA_MAX".to_string(), "4".to_string());
        rationale.push("Limited malloc arenas".to_string());

        // Temporary directory optimization
        if matches!(profile.disk_type, DiskType::Ssd | DiskType::NvMe) {
            env_vars.insert("TMPDIR".to_string(), "/tmp".to_string());
            rationale.push("Using fast temp storage".to_string());
        }

        // Compiler cache settings
        if profile.total_memory_gb > 8.0 {
            env_vars.insert("CCACHE_MAXSIZE".to_string(), "10G".to_string());
            env_vars.insert("CCACHE_COMPRESS".to_string(), "1".to_string());
            rationale.push("Optimized ccache settings".to_string());
        }

        // GCC-specific environment tuning
        if gcc_version.major >= 11 {
            env_vars.insert(
                "GCC_COLORS".to_string(),
                "error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01".to_string(),
            );
            rationale.push("Enhanced error colors".to_string());
        }

        Ok(env_vars)
    }

    /// Optimize temporary directory selection
    async fn optimize_temp_directory(
        &self,
        rationale: &mut Vec<String>,
    ) -> GccResult<Option<PathBuf>> {
        let profile = &self.system_profile;

        // Prefer fast storage for temporary files
        match profile.disk_type {
            DiskType::NvMe => {
                rationale.push("Using NVMe temp storage".to_string());
                Ok(Some(PathBuf::from("/tmp")))
            }
            DiskType::Ssd => {
                rationale.push("Using Ssd temp storage".to_string());
                Ok(Some(PathBuf::from("/tmp")))
            }
            DiskType::Hdd => {
                // Check if tmpfs is available and has enough space
                if let Ok(stat) = tokio::fs::metadata("/dev/shm").await {
                    if stat.len() > 2_000_000_000 {
                        // 2GB
                        rationale.push("Using tmpfs for temp storage".to_string());
                        return Ok(Some(PathBuf::from("/dev/shm")));
                    }
                }
                rationale.push("Using default temp storage".to_string());
                Ok(None)
            }
            DiskType::Unknown => {
                rationale.push("Unknown disk type, using default".to_string());
                Ok(None)
            }
        }
    }

    /// Profile the current system
    async fn profile_system() -> GccResult<SystemProfile> {
        // Get system info using sys_info crate
        let cpu_info = CpuInfo {
            physical_cores: sys_info::cpu_num().unwrap_or(4) as usize / 2,
            logical_cores: sys_info::cpu_num().unwrap_or(4) as usize,
            architecture: std::env::consts::ARCH.to_string(),
            features: vec![], // Would need cpuid detection
        };

        let mem_info = sys_info::mem_info().map_err(|e| {
            GccBuildError::system_requirements(format!("Failed to get memory info: {}", e))
        })?;

        let memory_info = MemoryInfo {
            total_mb: mem_info.total / 1024,
            available_mb: mem_info.avail / 1024,
        };
        let disk_info = Self::detect_disk_type().await?;
        let load_avg = Self::get_system_load().await?;

        Ok(SystemProfile {
            cpu_cores: cpu_info.physical_cores,
            cpu_threads: cpu_info.logical_cores,
            cpu_architecture: cpu_info.architecture,
            cpu_features: cpu_info.features,
            total_memory_gb: memory_info.total_mb as f64 / 1024.0,
            available_memory_gb: memory_info.available_mb as f64 / 1024.0,
            disk_type: disk_info.disk_type,
            disk_space_gb: disk_info.available_gb,
            network_bandwidth_mbps: None, // Could be detected if needed
            system_load: load_avg,
            platform: std::env::consts::OS.to_string(),
        })
    }

    /// Detect disk type (Ssd, Hdd, NVMe)
    async fn detect_disk_type() -> GccResult<DiskInfo> {
        // Try to detect via /sys/block information
        let mut disk_type = DiskType::Unknown;
        let mut available_gb = 0.0;

        // Get root filesystem info
        if let Ok(statvfs) = nix::sys::statvfs::statvfs("/") {
            available_gb = (statvfs.blocks() * statvfs.fragment_size()) as f64 / 1_000_000_000.0;
        }

        // Try to determine disk type from block device info
        if let Ok(entries) = tokio::fs::read_dir("/sys/block").await {
            // Look for common disk devices
            let mut entries = entries;
            while let Ok(Some(entry)) = entries.next_entry().await {
                let name = entry.file_name();
                let name_str = name.to_string_lossy();

                if name_str.starts_with("nvme") {
                    disk_type = DiskType::NvMe;
                    break;
                } else if name_str.starts_with("sd") {
                    // Check if it's Ssd by looking at rotational flag
                    let rotational_path = format!("/sys/block/{}/queue/rotational", name_str);
                    if let Ok(content) = tokio::fs::read_to_string(&rotational_path).await {
                        if content.trim() == "0" {
                            disk_type = DiskType::Ssd;
                        } else {
                            disk_type = DiskType::Hdd;
                        }
                        break;
                    }
                }
            }
        }

        Ok(DiskInfo {
            disk_type,
            available_gb,
        })
    }

    /// Get current system load average
    async fn get_system_load() -> GccResult<f64> {
        if let Ok(content) = tokio::fs::read_to_string("/proc/loadavg").await {
            if let Some(load_str) = content.split_whitespace().next() {
                return Ok(load_str.parse().unwrap_or(0.0));
            }
        }
        Ok(0.0)
    }

    /// Create tuning rules
    fn create_tuning_rules() -> TuningRules {
        let mut optimization_presets = HashMap::new();

        optimization_presets.insert(
            "O0".to_string(),
            OptimizationPreset {
                base_flags: vec!["-O0".to_string()],
                memory_multiplier: 0.8,
                cpu_multiplier: 1.2,
            },
        );

        optimization_presets.insert(
            "O2".to_string(),
            OptimizationPreset {
                base_flags: vec!["-O2".to_string()],
                memory_multiplier: 1.0,
                cpu_multiplier: 1.0,
            },
        );

        optimization_presets.insert(
            "O3".to_string(),
            OptimizationPreset {
                base_flags: vec!["-O3".to_string()],
                memory_multiplier: 1.4,
                cpu_multiplier: 0.8,
            },
        );

        let mut version_adjustments = HashMap::new();
        version_adjustments.insert(
            "13".to_string(),
            VersionAdjustments {
                memory_overhead_factor: 1.2,
                compilation_time_factor: 1.1,
                special_flags: vec!["--disable-werror".to_string()],
            },
        );

        version_adjustments.insert(
            "14".to_string(),
            VersionAdjustments {
                memory_overhead_factor: 1.3,
                compilation_time_factor: 1.2,
                special_flags: vec!["--disable-werror".to_string()],
            },
        );

        TuningRules {
            memory_rules: MemoryTuningRules {
                min_memory_per_job_gb: 2.5,
                memory_safety_margin: 0.15, // Keep 15% free
                swap_penalty_factor: 0.5,
            },
            cpu_rules: CpuTuningRules {
                max_cpu_utilization: 0.90,
                hyperthreading_efficiency: 0.3, // 30% benefit from hyperthreading
                load_adjustment_factor: 0.8,
            },
            disk_rules: DiskTuningRules {
                parallel_io_factor: 0.7, // Reduce parallelism for Hdd
                temp_space_multiplier: 2.0,
            },
            gcc_rules: GccTuningRules {
                optimization_presets,
                version_specific_adjustments: version_adjustments,
            },
        }
    }

    /// Get tuning recommendations as human-readable text
    pub async fn get_recommendations(&self, gcc_version: &GccVersion) -> Vec<String> {
        let mut recommendations = Vec::new();
        let profile = &self.system_profile;

        // Memory recommendations
        if profile.total_memory_gb < 8.0 {
            recommendations
                .push("⚠️ Low memory detected - consider using --preset minimal".to_string());
        }

        // CPU recommendations
        if profile.cpu_cores <= 2 {
            recommendations.push("💡 Limited CPU cores - single build recommended".to_string());
        } else if profile.cpu_cores >= 16 {
            recommendations.push(
                "🚀 High-end CPU detected - parallel builds will be very efficient".to_string(),
            );
        }

        // Disk recommendations
        match profile.disk_type {
            DiskType::Hdd => {
                recommendations
                    .push("💽 Hdd storage detected - builds will be I/O bound".to_string());
            }
            DiskType::Ssd => {
                recommendations
                    .push("⚡ Ssd storage detected - good build performance expected".to_string());
            }
            DiskType::NvMe => {
                recommendations
                    .push("🏎️ NVMe storage detected - optimal build performance".to_string());
            }
            DiskType::Unknown => {
                recommendations.push("❓ Unknown storage type - performance may vary".to_string());
            }
        }

        // GCC-specific recommendations
        if gcc_version.major >= 13 {
            recommendations.push("🔧 Modern GCC version - all optimizations available".to_string());
        }

        recommendations
    }
}

#[derive(Debug)]
struct DiskInfo {
    disk_type: DiskType,
    available_gb: f64,
}

/// System CPU information
#[derive(Debug)]
pub struct CpuInfo {
    pub physical_cores: usize,
    pub logical_cores: usize,
    pub architecture: String,
    pub features: Vec<String>,
}

/// System memory information  
#[derive(Debug)]
pub struct MemoryInfo {
    pub total_mb: u64,
    pub available_mb: u64,
}
