# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build/Development Commands

### Rust Implementation
- Build: `cargo build --release` (optimized) or `cargo build` (debug)
- Run: `./target/release/gcc-builder --versions 13 --verbose`
- Test: `cargo test`
- Lint: `cargo clippy -- -D warnings`
- Format: `cargo fmt`
- Type check: `cargo check`

### Bash Scripts (Legacy)
- Run bash version: `bash build-gcc.sh --dry-run -v`
- Check scripts: `shellcheck build-gcc.sh *.sh`

## High-Level Architecture

This is a high-performance Rust reimplementation of a GCC build automation script. The architecture is designed for:

1. **Parallel Build Orchestration**: Multiple GCC versions can be built simultaneously using rayon for CPU-bound parallelism
2. **Type Safety**: 100% type-safe with comprehensive error handling and zero runtime type errors
3. **System Tool Integration**: Leverages optimized system tools (curl, wget, tar) rather than reimplementing them
4. **Resource-Aware Execution**: Dynamic job allocation based on available CPU cores and memory

### Core Design Principles
- **Zero-cost abstractions**: No runtime overhead for safety features
- **Fail-fast validation**: All configuration validated upfront before expensive operations
- **Async-first**: Non-blocking I/O for downloads and monitoring (using tokio)
- **Smart resource allocation**: Automatically adjusts parallelism based on system capabilities

### Module Structure and Responsibilities

The codebase follows a modular architecture where each module has a specific responsibility:

- `main.rs`: Entry point with parallel orchestration logic and signal handling
- `build.rs`: Main build orchestration including all GCC build phases
- `cli.rs`: Command-line argument parsing using clap 4 with derive
- `config.rs`: Configuration management with compile-time validation
- `commands.rs`: Process execution utilities with retry/timeout support
- `gcc_config.rs`: GCC-specific configuration option generation
- `system.rs`: System resource validation and real-time monitoring
- `packages.rs`: Package dependency resolution and installation
- `error.rs`: Comprehensive error types using thiserror
- `logging.rs`: Structured logging with progress indicators

### Build Flow

1. **Validation Phase**: System requirements, disk space, dependencies
2. **Resolution Phase**: Resolve latest GCC versions if needed (cached)
3. **Download Phase**: Parallel downloads with retry logic
4. **Build Phase**: Configure → Make → Install with fallback strategies
5. **Post-Install Phase**: Symlinks, library cache, optional static binary saving

### Performance Optimizations

- Iterator-based parsing without intermediate allocations
- Stack-allocated paths and strings where possible
- Parallel builds with automatic CPU core allocation
- Efficient caching of version lookups
- System tools for I/O-heavy operations (tar, curl)

## Common Development Tasks

### Adding a New GCC Version
The tool automatically supports GCC versions 10-15. Version resolution happens at runtime by querying GNU FTP servers.

### Modifying Build Configuration
Edit `gcc_config.rs` to modify configure options. The system validates options based on GCC version compatibility.

### Debugging Build Failures
Use `--debug --verbose --log-file debug.log` for detailed output. Resource monitoring logs are automatically created during long builds.