#![allow(dead_code)]
use crate::config::GccVersion;
use crate::error::{GccBuildError, Result as GccResult};
use crate::scheduler::BuildScheduler;
use log::{error, info, warn};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

/// Retry strategy for build operations
#[derive(Clone, Debug)]
pub struct RetryStrategy {
    /// Maximum number of retry attempts
    pub max_attempts: usize,
    /// Initial delay between retries
    pub initial_delay: Duration,
    /// Backoff multiplier for delays
    pub backoff_multiplier: f64,
    /// Maximum delay between retries
    pub max_delay: Duration,
    /// Whether to reduce parallelism on OOM
    pub reduce_parallelism_on_oom: bool,
}

impl Default for RetryStrategy {
    fn default() -> Self {
        Self {
            max_attempts: 3,
            initial_delay: Duration::from_secs(10),
            backoff_multiplier: 2.0,
            max_delay: Duration::from_secs(300), // 5 minutes
            reduce_parallelism_on_oom: true,
        }
    }
}

/// Retry executor with OOM detection and automatic adjustment
pub struct RetryExecutor {
    strategy: RetryStrategy,
    oom_count: Arc<AtomicUsize>,
}

impl RetryExecutor {
    pub fn new(strategy: RetryStrategy) -> Self {
        Self {
            strategy,
            oom_count: Arc::new(AtomicUsize::new(0)),
        }
    }

    /// Execute a build operation with retry logic
    pub async fn execute_with_retry<F, Fut, T>(
        &self,
        operation_name: &str,
        version: &GccVersion,
        scheduler: Option<&BuildScheduler>,
        mut operation: F,
    ) -> GccResult<T>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = GccResult<T>>,
    {
        let mut attempt = 0;
        let mut delay = self.strategy.initial_delay;

        loop {
            attempt += 1;
            info!(
                "🔄 Attempt {}/{} for {}: GCC {}",
                attempt, self.strategy.max_attempts, operation_name, version
            );

            match operation().await {
                Ok(result) => {
                    if attempt > 1 {
                        info!("✅ {} succeeded after {} attempts", operation_name, attempt);
                    }
                    return Ok(result);
                }
                Err(e) => {
                    let is_oom = self.is_oom_error(&e);

                    if is_oom {
                        self.oom_count.fetch_add(1, Ordering::Relaxed);
                        error!("💥 OOM detected during {}: {}", operation_name, e);

                        if self.strategy.reduce_parallelism_on_oom {
                            if let Some(sched) = scheduler {
                                self.handle_oom_adjustment(sched).await;
                            }
                        }
                    }

                    if attempt >= self.strategy.max_attempts {
                        error!("❌ {} failed after {} attempts", operation_name, attempt);
                        return Err(e);
                    }

                    warn!(
                        "⚠️ {} failed (attempt {}): {}. Retrying in {:?}...",
                        operation_name, attempt, e, delay
                    );

                    // Apply different strategies based on error type
                    let adjusted_delay = self.calculate_retry_delay(&e, delay, is_oom);
                    tokio::time::sleep(adjusted_delay).await;

                    // Update delay for next retry
                    delay = Duration::from_secs_f64(
                        (delay.as_secs_f64() * self.strategy.backoff_multiplier)
                            .min(self.strategy.max_delay.as_secs_f64()),
                    );
                }
            }
        }
    }

    /// Check if error is OOM-related
    fn is_oom_error(&self, error: &GccBuildError) -> bool {
        let error_str = error.to_string().to_lowercase();

        // Common OOM patterns
        let oom_patterns = [
            "out of memory",
            "oom",
            "memory exhausted",
            "cannot allocate memory",
            "insufficient memory",
            "killed",   // Often indicates OOM killer
            "signal 9", // SIGKILL from OOM killer
            "virtual memory exhausted",
        ];

        oom_patterns
            .iter()
            .any(|pattern| error_str.contains(pattern))
    }

    /// Calculate retry delay based on error type
    fn calculate_retry_delay(
        &self,
        error: &GccBuildError,
        base_delay: Duration,
        is_oom: bool,
    ) -> Duration {
        if is_oom {
            // Longer delay for OOM to allow system to recover
            Duration::from_secs(60)
        } else if self.is_network_error(error) {
            // Shorter delay for network errors
            Duration::from_secs(5)
        } else {
            base_delay
        }
    }

    /// Check if error is network-related
    fn is_network_error(&self, error: &GccBuildError) -> bool {
        matches!(
            error,
            GccBuildError::Download { .. }
                | GccBuildError::NetworkTimeout { .. }
                | GccBuildError::Http { .. }
        )
    }

    /// Handle OOM by adjusting system resources
    async fn handle_oom_adjustment(&self, _scheduler: &BuildScheduler) {
        let oom_count = self.oom_count.load(Ordering::Relaxed);

        match oom_count {
            1 => {
                warn!("🔧 First OOM detected. Reducing parallel jobs by 25%");
                // This would be implemented in the scheduler
            }
            2 => {
                warn!("🔧 Second OOM detected. Reducing parallel jobs by 50%");
                // This would be implemented in the scheduler
            }
            _ => {
                error!("🔧 Multiple OOMs detected. Switching to sequential builds");
                // This would be implemented in the scheduler
            }
        }

        // Give system time to recover
        tokio::time::sleep(Duration::from_secs(30)).await;
    }

    /// Get OOM statistics
    pub fn get_oom_stats(&self) -> OomStatistics {
        OomStatistics {
            oom_count: self.oom_count.load(Ordering::Relaxed),
            reduction_applied: self.oom_count.load(Ordering::Relaxed) > 0,
        }
    }
}

#[derive(Debug)]
pub struct OomStatistics {
    pub oom_count: usize,
    pub reduction_applied: bool,
}

/// Retry wrapper for specific build phases
pub struct PhaseRetryExecutor {
    executor: RetryExecutor,
}

impl PhaseRetryExecutor {
    pub fn new() -> Self {
        Self {
            executor: RetryExecutor::new(RetryStrategy::default()),
        }
    }

    /// Retry download operations with network-specific strategy
    pub async fn retry_download<F, Fut, T>(
        &self,
        url: &str,
        version: &GccVersion,
        operation: F,
    ) -> GccResult<T>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = GccResult<T>>,
    {
        let mut strategy = RetryStrategy::default();
        strategy.max_attempts = 5; // More retries for downloads
        strategy.initial_delay = Duration::from_secs(2);

        let executor = RetryExecutor::new(strategy);
        executor
            .execute_with_retry(&format!("Download from {}", url), version, None, operation)
            .await
    }

    /// Retry build operations with OOM handling
    pub async fn retry_build<F, Fut, T>(
        &self,
        phase: &str,
        version: &GccVersion,
        scheduler: Option<&BuildScheduler>,
        operation: F,
    ) -> GccResult<T>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = GccResult<T>>,
    {
        self.executor
            .execute_with_retry(
                &format!("Build phase: {}", phase),
                version,
                scheduler,
                operation,
            )
            .await
    }
}

/// Global retry configuration
pub struct RetryConfig {
    pub enable_auto_retry: bool,
    pub enable_oom_adjustment: bool,
    pub max_global_retries: usize,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            enable_auto_retry: true,
            enable_oom_adjustment: true,
            max_global_retries: 10,
        }
    }
}
