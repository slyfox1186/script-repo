use crate::cli::Args;
use std::path::PathBuf;

/// Available GCC major versions
pub const AVAILABLE_VERSIONS: &[u32] = &[10, 11, 12, 13, 14, 15];

/// Script version (matching the bash script)
pub const SCRIPT_VERSION: &str = "2.6";

/// Default installation prefix base
pub const DEFAULT_PREFIX_BASE: &str = "/usr/local/programs";

/// Minimum required RAM in MB
pub const MIN_RAM_MB: u64 = 2000;

/// Estimated disk space per GCC version in GB
pub const DISK_SPACE_PER_VERSION_GB: u64 = 25;

/// Version cache TTL in seconds (1 hour)
pub const VERSION_CACHE_TTL_SECS: u64 = 3600;

/// Maximum download retry attempts
pub const MAX_DOWNLOAD_ATTEMPTS: u32 = 3;

/// GCC version information
#[derive(Debug, Clone)]
pub struct GccVersion {
    /// Major version number (e.g., 13)
    pub major: u32,
    /// Full version string (e.g., "13.2.0")
    pub full: String,
}

impl GccVersion {
    pub fn new(major: u32, full: String) -> Self {
        Self { major, full }
    }

    /// Get the installation prefix for this version
    pub fn install_prefix(&self, user_prefix: Option<&PathBuf>) -> PathBuf {
        if let Some(prefix) = user_prefix {
            prefix.join(format!("gcc-{}", self.full))
        } else {
            PathBuf::from(format!("{}/gcc-{}", DEFAULT_PREFIX_BASE, self.full))
        }
    }

    /// Get the tarball filename
    pub fn tarball_name(&self) -> String {
        format!("gcc-{}.tar.xz", self.full)
    }
}

impl std::fmt::Display for GccVersion {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "GCC {}", self.full)
    }
}

/// Build configuration derived from CLI arguments
#[derive(Debug, Clone)]
pub struct BuildConfig {
    pub dry_run: bool,
    pub enable_multilib: bool,
    pub static_build: bool,
    pub generic: bool,
    pub keep_build_dir: bool,
    pub optimization: String,
    pub prefix: Option<PathBuf>,
    pub save_binaries: bool,
    pub parallel: usize,
    pub target_arch: String,
    pub build_dir: PathBuf,
    pub workspace: PathBuf,
}

impl BuildConfig {
    /// Create a new BuildConfig from CLI args and detected system info
    pub fn from_args(args: &Args, build_dir: PathBuf, target_arch: String) -> Self {
        let workspace = build_dir.join("workspace");
        Self {
            dry_run: args.dry_run,
            enable_multilib: args.enable_multilib,
            static_build: args.static_build,
            generic: args.generic,
            keep_build_dir: args.keep_build_dir,
            optimization: args.optimization.clone(),
            prefix: args.prefix.clone(),
            save_binaries: args.save,
            parallel: args.parallel,
            target_arch,
            build_dir,
            workspace,
        }
    }

    /// Get the optimization flag
    pub fn optimization_flag(&self) -> String {
        format!("-O{}", self.optimization)
    }

    /// Get CFLAGS for the build
    pub fn cflags(&self) -> String {
        let mut flags = format!("{} -pipe", self.optimization_flag());

        if !self.generic {
            flags.push_str(" -march=native");
        }

        flags.push_str(" -fstack-protector-strong");
        flags
    }

    /// Get CXXFLAGS for the build
    pub fn cxxflags(&self) -> String {
        self.cflags()
    }

    /// Get CPPFLAGS for the build
    pub fn cppflags(&self) -> String {
        "-D_FORTIFY_SOURCE=2".to_string()
    }

    /// Get LDFLAGS for the build
    pub fn ldflags(&self) -> String {
        let mut flags = String::new();

        if self.static_build {
            flags.push_str("-static ");
        }

        flags.push_str("-Wl,-z,relro -Wl,-z,now");

        // Add library path for target architecture
        let lib_path = format!("/usr/lib/{}", self.target_arch);
        if PathBuf::from(&lib_path).exists() {
            flags.push_str(&format!(" -L{}", lib_path));
        } else if PathBuf::from("/usr/lib64").exists() && self.target_arch.contains("64") {
            flags.push_str(" -L/usr/lib64");
        } else if PathBuf::from("/usr/lib").exists() {
            flags.push_str(" -L/usr/lib");
        }

        flags
    }
}

/// Required system packages for building GCC
pub const REQUIRED_PACKAGES: &[&str] = &[
    "build-essential",
    "binutils",
    "gawk",
    "m4",
    "flex",
    "bison",
    "texinfo",
    "patch",
    "curl",
    "wget",
    "ca-certificates",
    "ccache",
    "libtool",
    "libtool-bin",
    "autoconf",
    "automake",
    "zlib1g-dev",
    "libisl-dev",
    "libzstd-dev",
];

/// Additional packages for multilib support
pub const MULTILIB_PACKAGES: &[&str] = &["libc6-dev-i386"];
