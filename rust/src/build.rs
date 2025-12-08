use crate::config::{BuildConfig, GccVersion, DEFAULT_PREFIX_BASE};
use crate::download::{download_gcc_source, extract_tarball};
use crate::environment::get_build_env;
use crate::error::{BuildError, BuildStatus};
use crate::logging::print_status;
use crate::post_install::run_post_install;
use crate::system::{check_cuda, get_make_threads, run_sudo_command};
use anyhow::{Context, Result};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;
use tracing::{debug, info, warn};

/// Result of building a single GCC version
#[derive(Debug)]
pub struct GccBuildResult {
    pub version: GccVersion,
    pub status: BuildStatus,
}

/// Build a single GCC version
pub async fn build_gcc_version(
    config: &BuildConfig,
    version: &GccVersion,
) -> Result<GccBuildResult> {
    let _start_time = Instant::now();
    let install_dir = version.install_prefix(config.prefix.as_ref());

    print_status("GCC", &version.full, "BUILD_PROCESS_START");
    info!(
        "Installation prefix for GCC {} will be: {}",
        version.full,
        install_dir.display()
    );

    // Create installation directory
    if !config.dry_run {
        create_install_directory(&install_dir).await?;
    }

    // Stage 1: Download
    print_status("GCC", &version.full, "DOWNLOAD_START");
    let tarball = download_gcc_source(version, &config.build_dir, config.dry_run).await?;
    print_status("GCC", &version.full, "DOWNLOAD_SUCCESS");

    if config.dry_run {
        info!(
            "Dry run: Would proceed to extract, configure, build, and install GCC {}",
            version.full
        );
        print_status("GCC", &version.full, "DRY_RUN_COMPLETE");

        return Ok(GccBuildResult {
            version: version.clone(),
            status: BuildStatus::DryRun,
        });
    }

    // Stage 2: Extract
    print_status("GCC", &version.full, "EXTRACT_START");
    let source_dir = extract_tarball(&tarball, &config.workspace, config.dry_run).await?;
    print_status("GCC", &version.full, "EXTRACT_SUCCESS");

    // Stage 3: Download prerequisites
    print_status("GCC", &version.full, "PREREQUISITES_START");
    download_prerequisites(&source_dir).await?;
    print_status("GCC", &version.full, "PREREQUISITES_SUCCESS");

    // Stage 4: Configure
    print_status("GCC", &version.full, "CONFIGURE_START");
    let build_dir = configure_gcc(config, version, &source_dir, &install_dir).await?;
    print_status("GCC", &version.full, "CONFIGURE_SUCCESS");

    // Stage 5: Build
    print_status("GCC", &version.full, "MAKE_START");
    let make_duration = make_gcc(&build_dir).await?;
    info!(
        "GCC {} build completed in {}",
        version.full,
        format_duration(make_duration)
    );
    print_status("GCC", &version.full, "MAKE_SUCCESS");

    // Stage 6: Install
    print_status("GCC", &version.full, "INSTALL_START");
    install_gcc(&build_dir).await?;
    print_status("GCC", &version.full, "INSTALL_SUCCESS");

    // Stage 7: Post-install
    print_status("GCC", &version.full, "POST_BUILD_TASKS_START");
    run_post_install(
        version,
        &install_dir,
        &config.target_arch,
        config.static_build,
        config.save_binaries,
        config.dry_run,
    )
    .await?;
    print_status("GCC", &version.full, "POST_BUILD_TASKS_SUCCESS");

    info!("Successfully built and installed GCC {}", version.full);
    print_status("GCC", &version.full, "BUILD_PROCESS_SUCCESS");

    Ok(GccBuildResult {
        version: version.clone(),
        status: BuildStatus::Success,
    })
}

/// Create the installation directory
async fn create_install_directory(install_dir: &Path) -> Result<()> {
    // Create base programs directory if using default
    let base = PathBuf::from(DEFAULT_PREFIX_BASE);
    if install_dir.starts_with(&base) && !base.exists() {
        info!("Creating default programs directory {}", base.display());
        run_sudo_command("mkdir", &["-p", base.to_str().unwrap()], None).await?;

        // Change ownership to current user
        let user = std::env::var("USER").unwrap_or_else(|_| "root".to_string());
        let group = crate::system::get_groupname();
        run_sudo_command(
            "chown",
            &[&format!("{}:{}", user, group), base.to_str().unwrap()],
            None,
        )
        .await?;
    }

    // Create version-specific directory
    if !install_dir.exists() {
        run_sudo_command("mkdir", &["-p", install_dir.to_str().unwrap()], None).await?;

        // Change ownership
        let user = std::env::var("USER").unwrap_or_else(|_| "root".to_string());
        let group = crate::system::get_groupname();
        run_sudo_command(
            "chown",
            &[
                &format!("{}:{}", user, group),
                install_dir.to_str().unwrap(),
            ],
            None,
        )
        .await?;
    }

    Ok(())
}

/// Download GCC prerequisites
async fn download_prerequisites(source_dir: &Path) -> Result<()> {
    let script = source_dir.join("contrib/download_prerequisites");

    if !script.exists() {
        warn!(
            "download_prerequisites script not found. Assuming prerequisites will be met by system libraries."
        );
        return Ok(());
    }

    info!("Downloading GCC prerequisites...");

    let output = tokio::process::Command::new(&script)
        .current_dir(source_dir)
        .output()
        .await
        .context("Failed to run download_prerequisites")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        warn!(
            "download_prerequisites failed: {}. Build might still succeed.",
            stderr
        );
    } else {
        info!("Successfully downloaded prerequisites.");
    }

    Ok(())
}

/// Configure GCC build
async fn configure_gcc(
    config: &BuildConfig,
    version: &GccVersion,
    source_dir: &Path,
    install_dir: &Path,
) -> Result<PathBuf> {
    info!("Configuring GCC {}...", version.full);

    // Create build directory (out-of-source build)
    let build_dir = source_dir.join("build-gcc");
    if build_dir.exists() {
        fs::remove_dir_all(&build_dir)?;
    }
    fs::create_dir_all(&build_dir)?;

    // Build configure options
    let mut options = vec![
        format!("--prefix={}", install_dir.display()),
        format!("--build={}", config.target_arch),
        format!("--host={}", config.target_arch),
        format!("--target={}", config.target_arch),
        "--enable-languages=all".to_string(),
        "--disable-bootstrap".to_string(),
        "--enable-checking=release".to_string(),
        "--disable-nls".to_string(),
        "--enable-shared".to_string(),
        "--enable-threads=posix".to_string(),
        "--with-system-zlib".to_string(),
    ];

    // Multilib option
    if config.enable_multilib {
        options.push("--enable-multilib".to_string());
        info!("Multilib support is explicitly enabled.");
    } else {
        options.push("--disable-multilib".to_string());
        info!("Multilib support is explicitly disabled.");
    }

    // Tuning
    if config.generic {
        options.push("--with-tune=generic".to_string());
    }

    // CUDA support
    if let Some(cuda_option) = check_cuda() {
        options.push(cuda_option);
    }

    // Program suffix for versioned binaries
    options.push(format!("--program-suffix=-{}", version.major));
    options.push("--with-gcc-major-version-only".to_string());

    // Version-specific options
    add_version_specific_options(&mut options, version.major);

    // Log configure command
    info!("Running configure with options:");
    for opt in &options {
        debug!("  {}", opt);
    }

    // Run configure with real-time output
    let configure_script = source_dir.join("configure");
    let mut cmd = tokio::process::Command::new(&configure_script);
    cmd.current_dir(&build_dir);

    // Add options as arguments
    for opt in &options {
        cmd.arg(opt);
    }

    // Set environment
    let env = get_build_env(config);
    for (key, value) in &env {
        cmd.env(key, value);
    }

    // Show output in real-time
    cmd.stdout(std::process::Stdio::inherit());
    cmd.stderr(std::process::Stdio::inherit());

    let status = cmd.status().await.context("Failed to run configure")?;

    if !status.success() {
        let config_log = build_dir.join("config.log");

        return Err(BuildError::Configure {
            version: version.full.clone(),
            message: format!(
                "Configure failed. Check {} for details (see output above)",
                config_log.display()
            ),
        }
        .into());
    }

    info!("GCC {} configuration completed successfully.", version.full);
    Ok(build_dir)
}

/// Add version-specific configure options
fn add_version_specific_options(options: &mut Vec<String>, major: u32) {
    match major {
        10 | 11 => {
            options.push("--enable-default-pie".to_string());
            options.push("--enable-gnu-unique-object".to_string());
        }
        12 => {
            options.push("--enable-default-pie".to_string());
            options.push("--enable-gnu-unique-object".to_string());
            options.push("--with-link-serialization=2".to_string());
        }
        13..=15 => {
            options.push("--enable-default-pie".to_string());
            options.push("--enable-gnu-unique-object".to_string());
            options.push("--with-link-serialization=2".to_string());
            options.push("--enable-cet".to_string());
        }
        _ => {
            warn!(
                "No version-specific configure options defined for GCC {}. Using common options.",
                major
            );
        }
    }
}

/// Build GCC using make with real-time output
async fn make_gcc(build_dir: &Path) -> Result<u64> {
    let threads = get_make_threads();
    info!("Building GCC (make -j{})...", threads);
    info!("This will take a significant amount of time...");
    info!("Build output will be shown in real-time below:");
    info!("{}", "─".repeat(60));

    let start = Instant::now();

    // Try parallel make first - use spawn() for real-time output
    let status = tokio::process::Command::new("make")
        .arg(format!("-j{}", threads))
        .current_dir(build_dir)
        .stdout(std::process::Stdio::inherit())
        .stderr(std::process::Stdio::inherit())
        .status()
        .await
        .context("Failed to run make")?;

    if !status.success() {
        warn!("Parallel make failed. Trying single-threaded build...");

        let status = tokio::process::Command::new("make")
            .current_dir(build_dir)
            .stdout(std::process::Stdio::inherit())
            .stderr(std::process::Stdio::inherit())
            .status()
            .await
            .context("Failed to run make (single-threaded)")?;

        if !status.success() {
            return Err(BuildError::Make {
                version: "unknown".to_string(),
                message: "Make failed - see output above".to_string(),
            }
            .into());
        }
    }

    info!("{}", "─".repeat(60));
    Ok(start.elapsed().as_secs())
}

/// Install GCC using sudo make install-strip
async fn install_gcc(build_dir: &Path) -> Result<()> {
    info!("Installing GCC (sudo make install-strip)...");

    let output = run_sudo_command("make", &["install-strip"], Some(build_dir)).await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(BuildError::Install {
            version: "unknown".to_string(),
            message: stderr.to_string(),
        }
        .into());
    }

    info!("GCC installation completed successfully.");
    Ok(())
}

/// Format duration as HH:MM:SS
fn format_duration(secs: u64) -> String {
    let hours = secs / 3600;
    let minutes = (secs % 3600) / 60;
    let seconds = secs % 60;
    format!("{:02}:{:02}:{:02}", hours, minutes, seconds)
}
