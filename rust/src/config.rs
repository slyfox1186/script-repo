#![allow(dead_code)]
use std::collections::HashMap;
use std::path::PathBuf;
use semver::Version;
use serde::{Deserialize, Serialize};

use crate::cli::{Args, OptimizationLevel};
use crate::error::{GccBuildError, Result as GccResult};
use log::info;

#[derive(Debug, Clone)]
pub struct Config {
    pub debug: bool,
    pub dry_run: bool,
    pub enable_multilib: bool,
    pub static_build: bool,
    pub generic_tuning: bool,
    pub keep_build_dir: bool,
    pub save_binaries: bool,
    pub verbose: bool,
    pub skip_checksum: bool,
    pub force_rebuild: bool,
    
    pub optimization_level: OptimizationLevel,
    pub max_retries: usize,
    pub download_timeout_secs: u64,
    pub parallel_jobs: usize,
    
    pub build_dir: PathBuf,
    pub packages_dir: PathBuf,
    pub workspace_dir: PathBuf,
    pub install_prefix: Option<PathBuf>,
    pub log_file: Option<PathBuf>,
    
    pub gcc_versions: Vec<GccVersion>,
    pub target_arch: String,
    pub system_info: SystemInfo,
    pub build_settings: BuildSettings,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct GccVersion {
    pub major: u8,
    pub minor: u8,
    pub patch: u8,
    pub full_version: String,
}

impl GccVersion {
    pub fn new(major: u8, minor: u8, patch: u8) -> Self {
        Self {
            major,
            minor,
            patch,
            full_version: format!("{}.{}.{}", major, minor, patch),
        }
    }
    
    pub fn from_str(version: &str) -> GccResult<Self> {
        let version = Version::parse(version)
            .map_err(|_| GccBuildError::configuration(format!("Invalid version format: {}", version)))?;
        
        Ok(Self {
            major: version.major as u8,
            minor: version.minor as u8,
            patch: version.patch as u8,
            full_version: version.to_string(),
        })
    }
    
    pub fn supports_feature(&self, feature: &str) -> bool {
        match feature {
            "default_pie" | "gnu_unique_object" => self.major >= 9,
            "link_serialization" => self.major >= 12,
            "cet" => self.major >= 13,
            _ => false,
        }
    }
}

impl std::fmt::Display for GccVersion {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.full_version)
    }
}

#[derive(Debug, Clone)]
pub struct SystemInfo {
    pub ram_mb: u64,
    pub cpu_cores: usize,
    pub available_disk_gb: u64,
    pub architecture: String,
    pub os_release: String,
}

#[derive(Debug, Clone)]
pub struct BuildSettings {
    pub cflags: Vec<String>,
    pub cxxflags: Vec<String>,
    pub cppflags: Vec<String>,
    pub ldflags: Vec<String>,
    pub env_vars: HashMap<String, String>,
}

impl Config {
    pub fn new(args: Args) -> GccResult<Self> {
        // Validate arguments
        args.validate().map_err(GccBuildError::configuration)?;
        
        // Detect system information
        let system_info = detect_system_info()?;
        
        // Determine target architecture
        let target_arch = detect_target_architecture()?;
        
        // Set up directories
        let build_dir = args.build_dir.clone().unwrap_or_else(|| PathBuf::from("/tmp/gcc-build-script"));
        let packages_dir = build_dir.join("packages");
        let workspace_dir = build_dir.join("workspace");
        
        // Determine parallel jobs
        let parallel_jobs = args.jobs.unwrap_or_else(|| {
            let memory_limit = system_info.ram_mb / 2000; // 2GB per job
            let cpu_limit = system_info.cpu_cores;
            std::cmp::min(memory_limit as usize, cpu_limit).max(1)
        });
        
        // Parse GCC versions
        let gcc_versions = parse_gcc_versions(Some(&args.get_versions_string()))?;
        
        // Build environment settings
        let build_settings = create_build_settings(&args, &target_arch, &system_info)?;
        
        Ok(Config {
            debug: args.debug,
            dry_run: args.dry_run,
            enable_multilib: args.enable_multilib,
            static_build: args.static_build,
            generic_tuning: args.generic,
            keep_build_dir: args.keep_build_dir,
            save_binaries: args.save_binaries,
            verbose: args.verbose,
            skip_checksum: args.skip_checksum,
            force_rebuild: args.force_rebuild,
            
            optimization_level: args.optimization,
            max_retries: args.max_retries,
            download_timeout_secs: args.download_timeout,
            parallel_jobs,
            
            build_dir,
            packages_dir,
            workspace_dir,
            install_prefix: args.prefix,
            log_file: args.log_file,
            
            gcc_versions,
            target_arch,
            system_info,
            build_settings,
        })
    }
    
    pub fn get_install_prefix(&self, version: &GccVersion) -> PathBuf {
        match &self.install_prefix {
            Some(prefix) => prefix.join(format!("gcc-{}", version)),
            None => PathBuf::from(format!("/usr/local/programs/gcc-{}", version)),
        }
    }
    
    pub fn validate_system_requirements(&self) -> GccResult<()> {
        // Check minimum RAM
        if self.system_info.ram_mb < 2000 {
            return Err(GccBuildError::system_requirements(
                format!("Insufficient RAM: {}MB available, 2000MB required", self.system_info.ram_mb)
            ));
        }
        
        // Check disk space
        let required_disk = self.gcc_versions.len() as u64 * 25 + 5; // 25GB per version + 5GB safety
        if self.system_info.available_disk_gb < required_disk {
            return Err(GccBuildError::system_requirements(
                format!("Insufficient disk space: {}GB available, {}GB required", 
                       self.system_info.available_disk_gb, required_disk)
            ));
        }
        
        Ok(())
    }
}

fn detect_system_info() -> GccResult<SystemInfo> {
    let ram_mb = sys_info::mem_info()
        .map_err(|e| GccBuildError::configuration(format!("Failed to get memory info: {}", e)))?
        .total / 1024; // Convert from KB to MB
    
    let cpu_cores = sys_info::cpu_num()
        .map_err(|e| GccBuildError::configuration(format!("Failed to get CPU info: {}", e)))? as usize;
    
    let available_disk_gb = 100; // TODO: Implement actual disk space detection
    
    let architecture = std::env::consts::ARCH.to_string();
    let os_release = "Unknown".to_string(); // TODO: Implement OS detection
    
    Ok(SystemInfo {
        ram_mb,
        cpu_cores,
        available_disk_gb,
        architecture,
        os_release,
    })
}

fn detect_target_architecture() -> GccResult<String> {
    // Try to get from gcc -dumpmachine
    let output = std::process::Command::new("gcc")
        .arg("-dumpmachine")
        .output();
    
    match output {
        Ok(output) if output.status.success() => {
            let arch = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !arch.is_empty() {
                return Ok(arch);
            }
        }
        _ => {}
    }
    
    // Fallback to default
    Ok("x86_64-linux-gnu".to_string())
}

fn parse_gcc_versions(versions_str: Option<&str>) -> GccResult<Vec<GccVersion>> {
    let versions_str = match versions_str {
        Some(s) if !s.is_empty() => s,
        _ => {
            return Err(GccBuildError::configuration("No GCC versions specified. Use --versions, --latest, or --all-supported".to_string()));
        }
    };
    
    let mut versions = Vec::new();
    
    // Handle special cases
    if versions_str == "latest" {
        info!("Resolving latest GCC version...");
        // Resolve the actual latest version immediately
        let latest_version = resolve_latest_version_sync()?;
        info!("Latest GCC version: {}", latest_version);
        versions.push(latest_version);
        return Ok(versions);
    }
    
    for part in versions_str.split(',') {
        let part = part.trim();
        
        if part.contains('-') {
            // Range like "11-13"
            let range_parts: Vec<&str> = part.split('-').collect();
            if range_parts.len() != 2 {
                return Err(GccBuildError::configuration(
                    format!("Invalid version range '{}'. Use format like '11-13'", part)
                ));
            }
            
            let start: u8 = range_parts[0].parse()
                .map_err(|_| GccBuildError::configuration(
                    format!("Invalid start version '{}' in range. Must be a number between 10-15", range_parts[0])
                ))?;
            let end: u8 = range_parts[1].parse()
                .map_err(|_| GccBuildError::configuration(
                    format!("Invalid end version '{}' in range. Must be a number between 10-15", range_parts[1])
                ))?;
            
            if start > end {
                return Err(GccBuildError::configuration(
                    format!("Invalid range '{}': start version must be less than or equal to end version", part)
                ));
            }
            
            if start < 10 || end > 15 {
                return Err(GccBuildError::configuration(
                    format!("Version range '{}' out of bounds. Supported versions are 10-15", part)
                ));
            }
            
            for v in start..=end {
                // We'll resolve the full version later from the GNU FTP site
                versions.push(GccVersion::new(v, 0, 0));
            }
        } else if let Ok(major) = part.parse::<u8>() {
            // Single version like "13"
            if major < 10 || major > 15 {
                return Err(GccBuildError::configuration(
                    format!("Version {} is not supported. Supported versions are 10-15", major)
                ));
            }
            versions.push(GccVersion::new(major, 0, 0));
        } else {
            // Try to parse as full version (e.g., "13.2.0")
            match GccVersion::from_str(part) {
                Ok(version) => {
                    if version.major < 10 || version.major > 15 {
                        return Err(GccBuildError::configuration(
                            format!("Version {} is not supported. Supported versions are 10-15", version)
                        ));
                    }
                    versions.push(version);
                }
                Err(_) => {
                    return Err(GccBuildError::configuration(
                        format!("Invalid version '{}'. Use a number (e.g., '13'), range (e.g., '11-13'), or full version (e.g., '13.2.0')", part)
                    ));
                }
            }
        }
    }
    
    if versions.is_empty() {
        return Err(GccBuildError::configuration("No GCC versions specified".to_string()));
    }
    
    versions.sort();
    versions.dedup();
    
    info!("Will build GCC versions: {}", 
          versions.iter().map(|v| v.to_string()).collect::<Vec<_>>().join(", "));
    
    Ok(versions)
}

fn create_build_settings(args: &Args, _target_arch: &str, system_info: &SystemInfo) -> GccResult<BuildSettings> {
    let mut cflags = vec![args.optimization.as_str().to_string(), "-pipe".to_string()];
    let mut cxxflags = cflags.clone();
    let cppflags = vec!["-D_FORTIFY_SOURCE=2".to_string()];
    let mut ldflags = vec!["-Wl,-z,relro".to_string(), "-Wl,-z,now".to_string()];
    
    // Add architecture-specific flags
    if !args.generic {
        cflags.push("-march=native".to_string());
        cxxflags.push("-march=native".to_string());
    }
    
    // Add security flags
    cflags.push("-fstack-protector-strong".to_string());
    cxxflags.push("-fstack-protector-strong".to_string());
    
    // Static build flags
    if args.static_build {
        ldflags.insert(0, "-static".to_string());
    }
    
    // Environment variables
    let mut env_vars = HashMap::new();
    env_vars.insert("CC".to_string(), "gcc".to_string());
    env_vars.insert("CXX".to_string(), "g++".to_string());
    env_vars.insert("MAKEFLAGS".to_string(), format!("-j{}", system_info.cpu_cores));
    
    // ccache optimization
    env_vars.insert("CCACHE_MAXSIZE".to_string(), "10G".to_string());
    env_vars.insert("CCACHE_COMPRESS".to_string(), "1".to_string());
    env_vars.insert("CCACHE_SLOPPINESS".to_string(), "time_macros,include_file_mtime".to_string());
    
    Ok(BuildSettings {
        cflags,
        cxxflags,
        cppflags,
        ldflags,
        env_vars,
    })
}

// Synchronous wrapper to resolve latest GCC version during config parsing
fn resolve_latest_version_sync() -> GccResult<GccVersion> {
    use std::process::Command;
    
    let output = Command::new("bash")
        .arg("-c")
        .arg(r#"curl -fsSL https://ftp.gnu.org/gnu/gcc/ | grep -oP 'gcc-\K\d+\.\d+\.\d+(?=/)' | sort -V | tail -n1"#)
        .output()
        .map_err(|e| GccBuildError::configuration(format!("Failed to resolve latest GCC version: {}", e)))?;
    
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(GccBuildError::configuration(format!("Failed to resolve latest GCC version: {}", stderr)));
    }
    
    let version_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if version_str.is_empty() {
        return Err(GccBuildError::configuration("Failed to resolve latest GCC version: no versions found".to_string()));
    }
    
    GccVersion::from_str(&version_str)
}