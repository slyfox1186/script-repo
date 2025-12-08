use crate::config::{DISK_SPACE_PER_VERSION_GB, MIN_RAM_MB};
use crate::error::BuildError;
use anyhow::{Context, Result};
use fs2::FileExt;
use nix::unistd::Uid;
use std::fs::{File, OpenOptions};
use std::path::{Path, PathBuf};
use std::process::Command;
use sysinfo::System;
use tracing::{debug, info, warn};

/// Check if running as root
pub fn check_not_root() -> Result<()> {
    if Uid::effective().is_root() {
        return Err(BuildError::RunningAsRoot.into());
    }
    Ok(())
}

/// Get the target architecture triplet
pub fn get_target_arch() -> String {
    // Try gcc -dumpmachine first
    if let Ok(output) = Command::new("gcc").arg("-dumpmachine").output() {
        if output.status.success() {
            let arch = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !arch.is_empty() {
                info!(
                    "Auto-detected machine type using 'gcc -dumpmachine': {}",
                    arch
                );
                return arch;
            }
        }
    }

    // Fallback to cc -dumpmachine
    if let Ok(output) = Command::new("cc").arg("-dumpmachine").output() {
        if output.status.success() {
            let arch = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !arch.is_empty() {
                info!(
                    "Auto-detected machine type using 'cc -dumpmachine': {}",
                    arch
                );
                return arch;
            }
        }
    }

    // Default fallback
    warn!("Could not auto-detect machine type, using default: x86_64-linux-gnu");
    "x86_64-linux-gnu".to_string()
}

/// Check system resources (RAM and disk space)
pub fn check_system_resources(build_dir: &Path, num_versions: usize) -> Result<()> {
    info!("Checking system resources...");

    // Check RAM
    let mut sys = System::new_all();
    sys.refresh_memory();

    let available_ram_mb = sys.available_memory() / 1024 / 1024;
    if available_ram_mb < MIN_RAM_MB {
        return Err(BuildError::InsufficientResources {
            message: format!(
                "Insufficient RAM. Required: {}MB, Available: {}MB",
                MIN_RAM_MB, available_ram_mb
            ),
        }
        .into());
    }
    info!(
        "Available RAM: {}MB (Required: {}MB)",
        available_ram_mb, MIN_RAM_MB
    );

    // Check disk space
    let required_space_gb = DISK_SPACE_PER_VERSION_GB * num_versions as u64 + 5; // +5GB margin

    // Get available disk space using df command
    let output = Command::new("df")
        .args(["-BG", build_dir.to_str().unwrap_or("/tmp")])
        .output()
        .context("Failed to check disk space")?;

    if output.status.success() {
        let output_str = String::from_utf8_lossy(&output.stdout);
        // Parse second line, fourth column (Available)
        if let Some(line) = output_str.lines().nth(1) {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 4 {
                let available_str = parts[3].trim_end_matches('G');
                if let Ok(available_gb) = available_str.parse::<u64>() {
                    if available_gb < required_space_gb {
                        return Err(BuildError::InsufficientResources {
                            message: format!(
                                "Insufficient disk space. Required: {}GB for {} version(s), Available: {}GB",
                                required_space_gb, num_versions, available_gb
                            ),
                        }
                        .into());
                    }
                    info!(
                        "Available disk space: {}GB (Required: {}GB for {} version(s))",
                        available_gb, required_space_gb, num_versions
                    );
                }
            }
        }
    }

    Ok(())
}

/// Lock file manager for preventing concurrent execution
pub struct LockFile {
    file: File,
    path: PathBuf,
}

impl LockFile {
    /// Acquire an exclusive lock
    pub fn acquire() -> Result<Self> {
        let uid = Uid::effective();
        let lock_path = PathBuf::from(format!("/tmp/build-gcc-{}.lock", uid));

        debug!("Acquiring lock at {:?}", lock_path);

        let file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(&lock_path)
            .context("Failed to create lock file")?;

        // Try to acquire exclusive lock (non-blocking)
        match file.try_lock_exclusive() {
            Ok(()) => {
                info!("Lock acquired successfully");
                Ok(Self {
                    file,
                    path: lock_path,
                })
            }
            Err(_) => Err(BuildError::LockFailed.into()),
        }
    }

    /// Release the lock
    pub fn release(&self) -> Result<()> {
        FileExt::unlock(&self.file)?;
        // Try to remove lock file
        let _ = std::fs::remove_file(&self.path);
        debug!("Lock released");
        Ok(())
    }
}

impl Drop for LockFile {
    fn drop(&mut self) {
        let _ = self.release();
    }
}

/// Check if CUDA/nvcc is available
pub fn check_cuda() -> Option<String> {
    if which::which("nvcc").is_ok() {
        if let Ok(output) = Command::new("nvcc").arg("--version").output() {
            if output.status.success() {
                let version = String::from_utf8_lossy(&output.stdout);
                info!("CUDA (nvcc) found. Enabling nvptx offload target.");
                debug!("nvcc version: {}", version.trim());
                return Some("--enable-offload-targets=nvptx-none".to_string());
            }
        }
    }
    info!("CUDA (nvcc) not found. nvptx offload target will not be configured.");
    None
}

/// Get the number of make threads to use
pub fn get_make_threads() -> usize {
    let available = std::thread::available_parallelism()
        .map(|p| p.get())
        .unwrap_or(4);

    // Use all cores minus 2, with a minimum of 2
    std::cmp::max(2, available.saturating_sub(2))
}

/// Run a command and return its output
pub async fn run_command(
    program: &str,
    args: &[&str],
    cwd: Option<&Path>,
    env_vars: Option<&[(&str, &str)]>,
) -> Result<std::process::Output> {
    let mut cmd = tokio::process::Command::new(program);
    cmd.args(args);

    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }

    if let Some(vars) = env_vars {
        for (key, value) in vars {
            cmd.env(key, value);
        }
    }

    let output = cmd
        .output()
        .await
        .with_context(|| format!("Failed to execute command: {} {}", program, args.join(" ")))?;

    Ok(output)
}

/// Run a command with sudo
pub async fn run_sudo_command(
    program: &str,
    args: &[&str],
    cwd: Option<&Path>,
) -> Result<std::process::Output> {
    let mut full_args = vec![program];
    full_args.extend(args);

    run_command("sudo", &full_args, cwd, None).await
}

/// Create a secure temporary directory
pub fn create_secure_temp_dir() -> Result<tempfile::TempDir> {
    tempfile::Builder::new()
        .prefix("build-gcc.")
        .tempdir()
        .context("Failed to create secure temporary directory")
}

/// Get current user name
pub fn get_username() -> String {
    std::env::var("USER").unwrap_or_else(|_| "unknown".to_string())
}

/// Get current user's group name
pub fn get_groupname() -> String {
    // Use id -gn command
    if let Ok(output) = Command::new("id").arg("-gn").output() {
        if output.status.success() {
            return String::from_utf8_lossy(&output.stdout).trim().to_string();
        }
    }
    get_username() // Fallback to username
}
