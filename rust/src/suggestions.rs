use crate::error::GccBuildError;
use lazy_static::lazy_static;
use log::{debug, info};
use regex::Regex;

/// Suggestion engine for common build failures
pub struct SuggestionEngine {
    patterns: Vec<ErrorPattern>,
}

struct ErrorPattern {
    name: &'static str,
    regex: Regex,
    suggestions: Vec<Suggestion>,
}

#[derive(Clone, Debug)]
pub struct Suggestion {
    pub title: String,
    pub description: String,
    pub commands: Vec<String>,
    pub severity: SuggestionSeverity,
}

#[derive(Clone, Debug, PartialEq)]
pub enum SuggestionSeverity {
    Info,
    Warning,
    Error,
    Critical,
}

lazy_static! {
    static ref SUGGESTION_ENGINE: SuggestionEngine = SuggestionEngine::new();
}

impl SuggestionEngine {
    fn new() -> Self {
        let patterns = vec![
            // Missing dependencies
            ErrorPattern {
                name: "missing_gmp",
                regex: Regex::new(r"(?i)(gmp|libgmp).*not found|cannot find.*gmp").unwrap(),
                suggestions: vec![Suggestion {
                    title: "Install GMP development package".to_string(),
                    description: "GCC requires GMP (GNU Multiple Precision) library".to_string(),
                    commands: vec![
                        "# Ubuntu/Debian:".to_string(),
                        "sudo apt-get install libgmp-dev".to_string(),
                        "# RHEL/CentOS/Fedora:".to_string(),
                        "sudo yum install gmp-devel".to_string(),
                    ],
                    severity: SuggestionSeverity::Critical,
                }],
            },
            // Missing MPFR
            ErrorPattern {
                name: "missing_mpfr",
                regex: Regex::new(r"(?i)(mpfr|libmpfr).*not found|cannot find.*mpfr").unwrap(),
                suggestions: vec![Suggestion {
                    title: "Install MPFR development package".to_string(),
                    description: "GCC requires MPFR (Multiple Precision Floating-Point) library"
                        .to_string(),
                    commands: vec![
                        "# Ubuntu/Debian:".to_string(),
                        "sudo apt-get install libmpfr-dev".to_string(),
                        "# RHEL/CentOS/Fedora:".to_string(),
                        "sudo yum install mpfr-devel".to_string(),
                    ],
                    severity: SuggestionSeverity::Critical,
                }],
            },
            // Missing MPC
            ErrorPattern {
                name: "missing_mpc",
                regex: Regex::new(r"(?i)(mpc|libmpc).*not found|cannot find.*mpc").unwrap(),
                suggestions: vec![Suggestion {
                    title: "Install MPC development package".to_string(),
                    description: "GCC requires MPC (Multiple Precision Complex) library"
                        .to_string(),
                    commands: vec![
                        "# Ubuntu/Debian:".to_string(),
                        "sudo apt-get install libmpc-dev".to_string(),
                        "# RHEL/CentOS/Fedora:".to_string(),
                        "sudo yum install libmpc-devel".to_string(),
                    ],
                    severity: SuggestionSeverity::Critical,
                }],
            },
            // Out of memory
            ErrorPattern {
                name: "out_of_memory",
                regex: Regex::new(
                    r"(?i)out of memory|memory exhausted|cannot allocate|oom|killed.*signal 9",
                )
                .unwrap(),
                suggestions: vec![
                    Suggestion {
                        title: "Reduce parallel jobs".to_string(),
                        description: "The build ran out of memory. Try reducing parallelism."
                            .to_string(),
                        commands: vec![
                            "# Reduce parallel jobs:".to_string(),
                            "./gcc-builder --jobs 2 ...".to_string(),
                            "# Or use minimal preset:".to_string(),
                            "./gcc-builder --preset minimal ...".to_string(),
                        ],
                        severity: SuggestionSeverity::Error,
                    },
                    Suggestion {
                        title: "Add swap space".to_string(),
                        description: "Consider adding temporary swap space for the build"
                            .to_string(),
                        commands: vec![
                            "# Create 8GB swap file:".to_string(),
                            "sudo fallocate -l 8G /swapfile".to_string(),
                            "sudo chmod 600 /swapfile".to_string(),
                            "sudo mkswap /swapfile".to_string(),
                            "sudo swapon /swapfile".to_string(),
                        ],
                        severity: SuggestionSeverity::Warning,
                    },
                ],
            },
            // Disk space
            ErrorPattern {
                name: "disk_space",
                regex: Regex::new(r"(?i)no space left|disk full|ENOSPC").unwrap(),
                suggestions: vec![Suggestion {
                    title: "Free up disk space".to_string(),
                    description: "The build requires significant disk space (25GB+ per version)"
                        .to_string(),
                    commands: vec![
                        "# Check disk usage:".to_string(),
                        "df -h".to_string(),
                        "# Clean build directory:".to_string(),
                        "rm -rf /tmp/gcc-build-*".to_string(),
                        "# Use different build directory:".to_string(),
                        "./gcc-builder --build-dir /path/with/space ...".to_string(),
                    ],
                    severity: SuggestionSeverity::Critical,
                }],
            },
            // Permission denied
            ErrorPattern {
                name: "permission_denied",
                regex: Regex::new(r"(?i)permission denied|EACCES|cannot create.*directory")
                    .unwrap(),
                suggestions: vec![Suggestion {
                    title: "Check directory permissions".to_string(),
                    description: "Ensure you have write permissions to the installation directory"
                        .to_string(),
                    commands: vec![
                        "# Use a different prefix:".to_string(),
                        "./gcc-builder --prefix $HOME/gcc ...".to_string(),
                        "# Or fix permissions:".to_string(),
                        "sudo chown -R $USER:$USER /path/to/directory".to_string(),
                    ],
                    severity: SuggestionSeverity::Error,
                }],
            },
            // Network issues
            ErrorPattern {
                name: "network_error",
                regex: Regex::new(
                    r"(?i)connection.*refused|timeout|could not resolve|network.*unreachable",
                )
                .unwrap(),
                suggestions: vec![Suggestion {
                    title: "Check network connectivity".to_string(),
                    description: "Unable to download files. Check your internet connection."
                        .to_string(),
                    commands: vec![
                        "# Test connectivity:".to_string(),
                        "ping -c 4 ftp.gnu.org".to_string(),
                        "# Check DNS:".to_string(),
                        "nslookup ftp.gnu.org".to_string(),
                        "# Use proxy if needed:".to_string(),
                        "export https_proxy=http://proxy:port".to_string(),
                    ],
                    severity: SuggestionSeverity::Error,
                }],
            },
            // Configure errors
            ErrorPattern {
                name: "configure_error",
                regex: Regex::new(r"(?i)configure: error:|configuration failed").unwrap(),
                suggestions: vec![Suggestion {
                    title: "Check configure log".to_string(),
                    description: "Configuration failed. Check config.log for details.".to_string(),
                    commands: vec![
                        "# View configure log:".to_string(),
                        "less /tmp/gcc-build-*/workspace/gcc-*/build-gcc/config.log".to_string(),
                        "# Common fixes:".to_string(),
                        "# - Install missing development packages".to_string(),
                        "# - Use --disable-multilib if 32-bit libs missing".to_string(),
                    ],
                    severity: SuggestionSeverity::Error,
                }],
            },
            // Missing tools
            ErrorPattern {
                name: "missing_make",
                regex: Regex::new(r"(?i)make.*not found|gmake.*not found").unwrap(),
                suggestions: vec![Suggestion {
                    title: "Install build essentials".to_string(),
                    description: "Basic build tools are missing".to_string(),
                    commands: vec![
                        "# Ubuntu/Debian:".to_string(),
                        "sudo apt-get install build-essential".to_string(),
                        "# RHEL/CentOS/Fedora:".to_string(),
                        "sudo yum groupinstall 'Development Tools'".to_string(),
                    ],
                    severity: SuggestionSeverity::Critical,
                }],
            },
            // ISL version issues
            ErrorPattern {
                name: "isl_version",
                regex: Regex::new(r"(?i)isl.*version.*required|libisl").unwrap(),
                suggestions: vec![Suggestion {
                    title: "ISL version mismatch".to_string(),
                    description: "GCC requires a specific ISL version for Graphite optimizations"
                        .to_string(),
                    commands: vec![
                        "# Disable Graphite to avoid ISL:".to_string(),
                        "./gcc-builder --versions X ... # (ISL handled automatically)".to_string(),
                        "# Or install ISL:".to_string(),
                        "sudo apt-get install libisl-dev  # Ubuntu/Debian".to_string(),
                    ],
                    severity: SuggestionSeverity::Warning,
                }],
            },
        ];

        Self { patterns }
    }

    /// Analyze error and provide suggestions
    pub fn analyze(&self, error: &GccBuildError) -> Vec<Suggestion> {
        let error_text = error.to_string();
        let mut suggestions = Vec::new();
        let mut matched_patterns = Vec::new();

        // Check all patterns
        for pattern in &self.patterns {
            if pattern.regex.is_match(&error_text) {
                matched_patterns.push(pattern.name);
                suggestions.extend(pattern.suggestions.clone());
            }
        }

        if !matched_patterns.is_empty() {
            debug!("Matched error patterns: {:?}", matched_patterns);
        }

        // Add generic suggestions if no specific match
        if suggestions.is_empty() {
            suggestions.push(Suggestion {
                title: "Check build logs".to_string(),
                description: "Review the detailed build logs for more information".to_string(),
                commands: vec![
                    "# Enable verbose output:".to_string(),
                    "./gcc-builder --verbose --debug ...".to_string(),
                    "# Save logs to file:".to_string(),
                    "./gcc-builder --log-file build.log ...".to_string(),
                ],
                severity: SuggestionSeverity::Info,
            });
        }

        suggestions
    }

    /// Format suggestions for display
    pub fn format_suggestions(suggestions: &[Suggestion]) -> String {
        if suggestions.is_empty() {
            return String::new();
        }

        let mut output = String::from("\n💡 Suggestions to resolve this issue:\n");
        output.push_str("─".repeat(50).as_str());
        output.push('\n');

        for (i, suggestion) in suggestions.iter().enumerate() {
            let severity_icon = match suggestion.severity {
                SuggestionSeverity::Info => "ℹ️",
                SuggestionSeverity::Warning => "⚠️",
                SuggestionSeverity::Error => "❌",
                SuggestionSeverity::Critical => "🔴",
            };

            output.push_str(&format!(
                "\n{} {}. {}\n",
                severity_icon,
                i + 1,
                suggestion.title
            ));
            output.push_str(&format!("   {}\n", suggestion.description));

            if !suggestion.commands.is_empty() {
                output.push_str("\n   Commands:\n");
                for cmd in &suggestion.commands {
                    output.push_str(&format!("   {}\n", cmd));
                }
            }
        }

        output.push_str(&"─".repeat(50));
        output
    }
}

/// Get suggestions for an error
pub fn get_suggestions(error: &GccBuildError) -> Vec<Suggestion> {
    SUGGESTION_ENGINE.analyze(error)
}

/// Display suggestions for an error
pub fn display_suggestions(error: &GccBuildError) {
    let suggestions = get_suggestions(error);
    if !suggestions.is_empty() {
        let formatted = SuggestionEngine::format_suggestions(&suggestions);
        info!("{}", formatted);
    }
}
