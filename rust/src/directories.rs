#![allow(dead_code)]
use log::{debug, info};
use std::fs;
use std::path::{Path, PathBuf};

use crate::error::{GccBuildError, Result as GccResult};

#[derive(Debug, Clone)]
pub struct DirectoryOperations {
    pub dry_run: bool,
}

impl DirectoryOperations {
    pub fn new(dry_run: bool) -> Self {
        Self { dry_run }
    }

    /// Create directory with proper error handling and logging
    pub fn create_directory(&self, dir: &Path, description: &str, use_sudo: bool) -> GccResult<()> {
        if self.dry_run {
            info!("Dry run: would create {}: {:?}", description, dir);
            return Ok(());
        }

        if dir.exists() {
            debug!("{} already exists: {:?}", description, dir);
            return Ok(());
        }

        if use_sudo {
            // Use sudo to create directory
            let status = std::process::Command::new("sudo")
                .args(["mkdir", "-p"])
                .arg(dir)
                .status()
                .map_err(|e| {
                    GccBuildError::directory_operation(
                        "sudo_mkdir".to_string(),
                        dir.display().to_string(),
                        e.to_string(),
                    )
                })?;

            if !status.success() {
                return Err(GccBuildError::directory_operation(
                    "sudo_mkdir".to_string(),
                    dir.display().to_string(),
                    "sudo mkdir command failed".to_string(),
                ));
            }
        } else {
            fs::create_dir_all(dir).map_err(|e| {
                GccBuildError::directory_operation(
                    "create_dir_all".to_string(),
                    dir.display().to_string(),
                    e.to_string(),
                )
            })?;
        }

        debug!("Created {}: {:?}", description, dir);
        Ok(())
    }

    /// Create multiple directories at once
    pub fn create_directories(&self, dirs: &[&Path]) -> GccResult<()> {
        let mut failed_dirs = Vec::new();

        for &dir in dirs {
            if self.dry_run {
                info!("Dry run: would create directory: {:?}", dir);
                continue;
            }

            if let Err(e) = fs::create_dir_all(dir) {
                failed_dirs.push(format!("{}: {}", dir.display(), e));
            } else {
                debug!("Created directory: {:?}", dir);
            }
        }

        if !failed_dirs.is_empty() {
            return Err(GccBuildError::directory_operation(
                "create_multiple".to_string(),
                "multiple directories".to_string(),
                format!("Failed to create directories: {}", failed_dirs.join(", ")),
            ));
        }

        if !self.dry_run {
            debug!("Created directories: {:?}", dirs);
        }
        Ok(())
    }

    /// Check if directory exists and is writable
    pub fn check_directory_writable(&self, dir: &Path, description: &str) -> GccResult<()> {
        if !dir.exists() {
            self.create_directory(dir, description, false)?;
        } else if !self.is_writable(dir)? {
            return Err(GccBuildError::directory_operation(
                "check_writable".to_string(),
                dir.display().to_string(),
                format!("{} exists but is not writable", description),
            ));
        }

        Ok(())
    }

    /// Check if a directory is writable
    pub fn is_writable(&self, dir: &Path) -> GccResult<bool> {
        if !dir.exists() {
            return Ok(false);
        }

        // Try to create a temporary file in the directory
        let temp_file = dir.join(".gcc_builder_write_test");

        match fs::write(&temp_file, "test") {
            Ok(_) => {
                // Clean up the test file
                let _ = fs::remove_file(&temp_file);
                Ok(true)
            }
            Err(_) => Ok(false),
        }
    }

    /// Get available disk space for a directory in specified unit
    pub fn get_available_space(&self, path: &Path, unit: SpaceUnit) -> GccResult<u64> {
        // Use statvfs on Unix systems
        #[cfg(unix)]
        {
            use std::ffi::CString;
            use std::mem;

            let path_cstring = CString::new(path.to_string_lossy().as_bytes()).map_err(|e| {
                GccBuildError::directory_operation(
                    "path_conversion".to_string(),
                    path.display().to_string(),
                    e.to_string(),
                )
            })?;

            let mut statvfs: libc::statvfs = unsafe { mem::zeroed() };

            let result = unsafe { libc::statvfs(path_cstring.as_ptr(), &mut statvfs) };

            if result != 0 {
                return Err(GccBuildError::directory_operation(
                    "statvfs".to_string(),
                    path.display().to_string(),
                    "Failed to get filesystem stats".to_string(),
                ));
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
            // Fallback for non-Unix systems using df command
            let output = std::process::Command::new("df")
                .arg("-B1") // Output in bytes
                .arg(path)
                .output()
                .map_err(|e| GccBuildError::directory_operation(
                    "df_command".to_string(),
                    path.display().to_string(),
                    e.to_string(),
                ))?;

            if !output.status.success() {
                return Err(GccBuildError::directory_operation(
                    "df_command".to_string(),
                    path.display().to_string(),
                    "df command failed".to_string(),
                ));
            }

            let output_str = String::from_utf8_lossy(&output.stdout);
            let lines: Vec<&str> = output_str.lines().collect();

            if lines.len() < 2 {
                return Err(GccBuildError::directory_operation(
                    "df_parse".to_string(),
                    path.display().to_string(),
                    "Unexpected df output".to_string(),
                ));
            }

            let fields: Vec<&str> = lines[1].split_whitespace().collect();
            if fields.len() < 4 {
                return Err(GccBuildError::directory_operation(
                    "df_parse".to_string(),
                    path.display().to_string(),
                    "Cannot parse df output".to_string(),
                ));
            }

            let available_bytes: u64 = fields[3].parse().map_err(|e| {
                GccBuildError::directory_operation(
                    "df_parse".to_string(),
                    path.display().to_string(),
                    format!("Cannot parse available bytes: {}", e),
                )
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

    /// Remove directory and all its contents
    pub fn remove_directory(&self, dir: &Path) -> GccResult<()> {
        if self.dry_run {
            info!("Dry run: would remove directory: {:?}", dir);
            return Ok(());
        }

        if !dir.exists() {
            debug!("Directory does not exist, nothing to remove: {:?}", dir);
            return Ok(());
        }

        fs::remove_dir_all(dir).map_err(|e| {
            GccBuildError::directory_operation(
                "remove_dir_all".to_string(),
                dir.display().to_string(),
                e.to_string(),
            )
        })?;

        debug!("Removed directory: {:?}", dir);
        Ok(())
    }

    /// Clean directory contents but keep the directory itself
    pub fn clean_directory(&self, dir: &Path) -> GccResult<()> {
        if self.dry_run {
            info!("Dry run: would clean directory: {:?}", dir);
            return Ok(());
        }

        if !dir.exists() {
            debug!("Directory does not exist: {:?}", dir);
            return Ok(());
        }

        let entries = fs::read_dir(dir).map_err(|e| {
            GccBuildError::directory_operation(
                "read_dir".to_string(),
                dir.display().to_string(),
                e.to_string(),
            )
        })?;

        for entry in entries {
            let entry = entry.map_err(|e| {
                GccBuildError::directory_operation(
                    "read_dir_entry".to_string(),
                    dir.display().to_string(),
                    e.to_string(),
                )
            })?;

            let path = entry.path();

            if path.is_dir() {
                fs::remove_dir_all(&path).map_err(|e| {
                    GccBuildError::directory_operation(
                        "remove_dir_all".to_string(),
                        path.display().to_string(),
                        e.to_string(),
                    )
                })?;
            } else {
                fs::remove_file(&path).map_err(|e| {
                    GccBuildError::directory_operation(
                        "remove_file".to_string(),
                        path.display().to_string(),
                        e.to_string(),
                    )
                })?;
            }
        }

        debug!("Cleaned directory: {:?}", dir);
        Ok(())
    }

    /// Ensure directory exists and has proper permissions
    pub fn ensure_directory(
        &self,
        dir: &Path,
        description: &str,
        create_if_missing: bool,
    ) -> GccResult<()> {
        if dir.exists() {
            if !dir.is_dir() {
                return Err(GccBuildError::directory_operation(
                    "ensure_directory".to_string(),
                    dir.display().to_string(),
                    format!("{} exists but is not a directory", description),
                ));
            }

            debug!("{} already exists: {:?}", description, dir);
            return Ok(());
        }

        if create_if_missing {
            self.create_directory(dir, description, false)?;
        } else {
            return Err(GccBuildError::directory_operation(
                "ensure_directory".to_string(),
                dir.display().to_string(),
                format!("{} does not exist", description),
            ));
        }

        Ok(())
    }

    /// Copy directory recursively
    pub fn copy_directory(&self, source: &Path, destination: &Path) -> GccResult<()> {
        if self.dry_run {
            info!(
                "Dry run: would copy directory {:?} to {:?}",
                source, destination
            );
            return Ok(());
        }

        if !source.exists() {
            return Err(GccBuildError::directory_operation(
                "copy_directory".to_string(),
                source.display().to_string(),
                "Source directory does not exist".to_string(),
            ));
        }

        if !source.is_dir() {
            return Err(GccBuildError::directory_operation(
                "copy_directory".to_string(),
                source.display().to_string(),
                "Source is not a directory".to_string(),
            ));
        }

        self.create_directory(destination, "destination directory", false)?;

        let entries = fs::read_dir(source).map_err(|e| {
            GccBuildError::directory_operation(
                "read_dir".to_string(),
                source.display().to_string(),
                e.to_string(),
            )
        })?;

        for entry in entries {
            let entry = entry.map_err(|e| {
                GccBuildError::directory_operation(
                    "read_dir_entry".to_string(),
                    source.display().to_string(),
                    e.to_string(),
                )
            })?;

            let source_path = entry.path();
            let dest_path = destination.join(entry.file_name());

            if source_path.is_dir() {
                self.copy_directory(&source_path, &dest_path)?;
            } else {
                fs::copy(&source_path, &dest_path).map_err(|e| {
                    GccBuildError::directory_operation(
                        "copy_file".to_string(),
                        format!("{} -> {}", source_path.display(), dest_path.display()),
                        e.to_string(),
                    )
                })?;
            }
        }

        debug!("Copied directory: {:?} -> {:?}", source, destination);
        Ok(())
    }

    /// Get directory size recursively
    pub fn get_directory_size(&self, dir: &Path) -> GccResult<u64> {
        if !dir.exists() {
            return Ok(0);
        }

        if !dir.is_dir() {
            let metadata = dir.metadata().map_err(|e| {
                GccBuildError::directory_operation(
                    "metadata".to_string(),
                    dir.display().to_string(),
                    e.to_string(),
                )
            })?;
            return Ok(metadata.len());
        }

        let mut total_size = 0u64;

        let entries = fs::read_dir(dir).map_err(|e| {
            GccBuildError::directory_operation(
                "read_dir".to_string(),
                dir.display().to_string(),
                e.to_string(),
            )
        })?;

        for entry in entries {
            let entry = entry.map_err(|e| {
                GccBuildError::directory_operation(
                    "read_dir_entry".to_string(),
                    dir.display().to_string(),
                    e.to_string(),
                )
            })?;

            let path = entry.path();

            if path.is_dir() {
                total_size += self.get_directory_size(&path)?;
            } else {
                let metadata = path.metadata().map_err(|e| {
                    GccBuildError::directory_operation(
                        "metadata".to_string(),
                        path.display().to_string(),
                        e.to_string(),
                    )
                })?;
                total_size += metadata.len();
            }
        }

        Ok(total_size)
    }
}

#[derive(Debug, Clone)]
pub enum SpaceUnit {
    Bytes,
    KB,
    MB,
    GB,
}

/// Batch create multiple directories efficiently
pub fn create_build_directories(paths: &[PathBuf], dry_run: bool) -> GccResult<()> {
    let dir_ops = DirectoryOperations::new(dry_run);

    for path in paths {
        dir_ops.create_directory(path, &format!("build directory: {}", path.display()), false)?;
    }

    Ok(())
}
