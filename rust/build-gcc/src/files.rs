use log::{debug, info, warn};
use sha2::{Digest, Sha512};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use tar::Archive;
use flate2::read::GzDecoder;

use crate::error::{GccBuildError, Result as GccResult};
use crate::logging::ProgressLogger;

#[derive(Debug, Clone)]
pub struct FileOperations {
    pub dry_run: bool,
}

impl FileOperations {
    pub fn new(dry_run: bool) -> Self {
        Self { dry_run }
    }
    
    /// Validate file based on different criteria
    pub fn validate_file(&self, file_path: &Path, validation_type: FileValidationType) -> GccResult<bool> {
        if !file_path.exists() {
            return match validation_type {
                FileValidationType::Exists => Ok(false),
                _ => Err(GccBuildError::file_operation(
                    "validate".to_string(),
                    file_path.display().to_string(),
                    "File does not exist".to_string(),
                )),
            };
        }
        
        match validation_type {
            FileValidationType::Exists => Ok(true),
            FileValidationType::Readable => Ok(file_path.metadata()?.permissions().readonly() == false),
            FileValidationType::Writable => {
                // Try to open for writing
                match fs::OpenOptions::new().write(true).open(file_path) {
                    Ok(_) => Ok(true),
                    Err(_) => Ok(false),
                }
            }
            FileValidationType::Executable => {
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    let metadata = file_path.metadata()?;
                    let permissions = metadata.permissions();
                    Ok(permissions.mode() & 0o111 != 0)
                }
                #[cfg(not(unix))]
                {
                    // On non-Unix systems, check if it's an executable extension
                    Ok(file_path.extension()
                        .and_then(|ext| ext.to_str())
                        .map(|ext| matches!(ext, "exe" | "bat" | "cmd"))
                        .unwrap_or(false))
                }
            }
            FileValidationType::Tarball => self.validate_tarball(file_path),
            FileValidationType::Checksum(expected) => self.validate_checksum(file_path, &expected),
        }
    }
    
    /// Validate that a file is a valid tarball
    fn validate_tarball(&self, file_path: &Path) -> GccResult<bool> {
        let file = File::open(file_path)
            .map_err(|e| GccBuildError::file_operation(
                "open".to_string(),
                file_path.display().to_string(),
                e.to_string(),
            ))?;
        
        // Try to read the tar headers
        let result = if file_path.extension().and_then(|s| s.to_str()) == Some("gz") {
            let decoder = GzDecoder::new(file);
            let mut archive = Archive::new(decoder);
            archive.entries().map(|_| ()).is_ok()
        } else if file_path.extension().and_then(|s| s.to_str()) == Some("xz") {
            // For xz files, we'd need the xz2 crate
            // For now, just check if tar can read it by using tar command
            return Ok(true); // Simplified for now
        } else {
            let mut archive = Archive::new(file);
            archive.entries().map(|_| ()).is_ok()
        };
        
        Ok(result)
    }
    
    /// Validate file checksum
    fn validate_checksum(&self, file_path: &Path, expected: &str) -> GccResult<bool> {
        let actual = self.calculate_checksum(file_path)?;
        Ok(actual.to_lowercase() == expected.to_lowercase())
    }
    
    /// Calculate SHA512 checksum of a file
    pub fn calculate_checksum(&self, file_path: &Path) -> GccResult<String> {
        let mut file = File::open(file_path)
            .map_err(|e| GccBuildError::file_operation(
                "open".to_string(),
                file_path.display().to_string(),
                e.to_string(),
            ))?;
        
        let mut hasher = Sha512::new();
        let mut buffer = [0; 8192];
        
        loop {
            let bytes_read = file.read(&mut buffer)
                .map_err(|e| GccBuildError::file_operation(
                    "read".to_string(),
                    file_path.display().to_string(),
                    e.to_string(),
                ))?;
            
            if bytes_read == 0 {
                break;
            }
            
            hasher.update(&buffer[..bytes_read]);
        }
        
        Ok(format!("{:x}", hasher.finalize()))
    }
    
    /// Extract archive with automatic format detection
    pub fn extract_archive(
        &self,
        archive_path: &Path,
        destination: &Path,
        strip_components: usize,
    ) -> GccResult<()> {
        let logger = ProgressLogger::new(&format!("Extracting {}", archive_path.display()));
        
        if self.dry_run {
            info!("Dry run: would extract {:?} to {:?}", archive_path, destination);
            logger.finish();
            return Ok(());
        }
        
        // Ensure destination exists
        fs::create_dir_all(destination)
            .map_err(|e| GccBuildError::file_operation(
                "create_dir_all".to_string(),
                destination.display().to_string(),
                e.to_string(),
            ))?;
        
        let file = File::open(archive_path)
            .map_err(|e| GccBuildError::file_operation(
                "open".to_string(),
                archive_path.display().to_string(),
                e.to_string(),
            ))?;
        
        let extension = archive_path.extension().and_then(|s| s.to_str()).unwrap_or("");
        let stem = archive_path.file_stem().and_then(|s| s.to_str()).unwrap_or("");
        
        match extension {
            "xz" if stem.ends_with(".tar") => {
                // Use external tar command for xz files for now
                let mut cmd = std::process::Command::new("tar");
                cmd.arg("-Jxf")
                   .arg(archive_path)
                   .arg("-C")
                   .arg(destination);
                
                if strip_components > 0 {
                    cmd.arg("--strip-components").arg(strip_components.to_string());
                }
                
                let status = cmd.status()
                    .map_err(|e| GccBuildError::file_operation(
                        "extract_xz".to_string(),
                        archive_path.display().to_string(),
                        e.to_string(),
                    ))?;
                
                if !status.success() {
                    return Err(GccBuildError::file_operation(
                        "extract_xz".to_string(),
                        archive_path.display().to_string(),
                        "tar command failed".to_string(),
                    ));
                }
            }
            "gz" if stem.ends_with(".tar") => {
                let decoder = GzDecoder::new(file);
                let mut archive = Archive::new(decoder);
                
                if strip_components > 0 {
                    archive.set_preserve_permissions(true);
                    for entry in archive.entries()? {
                        let mut entry = entry?;
                        let path = entry.path()?;
                        let components: Vec<_> = path.components().collect();
                        
                        if components.len() > strip_components {
                            let new_path: PathBuf = components[strip_components..].iter().collect();
                            let dest_path = destination.join(new_path);
                            
                            if let Some(parent) = dest_path.parent() {
                                fs::create_dir_all(parent)?;
                            }
                            
                            entry.unpack(dest_path)?;
                        }
                    }
                } else {
                    archive.unpack(destination)
                        .map_err(|e| GccBuildError::file_operation(
                            "unpack".to_string(),
                            archive_path.display().to_string(),
                            e.to_string(),
                        ))?;
                }
            }
            "tar" => {
                let mut archive = Archive::new(file);
                
                if strip_components > 0 {
                    // Similar logic as above for tar.gz
                    for entry in archive.entries()? {
                        let mut entry = entry?;
                        let path = entry.path()?;
                        let components: Vec<_> = path.components().collect();
                        
                        if components.len() > strip_components {
                            let new_path: PathBuf = components[strip_components..].iter().collect();
                            let dest_path = destination.join(new_path);
                            
                            if let Some(parent) = dest_path.parent() {
                                fs::create_dir_all(parent)?;
                            }
                            
                            entry.unpack(dest_path)?;
                        }
                    }
                } else {
                    archive.unpack(destination)
                        .map_err(|e| GccBuildError::file_operation(
                            "unpack".to_string(),
                            archive_path.display().to_string(),
                            e.to_string(),
                        ))?;
                }
            }
            _ => {
                return Err(GccBuildError::file_operation(
                    "extract".to_string(),
                    archive_path.display().to_string(),
                    format!("Unsupported archive format: {}", extension),
                ));
            }
        }
        
        logger.finish();
        Ok(())
    }
    
    /// Create symbolic link with conflict detection
    pub fn create_symlink(
        &self,
        target: &Path,
        link_path: &Path,
        force: bool,
    ) -> GccResult<()> {
        if self.dry_run {
            info!("Dry run: would create symlink {:?} -> {:?}", link_path, target);
            return Ok(());
        }
        
        // Check for conflicts
        if link_path.exists() && !force {
            if link_path.is_symlink() {
                let current_target = fs::read_link(link_path)
                    .map_err(|e| GccBuildError::file_operation(
                        "read_link".to_string(),
                        link_path.display().to_string(),
                        e.to_string(),
                    ))?;
                
                if current_target == target {
                    debug!("Symlink already correct: {:?} -> {:?}", link_path, target);
                    return Ok(());
                }
            } else {
                warn!("Non-symlink file exists at {:?}, skipping", link_path);
                return Err(GccBuildError::file_operation(
                    "create_symlink".to_string(),
                    link_path.display().to_string(),
                    "Non-symlink file exists".to_string(),
                ));
            }
        }
        
        // Remove existing link/file if force is true
        if force && link_path.exists() {
            fs::remove_file(link_path)
                .map_err(|e| GccBuildError::file_operation(
                    "remove".to_string(),
                    link_path.display().to_string(),
                    e.to_string(),
                ))?;
        }
        
        // Create the symlink
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(target, link_path)
                .map_err(|e| GccBuildError::file_operation(
                    "symlink".to_string(),
                    link_path.display().to_string(),
                    e.to_string(),
                ))?;
        }
        
        #[cfg(windows)]
        {
            std::os::windows::fs::symlink_file(target, link_path)
                .map_err(|e| GccBuildError::file_operation(
                    "symlink".to_string(),
                    link_path.display().to_string(),
                    e.to_string(),
                ))?;
        }
        
        debug!("Created symlink: {:?} -> {:?}", link_path, target);
        Ok(())
    }
    
    /// Get file size in different units
    pub fn get_file_size(&self, file_path: &Path, unit: SizeUnit) -> GccResult<u64> {
        if !file_path.exists() {
            return Ok(0);
        }
        
        let metadata = file_path.metadata()
            .map_err(|e| GccBuildError::file_operation(
                "metadata".to_string(),
                file_path.display().to_string(),
                e.to_string(),
            ))?;
        
        let size_bytes = metadata.len();
        
        Ok(match unit {
            SizeUnit::Bytes => size_bytes,
            SizeUnit::KB => size_bytes / 1024,
            SizeUnit::MB => size_bytes / (1024 * 1024),
            SizeUnit::GB => size_bytes / (1024 * 1024 * 1024),
        })
    }
    
    /// Copy file with progress tracking
    pub fn copy_file_with_progress(
        &self,
        source: &Path,
        destination: &Path,
    ) -> GccResult<()> {
        let logger = ProgressLogger::new(&format!("Copying {}", source.display()));
        
        if self.dry_run {
            info!("Dry run: would copy {:?} to {:?}", source, destination);
            logger.finish();
            return Ok(());
        }
        
        // Create destination directory if needed
        if let Some(parent) = destination.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| GccBuildError::file_operation(
                    "create_dir_all".to_string(),
                    parent.display().to_string(),
                    e.to_string(),
                ))?;
        }
        
        fs::copy(source, destination)
            .map_err(|e| GccBuildError::file_operation(
                "copy".to_string(),
                format!("{} -> {}", source.display(), destination.display()),
                e.to_string(),
            ))?;
        
        logger.finish();
        Ok(())
    }
    
    /// Remove file or directory
    pub fn remove_path(&self, path: &Path) -> GccResult<()> {
        if self.dry_run {
            info!("Dry run: would remove {:?}", path);
            return Ok(());
        }
        
        if !path.exists() {
            return Ok(());
        }
        
        if path.is_dir() {
            fs::remove_dir_all(path)
                .map_err(|e| GccBuildError::file_operation(
                    "remove_dir_all".to_string(),
                    path.display().to_string(),
                    e.to_string(),
                ))?;
        } else {
            fs::remove_file(path)
                .map_err(|e| GccBuildError::file_operation(
                    "remove_file".to_string(),
                    path.display().to_string(),
                    e.to_string(),
                ))?;
        }
        
        debug!("Removed: {:?}", path);
        Ok(())
    }
    
    /// Write content to file
    pub fn write_file(&self, path: &Path, content: &str) -> GccResult<()> {
        if self.dry_run {
            info!("Dry run: would write to {:?}", path);
            return Ok(());
        }
        
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| GccBuildError::file_operation(
                    "create_dir_all".to_string(),
                    parent.display().to_string(),
                    e.to_string(),
                ))?;
        }
        
        fs::write(path, content)
            .map_err(|e| GccBuildError::file_operation(
                "write".to_string(),
                path.display().to_string(),
                e.to_string(),
            ))?;
        
        debug!("Wrote file: {:?}", path);
        Ok(())
    }
}

#[derive(Debug, Clone)]
pub enum FileValidationType {
    Exists,
    Readable,
    Writable,
    Executable,
    Tarball,
    Checksum(String),
}

#[derive(Debug, Clone)]
pub enum SizeUnit {
    Bytes,
    KB,
    MB,
    GB,
}

/// Verify checksum of a downloaded file against expected value
pub async fn verify_checksum(
    file_path: &Path,
    expected_checksum: &str,
    dry_run: bool,
) -> GccResult<()> {
    if dry_run {
        info!("Dry run: would verify checksum for {:?}", file_path);
        return Ok(());
    }
    
    let file_ops = FileOperations::new(false);
    let actual_checksum = file_ops.calculate_checksum(file_path)?;
    
    if actual_checksum.to_lowercase() != expected_checksum.to_lowercase() {
        return Err(GccBuildError::checksum_mismatch(
            expected_checksum.to_string(),
            actual_checksum,
        ));
    }
    
    info!("Checksum verification passed for {:?}", file_path);
    Ok(())
}