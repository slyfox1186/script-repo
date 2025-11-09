# GCC Builder - Quick Setup

## Quick Start (3 Commands)

```bash
# 1. Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# 2. Clone and build
git clone https://github.com/slyfox1186/script-repo.git
cd script-repo/rust
sudo apt update && sudo apt install -y build-essential curl wget m4 flex bison
cargo build --release

# 3. Run GCC builder
./target/release/gcc-builder --latest --prefix $HOME/gcc --verbose
```

## Usage Examples

```bash
# Build latest GCC (recommended)
./target/release/gcc-builder --latest --prefix $HOME/gcc --jobs $(nproc)

# Build specific versions
./target/release/gcc-builder --versions 13 --prefix $HOME/gcc-13
./target/release/gcc-builder --versions 13,14,15 --prefix $HOME/gcc-multi

# Quick test (dry run)
./target/release/gcc-builder --latest --prefix $HOME/gcc --dry-run

# Production build
./target/release/gcc-builder --preset production --prefix $HOME/gcc-prod
```

## Common Options

- `--latest` - Build latest stable GCC
- `--versions X` - Build specific version(s)
- `--preset minimal|development|production` - Use presets
- `--prefix PATH` - Installation directory
- `--jobs N` - Parallel jobs (default: auto-detect)
- `--verbose` - Show detailed output
- `--dry-run` - Show what would be done

## Troubleshooting

**Permission errors:**
```bash
# Use home directory instead of system directories
./target/release/gcc-builder --latest --prefix $HOME/gcc
```

**Memory issues:**
```bash
# Reduce parallel jobs
./target/release/gcc-builder --latest --prefix $HOME/gcc --jobs 4
```

**Debug issues:**
```bash
# Enable full logging
./target/release/gcc-builder --latest --prefix $HOME/gcc --verbose --debug
```

## Install System-wide (Optional)

```bash
sudo cp ./target/release/gcc-builder /usr/local/bin/
```

Now you can run `gcc-builder` from anywhere.

---

**Features:** Zero configuration • Multi-version support • Automatic dependency handling • Works on Ubuntu/Debian