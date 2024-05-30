#!/usr/bin/env bash
# shellcheck disable=SC2162 source=/dev/null

echo
echo "This script will automatically uninstall any APT package version of cargo and rustc."
echo "The script will replace them using the RustUP command to give you the latest stable version."
echo "RustUp does not like any other versions of cargo or rustc on the computer to compete with it."
echo "The new binaries for rustc and cargo will be located in the directory: $HOME/.cargo/bin/"
echo "You must add that directory to your PATH which is usually done within the \".bashrc\" file."
echo
echo "Choose an option"
echo
echo "[1] Continue"
echo "[2] Exit"
echo
read -p "Your choices are (1 or 2): " choice
echo

case "$choice" in
    1) ;;
    2) exit 0 ;;
esac

script_dir="$PWD"
cwd="$script_dir/cargo-build-script"

if [[ ! -d "$cwd" ]]; then
    mkdir -p "$cwd"
fi
cd "$cwd" || exit 1

# Function to check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Ensure required tools are installed
if ! command_exists curl; then
    echo "curl is not installed. Please install it and try again."
    exit 1
fi

# Uninstall the APT packages of cargo and rustc if installed
if dpkg -s cargo rustc &>/dev/null; then
    sudo apt -y purge cargo rustc
    sudo apt -y autoremove
fi

# Also attempt to delete any manually installed binaries (possibly from this script)
if [[ -f "/usr/bin/cargo" ]] || [[ -f "/usr/bin/rustc" ]]; then
    sudo rm -f "/usr/bin/cargo" "/usr/bin/rustc"
fi

# Install RustUP
curl --proto '=https' --tlsv1.2 -sSf "https://sh.rustup.rs" | sh -s -- -y &>/dev/null
source "$HOME/.cargo/env"

# Get the latest Cargo release version from GitHub
latest_version=$(curl -fsS "https://github.com/rust-lang/cargo/tags/" | grep -oP '/releases/tag/\K\d+\.\d+\.\d+' | head -n1)

# Construct the download URL for the latest release
download_url="https://github.com/rust-lang/cargo/archive/refs/tags/${latest_version}.tar.gz"

# Download and extract the latest Cargo release
curl -LSso "cargo-${latest_version}.tar.gz" "$download_url"
[[ -d "cargo-${latest_version}" ]] && sudo rm -fr "cargo-${latest_version}"
mkdir "cargo-${latest_version}"
tar -zxf "cargo-${latest_version}.tar.gz" -C "cargo-${latest_version}" --strip-components 1
cd "cargo-${latest_version}" || exit 1

# Build Cargo
cargo update
cargo build --release --verbose

# Copy the built Cargo binary to the appropriate directories
cargo_build_dir=$(find "$PWD" -type f -name cargo)
[[ -d "$HOME/.cargo/bin" ]] && cp -f "$cargo_build_dir" "$HOME/.cargo/bin/"
sudo cp -f "$cargo_build_dir" "/usr/bin/"

# Clean up the temporary directory
cd "$script_dir" || exit 1
rm -fr "$cwd"

# Verify the installed version
echo_version=$(cargo --version | awk '{print $2}')

echo "Cargo has been successfully installed and updated to version: $echo_version"
