#![allow(dead_code)]
use chrono::{Duration as ChronoDuration, Local};
use indicatif::{MultiProgress, ProgressBar, ProgressDrawTarget, ProgressState, ProgressStyle};
use log::info;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Tracks progress for various build phases with ETA calculations
#[derive(Clone)]
pub struct BuildProgressTracker {
    multi: Arc<MultiProgress>,
    bars: Arc<Mutex<HashMap<String, ProgressBar>>>,
    phase_history: Arc<Mutex<PhaseHistory>>,
    start_time: Instant,
}

#[derive(Default)]
struct PhaseHistory {
    /// Historical durations for each phase type (in seconds)
    durations: HashMap<String, Vec<f64>>,
}

impl PhaseHistory {
    fn add_duration(&mut self, phase: &str, duration: Duration) {
        let secs = duration.as_secs_f64();
        self.durations
            .entry(phase.to_string())
            .or_default()
            .push(secs);
    }

    fn estimate_duration(&self, phase: &str) -> Option<Duration> {
        self.durations.get(phase).and_then(|durations| {
            if durations.is_empty() {
                None
            } else {
                // Use average of last 3 builds for estimation
                let recent: Vec<f64> = durations.iter().rev().take(3).copied().collect();
                let avg = recent.iter().sum::<f64>() / recent.len() as f64;
                Some(Duration::from_secs_f64(avg))
            }
        })
    }
}

impl BuildProgressTracker {
    pub fn new() -> Self {
        let multi = MultiProgress::new();
        multi.set_draw_target(ProgressDrawTarget::stderr());

        Self {
            multi: Arc::new(multi),
            bars: Arc::new(Mutex::new(HashMap::new())),
            phase_history: Arc::new(Mutex::new(PhaseHistory::default())),
            start_time: Instant::now(),
        }
    }

    /// Create a progress bar for downloads with size tracking
    pub fn create_download_progress(&self, name: &str, total_size: u64) -> ProgressBar {
        let pb = self.multi.add(ProgressBar::new(total_size));

        pb.set_style(
            ProgressStyle::default_bar()
                .template("{spinner:.green} [{elapsed_precise}] {msg}\n{wide_bar:.cyan/blue} {bytes}/{total_bytes} ({bytes_per_sec}, {eta})")
                .unwrap()
                .progress_chars("#>-")
        );

        pb.set_message(format!("Downloading {}", name));

        let mut bars = self.bars.lock().unwrap();
        bars.insert(format!("download_{}", name), pb.clone());

        pb
    }

    /// Create a progress bar for extraction operations
    pub fn create_extract_progress(&self, name: &str, file_count: u64) -> ProgressBar {
        let pb = self.multi.add(ProgressBar::new(file_count));

        pb.set_style(
            ProgressStyle::default_bar()
                .template("{spinner:.green} [{elapsed_precise}] {msg}\n{wide_bar:.yellow/blue} {pos}/{len} files ({per_sec}, {eta})")
                .unwrap()
                .progress_chars("#>-")
        );

        pb.set_message(format!("Extracting {}", name));

        let mut bars = self.bars.lock().unwrap();
        bars.insert(format!("extract_{}", name), pb.clone());

        pb
    }

    /// Create a progress bar for build operations with ETA
    pub fn create_build_progress(&self, name: &str, phase: &str) -> ProgressBar {
        let pb = self.multi.add(ProgressBar::new(100));

        // Get historical estimate if available
        let eta_msg = self
            .phase_history
            .lock()
            .unwrap()
            .estimate_duration(phase)
            .map(|d| format!(" (estimated: {})", humanize_duration(d)))
            .unwrap_or_default();

        pb.set_style(
            ProgressStyle::default_bar()
                .template("{spinner:.green} [{elapsed_precise}] {msg}\n{wide_bar:.cyan/blue} {pos}% | ETA: {eta_precise}")
                .unwrap()
                .with_key("eta_precise", |state: &ProgressState, w: &mut dyn std::fmt::Write| {
                    let elapsed = state.elapsed().as_secs_f64();
                    let pos = state.pos() as f64;
                    if pos > 0.0 {
                        let total_estimate = (elapsed / pos) * 100.0;
                        let remaining = total_estimate - elapsed;
                        let eta = Local::now() + ChronoDuration::seconds(remaining as i64);
                        write!(w, "{}", eta.format("%H:%M:%S")).unwrap();
                    } else {
                        write!(w, "calculating...").unwrap();
                    }
                })
                .progress_chars("#>-")
        );

        pb.set_message(format!("{}: {}{}", name, phase, eta_msg));

        let mut bars = self.bars.lock().unwrap();
        bars.insert(format!("build_{}_{}", name, phase), pb.clone());

        pb
    }

    /// Create a spinner for operations without clear progress
    pub fn create_spinner(&self, message: &str) -> ProgressBar {
        let pb = self.multi.add(ProgressBar::new_spinner());

        pb.set_style(
            ProgressStyle::default_spinner()
                .template("{spinner:.green} [{elapsed_precise}] {msg}")
                .unwrap(),
        );

        pb.enable_steady_tick(Duration::from_millis(100));
        pb.set_message(message.to_string());

        pb
    }

    /// Update build phase progress based on log output
    pub fn update_build_progress(&self, gcc_version: &str, phase: &str, line: &str) {
        let key = format!("build_{}_{}", gcc_version, phase);

        if let Some(pb) = self.bars.lock().unwrap().get(&key) {
            // Try to extract progress from common patterns
            if let Some(percent) = extract_progress_percentage(line) {
                pb.set_position(percent);
                pb.set_message(format!("GCC {}: {} ({}%)", gcc_version, phase, percent));
            }
        }
    }

    /// Record phase completion for future ETA calculations
    pub fn complete_phase(&self, phase: &str, duration: Duration) {
        self.phase_history
            .lock()
            .unwrap()
            .add_duration(phase, duration);
        info!(
            "Phase '{}' completed in {}",
            phase,
            humanize_duration(duration)
        );
    }

    /// Create a dashboard view for parallel builds
    pub fn create_parallel_dashboard(&self, versions: &[String]) -> Vec<ProgressBar> {
        let mut dashboard_bars = Vec::new();

        for version in versions {
            let pb = self.multi.add(ProgressBar::new(100));
            pb.set_style(
                ProgressStyle::default_bar()
                    .template(&format!("GCC {} {{spinner:.green}} [{{elapsed_precise}}] {{msg}}\n{{wide_bar:.cyan/blue}} {{pos}}%", version))
                    .unwrap()
                    .progress_chars("#>-")
            );
            pb.set_message("Waiting to start...");
            dashboard_bars.push(pb);
        }

        dashboard_bars
    }

    /// Get overall build statistics
    pub fn get_statistics(&self) -> BuildStatistics {
        let elapsed = self.start_time.elapsed();
        let bars = self.bars.lock().unwrap();

        let completed = bars.values().filter(|pb| pb.is_finished()).count();
        let total = bars.len();

        BuildStatistics {
            elapsed,
            completed_tasks: completed,
            total_tasks: total,
            average_task_time: if completed > 0 {
                Some(elapsed / completed as u32)
            } else {
                None
            },
        }
    }
}

#[derive(Debug)]
pub struct BuildStatistics {
    pub elapsed: Duration,
    pub completed_tasks: usize,
    pub total_tasks: usize,
    pub average_task_time: Option<Duration>,
}

/// Extract progress percentage from common build output patterns
fn extract_progress_percentage(line: &str) -> Option<u64> {
    // Pattern 1: "[50%] Building..."
    if let Some(start) = line.find('[') {
        if let Some(end) = line[start..].find('%') {
            let percent_str = &line[start + 1..start + end];
            return percent_str.parse().ok();
        }
    }

    // Pattern 2: "Progress: 50%"
    if line.contains("Progress:") || line.contains("progress:") {
        let parts: Vec<&str> = line.split_whitespace().collect();
        for (i, part) in parts.iter().enumerate() {
            if part.to_lowercase().contains("progress") && i + 1 < parts.len() {
                if let Some(percent_str) = parts[i + 1].strip_suffix('%') {
                    return percent_str.parse().ok();
                }
            }
        }
    }

    // Pattern 3: "50/100" or "50 of 100"
    if let Some(slash_pos) = line.find('/') {
        let before = line[..slash_pos].split_whitespace().last();
        let after = line[slash_pos + 1..].split_whitespace().next();

        if let (Some(current), Some(total)) = (before, after) {
            if let (Ok(current), Ok(total)) = (current.parse::<f64>(), total.parse::<f64>()) {
                if total > 0.0 {
                    return Some((current / total * 100.0) as u64);
                }
            }
        }
    }

    None
}

/// Convert duration to human-readable format
fn humanize_duration(duration: Duration) -> String {
    let secs = duration.as_secs();
    if secs < 60 {
        format!("{}s", secs)
    } else if secs < 3600 {
        format!("{}m {}s", secs / 60, secs % 60)
    } else {
        format!("{}h {}m", secs / 3600, (secs % 3600) / 60)
    }
}

/// Progress adapter for integration with existing logging
pub struct ProgressLogger {
    tracker: BuildProgressTracker,
    spinner: Option<ProgressBar>,
    phase_start: Instant,
    current_phase: String,
}

impl ProgressLogger {
    pub fn new_with_tracker(operation: &str, tracker: BuildProgressTracker) -> Self {
        let spinner = Some(tracker.create_spinner(operation));
        Self {
            tracker,
            spinner,
            phase_start: Instant::now(),
            current_phase: operation.to_string(),
        }
    }

    pub fn update(&self, message: &str) {
        if let Some(spinner) = &self.spinner {
            spinner.set_message(format!("{}: {}", self.current_phase, message));
        }
    }

    pub fn finish_with_message(self, message: &str) {
        let duration = self.phase_start.elapsed();
        if let Some(spinner) = self.spinner {
            spinner.finish_with_message(format!("✓ {} ({})", message, humanize_duration(duration)));
        }
        self.tracker.complete_phase(&self.current_phase, duration);
    }
}
