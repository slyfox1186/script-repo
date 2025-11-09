#![allow(dead_code)]
use crate::commands::CommandExecutor;
use crate::error::{GccBuildError, Result as GccResult};
use crate::progress::BuildProgressTracker;
use log::{debug, info, warn};
use std::time::{Duration, Instant};

/// Mirror manager with automatic failover for resilient downloads
pub struct MirrorManager {
    mirrors: Vec<Mirror>,
    executor: CommandExecutor,
    timeout: Duration,
    max_retries_per_mirror: usize,
}

#[derive(Debug, Clone)]
struct Mirror {
    name: String,
    base_url: String,
    priority: u8, // Lower = higher priority
    last_success: Option<Instant>,
    failure_count: usize,
    max_failures: usize,
    avg_speed_mbps: f64,
}

impl MirrorManager {
    pub fn new(executor: CommandExecutor) -> Self {
        let mirrors = vec![
            Mirror {
                name: "GNU Main".to_string(),
                base_url: "https://ftp.gnu.org/gnu/gcc/".to_string(),
                priority: 1,
                last_success: None,
                failure_count: 0,
                max_failures: 3,
                avg_speed_mbps: 0.0,
            },
            Mirror {
                name: "MIT".to_string(),
                base_url: "https://mirrors.mit.edu/gnu/gcc/".to_string(),
                priority: 2,
                last_success: None,
                failure_count: 0,
                max_failures: 3,
                avg_speed_mbps: 0.0,
            },
            Mirror {
                name: "Kernel.org".to_string(),
                base_url: "https://mirrors.kernel.org/gnu/gcc/".to_string(),
                priority: 3,
                last_success: None,
                failure_count: 0,
                max_failures: 3,
                avg_speed_mbps: 0.0,
            },
            Mirror {
                name: "GNU FTP".to_string(),
                base_url: "ftp://ftp.gnu.org/gnu/gcc/".to_string(),
                priority: 4,
                last_success: None,
                failure_count: 0,
                max_failures: 3,
                avg_speed_mbps: 0.0,
            },
            Mirror {
                name: "CTAN".to_string(),
                base_url: "https://mirror.ctan.org/gnu/gcc/".to_string(),
                priority: 5,
                last_success: None,
                failure_count: 0,
                max_failures: 3,
                avg_speed_mbps: 0.0,
            },
        ];

        Self {
            mirrors,
            executor,
            timeout: Duration::from_secs(300), // 5 minutes
            max_retries_per_mirror: 2,
        }
    }

    /// Download a file with automatic mirror failover
    pub async fn download_with_failover(
        &mut self,
        relative_path: &str,
        destination: &std::path::Path,
        progress_tracker: Option<&BuildProgressTracker>,
    ) -> GccResult<()> {
        info!("📥 Downloading {} with mirror failover", relative_path);

        // Sort mirrors by priority and health
        self.sort_mirrors_by_health();

        let mut last_error = None;

        // Create a vector of indices for healthy mirrors to avoid borrowing conflicts
        let healthy_indices: Vec<usize> = self
            .mirrors
            .iter()
            .enumerate()
            .filter(|(_, mirror)| self.is_mirror_healthy(mirror))
            .map(|(i, _)| i)
            .collect();

        for &mirror_index in &healthy_indices {
            let url = format!("{}{}", self.mirrors[mirror_index].base_url, relative_path);
            let mirror_name = self.mirrors[mirror_index].name.clone();

            info!("🔗 Trying mirror: {} ({})", mirror_name, url);

            match self
                .download_from_mirror_by_index(mirror_index, &url, destination, progress_tracker)
                .await
            {
                Ok(_) => {
                    self.mirrors[mirror_index].last_success = Some(Instant::now());
                    self.mirrors[mirror_index].failure_count = 0;
                    info!("✅ Successfully downloaded from {}", mirror_name);
                    return Ok(());
                }
                Err(e) => {
                    warn!("❌ Download failed from {}: {}", mirror_name, e);
                    self.mirrors[mirror_index].failure_count += 1;
                    last_error = Some(e);

                    // Small delay before trying next mirror
                    tokio::time::sleep(Duration::from_secs(2)).await;
                }
            }
        }

        Err(last_error.unwrap_or_else(|| {
            GccBuildError::download(relative_path.to_string(), "All mirrors failed".to_string())
        }))
    }

    /// Download from a specific mirror by index
    async fn download_from_mirror_by_index(
        &mut self,
        mirror_index: usize,
        url: &str,
        destination: &std::path::Path,
        progress_tracker: Option<&BuildProgressTracker>,
    ) -> GccResult<()> {
        let mirror_name = self.mirrors[mirror_index].name.clone();

        let start_time = Instant::now();

        // Create progress bar if tracker provided
        let progress_bar = progress_tracker.map(|tracker| {
            tracker.create_download_progress(
                &format!("from {}", mirror_name),
                0, // We don't know size yet
            )
        });

        for attempt in 1..=self.max_retries_per_mirror {
            debug!(
                "Attempt {}/{} for {}",
                attempt, self.max_retries_per_mirror, url
            );

            match self.download_single_attempt(url, destination).await {
                Ok(_) => {
                    let duration = start_time.elapsed();
                    let file_size = destination.metadata().map(|m| m.len()).unwrap_or(0) as f64;

                    // Calculate speed
                    if duration.as_secs() > 0 {
                        let mbps = (file_size / 1_000_000.0) / duration.as_secs_f64();
                        let mirror = &mut self.mirrors[mirror_index];
                        mirror.avg_speed_mbps = if mirror.avg_speed_mbps > 0.0 {
                            (mirror.avg_speed_mbps + mbps) / 2.0
                        } else {
                            mbps
                        };

                        info!("📊 Download speed: {:.1} MB/s", mbps);
                    }

                    if let Some(pb) = progress_bar {
                        pb.finish_with_message("Download completed");
                    }

                    return Ok(());
                }
                Err(e) => {
                    if attempt < self.max_retries_per_mirror {
                        warn!("Attempt {} failed, retrying in 5 seconds: {}", attempt, e);
                        tokio::time::sleep(Duration::from_secs(5)).await;
                    } else {
                        if let Some(pb) = progress_bar {
                            pb.abandon_with_message("Download failed");
                        }
                        return Err(e);
                    }
                }
            }
        }

        unreachable!()
    }

    /// Download from a specific mirror
    async fn download_from_mirror(
        &self,
        mirror: &mut Mirror,
        url: &str,
        destination: &std::path::Path,
        progress_tracker: Option<&BuildProgressTracker>,
    ) -> GccResult<()> {
        let start_time = Instant::now();

        // Create progress bar if tracker provided
        let progress_bar = if let Some(tracker) = progress_tracker {
            Some(tracker.create_download_progress(
                &format!("from {}", mirror.name),
                0, // We don't know size yet
            ))
        } else {
            None
        };

        for attempt in 1..=self.max_retries_per_mirror {
            debug!(
                "Attempt {}/{} for {}",
                attempt, self.max_retries_per_mirror, url
            );

            match self.download_single_attempt(url, destination).await {
                Ok(_) => {
                    let duration = start_time.elapsed();
                    let file_size = destination.metadata().map(|m| m.len()).unwrap_or(0) as f64;

                    // Calculate speed
                    if duration.as_secs() > 0 {
                        let mbps = (file_size / 1_000_000.0) / duration.as_secs_f64();
                        mirror.avg_speed_mbps = if mirror.avg_speed_mbps > 0.0 {
                            (mirror.avg_speed_mbps + mbps) / 2.0
                        } else {
                            mbps
                        };

                        info!("📊 Download speed: {:.1} MB/s", mbps);
                    }

                    if let Some(pb) = progress_bar {
                        pb.finish_with_message("Download completed");
                    }

                    return Ok(());
                }
                Err(e) => {
                    if attempt < self.max_retries_per_mirror {
                        warn!("Attempt {} failed, retrying in 5 seconds: {}", attempt, e);
                        tokio::time::sleep(Duration::from_secs(5)).await;
                    } else {
                        if let Some(pb) = progress_bar {
                            pb.abandon_with_message("Download failed");
                        }
                        return Err(e);
                    }
                }
            }
        }

        unreachable!()
    }

    /// Single download attempt
    async fn download_single_attempt(
        &self,
        url: &str,
        destination: &std::path::Path,
    ) -> GccResult<()> {
        // Use curl with progress and resume support
        let timeout_str = self.timeout.as_secs().to_string();
        let mut args = vec![
            "-fSL",
            "--connect-timeout",
            "30",
            "--max-time",
            &timeout_str,
            "--retry",
            "0", // We handle retries ourselves
            "-o",
            destination.to_str().unwrap(),
        ];

        // Add resume support if file exists
        if destination.exists() {
            args.extend(&["-C", "-"]); // Resume from where we left off
            info!("🔄 Resuming download...");
        }

        args.push(url);

        self.executor
            .execute("curl", args)
            .await
            .map_err(|e| GccBuildError::download(url.to_string(), e.to_string()))
    }

    /// Sort mirrors by health and priority
    fn sort_mirrors_by_health(&mut self) {
        // Create a separate vector with scores to avoid borrowing issues
        let mut mirror_scores: Vec<(usize, bool, f64)> = self
            .mirrors
            .iter()
            .enumerate()
            .map(|(i, mirror)| {
                let healthy = mirror.failure_count < mirror.max_failures;
                let score = self.calculate_mirror_score(mirror);
                (i, healthy, score)
            })
            .collect();

        // Sort by health first, then by score
        mirror_scores.sort_by(|a, b| match (a.1, b.1) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            (true, true) => b.2.partial_cmp(&a.2).unwrap_or(std::cmp::Ordering::Equal),
            (false, false) => {
                let a_mirror = &self.mirrors[a.0];
                let b_mirror = &self.mirrors[b.0];
                a_mirror.failure_count.cmp(&b_mirror.failure_count)
            }
        });

        // Reorder mirrors based on sorted indices
        let original_mirrors = self.mirrors.clone();
        for (new_pos, (old_pos, _, _)) in mirror_scores.into_iter().enumerate() {
            self.mirrors[new_pos] = original_mirrors[old_pos].clone();
        }
    }

    /// Check if mirror is healthy
    fn is_mirror_healthy(&self, mirror: &Mirror) -> bool {
        mirror.failure_count < mirror.max_failures
    }

    /// Calculate mirror score (higher is better)
    fn calculate_mirror_score(&self, mirror: &Mirror) -> f64 {
        let mut score = 100.0;

        // Subtract for lower priority (higher number = lower priority)
        score -= mirror.priority as f64 * 10.0;

        // Add for recent success
        if let Some(last_success) = mirror.last_success {
            let hours_since = last_success.elapsed().as_secs_f64() / 3600.0;
            score += (24.0 - hours_since.min(24.0)) * 2.0; // Recent success bonus
        }

        // Add for speed
        score += mirror.avg_speed_mbps * 5.0;

        // Subtract for failures
        score -= mirror.failure_count as f64 * 20.0;

        score.max(0.0)
    }

    /// Test mirror connectivity
    pub async fn test_mirrors(&mut self) -> GccResult<()> {
        info!("🔍 Testing mirror connectivity...");

        let test_file = "gcc-13.2.0/gcc-13.2.0.tar.xz.sig"; // Small signature file

        for mirror in &mut self.mirrors {
            let url = format!("{}{}", mirror.base_url, test_file);

            debug!("Testing {}: {}", mirror.name, url);

            let start = Instant::now();
            match tokio::time::timeout(
                Duration::from_secs(10),
                self.executor.execute("curl", ["-fsSI", &url]),
            )
            .await
            {
                Ok(Ok(_)) => {
                    let latency = start.elapsed().as_millis();
                    info!("✅ {} - OK ({}ms)", mirror.name, latency);
                    mirror.failure_count = 0;
                    mirror.last_success = Some(Instant::now());
                }
                Ok(Err(_)) | Err(_) => {
                    warn!("❌ {} - Failed", mirror.name);
                    mirror.failure_count += 1;
                }
            }
        }

        // Sort by health after testing
        self.sort_mirrors_by_health();

        let healthy_count = self
            .mirrors
            .iter()
            .filter(|m| self.is_mirror_healthy(m))
            .count();

        info!(
            "📊 Mirror health: {}/{} mirrors available",
            healthy_count,
            self.mirrors.len()
        );

        if healthy_count == 0 {
            return Err(GccBuildError::network_timeout(
                "No healthy mirrors available".to_string(),
            ));
        }

        Ok(())
    }

    /// Get mirror statistics
    pub fn get_stats(&self) -> MirrorStats {
        let healthy = self
            .mirrors
            .iter()
            .filter(|m| self.is_mirror_healthy(m))
            .count();

        let avg_speed = self
            .mirrors
            .iter()
            .filter(|m| m.avg_speed_mbps > 0.0)
            .map(|m| m.avg_speed_mbps)
            .sum::<f64>()
            / self.mirrors.len() as f64;

        MirrorStats {
            total_mirrors: self.mirrors.len(),
            healthy_mirrors: healthy,
            average_speed_mbps: avg_speed,
            best_mirror: self
                .mirrors
                .first()
                .map(|m| m.name.clone())
                .unwrap_or_default(),
        }
    }

    /// Reset all mirror statistics
    pub fn reset_stats(&mut self) {
        for mirror in &mut self.mirrors {
            mirror.failure_count = 0;
            mirror.last_success = None;
            mirror.avg_speed_mbps = 0.0;
        }
        info!("🔄 Mirror statistics reset");
    }
}

#[derive(Debug)]
pub struct MirrorStats {
    pub total_mirrors: usize,
    pub healthy_mirrors: usize,
    pub average_speed_mbps: f64,
    pub best_mirror: String,
}
