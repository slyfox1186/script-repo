#!/usr/bin/env bash
# shellcheck disable=SC2162 source=/dev/null

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc.sh
# Build GNU GCC
# Versions available:  10|11|12|13|14
# Features: Automatically sources the latest release of each version.
# Updated: 05.11.24

build_dir="/tmp/gcc-build-script"
packages="$build_dir/packages"
workspace="$build_dir/workspace"
keep_build_dir=0
log_file=""
selected_versions=()
verbose=0
version=""
versions=(10 11 12 13 14)

# ANSI color codes
GREEN='\033[1;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -k, --keep-build-dir       Keep the temporary build directory after completion"
    echo "  -l, --log-file FILE        Specify a log file for output"
    echo "  -p, --prefix DIR           Set the installation prefix (default: /usr/local/gcc-<version>)"
    echo "  -v, --verbose              Enable verbose logging"
    echo
    exit 0
}

log() {
    [[ "$verbose" -eq 1 ]] && echo -e "\\n${GREEN}[INFO $(date +"%I:%M:%S %p")]${NC} $1\\n"
    [[ -n "$log_file" ]] && echo "[INFO $(date +"%I:%M:%S %p")] $1" >> "$log_file"
}

warn() {
    [[ "$verbose" -eq 1 ]] && echo -e "\\n${YELLOW}[WARNING $(date +"%I:%M:%S %p")]${NC} $1\\n"
    [[ -n "$log_file" ]] && echo "[WARNING $(date +"%I:%M:%S %p")] $1" >> "$log_file"
}

fail() {
    [[ "$verbose" -eq 1 ]] && echo -e "\\n${RED}[ERROR $(date +"%I:%M:%S %p")]${NC} $1\\n"
    [[ -n "$log_file" ]] && echo "[ERROR $(date +"%I:%M:%S %p")] $1" >> "$log_file"
    echo -e "\\nTo report a bug, create an issue at: ${CYAN}https://github.com/slyfox1186/script-repo/issues${NC}"
    exit 1
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -p|--prefix)
                install_dir="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=1
                shift
                ;;
            -l|--log-file)
                log_file="$2"
                shift 2
                ;;
            -k|--keep-build-dir)
                keep_build_dir=1
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)  fail "Unknown option: $1. Use -h or --help for usage information." ;;
        esac
    done
}

execute() {
    echo "$ $*"

    if [[ "$verbose" -eq 1 ]]; then
        if ! output=$("$@"); then
            notify-send -t 5000 "Failed to execute $*" 2>/dev/null
            fail "Failed to execute $*"
        fi
    else
        if ! output=$("$@" 2>/dev/null); then
            notify-send -t 5000 "Failed to execute $*" 2>/dev/null
            fail "Failed to execute $*"
        fi
    fi
}

# Initialize log file removal
[[ -f "$log_file" ]] && rm -f "$log_file"

set_ccache_dir() {
    if [[ -d "/usr/lib/ccache/bin" ]]; then
        ccache_dir="/usr/lib/ccache/bin"
    else
        ccache_dir="/usr/lib/ccache"
    fi
    PATH="$ccache_dir:$workspace/bin:$PATH"
    export PATH
}

set_environment() {
    log "Setting environment variables..."
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -fstack-protector-strong -march=native"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now -Wl,-rpath,$install_dir/lib64 -Wl,-rpath,$install_dir/lib"
    export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}

install_deps() {
    local -a missing_pkgs
    local pkg pkgs
    log "Installing dependencies..."
    pkgs=(
        autoconf autoconf-archive automake binutils bison
        build-essential ccache curl flex gawk gnat libc6-dev
        libisl-dev libtool make m4 patch texinfo zlib1g-dev
    )
    missing_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done
    if [[ -n "${missing_pkgs[*]}" ]]; then
        sudo apt update
        sudo apt -y install $missing_pkgs
    else
        log "All required packages are already installed."
    fi
}

get_latest_version() {
    local version
    version="$1"
    store_version=$(curl -fsS "https://ftp.gnu.org/gnu/gcc/" | grep -oP "gcc-${version}[0-9.]+" | sort -ruV | head -n1 | cut -d- -f2)
    echo "$store_version"
}

create_symlinks() {
    local bin_dir file prefix source_path symlink_path target_dir
    version="$1"
    log "Creating symlinks for GCC $version..."
    bin_dir="/usr/local/gcc-$version/bin"
    target_dir="/usr/local/bin"

    local file gcc_long_name gcc_short_name

    gcc_long_name="$(sudo find $bin_dir -type f -name 'x86_64-linux-gnu-*' | grep -oP 'x86_64-linux-gnu-[a-z+-]+-[1-3]+$')"
    for file in ${gcc_long_name[@]}; do
        gcc_short_name="$(echo "$file" | sed 's/^x86_64-linux-gnu-\(.*\)$/\1/')"
        sudo ln -sf "$bin_dir/$file" "$target_dir/$gcc_short_name"
        sudo chmod 755 -R "$bin_dir/$file" "$target_dir/$gcc_short_name"
    done
}

build() {
    echo
    echo -e "${GREEN}Building${NC} ${YELLOW}$1${NC} - ${GREEN}version ${YELLOW}$2${NC}"
    echo "========================================================"

    if [[ -f "$packages/$1.done" ]]; then
        if grep -Fx "$2" "$packages/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $packages/$1.done lockfile to rebuild it."
            return 1
        else
            echo "$1 is outdated and will be rebuilt with latest version $2"
            return 0
        fi
    fi

    return 0
}

build_done() {
    echo "$2" > "$packages/$1.done"
}

download() {
    local download_file download_path download_url output_directory target_directory target_file
    download_path="$packages"
    download_url="$1"
    download_file="${2:-"${1##*/}"}"

    if [[ "$download_file" =~ tar. ]]; then
        output_directory="${download_file%.*}"
        output_directory="${3:-"${output_directory%.*}"}"
    else
        output_directory="${3:-"${download_file%.*}"}"
    fi

    target_file="$download_path/$download_file"
    target_directory="$download_path/$output_directory"

    if [[ -f "$target_file" ]]; then
        echo "$download_file is already downloaded."
    else
        echo "Downloading \"$download_url\" saving as \"$download_file\""
        if ! curl -LSso "$target_file" "$download_url"; then
            warn "Failed to download \"$download_file\". Second attempt in 3 seconds..."
            sleep 3
            if ! curl -LSso "$target_file" "$download_url"; then
                fail "Failed to download \"$download_file\". Exiting... Line: $LINENO"
            fi
        fi
        echo "Download Completed"
    fi

    [[ -d "$target_directory" ]] && rm -fr "$target_directory"
    mkdir -p "$target_directory"

    if ! tar -xf "$target_file" -C "$target_directory" --strip-components 1; then
        rm "$target_file"
        fail "Failed to extract the tarball \"$download_file\" and was deleted. Re-run the script to try again. Line: $LINENO"
    fi

    printf "%s\n\n" "File extracted: $download_file"

    cd "$target_directory" || fail "Failed to cd into \"$target_directory\". Line: $LINENO"
}

iscuda=$(sudo find /usr/local/ /opt/ -type f -name nvcc)
if [ -n "$iscuda" ]; then
    cuda_check="--with-cuda-driver"
else
    cuda_check="--without-cuda-driver"
fi

install_gcc() {
    local version short_version os_info
    version="$1"
    short_version="$2"
    os_info="$3"
    shift 3

    if build "gcc" "$version"; then
        download "https://ftp.gnu.org/gnu/gcc/gcc-$version/gcc-$version.tar.xz"
        execute autoreconf -fi
        execute ./contrib/download_prerequisites
        mkdir builddir; cd builddir || fail "Failed to change the autoconf directory to build"
        ../configure --program-suffix="-$short_version" --with-isl=system

        execute make "-j$threads"
        execute make install-strip
        execute libtool --finish "/usr/local/gcc-$version/libexec/gcc/x86_64-linux-gnu/$short_version"
        build_done "gcc" "$version"
    fi

    create_symlinks "$version"
}

build_gcc() {
    local -a common_options configure_options
    local cuda_check os_info pc_type version
    version="$1"
    install_dir="$2"
    shift 2
    configure_options=("$@")

    pc_type="$(gcc -dumpmachine)"
    os_info="$(lsb_release -si) $(lsb_release -sr)"

    log "Begin building GCC $version"

    common_options=(
        --prefix="$install_dir"
        --build="$pc_type"
        --host="$pc_type"
        --target="$pc_type"
        --disable-assembly
        --disable-nls
        --disable-vtable-verify
        --disable-werror
        --enable-bootstrap
        --enable-checking="release"
        --enable-clocale="gnu"
        --enable-default-pie
        --enable-gnu-unique-object
        --enable-languages="all"
        --enable-libphobos-checking="release"
        --enable-libstdcxx-debug
        --enable-libstdcxx-time="yes"
        --enable-linker-build-id
        --enable-multiarch
        --enable-multilib
        --enable-plugin
        --enable-shared
        --enable-threads="posix"
        --libdir="$install_dir/lib"
        --libexecdir="$install_dir/libexec"
        --program-prefix="x86_64-linux-gnu-"
        --with-abi="m64"
        --with-build-config="bootstrap-lto-lean"
        --with-default-libstdcxx-abi="new"
        --with-gcc-major-version-only
        --with-multilib-list="m32,m64,mx32"
        --with-system-zlib
        --with-target-system-zlib="auto"
        --with-tune="native"
        --without-included-gettext
        "$cuda_check"
    )

    log "Configuring GCC $version"

    short_version="${version%%.*}"

    case "$short_version" in
        9|10|11) install_gcc "$version" "$short_version" "$os_info" "${common_options[@]}" "${configure_options[@]}" ;;
        12) gcc_12_options=(--enable-lto --enable-offload-defaulted --with-isl=/usr -with-libiconv-prefix=/usr --with-link-serialization=2 --with-zstd="$workspace")
            install_gcc "$version" "$short_version" "$os_info" "${common_options[@]}" "${configure_options[@]}" "${gcc_12_options[@]}"
            ;;
        13) gcc_13_options=(--enable-cet --enable-lto --enable-link-serialization=2 --enable-offload-defaulted --with-arch-32=i686 --with-isl=/usr --with-libiconv-prefix=/usr --with-zstd="$workspace")
            install_gcc "$version" "$short_version" "$os_info" "${common_options[@]}" "${configure_options[@]}" "${gcc_13_options[@]}"
            ;;
        14) gcc_14_options=(--enable-cet --enable-lto --enable-link-serialization=2 --enable-offload-defaulted --with-arch-32=i686 --with-isl=/usr --with-libiconv-prefix=/usr --with-zstd="$workspace")
            install_gcc "$version" "$short_version" "$os_info" "${common_options[@]}" "${configure_options[@]}" "${gcc_14_options[@]}"
            ;;
        *)  fail "GCC version not found. Line: $LINENO" ;;
    esac
}

cleanup() {
    if [[ "$keep_build_dir" -ne 1 ]]; then
        log "Cleaning up..."
        rm -fr "$build_dir"
        log "Removed temporary build directory: $build_dir"
    else
        log "Temporary build directory retained: $build_dir"
    fi
}

install_autoconf() {
    if build "autoconf" "2.69"; then
        download "https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.xz" "autoconf-2.69.tar.xz"
        execute autoupdate
        execute autoconf
        mkdir build; cd build || fail "Failed to change the autoconf directory to build"
        execute ../configure --prefix="$workspace"
        execute make "-j$threads"
        execute make install
        build_done "autoconf" "2.69"
    fi
}

select_versions() {
    local -a selected_versions versions
    versions=(10 11 12 13 14)
    selected_versions=()

    echo -e "\\n${GREEN}Select the GCC version(s) to install:${NC}\n"
    echo -e "${CYAN}1. Single version${NC}"
    echo -e "${CYAN}2. All versions${NC}"
    echo -e "${CYAN}3. Custom versions${NC}"

    echo
    read -p "Enter your choice: " choice

    case "$choice" in
        1)
            echo -e "\\n${GREEN}Select a single GCC version to install:${NC}\n"
            for ((i=0; i<${#versions[@]}; i++)); do
                echo -e "${CYAN}$((i+1)). GCC ${versions[i]}${NC}"
            done
            echo
            read -p "Enter your choice: " single_choice
            selected_versions+=("${versions[$((single_choice-1))]}")
            ;;
        2)
            selected_versions=("${versions[@]}")
            ;;
        3)
            read -p "Enter comma-separated versions or ranges (e.g., 11,14 or 11-14): " custom_choice
            IFS=',' read -ra custom_versions <<< "$custom_choice"
            for version in "${custom_versions[@]}"; do
                if [[ $version =~ ^[0-9]+$ ]]; then
                    selected_versions+=("$version")
                elif [[ $version =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    start=${BASH_REMATCH[1]}
                    end=${BASH_REMATCH[2]}
                    for ((i=start; i<=end; i++)); do
                        selected_versions+=("$i")
                    done
                else
                    fail "Invalid version or range: $version"
                fi
            done
            ;;
        *)
            fail "Invalid choice: $choice"
            ;;
    esac

    if [[ "${#selected_versions[@]}" -eq 0 ]]; then
        fail "No GCC versions selected."
    fi

    for version in "${selected_versions[@]}"; do
        latest_version=$(get_latest_version "$version")
        case "$version" in
            10)
                build_gcc "$latest_version" "/usr/local/gcc-$latest_version" "--with-arch-32=i686"
                ;;
            11|12|13|14)
                build_gcc "$latest_version" "/usr/local/gcc-$latest_version"
                ;;
        esac
        create_symlinks "$latest_version"
    done
}

check_requirements() {
    local missing_tools tools
    tools=(curl make tar autoreconf autoupdate autoconf)
    missing_tools=()
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        fail "The following tools are required but not found: ${missing_tools[*]}"
    fi
}

summary() {
    echo
    echo -e "${GREEN}Summary:${NC}"
    echo -e "  ${YELLOW}Installed GCC version(s): ${CYAN}$latest_version${NC}"
    echo -e "  ${YELLOW}Installation prefix: ${CYAN}$install_dir${NC}"
    echo -e "  ${YELLOW}Build directory: ${CYAN}$build_dir${NC}"
    echo -e "  ${YELLOW}Temporary build directory retained: ${CYAN}$([[ "$keep_build_dir" -eq 1 ]] && echo "Yes" || echo "No")${NC}"
    if [[ -z "$log_file" ]]; then
        echo -e "  ${YELLOW}Log file: ${CYAN}Not Enabled${NC}"
    else
        echo -e "  ${YELLOW}Log file: ${CYAN}$log_file${NC}"
    fi
}

main() {
    parse_args "$@"

    [[ "$EUID" -ne 0 ]] && fail "This script must be run as root or with sudo."

    mkdir -p "$packages" "$workspace"

    if [[ -f /proc/cpuinfo ]]; then
        threads=$(grep -c ^processor /proc/cpuinfo)
    else
        threads=$(nproc --all)
    fi

    set_ccache_dir
    set_environment
    install_deps
    install_autoconf
    select_versions
    cleanup
    summary

    log "Build completed successfully!"
    echo -e "\\n${GREEN}Make sure to star this repository to show your support!${NC}"
    echo "https://github.com/slyfox1186/script-repo"
}

main "$@"
