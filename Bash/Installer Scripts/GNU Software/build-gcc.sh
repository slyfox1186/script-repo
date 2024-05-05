#!/usr/bin/env bash

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
    message="$1"
    [[ "$verbose" -eq 1 ]] && echo -e "\\n${GREEN}[INFO]${NC} $message\\n"
    [[ -n "$log_file" ]] && echo "$message" >> "$log_file"
}

warn() {
    local message
    message="$1"
    echo -e "${YELLOW}[WARN]${NC} $message"
    [[ -n "$log_file" ]] && echo "WARNING: $message" >> "$log_file"
}

fail() {
    local message
    message="$1"
    echo -e "${RED}[ERROR]${NC} $message"
    [[ -n "$log_file" ]] && echo "ERROR: $message" >> "$log_file"
    echo
    echo -e "${YELLOW}To report a bug, create an issue at: ${CYAN}https://github.com/slyfox1186/script-repo/issues${NC}"
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

set_ccache_dir() {
    if [[ -d "/usr/lib/ccache/bin" ]]; then
        ccache_dir="/usr/lib/ccache/bin"
    elif [[ -d "/usr/lib/ccache" ]]; then
        ccache_dir="/usr/lib/ccache"
    else
        fail "Unable to locate the ccache directory. Please make sure ccache is installed."
    fi
}

set_env_vars() {
    log "Setting environment variables..."
    CC="gnatgcc"
    CXX="g++"
    CFLAGS="-O3 -pipe -fstack-protector-strong -march=native -mtune=native"
    CXXFLAGS="-O3 -pipe -fstack-protector-strong -march=native -mtune=native"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"
    PATH="$ccache_dir:$workspace/bin:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig"
    export CC CFLAGS CPPFLAGS CXX CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

install_deps() {
    log "Installing dependencies..."
    local missing_packages pkgs
        pkgs=(
                autoconf autoconf-archive automake binutils bison
                build-essential ccache curl flex gawk gnat libc6-dev
                libtool make m4 patch texinfo zlib1g-dev
           )
    if command -v apt-get &>/dev/null; then
        for pkg in ${pkgs[@]}; do
            if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
                missing_packages+="$pkg "
            fi
        done
    fi
    [[ -n "$missing_packages" ]] && sudo apt -y install $missing_packages
}

get_latest_version() {
    curl -fsS "https://ftp.gnu.org/gnu/gcc/" | grep -Eo "gcc-$1\.[0-9]+\.[0-9]+" | sort -rV | head -n1 | cut -d- -f2
}

download() {
    local url="$1"
    local filename="${url##*/}"
    if [[ ! -f "$build_dir/$filename" ]]; then
        log "Downloading $url"
        curl -fsSLo "$build_dir/$filename" "$url"
    fi

    local extract_dir="${filename%.tar.xz}"
    if [[ ! -d "$build_dir/$extract_dir" ]]; then
        log "Extracting $filename"
        tar -xf "$build_dir/$filename" -C "$build_dir" || fail "Failed to extract $filename"
    else
        log "Source directory $build_dir/$extract_dir already exists"
    fi
}

build_gcc() {
    local configure_options gcc_dir install_dir languages version 
    version="$1"
    languages="$2"
    install_dir="$3"
    configure_options="$4"

    log "Building GCC $version"
    download "https://ftp.gnu.org/gnu/gcc/gcc-$version/gcc-$version.tar.xz"

    gcc_dir="$build_dir/gcc-$version"

    if [[ ! -d "$gcc_dir" ]]; then
        fail "GCC $version source directory not found: $gcc_dir"
    fi

    cd "$gcc_dir" || fail "Failed to change directory to $gcc_dir"

    log "Running autoreconf and downloading prerequisites"
    autoreconf -fi
    ./contrib/download_prerequisites

    mkdir -p builddir
    cd builddir || fail "Failed to change directory to builddir"

    log "Configuring GCC $version"
    ../configure --prefix="$install_dir" \
                 --enable-languages="$languages" \
                 --enable-multilib \
                 --with-system-zlib \
                 --enable-checking=release \
                 --enable-lto \
                 --enable-link-time-optimization \
                 --enable-hardening \
                 --enable-linker-build-id \
                 --with-linker-hash-style=gnu \
                 --enable-plugin \
                 --enable-default-pie \
                 --enable-default-ssp \
                 --enable-cet \
                 --with-pkgversion="$(lsb_release -is)-$(lsb_release -rs)" \
                 --target="$(dpkg-architecture --query DEB_HOST_GNU_TYPE)" \
                 --with-build-config=bootstrap-lto-lean \
                 LDFLAGS="-Wl,-rpath,/usr/local/gcc-$version/lib64 -Wl,-rpath,/usr/local/gcc-$version/lib" \
                 "$configure_options"

    log "Compiling GCC $version"
    make "-j$(nproc --all)"
    
    log "Installing GCC $version"
    make install-strip
}

create_symlinks() {
    local bin_dir major_version programs source_path symlink_path target_dir version

    log "Creating symlinks for GCC $version..."

    version="$1"
    bin_dir="/usr/local/gcc-$version/bin"
    target_dir="/usr/local/bin"

    programs=(
        "c++" "cpp" "g++" "gcc" "gcc-ar" "gcc-nm" "gcc-ranlib"
        "gcov" "gcov-dump" "gcov-tool" "gfortran" "gnat" "gnatbind"
        "gnatchop" "gnatclean" "gnatkr" "gnatlink" "gnatls" "gnatmake"
        "gnatname" "gnatprep" "lto-dump"
    )

    for program in "${programs[@]}"; do
        source_path="$bin_dir/$program"
        if [[ -x "$source_path" && ! "$program" =~ ^pc-linux-gnu-gcc-|^pc-linux-gnu- ]]; then
            major_version="${version%%.*}"
            symlink_path="$target_dir/$program-$major_version"
            ln -sfn "$source_path" "$symlink_path"
            log "Created symlink: $symlink_path -> $source_path"
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
    make "-j$(nproc --all)"
    make install
}

select_versions() {
    local -a versions
    versions=(9 10 11 12 13)
    selected_versions=()

    echo -e "\\n${GREEN}Select the GCC version(s) to install:${NC}\\n"
    echo -e "${CYAN}1. Single version${NC}"
    echo -e "${CYAN}2. All versions${NC}"
    echo -e "${CYAN}3. Custom versions${NC}"

    read -p "Enter your choice: " choice

    case "$choice" in
        1)
            echo -e "\\n${GREEN}Select a single GCC version to install:${NC}\\n"
            for ((i=0; i<${#versions[@]}; i++)); do
                echo -e "${CYAN}$((i+1)). GCC ${versions[i]}${NC}"
            done
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

    [[ "${#selected_versions[@]}" -eq 0 ]] && fail "No GCC versions selected."

    # Install GCC's recommended version of autoconf (version 2.69)
    install_autoconf

    for version in "${selected_versions[@]}"; do
        latest_version=$(get_latest_version "$version")
        case "$version" in
            10)
                build_gcc "$latest_version" "c,c++,fortran,objc,obj-c++,ada" "/usr/local/gcc-$latest_version" "--with-arch-32=i686"
                ;;
            11|12|13)
                build_gcc "$latest_version" "c,c++,fortran,objc,obj-c++,ada" "/usr/local/gcc-$latest_version"
                ;;
        esac
        create_symlinks "$latest_version"
    done
}

summary() {
    echo
    echo -e "${GREEN}Summary:${NC}"
    echo -e "  Installed GCC version(s):"
    for version in "${selected_versions[@]}"; do
        latest_version=$(get_latest_version "$version")
        echo -e "    ${CYAN}$latest_version${NC}"
    done
    echo -e "  Installation prefix: ${CYAN}$install_dir${NC}"
    echo -e "  Build directory: ${CYAN}$build_dir${NC}"
    echo -e "  Temporary build directory retained: ${CYAN}$([[ "$keep_build_dir" -eq 1 ]] && echo "Yes" || echo "No")${NC}"
    echo -e "  Log file: ${CYAN}$log_file${NC}"
}

main() {
    parse_args "$@"

    if [[ "$EUID" -ne 0 ]]; then
        echo "This script must be run as root or with sudo."
        exit 1
    fi

    if [[ -d "$build_dir" ]]; then
        rm -fr "$build_dir"
    fi

    mkdir -p "$build_dir"

    set_ccache_dir
    set_env_vars
    install_deps
    select_versions
    cleanup
    summary

    log "Build completed successfully!"
    echo
    echo -e "${GREEN}Make sure to star this repository to show your support!${NC}"
    echo "https://github.com/slyfox1186/script-repo"
}

main "$@"
