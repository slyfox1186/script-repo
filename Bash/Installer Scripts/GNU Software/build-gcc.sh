#!/usr/bin/env bash
# shellcheck disable=SC2162 source=/dev/null

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc.sh
# Build GNU GCC
# Versions available:  9|10|11|12|13
# Features: Automatically sources the latest release of each version.
# Updated: 05.05.24

build_dir="/tmp/gcc-build-script"
workspace="$build_dir/workspace"
verbose=0
log_file=""
version=""
versions=()
keep_build_dir=0

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    printf "  %-25s %s\\n" "-p, --prefix DIR" "Set the installation prefix (default: /usr/local)"
    printf "  %-25s %s\\n" "-v, --verbose" "Enable verbose logging"
    printf "  %-25s %s\\n" "-l, --log-file FILE" "Specify a log file for output"
    printf "  %-25s %s\\n" "-k, --keep-build-dir" "Keep the temporary build directory after completion"
    printf "  %-25s %s\\n" "-h, --help" "Show this help message"
    echo
    exit 0
}

log() {
    local message
    message="[INFO $(date +"%I:%M:%S %p")] $1"
    [[ "$verbose" -eq 1 ]] && echo -e "\\n${GREEN}[INFO $(date +"%I:%M:%S %p")]${NC} $message\\n"
    [[ -n "$log_file" ]] && echo "INFO: $message" >> "$log_file"
}

warn() {
    local message
    message="[WARNING $(date +"%I:%M:%S %p")] $1"
    [[ "$verbose" -eq 1 ]] && echo -e "\\n${YELLOW}[WARNING $(date +"%I:%M:%S %p")]${NC} $message\\n"
    [[ -n "$log_file" ]] && echo "WARNING: $message" >> "$log_file"
}

fail() {
    local message
    message="[ERROR $(date +"%I:%M:%S %p")] $1"
    [[ "$verbose" -eq 1 ]] && echo -e "\\n${RED}[ERROR $(date +"%I:%M:%S %p")]${NC} $message\\n"
    [[ -n "$log_file" ]] && echo "ERROR: $message" >> "$log_file"
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

# Remove leftover log files from previous runs
[[ -f "$log_file" ]] && rm -f "$log_file"

set_ccache_dir() {
    if [[ -d "/usr/lib/ccache/bin" ]]; then
        ccache_dir="/usr/lib/ccache/bin"
    else
        ccache_dir="/usr/lib/ccache"
    fi
    PATH="$ccache_dir:$PATH"
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
        libtool make m4 patch texinfo zlib1g-dev
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

download() {
    local extract_dir filename url
    url="$1"
    filename="${url##*/}"
    if [[ ! -f "$build_dir/$filename" ]]; then
        log "Downloading $url"
        if ! curl -fsSLo "$build_dir/$filename" "$url"; then
            fail "Failed to download $url"
        fi
    fi

    extract_dir="${filename%.tar.xz}"
    if [[ ! -d "$build_dir/$extract_dir" ]]; then
        log "Extracting $filename"
        if ! tar -xf "$build_dir/$filename" -C "$build_dir"; then
            fail "Failed to extract $filename"
        fi
    else
        log "Source directory $build_dir/$extract_dir already exists"
    fi
}

iscuda=$(sudo find /usr/local/ /opt/ -type f -name nvcc)
if [ -n "$iscuda" ]; then
    cuda_check="--with-cuda-driver"
else
    cuda_check="--without-cuda-driver"
fi

build_gcc() {
    local -a common_options configure_options
    local cuda_check gcc_dir languages os_info pc_type version
    version="$1"
    languages="$2"
    install_dir="$3"
    shift 3
    configure_options=("$@")

    pc_type="$(gcc -dumpmachine)"
    os_info="$(lsb_release -si) $(lsb_release -sr)"

    log "Building GCC $version"
    download "https://ftp.gnu.org/gnu/gcc/gcc-$version/gcc-$version.tar.xz"

    gcc_dir="$build_dir/gcc-$version"

    cd "$gcc_dir" || fail "Failed to change directory to $gcc_dir"

    log "Running autoreconf and downloading prerequisites"

    autoreconf -fi
    ./contrib/download_prerequisites

    mkdir -p builddir
    cd builddir || fail "Failed to change directory to builddir"

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
        10)
            ../configure --program-suffix=-10 \
                         --with-pkgversion="$os_info GCC $version" \
                         "${common_options[@]}" \
                         "${configure_options[@]}"
            ;;
        11)
            ../configure --program-suffix=-11 \
                         --with-pkgversion="$os_info GCC $version" \
                         "${common_options[@]}" \
                         "${configure_options[@]}"
            ;;
        12)
            ../configure --enable-lto \
                         --enable-offload-defaulted \
                         --program-suffix=-12 \
                         --with-pkgversion="$os_info GCC $version" \
                         --with-isl=/usr \
                         --with-libiconv-prefix=/usr \
                         --with-link-serialization=2 \
                         --with-zstd="$workspace" \
                         "${common_options[@]}" \
                         "${configure_options[@]}"
            ;;
        13)
            ../configure --enable-cet \
                         --enable-lto \
                         --enable-link-serialization=2 \
                         --enable-offload-defaulted \
                         --program-suffix=-13 \
                         --with-arch-32=i686 \
                         --with-pkgversion="$os_info GCC $version" \
                         --with-isl=/usr \
                         --with-libiconv-prefix=/usr \
                         --with-zstd="$workspace" \
                         "${common_options[@]}" \
                         "${configure_options[@]}"
            ;;
        *) clear; echo "VERSION NOT FOUND!"; exit ;;
    esac

    log "Compiling GCC $version"
    if ! make "-j$(nproc)"; then
        fail "Failed to compile GCC $version"
    fi
    log "Installing GCC $version"
    if ! make install-strip; then
        fail "Failed to install GCC $version"
    fi

    create_symlinks "$version"
}

create_symlinks() {
    local bin_dir major_version prefix_regex programs source_path symlink_path target_dir 
    version="$1"
    log "Creating symlinks for GCC $version..."
    bin_dir="/usr/local/gcc-$version/bin"
    target_dir="/usr/local/bin"
    prefix_regex='^x86_64-linux-gnu-'

    programs=(
        c++ cpp g++ gcc gcc-ar gcc-nm gcc-ranlib
        gcov gcov-dump gcov-tool gfortran gnat gnatbind
        gnatchop gnatclean gnatkr gnatlink gnatls gnatmake
        gnatname gnatprep lto-dump
    )

    for program in ${programs[@]}; do
        source_path="$bin_dir/$program"
        if [[ -x "$source_path" && ! "$program" =~ $prefix_regex ]]; then
            major_version="${version%%.*}"
            symlink_path="$target_dir/$program-$major_version"
            if ln -sfn "$source_path" "$symlink_path"; then
                log "Created symlink: $symlink_path -> $source_path"
            else
                warn "Failed to create symlink: $symlink_path -> $source_path"
            fi
        fi
    done
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
    log "Installing autoconf 2.69"
    curl -fsSLo "$build_dir/autoconf-2.69.tar.xz" "https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.xz"
    mkdir -p "$build_dir/autoconf-2.69/build" "$workspace"
    tar -xf "$build_dir/autoconf-2.69.tar.xz" -C "$build_dir/autoconf-2.69" --strip-components 1
    cd "$build_dir/autoconf-2.69" || fail "Failed to change directory to autoconf-2.69"
    autoupdate
    autoconf
    cd build || fail "Failed to change directory to build"
    ../configure --prefix="$build_dir/workspace"
    make "-j$(nproc)"
    make install
}

selected_versions=()

select_versions() {
    local -a selected_versions versions 
    versions=(9 10 11 12 13)
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
            read -p "Enter comma-separated versions or ranges (e.g., 11,13 or 11-13): " custom_choice
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

    # Install GCC's recommended version of autoconf (version 2.69)
    install_autoconf

    for version in "${selected_versions[@]}"; do
        latest_version=$(get_latest_version "$version")
        case "$version" in
            10)
                build_gcc "$latest_version" "c,c++,fortran,objc,obj-c++,ada" "/usr/local/gcc-$latest_version" "--enable-checking=release --with-arch-32=i686"
                ;;
            11|12|13)
                build_gcc "$latest_version" "c,c++,fortran,objc,obj-c++,ada" "/usr/local/gcc-$latest_version" "--enable-checking=release"
                ;;
        esac
        create_symlinks "$latest_version"
    done
}

ensure_root() {
    if [[ "$EUID" -ne 0 ]]; then
        fail "This script must be run as root or with sudo."
    fi
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

    [[ -d "$build_dir" ]] && rm -rf "$build_dir"
    mkdir -p "$build_dir"

    set_ccache_dir
    set_environment
    install_deps
    select_versions
    cleanup
    summary

    log "Build completed successfully!"
    echo -e "\\n${GREEN}Make sure to star this repository to show your support!${NC}"
    echo "https://github.com/slyfox1186/script-repo"
}

main "$@"
