#![allow(dead_code)]
use log::{info, warn};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::process::Command;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tokio::time::interval;

use crate::config::Config;
use crate::directories::SpaceUnit;
use crate::error::{GccBuildError, Result as GccResult};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemRequirements {
    pub min_ram_mb: u64,
    pub min_disk_gb: u64,
    pub recommended_ram_gb: u64,
    pub gb_per_gcc_version: u64,
    pub safety_margin_gb: u64,
}

impl Default for SystemRequirements {
    fn default() -> Self {
        Self {
            min_ram_mb: 2000,
            min_disk_gb: 10,
            recommended_ram_gb: 8,
            gb_per_gcc_version: 25,
            safety_margin_gb: 5,
        }
    }
}

#[derive(Debug, Clone)]
pub struct SystemUtilities {
    requirements: SystemRequirements,
}

impl SystemUtilities {
    pub fn new() -> Self {
        Self {
            requirements: SystemRequirements::default(),
        }
    }

    pub fn with_requirements(requirements: SystemRequirements) -> Self {
        Self { requirements }
    }

    /// Get various system information
    pub async fn get_system_info(&self, info_type: SystemInfoType) -> GccResult<String> {
        match info_type {
            SystemInfoType::RamMb => {
                let info = sys_info::mem_info().map_err(|e| {
                    GccBuildError::system_requirements(format!("Failed to get memory info: {}", e))
                })?;
                Ok((info.total / 1024).to_string()) // Convert KB to MB
            }
            SystemInfoType::AvailableRamMb => {
                let info = sys_info::mem_info().map_err(|e| {
                    GccBuildError::system_requirements(format!("Failed to get memory info: {}", e))
                })?;
                Ok((info.avail / 1024).to_string()) // Convert KB to MB
            }
            SystemInfoType::CpuCores => {
                let cores = sys_info::cpu_num().map_err(|e| {
                    GccBuildError::system_requirements(format!("Failed to get CPU info: {}", e))
                })?;
                Ok(cores.to_string())
            }
            SystemInfoType::CpuThreads => {
                // Try to read from /proc/cpuinfo
                match fs::read_to_string("/proc/cpuinfo") {
                    Ok(content) => {
                        let thread_count = content
                            .lines()
                            .filter(|line| line.starts_with("processor"))
                            .count();
                        Ok(thread_count.to_string())
                    }
                    Err(_) => {
                        // Fallback to cpu_num
                        let cores = sys_info::cpu_num().map_err(|e| {
                            GccBuildError::system_requirements(format!(
                                "Failed to get CPU info: {}",
                                e
                            ))
                        })?;
                        Ok(cores.to_string())
                    }
                }
            }
            SystemInfoType::Architecture => Ok(std::env::consts::ARCH.to_string()),
            SystemInfoType::OsRelease => {
                // Try to get from lsb_release first
                if let Ok(output) = Command::new("lsb_release").args(["-ds"]).output() {
                    if output.status.success() {
                        let release = String::from_utf8_lossy(&output.stdout).trim().to_string();
                        if !release.is_empty() {
                            return Ok(release);
                        }
                    }
                }

                // Fallback to /etc/os-release
                match fs::read_to_string("/etc/os-release") {
                    Ok(content) => {
                        for line in content.lines() {
                            if line.starts_with("PRETTY_NAME=") {
                                let name = line.split('=').nth(1).unwrap_or("Unknown");
                                return Ok(name.trim_matches('"').to_string());
                            }
                        }
                        Ok("Unknown".to_string())
                    }
                    Err(_) => Ok("Unknown".to_string()),
                }
            }
            SystemInfoType::Kernel => match Command::new("uname").arg("-r").output() {
                Ok(output) if output.status.success() => {
                    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
                }
                _ => Ok("Unknown".to_string()),
            },
        }
    }

    /// Calculate optimal build settings based on system resources
    pub async fn calculate_build_settings(
        &self,
        gcc_version_count: usize,
    ) -> GccResult<BuildSettings> {
        let available_ram_mb = self
            .get_system_info(SystemInfoType::AvailableRamMb)
            .await?
            .parse::<u64>()
            .unwrap_or(2000);

        let available_cores = self
            .get_system_info(SystemInfoType::CpuCores)
            .await?
            .parse::<usize>()
            .unwrap_or(2);

        // Calculate optimal thread count
        let memory_threads = (available_ram_mb / 2000) as usize; // 2GB per thread
        let optimal_threads = std::cmp::min(available_cores, memory_threads).max(1);

        // Calculate disk space requirements
        let required_disk_gb = gcc_version_count as u64 * self.requirements.gb_per_gcc_version
            + self.requirements.safety_margin_gb;

        Ok(BuildSettings {
            optimal_threads,
            available_ram_mb,
            available_cores,
            required_disk_gb,
            gcc_versions: gcc_version_count,
        })
    }

    /// Validate system requirements
    pub async fn validate_requirements(&self, config: &Config) -> GccResult<()> {
        let mut errors = Vec::new();

        // Check RAM
        let available_ram_mb = self
            .get_system_info(SystemInfoType::AvailableRamMb)
            .await?
            .parse::<u64>()
            .unwrap_or(0);

        if available_ram_mb < self.requirements.min_ram_mb {
            errors.push(format!(
                "Insufficient RAM: {}MB available, {}MB required",
                available_ram_mb, self.requirements.min_ram_mb
            ));
        }

        // Ensure build directory exists before checking disk space
        if !config.build_dir.exists() {
            fs::create_dir_all(&config.build_dir).map_err(|e| {
                GccBuildError::system_requirements(format!(
                    "Failed to create build directory {}: {}",
                    config.build_dir.display(),
                    e
                ))
            })?;
            info!("✅ Created build directory: {}", config.build_dir.display());
        }

        // Check disk space
        let available_disk_gb = self.get_available_space(&config.build_dir, SpaceUnit::GB)?;
        let required_disk_gb = config.gcc_versions.len() as u64
            * self.requirements.gb_per_gcc_version
            + self.requirements.safety_margin_gb;

        if available_disk_gb < required_disk_gb {
            errors.push(format!(
                "Insufficient disk space: {}GB available, {}GB required",
                available_disk_gb, required_disk_gb
            ));
        }

        // Check for required commands
        let required_commands = ["gcc", "g++", "make", "tar", "wget", "curl"];
        for &cmd in &required_commands {
            if !self.command_exists(cmd).await {
                errors.push(format!("Required command not found: {}", cmd));
            }
        }

        // Report errors
        if !errors.is_empty() {
            let error_msg = format!(
                "System requirement validation failed:\n{}",
                errors
                    .iter()
                    .map(|e| format!("  - {}", e))
                    .collect::<Vec<_>>()
                    .join("\n")
            );
            return Err(GccBuildError::system_requirements(error_msg));
        }

        info!("System requirements validation passed");
        info!(
            "Available RAM: {}MB, Available disk: {}GB",
            available_ram_mb, available_disk_gb
        );
        Ok(())
    }

    /// Check if a command exists in PATH
    pub async fn command_exists(&self, command: &str) -> bool {
        Command::new("which")
            .arg(command)
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }

    /// Get available disk space
    pub fn get_available_space(&self, path: &Path, unit: SpaceUnit) -> GccResult<u64> {
        #[cfg(unix)]
        {
            use std::ffi::CString;
            use std::mem;

            let path_cstring = CString::new(path.to_string_lossy().as_bytes()).map_err(|e| {
                GccBuildError::system_requirements(format!("Path conversion error: {}", e))
            })?;

            let mut statvfs: libc::statvfs = unsafe { mem::zeroed() };

            let result = unsafe { libc::statvfs(path_cstring.as_ptr(), &mut statvfs) };

            if result != 0 {
                return Err(GccBuildError::system_requirements(format!(
                    "Failed to get filesystem stats for {}",
                    path.display()
                )));
            }

            let available_bytes = statvfs.f_bavail * statvfs.f_frsize;

            let result = match unit {
                SpaceUnit::Bytes => available_bytes,
                SpaceUnit::KB => available_bytes / 1024,
                SpaceUnit::MB => available_bytes / (1024 * 1024),
                SpaceUnit::GB => available_bytes / (1024 * 1024 * 1024),
            };

            Ok(result as u64)
        }

        #[cfg(not(unix))]
        {
            // Fallback using df command
            let output = Command::new("df")
                .arg("-B1")
                .arg(path)
                .output()
                .map_err(|e| {
                    GccBuildError::system_requirements(format!("df command error: {}", e))
                })?;

            if !output.status.success() {
                return Err(GccBuildError::system_requirements(
                    "df command failed".to_string(),
                ));
            }

            let output_str = String::from_utf8_lossy(&output.stdout);
            let lines: Vec<&str> = output_str.lines().collect();

            if lines.len() < 2 {
                return Err(GccBuildError::system_requirements(
                    "Unexpected df output".to_string(),
                ));
            }

            let fields: Vec<&str> = lines[1].split_whitespace().collect();
            if fields.len() < 4 {
                return Err(GccBuildError::system_requirements(
                    "Cannot parse df output".to_string(),
                ));
            }

            let available_bytes: u64 = fields[3].parse().map_err(|e| {
                GccBuildError::system_requirements(format!("Cannot parse available bytes: {}", e))
            })?;

            let result = match unit {
                SpaceUnit::Bytes => available_bytes,
                SpaceUnit::KB => available_bytes / 1024,
                SpaceUnit::MB => available_bytes / (1024 * 1024),
                SpaceUnit::GB => available_bytes / (1024 * 1024 * 1024),
            };

            Ok(result)
        }
    }

    /// Detect target architecture
    pub async fn detect_target_architecture(&self) -> GccResult<String> {
        // Try gcc -dumpmachine first
        if let Ok(output) = Command::new("gcc").arg("-dumpmachine").output() {
            if output.status.success() {
                let arch = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !arch.is_empty() {
                    info!("Detected target architecture from gcc: {}", arch);
                    return Ok(arch);
                }
            }
        }

        // Try cc -dumpmachine as fallback
        if let Ok(output) = Command::new("cc").arg("-dumpmachine").output() {
            if output.status.success() {
                let arch = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !arch.is_empty() {
                    info!("Detected target architecture from cc: {}", arch);
                    return Ok(arch);
                }
            }
        }

        // Final fallback
        warn!("Could not auto-detect target architecture, using default");
        Ok("x86_64-linux-gnu".to_string())
    }

    /// Get comprehensive system information
    pub async fn get_comprehensive_system_info(&self) -> GccResult<HashMap<String, String>> {
        let mut info = HashMap::new();

        let info_types = [
            (SystemInfoType::RamMb, "ram_mb"),
            (SystemInfoType::AvailableRamMb, "available_ram_mb"),
            (SystemInfoType::CpuCores, "cpu_cores"),
            (SystemInfoType::CpuThreads, "cpu_threads"),
            (SystemInfoType::Architecture, "architecture"),
            (SystemInfoType::OsRelease, "os_release"),
            (SystemInfoType::Kernel, "kernel"),
        ];

        for (info_type, key) in &info_types {
            match self.get_system_info(info_type.clone()).await {
                Ok(value) => {
                    info.insert(key.to_string(), value);
                }
                Err(e) => {
                    warn!("Failed to get {}: {}", key, e);
                    info.insert(key.to_string(), "Unknown".to_string());
                }
            }
        }

        Ok(info)
    }
}

#[derive(Debug, Clone)]
pub enum SystemInfoType {
    RamMb,
    AvailableRamMb,
    CpuCores,
    CpuThreads,
    Architecture,
    OsRelease,
    Kernel,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BuildSettings {
    pub optimal_threads: usize,
    pub available_ram_mb: u64,
    pub available_cores: usize,
    pub required_disk_gb: u64,
    pub gcc_versions: usize,
}

/// Resource monitor for long-running builds
#[derive(Debug)]
pub struct ResourceMonitor {
    build_dir: std::path::PathBuf,
    check_interval: Duration,
    log_file: std::path::PathBuf,
    running: Arc<RwLock<bool>>,
}

impl ResourceMonitor {
    pub fn new(
        build_dir: std::path::PathBuf,
        check_interval: Duration,
        log_file: std::path::PathBuf,
    ) -> Self {
        Self {
            build_dir,
            check_interval,
            log_file,
            running: Arc::new(RwLock::new(false)),
        }
    }

    /// Start monitoring system resources
    pub async fn start(&self) -> GccResult<()> {
        {
            let mut running = self.running.write().await;
            if *running {
                return Ok(()); // Already running
            }
            *running = true;
        }

        let build_dir = self.build_dir.clone();
        let log_file = self.log_file.clone();
        let check_interval = self.check_interval;
        let running = Arc::clone(&self.running);

        tokio::spawn(async move {
            let mut interval = interval(check_interval);
            let system_utils = SystemUtilities::new();

            loop {
                interval.tick().await;

                // Check if we should stop
                {
                    let running_guard = running.read().await;
                    if !*running_guard {
                        break;
                    }
                }

                // Collect resource information
                let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");

                let ram_usage = match sys_info::mem_info() {
                    Ok(info) => {
                        let usage_percent =
                            (info.total - info.avail) as f64 / info.total as f64 * 100.0;
                        format!("{:.1}%", usage_percent)
                    }
                    Err(_) => "N/A".to_string(),
                };

                let disk_usage = match system_utils.get_available_space(&build_dir, SpaceUnit::GB) {
                    Ok(space) => format!("{}GB", space),
                    Err(_) => "N/A".to_string(),
                };

                let load_avg = match fs::read_to_string("/proc/loadavg") {
                    Ok(content) => content
                        .split_whitespace()
                        .next()
                        .unwrap_or("N/A")
                        .to_string(),
                    Err(_) => "N/A".to_string(),
                };

                let log_entry = format!(
                    "{} RAM:{} DISK:{} LOAD:{}\n",
                    timestamp, ram_usage, disk_usage, load_avg
                );

                // Write to log file
                if let Err(e) = fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(&log_file)
                    .and_then(|mut file| std::io::Write::write_all(&mut file, log_entry.as_bytes()))
                {
                    warn!("Failed to write to resource monitor log: {}", e);
                }

                // Check for critical conditions
                if let Ok(available_gb) =
                    system_utils.get_available_space(&build_dir, SpaceUnit::GB)
                {
                    if available_gb < 2 {
                        warn!("Critical disk space: {}GB remaining", available_gb);
                        // Could trigger emergency cleanup here
                    }
                }
            }
        });

        Ok(())
    }

    /// Stop monitoring
    pub async fn stop(&self) {
        let mut running = self.running.write().await;
        *running = false;
    }
}

/// Public convenience function for validating system requirements
pub async fn validate_requirements(config: &Config) -> GccResult<()> {
    let system_utils = SystemUtilities::new();
    system_utils.validate_requirements(config).await
}
