use dashmap::DashMap;
use futures::future::join_all;
use log::{info, warn};
use once_cell::sync::Lazy;
use rayon::prelude::*;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tempfile::NamedTempFile;
use tokio::sync::Semaphore;
use walkdir::WalkDir;

use crate::error::{GccBuildError, Result as GccResult};
use crate::files::FileOperations;

/// Cache for symlink operations to avoid redundant checks
static SYMLINK_CACHE: Lazy<DashMap<PathBuf, PathBuf>> = Lazy::new(DashMap::new);

/// Optimized batch symlink creator
pub struct SymlinkOptimizer {
    file_ops: FileOperations,
    max_parallel: usize,
}

impl SymlinkOptimizer {
    pub fn new(dry_run: bool) -> Self {
        Self {
            file_ops: FileOperations::new(dry_run),
            // Use rayon's thread pool size, cap at 32
            max_parallel: rayon::current_num_threads().min(32),
        }
    }

    /// Create symlinks in parallel with batch sudo optimization
    pub async fn create_symlinks_batch(
        &self,
        symlinks: Vec<(PathBuf, PathBuf)>,
        use_sudo: bool,
    ) -> GccResult<usize> {
        if symlinks.is_empty() {
            return Ok(0);
        }

        info!(
            "🚀 Creating {} symlinks with parallel optimization",
            symlinks.len()
        );

        if use_sudo {
            // ULTRAFAST: Single sudo call for all symlinks
            self.create_symlinks_sudo_batch(symlinks).await
        } else {
            // Parallel creation without sudo
            self.create_symlinks_parallel(symlinks).await
        }
    }

    /// Create all symlinks with a single sudo call
    async fn create_symlinks_sudo_batch(
        &self,
        symlinks: Vec<(PathBuf, PathBuf)>,
    ) -> GccResult<usize> {
        // Build batch script
        let mut script = String::from("#!/bin/bash\nset -e\n");
        let mut count = 0;

        for (source, target) in &symlinks {
            // Check cache first
            if let Some(cached) = SYMLINK_CACHE.get(target) {
                if cached.value() == source {
                    continue; // Already created
                }
            }

            // Add to batch script
            script.push_str(&format!(
                "if [ ! -L \"{}\" ] || [ \"$(readlink -f \"{}\")\" != \"{}\" ]; then\n",
                target.display(),
                target.display(),
                source.display()
            ));
            script.push_str(&format!("  rm -f \"{}\"\n", target.display()));
            script.push_str(&format!(
                "  ln -sf \"{}\" \"{}\"\n",
                source.display(),
                target.display()
            ));
            script.push_str(&format!(
                "  echo \"✅ Linked: {}\"\n",
                target.file_name().unwrap().to_string_lossy()
            ));
            script.push_str("fi\n");
            count += 1;
        }

        if count == 0 {
            info!("⚡ All symlinks already up to date (cached)");
            return Ok(0);
        }

        // Execute batch script with single sudo call
        let script_file = NamedTempFile::new().map_err(|e| {
            GccBuildError::file_operation(
                "create_temp_file".to_string(),
                "batch_symlink_script".to_string(),
                e.to_string(),
            )
        })?;
        std::fs::write(script_file.path(), script).map_err(|e| {
            GccBuildError::file_operation(
                "write".to_string(),
                script_file.path().display().to_string(),
                e.to_string(),
            )
        })?;

        let output = tokio::process::Command::new("sudo")
            .arg("bash")
            .arg(script_file.path())
            .output()
            .await
            .map_err(|e| {
                GccBuildError::command_failed(
                    "sudo batch symlink".to_string(),
                    e.raw_os_error().unwrap_or(-1),
                )
            })?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(GccBuildError::command_failed(
                format!("sudo batch symlink: {}", stderr),
                output.status.code().unwrap_or(-1),
            ));
        }

        // Update cache
        for (source, target) in symlinks {
            SYMLINK_CACHE.insert(target, source);
        }

        Ok(count)
    }

    /// Create symlinks in parallel without sudo
    async fn create_symlinks_parallel(
        &self,
        symlinks: Vec<(PathBuf, PathBuf)>,
    ) -> GccResult<usize> {
        let semaphore = Arc::new(Semaphore::new(self.max_parallel));

        let tasks: Vec<_> = symlinks
            .into_iter()
            .map(|(source, target)| {
                let sem = semaphore.clone();
                let file_ops = self.file_ops.clone();

                tokio::spawn(async move {
                    let _permit = sem.acquire().await.unwrap();

                    // Check cache
                    if let Some(cached) = SYMLINK_CACHE.get(&target) {
                        if cached.value() == &source {
                            return Ok::<bool, GccBuildError>(false); // Already exists
                        }
                    }

                    match file_ops.create_symlink(&source, &target, true) {
                        Ok(_) => {
                            SYMLINK_CACHE.insert(target.clone(), source);
                            Ok::<bool, GccBuildError>(true)
                        }
                        Err(e) => {
                            warn!("Failed to create symlink {:?}: {}", target, e);
                            Ok::<bool, GccBuildError>(false)
                        }
                    }
                })
            })
            .collect();

        let results = join_all(tasks).await;

        let created_count = results
            .into_iter()
            .filter_map(|r| r.ok())
            .filter_map(|r| r.ok())
            .filter(|created| *created)
            .count();

        Ok(created_count)
    }

    /// Clear the symlink cache - used for testing and when installation paths change
    pub fn clear_cache() {
        info!(
            "🧹 Clearing symlink cache ({} entries)",
            SYMLINK_CACHE.len()
        );
        SYMLINK_CACHE.clear();
    }
}

/// Optimized binary discovery using parallel directory scanning
pub async fn discover_gcc_binaries_parallel(
    bin_dir: &Path,
    version_patterns: &[String],
) -> GccResult<Vec<(PathBuf, String)>> {
    let patterns = version_patterns.to_vec();
    let bin_dir = bin_dir.to_path_buf();

    // Use tokio to spawn blocking operation
    let binaries = tokio::task::spawn_blocking(move || {
        WalkDir::new(&bin_dir)
            .max_depth(1)
            .into_iter()
            .par_bridge()
            .filter_map(|entry| entry.ok())
            .filter(|entry| entry.file_type().is_file())
            .filter_map(|entry| {
                let path = entry.path().to_path_buf();
                let filename = path.file_name()?.to_str()?.to_string();

                // Check if executable (Unix only)
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    if let Ok(metadata) = entry.metadata() {
                        if metadata.permissions().mode() & 0o111 == 0 {
                            return None; // Not executable
                        }
                    }
                }

                // Check if filename matches any pattern
                for pattern in &patterns {
                    if filename.ends_with(pattern) {
                        return Some((path, filename));
                    }
                }
                None
            })
            .collect::<Vec<_>>()
    })
    .await
    .map_err(|_| GccBuildError::Configuration {
        message: "Failed to spawn blocking task for directory scanning".to_string(),
    })?;

    info!("⚡ Discovered {} GCC binaries in parallel", binaries.len());
    Ok(binaries)
}
