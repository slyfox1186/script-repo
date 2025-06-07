#![allow(dead_code)]
use log::{debug, info};
use std::collections::HashMap;

use crate::config::{Config, GccVersion};
use crate::error::{GccBuildError, Result as GccResult};

#[derive(Debug, Clone)]
pub struct GccConfigGenerator {
    pub base_options: HashMap<String, String>,
    pub version_features: HashMap<String, Vec<String>>,
    pub feature_options: HashMap<String, String>,
}

impl GccConfigGenerator {
    pub fn new() -> Self {
        let base_options = Self::init_base_options();
        let version_features = Self::init_version_features();
        let feature_options = Self::init_feature_options();
        
        Self {
            base_options,
            version_features,
            feature_options,
        }
    }
    
    fn init_base_options() -> HashMap<String, String> {
        let mut options = HashMap::new();
        
        options.insert("languages".to_string(), "--enable-languages=all".to_string());
        options.insert("bootstrap".to_string(), "--disable-bootstrap".to_string());
        options.insert("checking".to_string(), "--enable-checking=release".to_string());
        options.insert("nls".to_string(), "--disable-nls".to_string());
        options.insert("shared".to_string(), "--enable-shared".to_string());
        options.insert("threads".to_string(), "--enable-threads=posix".to_string());
        options.insert("zlib".to_string(), "--with-system-zlib".to_string());
        options.insert("isl".to_string(), "--with-isl=/usr".to_string());
        options.insert("major_version_only".to_string(), "--with-gcc-major-version-only".to_string());
        
        options
    }
    
    fn init_version_features() -> HashMap<String, Vec<String>> {
        let mut features = HashMap::new();
        
        features.insert("9,10,11".to_string(), vec![
            "default_pie".to_string(),
            "gnu_unique_object".to_string(),
        ]);
        
        features.insert("12".to_string(), vec![
            "default_pie".to_string(),
            "gnu_unique_object".to_string(),
            "link_serialization".to_string(),
        ]);
        
        features.insert("13,14".to_string(), vec![
            "default_pie".to_string(),
            "gnu_unique_object".to_string(),
            "link_serialization".to_string(),
            "cet".to_string(),
        ]);
        
        features.insert("15".to_string(), vec![
            "default_pie".to_string(),
            "gnu_unique_object".to_string(),
            "link_serialization".to_string(),
            "cet".to_string(),
        ]);
        
        features
    }
    
    fn init_feature_options() -> HashMap<String, String> {
        let mut options = HashMap::new();
        
        options.insert("default_pie".to_string(), "--enable-default-pie".to_string());
        options.insert("gnu_unique_object".to_string(), "--enable-gnu-unique-object".to_string());
        options.insert("link_serialization".to_string(), "--with-link-serialization=2".to_string());
        options.insert("cet".to_string(), "--enable-cet".to_string());
        options.insert("multilib_enable".to_string(), "--enable-multilib".to_string());
        options.insert("multilib_disable".to_string(), "--disable-multilib".to_string());
        
        options
    }
    
    /// Generate configure options for a specific GCC version
    pub fn get_gcc_configure_options(
        &self,
        gcc_version: &GccVersion,
        config: &Config,
    ) -> GccResult<Vec<String>> {
        let install_prefix = config.get_install_prefix(gcc_version);
        let mut options = Vec::new();
        
        // Add prefix
        options.push(format!("--prefix={}", install_prefix.display()));
        
        // Add build/host/target architecture
        options.push(format!("--build={}", config.target_arch));
        options.push(format!("--host={}", config.target_arch));
        options.push(format!("--target={}", config.target_arch));
        
        // Add program suffix
        options.push(format!("--program-suffix=-{}", gcc_version.major));
        
        // Add base options
        for (_, option) in &self.base_options {
            options.push(option.clone());
        }
        
        // Add multilib option
        if config.enable_multilib {
            options.push(self.feature_options["multilib_enable"].clone());
        } else {
            options.push(self.feature_options["multilib_disable"].clone());
        }
        
        // Add version-specific features
        for (version_range, features) in &self.version_features {
            if self.version_matches(gcc_version.major, version_range) {
                for feature in features {
                    if let Some(option) = self.feature_options.get(feature) {
                        options.push(option.clone());
                    }
                }
                break;
            }
        }
        
        // Add tuning options
        if config.generic_tuning {
            options.push("--with-tune=generic".to_string());
        }
        
        // Add CUDA support if available
        if let Some(cuda_option) = self.detect_cuda_support()? {
            options.push(cuda_option);
        }
        
        debug!("Generated {} configure options for GCC {}", options.len(), gcc_version);
        Ok(options)
    }
    
    /// Check if version matches version range (e.g., "13" matches "13,14")
    fn version_matches(&self, version: u8, range: &str) -> bool {
        let versions: Vec<u8> = range.split(',')
            .filter_map(|v| v.trim().parse().ok())
            .collect();
        
        versions.contains(&version)
    }
    
    /// Detect CUDA support and return appropriate configure option
    fn detect_cuda_support(&self) -> GccResult<Option<String>> {
        // Check if nvcc is available
        let nvcc_check = std::process::Command::new("which")
            .arg("nvcc")
            .output();
        
        match nvcc_check {
            Ok(output) if output.status.success() => {
                let nvcc_path_bytes = String::from_utf8_lossy(&output.stdout);
                let nvcc_path = nvcc_path_bytes.trim();
                if !nvcc_path.is_empty() {
                    info!("CUDA (nvcc) found at: {}", nvcc_path);
                    
                    // Try to get CUDA installation directory
                    if let Some(cuda_dir) = self.get_cuda_directory(nvcc_path) {
                        Ok(Some(format!("--enable-offload-targets=nvptx-none={}", cuda_dir)))
                    } else {
                        // Generic CUDA support without specific path
                        Ok(Some("--enable-offload-targets=nvptx-none".to_string()))
                    }
                } else {
                    Ok(None)
                }
            }
            _ => {
                debug!("CUDA (nvcc) not found. nvptx offload target will not be configured.");
                Ok(None)
            }
        }
    }
    
    /// Get CUDA installation directory from nvcc path
    fn get_cuda_directory(&self, nvcc_path: &str) -> Option<String> {
        // nvcc is typically at /usr/local/cuda/bin/nvcc
        // So CUDA directory would be /usr/local/cuda
        if let Some(bin_pos) = nvcc_path.rfind("/bin/nvcc") {
            Some(nvcc_path[..bin_pos].to_string())
        } else {
            None
        }
    }
    
    /// Get configure options as a formatted string for logging
    pub fn format_configure_command(
        &self,
        gcc_version: &GccVersion,
        config: &Config,
    ) -> GccResult<String> {
        let options = self.get_gcc_configure_options(gcc_version, config)?;
        
        let mut command = String::from("../configure");
        for option in options {
            command.push_str(" \\\n    ");
            command.push_str(&option);
        }
        
        Ok(command)
    }
    
    /// Validate configure options
    pub fn validate_configure_options(
        &self,
        gcc_version: &GccVersion,
        config: &Config,
    ) -> GccResult<()> {
        let options = self.get_gcc_configure_options(gcc_version, config)?;
        
        // Check for conflicting options
        let has_multilib_enable = options.iter().any(|opt| opt == "--enable-multilib");
        let has_multilib_disable = options.iter().any(|opt| opt == "--disable-multilib");
        
        if has_multilib_enable && has_multilib_disable {
            return Err(GccBuildError::configuration(
                "Conflicting multilib options detected".to_string()
            ));
        }
        
        // Check that essential options are present
        let required_options = [
            "--prefix=",
            "--build=",
            "--host=",
            "--target=",
            "--enable-languages=",
        ];
        
        for required in &required_options {
            if !options.iter().any(|opt| opt.starts_with(required)) {
                return Err(GccBuildError::configuration(
                    format!("Missing required configure option: {}", required)
                ));
            }
        }
        
        info!("Configure options validation passed for GCC {}", gcc_version);
        Ok(())
    }
    
    /// Get environment variables for GCC build
    pub fn get_build_environment(&self, config: &Config) -> HashMap<String, String> {
        let mut env = HashMap::new();
        
        // Basic compiler settings
        env.insert("CC".to_string(), "gcc".to_string());
        env.insert("CXX".to_string(), "g++".to_string());
        
        // Build flags
        let cflags = config.build_settings.cflags.join(" ");
        let cxxflags = config.build_settings.cxxflags.join(" ");
        let cppflags = config.build_settings.cppflags.join(" ");
        let ldflags = config.build_settings.ldflags.join(" ");
        
        env.insert("CFLAGS".to_string(), cflags);
        env.insert("CXXFLAGS".to_string(), cxxflags);
        env.insert("CPPFLAGS".to_string(), cppflags);
        env.insert("LDFLAGS".to_string(), ldflags);
        
        // Parallel build settings
        env.insert("MAKEFLAGS".to_string(), format!("-j{}", config.parallel_jobs));
        
        // Add custom environment variables from config
        for (key, value) in &config.build_settings.env_vars {
            env.insert(key.clone(), value.clone());
        }
        
        env
    }
    
    /// Get language-specific configure options
    pub fn get_language_options(&self, languages: &[&str]) -> Vec<String> {
        if languages.is_empty() || languages.contains(&"all") {
            vec!["--enable-languages=all".to_string()]
        } else {
            vec![format!("--enable-languages={}", languages.join(","))]
        }
    }
    
    /// Get optimization-specific configure options
    pub fn get_optimization_options(&self, _config: &Config) -> Vec<String> {
        let mut options = Vec::new();
        
        // Add LTO support for newer versions
        options.push("--enable-lto".to_string());
        
        // Add plugin support
        options.push("--enable-plugin".to_string());
        
        // Add libgomp (OpenMP) support
        options.push("--enable-libgomp".to_string());
        
        options
    }
    
    /// Get security-related configure options
    pub fn get_security_options(&self) -> Vec<String> {
        vec![
            "--enable-default-ssp".to_string(),
            "--enable-default-pie".to_string(),
        ]
    }
}

impl Default for GccConfigGenerator {
    fn default() -> Self {
        Self::new()
    }
}

/// Convenience function to generate configure options
pub fn get_configure_options(
    gcc_version: &GccVersion,
    config: &Config,
) -> GccResult<Vec<String>> {
    let generator = GccConfigGenerator::new();
    generator.get_gcc_configure_options(gcc_version, config)
}

/// Convenience function to get build environment
pub fn get_build_environment(config: &Config) -> HashMap<String, String> {
    let generator = GccConfigGenerator::new();
    generator.get_build_environment(config)
}