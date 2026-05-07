use console::style;
use std::fs::OpenOptions;
use std::path::Path;
use tracing::Level;
use tracing_subscriber::fmt::format::FmtSpan;
use tracing_subscriber::fmt::time::ChronoLocal;
use tracing_subscriber::EnvFilter;

/// Initialize the logging system
pub fn init_logging(verbose: bool, debug: bool, log_file: Option<&Path>) -> anyhow::Result<()> {
    let level = if debug {
        Level::DEBUG
    } else if verbose {
        Level::INFO
    } else {
        Level::WARN
    };

    let filter = EnvFilter::from_default_env()
        .add_directive(level.into())
        .add_directive("reqwest=warn".parse().unwrap())
        .add_directive("hyper=warn".parse().unwrap());

    let subscriber = tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_timer(ChronoLocal::new("%Y-%m-%d %H:%M:%S".to_string()))
        .with_target(false)
        .with_span_events(FmtSpan::NONE);

    if let Some(path) = log_file {
        // Log to file
        let file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(path)?;

        subscriber.with_writer(file).with_ansi(false).init();
    } else {
        // Log to stderr with colors
        subscriber.with_writer(std::io::stderr).init();
    }

    Ok(())
}

/// Print a section header
pub fn print_header(title: &str) {
    let width = 80;
    let line = "=".repeat(width);
    eprintln!();
    eprintln!("{}", style(&line).cyan());
    eprintln!("{}", style(title).cyan().bold());
    eprintln!("{}", style(&line).cyan());
    eprintln!();
}

/// Print a box with content
pub fn print_box(title: &str, content: &[String]) {
    let width = 80;
    let top = format!("┌{}┐", "─".repeat(width - 2));
    let bottom = format!("└{}┘", "─".repeat(width - 2));

    eprintln!();
    eprintln!("{}", style(&top).cyan());
    eprintln!("│{:^width$}│", style(title).bold(), width = width - 2);
    eprintln!("{}", style(&bottom).cyan());

    for line in content {
        eprintln!("{}", line);
    }
    eprintln!();
}

/// Format duration as HH:MM:SS
pub fn format_duration(secs: u64) -> String {
    let hours = secs / 3600;
    let minutes = (secs % 3600) / 60;
    let seconds = secs % 60;
    format!("{:02}:{:02}:{:02}", hours, minutes, seconds)
}

/// Print build status log
pub fn print_status(package: &str, version: &str, stage: &str) {
    tracing::info!(
        "STATUS: Package: {}, Version: {}, Stage: {}",
        package,
        version,
        stage
    );
}
