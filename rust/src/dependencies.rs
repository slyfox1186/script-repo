use crate::config::{MULTILIB_PACKAGES, REQUIRED_PACKAGES};
use crate::error::BuildError;
use crate::system::run_sudo_command;
use anyhow::{Context, Result};
use std::collections::HashSet;
use std::process::Command;
use tracing::{debug, info, warn};

/// Check which packages are installed
fn get_installed_packages() -> Result<HashSet<String>> {
    let output = Command::new("dpkg-query")
        .args(["-W", "-f=${Package}\t${Status}\n"])
        .output()
        .context("Failed to query installed packages")?;

    let mut installed = HashSet::new();

    if output.status.success() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        for line in stdout.lines() {
            if let Some((package, status)) = line.split_once('\t') {
                if status.contains("ok installed") {
                    installed.insert(package.to_string());
                }
            }
        }
    }

    Ok(installed)
}

/// Check and install required system dependencies
pub async fn install_dependencies(
    enable_multilib: bool,
    dry_run: bool,
    target_arch: &str,
) -> Result<()> {
    info!("Checking and installing system dependencies...");

    let installed = get_installed_packages()?;

    // Build list of required packages
    let mut required: Vec<&str> = REQUIRED_PACKAGES.to_vec();

    // Add multilib packages if needed
    if enable_multilib && target_arch == "x86_64-linux-gnu" {
        info!("Multilib flag is set, adding i386 development packages");
        required.extend(MULTILIB_PACKAGES);
    }

    // Find missing packages
    let missing: Vec<&str> = required
        .iter()
        .filter(|pkg| !installed.contains(**pkg))
        .copied()
        .collect();

    if missing.is_empty() {
        info!("All required system dependencies appear to be installed.");
        return Ok(());
    }

    info!("Missing required packages: {}", missing.join(", "));

    if dry_run {
        info!("Dry run: would attempt to install {}", missing.join(", "));
        return Ok(());
    }

    // Update package lists
    info!("Updating package lists...");
    let output = run_sudo_command("apt-get", &["update"], None).await?;
    if !output.status.success() {
        return Err(BuildError::DependencyInstall {
            message: "Failed to update package lists (apt-get update)".to_string(),
        }
        .into());
    }

    // Install missing packages
    info!("Installing missing packages...");
    let mut args = vec!["apt-get", "install", "-y", "--no-install-recommends"];
    args.extend(missing.iter());

    let output = run_sudo_command("apt-get", &args[1..], None).await?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(BuildError::DependencyInstall {
            message: format!(
                "Failed to install packages: {}. Error: {}",
                missing.join(", "),
                stderr
            ),
        }
        .into());
    }

    info!("Successfully installed missing packages.");
    Ok(())
}

/// Check if autoconf is available
pub fn check_autoconf() -> Result<()> {
    match Command::new("autoconf").arg("--version").output() {
        Ok(output) if output.status.success() => {
            let version = String::from_utf8_lossy(&output.stdout);
            let first_line = version.lines().next().unwrap_or("unknown");
            info!("Found autoconf: {}", first_line);
            Ok(())
        }
        _ => {
            warn!("autoconf not found. It should have been installed by install_dependencies.");
            Ok(()) // Don't fail, it might be installed by dependencies
        }
    }
}

/// Check if a command is available in PATH
pub fn command_exists(command: &str) -> bool {
    which::which(command).is_ok()
}

/// Check for required build tools
pub fn check_build_tools() -> Result<()> {
    let required_tools = ["gcc", "g++", "make", "tar", "wget", "curl"];

    for tool in required_tools {
        if !command_exists(tool) {
            return Err(BuildError::MissingDependency {
                package: tool.to_string(),
            }
            .into());
        }
        debug!("Found required tool: {}", tool);
    }

    info!("All required build tools are available.");
    Ok(())
}
