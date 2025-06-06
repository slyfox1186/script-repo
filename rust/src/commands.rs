use log::{debug, error, info, warn};
use std::collections::HashMap;
use std::ffi::OsStr;
use std::path::Path;
use std::process::Stdio;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command as AsyncCommand;
use tokio::time::timeout;

use crate::error::{GccBuildError, Result as GccResult};
use crate::logging::ProgressLogger;

#[derive(Debug, Clone)]
pub struct CommandExecutor {
    pub dry_run: bool,
    pub verbose: bool,
    pub env_vars: HashMap<String, String>,
    pub working_dir: Option<std::path::PathBuf>,
}

impl CommandExecutor {
    pub fn new(dry_run: bool, verbose: bool) -> Self {
        Self {
            dry_run,
            verbose,
            env_vars: HashMap::new(),
            working_dir: None,
        }
    }
    
    pub fn with_env_vars(mut self, env_vars: HashMap<String, String>) -> Self {
        self.env_vars = env_vars;
        self
    }
    
    pub fn with_working_dir<P: AsRef<Path>>(mut self, dir: P) -> Self {
        self.working_dir = Some(dir.as_ref().to_path_buf());
        self
    }
    
    /// Execute a command with retry logic
    pub async fn execute_with_retry<I, S>(
        &self,
        program: &str,
        args: I,
        max_attempts: usize,
        wait_time: Duration,
    ) -> GccResult<()>
    where
        I: IntoIterator<Item = S> + Clone,
        S: AsRef<OsStr>,
    {
        let mut last_error = None;
        
        for attempt in 1..=max_attempts {
            debug!("Attempt {}/{}: {} {:?}", attempt, max_attempts, program, 
                   args.clone().into_iter().map(|s| s.as_ref().to_string_lossy().to_string()).collect::<Vec<_>>());
            
            match self.execute(program, args.clone()).await {
                Ok(_) => return Ok(()),
                Err(e) => {
                    last_error = Some(e);
                    if attempt < max_attempts {
                        warn!("Command failed, retrying in {:?}...", wait_time);
                        tokio::time::sleep(wait_time).await;
                    }
                }
            }
        }
        
        Err(last_error.unwrap_or_else(|| {
            GccBuildError::command_failed(
                format!("{} with args", program),
                -1
            )
        }))
    }
    
    /// Execute a command with timeout
    pub async fn execute_with_timeout<I, S>(
        &self,
        program: &str,
        args: I,
        timeout_duration: Duration,
    ) -> GccResult<()>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        match timeout(timeout_duration, self.execute(program, args)).await {
            Ok(result) => result,
            Err(_) => Err(GccBuildError::network_timeout(
                format!("Command timed out: {}", program)
            )),
        }
    }
    
    /// Execute a command as a specific user (sudo/regular)
    pub async fn execute_as<I, S>(
        &self,
        user: &str,
        program: &str,
        args: I,
    ) -> GccResult<()>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        match user {
            "sudo" | "root" => {
                let args_vec: Vec<_> = args.into_iter().map(|s| s.as_ref().to_string_lossy().to_string()).collect();
                let mut sudo_args = vec![program.to_string()];
                sudo_args.extend(args_vec);
                self.execute("sudo", sudo_args.iter().map(|s| s.as_str())).await
            }
            "user" | "" => {
                self.execute(program, args).await
            }
            _ => {
                let args_vec: Vec<_> = args.into_iter().map(|s| s.as_ref().to_string_lossy().to_string()).collect();
                let mut sudo_args = vec!["-u".to_string(), user.to_string(), program.to_string()];
                sudo_args.extend(args_vec);
                self.execute("sudo", sudo_args.iter().map(|s| s.as_str())).await
            }
        }
    }
    
    /// Basic command execution
    pub async fn execute<I, S>(&self, program: &str, args: I) -> GccResult<()>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        let args: Vec<_> = args.into_iter().collect();
        let cmd_string = format!("{} {}", program, 
                                args.iter().map(|s| s.as_ref().to_string_lossy()).collect::<Vec<_>>().join(" "));
        
        debug!("Executing command: {}", cmd_string);
        
        if self.dry_run {
            info!("Dry run: would execute: {}", cmd_string);
            return Ok(());
        }
        
        let start_time = Instant::now();
        let mut command = AsyncCommand::new(program);
        command.args(&args);
        
        // Set environment variables
        for (key, value) in &self.env_vars {
            command.env(key, value);
        }
        
        // Set working directory if specified
        if let Some(dir) = &self.working_dir {
            command.current_dir(dir);
        }
        
        // Configure stdio - ALWAYS inherit for maximum verbosity
        command.stdout(Stdio::inherit());
        command.stderr(Stdio::inherit());
        
        let mut child = command.spawn()
            .map_err(|e| GccBuildError::command_failed(cmd_string.clone(), -1))?;
        
        // All output is now inherited, so no need to handle pipes
        
        let status = child.wait().await
            .map_err(|e| GccBuildError::command_failed(cmd_string.clone(), -1))?;
        
        let duration = start_time.elapsed();
        
        if status.success() {
            debug!("Command completed successfully in {:?}: {}", duration, cmd_string);
            Ok(())
        } else {
            let exit_code = status.code().unwrap_or(-1);
            error!("Command failed with exit code {} after {:?}: {}", exit_code, duration, cmd_string);
            Err(GccBuildError::command_failed(cmd_string, exit_code))
        }
    }
    
    /// Execute a command and capture its output
    pub async fn execute_with_output<I, S>(&self, program: &str, args: I) -> GccResult<String>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        let args: Vec<_> = args.into_iter().collect();
        let cmd_string = format!("{} {}", program, 
                                args.iter().map(|s| s.as_ref().to_string_lossy()).collect::<Vec<_>>().join(" "));
        
        debug!("Executing command with output capture: {}", cmd_string);
        
        // Special handling for version resolution commands - always execute these
        // since they're read-only operations needed for proper planning
        let is_version_resolution = program == "bash" && 
            args.iter().any(|arg| arg.as_ref().to_string_lossy().contains("curl -fsSL https://ftp.gnu.org/gnu/gcc/"));
        
        if self.dry_run && !is_version_resolution {
            info!("Dry run: would execute: {}", cmd_string);
            return Ok("dry-run-output".to_string());
        }
        
        let mut command = AsyncCommand::new(program);
        command.args(&args);
        
        // Set environment variables
        for (key, value) in &self.env_vars {
            command.env(key, value);
        }
        
        // Set working directory if specified
        if let Some(dir) = &self.working_dir {
            command.current_dir(dir);
        }
        
        command.stdout(Stdio::piped());
        command.stderr(Stdio::piped());
        
        let output = command.output().await
            .map_err(|e| GccBuildError::command_failed(cmd_string.clone(), -1))?;
        
        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
        } else {
            let exit_code = output.status.code().unwrap_or(-1);
            let stderr = String::from_utf8_lossy(&output.stderr);
            error!("Command failed with exit code {}: {}\nstderr: {}", exit_code, cmd_string, stderr);
            Err(GccBuildError::command_failed(cmd_string, exit_code))
        }
    }
    
    /// Check if a command exists in PATH
    pub async fn command_exists(&self, program: &str) -> bool {
        self.execute_with_output("which", [program]).await.is_ok()
    }
    
    /// Download a file with progress tracking
    pub async fn download_file(
        &self,
        url: &str,
        output_path: &Path,
        max_attempts: usize,
    ) -> GccResult<()> {
        let logger = ProgressLogger::new(&format!("Downloading {}", url));
        
        if self.dry_run {
            info!("Dry run: would download {} to {:?}", url, output_path);
            logger.finish();
            return Ok(());
        }
        
        let mut last_error = None;
        
        for attempt in 1..=max_attempts {
            logger.update(&format!("Attempt {}/{}", attempt, max_attempts));
            
            let wget_args = vec![
                "--progress=bar:force:noscroll",
                "--timeout=60",
                "--continue",
                "--output-document",
                output_path.to_str().unwrap(),
                url,
            ];
            
            match self.execute("wget", wget_args).await {
                Ok(_) => {
                    // Verify the download
                    if let Ok(metadata) = output_path.metadata() {
                        let file_size = metadata.len();
                        if file_size > 10_000_000 { // At least 10MB for GCC source
                            info!("✅ Download completed successfully ({:.1} MB)", file_size as f64 / 1_000_000.0);
                            logger.finish();
                            return Ok(());
                        } else {
                            last_error = Some(GccBuildError::download(
                                url.to_string(),
                                format!("Downloaded file too small: {:.1} MB", file_size as f64 / 1_000_000.0),
                            ));
                        }
                    } else {
                        last_error = Some(GccBuildError::download(
                            url.to_string(),
                            "Downloaded file is missing".to_string(),
                        ));
                    }
                }
                Err(e) => {
                    last_error = Some(e);
                    if attempt < max_attempts {
                        warn!("Download attempt {} failed, retrying...", attempt);
                        tokio::time::sleep(Duration::from_secs(5)).await;
                    }
                }
            }
        }
        
        logger.fail(&format!("Failed after {} attempts", max_attempts));
        Err(last_error.unwrap_or_else(|| {
            GccBuildError::download(url.to_string(), "Unknown error".to_string())
        }))
    }
}

/// Execute multiple commands in parallel
pub async fn execute_parallel(
    executor: &CommandExecutor,
    commands: Vec<(&str, Vec<&str>)>,
) -> GccResult<()> {
    let futures: Vec<_> = commands
        .into_iter()
        .map(|(program, args)| executor.execute(program, args))
        .collect();
    
    let results = futures::future::join_all(futures).await;
    
    let mut failed_commands = Vec::new();
    for (i, result) in results.into_iter().enumerate() {
        if let Err(e) = result {
            failed_commands.push(format!("Command {}: {}", i, e));
        }
    }
    
    if !failed_commands.is_empty() {
        return Err(GccBuildError::command_failed(
            "Parallel execution".to_string(),
            failed_commands.len() as i32,
        ));
    }
    
    Ok(())
}

/// Monitor a long-running command with progress updates
pub async fn monitor_command_progress<F>(
    executor: &CommandExecutor,
    program: &str,
    args: Vec<&str>,
    progress_callback: F,
) -> GccResult<()>
where
    F: Fn(&str) + Send + 'static,
{
    let cmd_string = format!("{} {}", program, args.join(" "));
    info!("Starting monitored command: {}", cmd_string);
    
    if executor.dry_run {
        info!("Dry run: would execute monitored: {}", cmd_string);
        return Ok(());
    }
    
    // Implementation would include real-time output parsing
    // and progress reporting based on command-specific patterns
    executor.execute(program, args).await
}