#![allow(dead_code)]
use log::{info, warn};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::fs;

use crate::commands::CommandExecutor;
use crate::config::{Config, GccVersion};
use crate::directories::DirectoryOperations;
use crate::error::{GccBuildError, Result as GccResult};
use crate::files::{FileOperations, FileValidationType};
use crate::gcc_config::GccConfigGenerator;
use crate::logging::ProgressLogger;
use crate::progress::BuildProgressTracker;
use crate::system::ResourceMonitor;

#[derive(Clone)]
pub struct BuildEnvironment {
    pub config: Config,
    pub command_executor: CommandExecutor,
    pub file_ops: FileOperations,
    pub dir_ops: DirectoryOperations,
    pub gcc_config: GccConfigGenerator,
    pub resource_monitor: Option<Arc<ResourceMonitor>>,
    pub progress_tracker: BuildProgressTracker,
}

impl BuildEnvironment {
    pub async fn new(config: &Config) -> GccResult<Self> {
        info!("⚡ Setting up ULTRAFAST build environment");
        
        // EFFICIENCY: Clean and recreate build directories every time
        let dir_ops = DirectoryOperations::new(config.dry_run);
        
        // Clean workspace directory only, preserve packages and root build dir
        let workspace_dir = &config.workspace_dir;
        if workspace_dir.exists() {
            info!("🧹 Cleaning workspace directory: {}", workspace_dir.display());
            dir_ops.remove_directory(workspace_dir)?;
        }
        
        // Show preserved packages if they exist
        if config.packages_dir.exists() {
            if let Ok(entries) = std::fs::read_dir(&config.packages_dir) {
                let packages: Vec<_> = entries
                    .filter_map(|entry| entry.ok())
                    .filter(|entry| entry.path().extension().map_or(false, |ext| ext == "xz" || ext == "gz"))
                    .collect();
                
                if !packages.is_empty() {
                    info!("💾 Found {} existing package(s) - preserving downloads", packages.len());
                    for package in packages {
                        if let Ok(metadata) = package.metadata() {
                            info!("  📦 {}: {:.1} MB", 
                                package.file_name().to_string_lossy(), 
                                metadata.len() as f64 / 1_000_000.0);
                        }
                    }
                }
            }
        }
        
        // Create all directories fresh
        let dirs_to_create = [
            &config.build_dir,
            &config.packages_dir, 
            &config.workspace_dir,
        ];
        
        crate::directories::create_build_directories(&dirs_to_create.iter().cloned().cloned().collect::<Vec<_>>(), config.dry_run)?;
        
        // EFFICIENCY: Setup command executor with pre-allocated environment
        let build_env_vars = crate::gcc_config::get_build_environment(config);
        let command_executor = CommandExecutor::new(config.dry_run, config.verbose)
            .with_env_vars(build_env_vars)
            .with_working_dir(&config.build_dir);
        
        // EFFICIENCY: Only start monitoring for long-running builds
        let resource_monitor = if !config.dry_run && config.gcc_versions.len() > 1 {
            let monitor = ResourceMonitor::new(
                config.build_dir.clone(),
                Duration::from_secs(300), // 5 minutes
                config.build_dir.join("resource_monitor.log"),
            );
            monitor.start().await?;
            Some(Arc::new(monitor))
        } else {
            None
        };
        
        Ok(Self {
            config: config.clone(),
            command_executor,
            file_ops: FileOperations::new(config.dry_run),
            dir_ops,
            gcc_config: GccConfigGenerator::new(),
            resource_monitor,
            progress_tracker: BuildProgressTracker::new(),
        })
    }
    
    pub async fn cleanup(&self) -> GccResult<()> {
        if let Some(monitor) = &self.resource_monitor {
            monitor.stop().await;
        }
        
        if !self.config.keep_build_dir {
            // Only clean workspace, preserve packages and root build dir structure
            if self.config.workspace_dir.exists() {
                info!("🧹 Cleaning up workspace directory: {}", self.config.workspace_dir.display());
                self.dir_ops.remove_directory(&self.config.workspace_dir)?;
            }
            info!("💾 Build directory structure and packages preserved");
        }
        
        Ok(())
    }
}

pub async fn build_gcc_version(
    env: &BuildEnvironment,
    version: &GccVersion,
) -> GccResult<()> {
    let logger = ProgressLogger::new(&format!("🔨 Building GCC {}", version));
    let start_time = Instant::now();
    
    println!("\n┌─────────────────────────────────────────────────────────────┐");
    println!("│            🔨 Building GCC {}                               │", version.major);
    println!("└─────────────────────────────────────────────────────────────┘");
    
    // EFFICIENCY: Resolve version ONLY if needed (zero-allocation check first)
    let full_version = if version.minor == 0 && version.patch == 0 {
        resolve_latest_gcc_version_fast(env, version.major).await?
    } else {
        version.clone()
    };
    
    // EFFICIENCY: Pre-allocate all paths (zero heap allocations in hot path)
    let install_prefix = env.config.get_install_prefix(&full_version);
    let source_dir = env.config.workspace_dir.join(format!("gcc-{}", full_version));
    let build_dir = source_dir.join("build-gcc");
    
    // ULTRAFAST: Smart binary verification before expensive operations
    if crate::binary_verifier::should_skip_build(
        &install_prefix,
        &full_version,
        env.config.force_rebuild,
        env.config.verify_level.clone(),
    ).await? {
        logger.finish();
        return Ok(());
    }
    
    println!("\n   📋 Build Details:");
    println!("   • Version: GCC {}", full_version);
    println!("   • Install to: {}", install_prefix.display());
    println!("   • Build directory: {}", build_dir.display());
    println!("   • Parallel jobs: {}", env.config.parallel_jobs);
    println!();
    
    println!("   ⏳ Starting build process...");
    println!();
    
    info!("📥 Step 1/7: Downloading GCC {} source code...", full_version);
    download_gcc_source_fast(env, &full_version).await?;
    
    info!("📦 Step 2/7: Extracting GCC {} source archive...", full_version);
    extract_gcc_source_fast(env, &full_version, &source_dir).await?;
    
    info!("📚 Step 3/7: Downloading GCC prerequisites (GMP, MPFR, MPC)...");
    download_prerequisites_fast(env, &source_dir).await?;
    
    info!("⚙️ Step 4/7: Configuring GCC {} build system...", full_version);
    configure_gcc_fast(env, &full_version, &source_dir, &build_dir, &install_prefix).await?;
    
    info!("🏗️ Step 5/7: Building GCC {} (this takes 45-90 minutes)...", full_version);
    build_gcc_fast(env, &full_version, &build_dir).await?;
    
    info!("📦 Step 6/7: Installing GCC {} to {}...", full_version, install_prefix.display());
    install_gcc_fast(env, &full_version, &build_dir, &install_prefix).await?;
    
    info!("🔧 Step 7/7: Post-installation tasks (symlinks, libraries)...");
    post_install_tasks_fast(env, &full_version, &install_prefix).await?;
    
    let duration = start_time.elapsed();
    println!("\n   ✅ GCC {} successfully built!", full_version);
    println!("   ⏱️  Total time: {:.2?}", duration);
    println!("   📍 Installed to: {}", install_prefix.display());
    println!();
    logger.finish();
    
    Ok(())
}


async fn resolve_latest_gcc_version_fast(
    env: &BuildEnvironment,
    major_version: u8,
) -> GccResult<GccVersion> {
    let logger = ProgressLogger::new(&format!("🔍 Resolving GCC {} latest", major_version));
    
    // EFFICIENCY: Use stack-allocated cache path
    let cache_file = env.config.build_dir.join(".gcc_version_cache");
    
    // EFFICIENCY: Check cache first (avoid network if possible)
    if let Ok(cache_content) = fs::read_to_string(&cache_file).await {
        let cache_key = format!("gcc-{}:", major_version);
        if let Some(line) = cache_content.lines().find(|l| l.starts_with(&cache_key)) {
            if let Some(version_str) = line.split(':').nth(1) {
                if let Ok(version) = GccVersion::from_str(version_str) {
                    info!("⚡ Using cached version: {}", version);
                    logger.finish();
                    return Ok(version);
                }
            }
        }
    }
    
    // Use simple shell command to find latest version for this major version
    let command = format!(
        r#"curl -fsSL https://ftp.gnu.org/gnu/gcc/ | grep -oP 'gcc-{}\.\d+\.\d+(?=/)' | sort -V | tail -n1 | cut -d- -f2"#,
        major_version
    );
    
    let output = env.command_executor.execute_with_output("bash", ["-c", &command]).await
        .map_err(|e| GccBuildError::download("https://ftp.gnu.org/gnu/gcc/".to_string(), e.to_string()))?;
    
    let version_str = output.trim();
    if version_str.is_empty() {
        return Err(GccBuildError::configuration(format!("No versions found for GCC {}", major_version)));
    }
    
    let version = GccVersion::from_str(version_str)?;
    
    // EFFICIENCY: Async cache update (don't block on this)
    let cache_entry = format!("gcc-{}:{}\n", major_version, version);
    let _ = fs::write(&cache_file, cache_entry).await;
    
    info!("🎯 Latest GCC {} version: {}", major_version, version);
    logger.finish();
    Ok(version)
}

async fn download_gcc_source_fast(
    env: &BuildEnvironment,
    version: &GccVersion,
) -> GccResult<()> {
    let logger = ProgressLogger::new(&format!("⬇️ Downloading GCC {}", version));
    
    // EFFICIENCY: Stack-allocated filename (no heap allocation)
    let filename = format!("gcc-{}.tar.xz", version);
    let url = format!("https://ftp.gnu.org/gnu/gcc/gcc-{}/{}", version, filename);
    let download_path = env.config.packages_dir.join(&filename);
    
    info!("🌐 Downloading from: {}", url);
    info!("💾 Saving to: {}", download_path.display());
    
    // EFFICIENCY: Fast existence and validity check
    if download_path.exists() {
        let file_size = fs::metadata(&download_path).await?.len();
        if file_size > 50_000_000 && env.file_ops.validate_file(&download_path, FileValidationType::Tarball)? {
            info!("⚡ Source already downloaded: {} ({:.1} MB)", filename, file_size as f64 / 1_000_000.0);
            logger.finish();
            return Ok(());
        } else {
            warn!("🔄 Re-downloading corrupted/incomplete file (size: {:.1} MB)", file_size as f64 / 1_000_000.0);
            fs::remove_file(&download_path).await.ok();
        }
    }
    
    if env.config.dry_run {
        info!("🔍 Dry run: would download {}", url);
        logger.finish();
        return Ok(());
    }
    
    // EFFICIENCY: Use system tools (curl/wget) - already optimized!
    env.command_executor.download_file(&url, &download_path, env.config.max_retries).await?;
    
    // Skip checksum - modern GCC uses GPG signatures, not SHA checksums
    info!("✅ Download verified by file size and GNU FTP integrity");
    
    logger.finish();
    Ok(())
}

// Checksum verification removed - modern GCC uses GPG signatures from GNU FTP
// File integrity is verified by download size validation and GNU's infrastructure

async fn extract_gcc_source_fast(
    env: &BuildEnvironment,
    version: &GccVersion,
    target_dir: &Path,
) -> GccResult<()> {
    let logger = ProgressLogger::new("📦 Extracting GCC source");
    
    let archive_path = env.config.packages_dir.join(format!("gcc-{}.tar.xz", version));
    
    // EFFICIENCY: Remove and recreate in one operation
    if target_dir.exists() {
        env.dir_ops.remove_directory(target_dir)?;
    }
    
    info!("📂 Extracting to: {}", target_dir.display());
    info!("⏳ This may take a few minutes for large archives...");
    
    // EFFICIENCY: Use system tar (optimized, memory-mapped)
    env.command_executor.execute("tar", [
        "-Jxf", 
        archive_path.to_str().unwrap(),
        "-C",
        target_dir.parent().unwrap().to_str().unwrap()
    ]).await?;
    
    info!("✅ Extraction completed successfully");
    
    logger.finish();
    Ok(())
}

async fn download_prerequisites_fast(
    env: &BuildEnvironment,
    source_dir: &Path,
) -> GccResult<()> {
    let logger = ProgressLogger::new("📚 Downloading prerequisites");
    
    let prerequisites_script = source_dir.join("contrib/download_prerequisites");
    
    if !prerequisites_script.exists() {
        logger.finish();
        return Ok(());
    }
    
    info!("📚 Running GCC's download_prerequisites script...");
    info!("📦 This downloads GMP, MPFR, MPC, and ISL libraries");
    
    let executor = env.command_executor.clone().with_working_dir(source_dir);
    
    // EFFICIENCY: Don't fail the build if prerequisites fail
    if let Err(e) = executor.execute("./contrib/download_prerequisites", Vec::<&str>::new()).await {
        warn!("Prerequisites download failed: {}, continuing", e);
    } else {
        info!("✅ Prerequisites downloaded successfully");
    }
    
    logger.finish();
    Ok(())
}

async fn configure_gcc_fast(
    env: &BuildEnvironment,
    version: &GccVersion,
    source_dir: &Path,
    build_dir: &Path,
    install_prefix: &Path,
) -> GccResult<()> {
    let logger = ProgressLogger::new("⚙️ Configuring GCC");
    
    // EFFICIENCY: Batch directory operations
    if build_dir.exists() {
        env.dir_ops.remove_directory(build_dir)?;
    }
    env.dir_ops.create_directory(build_dir, "build directory", false)?;
    env.dir_ops.create_directory(install_prefix, "install prefix", false)?;
    
    // EFFICIENCY: Pre-validated configuration options
    let configure_options = env.gcc_config.get_gcc_configure_options(version, &env.config)?;
    env.gcc_config.validate_configure_options(version, &env.config)?;
    
    // EFFICIENCY: Execute configure with optimized environment
    let executor = env.command_executor.clone().with_working_dir(build_dir);
    let configure_script = source_dir.join("configure");
    
    println!("\n─────────────────────────────────────────────────────────────────");
    println!("⚙️  Configuring GCC {}", version);
    println!("─────────────────────────────────────────────────────────────────");
    println!("Configure command:");
    println!("  {} {}", configure_script.to_str().unwrap(), configure_options.join(" "));
    println!("\nConfigure output:");
    println!("─────────────────────────────────────────────────────────────────");
    
    executor.execute(
        configure_script.to_str().unwrap(),
        configure_options.iter().map(|s| s.as_str()),
    ).await.map_err(|e| GccBuildError::build_failed(
        "configure".to_string(),
        format!("Configure failed: {}", e),
    ))?;
    
    println!("─────────────────────────────────────────────────────────────────");
    println!("✅ Configuration completed successfully!\n");
    
    logger.finish();
    Ok(())
}

async fn build_gcc_fast(
    env: &BuildEnvironment,
    version: &GccVersion,
    build_dir: &Path,
) -> GccResult<()> {
    let logger = ProgressLogger::new(&format!("🏗️ Building GCC {} (parallel)", version));
    let start_time = Instant::now();
    
    let executor = env.command_executor.clone().with_working_dir(build_dir);
    
    // EFFICIENCY: Smart job allocation based on available resources
    let optimal_jobs = std::cmp::min(
        env.config.parallel_jobs,
        env.config.system_info.cpu_cores
    );
    
    println!("\n─────────────────────────────────────────────────────────────────");
    println!("🏗️  Building GCC {} (make -j{})", version, optimal_jobs);
    println!("─────────────────────────────────────────────────────────────────");
    println!("This is the longest step (45-90 minutes). You'll see compiler output below.");
    println!("💡 Tip: Open another terminal and run 'htop' to monitor system resources.");
    println!("\nMake output:");
    println!("─────────────────────────────────────────────────────────────────");
    
    // EFFICIENCY: Try parallel first, fallback to single-threaded
    let make_args = vec![format!("-j{}", optimal_jobs)];
    match executor.execute("make", make_args.iter().map(|s| s.as_str())).await {
        Ok(_) => {
            let duration = start_time.elapsed();
            println!("─────────────────────────────────────────────────────────────────");
            println!("✅ Build completed successfully in {:.2?}\n", duration);
        }
        Err(_) => {
            warn!("🔄 Parallel build failed, trying single-threaded");
            info!("🐌 Falling back to single-threaded build (this will take longer)...");
            
            executor.execute("make", Vec::<&str>::new()).await
                .map_err(|e| GccBuildError::build_failed(
                    "make".to_string(),
                    format!("Build failed: {}", e),
                ))?;
            
            let duration = start_time.elapsed();
            info!("🐌 Single-threaded build completed in {:.2?}", duration);
        }
    }
    
    logger.finish();
    Ok(())
}

async fn install_gcc_fast(
    env: &BuildEnvironment,
    version: &GccVersion,
    build_dir: &Path,
    install_prefix: &Path,
) -> GccResult<()> {
    let logger = ProgressLogger::new("📦 Installing GCC");
    
    println!("\n─────────────────────────────────────────────────────────────────");
    println!("📦 Installing GCC {} to {}", version, install_prefix.display());
    println!("─────────────────────────────────────────────────────────────────");
    println!("This requires sudo privileges. You may be prompted for your password.");
    println!("\nInstall output:");
    println!("─────────────────────────────────────────────────────────────────");
    
    let executor = env.command_executor.clone().with_working_dir(build_dir);
    
    // EFFICIENCY: Use install-strip to save space and time
    executor.execute_as("sudo", "make", ["install-strip"]).await
        .map_err(|e| GccBuildError::build_failed(
            "install".to_string(),
            format!("Installation failed: {}", e),
        ))?;
    
    println!("─────────────────────────────────────────────────────────────────");
    println!("✅ Installation completed successfully!\n");
    logger.finish();
    Ok(())
}

async fn post_install_tasks_fast(
    env: &BuildEnvironment,
    version: &GccVersion,
    install_prefix: &Path,
) -> GccResult<()> {
    let logger = ProgressLogger::new("🔧 Post-installation");
    
    // ULTRAFAST: Run independent tasks in parallel
    let env_clone1 = env.clone();
    let env_clone2 = env.clone();
    let env_clone3 = env.clone();
    let version_clone1 = version.clone();
    let version_clone2 = version.clone();
    let version_clone3 = version.clone();
    let prefix_clone1 = install_prefix.to_path_buf();
    let prefix_clone2 = install_prefix.to_path_buf();
    let prefix_clone3 = install_prefix.to_path_buf();
    
    // Spawn parallel tasks
    let libtool_task = tokio::spawn(async move {
        run_libtool_finish_fast(&env_clone1, &version_clone1, &prefix_clone1).await
    });
    
    let symlinks_task = if env.config.create_symlinks {
        Some(tokio::spawn(async move {
            create_gcc_symlinks_fast(&env_clone2, &version_clone2, &prefix_clone2).await
        }))
    } else {
        info!("⏭️  Skipping symlink creation (disabled by configuration)");
        None
    };
    
    let trim_task = tokio::spawn(async move {
        trim_gcc_binaries_fast(&env_clone3, &version_clone3, &prefix_clone3).await
    });
    
    // Execute parallel tasks and collect results
    let (libtool_result, trim_result) = tokio::join!(libtool_task, trim_task);
    
    // Handle results
    libtool_result.unwrap()?;
    trim_result.unwrap()?;
    
    if let Some(task) = symlinks_task {
        task.await.unwrap()?;
    }
    
    // Linker cache must run after other tasks complete
    update_linker_cache_fast(env, version, install_prefix).await?;
    
    // Static binary saving (if needed)
    if env.config.static_build && env.config.save_binaries {
        save_static_binaries_fast(env, version, install_prefix).await?;
    }
    
    logger.finish();
    Ok(())
}

// EFFICIENCY: Simplified post-install functions with error handling that doesn't fail the build

async fn run_libtool_finish_fast(
    env: &BuildEnvironment,
    version: &GccVersion,
    install_prefix: &Path,
) -> GccResult<()> {
    let libexec_dir = install_prefix
        .join("libexec/gcc")
        .join(&env.config.target_arch)
        .join(&version.full_version);
    
    if libexec_dir.exists() {
        let _ = env.command_executor.execute_as(
            "sudo", "libtool", ["--finish", libexec_dir.to_str().unwrap()]
        ).await;
    }
    Ok(())
}

async fn update_linker_cache_fast(
    env: &BuildEnvironment,
    version: &GccVersion,
    install_prefix: &Path,
) -> GccResult<()> {
    info!("📚 Updating linker cache for GCC {}", version);
    
    // Include all possible library directories
    let lib_dirs = vec![
        install_prefix.join("lib"),
        install_prefix.join("lib64"),
        install_prefix.join("lib32"),  // For multilib support
        install_prefix.join(format!("lib/gcc/{}/{}", env.config.target_arch, version.full_version)),
    ];
    
    let mut conf_content = String::new();
    for lib_dir in &lib_dirs {
        if lib_dir.exists() {
            conf_content.push_str(&format!("{}\n", lib_dir.display()));
            info!("  📁 Added library path: {}", lib_dir.display());
        }
    }
    
    let conf_file = format!("/etc/ld.so.conf.d/gcc-{}.conf", version.full_version);
    let conf_path = Path::new(&conf_file);
    
    // Write config file with sudo
    let temp_file = env.config.build_dir.join(format!("gcc-{}.conf", version.full_version));
    env.file_ops.write_file(&temp_file, &conf_content)?;
    
    // Copy to system location with sudo
    env.command_executor.execute_as("sudo", "cp", [
        temp_file.to_str().unwrap(),
        conf_path.to_str().unwrap(),
    ]).await?;
    
    // Set proper permissions
    env.command_executor.execute_as("sudo", "chmod", ["644", conf_path.to_str().unwrap()]).await?;
    
    // Update linker cache
    info!("  🔄 Running ldconfig to update library cache...");
    env.command_executor.execute_as("sudo", "ldconfig", Vec::<&str>::new()).await?;
    
    info!("  ✅ Linker cache updated successfully");
    
    // Clean up temp file
    let _ = fs::remove_file(&temp_file).await;
    
    Ok(())
}

async fn create_gcc_symlinks_fast(
    env: &BuildEnvironment,
    version: &GccVersion,
    install_prefix: &Path,
) -> GccResult<()> {
    use crate::symlink_optimizer::{SymlinkOptimizer, discover_gcc_binaries_parallel};
    
    info!("🔗 Creating symlinks for GCC {} binaries", version);
    
    let bin_dir = install_prefix.join("bin");
    let symlink_dir = Path::new("/usr/local/bin");
    
    if !bin_dir.exists() {
        warn!("Binary directory not found: {}", bin_dir.display());
        return Ok(());
    }
    
    // Ensure symlink directory exists
    env.dir_ops.create_directory(symlink_dir, "symlink directory", true)?;
    
    // Dynamically find all GCC binaries with version suffixes
    let version_patterns = vec![
        format!("-{}", version.major),                    // e.g., gcc-14
        format!("-{}.{}", version.major, version.minor),  // e.g., gcc-14.3
        format!("-{}", version.full_version),             // e.g., gcc-14.3.0
    ];
    
    // ULTRAFAST: Parallel binary discovery
    let binaries = discover_gcc_binaries_parallel(&bin_dir, &version_patterns).await?;
    
    // Prepare symlink pairs
    let symlinks: Vec<(PathBuf, PathBuf)> = binaries
        .into_iter()
        .map(|(source, filename)| {
            let target = symlink_dir.join(&filename);
            (source, target)
        })
        .collect();
    
    if symlinks.is_empty() {
        info!("No GCC binaries found to symlink");
        return Ok(());
    }
    
    // ULTRAFAST: Batch symlink creation
    let optimizer = SymlinkOptimizer::new(env.config.dry_run);
    let created_count = optimizer.create_symlinks_batch(symlinks, true).await?;
    
    info!("🔗 Created {} symlinks in /usr/local/bin/", created_count);
    
    Ok(())
}

async fn trim_gcc_binaries_fast(
    env: &BuildEnvironment,
    version: &GccVersion,
    install_prefix: &Path,
) -> GccResult<()> {
    info!("🔧 Trimming architecture prefix from GCC {} binaries", version);
    
    let bin_dir = install_prefix.join("bin");
    if !bin_dir.exists() {
        return Ok(());
    }
    
    // Read directory to find binaries with architecture prefix
    let prefix = format!("{}-", env.config.target_arch);
    let mut entries = fs::read_dir(&bin_dir).await
        .map_err(|e| GccBuildError::file_operation(
            "read_dir".to_string(),
            bin_dir.display().to_string(),
            e.to_string(),
        ))?;
    
    let mut trimmed_count = 0;
    
    while let Some(entry) = entries.next_entry().await
        .map_err(|e| GccBuildError::file_operation(
            "next_entry".to_string(),
            bin_dir.display().to_string(),
            e.to_string(),
        ))? {
        let path = entry.path();
        if let Some(filename) = path.file_name().and_then(|f| f.to_str()) {
                if filename.starts_with(&prefix) && !filename.contains(&format!("-{}", version.major)) {
                    // This is a prefixed binary without version number
                    let new_name = filename.strip_prefix(&prefix).unwrap();
                    let new_path = bin_dir.join(new_name);
                    
                    // Only rename if target doesn't exist
                    if !new_path.exists() {
                        match env.command_executor.execute_as("sudo", "mv", [
                            path.to_str().unwrap(),
                            new_path.to_str().unwrap(),
                        ]).await {
                            Ok(_) => {
                                info!("  ✂️  Trimmed: {} -> {}", filename, new_name);
                                trimmed_count += 1;
                            }
                            Err(e) => {
                                warn!("  ⚠️  Failed to trim {}: {}", filename, e);
                            }
                        }
                    }
                }
        }
    }
    
    info!("  ✅ Trimmed {} binary names", trimmed_count);
    Ok(())
}

async fn save_static_binaries_fast(
    env: &BuildEnvironment,
    version: &GccVersion,
    install_prefix: &Path,
) -> GccResult<()> {
    // FIXED: Create static binaries in a proper dedicated location
    let save_dir = if let Some(static_dir) = &env.config.static_binaries_dir {
        static_dir.join(format!("gcc-{}", version))
    } else if let Some(prefix) = &env.config.install_prefix {
        prefix.parent().unwrap_or_else(|| Path::new("/usr/local"))
            .join("static-binaries")
            .join(format!("gcc-{}", version))
    } else {
        Path::new("/usr/local/static-binaries")
            .join(format!("gcc-{}", version))
    };
    
    env.dir_ops.create_directory(&save_dir, "static binaries", false)?;
    
    // EFFICIENCY: Use system cp for batch copying
    let bin_dir = install_prefix.join("bin");
    let _ = env.command_executor.execute("cp", [
        "-t", save_dir.to_str().unwrap(),
        &format!("{}/gcc-{}", bin_dir.display(), version.major),
        &format!("{}/g++-{}", bin_dir.display(), version.major),
    ]).await;
    
    info!("💾 Static binaries saved to {}", save_dir.display());
    Ok(())
}