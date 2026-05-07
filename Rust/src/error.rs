use thiserror::Error;

/// Custom error types for the GCC build process
#[derive(Error, Debug)]
#[allow(dead_code)]
pub enum BuildError {
    #[error("Failed to download {url}: {message}")]
    Download { url: String, message: String },

    #[error("Checksum verification failed for {file}: expected {expected}, got {actual}")]
    ChecksumMismatch {
        file: String,
        expected: String,
        actual: String,
    },

    #[error("GPG signature verification failed for {file}")]
    GpgVerificationFailed { file: String },

    #[error("Failed to extract archive {file}: {message}")]
    Extraction { file: String, message: String },

    #[error("Configure failed for GCC {version}: {message}")]
    Configure { version: String, message: String },

    #[error("Build (make) failed for GCC {version}: {message}")]
    Make { version: String, message: String },

    #[error("Installation failed for GCC {version}: {message}")]
    Install { version: String, message: String },

    #[error("Insufficient system resources: {message}")]
    InsufficientResources { message: String },

    #[error("Missing dependency: {package}")]
    MissingDependency { package: String },

    #[error("Failed to install dependencies: {message}")]
    DependencyInstall { message: String },

    #[error("Version lookup failed for GCC {major_version}: {message}")]
    VersionLookup { major_version: u32, message: String },

    #[error("Invalid version specification: {spec}")]
    InvalidVersionSpec { spec: String },

    #[error("No GCC versions selected")]
    NoVersionsSelected,

    #[error("Lock acquisition failed: another instance is running")]
    LockFailed,

    #[error("Command execution failed: {command}")]
    CommandFailed { command: String },

    #[error("IO error: {message}")]
    Io { message: String },

    #[error("Permission denied: {path}")]
    PermissionDenied { path: String },

    #[error("Script must not be run as root")]
    RunningAsRoot,

    #[error("Post-install task failed: {task}")]
    PostInstall { task: String },
}

impl From<std::io::Error> for BuildError {
    fn from(err: std::io::Error) -> Self {
        BuildError::Io {
            message: err.to_string(),
        }
    }
}

impl From<reqwest::Error> for BuildError {
    fn from(err: reqwest::Error) -> Self {
        BuildError::Download {
            url: err
                .url()
                .map(|u| u.to_string())
                .unwrap_or_else(|| "unknown".to_string()),
            message: err.to_string(),
        }
    }
}

/// Build status for tracking progress
#[derive(Debug, Clone, PartialEq, Eq)]
#[allow(dead_code)]
pub enum BuildStatus {
    Pending,
    Downloading,
    Extracting,
    Configuring,
    Building,
    Installing,
    PostInstall,
    Success,
    Failed(String),
    DryRun,
    Skipped(String),
}

impl std::fmt::Display for BuildStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BuildStatus::Pending => write!(f, "PENDING"),
            BuildStatus::Downloading => write!(f, "DOWNLOADING"),
            BuildStatus::Extracting => write!(f, "EXTRACTING"),
            BuildStatus::Configuring => write!(f, "CONFIGURING"),
            BuildStatus::Building => write!(f, "BUILDING"),
            BuildStatus::Installing => write!(f, "INSTALLING"),
            BuildStatus::PostInstall => write!(f, "POST_INSTALL"),
            BuildStatus::Success => write!(f, "SUCCESS"),
            BuildStatus::Failed(msg) => write!(f, "FAILED: {}", msg),
            BuildStatus::DryRun => write!(f, "DRY_RUN"),
            BuildStatus::Skipped(reason) => write!(f, "SKIPPED: {}", reason),
        }
    }
}
