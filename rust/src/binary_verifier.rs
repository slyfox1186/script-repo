use dashmap::DashMap;
use log::{debug, info, warn};
use once_cell::sync::Lazy;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};
use tokio::process::Command;

use crate::config::GccVersion;
use crate::error::{GccBuildError, Result as GccResult};

/// Cache for binary verification results to avoid repeated checks
static VERIFICATION_CACHE: Lazy<DashMap<(PathBuf, String), VerificationResult>> =
    Lazy::new(DashMap::new);

#[derive(Debug, Clone, PartialEq)]
pub enum VerificationLevel {
    /// Quick: Check file exists and is executable
    Quick,
    /// Fast: Quick + run --version
    Fast,
    /// Full: Fast + compile a simple test program
    Full,
}

#[derive(Debug, Clone)]
pub struct VerificationResult {
    pub exists: bool,
    pub executable: bool,
    pub version_works: bool,
    pub compile_works: bool,
    pub version_string: Option<String>,
    pub verified_at: Instant,
}

impl VerificationResult {
    pub fn is_valid(&self, level: &VerificationLevel) -> bool {
        match level {
            VerificationLevel::Quick => self.exists && self.executable,
            VerificationLevel::Fast => self.exists && self.executable && self.version_works,
            VerificationLevel::Full => {
                self.exists && self.executable && self.version_works && self.compile_works
            }
        }
    }

    pub fn is_fresh(&self, max_age: Duration) -> bool {
        self.verified_at.elapsed() < max_age
    }
}

pub struct BinaryVerifier {
    verification_level: VerificationLevel,
    cache_max_age: Duration,
}

impl BinaryVerifier {
    pub fn new(level: VerificationLevel) -> Self {
        Self {
            verification_level: level,
            cache_max_age: Duration::from_secs(300), // 5 minutes
        }
    }

    /// Verify ALL essential GCC binaries in parallel
    pub async fn verify_gcc_installation(
        &self,
        install_prefix: &Path,
        version: &GccVersion,
    ) -> GccResult<bool> {
        let bin_dir = install_prefix.join("bin");

        if !bin_dir.exists() {
            debug!("Binary directory does not exist: {}", bin_dir.display());
            return Ok(false);
        }

        // Essential binaries that MUST exist for a valid GCC installation
        let essential_binaries = vec![
            format!("gcc-{}", version.major),
            format!("g++-{}", version.major),
            // Optional but important
            format!("gfortran-{}", version.major),
            format!("gcov-{}", version.major),
        ];

        info!(
            "🔍 Verifying GCC {} installation at {}",
            version,
            install_prefix.display()
        );

        // Spawn parallel verification tasks
        let verification_tasks: Vec<_> = essential_binaries
            .into_iter()
            .map(|binary_name| {
                let binary_path = bin_dir.join(&binary_name);
                let level = self.verification_level.clone();
                let cache_key = (binary_path.clone(), binary_name.clone());

                tokio::spawn(async move {
                    // Check cache first with proper max age
                    let verifier = BinaryVerifier::new(level.clone());
                    if let Some(cached) = VERIFICATION_CACHE.get(&cache_key) {
                        if cached.is_fresh(verifier.cache_max_age) {
                            debug!(
                                "Using cached verification for {} ({})",
                                binary_name,
                                cached
                                    .version_string
                                    .as_deref()
                                    .unwrap_or("unknown version")
                            );
                            return Ok((binary_name.clone(), cached.is_valid(&level)));
                        }
                    }

                    // Perform verification
                    let result = Self::verify_single_binary(&binary_path, &level).await?;
                    let is_valid = result.is_valid(&level);

                    // Cache result
                    VERIFICATION_CACHE.insert(cache_key, result);

                    Ok::<(String, bool), GccBuildError>((binary_name, is_valid))
                })
            })
            .collect();

        // Wait for all verifications to complete
        let results = futures::future::join_all(verification_tasks).await;

        let mut all_valid = true;
        let mut verified_count = 0;
        let mut essential_missing = Vec::new();

        for task_result in results {
            match task_result {
                Ok(Ok((binary_name, is_valid))) => {
                    if is_valid {
                        // Show version info if available
                        let version_info = VERIFICATION_CACHE
                            .get(&(bin_dir.join(&binary_name), binary_name.clone()))
                            .and_then(|cached| cached.version_string.clone())
                            .map(|v| format!(" ({})", v.lines().next().unwrap_or(&v)))
                            .unwrap_or_default();
                        info!("  ✅ {}{} - OK", binary_name, version_info);
                        verified_count += 1;
                    } else {
                        if binary_name.starts_with("gcc-") || binary_name.starts_with("g++-") {
                            // Critical binaries
                            essential_missing.push(binary_name.clone());
                            all_valid = false;
                        }
                        warn!("  ❌ {} - FAILED", binary_name);
                    }
                }
                Ok(Err(e)) => {
                    warn!("  ⚠️  Verification error: {}", e);
                    all_valid = false;
                }
                Err(e) => {
                    warn!("  ⚠️  Task error: {}", e);
                    all_valid = false;
                }
            }
        }

        if all_valid {
            info!(
                "✅ GCC {} installation verified ({} binaries)",
                version, verified_count
            );
        } else if !essential_missing.is_empty() {
            info!(
                "❌ GCC {} installation incomplete (missing: {})",
                version,
                essential_missing.join(", ")
            );
        }

        Ok(all_valid)
    }

    /// Verify a single binary with the specified level
    async fn verify_single_binary(
        binary_path: &Path,
        level: &VerificationLevel,
    ) -> GccResult<VerificationResult> {
        let start_time = Instant::now();

        // Quick check: file exists and is executable
        let (exists, executable) = if binary_path.exists() {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                if let Ok(metadata) = std::fs::metadata(binary_path) {
                    let is_executable = metadata.permissions().mode() & 0o111 != 0;
                    (true, is_executable)
                } else {
                    (false, false)
                }
            }
            #[cfg(not(unix))]
            {
                (true, true) // Assume executable on non-Unix
            }
        } else {
            (false, false)
        };

        if !exists || !executable {
            return Ok(VerificationResult {
                exists,
                executable,
                version_works: false,
                compile_works: false,
                version_string: None,
                verified_at: start_time,
            });
        }

        // Fast check: run --version
        let (version_works, version_string) =
            if matches!(level, VerificationLevel::Fast | VerificationLevel::Full) {
                match Self::check_version(binary_path).await {
                    Ok(version_str) => (true, Some(version_str)),
                    Err(_) => (false, None),
                }
            } else {
                (true, None) // Skip for Quick level
            };

        // Full check: compile test program
        let compile_works = if matches!(level, VerificationLevel::Full) && version_works {
            Self::check_compile(binary_path).await.unwrap_or(false)
        } else {
            true // Skip for Quick/Fast levels
        };

        Ok(VerificationResult {
            exists,
            executable,
            version_works,
            compile_works,
            version_string,
            verified_at: start_time,
        })
    }

    /// Quick version check
    async fn check_version(binary_path: &Path) -> GccResult<String> {
        let output = Command::new(binary_path)
            .arg("--version")
            .output()
            .await
            .map_err(|e| GccBuildError::CommandFailed {
                command: format!("{} --version", binary_path.display()),
                exit_code: e.raw_os_error().unwrap_or(-1),
            })?;

        if output.status.success() {
            let version_output = String::from_utf8_lossy(&output.stdout);
            let first_line = version_output.lines().next().unwrap_or("").to_string();
            Ok(first_line)
        } else {
            Err(GccBuildError::CommandFailed {
                command: format!("{} --version", binary_path.display()),
                exit_code: output.status.code().unwrap_or(-1),
            })
        }
    }

    /// Compile test to verify functionality
    async fn check_compile(binary_path: &Path) -> GccResult<bool> {
        // Create a simple test program
        let test_program = r#"
#include <stdio.h>
int main() {
    printf("Hello, GCC!\n");
    return 0;
}
"#;

        let temp_dir = tempfile::tempdir().map_err(|e| GccBuildError::FileOperation {
            operation: "create_temp_dir".to_string(),
            path: "compile_test".to_string(),
            reason: e.to_string(),
        })?;

        let source_file = temp_dir.path().join("test.c");
        let output_file = temp_dir.path().join("test");

        // Write test program
        std::fs::write(&source_file, test_program).map_err(|e| GccBuildError::FileOperation {
            operation: "write".to_string(),
            path: source_file.display().to_string(),
            reason: e.to_string(),
        })?;

        // Compile with timeout
        let compile_result = tokio::time::timeout(
            Duration::from_secs(10),
            Command::new(binary_path)
                .arg("-o")
                .arg(&output_file)
                .arg(&source_file)
                .output(),
        )
        .await;

        match compile_result {
            Ok(Ok(output)) => Ok(output.status.success() && output_file.exists()),
            _ => Ok(false),
        }
    }

    /// Clear verification cache - useful when installations change or during force rebuild
    pub fn clear_cache() {
        let cache_size = VERIFICATION_CACHE.len();
        if cache_size > 0 {
            info!(
                "🧹 Clearing binary verification cache ({} entries)",
                cache_size
            );
            VERIFICATION_CACHE.clear();
        }
    }
}

/// Check if GCC installation should be skipped
pub async fn should_skip_build(
    install_prefix: &Path,
    version: &GccVersion,
    force_rebuild: bool,
    verification_level: VerificationLevel,
) -> GccResult<bool> {
    if force_rebuild {
        info!(
            "🔄 Force rebuild enabled - will rebuild GCC {} even if present",
            version
        );
        // Clear caches to ensure fresh verification during force rebuild
        BinaryVerifier::clear_cache();
        crate::symlink_optimizer::SymlinkOptimizer::clear_cache();
        return Ok(false);
    }

    let verifier = BinaryVerifier::new(verification_level);
    let is_valid = verifier
        .verify_gcc_installation(install_prefix, version)
        .await?;

    if is_valid {
        info!(
            "⚡ GCC {} already installed and verified - SKIPPING build",
            version
        );
        info!("   📍 Location: {}", install_prefix.display());
        info!("   💡 Use --force-rebuild to rebuild anyway");
        Ok(true)
    } else {
        info!(
            "🔨 GCC {} not found or invalid - proceeding with build",
            version
        );
        Ok(false)
    }
}
