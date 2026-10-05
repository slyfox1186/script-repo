use indicatif::{ProgressBar, ProgressStyle};
use std::time::Duration;

/// Create a download progress bar
pub fn create_download_bar(total_size: u64) -> ProgressBar {
    let pb = ProgressBar::new(total_size);
    pb.set_style(
        ProgressStyle::with_template(
            "{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({bytes_per_sec}, {eta})"
        )
        .unwrap()
        .progress_chars("█▓▒░ ")
    );
    pb.enable_steady_tick(Duration::from_millis(100));
    pb
}

/// Summary statistics for build results
#[derive(Debug, Default)]
pub struct BuildSummary {
    pub successful: Vec<String>,
    pub failed: Vec<(String, String)>,  // (version, error)
    pub skipped: Vec<(String, String)>, // (version, reason)
    pub total_duration_secs: u64,
}

impl BuildSummary {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn add_success(&mut self, version: String) {
        self.successful.push(version);
    }

    pub fn add_failure(&mut self, version: String, error: String) {
        self.failed.push((version, error));
    }

    pub fn add_skipped(&mut self, version: String, reason: String) {
        self.skipped.push((version, reason));
    }

    pub fn total_builds(&self) -> usize {
        self.successful.len() + self.failed.len() + self.skipped.len()
    }

    pub fn success_rate(&self) -> f64 {
        if self.total_builds() == 0 {
            return 0.0;
        }
        (self.successful.len() as f64 / self.total_builds() as f64) * 100.0
    }

    pub fn print_summary(&self) {
        use crate::logging::{format_duration, print_box, print_header};
        use console::style;

        print_header("GCC BUILD SUMMARY REPORT");

        // Build results
        let mut content = Vec::new();

        for version in &self.successful {
            content.push(format!("{} GCC {} - SUCCESS", style("[OK]").green(), version));
        }

        for (version, error) in &self.failed {
            content.push(format!(
                "{} GCC {} - FAILED: {}",
                style("[FAIL]").red(),
                version,
                error
            ));
        }

        for (version, reason) in &self.skipped {
            content.push(format!(
                "{} GCC {} - SKIPPED: {}",
                style("[SKIP]").yellow(),
                version,
                reason
            ));
        }

        print_box("BUILD RESULTS", &content);

        // Statistics
        eprintln!();
        eprintln!("Total Versions: {}", self.total_builds());
        eprintln!("Successful: {}", style(self.successful.len()).green());
        eprintln!("Failed: {}", style(self.failed.len()).red());
        eprintln!("Skipped: {}", style(self.skipped.len()).yellow());
        eprintln!("Success Rate: {:.1}%", self.success_rate());
        eprintln!(
            "Total Time: {}",
            format_duration(self.total_duration_secs)
        );
        eprintln!();
    }
}
