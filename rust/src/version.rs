//! GCC version detection and selection module.
//!
//! Provides functionality to detect available GCC versions from the GNU FTP server,
//! cache version information, parse version specifications, and interactive selection.

use crate::config::{GccVersion, AVAILABLE_VERSIONS, VERSION_CACHE_TTL_SECS};
use crate::error::BuildError;
use crate::http_client::get_client;
use anyhow::{Context, Result};
use dialoguer::{theme::ColorfulTheme, MultiSelect, Select};
use regex::Regex;
use std::collections::HashSet;
use std::fs;
use std::path::Path;
use std::time::{Duration, SystemTime};
use tracing::{debug, info, instrument, warn};

/// Official GCC FTP server (confirmed working)
const GCC_FTP_URL: &str = "https://gcc.gnu.org/ftp/gcc/releases";

/// Known latest versions as fallback when server lookup fails
fn get_known_version(major: u32) -> Option<&'static str> {
    match major {
        10 => Some("10.5.0"),
        11 => Some("11.5.0"),
        12 => Some("12.4.0"),
        13 => Some("13.3.0"),
        14 => Some("14.2.0"),
        15 => Some("15.2.0"),
        _ => None,
    }
}

/// Fetch the latest release version for a GCC major version
#[instrument(skip(cache_dir), fields(major, cache_dir = %cache_dir.display()))]
pub async fn get_latest_gcc_release(major: u32, cache_dir: &Path) -> Result<String> {
    let cache_file = cache_dir.join(".gcc_version_cache");

    // Check cache first
    if let Some(cached) = check_cache(&cache_file, major)? {
        info!(major, version = %cached, "Using cached latest release");
        return Ok(cached);
    }

    info!(major, "Fetching GCC version from official server");

    match fetch_version_from_server(major).await {
        Ok(version) => {
            info!(major, version = %version, "Found GCC version");
            // Update cache
            let _ = update_cache(&cache_file, major, &version);
            return Ok(version);
        }
        Err(e) => {
            debug!(error = %e, "Server lookup failed");
        }
    }

    // Server failed, use known fallback versions
    if let Some(fallback) = get_known_version(major) {
        warn!(
            major,
            fallback, "Server lookup failed, using known fallback version"
        );
        return Ok(fallback.to_string());
    }

    Err(BuildError::VersionLookup {
        major_version: major,
        message: "Server lookup failed and no fallback version available".to_string(),
    }
    .into())
}

/// Fetch version from official GNU FTP server (matches bash script approach)
/// Uses curl-style directory listing parse: grep -oP "gcc-${major}[0-9.]+/" | sort -rV | head -n1
#[instrument(fields(major))]
async fn fetch_version_from_server(major: u32) -> Result<String> {
    let client = get_client();

    info!(url = GCC_FTP_URL, "Fetching GCC directory listing");

    let response = client
        .get(format!("{}/", GCC_FTP_URL))
        .send()
        .await
        .context("Failed to fetch GCC directory listing")?;

    if !response.status().is_success() {
        anyhow::bail!("HTTP error: {}", response.status());
    }

    let body = response
        .text()
        .await
        .context("Failed to read GCC directory listing")?;

    // Match pattern like bash: grep -oP "gcc-${major_version}[0-9.]+/"
    // This matches: gcc-15.1.0/ or gcc-15.2.0/ etc.
    let pattern = format!(r"gcc-({}\.\d+\.\d+)/", major);
    let re = Regex::new(&pattern).unwrap();

    let mut versions: Vec<String> = Vec::new();
    for cap in re.captures_iter(&body) {
        versions.push(cap[1].to_string());
    }

    if versions.is_empty() {
        anyhow::bail!("No releases found for GCC {}", major);
    }

    // Sort versions in reverse order (like sort -rV) to get the latest
    versions.sort_by(|a, b| {
        let parse_version = |s: &str| -> (u32, u32, u32) {
            let parts: Vec<u32> = s.split('.').filter_map(|p| p.parse().ok()).collect();
            (
                parts.first().copied().unwrap_or(0),
                parts.get(1).copied().unwrap_or(0),
                parts.get(2).copied().unwrap_or(0),
            )
        };
        parse_version(b).cmp(&parse_version(a))
    });

    let latest = versions.first().unwrap().clone();
    info!(major, latest = %latest, "Latest release found");
    Ok(latest)
}

/// Check the version cache for a cached version
fn check_cache(cache_file: &Path, major: u32) -> Result<Option<String>> {
    if !cache_file.exists() {
        return Ok(None);
    }

    // Check cache age
    let metadata = fs::metadata(cache_file)?;
    let modified = metadata.modified()?;
    let age = SystemTime::now()
        .duration_since(modified)
        .unwrap_or(Duration::MAX);

    if age > Duration::from_secs(VERSION_CACHE_TTL_SECS) {
        debug!(age_secs = age.as_secs(), "Cache file is stale");
        return Ok(None);
    }

    // Read cache and find entry for this major version
    let contents = fs::read_to_string(cache_file)?;
    for line in contents.lines() {
        if let Some((key, value)) = line.split_once(':') {
            if key == format!("gcc-{}", major) {
                return Ok(Some(value.to_string()));
            }
        }
    }

    Ok(None)
}

/// Update the version cache
fn update_cache(cache_file: &Path, major: u32, version: &str) -> Result<()> {
    // Read existing cache entries (excluding this major version)
    let mut entries: Vec<String> = Vec::new();
    if cache_file.exists() {
        let contents = fs::read_to_string(cache_file)?;
        for line in contents.lines() {
            if !line.starts_with(&format!("gcc-{}:", major)) {
                entries.push(line.to_string());
            }
        }
    }

    // Add new entry
    entries.push(format!("gcc-{}:{}", major, version));

    // Ensure parent directory exists
    if let Some(parent) = cache_file.parent() {
        fs::create_dir_all(parent)?;
    }

    // Write updated cache
    fs::write(cache_file, entries.join("\n"))?;
    Ok(())
}

/// Parse version specification string into list of major versions
#[instrument(fields(spec))]
pub fn parse_version_spec(spec: &str) -> Result<Vec<u32>> {
    let mut versions = HashSet::new();

    // Remove whitespace
    let spec = spec.replace(' ', "");

    for part in spec.split(',') {
        if part.contains('-') {
            // Range: "11-14"
            let parts: Vec<&str> = part.split('-').collect();
            if parts.len() != 2 {
                return Err(BuildError::InvalidVersionSpec {
                    spec: part.to_string(),
                }
                .into());
            }

            let start: u32 = parts[0]
                .parse()
                .map_err(|_| BuildError::InvalidVersionSpec {
                    spec: part.to_string(),
                })?;
            let end: u32 = parts[1]
                .parse()
                .map_err(|_| BuildError::InvalidVersionSpec {
                    spec: part.to_string(),
                })?;

            if start > end {
                warn!(start, end, "Invalid range (start > end)");
                continue;
            }

            for v in start..=end {
                if AVAILABLE_VERSIONS.contains(&v) {
                    versions.insert(v);
                } else {
                    warn!(version = v, "Version is not available and will be skipped");
                }
            }
        } else {
            // Single version: "13"
            let v: u32 = part.parse().map_err(|_| BuildError::InvalidVersionSpec {
                spec: part.to_string(),
            })?;

            if AVAILABLE_VERSIONS.contains(&v) {
                versions.insert(v);
            } else {
                warn!(version = v, "Version is not available and will be skipped");
            }
        }
    }

    if versions.is_empty() {
        return Err(BuildError::NoVersionsSelected.into());
    }

    let mut sorted: Vec<u32> = versions.into_iter().collect();
    sorted.sort();
    debug!(versions = ?sorted, "Parsed version specification");
    Ok(sorted)
}

/// Interactive version selection
pub fn select_versions_interactive() -> Result<Vec<u32>> {
    println!();
    let theme = ColorfulTheme::default();

    let options = vec![
        "A single major version",
        "Multiple major versions",
        "All available major versions",
    ];

    let selection = Select::with_theme(&theme)
        .with_prompt("Select how to choose GCC version(s)")
        .items(&options)
        .default(0)
        .interact()?;

    match selection {
        0 => {
            // Single version
            let version_options: Vec<String> = AVAILABLE_VERSIONS
                .iter()
                .map(|v| format!("GCC {}", v))
                .collect();

            let idx = Select::with_theme(&theme)
                .with_prompt("Select GCC version")
                .items(&version_options)
                .default(0)
                .interact()?;

            Ok(vec![AVAILABLE_VERSIONS[idx]])
        }
        1 => {
            // Multiple versions
            let version_options: Vec<String> = AVAILABLE_VERSIONS
                .iter()
                .map(|v| format!("GCC {}", v))
                .collect();

            let selections = MultiSelect::with_theme(&theme)
                .with_prompt("Select GCC versions (Space to toggle, Enter to confirm)")
                .items(&version_options)
                .interact()?;

            if selections.is_empty() {
                return Err(BuildError::NoVersionsSelected.into());
            }

            let versions: Vec<u32> = selections
                .into_iter()
                .map(|i| AVAILABLE_VERSIONS[i])
                .collect();

            Ok(versions)
        }
        2 => {
            // All versions
            info!("Selected all available GCC major versions");
            Ok(AVAILABLE_VERSIONS.to_vec())
        }
        _ => unreachable!(),
    }
}

/// Resolve major versions to full GccVersion structs
#[instrument(skip(cache_dir), fields(majors = ?majors, cache_dir = %cache_dir.display()))]
pub async fn resolve_versions(majors: &[u32], cache_dir: &Path) -> Result<Vec<GccVersion>> {
    let mut versions = Vec::new();

    for &major in majors {
        match get_latest_gcc_release(major, cache_dir).await {
            Ok(full) => {
                info!(major, full = %full, "Resolved latest release");
                versions.push(GccVersion::new(major, full));
            }
            Err(e) => {
                warn!(major, error = %e, "Could not determine latest release");
                // Continue with other versions
            }
        }
    }

    if versions.is_empty() {
        return Err(BuildError::NoVersionsSelected.into());
    }

    Ok(versions)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_single_version() {
        let result = parse_version_spec("13").unwrap();
        assert_eq!(result, vec![13]);
    }

    #[test]
    fn test_parse_multiple_versions() {
        let result = parse_version_spec("11,13,14").unwrap();
        assert_eq!(result, vec![11, 13, 14]);
    }

    #[test]
    fn test_parse_range() {
        let result = parse_version_spec("11-14").unwrap();
        assert_eq!(result, vec![11, 12, 13, 14]);
    }

    #[test]
    fn test_parse_mixed() {
        let result = parse_version_spec("10,12-14").unwrap();
        assert_eq!(result, vec![10, 12, 13, 14]);
    }

    #[test]
    fn test_parse_with_spaces() {
        let result = parse_version_spec("11, 13, 14").unwrap();
        assert_eq!(result, vec![11, 13, 14]);
    }

    #[test]
    fn test_parse_invalid() {
        assert!(parse_version_spec("abc").is_err());
    }

    #[test]
    fn test_parse_unavailable_version() {
        // Version 5 is not in AVAILABLE_VERSIONS
        let result = parse_version_spec("5,13");
        // Should succeed but only include 13
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), vec![13]);
    }
}
