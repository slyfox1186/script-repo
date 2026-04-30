#!/usr/bin/env bash

RUST_SRC_DIR="rust-build-script"

# Function to log messages
log() {
    echo "[INFO] $1"
}

# Function to handle errors
fail() {
    echo "[ERROR] $1"
    exit 1
}
# Cleanup leftover files from previous runs
[[ -d "$RUST_SRC_DIR" ]] && rm -fr "$RUST_SRC_DIR"

install_rustc_fn() {
    get_rustc_ver=$(rustc --version | grep -Eo '[0-9\.]+' | head -n1)
    if [ "$get_rustc_ver" != "1.75.0" ]; then
        echo "Installing RustUp"
        curl -sS --proto "=https" --tlsv1.2 "https://sh.rustup.rs" | sh -s -- -y &>/dev/null
        source "$HOME/.cargo/env"
        if [[ -f "$HOME/.zshrc" ]]; then
            source "$HOME/.zshrc"
        else
            source "$HOME/.bashrc"
        fi
    fi
}

install_rustc_fn

# Shallow clone option (uncomment if needed)
log "Performing a shallow clone of the Rust repository..."
git clone --depth 1 "https://github.com/rust-lang/rust.git" "$RUST_SRC_DIR" || fail "Failed to perform a shallow clone."
cd "$RUST_SRC_DIR" || fail "Failed to change directory to the cloned repository."

# Create a config.toml
log "Creating a config.toml file..."
./x setup dist || fail "Failed to run './x setup'."

# Build the compiler
log "Building the compiler..."
./x build library || fail "Failed to build the compiler."

# Creating rustup toolchains
log "Creating rustup toolchains..."
rustup toolchain link stage0 build/host/stage0-sysroot || fail "Failed to create stage0 toolchain."
rustup toolchain link stage1 build/host/stage1 || fail "Failed to create stage1 toolchain."
rustup toolchain link stage2 build/host/stage2 || fail "Failed to create stage2 toolchain."

log "Rust compiler installation and build process completed successfully."

rm -fr "$RUST_SRC_DIR"
