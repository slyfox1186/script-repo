use log::{debug, info, warn};
use std::collections::{HashMap, HashSet};
use std::process::Command;

use crate::commands::CommandExecutor;
use crate::config::Config;
use crate::error::{GccBuildError, Result as GccResult};

#[derive(Debug, Clone)]
pub struct PackageManager {
    pub dry_run: bool,
    pub command_executor: CommandExecutor,
    pub package_groups: HashMap<String, Vec<String>>,
}

impl PackageManager {
    pub fn new(dry_run: bool, verbose: bool) -> Self {
        let command_executor = CommandExecutor::new(dry_run, verbose);
        let package_groups = Self::init_package_groups();
        
        Self {
            dry_run,
            command_executor,
            package_groups,
        }
    }
    
    fn init_package_groups() -> HashMap<String, Vec<String>> {
        let mut groups = HashMap::new();
        
        groups.insert("build_essential".to_string(), vec![
            "build-essential".to_string(),
            "binutils".to_string(),
            "make".to_string(),
            "dpkg-dev".to_string(),
        ]);
        
        groups.insert("gnu_tools".to_string(), vec![
            "gawk".to_string(),
            "m4".to_string(),
            "flex".to_string(),
            "bison".to_string(),
            "texinfo".to_string(),
            "patch".to_string(),
        ]);
        
        groups.insert("download_tools".to_string(), vec![
            "curl".to_string(),
            "wget".to_string(),
            "ca-certificates".to_string(),
        ]);
        
        groups.insert("build_optimization".to_string(), vec![
            "ccache".to_string(),
        ]);
        
        groups.insert("autotools".to_string(), vec![
            "libtool".to_string(),
            "libtool-bin".to_string(),
            "autoconf".to_string(),
            "automake".to_string(),
        ]);
        
        groups.insert("dev_libraries".to_string(), vec![
            "zlib1g-dev".to_string(),
            "libisl-dev".to_string(),
            "libzstd-dev".to_string(),
        ]);
        
        groups.insert("multilib_i386".to_string(), vec![
            "libc6-dev-i386".to_string(),
        ]);
        
        groups
    }
    
    /// Get required packages based on configuration
    pub fn get_required_packages(&self, config: &Config) -> GccResult<Vec<String>> {
        let mut packages = HashSet::new();
        
        // Always required groups
        let required_groups = vec![
            "build_essential",
            "gnu_tools",
            "download_tools",
            "build_optimization",
            "autotools",
            "dev_libraries",
        ];
        
        // Add conditional groups
        let mut all_groups = required_groups;
        if config.enable_multilib && config.target_arch == "x86_64-linux-gnu" {
            all_groups.push("multilib_i386");
        }
        
        // Expand groups to individual packages
        for group in all_groups {
            if let Some(group_packages) = self.package_groups.get(group) {
                for package in group_packages {
                    packages.insert(package.clone());
                }
            } else {
                warn!("Unknown package group: {}", group);
            }
        }
        
        let mut result: Vec<String> = packages.into_iter().collect();
        result.sort();
        Ok(result)
    }
    
    /// Check package installation status efficiently
    pub async fn check_packages_installed(&self, packages: &[String]) -> GccResult<PackageStatus> {
        if packages.is_empty() {
            return Ok(PackageStatus::default());
        }
        
        debug!("Checking installation status for {} packages", packages.len());
        
        // Use single dpkg-query call for all packages
        let mut dpkg_args = vec!["-W", "-f", "${Package} ${Status}\\n"];
        for package in packages {
            dpkg_args.push(package);
        }
        
        let dpkg_output = match self.command_executor.execute_with_output("dpkg-query", dpkg_args).await {
            Ok(output) => output,
            Err(_) => {
                // If dpkg-query fails, assume no packages are installed
                warn!("dpkg-query failed, assuming no packages are installed");
                String::new()
            }
        };
        
        let mut installed = Vec::new();
        let mut missing = Vec::new();
        
        for package in packages {
            let is_installed = dpkg_output.lines().any(|line| {
                line.starts_with(&format!("{} ", package)) && line.contains("ok installed")
            });
            
            if is_installed {
                installed.push(package.clone());
            } else {
                missing.push(package.clone());
            }
        }
        
        if !missing.is_empty() {
            info!("Missing packages: {}", missing.join(", "));
        }
        
        if !installed.is_empty() {
            debug!("Installed packages: {}", installed.join(", "));
        }
        
        Ok(PackageStatus { installed, missing })
    }
    
    /// Install packages with error handling
    pub async fn install_packages(&self, packages: &[String]) -> GccResult<()> {
        if packages.is_empty() {
            info!("No packages to install");
            return Ok(());
        }
        
        info!("Installing {} packages: {}", packages.len(), packages.join(", "));
        
        if self.dry_run {
            info!("Dry run: would install packages: {}", packages.join(", "));
            return Ok(());
        }
        
        // Update package list first
        info!("Updating package lists...");
        self.command_executor.execute_with_retry(
            "sudo", 
            ["apt-get", "update"].iter(),
            2,
            std::time::Duration::from_secs(5)
        ).await.map_err(|e| GccBuildError::package_manager(
            format!("Failed to update package lists: {}", e)
        ))?;
        
        // Install packages
        let mut apt_args = vec![
            "apt-get".to_string(),
            "-y".to_string(),
            "--no-install-recommends".to_string(),
            "install".to_string(),
        ];
        apt_args.extend_from_slice(packages);
        
        // Set environment for non-interactive installation
        let mut env_vars = HashMap::new();
        env_vars.insert("DEBIAN_FRONTEND".to_string(), "noninteractive".to_string());
        
        let executor_with_env = self.command_executor.clone().with_env_vars(env_vars);
        
        executor_with_env.execute_with_retry(
            "sudo",
            apt_args.iter().map(|s| s.as_str()),
            2,
            std::time::Duration::from_secs(10)
        ).await.map_err(|e| GccBuildError::package_manager(
            format!("Failed to install packages: {}", e)
        ))?;
        
        info!("Successfully installed {} packages", packages.len());
        Ok(())
    }
    
    /// Check if a specific package is available in repositories
    pub async fn is_package_available(&self, package: &str) -> GccResult<bool> {
        let output = self.command_executor.execute_with_output(
            "apt-cache", 
            ["search", "--names-only", &format!("^{}$", package)]
        ).await?;
        
        Ok(!output.trim().is_empty())
    }
    
    /// Get package information
    pub async fn get_package_info(&self, package: &str) -> GccResult<PackageInfo> {
        let output = self.command_executor.execute_with_output(
            "apt-cache",
            ["show", package]
        ).await?;
        
        let mut info = PackageInfo {
            name: package.to_string(),
            version: "Unknown".to_string(),
            description: "Unknown".to_string(),
            size: 0,
            dependencies: Vec::new(),
        };
        
        for line in output.lines() {
            if let Some(version) = line.strip_prefix("Version: ") {
                info.version = version.to_string();
            } else if let Some(description) = line.strip_prefix("Description: ") {
                info.description = description.to_string();
            } else if let Some(size_str) = line.strip_prefix("Installed-Size: ") {
                if let Ok(size) = size_str.parse::<u64>() {
                    info.size = size * 1024; // Convert from KB to bytes
                }
            } else if let Some(depends) = line.strip_prefix("Depends: ") {
                info.dependencies = depends.split(", ")
                    .map(|s| s.split_whitespace().next().unwrap_or(s).to_string())
                    .collect();
            }
        }
        
        Ok(info)
    }
    
    /// Remove packages
    pub async fn remove_packages(&self, packages: &[String]) -> GccResult<()> {
        if packages.is_empty() {
            return Ok(());
        }
        
        info!("Removing packages: {}", packages.join(", "));
        
        if self.dry_run {
            info!("Dry run: would remove packages: {}", packages.join(", "));
            return Ok(());
        }
        
        let mut apt_args = vec!["apt-get", "-y", "remove"];
        for package in packages {
            apt_args.push(package);
        }
        
        self.command_executor.execute("sudo", apt_args).await
            .map_err(|e| GccBuildError::package_manager(
                format!("Failed to remove packages: {}", e)
            ))?;
        
        info!("Successfully removed {} packages", packages.len());
        Ok(())
    }
    
    /// Update package cache
    pub async fn update_package_cache(&self) -> GccResult<()> {
        info!("Updating package cache...");
        
        if self.dry_run {
            info!("Dry run: would update package cache");
            return Ok(());
        }
        
        self.command_executor.execute("sudo", ["apt-get", "update"]).await
            .map_err(|e| GccBuildError::package_manager(
                format!("Failed to update package cache: {}", e)
            ))?;
        
        info!("Package cache updated successfully");
        Ok(())
    }
    
    /// Upgrade system packages
    pub async fn upgrade_packages(&self) -> GccResult<()> {
        info!("Upgrading system packages...");
        
        if self.dry_run {
            info!("Dry run: would upgrade system packages");
            return Ok(());
        }
        
        self.command_executor.execute("sudo", ["apt-get", "-y", "upgrade"]).await
            .map_err(|e| GccBuildError::package_manager(
                format!("Failed to upgrade packages: {}", e)
            ))?;
        
        info!("System packages upgraded successfully");
        Ok(())
    }
    
    /// Clean package cache
    pub async fn clean_package_cache(&self) -> GccResult<()> {
        info!("Cleaning package cache...");
        
        if self.dry_run {
            info!("Dry run: would clean package cache");
            return Ok(());
        }
        
        self.command_executor.execute("sudo", ["apt-get", "clean"]).await
            .map_err(|e| GccBuildError::package_manager(
                format!("Failed to clean package cache: {}", e)
            ))?;
        
        info!("Package cache cleaned successfully");
        Ok(())
    }
}

#[derive(Debug, Clone, Default)]
pub struct PackageStatus {
    pub installed: Vec<String>,
    pub missing: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct PackageInfo {
    pub name: String,
    pub version: String,
    pub description: String,
    pub size: u64,
    pub dependencies: Vec<String>,
}

/// Public convenience function for installing dependencies
pub async fn install_dependencies(config: &Config) -> GccResult<()> {
    let package_manager = PackageManager::new(config.dry_run, config.verbose);
    
    // Get required packages based on configuration
    let required_packages = package_manager.get_required_packages(config)?;
    
    // Check which packages are missing
    let package_status = package_manager.check_packages_installed(&required_packages).await?;
    
    if package_status.missing.is_empty() {
        info!("All required dependencies are already installed");
        return Ok(());
    }
    
    // Install missing packages
    package_manager.install_packages(&package_status.missing).await?;
    
    // Skip verification in dry-run mode
    if !config.dry_run {
        // Verify installation
        let verification_status = package_manager.check_packages_installed(&package_status.missing).await?;
        
        if !verification_status.missing.is_empty() {
            return Err(GccBuildError::package_manager(
                format!("Failed to install packages: {}", verification_status.missing.join(", "))
            ));
        }
    }
    
    info!("All dependencies installed successfully");
    Ok(())
}

/// Check if system has a package manager available
pub async fn detect_package_manager() -> Option<String> {
    let managers = ["apt-get", "yum", "dnf", "pacman", "zypper"];
    
    for manager in &managers {
        if Command::new("which").arg(manager).output()
            .map(|output| output.status.success())
            .unwrap_or(false) 
        {
            return Some(manager.to_string());
        }
    }
    
    None
}