# build-gcc

A modern, high-performance Rust tool for building GNU GCC from source with async downloads and parallel builds.

![Rust](https://img.shields.io/badge/Rust-1.75+-orange?logo=rust)
![License](https://img.shields.io/badge/License-MIT-blue)
![Platform](https://img.shields.io/badge/Platform-Linux-green)

## Overview

**build-gcc** is a complete rewrite of the traditional shell-based GCC build scripts, designed for speed, reliability, and ease of use. It leverages Rust's async runtime to download sources faster and can build multiple GCC versions in parallel, significantly reducing the time to set up a multi-version GCC development environment.

### Why This Tool?

- **Fast Downloads**: Async HTTP downloads with automatic mirror failover and retry logic
- **Parallel Builds**: Build multiple GCC versions simultaneously (e.g., GCC 12, 13, and 14 at once)
- **Interactive Mode**: User-friendly menu-driven interface when no version is specified
- **Robust Error Handling**: Comprehensive error messages and graceful failure recovery
- **Progress Tracking**: Real-time progress bars for downloads and build status updates
- **Checksum Verification**: Automatic SHA512/GPG signature verification for all downloads

## Features

- Build GCC versions 10 through 15
- Automatic dependency installation (Debian/Ubuntu)
- Interactive version selection menu
- CLI mode for automation and scripting
- Parallel multi-version builds
- Download progress bars with ETA
- CUDA/nvptx offload target detection
- Multilib (32-bit + 64-bit) support
- Static binary builds
- Custom installation prefix support
- Dry-run mode for testing
- Graceful shutdown on SIGINT/SIGTERM
- File locking to prevent concurrent runs
- Colored terminal output with logging

## Requirements

### System Requirements

| Requirement | Minimum |
|-------------|---------|
| OS | Linux (Debian/Ubuntu recommended) |
| RAM | 2 GB available |
| Disk Space | ~25 GB per GCC version |
| Rust | 1.75+ (for building from source) |

### Build Dependencies

The tool automatically installs these packages if missing:

- `build-essential`, `binutils`, `gawk`, `m4`, `flex`, `bison`
- `texinfo`, `patch`, `curl`, `wget`, `ca-certificates`
- `ccache`, `libtool`, `libtool-bin`, `autoconf`, `automake`
- `zlib1g-dev`, `libisl-dev`, `libzstd-dev`

For multilib builds: `libc6-dev-i386`

## Installation

### Option 1: Download Pre-built Binary

```bash
# Download the latest release
curl -LO https://github.com/slyfox1186/script-repo/releases/latest/download/build-gcc
chmod +x build-gcc
sudo mv build-gcc /usr/local/bin/
```

### Option 2: Build from Source

```bash
# Clone the repository
git clone https://github.com/slyfox1186/script-repo.git
cd script-repo/Rust/build-gcc

# Build in release mode (optimized)
cargo build --release

# Install to system
sudo cp target/release/build-gcc /usr/local/bin/
```

### Option 3: Install with Cargo

```bash
cargo install --path .
```

## Usage

### Interactive Mode

Simply run without arguments for an interactive menu:

```bash
build-gcc
```

You'll be presented with options to:
1. Select a single GCC version
2. Select multiple versions
3. Build all available versions (10-15)

### CLI Mode

Specify versions directly for automation:

```bash
# Build a single version
build-gcc --versions 14

# Build multiple versions (comma-separated)
build-gcc --versions 12,13,14

# Build a range of versions
build-gcc --versions 11-14

# Mixed format
build-gcc --versions 10,12-14
```

### Parallel Builds

Build multiple versions simultaneously to save time:

```bash
# Build GCC 12, 13, and 14 with 2 parallel builds
build-gcc --versions 12,13,14 --parallel 2
```

> **Note**: Each GCC build is CPU and memory intensive. Only use `--parallel 2` or higher if you have sufficient resources (16+ GB RAM, 8+ CPU cores).

## Command-Line Options

| Option | Short | Description |
|--------|-------|-------------|
| `--versions <SPEC>` | `-V` | GCC versions to build (e.g., "13", "11-14", "12,14") |
| `--parallel <N>` | | Max parallel builds (default: 1) |
| `--dry-run` | | Show what would be done without making changes |
| `--verbose` | `-v` | Enable verbose logging |
| `--debug` | | Enable debug-level logging |
| `--prefix <DIR>` | `-p` | Custom installation prefix (default: `/usr/local/programs/gcc-<version>`) |
| `--optimization <LEVEL>` | `-O` | Optimization level: 0, 1, 2, 3, fast, g, s (default: 3) |
| `--generic` | `-g` | Use generic tuning instead of `-march=native` |
| `--enable-multilib` | | Enable 32-bit and 64-bit support |
| `--static` | | Build static GCC executables |
| `--save` | `-s` | Save static binaries (requires `--static`) |
| `--keep-build-dir` | `-k` | Keep temporary build directory after completion |
| `--log-file <FILE>` | `-l` | Write logs to file instead of stderr |
| `--help` | `-h` | Show help message |
| `--version` | | Show version information |

## Examples

### Basic Build

Build the latest GCC 14:

```bash
build-gcc -V 14 -v
```

### Development Setup

Build multiple versions for testing compatibility:

```bash
build-gcc --versions 11,12,13,14 --parallel 2 --verbose
```

### Custom Installation

Install to a custom directory:

```bash
build-gcc -V 14 --prefix /opt/compilers
# Installs to: /opt/compilers/gcc-14.x.x
```

### CI/CD Integration

Scripted build with logging:

```bash
build-gcc --versions 14 --log-file /var/log/gcc-build.log --generic
```

### Dry Run

Test what would happen without making changes:

```bash
build-gcc --versions 12-15 --parallel 2 --dry-run
```

## Build Process

The tool performs these stages for each GCC version:

| Stage | Description |
|-------|-------------|
| 1. Download | Fetch source tarball from GNU mirrors |
| 2. Verify | Check SHA512 (GCC 14+) or GPG signature (older) |
| 3. Extract | Decompress and extract tarball |
| 4. Prerequisites | Download GMP, MPFR, MPC, ISL |
| 5. Configure | Run configure with optimized options |
| 6. Build | Compile with `make -j<threads>` |
| 7. Install | Run `sudo make install-strip` |
| 8. Post-Install | Create symlinks, update ldconfig |

### Configure Options Applied

- `--enable-languages=all` - Build all language frontends
- `--disable-bootstrap` - Faster builds (skip 3-stage bootstrap)
- `--enable-checking=release` - Release-grade checking
- `--enable-threads=posix` - POSIX threading support
- `--with-system-zlib` - Use system zlib
- `--enable-default-pie` - Position-independent executables
- `--enable-cet` - Control-flow enforcement (GCC 13+)

## After Installation

Once built, GCC is installed to `/usr/local/programs/gcc-<version>/`.

### Add to PATH

```bash
# For GCC 14.2.0
export PATH="/usr/local/programs/gcc-14.2.0/bin:$PATH"

# Add to ~/.bashrc for persistence
echo 'export PATH="/usr/local/programs/gcc-14.2.0/bin:$PATH"' >> ~/.bashrc
```

### Verify Installation

```bash
gcc-14 --version
g++-14 --version
```

### Using a Specific Version

The binaries are suffixed with the major version:

```bash
gcc-14 -o myprogram myprogram.c
g++-14 -std=c++23 -o myapp myapp.cpp
gfortran-14 -o simulation simulation.f90
```

## Troubleshooting

### "Lock acquisition failed"

Another instance is running. Wait for it to complete or remove the lock:

```bash
rm /tmp/build-gcc-$(id -u).lock
```

### "Insufficient disk space"

Each GCC version needs ~25 GB. Free up space or use `--keep-build-dir` to manually clean up.

### "Configure failed"

Check the config.log in the build directory:

```bash
build-gcc -V 14 --keep-build-dir -v
# Then examine: /tmp/build-gcc.*/workspace/gcc-14.*/build-gcc/config.log
```

### Build Fails on Parallel Make

The tool automatically retries with single-threaded make if parallel fails. If issues persist, check RAM availability.

### Mirror Connection Issues

The tool uses multiple mirrors with fast failover (5-second timeout). If all mirrors fail, check your internet connection.

## Project Structure

```
build-gcc/
├── Cargo.toml          # Dependencies and metadata
├── src/
│   ├── main.rs         # Entry point and orchestration
│   ├── cli.rs          # Command-line argument parsing
│   ├── config.rs       # Configuration structs
│   ├── version.rs      # GCC version detection and selection
│   ├── download.rs     # Async downloads with retry logic
│   ├── build.rs        # Configure, make, install logic
│   ├── environment.rs  # PATH, CFLAGS, LDFLAGS setup
│   ├── dependencies.rs # System package installation
│   ├── post_install.rs # Symlinks, ldconfig, binary trimming
│   ├── logging.rs      # Colored logging and formatting
│   ├── progress.rs     # Progress bars and build summary
│   ├── system.rs       # Resource checks and lock files
│   └── error.rs        # Custom error types
├── rustfmt.toml        # Code formatting config
├── clippy.toml         # Linter config
└── .cargo/config.toml  # Cargo aliases
```

## Performance

Compared to traditional shell scripts:

| Metric | Shell Script | build-gcc (Rust) |
|--------|-------------|------------------|
| Download Speed | Sequential | Async with progress |
| Mirror Failover | Manual | Automatic (5s timeout) |
| Multiple Versions | Sequential | Parallel (`--parallel N`) |
| Error Recovery | Basic | Comprehensive |
| Progress Feedback | Minimal | Real-time progress bars |

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Run `cargo fmt` and `cargo clippy`
4. Submit a pull request

### Development Commands

```bash
# Format code
cargo fmt

# Run linter
cargo clippy --all-targets --all-features -- -D warnings

# Run tests
cargo test

# Build debug version
cargo build

# Build optimized release
cargo build --release
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- GNU GCC Team for the compiler
- Rust community for excellent async ecosystem
- Mirror providers: ibiblio.org, mirror.cs.odu.edu

---

**Built with Rust** | **Async Downloads** | **Parallel Builds**
