use crate::config::GccVersion;
use crate::system::run_sudo_command;
use anyhow::{Context, Result};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use tracing::{debug, info, warn};

/// Trim the target architecture prefix from binary names
pub async fn trim_binaries(
    _version: &GccVersion,
    install_dir: &Path,
    target_arch: &str,
    dry_run: bool,
) -> Result<()> {
    let bin_dir = install_dir.join("bin");
    info!(
        "Trimming binary filenames in {} (removing {}- prefix)",
        bin_dir.display(),
        target_arch
    );

    if !bin_dir.exists() {
        warn!(
            "Binary directory {} not found. Skipping trimming.",
            bin_dir.display()
        );
        return Ok(());
    }

    if target_arch.is_empty() {
        warn!("target_arch is empty. Cannot trim binaries safely. Skipping.");
        return Ok(());
    }

    let prefix = format!("{}-", target_arch);

    // Find all files with the architecture prefix
    let entries: Vec<_> = fs::read_dir(&bin_dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.file_name().to_string_lossy().starts_with(&prefix))
        .collect();

    if dry_run {
        for entry in &entries {
            let old_name = entry.file_name();
            let new_name = old_name
                .to_string_lossy()
                .trim_start_matches(&prefix)
                .to_string();
            info!(
                "Dry run: would rename {} to {}",
                old_name.to_string_lossy(),
                new_name
            );
        }
        return Ok(());
    }

    for entry in entries {
        let old_name = entry.file_name();
        let new_name = old_name
            .to_string_lossy()
            .trim_start_matches(&prefix)
            .to_string();
        let old_path = entry.path();
        let new_path = bin_dir.join(&new_name);

        // Check if destination already exists
        if new_path.exists() {
            // Check if it's a symlink pointing to the old name
            if new_path.is_symlink() {
                let target = fs::read_link(&new_path)?;
                if target == old_path {
                    debug!(
                        "Symlink {} already points to {}. Skipping.",
                        new_name,
                        old_name.to_string_lossy()
                    );
                    continue;
                }
            }
            warn!(
                "File {} already exists. Skipping rename of {}.",
                new_name,
                old_name.to_string_lossy()
            );
            continue;
        }

        info!("Renaming {} to {}", old_name.to_string_lossy(), new_name);
        let output = run_sudo_command(
            "mv",
            &[old_path.to_str().unwrap(), new_path.to_str().unwrap()],
            None,
        )
        .await?;

        if output.status.success() {
            info!(
                "Renamed {} to {} successfully",
                old_name.to_string_lossy(),
                new_name
            );
        } else {
            warn!(
                "Failed to rename {} to {}",
                old_name.to_string_lossy(),
                new_name
            );
        }
    }

    Ok(())
}

/// Create symlinks in /usr/local/bin
pub async fn create_symlinks(
    version: &GccVersion,
    install_dir: &Path,
    dry_run: bool,
) -> Result<()> {
    let bin_dir = install_dir.join("bin");
    let symlink_dir = PathBuf::from("/usr/local/bin");

    if !bin_dir.exists() {
        warn!(
            "Binary directory {} not found. Cannot create symlinks.",
            bin_dir.display()
        );
        return Ok(());
    }

    info!(
        "Creating symlinks in {} for GCC {} executables",
        symlink_dir.display(),
        version.full
    );

    // Ensure symlink directory exists
    if !symlink_dir.exists() {
        if dry_run {
            info!("Dry run: would create directory {}", symlink_dir.display());
        } else {
            run_sudo_command("mkdir", &["-p", symlink_dir.to_str().unwrap()], None).await?;
        }
    }

    let mut created_count = 0;
    let mut skipped_count = 0;

    // Iterate over executables
    for entry in fs::read_dir(&bin_dir)? {
        let entry = entry?;
        let path = entry.path();

        if !path.is_file() {
            continue;
        }

        // Check if executable
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let metadata = fs::metadata(&path)?;
            if metadata.permissions().mode() & 0o111 == 0 {
                continue; // Not executable
            }
        }

        let filename = entry.file_name();
        let filename_str = filename.to_string_lossy();
        let symlink_path = symlink_dir.join(&filename);

        // Check for conflicts
        if symlink_path.exists() {
            if symlink_path.is_symlink() {
                let target = fs::read_link(&symlink_path)?;
                if target == path {
                    debug!(
                        "Symlink {} already exists and is correct. Skipping.",
                        filename_str
                    );
                    skipped_count += 1;
                    continue;
                }
            } else {
                warn!(
                    "Non-symlink file exists at {}. Skipping.",
                    symlink_path.display()
                );
                skipped_count += 1;
                continue;
            }
        }

        if dry_run {
            info!(
                "Dry run: would create symlink {} -> {}",
                symlink_path.display(),
                path.display()
            );
            created_count += 1;
        } else {
            info!(
                "Creating symlink: {} -> {}",
                symlink_path.display(),
                path.display()
            );

            let output = run_sudo_command(
                "ln",
                &[
                    "-sf",
                    path.to_str().unwrap(),
                    symlink_path.to_str().unwrap(),
                ],
                None,
            )
            .await?;

            if output.status.success() {
                created_count += 1;
            } else {
                warn!("Failed to create symlink {}", symlink_path.display());
            }
        }
    }

    info!(
        "Created {} symlinks for GCC {} ({} skipped)",
        created_count, version.full, skipped_count
    );

    Ok(())
}

/// Update the dynamic linker configuration
pub async fn update_ldconfig(
    version: &GccVersion,
    install_dir: &Path,
    dry_run: bool,
) -> Result<()> {
    info!(
        "Updating dynamic linker cache for GCC {} libraries...",
        version.full
    );

    let conf_file = format!("/etc/ld.so.conf.d/custom-gcc-{}.conf", version.full);
    let lib_path = install_dir.join("lib");
    let lib64_path = install_dir.join("lib64");

    if dry_run {
        if lib_path.exists() {
            info!("Dry run: would add {} to {}", lib_path.display(), conf_file);
        }
        if lib64_path.exists() {
            info!(
                "Dry run: would add {} to {}",
                lib64_path.display(),
                conf_file
            );
        }
        info!("Dry run: would run sudo ldconfig");
        return Ok(());
    }

    // Remove old conf file if it exists
    let _ = run_sudo_command("rm", &["-f", &conf_file], None).await;

    let mut paths_added = 0;

    // Add lib path
    if lib_path.exists() {
        let output = Command::new("sudo")
            .args(["tee", "-a", &conf_file])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .spawn()
            .and_then(|mut child| {
                if let Some(ref mut stdin) = child.stdin {
                    use std::io::Write;
                    writeln!(stdin, "{}", lib_path.display())?;
                }
                child.wait()
            });

        if output.is_ok() {
            info!("Added {} to {}", lib_path.display(), conf_file);
            paths_added += 1;
        }
    }

    // Add lib64 path
    if lib64_path.exists() {
        let output = Command::new("sudo")
            .args(["tee", "-a", &conf_file])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .spawn()
            .and_then(|mut child| {
                if let Some(ref mut stdin) = child.stdin {
                    use std::io::Write;
                    writeln!(stdin, "{}", lib64_path.display())?;
                }
                child.wait()
            });

        if output.is_ok() {
            info!("Added {} to {}", lib64_path.display(), conf_file);
            paths_added += 1;
        }
    }

    // Run ldconfig if we added any paths
    if paths_added > 0 {
        info!("Running ldconfig to update linker cache...");
        let output = run_sudo_command("ldconfig", &[], None).await?;

        if output.status.success() {
            info!("ldconfig completed successfully.");
        } else {
            warn!("ldconfig failed. Dynamic linker cache might not be up-to-date.");
        }
    } else {
        info!(
            "No library paths found in {}. ld.so.conf.d file not created.",
            install_dir.display()
        );
    }

    Ok(())
}

/// Run libtool --finish
pub async fn run_libtool_finish(
    version: &GccVersion,
    install_dir: &Path,
    target_arch: &str,
    dry_run: bool,
) -> Result<()> {
    // Find the libexec directory
    let libexec_patterns = [
        install_dir.join(format!("libexec/gcc/{}/{}", target_arch, version.full)),
        install_dir.join(format!("libexec/gcc/{}/{}", target_arch, version.major)),
    ];

    let libexec_dir = libexec_patterns.iter().find(|p| p.exists()).cloned();

    let libexec_dir = match libexec_dir {
        Some(dir) => dir,
        None => {
            warn!("Could not find libexec directory for libtool --finish. Skipping.");
            return Ok(());
        }
    };

    if dry_run {
        info!(
            "Dry run: would run sudo libtool --finish {}",
            libexec_dir.display()
        );
        return Ok(());
    }

    info!("Running libtool --finish in {}", libexec_dir.display());

    let output = run_sudo_command(
        "libtool",
        &["--finish", libexec_dir.to_str().unwrap()],
        None,
    )
    .await?;

    if output.status.success() {
        info!(
            "libtool --finish completed successfully for {}",
            libexec_dir.display()
        );
    } else {
        warn!(
            "libtool --finish failed for {}. This might not be critical.",
            libexec_dir.display()
        );
    }

    Ok(())
}

/// Save static binaries to a specified location
pub async fn save_static_binaries(
    version: &GccVersion,
    install_dir: &Path,
    save_dir: &Path,
    dry_run: bool,
) -> Result<()> {
    info!(
        "Saving static binaries from {} to {}",
        install_dir.display(),
        save_dir.display()
    );

    let bin_dir = install_dir.join("bin");
    if !bin_dir.exists() {
        warn!(
            "Binary directory {} not found. Cannot save static binaries.",
            bin_dir.display()
        );
        return Ok(());
    }

    let programs_to_save = [
        format!("cpp-{}", version.major),
        format!("g++-{}", version.major),
        format!("gcc-{}", version.major),
        format!("gcc-ar-{}", version.major),
        format!("gcc-nm-{}", version.major),
        format!("gcc-ranlib-{}", version.major),
        format!("gcov-{}", version.major),
        format!("gcov-dump-{}", version.major),
        format!("gcov-tool-{}", version.major),
        format!("gfortran-{}", version.major),
    ];

    if dry_run {
        info!(
            "Dry run: would create {} and copy static binaries",
            save_dir.display()
        );
        return Ok(());
    }

    // Create save directory
    fs::create_dir_all(save_dir).context("Failed to create save directory")?;

    let mut copied = 0;
    for program in &programs_to_save {
        let source = bin_dir.join(program);
        if source.exists() {
            let dest = save_dir.join(program);
            let output = run_sudo_command(
                "cp",
                &["-f", source.to_str().unwrap(), dest.to_str().unwrap()],
                None,
            )
            .await?;

            if output.status.success() {
                info!("Copied {} to {}", program, save_dir.display());
                copied += 1;
            } else {
                warn!("Failed to copy {}", program);
            }
        } else {
            debug!("Static binary not found: {}", source.display());
        }
    }

    info!("Saved {} static binaries to {}", copied, save_dir.display());

    Ok(())
}

/// Run all post-installation tasks
pub async fn run_post_install(
    version: &GccVersion,
    install_dir: &Path,
    target_arch: &str,
    static_build: bool,
    save_binaries: bool,
    dry_run: bool,
) -> Result<()> {
    info!(
        "Performing post-build tasks for GCC {} at {}",
        version.full,
        install_dir.display()
    );

    // Run libtool --finish
    run_libtool_finish(version, install_dir, target_arch, dry_run).await?;

    // Update ldconfig
    update_ldconfig(version, install_dir, dry_run).await?;

    // Create symlinks
    create_symlinks(version, install_dir, dry_run).await?;

    // Trim binary names
    trim_binaries(version, install_dir, target_arch, dry_run).await?;

    // Save static binaries if requested
    if static_build && save_binaries {
        let save_dir = PathBuf::from(format!("gcc-{}-static-binaries", version.full));
        save_static_binaries(version, install_dir, &save_dir, dry_run).await?;
    }

    Ok(())
}
