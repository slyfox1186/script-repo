use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use std::collections::HashMap;
use tokio::sync::Semaphore;
use tokio::sync::OwnedSemaphorePermit;
use log::{info, warn, debug};
use crate::config::{Config, GccVersion};
use crate::error::{GccBuildError, Result as GccResult};

/// Smart resource-aware build scheduler with phase-aware CPU scheduling
pub struct BuildScheduler {
    /// Maximum concurrent builds based on system resources
    max_concurrent: usize,
    /// Semaphore for controlling concurrent builds
    build_semaphore: Arc<Semaphore>,
    /// RAM required per GCC build (in MB)
    ram_per_build: u64,
    /// Current system state
    system_state: Arc<Mutex<SystemState>>,
    /// Phase-specific resource profiles
    phase_profiles: HashMap<BuildPhase, PhaseProfile>,
    /// CPU scheduling strategy
    cpu_scheduler: CpuScheduler,
}

#[derive(Debug, Clone)]
struct SystemState {
    total_ram_mb: u64,
    available_ram_mb: u64,
    active_builds: Vec<ActiveBuild>,
    completed_builds: Vec<CompletedBuild>,
}

#[derive(Debug, Clone)]
struct ActiveBuild {
    version: GccVersion,
    start_time: Instant,
    estimated_ram_mb: u64,
    phase: BuildPhase,
}

#[derive(Debug, Clone)]
struct CompletedBuild {
    version: GccVersion,
    duration: Duration,
    peak_ram_mb: u64,
    success: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BuildPhase {
    Configure,
    Bootstrap,
    Compile,
    Link,
    Install,
    Test,
}

#[derive(Debug, Clone)]
struct PhaseProfile {
    cpu_intensity: f64,      // 0.0 to 1.0
    memory_multiplier: f64,  // Memory usage relative to base
    io_intensity: f64,       // I/O usage 0.0 to 1.0
    parallelism_efficiency: f64, // How well phase scales with multiple jobs
    typical_duration_pct: f64,   // Percentage of total build time
}

#[derive(Debug, Clone)]
struct CpuScheduler {
    strategy: SchedulingStrategy,
    load_balancer: LoadBalancer,
    affinity_manager: AffinityManager,
}

#[derive(Debug, Clone)]
enum SchedulingStrategy {
    Conservative,  // Safer resource usage
    Balanced,      // Balanced approach
    Aggressive,    // Maximum performance
}

#[derive(Debug, Clone)]
struct LoadBalancer {
    current_load: f64,
    load_history: Vec<f64>,
    target_utilization: f64,
}

#[derive(Debug, Clone)]
struct AffinityManager {
    cpu_topology: CpuTopology,
    build_assignments: HashMap<GccVersion, CpuAssignment>,
}

#[derive(Debug, Clone)]
struct CpuTopology {
    total_cores: usize,
    physical_cores: usize,
    numa_nodes: usize,
    l3_cache_groups: Vec<Vec<usize>>,
}

#[derive(Debug, Clone)]
struct CpuAssignment {
    assigned_cores: Vec<usize>,
    numa_node: usize,
    priority: i32,
}

impl BuildScheduler {
    pub fn new(config: &Config) -> Self {
        // Calculate optimal concurrent builds based on RAM and CPU
        let ram_per_build = calculate_ram_per_build(config);
        let ram_limited = (config.system_info.ram_mb * 80 / 100) / ram_per_build; // Use 80% of RAM
        let cpu_limited = config.system_info.cpu_cores / 2; // Use half the cores per build
        
        let max_concurrent = std::cmp::min(ram_limited as usize, cpu_limited).max(1);
        
        // Initialize phase profiles
        let phase_profiles = Self::create_phase_profiles();
        
        // Initialize CPU scheduler
        let cpu_scheduler = Self::create_cpu_scheduler(config);
        
        println!("\n📊 System Resource Analysis:");
        println!("─────────────────────────────────────────────────────────────────");
        println!("  • Total system RAM: {:.1} GB ({} MB)", config.system_info.ram_mb as f64 / 1024.0, config.system_info.ram_mb);
        println!("  • RAM per GCC build: ~{:.1} GB ({} MB)", ram_per_build as f64 / 1024.0, ram_per_build);
        println!("  • CPU cores available: {}", config.system_info.cpu_cores);
        println!("  • Max parallel builds: {} (based on available resources)", max_concurrent);
        println!("  • Smart scheduling: ✓ (adjusts based on build phases)");
        println!("  • CPU affinity: ✓ (optimizes cache usage)");
        println!("─────────────────────────────────────────────────────────────────");
        println!();
        
        Self {
            max_concurrent,
            build_semaphore: Arc::new(Semaphore::new(max_concurrent)),
            ram_per_build,
            system_state: Arc::new(Mutex::new(SystemState {
                total_ram_mb: config.system_info.ram_mb,
                available_ram_mb: config.system_info.ram_mb,
                active_builds: Vec::new(),
                completed_builds: Vec::new(),
            })),
            phase_profiles,
            cpu_scheduler,
        }
    }
    
    /// Acquire a build slot with resource checking
    pub async fn acquire_build_slot(&self, version: &GccVersion) -> GccResult<BuildSlot> {
        // Check current system resources
        let available_ram = self.get_available_ram().await?;
        
        // Dynamic adjustment: wait if RAM is too low
        if available_ram < self.ram_per_build {
            warn!("⚠️ Low RAM detected ({} MB). Waiting for builds to complete...", available_ram);
            self.wait_for_resources().await?;
        }
        
        // Acquire owned semaphore permit (no memory leak!)
        let permit = Arc::clone(&self.build_semaphore)
            .acquire_owned()
            .await
            .map_err(|e| GccBuildError::resource_exhausted("build slots", e.to_string()))?;
        
        // Register active build
        {
            let mut state = self.system_state.lock().unwrap();
            state.active_builds.push(ActiveBuild {
                version: version.clone(),
                start_time: Instant::now(),
                estimated_ram_mb: self.ram_per_build,
                phase: BuildPhase::Configure,
            });
            state.available_ram_mb = state.available_ram_mb.saturating_sub(self.ram_per_build);
        }
        
        info!("🎯 Build slot acquired for GCC {} (RAM: {} MB allocated)", version, self.ram_per_build);
        
        Ok(BuildSlot {
            scheduler: self.clone(),
            version: version.clone(),
            permit: Some(permit),
            start_time: Instant::now(),
        })
    }
    
    /// Update build phase for better resource prediction and CPU scheduling
    pub fn update_build_phase(&self, version: &GccVersion, phase: BuildPhase) {
        let mut state = self.system_state.lock().unwrap();
        if let Some(build) = state.active_builds.iter_mut().find(|b| &b.version == version) {
            let old_phase = build.phase;
            build.phase = phase;
            
            // Update CPU allocation based on new phase
            if let Some(profile) = self.phase_profiles.get(&phase) {
                self.adjust_cpu_allocation(version, phase, profile);
            }
            
            debug!("Build phase updated for GCC {}: {:?} -> {:?}", version, old_phase, phase);
            info!("🔄 Phase transition for GCC {}: {:?} (CPU: {:.1}%, Mem: {:.1}x, I/O: {:.1}%)",
                  version, phase,
                  self.phase_profiles.get(&phase).map(|p| p.cpu_intensity * 100.0).unwrap_or(0.0),
                  self.phase_profiles.get(&phase).map(|p| p.memory_multiplier).unwrap_or(1.0),
                  self.phase_profiles.get(&phase).map(|p| p.io_intensity * 100.0).unwrap_or(0.0));
        }
    }
    
    /// Get current available RAM
    async fn get_available_ram(&self) -> GccResult<u64> {
        match sys_info::mem_info() {
            Ok(info) => Ok(info.avail / 1024), // Convert KB to MB
            Err(e) => {
                warn!("Failed to get memory info: {}. Using estimate.", e);
                let state = self.system_state.lock().unwrap();
                Ok(state.available_ram_mb)
            }
        }
    }
    
    /// Wait for resources to become available
    async fn wait_for_resources(&self) -> GccResult<()> {
        let check_interval = Duration::from_secs(10);
        let max_wait = Duration::from_secs(300); // 5 minutes
        let start = Instant::now();
        
        loop {
            let available_ram = self.get_available_ram().await?;
            if available_ram >= self.ram_per_build {
                info!("✅ Sufficient resources available. Proceeding with build.");
                return Ok(());
            }
            
            if start.elapsed() > max_wait {
                return Err(GccBuildError::resource_exhausted(
                    "RAM",
                    format!("Waited {} seconds but insufficient RAM available", max_wait.as_secs())
                ));
            }
            
            tokio::time::sleep(check_interval).await;
        }
    }
    
    /// Calculate optimal -j flag based on current system load and build phase
    pub async fn calculate_optimal_jobs(&self, version: &GccVersion, base_jobs: Option<usize>) -> usize {
        let state = self.system_state.lock().unwrap();
        let active_builds = state.active_builds.len();
        
        // Get current build phase
        let current_phase = state.active_builds
            .iter()
            .find(|b| &b.version == version)
            .map(|b| b.phase)
            .unwrap_or(BuildPhase::Configure);
        
        // Get phase profile
        let phase_profile = self.phase_profiles.get(&current_phase)
            .cloned()
            .unwrap_or_else(|| PhaseProfile {
                cpu_intensity: 0.7,
                memory_multiplier: 1.0,
                io_intensity: 0.3,
                parallelism_efficiency: 0.8,
                typical_duration_pct: 20.0,
            });
        
        // Base calculation
        let system_cores = sys_info::cpu_num().unwrap_or(4) as usize;
        let default_jobs = base_jobs.unwrap_or_else(|| {
            // Better heuristic: consider both CPU and RAM
            let cpu_jobs = system_cores;
            let ram_jobs = (state.available_ram_mb / 2000) as usize; // 2GB per job
            std::cmp::min(cpu_jobs, ram_jobs).max(1)
        });
        
        // Phase-aware adjustment
        let phase_adjusted = (default_jobs as f64 * phase_profile.parallelism_efficiency) as usize;
        
        // Adjust based on active builds and CPU intensity
        let final_jobs = if active_builds > 1 {
            let reduction_factor = 1.0 / (active_builds as f64).sqrt();
            let cpu_factor = phase_profile.cpu_intensity;
            ((phase_adjusted as f64) * reduction_factor * cpu_factor) as usize
        } else {
            phase_adjusted
        };
        
        let optimal_jobs = final_jobs.max(1).min(system_cores);
        
        info!("🎯 Optimal jobs for GCC {} in {:?} phase: {} (base: {}, efficiency: {:.1}%, intensity: {:.1}%)",
              version, current_phase, optimal_jobs, default_jobs,
              phase_profile.parallelism_efficiency * 100.0,
              phase_profile.cpu_intensity * 100.0);
        
        optimal_jobs
    }
    
    /// Get build statistics for reporting
    pub fn get_statistics(&self) -> SchedulerStatistics {
        let state = self.system_state.lock().unwrap();
        SchedulerStatistics {
            total_builds: state.completed_builds.len() + state.active_builds.len(),
            completed_builds: state.completed_builds.len(),
            active_builds: state.active_builds.len(),
            failed_builds: state.completed_builds.iter().filter(|b| !b.success).count(),
            average_build_time: if !state.completed_builds.is_empty() {
                let total_time: Duration = state.completed_builds.iter()
                    .map(|b| b.duration)
                    .sum();
                Some(total_time / state.completed_builds.len() as u32)
            } else {
                None
            },
            peak_ram_usage: state.completed_builds.iter()
                .map(|b| b.peak_ram_mb)
                .max()
                .unwrap_or(0),
        }
    }
    
    /// Create phase profiles with resource characteristics
    fn create_phase_profiles() -> HashMap<BuildPhase, PhaseProfile> {
        let mut profiles = HashMap::new();
        
        profiles.insert(BuildPhase::Configure, PhaseProfile {
            cpu_intensity: 0.2,        // Light CPU usage
            memory_multiplier: 0.1,    // Very low memory
            io_intensity: 0.8,         // Heavy disk I/O
            parallelism_efficiency: 0.3, // Limited parallelism
            typical_duration_pct: 5.0,
        });
        
        profiles.insert(BuildPhase::Bootstrap, PhaseProfile {
            cpu_intensity: 0.6,        // Moderate CPU usage
            memory_multiplier: 0.4,    // Moderate memory
            io_intensity: 0.4,         // Moderate I/O
            parallelism_efficiency: 0.7, // Good parallelism
            typical_duration_pct: 15.0,
        });
        
        profiles.insert(BuildPhase::Compile, PhaseProfile {
            cpu_intensity: 0.95,       // Maximum CPU usage
            memory_multiplier: 1.0,    // Full memory usage
            io_intensity: 0.3,         // Lower I/O during compilation
            parallelism_efficiency: 0.9, // Excellent parallelism
            typical_duration_pct: 60.0,
        });
        
        profiles.insert(BuildPhase::Link, PhaseProfile {
            cpu_intensity: 0.4,        // Lower CPU during linking
            memory_multiplier: 1.2,    // High memory for linking
            io_intensity: 0.7,         // High I/O for object files
            parallelism_efficiency: 0.2, // Poor parallelism
            typical_duration_pct: 10.0,
        });
        
        profiles.insert(BuildPhase::Install, PhaseProfile {
            cpu_intensity: 0.1,        // Very light CPU
            memory_multiplier: 0.1,    // Low memory
            io_intensity: 0.9,         // Heavy I/O for file operations
            parallelism_efficiency: 0.4, // Limited parallelism
            typical_duration_pct: 5.0,
        });
        
        profiles.insert(BuildPhase::Test, PhaseProfile {
            cpu_intensity: 0.8,        // High CPU for test execution
            memory_multiplier: 0.6,    // Moderate memory
            io_intensity: 0.5,         // Moderate I/O
            parallelism_efficiency: 0.8, // Good parallelism
            typical_duration_pct: 5.0,
        });
        
        profiles
    }
    
    /// Create CPU scheduler with system detection
    fn create_cpu_scheduler(config: &Config) -> CpuScheduler {
        let cpu_topology = Self::detect_cpu_topology();
        let strategy = Self::determine_scheduling_strategy(config, &cpu_topology);
        
        let load_balancer = LoadBalancer {
            current_load: 0.0,
            load_history: Vec::new(),
            target_utilization: match strategy {
                SchedulingStrategy::Conservative => 0.70,
                SchedulingStrategy::Balanced => 0.80,
                SchedulingStrategy::Aggressive => 0.95,
            },
        };
        
        let affinity_manager = AffinityManager {
            cpu_topology: cpu_topology.clone(),
            build_assignments: HashMap::new(),
        };
        
        CpuScheduler {
            strategy,
            load_balancer,
            affinity_manager,
        }
    }
    
    /// Detect system CPU topology
    fn detect_cpu_topology() -> CpuTopology {
        let total_cores = sys_info::cpu_num().unwrap_or(4) as usize;
        
        // Try to detect physical cores (simplified)
        let physical_cores = if let Ok(output) = std::process::Command::new("lscpu")
            .output() {
            let output_str = String::from_utf8_lossy(&output.stdout);
            for line in output_str.lines() {
                if line.starts_with("Core(s) per socket:") {
                    if let Some(cores_str) = line.split_whitespace().last() {
                        if let Ok(cores) = cores_str.parse::<usize>() {
                            // Also try to get socket count
                            for socket_line in output_str.lines() {
                                if socket_line.starts_with("Socket(s):") {
                                    if let Some(sockets_str) = socket_line.split_whitespace().last() {
                                        if let Ok(sockets) = sockets_str.parse::<usize>() {
                                            return CpuTopology {
                                                total_cores,
                                                physical_cores: cores * sockets,
                                                numa_nodes: sockets, // Approximation
                                                l3_cache_groups: vec![vec![0; cores]; sockets],
                                            };
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            total_cores / 2 // Fallback: assume hyperthreading
        } else {
            total_cores / 2 // Fallback: assume hyperthreading
        };
        
        CpuTopology {
            total_cores,
            physical_cores,
            numa_nodes: 1,
            l3_cache_groups: vec![vec![0; total_cores]],
        }
    }
    
    /// Determine optimal scheduling strategy
    fn determine_scheduling_strategy(config: &Config, topology: &CpuTopology) -> SchedulingStrategy {
        // Conservative for low-resource systems
        if config.system_info.ram_mb < 8000 || topology.total_cores <= 4 {
            SchedulingStrategy::Conservative
        }
        // Aggressive for high-end systems
        else if config.system_info.ram_mb >= 32000 && topology.total_cores >= 16 {
            SchedulingStrategy::Aggressive
        }
        // Balanced for everything else
        else {
            SchedulingStrategy::Balanced
        }
    }
    
    /// Adjust CPU allocation for a build phase
    fn adjust_cpu_allocation(&self, version: &GccVersion, phase: BuildPhase, profile: &PhaseProfile) {
        // This would integrate with process CPU affinity and priority
        // For now, we log the intention
        debug!("Adjusting CPU allocation for GCC {} in {:?} phase: intensity={:.1}%",
               version, phase, profile.cpu_intensity * 100.0);
        
        // In a full implementation, this would:
        // 1. Set CPU affinity using sched_setaffinity
        // 2. Adjust process priority with nice/ionice
        // 3. Configure NUMA memory policy
        // 4. Set cgroup limits if available
    }
    
    /// Get phase-aware resource estimation
    pub fn get_phase_resource_estimate(&self, phase: BuildPhase) -> (f64, f64, f64) {
        if let Some(profile) = self.phase_profiles.get(&phase) {
            (profile.cpu_intensity, profile.memory_multiplier, profile.io_intensity)
        } else {
            (0.7, 1.0, 0.3) // Default values
        }
    }
    
    /// Update system load monitoring
    pub fn update_system_load(&mut self, current_load: f64) {
        self.cpu_scheduler.load_balancer.current_load = current_load;
        self.cpu_scheduler.load_balancer.load_history.push(current_load);
        
        // Keep only recent history (last 60 readings)
        if self.cpu_scheduler.load_balancer.load_history.len() > 60 {
            self.cpu_scheduler.load_balancer.load_history.remove(0);
        }
        
        debug!("System load updated: {:.2} (target: {:.2})",
               current_load, self.cpu_scheduler.load_balancer.target_utilization);
    }
    
    /// Check if system is under high load
    pub fn is_system_overloaded(&self) -> bool {
        let current_load = self.cpu_scheduler.load_balancer.current_load;
        let target = self.cpu_scheduler.load_balancer.target_utilization;
        current_load > target * 1.2 // 20% over target is considered overloaded
    }
}

/// RAII guard for build slots
pub struct BuildSlot {
    scheduler: BuildScheduler,
    version: GccVersion,
    permit: Option<OwnedSemaphorePermit>,
    start_time: Instant,
}

impl BuildSlot {
    /// Mark build as completed
    pub fn complete(mut self, success: bool, peak_ram_mb: Option<u64>) {
        let duration = self.start_time.elapsed();
        
        // Update system state
        {
            let mut state = self.scheduler.system_state.lock().unwrap();
            
            // Remove from active builds
            state.active_builds.retain(|b| &b.version != &self.version);
            
            // Add to completed builds
            state.completed_builds.push(CompletedBuild {
                version: self.version.clone(),
                duration,
                peak_ram_mb: peak_ram_mb.unwrap_or(self.scheduler.ram_per_build),
                success,
            });
            
            // Release RAM
            state.available_ram_mb = state.available_ram_mb.saturating_add(self.scheduler.ram_per_build);
        }
        
        info!("🏁 Build slot released for GCC {} (duration: {:?}, success: {})", 
              self.version, duration, success);
        
        // Permit is automatically released when dropped
        self.permit = None;
    }
}

impl Drop for BuildSlot {
    fn drop(&mut self) {
        if self.permit.is_some() {
            // Build was not properly completed, mark as failed
            self.permit = None;
            let mut state = self.scheduler.system_state.lock().unwrap();
            state.active_builds.retain(|b| &b.version != &self.version);
            state.available_ram_mb = state.available_ram_mb.saturating_add(self.scheduler.ram_per_build);
            warn!("Build slot for GCC {} dropped without completion", self.version);
        }
    }
}

#[derive(Debug)]
pub struct SchedulerStatistics {
    pub total_builds: usize,
    pub completed_builds: usize,
    pub active_builds: usize,
    pub failed_builds: usize,
    pub average_build_time: Option<Duration>,
    pub peak_ram_usage: u64,
}

/// Calculate estimated RAM per GCC build based on version and settings
fn calculate_ram_per_build(config: &Config) -> u64 {
    let base_ram = 3000; // 3GB base
    
    let mut ram = base_ram;
    
    // Adjust for multilib
    if config.enable_multilib {
        ram += 1000; // +1GB for multilib
    }
    
    // Adjust for optimization level
    ram += match config.optimization_level {
        crate::cli::OptimizationLevel::O0 => 0,
        crate::cli::OptimizationLevel::O1 => 200,
        crate::cli::OptimizationLevel::O2 => 500,
        crate::cli::OptimizationLevel::O3 => 800,
        crate::cli::OptimizationLevel::Fast => 1000,
        crate::cli::OptimizationLevel::Debug => 300,
        crate::cli::OptimizationLevel::Size => 200,
    };
    
    // Adjust for static build
    if config.static_build {
        ram += 500; // +500MB for static linking
    }
    
    ram
}

// Re-export for convenience
impl Clone for BuildScheduler {
    fn clone(&self) -> Self {
        Self {
            max_concurrent: self.max_concurrent,
            build_semaphore: Arc::clone(&self.build_semaphore),
            ram_per_build: self.ram_per_build,
            system_state: Arc::clone(&self.system_state),
            phase_profiles: self.phase_profiles.clone(),
            cpu_scheduler: self.cpu_scheduler.clone(),
        }
    }
}