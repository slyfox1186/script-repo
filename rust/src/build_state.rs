#![allow(dead_code)]
use std::path::PathBuf;
use std::collections::HashMap;
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Local};
use log::{info, debug};
use crate::config::GccVersion;
use crate::error::{GccBuildError, Result as GccResult};

/// Manages build state for resume capability and incremental builds
#[derive(Clone)]
pub struct BuildStateManager {
    state_dir: PathBuf,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct BuildState {
    pub version: GccVersion,
    pub phases: HashMap<BuildPhase, PhaseState>,
    pub started_at: DateTime<Local>,
    pub last_updated: DateTime<Local>,
    pub build_dir: PathBuf,
    pub install_prefix: PathBuf,
    pub config_hash: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BuildPhase {
    Download,
    Extract,
    Prerequisites,
    Configure,
    Build,
    Install,
    PostInstall,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct PhaseState {
    pub status: PhaseStatus,
    pub started_at: Option<DateTime<Local>>,
    pub completed_at: Option<DateTime<Local>>,
    pub error: Option<String>,
    pub artifacts: Vec<String>,
    pub checkpoints: HashMap<String, String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq)]
pub enum PhaseStatus {
    NotStarted,
    InProgress,
    Completed,
    Failed,
}

impl BuildStateManager {
    pub fn new(state_dir: PathBuf) -> Self {
        Self { state_dir }
    }
    
    /// Initialize state directory
    pub async fn init(&self) -> GccResult<()> {
        tokio::fs::create_dir_all(&self.state_dir).await
            .map_err(|e| GccBuildError::directory_operation(
                "create state directory",
                self.state_dir.display().to_string(),
                e.to_string()
            ))?;
        Ok(())
    }
    
    /// Get state file path for a version
    fn state_file(&self, version: &GccVersion) -> PathBuf {
        self.state_dir.join(format!("gcc-{}-state.json", version))
    }
    
    /// Load build state for a version
    pub async fn load_state(&self, version: &GccVersion) -> GccResult<Option<BuildState>> {
        let state_file = self.state_file(version);
        
        if !state_file.exists() {
            return Ok(None);
        }
        
        let content = tokio::fs::read_to_string(&state_file).await
            .map_err(|e| GccBuildError::file_operation(
                "read state file",
                state_file.display().to_string(),
                e.to_string()
            ))?;
        
        let state: BuildState = serde_json::from_str(&content)
            .map_err(|e| GccBuildError::file_operation(
                "parse state file",
                state_file.display().to_string(),
                e.to_string()
            ))?;
        
        debug!("Loaded build state for GCC {}", version);
        Ok(Some(state))
    }
    
    /// Save build state
    pub async fn save_state(&self, state: &BuildState) -> GccResult<()> {
        let state_file = self.state_file(&state.version);
        
        let content = serde_json::to_string_pretty(state)
            .map_err(|e| GccBuildError::file_operation(
                "serialize state",
                state_file.display().to_string(),
                e.to_string()
            ))?;
        
        tokio::fs::write(&state_file, content).await
            .map_err(|e| GccBuildError::file_operation(
                "write state file",
                state_file.display().to_string(),
                e.to_string()
            ))?;
        
        debug!("Saved build state for GCC {}", state.version);
        Ok(())
    }
    
    /// Create new build state
    pub fn create_state(
        version: GccVersion,
        build_dir: PathBuf,
        install_prefix: PathBuf,
        config_hash: String,
    ) -> BuildState {
        let mut phases = HashMap::new();
        
        for phase in [
            BuildPhase::Download,
            BuildPhase::Extract,
            BuildPhase::Prerequisites,
            BuildPhase::Configure,
            BuildPhase::Build,
            BuildPhase::Install,
            BuildPhase::PostInstall,
        ] {
            phases.insert(phase, PhaseState {
                status: PhaseStatus::NotStarted,
                started_at: None,
                completed_at: None,
                error: None,
                artifacts: Vec::new(),
                checkpoints: HashMap::new(),
            });
        }
        
        BuildState {
            version,
            phases,
            started_at: Local::now(),
            last_updated: Local::now(),
            build_dir,
            install_prefix,
            config_hash,
        }
    }
    
    /// Update phase status
    pub async fn update_phase(
        &self,
        version: &GccVersion,
        phase: BuildPhase,
        status: PhaseStatus,
        error: Option<String>,
    ) -> GccResult<()> {
        let mut state = match self.load_state(version).await? {
            Some(s) => s,
            None => return Err(GccBuildError::configuration("No build state found")),
        };
        
        if let Some(phase_state) = state.phases.get_mut(&phase) {
            phase_state.status = status;
            phase_state.error = error;
            
            match status {
                PhaseStatus::InProgress => {
                    phase_state.started_at = Some(Local::now());
                }
                PhaseStatus::Completed | PhaseStatus::Failed => {
                    phase_state.completed_at = Some(Local::now());
                }
                _ => {}
            }
        }
        
        state.last_updated = Local::now();
        self.save_state(&state).await?;
        
        info!("Updated phase {:?} to {:?} for GCC {}", phase, status, version);
        Ok(())
    }
    
    /// Add checkpoint to phase
    pub async fn add_checkpoint(
        &self,
        version: &GccVersion,
        phase: BuildPhase,
        key: String,
        value: String,
    ) -> GccResult<()> {
        let mut state = match self.load_state(version).await? {
            Some(s) => s,
            None => return Err(GccBuildError::configuration("No build state found")),
        };
        
        if let Some(phase_state) = state.phases.get_mut(&phase) {
            phase_state.checkpoints.insert(key, value);
        }
        
        state.last_updated = Local::now();
        self.save_state(&state).await?;
        Ok(())
    }
    
    /// Check if build can be resumed
    pub async fn can_resume(&self, version: &GccVersion, config_hash: &str) -> GccResult<bool> {
        if let Some(state) = self.load_state(version).await? {
            // Check if configuration matches
            if state.config_hash != config_hash {
                info!("Configuration changed, cannot resume build for GCC {}", version);
                return Ok(false);
            }
            
            // Check if build directory still exists
            if !state.build_dir.exists() {
                info!("Build directory missing, cannot resume build for GCC {}", version);
                return Ok(false);
            }
            
            // Check if any phase failed
            for (phase, phase_state) in &state.phases {
                if phase_state.status == PhaseStatus::Failed {
                    info!("Phase {:?} failed, can resume from this point for GCC {}", phase, version);
                    return Ok(true);
                }
            }
            
            // Check if build is incomplete
            if state.phases.get(&BuildPhase::PostInstall)
                .map(|p| p.status != PhaseStatus::Completed)
                .unwrap_or(true) {
                return Ok(true);
            }
        }
        
        Ok(false)
    }
    
    /// Get resume point
    pub async fn get_resume_point(&self, version: &GccVersion) -> GccResult<Option<BuildPhase>> {
        if let Some(state) = self.load_state(version).await? {
            // Find first incomplete or failed phase
            for phase in [
                BuildPhase::Download,
                BuildPhase::Extract,
                BuildPhase::Prerequisites,
                BuildPhase::Configure,
                BuildPhase::Build,
                BuildPhase::Install,
                BuildPhase::PostInstall,
            ] {
                if let Some(phase_state) = state.phases.get(&phase) {
                    match phase_state.status {
                        PhaseStatus::NotStarted | PhaseStatus::InProgress | PhaseStatus::Failed => {
                            return Ok(Some(phase));
                        }
                        PhaseStatus::Completed => continue,
                    }
                }
            }
        }
        
        Ok(None)
    }
    
    /// Clean up state for a version
    pub async fn cleanup_state(&self, version: &GccVersion) -> GccResult<()> {
        let state_file = self.state_file(version);
        
        if state_file.exists() {
            tokio::fs::remove_file(&state_file).await
                .map_err(|e| GccBuildError::file_operation(
                    "remove state file",
                    state_file.display().to_string(),
                    e.to_string()
                ))?;
            info!("Cleaned up build state for GCC {}", version);
        }
        
        Ok(())
    }
    
    /// Get all saved build states
    pub async fn list_states(&self) -> GccResult<Vec<BuildState>> {
        let mut states = Vec::new();
        
        let mut entries = tokio::fs::read_dir(&self.state_dir).await
            .map_err(|e| GccBuildError::directory_operation(
                "read state directory",
                self.state_dir.display().to_string(),
                e.to_string()
            ))?;
        
        while let Some(entry) = entries.next_entry().await
            .map_err(|e| GccBuildError::directory_operation(
                "read directory entry",
                self.state_dir.display().to_string(),
                e.to_string()
            ))? {
            if let Some(name) = entry.file_name().to_str() {
                if name.ends_with("-state.json") {
                    let content = tokio::fs::read_to_string(entry.path()).await?;
                    if let Ok(state) = serde_json::from_str::<BuildState>(&content) {
                        states.push(state);
                    }
                }
            }
        }
        
        Ok(states)
    }
}

impl BuildPhase {
    pub fn all_phases() -> &'static [BuildPhase] {
        &[
            BuildPhase::Download,
            BuildPhase::Extract,
            BuildPhase::Prerequisites,
            BuildPhase::Configure,
            BuildPhase::Build,
            BuildPhase::Install,
            BuildPhase::PostInstall,
        ]
    }
    
    pub fn display_name(&self) -> &'static str {
        match self {
            BuildPhase::Download => "Downloading source",
            BuildPhase::Extract => "Extracting archive",
            BuildPhase::Prerequisites => "Downloading prerequisites",
            BuildPhase::Configure => "Configuring build",
            BuildPhase::Build => "Building GCC",
            BuildPhase::Install => "Installing GCC",
            BuildPhase::PostInstall => "Post-installation tasks",
        }
    }
}