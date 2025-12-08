use crate::config::BuildConfig;
use std::collections::HashMap;
use std::env;
use std::path::Path;
use tracing::{debug, info};

/// Set up the PATH environment variable
pub fn setup_path(workspace: &Path) {
    info!("Setting PATH...");

    let current_path = env::var("PATH").unwrap_or_default();
    let workspace_bin = workspace.join("bin");

    // Prepend ccache and workspace bin to PATH
    let new_path = format!(
        "/usr/lib/ccache:{}:{}",
        workspace_bin.display(),
        current_path
    );

    env::set_var("PATH", &new_path);
    debug!("Updated PATH: {}", new_path);
}

/// Set up the PKG_CONFIG_PATH environment variable
pub fn setup_pkg_config_path(target_arch: &str) {
    info!("Setting PKG_CONFIG_PATH...");

    let mut paths = vec![
        "/usr/local/lib/pkgconfig".to_string(),
        "/usr/local/lib64/pkgconfig".to_string(),
        "/usr/local/share/pkgconfig".to_string(),
        "/usr/lib/pkgconfig".to_string(),
        "/usr/lib64/pkgconfig".to_string(),
        "/usr/share/pkgconfig".to_string(),
        // CUDA paths
        "/usr/local/cuda/lib64/pkgconfig".to_string(),
        "/usr/local/cuda/lib/pkgconfig".to_string(),
        "/opt/cuda/lib64/pkgconfig".to_string(),
        "/opt/cuda/lib/pkgconfig".to_string(),
        // Arch-specific paths
        format!("/usr/lib/{}/pkgconfig", target_arch),
    ];

    // Add common cross-compile paths for x86_64
    if target_arch == "x86_64-linux-gnu" {
        paths.extend([
            "/usr/lib/i386-linux-gnu/pkgconfig".to_string(),
            "/usr/lib/arm-linux-gnueabihf/pkgconfig".to_string(),
            "/usr/lib/aarch64-linux-gnu/pkgconfig".to_string(),
        ]);
    }

    // Get existing PKG_CONFIG_PATH
    let existing = env::var("PKG_CONFIG_PATH").unwrap_or_default();

    // Build new path
    let new_path = if existing.is_empty() {
        paths.join(":")
    } else {
        format!("{}:{}", paths.join(":"), existing)
    };

    env::set_var("PKG_CONFIG_PATH", &new_path);
    debug!("Updated PKG_CONFIG_PATH: {}", new_path);
}

/// Get environment variables for the build
pub fn get_build_env(config: &BuildConfig) -> HashMap<String, String> {
    let mut env = HashMap::new();

    // Compiler settings
    env.insert("CC".to_string(), "gcc".to_string());
    env.insert("CXX".to_string(), "g++".to_string());

    // Flags
    env.insert("CFLAGS".to_string(), config.cflags());
    env.insert("CXXFLAGS".to_string(), config.cxxflags());
    env.insert("CPPFLAGS".to_string(), config.cppflags());
    env.insert("LDFLAGS".to_string(), config.ldflags());

    // Copy current PATH and PKG_CONFIG_PATH
    if let Ok(path) = env::var("PATH") {
        env.insert("PATH".to_string(), path);
    }
    if let Ok(pkg_config) = env::var("PKG_CONFIG_PATH") {
        env.insert("PKG_CONFIG_PATH".to_string(), pkg_config);
    }

    debug!("Build environment: CC=gcc, CXX=g++");
    debug!("CFLAGS={}", config.cflags());
    debug!("CXXFLAGS={}", config.cxxflags());
    debug!("CPPFLAGS={}", config.cppflags());
    debug!("LDFLAGS={}", config.ldflags());

    env
}

/// Set all build environment variables
pub fn setup_environment(config: &BuildConfig) {
    info!("Setting build environment variables...");

    setup_path(&config.workspace);
    setup_pkg_config_path(&config.target_arch);

    // Set compiler and flags
    env::set_var("CC", "gcc");
    env::set_var("CXX", "g++");
    env::set_var("CFLAGS", config.cflags());
    env::set_var("CXXFLAGS", config.cxxflags());
    env::set_var("CPPFLAGS", config.cppflags());
    env::set_var("LDFLAGS", config.ldflags());

    info!("Build environment configured");
}
