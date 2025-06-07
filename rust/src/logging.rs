#![allow(dead_code)]
use anyhow::Result;
use colored::*;
use env_logger::{Builder, Target};
use log::LevelFilter;
use std::io::Write;
use std::fs::OpenOptions;
use std::path::Path;

use crate::cli::Args;

pub fn init_logger(args: &Args) -> Result<()> {
    let mut builder = Builder::new();
    
    // Set log level based on verbosity - ALWAYS show progress
    let level = match (args.debug, args.verbose) {
        (true, _) => LevelFilter::Debug,
        (false, true) => LevelFilter::Info,
        (false, false) => LevelFilter::Info, // ALWAYS show progress info
    };
    
    builder.filter_level(level);
    
    // Configure output target
    if let Some(log_file) = &args.log_file {
        setup_file_logging(&mut builder, log_file)?;
    } else {
        setup_console_logging(&mut builder);
    }
    
    builder.init();
    Ok(())
}

fn setup_console_logging(builder: &mut Builder) {
    builder
        .target(Target::Stderr)
        .format(|buf, record| {
            let level_color = match record.level() {
                log::Level::Error => "red",
                log::Level::Warn => "yellow", 
                log::Level::Info => "green",
                log::Level::Debug => "cyan",
                log::Level::Trace => "magenta",
            };
            
            let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
            
            writeln!(
                buf,
                "[{} {}] {}",
                timestamp,
                record.level().to_string().color(level_color).bold(),
                record.args()
            )
        });
}

fn setup_file_logging(builder: &mut Builder, log_file: &Path) -> Result<()> {
    // Create log directory if it doesn't exist
    if let Some(parent) = log_file.parent() {
        std::fs::create_dir_all(parent)?;
    }
    
    // Open log file
    let file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(log_file)?;
    
    builder
        .target(Target::Pipe(Box::new(file)))
        .format(|buf, record| {
            let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
            writeln!(
                buf,
                "[{} {}] {}",
                timestamp,
                record.level(),
                record.args()
            )
        });
    
    Ok(())
}

#[macro_export]
macro_rules! log_command {
    ($cmd:expr) => {
        log::debug!("Executing command: {}", $cmd);
    };
}

#[macro_export]
macro_rules! log_duration {
    ($operation:expr, $duration:expr) => {
        log::info!("{} completed in {:.2?}", $operation, $duration);
    };
}

pub fn log_system_info() {
    log::info!("System Information:");
    if let Ok(info) = sys_info::mem_info() {
        log::info!("  RAM: {:.1} GB total, {:.1} GB available", 
                  info.total as f64 / 1024.0 / 1024.0,
                  info.avail as f64 / 1024.0 / 1024.0);
    }
    
    if let Ok(cpu_num) = sys_info::cpu_num() {
        log::info!("  CPU cores: {}", cpu_num);
    }
    
    if let Ok(hostname) = sys_info::hostname() {
        log::info!("  Hostname: {}", hostname);
    }
}

pub struct ProgressLogger {
    operation: String,
    start_time: std::time::Instant,
}

impl ProgressLogger {
    pub fn new(operation: &str) -> Self {
        log::info!("Starting: {}", operation);
        Self {
            operation: operation.to_string(),
            start_time: std::time::Instant::now(),
        }
    }
    
    pub fn update(&self, message: &str) {
        log::debug!("{}: {}", self.operation, message);
    }
    
    pub fn finish(self) {
        let duration = self.start_time.elapsed();
        log::info!("Completed: {} (took {:.2?})", self.operation, duration);
    }
    
    pub fn fail(self, error: &str) {
        let duration = self.start_time.elapsed();
        log::error!("Failed: {} after {:.2?} - {}", self.operation, duration, error);
    }
}