#![allow(dead_code)]
use std::collections::HashMap;
use log::{info, warn, error};
use crate::error::{GccBuildError, Result as GccResult};
use crate::commands::CommandExecutor;

use colored::*;

/// Automatic dependency installer for missing packages
pub struct DependencyInstaller {
    executor: CommandExecutor,
    dry_run: bool,
    package_manager: PackageManager,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
enum PackageManager {
    Apt,
    Yum,
    Dnf,
    Pacman,
    Zypper,
    Brew,
    Unknown,
}

#[derive(Debug, Clone)]
struct PackageMapping {
    generic_name: &'static str,
    packages: HashMap<PackageManager, Vec<&'static str>>,
}

impl DependencyInstaller {
    pub async fn new(executor: CommandExecutor, dry_run: bool) -> GccResult<Self> {
        let package_manager = Self::detect_package_manager(&executor).await?;
        
        Ok(Self {
            executor,
            dry_run,
            package_manager,
        })
    }
    
    /// Detect the system's package manager
    async fn detect_package_manager(executor: &CommandExecutor) -> GccResult<PackageManager> {
        let managers = [
            ("apt-get", PackageManager::Apt),
            ("yum", PackageManager::Yum),
            ("dnf", PackageManager::Dnf),
            ("pacman", PackageManager::Pacman),
            ("zypper", PackageManager::Zypper),
            ("brew", PackageManager::Brew),
        ];
        
        for (cmd, pm) in managers {
            if executor.command_exists(cmd).await {
                info!("Detected package manager: {:?}", pm);
                return Ok(pm);
            }
        }
        
        warn!("Could not detect package manager");
        Ok(PackageManager::Unknown)
    }
    
    /// Check and install missing dependencies
    pub async fn check_and_install(&self, auto_install: bool) -> GccResult<()> {
        info!("🔍 Checking system dependencies...");
        
        let missing = self.find_missing_dependencies().await?;
        
        if missing.is_empty() {
            info!("✅ All required dependencies are installed");
            return Ok(());
        }
        
        info!("❌ Missing dependencies detected:");
        for dep in &missing {
            println!("  • {}", dep.generic_name.red());
        }
        
        if !auto_install {
            self.print_install_commands(&missing);
            return Err(GccBuildError::system_requirements(
                "Missing dependencies. Run with --auto-install-deps to install automatically"
            ));
        }
        
        // Install dependencies
        self.install_dependencies(&missing).await
    }
    
    /// Find missing dependencies
    async fn find_missing_dependencies(&self) -> GccResult<Vec<PackageMapping>> {
        let required = self.get_required_packages();
        let mut missing = Vec::new();
        
        for mapping in required {
            if !self.is_installed(&mapping).await {
                missing.push(mapping);
            }
        }
        
        Ok(missing)
    }
    
    /// Get list of required packages
    fn get_required_packages(&self) -> Vec<PackageMapping> {
        vec![
            PackageMapping {
                generic_name: "build-essential",
                packages: HashMap::from([
                    (PackageManager::Apt, vec!["build-essential"]),
                    (PackageManager::Yum, vec!["gcc", "gcc-c++", "make"]),
                    (PackageManager::Dnf, vec!["gcc", "gcc-c++", "make"]),
                    (PackageManager::Pacman, vec!["base-devel"]),
                    (PackageManager::Zypper, vec!["gcc", "gcc-c++", "make"]),
                    (PackageManager::Brew, vec!["gcc"]),
                ]),
            },
            PackageMapping {
                generic_name: "gmp-dev",
                packages: HashMap::from([
                    (PackageManager::Apt, vec!["libgmp-dev"]),
                    (PackageManager::Yum, vec!["gmp-devel"]),
                    (PackageManager::Dnf, vec!["gmp-devel"]),
                    (PackageManager::Pacman, vec!["gmp"]),
                    (PackageManager::Zypper, vec!["gmp-devel"]),
                    (PackageManager::Brew, vec!["gmp"]),
                ]),
            },
            PackageMapping {
                generic_name: "mpfr-dev",
                packages: HashMap::from([
                    (PackageManager::Apt, vec!["libmpfr-dev"]),
                    (PackageManager::Yum, vec!["mpfr-devel"]),
                    (PackageManager::Dnf, vec!["mpfr-devel"]),
                    (PackageManager::Pacman, vec!["mpfr"]),
                    (PackageManager::Zypper, vec!["mpfr-devel"]),
                    (PackageManager::Brew, vec!["mpfr"]),
                ]),
            },
            PackageMapping {
                generic_name: "mpc-dev",
                packages: HashMap::from([
                    (PackageManager::Apt, vec!["libmpc-dev"]),
                    (PackageManager::Yum, vec!["libmpc-devel"]),
                    (PackageManager::Dnf, vec!["libmpc-devel"]),
                    (PackageManager::Pacman, vec!["libmpc"]),
                    (PackageManager::Zypper, vec!["mpc-devel"]),
                    (PackageManager::Brew, vec!["libmpc"]),
                ]),
            },
            PackageMapping {
                generic_name: "flex",
                packages: HashMap::from([
                    (PackageManager::Apt, vec!["flex"]),
                    (PackageManager::Yum, vec!["flex"]),
                    (PackageManager::Dnf, vec!["flex"]),
                    (PackageManager::Pacman, vec!["flex"]),
                    (PackageManager::Zypper, vec!["flex"]),
                    (PackageManager::Brew, vec!["flex"]),
                ]),
            },
            PackageMapping {
                generic_name: "bison",
                packages: HashMap::from([
                    (PackageManager::Apt, vec!["bison"]),
                    (PackageManager::Yum, vec!["bison"]),
                    (PackageManager::Dnf, vec!["bison"]),
                    (PackageManager::Pacman, vec!["bison"]),
                    (PackageManager::Zypper, vec!["bison"]),
                    (PackageManager::Brew, vec!["bison"]),
                ]),
            },
            PackageMapping {
                generic_name: "texinfo",
                packages: HashMap::from([
                    (PackageManager::Apt, vec!["texinfo"]),
                    (PackageManager::Yum, vec!["texinfo"]),
                    (PackageManager::Dnf, vec!["texinfo"]),
                    (PackageManager::Pacman, vec!["texinfo"]),
                    (PackageManager::Zypper, vec!["texinfo"]),
                    (PackageManager::Brew, vec!["texinfo"]),
                ]),
            },
        ]
    }
    
    /// Check if a package is installed
    async fn is_installed(&self, mapping: &PackageMapping) -> bool {
        match &self.package_manager {
            PackageManager::Apt => {
                // Check with dpkg
                if let Some(packages) = mapping.packages.get(&self.package_manager) {
                    for pkg in packages {
                        match self.executor.execute_with_output("dpkg", ["-l", pkg]).await {
                            Ok(output) => {
                                if output.contains("ii ") {
                                    return true;
                                }
                            }
                            Err(_) => continue,
                        }
                    }
                }
            }
            PackageManager::Yum | PackageManager::Dnf => {
                // Check with rpm
                if let Some(packages) = mapping.packages.get(&self.package_manager) {
                    for pkg in packages {
                        if self.executor.execute("rpm", ["-q", pkg]).await.is_ok() {
                            return true;
                        }
                    }
                }
            }
            PackageManager::Pacman => {
                // Check with pacman
                if let Some(packages) = mapping.packages.get(&self.package_manager) {
                    for pkg in packages {
                        if self.executor.execute("pacman", ["-Qs", pkg]).await.is_ok() {
                            return true;
                        }
                    }
                }
            }
            PackageManager::Brew => {
                // Check with brew
                if let Some(packages) = mapping.packages.get(&self.package_manager) {
                    for pkg in packages {
                        if self.executor.execute("brew", ["list", pkg]).await.is_ok() {
                            return true;
                        }
                    }
                }
            }
            _ => {
                // For unknown or other package managers, check common locations
                return match mapping.generic_name {
                    "build-essential" => self.executor.command_exists("gcc").await && self.executor.command_exists("make").await,
                    "gmp-dev" => self.check_library_exists("gmp"),
                    "mpfr-dev" => self.check_library_exists("mpfr"),
                    "mpc-dev" => self.check_library_exists("mpc"),
                    "flex" => self.executor.command_exists("flex").await,
                    "bison" => self.executor.command_exists("bison").await,
                    "texinfo" => self.executor.command_exists("makeinfo").await,
                    _ => false,
                };
            }
        }
        
        false
    }
    
    /// Check if a library exists in common locations
    fn check_library_exists(&self, lib_name: &str) -> bool {
        let common_paths = [
            "/usr/lib",
            "/usr/lib64",
            "/usr/local/lib",
            "/usr/local/lib64",
        ];
        
        for path in common_paths {
            let lib_path = format!("{}/lib{}.so", path, lib_name);
            if std::path::Path::new(&lib_path).exists() {
                return true;
            }
            let lib_path = format!("{}/lib{}.a", path, lib_name);
            if std::path::Path::new(&lib_path).exists() {
                return true;
            }
        }
        
        false
    }
    
    /// Install missing dependencies
    async fn install_dependencies(&self, missing: &[PackageMapping]) -> GccResult<()> {
        if self.dry_run {
            info!("Dry run: Would install missing dependencies");
            self.print_install_commands(missing);
            return Ok(());
        }
        
        match &self.package_manager {
            PackageManager::Unknown => {
                error!("Cannot auto-install: package manager not detected");
                self.print_install_commands(missing);
                return Err(GccBuildError::system_requirements(
                    "Cannot auto-install dependencies: package manager not detected"
                ));
            }
            _ => {}
        }
        
        // Collect all packages to install
        let mut packages = Vec::new();
        for mapping in missing {
            if let Some(pkgs) = mapping.packages.get(&self.package_manager) {
                packages.extend(pkgs.iter().map(|s| s.to_string()));
            }
        }
        
        if packages.is_empty() {
            return Ok(());
        }
        
        info!("📦 Installing {} packages...", packages.len());
        
        // Build install command
        let install_cmd = match &self.package_manager {
            PackageManager::Apt => {
                vec!["sudo", "apt-get", "install", "-y"]
            }
            PackageManager::Yum => {
                vec!["sudo", "yum", "install", "-y"]
            }
            PackageManager::Dnf => {
                vec!["sudo", "dnf", "install", "-y"]
            }
            PackageManager::Pacman => {
                vec!["sudo", "pacman", "-S", "--noconfirm"]
            }
            PackageManager::Zypper => {
                vec!["sudo", "zypper", "install", "-y"]
            }
            PackageManager::Brew => {
                vec!["brew", "install"]
            }
            _ => unreachable!(),
        };
        
        // Add packages to command
        let mut full_cmd = install_cmd;
        full_cmd.extend(packages.iter().map(|s| s.as_str()));
        
        // Execute installation
        info!("Running: {}", full_cmd.join(" "));
        
        match self.executor.execute(&full_cmd[0], &full_cmd[1..]).await {
            Ok(_) => {
                info!("✅ Dependencies installed successfully");
                Ok(())
            }
            Err(e) => {
                error!("Failed to install dependencies: {}", e);
                Err(GccBuildError::package_manager(
                    format!("Failed to install dependencies: {}", e)
                ))
            }
        }
    }
    
    /// Print manual install commands
    fn print_install_commands(&self, missing: &[PackageMapping]) {
        println!("\n{}", "To install missing dependencies manually:".yellow().bold());
        
        match &self.package_manager {
            PackageManager::Apt => {
                let packages: Vec<&str> = missing.iter()
                    .filter_map(|m| m.packages.get(&self.package_manager))
                    .flatten()
                    .copied()
                    .collect();
                println!("  sudo apt-get update");
                println!("  sudo apt-get install -y {}", packages.join(" "));
            }
            PackageManager::Yum => {
                let packages: Vec<&str> = missing.iter()
                    .filter_map(|m| m.packages.get(&self.package_manager))
                    .flatten()
                    .copied()
                    .collect();
                println!("  sudo yum install -y {}", packages.join(" "));
            }
            PackageManager::Dnf => {
                let packages: Vec<&str> = missing.iter()
                    .filter_map(|m| m.packages.get(&self.package_manager))
                    .flatten()
                    .copied()
                    .collect();
                println!("  sudo dnf install -y {}", packages.join(" "));
            }
            PackageManager::Pacman => {
                let packages: Vec<&str> = missing.iter()
                    .filter_map(|m| m.packages.get(&self.package_manager))
                    .flatten()
                    .copied()
                    .collect();
                println!("  sudo pacman -S {}", packages.join(" "));
            }
            _ => {
                println!("  Please install the following packages using your package manager:");
                for mapping in missing {
                    println!("    • {}", mapping.generic_name);
                }
            }
        }
        
        println!("\nOr run with {} to install automatically", "--auto-install-deps".green());
    }
}

