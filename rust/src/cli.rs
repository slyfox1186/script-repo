use clap::Parser;
use std::path::PathBuf;

/// Build GNU GCC from source with async downloads and parallel builds
#[derive(Parser, Debug, Clone)]
#[command(name = "build-gcc", version, about, long_about = None)]
#[command(author = "slyfox1186")]
pub struct Args {
    /// GCC versions to build (e.g., "12,13,14" or "11-14" or "13")
    /// If not specified, interactive selection menu is shown
    #[arg(short = 'V', long, value_name = "VERSIONS")]
    pub versions: Option<String>,

    /// Enable debug mode (verbose shell command output)
    #[arg(long)]
    pub debug: bool,

    /// Perform a dry run without making any changes
    #[arg(long)]
    pub dry_run: bool,

    /// Enable multilib support for GCC (32-bit and 64-bit)
    #[arg(long)]
    pub enable_multilib: bool,

    /// Build static GCC executables
    #[arg(long, name = "static")]
    pub static_build: bool,

    /// Use generic tuning instead of native for GCC build
    #[arg(short, long)]
    pub generic: bool,

    /// Keep the temporary build directory after completion
    #[arg(short, long)]
    pub keep_build_dir: bool,

    /// Specify a log file for output
    #[arg(short, long, value_name = "FILE")]
    pub log_file: Option<PathBuf>,

    /// Set optimization level for building GCC (0, 1, 2, 3, fast, g, s)
    #[arg(short = 'O', default_value = "3", value_name = "LEVEL")]
    pub optimization: String,

    /// Set the installation prefix
    /// Default: /usr/local/programs/gcc-<version>
    #[arg(short, long, value_name = "DIR")]
    pub prefix: Option<PathBuf>,

    /// Save static binaries (only works with --static)
    #[arg(short, long)]
    pub save: bool,

    /// Enable verbose logging
    #[arg(short, long)]
    pub verbose: bool,

    /// Maximum number of GCC versions to build in parallel
    #[arg(long, default_value = "1", value_name = "N")]
    pub parallel: usize,
}

impl Args {
    /// Validate the command line arguments
    pub fn validate(&self) -> anyhow::Result<()> {
        // Validate optimization level
        match self.optimization.as_str() {
            "0" | "1" | "2" | "3" | "fast" | "g" | "s" => {}
            _ => {
                anyhow::bail!(
                    "Invalid optimization level: {}. Valid values are: 0, 1, 2, 3, fast, g, s",
                    self.optimization
                );
            }
        }

        // Validate --save requires --static
        if self.save && !self.static_build {
            anyhow::bail!("The --save option can only be used with --static");
        }

        // Validate prefix is absolute path if provided
        if let Some(ref prefix) = self.prefix {
            if !prefix.is_absolute() {
                anyhow::bail!(
                    "Prefix must be an absolute path starting with '/'. Value: {}",
                    prefix.display()
                );
            }
        }

        // Validate parallel is at least 1
        if self.parallel == 0 {
            anyhow::bail!("--parallel must be at least 1");
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_optimization_validation() {
        let args = Args {
            versions: None,
            debug: false,
            dry_run: false,
            enable_multilib: false,
            static_build: false,
            generic: false,
            keep_build_dir: false,
            log_file: None,
            optimization: "3".to_string(),
            prefix: None,
            save: false,
            verbose: false,
            parallel: 1,
        };
        assert!(args.validate().is_ok());
    }

    #[test]
    fn test_invalid_optimization() {
        let args = Args {
            versions: None,
            debug: false,
            dry_run: false,
            enable_multilib: false,
            static_build: false,
            generic: false,
            keep_build_dir: false,
            log_file: None,
            optimization: "invalid".to_string(),
            prefix: None,
            save: false,
            verbose: false,
            parallel: 1,
        };
        assert!(args.validate().is_err());
    }

    #[test]
    fn test_save_requires_static() {
        let args = Args {
            versions: None,
            debug: false,
            dry_run: false,
            enable_multilib: false,
            static_build: false,
            generic: false,
            keep_build_dir: false,
            log_file: None,
            optimization: "3".to_string(),
            prefix: None,
            save: true,
            verbose: false,
            parallel: 1,
        };
        assert!(args.validate().is_err());
    }
}
