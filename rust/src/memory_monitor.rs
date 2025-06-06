use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{RwLock, watch};
use tokio::time::interval;
use log::{info, warn, debug, error};
use serde::{Deserialize, Serialize};
use crate::error::{GccBuildError, Result as GccResult};

/// Real-time memory pressure monitoring and automatic response system
#[derive(Clone)]
pub struct MemoryMonitor {
    state: Arc<RwLock<MonitorState>>,
    config: MonitorConfig,
    pressure_sender: watch::Sender<MemoryPressure>,
    pressure_receiver: watch::Receiver<MemoryPressure>,
}

#[derive(Debug)]
struct MonitorState {
    current_memory: MemoryInfo,
    pressure_level: MemoryPressure,
    pressure_history: Vec<PressureReading>,
    monitoring_active: bool,
    last_gc_trigger: Option<Instant>,
    adaptive_thresholds: AdaptiveThresholds,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemoryPressure {
    None,     // < 70% usage
    Low,      // 70-80% usage  
    Medium,   // 80-90% usage
    High,     // 90-95% usage
    Critical, // > 95% usage
}

#[derive(Debug, Clone)]
pub struct MemoryInfo {
    pub total_mb: u64,
    pub available_mb: u64,
    pub used_mb: u64,
    pub cached_mb: u64,
    pub buffers_mb: u64,
    pub swap_total_mb: u64,
    pub swap_used_mb: u64,
    pub timestamp: Instant,
}

#[derive(Debug)]
struct PressureReading {
    pressure: MemoryPressure,
    memory_info: MemoryInfo,
    timestamp: Instant,
}

#[derive(Debug)]
struct AdaptiveThresholds {
    low_threshold: f64,
    medium_threshold: f64,
    high_threshold: f64,
    critical_threshold: f64,
    adaptation_factor: f64,
}

#[derive(Debug, Clone)]
pub struct MonitorConfig {
    pub polling_interval: Duration,
    pub gc_cooldown: Duration,
    pub pressure_window_size: usize,
    pub adaptive_mode: bool,
    pub emergency_actions: bool,
}

impl Default for MonitorConfig {
    fn default() -> Self {
        Self {
            polling_interval: Duration::from_secs(5),
            gc_cooldown: Duration::from_secs(30),
            pressure_window_size: 12, // 1 minute of history at 5s intervals
            adaptive_mode: true,
            emergency_actions: true,
        }
    }
}

impl Default for AdaptiveThresholds {
    fn default() -> Self {
        Self {
            low_threshold: 0.70,
            medium_threshold: 0.80,
            high_threshold: 0.90,
            critical_threshold: 0.95,
            adaptation_factor: 0.1,
        }
    }
}

impl MemoryMonitor {
    pub fn new(config: MonitorConfig) -> Self {
        let (pressure_sender, pressure_receiver) = watch::channel(MemoryPressure::None);
        
        Self {
            state: Arc::new(RwLock::new(MonitorState {
                current_memory: MemoryInfo::default(),
                pressure_level: MemoryPressure::None,
                pressure_history: Vec::new(),
                monitoring_active: false,
                last_gc_trigger: None,
                adaptive_thresholds: AdaptiveThresholds::default(),
            })),
            config,
            pressure_sender,
            pressure_receiver,
        }
    }
    
    /// Start monitoring memory pressure
    pub async fn start_monitoring(&self) -> GccResult<()> {
        {
            let mut state = self.state.write().await;
            if state.monitoring_active {
                return Ok(());
            }
            state.monitoring_active = true;
        }
        
        info!("🔍 Starting memory pressure monitoring ({}s intervals)", 
              self.config.polling_interval.as_secs());
        
        let monitor = self.clone();
        tokio::spawn(async move {
            monitor.monitoring_loop().await;
        });
        
        Ok(())
    }
    
    /// Stop monitoring
    pub async fn stop_monitoring(&self) {
        let mut state = self.state.write().await;
        state.monitoring_active = false;
        info!("⏹️ Memory monitoring stopped");
    }
    
    /// Get current memory pressure level
    pub async fn get_pressure_level(&self) -> MemoryPressure {
        self.state.read().await.pressure_level
    }
    
    /// Get memory pressure change notifications
    pub fn subscribe_pressure_changes(&self) -> watch::Receiver<MemoryPressure> {
        self.pressure_receiver.clone()
    }
    
    /// Get current memory information
    pub async fn get_memory_info(&self) -> MemoryInfo {
        self.state.read().await.current_memory.clone()
    }
    
    /// Check if system can handle additional memory load
    pub async fn can_allocate_memory(&self, required_mb: u64) -> bool {
        let state = self.state.read().await;
        let available = state.current_memory.available_mb;
        let would_use_percent = (state.current_memory.used_mb + required_mb) as f64 
            / state.current_memory.total_mb as f64;
        
        // Don't allow allocation if it would push us into high pressure
        would_use_percent < state.adaptive_thresholds.high_threshold && available > required_mb
    }
    
    /// Request emergency memory cleanup
    pub async fn request_emergency_cleanup(&self) -> GccResult<()> {
        info!("🚨 Emergency memory cleanup requested");
        
        let mut state = self.state.write().await;
        
        // Avoid too frequent cleanups
        if let Some(last_gc) = state.last_gc_trigger {
            if last_gc.elapsed() < self.config.gc_cooldown {
                debug!("Skipping cleanup - too recent");
                return Ok(());
            }
        }
        
        state.last_gc_trigger = Some(Instant::now());
        drop(state);
        
        // Trigger system garbage collection
        self.trigger_system_cleanup().await?;
        
        // Force memory update
        self.update_memory_info().await?;
        
        Ok(())
    }
    
    /// Main monitoring loop
    async fn monitoring_loop(&self) {
        let mut interval = interval(self.config.polling_interval);
        
        while self.state.read().await.monitoring_active {
            interval.tick().await;
            
            if let Err(e) = self.update_memory_info().await {
                error!("Failed to update memory info: {}", e);
                continue;
            }
            
            if let Err(e) = self.evaluate_pressure().await {
                error!("Failed to evaluate memory pressure: {}", e);
                continue;
            }
            
            if let Err(e) = self.handle_pressure_changes().await {
                error!("Failed to handle pressure changes: {}", e);
            }
        }
    }
    
    /// Update current memory information
    async fn update_memory_info(&self) -> GccResult<()> {
        let memory_info = self.read_system_memory().await?;
        
        let mut state = self.state.write().await;
        state.current_memory = memory_info;
        
        Ok(())
    }
    
    /// Read memory information from system
    async fn read_system_memory(&self) -> GccResult<MemoryInfo> {
        let sys_info = sys_info::mem_info()
            .map_err(|e| GccBuildError::system_requirements(
                format!("Failed to read memory info: {}", e)
            ))?;
        
        // Read additional info from /proc/meminfo for more details
        let meminfo = tokio::fs::read_to_string("/proc/meminfo").await
            .unwrap_or_default();
        
        let mut cached_mb = 0;
        let mut buffers_mb = 0;
        
        for line in meminfo.lines() {
            if line.starts_with("Cached:") {
                if let Some(kb) = self.extract_kb_value(line) {
                    cached_mb = kb / 1024;
                }
            } else if line.starts_with("Buffers:") {
                if let Some(kb) = self.extract_kb_value(line) {
                    buffers_mb = kb / 1024;
                }
            }
        }
        
        Ok(MemoryInfo {
            total_mb: sys_info.total / 1024,
            available_mb: sys_info.avail / 1024,
            used_mb: (sys_info.total - sys_info.avail) / 1024,
            cached_mb,
            buffers_mb,
            swap_total_mb: sys_info.swap_total / 1024,
            swap_used_mb: (sys_info.swap_total - sys_info.swap_free) / 1024,
            timestamp: Instant::now(),
        })
    }
    
    /// Extract KB value from /proc/meminfo line
    fn extract_kb_value(&self, line: &str) -> Option<u64> {
        line.split_whitespace()
            .nth(1)?
            .parse::<u64>()
            .ok()
    }
    
    /// Evaluate current memory pressure
    async fn evaluate_pressure(&self) -> GccResult<()> {
        let mut state = self.state.write().await;
        
        let usage_ratio = state.current_memory.used_mb as f64 / state.current_memory.total_mb as f64;
        let thresholds = &state.adaptive_thresholds;
        
        let new_pressure = if usage_ratio >= thresholds.critical_threshold {
            MemoryPressure::Critical
        } else if usage_ratio >= thresholds.high_threshold {
            MemoryPressure::High
        } else if usage_ratio >= thresholds.medium_threshold {
            MemoryPressure::Medium
        } else if usage_ratio >= thresholds.low_threshold {
            MemoryPressure::Low
        } else {
            MemoryPressure::None
        };
        
        // Update pressure history
        state.pressure_history.push(PressureReading {
            pressure: new_pressure,
            memory_info: state.current_memory.clone(),
            timestamp: Instant::now(),
        });
        
        // Keep only recent history
        if state.pressure_history.len() > self.config.pressure_window_size {
            state.pressure_history.remove(0);
        }
        
        // Adapt thresholds if enabled
        if self.config.adaptive_mode {
            self.adapt_thresholds(&mut state).await;
        }
        
        let old_pressure = state.pressure_level;
        state.pressure_level = new_pressure;
        
        // Notify pressure change
        if old_pressure != new_pressure {
            debug!("Memory pressure changed: {:?} -> {:?} ({:.1}% usage)", 
                   old_pressure, new_pressure, usage_ratio * 100.0);
            
            let _ = self.pressure_sender.send(new_pressure);
        }
        
        Ok(())
    }
    
    /// Adapt thresholds based on system behavior
    async fn adapt_thresholds(&self, state: &mut MonitorState) {
        if state.pressure_history.len() < self.config.pressure_window_size {
            return;
        }
        
        // Analyze pressure stability
        let recent_pressures: Vec<_> = state.pressure_history
            .iter()
            .rev()
            .take(5)
            .map(|r| r.pressure)
            .collect();
        
        let all_same = recent_pressures.windows(2).all(|w| w[0] == w[1]);
        
        if all_same && recent_pressures[0] == MemoryPressure::High {
            // System is consistently at high pressure - lower thresholds slightly
            let factor = state.adaptive_thresholds.adaptation_factor;
            state.adaptive_thresholds.high_threshold = 
                (state.adaptive_thresholds.high_threshold - factor * 0.1).max(0.80);
            
            debug!("Adapted high threshold to {:.2}", state.adaptive_thresholds.high_threshold);
        }
    }
    
    /// Handle memory pressure changes
    async fn handle_pressure_changes(&self) -> GccResult<()> {
        let pressure = {
            let state = self.state.read().await;
            state.pressure_level
        };
        
        match pressure {
            MemoryPressure::Critical => {
                warn!("🚨 CRITICAL memory pressure detected!");
                if self.config.emergency_actions {
                    self.emergency_response().await?;
                }
            }
            MemoryPressure::High => {
                warn!("⚠️ HIGH memory pressure - consider reducing build parallelism");
                self.high_pressure_response().await?;
            }
            MemoryPressure::Medium => {
                info!("📊 Medium memory pressure - monitoring closely");
            }
            MemoryPressure::Low => {
                debug!("Low memory pressure");
            }
            MemoryPressure::None => {
                debug!("No memory pressure");
            }
        }
        
        Ok(())
    }
    
    /// Emergency response to critical memory pressure
    async fn emergency_response(&self) -> GccResult<()> {
        info!("🚨 Executing emergency memory response");
        
        // Force garbage collection
        self.trigger_system_cleanup().await?;
        
        // Clear caches if possible
        if let Err(e) = self.clear_system_caches().await {
            warn!("Failed to clear system caches: {}", e);
        }
        
        // Wait a moment for memory to stabilize
        tokio::time::sleep(Duration::from_secs(5)).await;
        
        Ok(())
    }
    
    /// Response to high memory pressure
    async fn high_pressure_response(&self) -> GccResult<()> {
        // Trigger garbage collection if cooldown period has passed
        let should_gc = {
            let state = self.state.read().await;
            match state.last_gc_trigger {
                Some(last) => last.elapsed() >= self.config.gc_cooldown,
                None => true,
            }
        };
        
        if should_gc {
            self.trigger_system_cleanup().await?;
            self.state.write().await.last_gc_trigger = Some(Instant::now());
        }
        
        Ok(())
    }
    
    /// Trigger system-level memory cleanup
    async fn trigger_system_cleanup(&self) -> GccResult<()> {
        info!("🧹 Triggering system memory cleanup");
        
        // Force kernel to drop caches
        if let Err(e) = tokio::fs::write("/proc/sys/vm/drop_caches", "3").await {
            debug!("Cannot drop caches (permission issue): {}", e);
        }
        
        // Force garbage collection in allocator (if using jemalloc)
        #[cfg(feature = "jemalloc")]
        {
            extern "C" {
                fn malloc_trim(pad: libc::size_t) -> libc::c_int;
            }
            unsafe {
                malloc_trim(0);
            }
        }
        
        Ok(())
    }
    
    /// Clear system caches
    async fn clear_system_caches(&self) -> GccResult<()> {
        // Drop page cache, dentries and inodes
        tokio::fs::write("/proc/sys/vm/drop_caches", "3").await
            .map_err(|e| GccBuildError::system_requirements(
                format!("Failed to clear system caches: {}", e)
            ))?;
        
        Ok(())
    }
    
    /// Get monitoring statistics
    pub async fn get_stats(&self) -> MonitorStats {
        let state = self.state.read().await;
        
        let pressure_distribution = self.calculate_pressure_distribution(&state.pressure_history);
        let avg_usage = self.calculate_average_usage(&state.pressure_history);
        
        MonitorStats {
            monitoring_active: state.monitoring_active,
            current_pressure: state.pressure_level,
            current_memory: state.current_memory.clone(),
            pressure_distribution,
            average_usage_percent: avg_usage,
            total_readings: state.pressure_history.len(),
            adaptive_thresholds: state.adaptive_thresholds.clone(),
        }
    }
    
    /// Calculate pressure level distribution
    fn calculate_pressure_distribution(&self, history: &[PressureReading]) -> PressureDistribution {
        if history.is_empty() {
            return PressureDistribution::default();
        }
        
        let total = history.len() as f64;
        let mut dist = PressureDistribution::default();
        
        for reading in history {
            match reading.pressure {
                MemoryPressure::None => dist.none_percent += 1.0,
                MemoryPressure::Low => dist.low_percent += 1.0,
                MemoryPressure::Medium => dist.medium_percent += 1.0,
                MemoryPressure::High => dist.high_percent += 1.0,
                MemoryPressure::Critical => dist.critical_percent += 1.0,
            }
        }
        
        dist.none_percent = (dist.none_percent / total) * 100.0;
        dist.low_percent = (dist.low_percent / total) * 100.0;
        dist.medium_percent = (dist.medium_percent / total) * 100.0;
        dist.high_percent = (dist.high_percent / total) * 100.0;
        dist.critical_percent = (dist.critical_percent / total) * 100.0;
        
        dist
    }
    
    /// Calculate average memory usage
    fn calculate_average_usage(&self, history: &[PressureReading]) -> f64 {
        if history.is_empty() {
            return 0.0;
        }
        
        let sum: f64 = history.iter()
            .map(|r| r.memory_info.used_mb as f64 / r.memory_info.total_mb as f64)
            .sum();
        
        (sum / history.len() as f64) * 100.0
    }
}

impl Default for MemoryInfo {
    fn default() -> Self {
        Self {
            total_mb: 0,
            available_mb: 0,
            used_mb: 0,
            cached_mb: 0,
            buffers_mb: 0,
            swap_total_mb: 0,
            swap_used_mb: 0,
            timestamp: Instant::now(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct MonitorStats {
    pub monitoring_active: bool,
    pub current_pressure: MemoryPressure,
    pub current_memory: MemoryInfo,
    pub pressure_distribution: PressureDistribution,
    pub average_usage_percent: f64,
    pub total_readings: usize,
    pub adaptive_thresholds: AdaptiveThresholds,
}

#[derive(Debug, Clone, Default)]
pub struct PressureDistribution {
    pub none_percent: f64,
    pub low_percent: f64,
    pub medium_percent: f64,
    pub high_percent: f64,
    pub critical_percent: f64,
}

impl std::fmt::Display for MemoryPressure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MemoryPressure::None => write!(f, "None"),
            MemoryPressure::Low => write!(f, "Low"),
            MemoryPressure::Medium => write!(f, "Medium"),
            MemoryPressure::High => write!(f, "High"),
            MemoryPressure::Critical => write!(f, "Critical"),
        }
    }
}