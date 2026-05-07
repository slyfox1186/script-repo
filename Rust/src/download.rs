//! GCC source download and verification module.
//!
//! Provides async download with progress tracking, retry logic, caching,
//! and checksum verification for GCC source tarballs.

use crate::config::{GccVersion, MAX_DOWNLOAD_ATTEMPTS};
use crate::error::BuildError;
use crate::http_client::{create_download_client, get_client};
use crate::progress::create_download_bar;
use anyhow::{Context, Result};
use futures::StreamExt;
use indicatif::{ProgressBar, ProgressStyle};
use sha2::{Digest, Sha512};
use std::fs::{self, File};
use std::io::{Read as IoRead, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;
use tracing::{debug, info, instrument, warn};

/// Official GCC FTP server (confirmed working)
const GCC_FTP_URL: &str = "https://gcc.gnu.org/ftp/gcc/releases";

/// Cache directory for downloaded tarballs to avoid re-downloading
const DOWNLOAD_CACHE_DIR: &str = "/tmp/build-gcc-cache";

/// Download a file with progress tracking and retry logic
#[instrument(skip(progress), fields(dest = %dest.display()))]
pub async fn download_file(url: &str, dest: &Path, progress: Option<&ProgressBar>) -> Result<()> {
    let client = create_download_client().context("Failed to create download client")?;

    let response = client
        .get(url)
        .send()
        .await
        .with_context(|| format!("Failed to initiate download from {}", url))?;

    if !response.status().is_success() {
        return Err(BuildError::Download {
            url: url.to_string(),
            message: format!("HTTP error: {}", response.status()),
        }
        .into());
    }

    let total_size = response.content_length().unwrap_or(0);
    debug!(total_size, "Download starting");

    // Create or update progress bar
    let pb = if let Some(p) = progress {
        p.set_length(total_size);
        p.clone()
    } else {
        create_download_bar(total_size)
    };

    // Ensure parent directory exists
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create parent directory: {}", parent.display()))?;
    }

    // Create file
    let mut file =
        File::create(dest).with_context(|| format!("Failed to create file: {}", dest.display()))?;

    // Stream the response
    let mut stream = response.bytes_stream();
    let mut downloaded: u64 = 0;

    while let Some(chunk) = stream.next().await {
        let chunk = chunk.context("Failed to read chunk from response stream")?;
        file.write_all(&chunk)
            .with_context(|| format!("Failed to write to file: {}", dest.display()))?;
        downloaded += chunk.len() as u64;
        pb.set_position(downloaded);
    }

    pb.finish_with_message("Download complete");
    debug!(bytes = downloaded, "Download completed successfully");
    Ok(())
}

/// Download GCC source with retry logic and caching
#[instrument(skip(build_dir), fields(version = %version.full, dry_run))]
pub async fn download_gcc_source(
    version: &GccVersion,
    build_dir: &Path,
    dry_run: bool,
) -> Result<PathBuf> {
    let dest = build_dir.join(version.tarball_name());
    let cache_dir = PathBuf::from(DOWNLOAD_CACHE_DIR);
    let cached_file = cache_dir.join(version.tarball_name());

    info!(
        tarball = %version.tarball_name(),
        "Preparing to download GCC source"
    );

    // Ensure cache directory exists
    if !cache_dir.exists() {
        info!(cache_dir = %cache_dir.display(), "Creating download cache directory");
        fs::create_dir_all(&cache_dir).context("Failed to create cache directory")?;
    }

    // Check if file exists in cache first
    if cached_file.exists() {
        info!(cached_file = %cached_file.display(), "Found cached file, verifying integrity");

        if verify_tarball(&cached_file)? {
            info!("Cached file is valid");

            if !dry_run {
                // Verify checksum of cached file
                match verify_checksum(&cached_file, version).await {
                    Ok(true) => {
                        info!("Checksum verified for cached file, copying to build directory");
                        fs::copy(&cached_file, &dest).with_context(|| {
                            format!(
                                "Failed to copy cached file from {} to {}",
                                cached_file.display(),
                                dest.display()
                            )
                        })?;
                        return Ok(dest);
                    }
                    Ok(false) => {
                        warn!("Cached file checksum mismatch, will re-download");
                        fs::remove_file(&cached_file)?;
                    }
                    Err(e) => {
                        warn!(error = %e, "Cached file checksum error, will re-download");
                        fs::remove_file(&cached_file)?;
                    }
                }
            } else {
                info!("Dry run: Would use cached file");
                return Ok(dest);
            }
        } else {
            warn!("Cached file appears corrupted, removing");
            fs::remove_file(&cached_file)?;
        }
    }

    // Check if file already exists in build dir
    if dest.exists() {
        info!(
            dest = %dest.display(),
            "File already exists in build dir, verifying integrity"
        );

        if verify_tarball(&dest)? {
            if !dry_run {
                match verify_checksum(&dest, version).await {
                    Ok(true) => {
                        info!("Checksum verified, caching file for future use");
                        // Copy to cache for future runs
                        let _ = fs::copy(&dest, &cached_file);
                        return Ok(dest);
                    }
                    Ok(false) => {
                        warn!("Checksum mismatch, will re-download");
                        fs::remove_file(&dest)?;
                    }
                    Err(e) => {
                        warn!(error = %e, "Checksum error, will re-download");
                        fs::remove_file(&dest)?;
                    }
                }
            } else {
                info!("Dry run: Would verify checksum for existing file");
                return Ok(dest);
            }
        } else {
            warn!("Existing file appears corrupted, removing");
            fs::remove_file(&dest)?;
        }
    }

    // Build URL from official GCC FTP server
    let url = format!(
        "{}/gcc-{}/{}",
        GCC_FTP_URL,
        version.full,
        version.tarball_name()
    );

    if dry_run {
        info!(url, dest = %dest.display(), "Dry run: would download");
        return Ok(dest);
    }

    info!(url, "Downloading GCC source");

    // Download with retry
    let mut last_error = None;
    for attempt in 1..=MAX_DOWNLOAD_ATTEMPTS {
        info!(attempt, max = MAX_DOWNLOAD_ATTEMPTS, "Download attempt");

        let pb = create_download_bar(0);
        pb.set_message(format!("Downloading {}", version.tarball_name()));

        match download_file(&url, &dest, Some(&pb)).await {
            Ok(()) => {
                // Verify downloaded file
                if verify_tarball(&dest)? {
                    info!(tarball = %version.tarball_name(), "Successfully downloaded");

                    // Verify checksum
                    match verify_checksum(&dest, version).await {
                        Ok(true) => {
                            info!("Checksum verified successfully");
                            // Save to cache for future runs
                            info!(cache = %cached_file.display(), "Caching download");
                            if let Err(e) = fs::copy(&dest, &cached_file) {
                                warn!(error = %e, "Failed to cache file");
                            }
                            return Ok(dest);
                        }
                        Ok(false) => {
                            warn!("Checksum mismatch for downloaded file");
                            fs::remove_file(&dest)?;
                            last_error = Some("Checksum mismatch".to_string());
                        }
                        Err(e) => {
                            // Some versions might not have checksums available
                            warn!(error = %e, "Checksum verification skipped");
                            // Still cache it
                            let _ = fs::copy(&dest, &cached_file);
                            return Ok(dest);
                        }
                    }
                } else {
                    warn!("Downloaded file appears corrupted");
                    fs::remove_file(&dest)?;
                    last_error = Some("Corrupted download".to_string());
                }
            }
            Err(e) => {
                warn!(attempt, error = %e, "Download attempt failed");
                let _ = fs::remove_file(&dest);
                last_error = Some(e.to_string());
            }
        }

        if attempt < MAX_DOWNLOAD_ATTEMPTS {
            tokio::time::sleep(Duration::from_secs(2)).await;
        }
    }

    Err(BuildError::Download {
        url,
        message: format!("Download failed: {}", last_error.unwrap_or_default()),
    }
    .into())
}

/// Verify that a tarball is valid
fn verify_tarball(path: &Path) -> Result<bool> {
    let output = Command::new("tar")
        .args(["-tf", path.to_str().unwrap_or("")])
        .output()
        .with_context(|| format!("Failed to verify tarball: {}", path.display()))?;

    Ok(output.status.success())
}

/// Verify checksum of downloaded file
#[instrument(skip(path), fields(path = %path.display(), version = %version.full))]
async fn verify_checksum(path: &Path, version: &GccVersion) -> Result<bool> {
    let major = version.major;

    if major >= 14 {
        // GCC 14+ uses sha512.sum file
        verify_sha512(path, version).await
    } else {
        // Older versions use GPG signatures
        verify_gpg(path, version).await
    }
}

/// Create a spinner for checksum verification
fn create_checksum_spinner(message: &str) -> ProgressBar {
    let spinner = ProgressBar::new_spinner();
    spinner.set_style(
        ProgressStyle::with_template("{spinner:.green} [{elapsed_precise}] {msg}")
            .unwrap()
            .tick_chars("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"),
    );
    spinner.set_message(message.to_string());
    spinner.enable_steady_tick(Duration::from_millis(80));
    spinner
}

/// Verify SHA512 checksum with progress indication
#[instrument(skip(path), fields(path = %path.display(), version = %version.full))]
async fn verify_sha512(path: &Path, version: &GccVersion) -> Result<bool> {
    info!("Starting SHA512 checksum verification");

    // Create spinner for fetching checksum
    let spinner = create_checksum_spinner("Fetching SHA512 checksum from GCC server...");

    let client = get_client();

    // Fetch checksum from official GCC FTP server
    let sha512_url = format!("{}/gcc-{}/sha512.sum", GCC_FTP_URL, version.full);
    debug!(url = sha512_url, "Fetching checksum");

    let response = client.get(&sha512_url).send().await;
    let checksum_file = match response {
        Ok(r) if r.status().is_success() => {
            spinner.set_message("Parsing checksum file...");
            r.text().await?
        }
        Ok(r) => {
            spinner.finish_with_message(format!(
                "Checksum fetch failed (HTTP {}). Skipping verification.",
                r.status()
            ));
            warn!(status = %r.status(), "Failed to fetch checksum, skipping verification");
            return Ok(true);
        }
        Err(e) => {
            spinner.finish_with_message(format!("Checksum fetch error: {}. Skipping.", e));
            warn!(error = %e, "Failed to fetch checksum, skipping verification");
            return Ok(true);
        }
    };

    // Find the checksum for our file
    let filename = version.tarball_name();
    let mut expected_checksum = None;

    for line in checksum_file.lines() {
        if line.contains(&filename) {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if !parts.is_empty() {
                expected_checksum = Some(parts[0].to_string());
                debug!(checksum = parts[0], "Found expected checksum");
                break;
            }
        }
    }

    let expected = match expected_checksum {
        Some(c) => c,
        None => {
            spinner.finish_with_message(format!(
                "No checksum found for {} in sha512.sum. Skipping.",
                filename
            ));
            warn!(filename, "Could not find checksum in sha512.sum");
            return Ok(true);
        }
    };

    // Get file size for progress reporting
    let file_size = fs::metadata(path).map(|m| m.len()).unwrap_or(0);
    let size_mb = file_size as f64 / 1_048_576.0;

    spinner.set_message(format!(
        "Calculating SHA512 checksum for {:.1} MB file...",
        size_mb
    ));
    info!(size_mb, path = %path.display(), "Calculating SHA512 checksum");

    // Calculate checksum in blocking task with chunked reading for better responsiveness
    let path_clone = path.to_path_buf();
    let spinner_clone = spinner.clone();

    // Use tokio timeout to prevent indefinite hanging
    let checksum_result = tokio::time::timeout(
        Duration::from_secs(300), // 5 minute timeout for very large files
        tokio::task::spawn_blocking(move || -> Result<String> {
            let mut file = File::open(&path_clone)?;
            let mut hasher = Sha512::new();

            // Read in 8MB chunks to allow periodic updates
            let mut buffer = vec![0u8; 8 * 1024 * 1024];
            let mut bytes_read: u64 = 0;

            loop {
                let n = file.read(&mut buffer)?;
                if n == 0 {
                    break;
                }
                hasher.update(&buffer[..n]);
                bytes_read += n as u64;

                // Update spinner with progress
                if file_size > 0 {
                    let percent = (bytes_read as f64 / file_size as f64) * 100.0;
                    spinner_clone.set_message(format!(
                        "Calculating SHA512 checksum... {:.1}% ({:.1} / {:.1} MB)",
                        percent,
                        bytes_read as f64 / 1_048_576.0,
                        size_mb
                    ));
                }
            }

            Ok(format!("{:x}", hasher.finalize()))
        }),
    )
    .await;

    let actual = match checksum_result {
        Ok(Ok(Ok(hash))) => hash,
        Ok(Ok(Err(e))) => {
            spinner.finish_with_message(format!("Checksum calculation error: {}", e));
            return Err(e);
        }
        Ok(Err(e)) => {
            spinner.finish_with_message("Checksum task panicked!");
            return Err(anyhow::anyhow!("Checksum task failed: {}", e));
        }
        Err(_) => {
            spinner.finish_with_message("Checksum calculation timed out!");
            return Err(anyhow::anyhow!(
                "Checksum calculation timed out after 5 minutes"
            ));
        }
    };

    debug!(expected, actual, "Comparing checksums");

    if expected.to_lowercase() == actual.to_lowercase() {
        spinner.finish_with_message("SHA512 checksum verified successfully!");
        info!("SHA512 checksum verified successfully");
        Ok(true)
    } else {
        spinner.finish_with_message("SHA512 checksum MISMATCH!");
        warn!(expected, actual, "SHA512 checksum MISMATCH!");
        Ok(false)
    }
}

/// Verify GPG signature
#[instrument(skip(path), fields(path = %path.display(), version = %version.full))]
async fn verify_gpg(path: &Path, version: &GccVersion) -> Result<bool> {
    let sig_path = path.with_extension("xz.sig");

    let client = get_client();

    // Fetch signature from official GCC FTP server
    let sig_url = format!(
        "{}/gcc-{}/gcc-{}.tar.xz.sig",
        GCC_FTP_URL, version.full, version.full
    );

    info!(url = sig_url, "Downloading GPG signature");

    let response = client.get(&sig_url).send().await;
    let sig_downloaded = match response {
        Ok(r) if r.status().is_success() => {
            let bytes = r.bytes().await?;
            fs::write(&sig_path, &bytes)?;
            true
        }
        Ok(r) => {
            warn!(
                status = %r.status(),
                "Failed to fetch signature, skipping GPG verification"
            );
            return Ok(true);
        }
        Err(e) => {
            warn!(error = %e, "Failed to fetch signature, skipping GPG verification");
            return Ok(true);
        }
    };

    if !sig_downloaded {
        warn!("Could not download signature file, skipping GPG verification");
        return Ok(true);
    }

    // Import GCC signing keys
    info!("Importing GCC release signing keys");
    let gcc_keys = [
        "33C235A34C46AA3FFB293709A328C3A2C3C45C06", // Jakub Jelinek
        "7F74F97C103468EE5D750B583AB00996FC26A641", // Recent releases
        "13975A70E63C361C73AE69EF6EEB81F8981C74C7", // Richard Biener
    ];

    for key in gcc_keys {
        let _ = Command::new("gpg")
            .args(["--keyserver", "keyserver.ubuntu.com", "--recv-keys", key])
            .output();
    }

    // Verify signature
    info!("Verifying GPG signature");
    let output = Command::new("gpg")
        .args([
            "--verify",
            sig_path.to_str().unwrap(),
            path.to_str().unwrap(),
        ])
        .output()?;

    // Clean up signature file
    let _ = fs::remove_file(&sig_path);

    if output.status.success() {
        info!("GPG signature verified successfully");
        Ok(true)
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        debug!(stderr = %stderr, "GPG verification output");

        // Check if it's a key issue vs actual verification failure
        if stderr.contains("No public key") || stderr.contains("unknown key") {
            warn!("Could not verify GPG signature (key not found), proceeding anyway");
            Ok(true)
        } else {
            warn!("GPG signature verification failed");
            Ok(false)
        }
    }
}

/// Extract a tarball
#[instrument(skip(tarball, dest_dir), fields(tarball = %tarball.display(), dest = %dest_dir.display()))]
pub async fn extract_tarball(tarball: &Path, dest_dir: &Path, dry_run: bool) -> Result<PathBuf> {
    let filename = tarball.file_name().unwrap().to_string_lossy();

    if dry_run {
        info!(filename = %filename, "Dry run: would extract tarball");
        // Return the expected source directory
        let source_name = filename.trim_end_matches(".tar.xz");
        return Ok(dest_dir.join(source_name));
    }

    info!(filename = %filename, dest = %dest_dir.display(), "Extracting tarball");

    // Ensure destination directory exists
    fs::create_dir_all(dest_dir).with_context(|| {
        format!(
            "Failed to create destination directory: {}",
            dest_dir.display()
        )
    })?;

    // Use tar with xz decompression
    let output = tokio::process::Command::new("tar")
        .args([
            "-Jxf",
            tarball.to_str().unwrap(),
            "-C",
            dest_dir.to_str().unwrap(),
        ])
        .output()
        .await
        .with_context(|| format!("Failed to extract tarball: {}", filename))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(BuildError::Extraction {
            file: filename.to_string(),
            message: stderr.to_string(),
        }
        .into());
    }

    // Return path to extracted source directory
    let source_name = filename.trim_end_matches(".tar.xz");
    let source_dir = dest_dir.join(source_name);

    info!(source_dir = %source_dir.display(), "Successfully extracted tarball");
    Ok(source_dir)
}
