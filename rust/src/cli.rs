use clap::{ArgGroup, Parser, ValueEnum};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "gcc-builder")]
#[command(about = "A high-performance GCC build automation tool")]
#[command(version = env!("CARGO_PKG_VERSION"))]
#[command(author = "GCC Builder Team")]
#[command(group(
    ArgGroup::new("version-selection")
        .required(false)
        .args(&["versions", "latest", "all_supported", "preset"])
))]
pub struct Args {
    /// Enable debug mode with verbose command logging
    #[arg(long, help = "Enable debug mode (set -x, logs every executed command)")]
    pub debug: bool,

    /// Perform a dry run without making any changes
    #[arg(long, help = "Perform a dry run without making any changes")]
    pub dry_run: bool,

    /// Enable multilib support for GCC
    #[arg(
        long,
        help = "Enable multilib support for GCC (passed to GCC's configure)"
    )]
    pub enable_multilib: bool,

    /// Build static GCC executables
    #[arg(long, help = "Build static GCC executables")]
    pub static_build: bool,

    /// Use generic tuning instead of native for GCC build
    #[arg(
        short = 'g',
        long,
        help = "Use generic tuning instead of native for GCC build"
    )]
    pub generic: bool,

    /// Keep the temporary build directory after completion
    #[arg(
        short = 'k',
        long,
        help = "Keep the temporary build directory after completion"
    )]
    pub keep_build_dir: bool,

    /// Specify a log file for output
    #[arg(
        short = 'l',
        long,
        value_name = "FILE",
        help = "Specify a log file for output"
    )]
    pub log_file: Option<PathBuf>,

    /// Set optimization level for building GCC
    #[arg(
        short = 'O',
        value_enum,
        default_value = "2",
        help = "Set optimization level for building GCC"
    )]
    pub optimization: OptimizationLevel,

    /// Set the installation prefix
    #[arg(
        short = 'p',
        long,
        value_name = "DIR",
        help = "Set the installation prefix"
    )]
    pub prefix: Option<PathBuf>,

    /// Save static binaries (only works with --static)
    #[arg(
        short = 's',
        long,
        help = "Save static binaries (only works with --static-build)"
    )]
    pub save_binaries: bool,

    /// Enable verbose logging
    #[arg(short = 'v', long, help = "Enable verbose logging to stdout/stderr")]
    pub verbose: bool,

    /// GCC versions to build (comma-separated or ranges like 11-13)
    #[arg(
        long,
        value_name = "VERSIONS",
        help = "GCC versions to build (e.g., '11,13' or '11-13')"
    )]
    pub versions: Option<String>,

    /// Build the latest stable GCC version
    #[arg(long, help = "Build the latest stable GCC version")]
    pub latest: bool,

    /// Build all currently supported GCC versions
    #[arg(
        long,
        help = "Build all currently supported GCC versions (dynamically detected)"
    )]
    pub all_supported: bool,

    /// Use a build preset configuration
    #[arg(long, value_enum, help = "Use a predefined build configuration preset")]
    pub preset: Option<BuildPreset>,

    /// Number of parallel build jobs
    #[arg(
        short = 'j',
        long,
        value_name = "N",
        help = "Number of parallel build jobs (default: auto-detect)"
    )]
    pub jobs: Option<usize>,

    /// Build directory location
    #[arg(long, value_name = "DIR", help = "Temporary build directory location")]
    pub build_dir: Option<PathBuf>,

    /// Maximum download retries
    #[arg(
        long,
        default_value = "3",
        help = "Maximum number of download retry attempts"
    )]
    pub max_retries: usize,

    /// Download timeout in seconds
    #[arg(long, default_value = "300", help = "Download timeout in seconds")]
    pub download_timeout: u64,

    /// Skip checksum verification
    #[arg(long, help = "Skip checksum verification of downloaded files")]
    pub skip_checksum: bool,

    /// Force rebuild even if installation exists
    #[arg(long, help = "Force rebuild even if installation already exists")]
    pub force_rebuild: bool,

    /// Create symlinks in /usr/local/bin for GCC binaries
    #[arg(
        long,
        help = "Create symlinks in /usr/local/bin for all GCC binaries (requires sudo)"
    )]
    pub create_symlinks: bool,

    /// Skip creating symlinks (overrides default behavior)
    #[arg(
        long,
        conflicts_with = "create_symlinks",
        help = "Skip creating symlinks in /usr/local/bin"
    )]
    pub skip_symlinks: bool,

    /// Verification level for existing installations
    #[arg(
        long,
        value_enum,
        default_value = "fast",
        help = "Level of verification for existing GCC installations"
    )]
    pub verify_level: VerificationLevel,

    /// Directory to save static binaries (only with --save-binaries)
    #[arg(
        long,
        value_name = "DIR",
        help = "Directory to save static binaries (default: /usr/local/static-binaries)"
    )]
    pub static_binaries_dir: Option<PathBuf>,
}

#[derive(ValueEnum, Clone, Debug)]
pub enum VerificationLevel {
    /// Quick: Check file exists and is executable
    #[value(name = "quick")]
    Quick,
    /// Fast: Quick + run --version (default)
    #[value(name = "fast")]
    Fast,
    /// Full: Fast + compile test program
    #[value(name = "full")]
    Full,
}

impl From<VerificationLevel> for crate::binary_verifier::VerificationLevel {
    fn from(level: VerificationLevel) -> Self {
        match level {
            VerificationLevel::Quick => crate::binary_verifier::VerificationLevel::Quick,
            VerificationLevel::Fast => crate::binary_verifier::VerificationLevel::Fast,
            VerificationLevel::Full => crate::binary_verifier::VerificationLevel::Full,
        }
    }
}

#[derive(ValueEnum, Clone, Debug)]
pub enum OptimizationLevel {
    #[value(name = "0")]
    O0,
    #[value(name = "1")]
    O1,
    #[value(name = "2")]
    O2,
    #[value(name = "3")]
    O3,
    #[value(name = "fast")]
    Fast,
    #[value(name = "g")]
    Debug,
    #[value(name = "s")]
    Size,
}

#[derive(ValueEnum, Clone, Debug)]
pub enum BuildPreset {
    /// Minimal build for testing (latest GCC, no multilib, -O2)
    #[value(name = "minimal")]
    Minimal,

    /// Development build (latest GCC, multilib, debug symbols, -Og)
    #[value(name = "development")]
    Development,

    /// Production build (latest stable, static, -O3, generic tuning)
    #[value(name = "production")]
    Production,

    /// CI/CD optimized build (fast compile, -O1, no static)
    #[value(name = "ci")]
    Ci,

    /// Cross-compilation ready (multilib, generic, latest 3 versions)
    #[value(name = "cross")]
    Cross,
}

impl OptimizationLevel {
    pub fn as_str(&self) -> &'static str {
        match self {
            OptimizationLevel::O0 => "-O0",
            OptimizationLevel::O1 => "-O1",
            OptimizationLevel::O2 => "-O2",
            OptimizationLevel::O3 => "-O3",
            OptimizationLevel::Fast => "-Ofast",
            OptimizationLevel::Debug => "-Og",
            OptimizationLevel::Size => "-Os",
        }
    }
}

impl PartialEq<&str> for OptimizationLevel {
    fn eq(&self, other: &&str) -> bool {
        matches!(
            (self, *other),
            (OptimizationLevel::O0, "O0")
                | (OptimizationLevel::O1, "O1")
                | (OptimizationLevel::O2, "O2")
                | (OptimizationLevel::O3, "O3")
                | (OptimizationLevel::Fast, "fast")
                | (OptimizationLevel::Debug, "g")
                | (OptimizationLevel::Size, "s")
        )
    }
}

impl std::fmt::Display for OptimizationLevel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OptimizationLevel::O0 => write!(f, "O0"),
            OptimizationLevel::O1 => write!(f, "O1"),
            OptimizationLevel::O2 => write!(f, "O2"),
            OptimizationLevel::O3 => write!(f, "O3"),
            OptimizationLevel::Fast => write!(f, "fast"),
            OptimizationLevel::Debug => write!(f, "g"),
            OptimizationLevel::Size => write!(f, "s"),
        }
    }
}

impl Args {
    pub fn validate(&self) -> Result<(), String> {
        // Validate save_binaries only works with static_build
        if self.save_binaries && !self.static_build {
            return Err(
                "The --save-binaries option can only be used with --static-build".to_string(),
            );
        }

        // Validate prefix is absolute path if provided
        if let Some(prefix) = &self.prefix {
            if !prefix.is_absolute() {
                return Err("Prefix must be an absolute path".to_string());
            }
        }

        // Validate build directory is absolute if provided
        if let Some(build_dir) = &self.build_dir {
            if !build_dir.is_absolute() {
                return Err("Build directory must be an absolute path".to_string());
            }
        }

        // Validate jobs count
        if let Some(jobs) = self.jobs {
            if jobs == 0 {
                return Err("Number of jobs must be greater than 0".to_string());
            }
        }

        Ok(())
    }

    /// Get the effective versions string based on flags
    pub fn get_versions_string(&self) -> String {
        use crate::config::{MAX_GCC_VERSION, MIN_GCC_VERSION};

        if let Some(preset) = &self.preset {
            match preset {
                BuildPreset::Minimal
                | BuildPreset::Development
                | BuildPreset::Production
                | BuildPreset::Ci => "latest".to_string(),
                BuildPreset::Cross => {
                    // Latest 3 versions dynamically
                    let max = *MAX_GCC_VERSION.read().unwrap();
                    if max >= MIN_GCC_VERSION + 2 {
                        format!("{}-{}", max - 2, max)
                    } else {
                        format!("{}-{}", MIN_GCC_VERSION, max)
                    }
                }
            }
        } else if self.latest {
            "latest".to_string()
        } else if self.all_supported {
            let max = *MAX_GCC_VERSION.read().unwrap();
            format!("{}-{}", MIN_GCC_VERSION, max)
        } else {
            self.versions.clone().unwrap_or_default()
        }
    }

    /// Apply preset configurations
    pub fn apply_preset(&mut self) {
        if let Some(preset) = &self.preset {
            match preset {
                BuildPreset::Minimal => {
                    self.enable_multilib = false;
                    self.optimization = OptimizationLevel::O2;
                    self.static_build = false;
                }
                BuildPreset::Development => {
                    self.enable_multilib = true;
                    self.optimization = OptimizationLevel::Debug;
                    self.static_build = false;
                    self.verbose = true;
                }
                BuildPreset::Production => {
                    self.static_build = true;
                    self.optimization = OptimizationLevel::O3;
                    self.generic = true;
                    self.enable_multilib = false;
                }
                BuildPreset::Ci => {
                    self.optimization = OptimizationLevel::O1;
                    self.static_build = false;
                    self.enable_multilib = false;
                }
                BuildPreset::Cross => {
                    self.enable_multilib = true;
                    self.generic = true;
                    self.optimization = OptimizationLevel::O2;
                }
            }
        }
    }
}
