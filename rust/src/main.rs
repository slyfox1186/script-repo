use anyhow::Result;
use clap::Parser;
use log::{debug, error, info, warn};
use std::process;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::signal;

mod cli;
mod config;
mod error;
mod logging;
mod commands;
mod files;
mod directories;
mod system;
mod packages;
mod gcc_config;
mod build;
mod progress;
mod scheduler;
mod cache;
mod build_state;
mod retry;
mod suggestions;
mod symlink_optimizer;
mod binary_verifier;
mod prerequisite_cache;
mod dependency_installer;
mod build_cache;
mod mirror_manager;
mod memory_profiler;
mod memory_monitor;
mod auto_tuner;
mod build_verifier;
mod artifact_cache;

use cli::Args;
use config::Config;
use error::GccBuildError;

#[tokio::main]
async fn main() -> Result<()> {
    let mut args = Args::parse();
    
    // Apply preset configurations if specified
    args.apply_preset();
    
    // Initialize logging
    logging::init_logger(&args)?;
    
    println!("\n╔═══════════════════════════════════════════════════════════════╗");
    println!("║         🚀 GCC Builder v{} - ULTRAFAST Rust Edition         ║", env!("CARGO_PKG_VERSION"));
    println!("╚═══════════════════════════════════════════════════════════════╝");
    println!();
    info!("💡 Press Ctrl+C at any time to gracefully stop the build");
    println!();
    
    // Set up graceful shutdown signal handling
    let shutdown_flag = Arc::new(AtomicBool::new(false));
    let shutdown_flag_clone = Arc::clone(&shutdown_flag);
    
    tokio::spawn(async move {
        match signal::ctrl_c().await {
            Ok(()) => {
                warn!("🛑 Received Ctrl+C, initiating graceful shutdown...");
                shutdown_flag_clone.store(true, Ordering::Relaxed);
            }
            Err(err) => {
                error!("Failed to listen for shutdown signal: {}", err);
            }
        }
    });
    
    // Initialize configuration with compile-time validation
    let config = Config::new(args)?;
    
    // Display build plan
    println!("📋 Build Plan:");
    println!("─────────────────────────────────────────────────────────────────");
    for version in &config.gcc_versions {
        println!("   • GCC {} (will resolve to latest patch version)", version.major);
    }
    println!("   • Installation prefix: {}", config.install_prefix.as_ref().map(|p| p.display().to_string()).unwrap_or_else(|| "/usr/local/programs".to_string()));
    println!("   • Build directory: {}", config.build_dir.display());
    println!("   • Parallel jobs: {}", config.parallel_jobs);
    if config.dry_run {
        println!("   • Mode: DRY RUN (no actual changes)");
    }
    println!("─────────────────────────────────────────────────────────────────");
    println!();
    
    // EFFICIENCY: Validate EVERYTHING upfront before any long operations
    system::validate_requirements(&config).await?;
    
    // EFFICIENCY: Install dependencies once, parallel-ready
    packages::install_dependencies(&config).await?;
    
    // EFFICIENCY: Build multiple GCC versions in PARALLEL
    match run_parallel_builds(config, shutdown_flag).await {
        Ok(_) => {
            println!("\n╔═══════════════════════════════════════════════════════════════╗");
            println!("║              ✅ ALL GCC BUILDS COMPLETED SUCCESSFULLY!         ║");
            println!("╚═══════════════════════════════════════════════════════════════╝");
            Ok(())
        }
        Err(e) => {
            error!("❌ Build failed: {}", e);
            
            // Display helpful suggestions
            suggestions::display_suggestions(&e);
            
            process::exit(1);
        }
    }
}

async fn run_parallel_builds(config: Config, shutdown_flag: Arc<AtomicBool>) -> Result<(), GccBuildError> {
    let build_env = build::BuildEnvironment::new(&config).await?;
    
    // Initialize scheduler for resource-aware builds
    let scheduler = scheduler::BuildScheduler::new(&config);
    
    if config.gcc_versions.len() == 1 {
        // Single version - no need for parallelization overhead
        if shutdown_flag.load(Ordering::Relaxed) {
            warn!("🛑 Build cancelled by user");
            return Ok(());
        }
        
        // Still use scheduler for resource management
        let slot = scheduler.acquire_build_slot(&config.gcc_versions[0]).await?;
        let result = build::build_gcc_version(&build_env, &config.gcc_versions[0]).await;
        slot.complete(result.is_ok(), None);
        result?;
    } else {
        // EFFICIENCY: Parallel builds with smart resource allocation
        info!("🔥 Building {} GCC versions with resource-aware scheduling", 
              config.gcc_versions.len());
        
        // Create futures for all builds
        let mut handles = Vec::new();
        
        for version in config.gcc_versions.clone() {
            let build_env_clone = build_env.clone();
            let scheduler_clone = scheduler.clone();
            let shutdown_flag_clone = shutdown_flag.clone();
            
            let handle = tokio::spawn(async move {
                if shutdown_flag_clone.load(Ordering::Relaxed) {
                    return Ok(());
                }
                
                // Acquire build slot (will wait if resources unavailable)
                let slot = scheduler_clone.acquire_build_slot(&version).await?;
                
                // Execute build with retry logic
                let retry_executor = retry::PhaseRetryExecutor::new();
                let result = retry_executor.retry_build(
                    "complete build",
                    &version,
                    Some(&scheduler_clone),
                    || build::build_gcc_version(&build_env_clone, &version)
                ).await;
                
                // Release slot
                slot.complete(result.is_ok(), None);
                result
            });
            
            handles.push(handle);
        }
        
        // Wait for all builds to complete
        for (i, handle) in handles.into_iter().enumerate() {
            match handle.await {
                Ok(Ok(())) => {
                    debug!("Build task {} completed successfully", i);
                }
                Ok(Err(e)) => {
                    error!("Build task {} failed: {}", i, e);
                    return Err(e);
                }
                Err(e) => {
                    error!("Build task {} panicked: {}", i, e);
                    return Err(GccBuildError::configuration(format!("Build task panicked: {}", e)));
                }
            }
        }
        
        // Display scheduler statistics
        let stats = scheduler.get_statistics();
        info!("📊 Build Statistics:");
        info!("  • Total builds: {}", stats.total_builds);
        info!("  • Completed: {}", stats.completed_builds);
        info!("  • Failed: {}", stats.failed_builds);
        if let Some(avg_time) = stats.average_build_time {
            info!("  • Average build time: {:?}", avg_time);
        }
    }
    
    // Cleanup if requested
    if !config.keep_build_dir {
        build_env.cleanup().await?;
    }
    
    Ok(())
}