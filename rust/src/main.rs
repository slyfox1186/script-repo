mod build;
mod cli;
mod config;
mod dependencies;
mod download;
mod environment;
mod error;
mod logging;
mod post_install;
mod progress;
mod system;
mod version;

use crate::build::{build_gcc_version, GccBuildResult};
use crate::cli::Args;
use crate::config::{BuildConfig, GccVersion, SCRIPT_VERSION};
use crate::dependencies::{check_autoconf, check_build_tools, install_dependencies};
use crate::environment::setup_environment;
use crate::error::BuildStatus;
use crate::logging::{init_logging, print_header};
use crate::progress::BuildSummary;
use crate::system::{
    check_not_root, check_system_resources, create_secure_temp_dir, get_target_arch, LockFile,
};
use crate::version::{parse_version_spec, resolve_versions, select_versions_interactive};
use anyhow::Result;
use clap::Parser;
use console::style;
use futures::future::join_all;
use std::sync::Arc;
use std::time::Instant;
use tokio::signal;
use tokio::sync::Mutex;
use tracing::{error, info, warn};

#[tokio::main]
async fn main() -> Result<()> {
    // Parse command line arguments
    let args = Args::parse();

    // Validate arguments
    args.validate()?;

    // Initialize logging
    init_logging(args.verbose, args.debug, args.log_file.as_deref())?;

    info!("Starting GCC Build Script v{}", SCRIPT_VERSION);
    info!("Rust version - async downloads and parallel builds enabled");

    // Log configuration
    log_configuration(&args);

    // Check we're not running as root
    check_not_root()?;

    // Acquire exclusive lock
    let _lock = LockFile::acquire()?;
    info!("Lock acquired - no other instance is running");

    // Create secure temporary build directory
    let temp_dir = create_secure_temp_dir()?;
    let build_dir = temp_dir.path().to_path_buf();
    info!("Secure build directory created: {}", build_dir.display());

    // Get target architecture
    let target_arch = get_target_arch();
    info!("Target architecture: {}", target_arch);

    // Create build configuration
    let config = BuildConfig::from_args(&args, build_dir.clone(), target_arch.clone());

    // Create workspace directory
    std::fs::create_dir_all(&config.workspace)?;

    // Setup environment
    setup_environment(&config);

    // Install dependencies
    install_dependencies(config.enable_multilib, config.dry_run, &config.target_arch).await?;
    check_autoconf()?;
    check_build_tools()?;

    // Select GCC versions
    let major_versions = if let Some(ref spec) = args.versions {
        parse_version_spec(spec)?
    } else {
        select_versions_interactive()?
    };

    info!("Selected GCC major versions: {:?}", major_versions);

    // Check system resources
    check_system_resources(&build_dir, major_versions.len())?;

    // Resolve to full versions
    let versions = resolve_versions(&major_versions, &build_dir).await?;
    info!(
        "Will build: {}",
        versions
            .iter()
            .map(|v| v.full.as_str())
            .collect::<Vec<_>>()
            .join(", ")
    );

    // Setup signal handler for graceful shutdown
    let shutdown = setup_shutdown_handler();

    // Start build process
    let overall_start = Instant::now();
    let summary = Arc::new(Mutex::new(BuildSummary::new()));

    print_header("GCC BUILD PROCESS");

    // Build versions (parallel or sequential based on --parallel flag)
    let results = if config.parallel > 1 && versions.len() > 1 {
        info!(
            "Building {} versions with parallelism of {}",
            versions.len(),
            config.parallel
        );
        build_parallel(&config, &versions, config.parallel, shutdown.clone()).await
    } else {
        info!("Building {} versions sequentially", versions.len());
        build_sequential(&config, &versions, shutdown.clone()).await
    };

    // Process results
    {
        let mut summary = summary.lock().await;
        for result in results {
            match result {
                Ok(build_result) => match build_result.status {
                    BuildStatus::Success => {
                        summary.add_success(build_result.version.full);
                    }
                    BuildStatus::DryRun => {
                        summary.add_skipped(build_result.version.full, "Dry run".to_string());
                    }
                    BuildStatus::Failed(msg) => {
                        summary.add_failure(build_result.version.full, msg);
                    }
                    _ => {}
                },
                Err(e) => {
                    error!("Build failed: {}", e);
                    summary.add_failure("unknown".to_string(), e.to_string());
                }
            }
        }
        summary.total_duration_secs = overall_start.elapsed().as_secs();
    }

    // Cleanup
    if !config.keep_build_dir {
        info!("Cleaning up temporary build directory...");
        // temp_dir will be automatically cleaned up when dropped
    } else {
        info!("Keeping build directory at: {}", build_dir.display());
        // Prevent temp_dir from being dropped
        std::mem::forget(temp_dir);
    }

    // Print summary
    let summary = summary.lock().await;
    summary.print_summary();

    // Print usage instructions for successful builds
    if !summary.successful.is_empty() {
        print_header("NEXT STEPS");
        println!();
        println!(
            "{} Successfully built GCC versions are ready for use!",
            style("").green()
        );
        println!();
        println!("To use your new GCC installations:");
        for version in &summary.successful {
            let install_path = format!("/usr/local/programs/gcc-{}", version);
            println!(
                "  {} GCC {}: {}",
                style("•").cyan(),
                version,
                style(format!("export PATH=\"{}/bin:$PATH\"", install_path)).yellow()
            );
        }
        println!();
        println!(
            "{} Consider adding your preferred version to ~/.bashrc or ~/.profile",
            style("").cyan()
        );
        println!();
    }

    info!("GCC Build Script finished");

    Ok(())
}

/// Log the configuration
fn log_configuration(args: &Args) {
    info!("Configuration:");
    info!("  Dry run: {}", args.dry_run);
    info!("  Debug: {}", args.debug);
    info!("  Verbose: {}", args.verbose);
    info!("  Keep build dir: {}", args.keep_build_dir);
    info!("  Optimization: -O{}", args.optimization);
    info!("  Static build: {}", args.static_build);
    info!("  Save binaries: {}", args.save);
    info!("  Enable multilib: {}", args.enable_multilib);
    info!("  Generic build: {}", args.generic);
    info!("  Parallel builds: {}", args.parallel);
    if let Some(ref prefix) = args.prefix {
        info!("  Custom prefix: {}", prefix.display());
    }
    if let Some(ref log_file) = args.log_file {
        info!("  Log file: {}", log_file.display());
    }
}

/// Build versions sequentially
async fn build_sequential(
    config: &BuildConfig,
    versions: &[GccVersion],
    shutdown: Arc<Mutex<bool>>,
) -> Vec<Result<GccBuildResult>> {
    let mut results = Vec::new();

    for version in versions {
        // Check for shutdown signal
        if *shutdown.lock().await {
            warn!("Shutdown signal received. Stopping builds.");
            break;
        }

        info!("--- Building GCC {} ---", version.full);
        let result = build_gcc_version(config, version).await;
        results.push(result);
    }

    results
}

/// Build versions in parallel
async fn build_parallel(
    config: &BuildConfig,
    versions: &[GccVersion],
    parallelism: usize,
    shutdown: Arc<Mutex<bool>>,
) -> Vec<Result<GccBuildResult>> {
    let mut results = Vec::new();

    // Process versions in chunks based on parallelism
    for chunk in versions.chunks(parallelism) {
        // Check for shutdown signal
        if *shutdown.lock().await {
            warn!("Shutdown signal received. Stopping builds.");
            break;
        }

        info!(
            "Building {} version(s) in parallel: {}",
            chunk.len(),
            chunk
                .iter()
                .map(|v| v.full.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        );

        // Create futures for each version in the chunk
        let futures: Vec<_> = chunk
            .iter()
            .map(|version| {
                // Clone config for each future
                let config = config.clone();
                let version = version.clone();
                async move { build_gcc_version(&config, &version).await }
            })
            .collect();

        // Wait for all in this chunk to complete
        let chunk_results = join_all(futures).await;
        results.extend(chunk_results);
    }

    results
}

/// Setup shutdown signal handler
fn setup_shutdown_handler() -> Arc<Mutex<bool>> {
    let shutdown = Arc::new(Mutex::new(false));
    let shutdown_clone = Arc::clone(&shutdown);

    tokio::spawn(async move {
        let ctrl_c = signal::ctrl_c();

        #[cfg(unix)]
        let mut sigterm = signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("Failed to create SIGTERM handler");

        #[cfg(unix)]
        tokio::select! {
            _ = ctrl_c => {
                warn!("Received SIGINT (Ctrl+C). Initiating graceful shutdown...");
            }
            _ = sigterm.recv() => {
                warn!("Received SIGTERM. Initiating graceful shutdown...");
            }
        }

        #[cfg(not(unix))]
        {
            ctrl_c.await.expect("Failed to wait for Ctrl+C");
            warn!("Received Ctrl+C. Initiating graceful shutdown...");
        }

        *shutdown_clone.lock().await = true;
    });

    shutdown
}
