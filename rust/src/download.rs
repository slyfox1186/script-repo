use crate::config::{GccVersion, MAX_DOWNLOAD_ATTEMPTS};
use crate::error::BuildError;
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
use tracing::{debug, info, warn};

/// Official GCC FTP server (confirmed working)
const GCC_FTP_URL: &str = "https://gcc.gnu.org/ftp/gcc/releases";

/// Cache directory for downloaded tarballs to avoid re-downloading
const DOWNLOAD_CACHE_DIR: &str = "/tmp/build-gcc-cache";

/// Download a file with progress tracking and retry logic
pub async fn download_file(url: &str, dest: &Path, progress: Option<&ProgressBar>) -> Result<()> {
    let client = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_secs(5)) // Fast fail on connection
        .timeout(std::time::Duration::from_secs(300)) // 5 min for large files
        .build()?;

    let response = client
        .get(url)
        .send()
        .await
        .context("Failed to initiate download")?;

    if !response.status().is_success() {
        return Err(BuildError::Download {
            url: url.to_string(),
            message: format!("HTTP error: {}", response.status()),
        }
        .into());
    }

    let total_size = response.content_length().unwrap_or(0);

    // Create or update progress bar
    let pb = if let Some(p) = progress {
        p.set_length(total_size);
        p.clone()
    } else {
        create_download_bar(total_size)
    };

    // Ensure parent directory exists
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)?;
    }

    // Create file
    let mut file = File::create(dest).context("Failed to create destination file")?;

    // Stream the response
    let mut stream = response.bytes_stream();
    let mut downloaded: u64 = 0;

    while let Some(chunk) = stream.next().await {
        let chunk = chunk.context("Failed to read chunk")?;
        file.write_all(&chunk).context("Failed to write to file")?;
        downloaded += chunk.len() as u64;
        pb.set_position(downloaded);
    }

    pb.finish_with_message("Download complete");
    Ok(())
}

/// Download GCC source with retry logic and caching
pub async fn download_gcc_source(
    version: &GccVersion,
    build_dir: &Path,
    dry_run: bool,
) -> Result<PathBuf> {
    let dest = build_dir.join(version.tarball_name());
    let cache_dir = PathBuf::from(DOWNLOAD_CACHE_DIR);
    let cached_file = cache_dir.join(version.tarball_name());

    info!(
        "Preparing to download {} for GCC {}",
        version.tarball_name(),
        version.full
    );

    // Ensure cache directory exists
    if !cache_dir.exists() {
        info!("Creating download cache directory: {}", cache_dir.display());
        fs::create_dir_all(&cache_dir).context("Failed to create cache directory")?;
    }

    // Check if file exists in cache first
    if cached_file.exists() {
        info!(
            "Found cached file: {}. Verifying integrity...",
            cached_file.display()
        );

        if verify_tarball(&cached_file)? {
            info!("Cached file {} is valid.", cached_file.display());

            if !dry_run {
                // Verify checksum of cached file
                match verify_checksum(&cached_file, version).await {
                    Ok(true) => {
                        info!("Checksum verified for cached file. Copying to build directory...");
                        fs::copy(&cached_file, &dest).context("Failed to copy cached file")?;
                        return Ok(dest);
                    }
                    Ok(false) => {
                        warn!("Cached file checksum mismatch. Will re-download.");
                        fs::remove_file(&cached_file)?;
                    }
                    Err(e) => {
                        warn!("Cached file checksum error: {}. Will re-download.", e);
                        fs::remove_file(&cached_file)?;
                    }
                }
            } else {
                info!("Dry run: Would use cached file.");
                return Ok(dest);
            }
        } else {
            warn!("Cached file appears corrupted. Removing...");
            fs::remove_file(&cached_file)?;
        }
    }

    // Check if file already exists in build dir
    if dest.exists() {
        info!(
            "File {} already exists in build dir. Verifying integrity...",
            dest.display()
        );

        if verify_tarball(&dest)? {
            if !dry_run {
                match verify_checksum(&dest, version).await {
                    Ok(true) => {
                        info!("Checksum verified. Caching file for future use...");
                        // Copy to cache for future runs
                        let _ = fs::copy(&dest, &cached_file);
                        return Ok(dest);
                    }
                    Ok(false) => {
                        warn!("Checksum mismatch. Will re-download.");
                        fs::remove_file(&dest)?;
                    }
                    Err(e) => {
                        warn!("Checksum error: {}. Will re-download.", e);
                        fs::remove_file(&dest)?;
                    }
                }
            } else {
                info!("Dry run: Would verify checksum for existing file.");
                return Ok(dest);
            }
        } else {
            warn!("Existing file appears corrupted. Removing...");
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
        info!("Dry run: would download {} to {}", url, dest.display());
        return Ok(dest);
    }

    info!("Downloading from {}", url);

    // Download with retry
    let mut last_error = None;
    for attempt in 1..=MAX_DOWNLOAD_ATTEMPTS {
        info!("Download attempt {} of {}", attempt, MAX_DOWNLOAD_ATTEMPTS);

        let pb = create_download_bar(0);
        pb.set_message(format!("Downloading {}", version.tarball_name()));

        match download_file(&url, &dest, Some(&pb)).await {
            Ok(()) => {
                // Verify downloaded file
                if verify_tarball(&dest)? {
                    info!("Successfully downloaded {}", version.tarball_name());

                    // Verify checksum
                    match verify_checksum(&dest, version).await {
                        Ok(true) => {
                            info!("Checksum verified successfully.");
                            // Save to cache for future runs
                            info!("Caching download to {}", cached_file.display());
                            if let Err(e) = fs::copy(&dest, &cached_file) {
                                warn!("Failed to cache file: {}", e);
                            }
                            return Ok(dest);
                        }
                        Ok(false) => {
                            warn!("Checksum mismatch for downloaded file.");
                            fs::remove_file(&dest)?;
                            last_error = Some("Checksum mismatch".to_string());
                        }
                        Err(e) => {
                            // Some versions might not have checksums available
                            warn!("Checksum verification skipped: {}", e);
                            // Still cache it
                            let _ = fs::copy(&dest, &cached_file);
                            return Ok(dest);
                        }
                    }
                } else {
                    warn!("Downloaded file appears corrupted.");
                    fs::remove_file(&dest)?;
                    last_error = Some("Corrupted download".to_string());
                }
            }
            Err(e) => {
                warn!("Download attempt {} failed: {}", attempt, e);
                let _ = fs::remove_file(&dest);
                last_error = Some(e.to_string());
            }
        }

        if attempt < MAX_DOWNLOAD_ATTEMPTS {
            tokio::time::sleep(std::time::Duration::from_secs(2)).await;
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
        .context("Failed to verify tarball")?;

    Ok(output.status.success())
}

/// Verify checksum of downloaded file
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
async fn verify_sha512(path: &Path, version: &GccVersion) -> Result<bool> {
    info!("Starting SHA512 checksum verification...");

    // Create spinner for fetching checksum
    let spinner = create_checksum_spinner("Fetching SHA512 checksum from GCC server...");

    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(30))
        .build()?;

    // Fetch checksum from official GCC FTP server
    let sha512_url = format!("{}/gcc-{}/sha512.sum", GCC_FTP_URL, version.full);
    debug!("Fetching checksum from: {}", sha512_url);

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
            warn!(
                "Failed to fetch checksum (HTTP {}). Skipping verification.",
                r.status()
            );
            return Ok(true);
        }
        Err(e) => {
            spinner.finish_with_message(format!("Checksum fetch error: {}. Skipping.", e));
            warn!("Failed to fetch checksum: {}. Skipping verification.", e);
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
                debug!("Found expected checksum: {}", parts[0]);
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
            warn!("Could not find checksum for {} in sha512.sum", filename);
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
    info!(
        "Calculating SHA512 checksum for {} ({:.1} MB)...",
        path.display(),
        size_mb
    );

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

    debug!("Expected checksum: {}", expected);
    debug!("Actual checksum:   {}", actual);

    if expected.to_lowercase() == actual.to_lowercase() {
        spinner.finish_with_message("SHA512 checksum verified successfully!");
        info!("SHA512 checksum verified successfully");
        Ok(true)
    } else {
        spinner.finish_with_message("SHA512 checksum MISMATCH!");
        warn!("SHA512 checksum MISMATCH!");
        warn!("Expected: {}", expected);
        warn!("Actual:   {}", actual);
        Ok(false)
    }
}

/// Verify GPG signature
async fn verify_gpg(path: &Path, version: &GccVersion) -> Result<bool> {
    let sig_path = path.with_extension("xz.sig");

    let client = reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_secs(5))
        .timeout(std::time::Duration::from_secs(15))
        .build()?;

    // Fetch signature from official GCC FTP server
    let sig_url = format!(
        "{}/gcc-{}/gcc-{}.tar.xz.sig",
        GCC_FTP_URL, version.full, version.full
    );

    info!("Downloading GPG signature from {}", sig_url);

    let response = client.get(&sig_url).send().await;
    let sig_downloaded = match response {
        Ok(r) if r.status().is_success() => {
            let bytes = r.bytes().await?;
            fs::write(&sig_path, &bytes)?;
            true
        }
        Ok(r) => {
            warn!(
                "Failed to fetch signature (HTTP {}). Skipping GPG verification.",
                r.status()
            );
            return Ok(true);
        }
        Err(e) => {
            warn!(
                "Failed to fetch signature: {}. Skipping GPG verification.",
                e
            );
            return Ok(true);
        }
    };

    if !sig_downloaded {
        warn!("Could not download signature file. Skipping GPG verification.");
        return Ok(true);
    }

    // Import GCC signing keys
    info!("Importing GCC release signing keys...");
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
    info!("Verifying GPG signature...");
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
        info!("GPG signature verified successfully.");
        Ok(true)
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        debug!("GPG verification output: {}", stderr);

        // Check if it's a key issue vs actual verification failure
        if stderr.contains("No public key") || stderr.contains("unknown key") {
            warn!("Could not verify GPG signature (key not found). Proceeding anyway.");
            Ok(true)
        } else {
            warn!("GPG signature verification failed.");
            Ok(false)
        }
    }
}

/// Extract a tarball
pub async fn extract_tarball(tarball: &Path, dest_dir: &Path, dry_run: bool) -> Result<PathBuf> {
    let filename = tarball.file_name().unwrap().to_string_lossy();

    if dry_run {
        info!(
            "Dry run: would extract {} to {}",
            filename,
            dest_dir.display()
        );
        // Return the expected source directory
        let source_name = filename.trim_end_matches(".tar.xz");
        return Ok(dest_dir.join(source_name));
    }

    info!("Extracting {} to {}...", filename, dest_dir.display());

    // Ensure destination directory exists
    fs::create_dir_all(dest_dir)?;

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
        .context("Failed to extract tarball")?;

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

    info!("Successfully extracted to {}", source_dir.display());
    Ok(source_dir)
}
