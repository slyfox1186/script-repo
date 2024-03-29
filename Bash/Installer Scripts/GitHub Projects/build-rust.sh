#!/usr/bin/env bash

RUST_SRC_DIR="rust-build-script"

# Function to log messages
log_message() {
    echo "[LOG] $1"
}

# Function to handle errors
handle_error() {
    echo "[ERROR] $1"
    exit 1
}
# Cleanup leftover files from previous runs
[[ -d "$RUST_SRC_DIR" ]] && rm -fr "$RUST_SRC_DIR"

install_rustc_fn() {
    get_rustc_ver=$(rustc --version | grep -Eo '[0-9 \.]+' | head -n1)
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
log_message "Performing a shallow clone of the Rust repository..."
git clone --depth 1 "https://github.com/rust-lang/rust.git" "$RUST_SRC_DIR" || handle_error "Failed to perform a shallow clone."
cd "$RUST_SRC_DIR" || handle_error "Failed to change directory to the cloned repository."

# Create a config.toml
log_message "Creating a config.toml file..."
./x setup dist || handle_error "Failed to run './x setup'."

# Build the compiler
log_message "Building the compiler..."
./x build library || handle_error "Failed to build the compiler."

# Creating rustup toolchains
log_message "Creating rustup toolchains..."
rustup toolchain link stage0 build/host/stage0-sysroot || handle_error "Failed to create stage0 toolchain."
rustup toolchain link stage1 build/host/stage1 || handle_error "Failed to create stage1 toolchain."
rustup toolchain link stage2 build/host/stage2 || handle_error "Failed to create stage2 toolchain."

log_message "Rust compiler installation and build process completed successfully."

rm -fr "$RUST_SRC_DIR"
