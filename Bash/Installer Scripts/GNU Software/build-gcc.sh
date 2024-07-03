#!/usr/bin/env bash
# shellcheck disable=SC2162 source=/dev/null

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc.sh
# Purpose: Build GNU GCC
# GCC versions available: 10-14
# Features: Automatically sources the latest release of each version.
# Updated: 07.03.24
# Script version: 1.3

build_dir="/tmp/gcc-build-script"
packages="$build_dir/packages"
workspace="$build_dir/workspace"
keep_build_dir=0
log_file=""
selected_versions=()
verbose=1
version=""
versions=(10 11 12 13 14)

# ANSI color codes
CYAN='\033[0;36m'
GREEN='\033[1;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No color

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -k, --keep-build-dir       Keep the temporary build directory after completion"
    echo "  -l, --log-file FILE        Specify a log file for output"
    echo "  -p, --prefix DIR           Set the installation prefix (default: /usr/local/programs/gcc-<version>)"
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

set_path() {
    PATH="/usr/lib/ccache:$workspace/bin:$PATH"
    export PATH
}

set_pkg_config_path() {
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export PKG_CONFIG_PATH
}

set_environment() {
    log "Setting environment variables..."
    CC="/usr/bin/gcc"
    CXX="/usr/bin/g++"
    CFLAGS="-O2 -pipe -march=native -fstack-protector-strong"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    LDFLAGS="-L/usr/lib/x86_64-linux-gnu -Wl,-rpath,$install_dir/lib64 -Wl,-rpath,$install_dir/lib -Wl,-z,relro -Wl,-z,now"
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
}

build() {
    local package version
    package=$1
    version=$2
    log "Building $package $version..."

    # Change to the build directory
    cd "$build_dir" || fail "Failed to change directory to $build_dir"

    case "$package" in
        gcc)
            download "https://ftp.gnu.org/gnu/gcc/gcc-$version/gcc-$version.tar.xz"
            tar -xf "gcc-$version.tar.xz"
            cd "gcc-$version" || fail "Failed to change directory to gcc-$version"
            execute ./contrib/download_prerequisites
            mkdir build; cd build || fail "Failed to create build directory"
            execute ../configure $configure_options
            execute make "-j$threads"
            execute sudo make install-strip
            ;;
        autoconf)
            download "https://ftp.gnu.org/gnu/autoconf/autoconf-$version.tar.xz"
            tar -xf "autoconf-$version.tar.xz"
            cd "autoconf-$version" || fail "Failed to change directory to autoconf-$version"
            execute ./configure --prefix="$workspace"
            execute make "-j$threads"
            execute sudo make install
            ;;
        *)
            fail "Unsupported package: $package"
            ;;
    esac

    return 0  # Return success
}

download() {
    local url file
    url=$1
    file=${url##*/}
    log "Downloading $file from $url..."
    curl -fsSLO "$url"
}

create_symlinks() {
    local version
    version=$1
    log "Creating symlinks for GCC $version..."

    local programs=(
        "cpp-$version"
        "c++-$version"
        "gccgo-$version"
        "gcc-$version"
        "gcc-ar-$version"
        "gcc-nm-$version"
        "gcc-ranlib-$version"
        "gcov-$version"
        "gcov-dump-$version"
        "gcov-tool-$version"
        "gfortran-$version"
        "gnatbind-$version"
        "gnatchop-$version"
        "gnatclean-$version"
        "gnatkr-$version"
        "gnatlink-$version"
        "gnatls-$version"
        "gnatmake-$version"
        "gnatname-$version"
        "gnatprep-$version"
        "gnat-$version"
        "gofmt-$version"
        "go-$version"
        "g++-$version"
        "lto-dump-$version"
    )

    for program in "${programs[@]}"; do
        local trimmed_program="${program#*-}"  # Trim leading text up to and including the first hyphen
        local full_path="/usr/local/programs/gcc-$version/bin/x86_64-linux-gnu-$program"
        sudo ln -sf "$full_path" "/usr/local/bin/$trimmed_program"
    done
}

install_deps() {
    local -a missing_pkgs=() pkgs=()
    local pkg
    log "Installing dependencies..."
    pkgs=(
        autoconf autoconf-archive automake binutils bison
        build-essential ccache curl flex gawk gcc gnat libc6-dev
        libisl-dev libtool make m4 patch texinfo zlib1g-dev
        libc6-dev libc6-dev-i386 linux-libc-dev linux-libc-dev:i386
    )

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ -n "${missing_pkgs[*]}" ]]; then
        sudo apt update
        sudo apt install "${missing_pkgs[@]}"
    else
        log "All required packages are already installed."
    fi
}

get_latest_version() {
    local version
    version="$1"
    store_version=$(curl -fsS "https://ftp.gnu.org/gnu/gcc/" | grep -oP "gcc-\K${version}[0-9.]+" | sort -ruV | head -n1)
    echo "$store_version"
}

install_gcc() {
    local options short_version version
    version=$1
    options=$2
    install_dir="/usr/local/programs/gcc-$version"

    if build gcc "$version"; then
        download "https://ftp.gnu.org/gnu/gcc/gcc-$version/gcc-$version.tar.xz"
        tar -xf "gcc-$version.tar.xz"
        cd "gcc-$version" || fail "Failed to change directory to gcc-$version"
        execute ./contrib/download_prerequisites
        mkdir build; cd build || fail "Failed to create build directory"
        execute ../configure $options
        execute make "-j$threads"
        execute sudo make install-strip
        if [[ -d "$install_dir/libexec/gcc/x86_64-pc-linux-gnu/$short_version" ]]; then
            execute sudo libtool --finish "$install_dir/libexec/gcc/x86_64-pc-linux-gnu/$short_version"
        elif [[ -d "$install_dir/libexec/gcc/x86_64-linux-gnu/$short_version" ]]; then
            execute sudo libtool --finish "$install_dir/libexec/gcc/x86_64-linux-gnu/$short_version"
        elif [[ -d "$install_dir/libexec/gcc/$pc_type/$short_version" ]]; then
            execute sudo libtool --finish "$install_dir/libexec/gcc/$pc_type/$short_version"
        else
            fail "The script could not find the correct folder for libtool to run --finish on. Line: $LINENO"
        fi
        build_done "gcc" "$version"
    fi

    create_symlinks "$version"
}

build_gcc() {
    local -a common_options=() configure_options=()
    local cuda_check version
    version=$1
    install_dir="/usr/local/programs/gcc-$version"

    pc_type=$(gcc -dumpmachine)

    log "Begin building GCC $version"

    short_version="${version%%.*}"

    common_options=(
        "--prefix=$install_dir"
        "--build=$pc_type"
        "--host=$pc_type"
        "--target=$pc_type"
        "--disable-assembly"
        "--disable-isl-version-check"
        "--disable-lto"
        "--disable-nls"
        "--disable-vtable-verify"
        "--disable-werror"
        "--enable-bootstrap"
        "--enable-checking=release"
        "--enable-clocale=gnu"
        "--enable-default-pie"
        "--enable-gnu-unique-object"
        "--enable-languages=all"
        "--enable-libphobos-checking=release"
        "--enable-libstdcxx-debug"
        "--enable-libstdcxx-time=yes"
        "--enable-linker-build-id"
        "--enable-multiarch"
        "--enable-multilib"
        "--enable-plugin"
        "--enable-shared"
        "--enable-stage1-checking=all"
        "--enable-threads=posix"
        "--libdir=$install_dir/lib"
        "--libexecdir=$install_dir/libexec"
        "--program-prefix=$pc_type-"
        "--program-suffix=-$short_version"
        "--with-abi=m64"
        "--with-build-config=bootstrap-lto-lean"
        "--with-default-libstdcxx-abi=new"
        "--with-gcc-major-version-only"
        "--with-isl=/usr"
        "--with-system-zlib"
        "--with-target-system-zlib=auto"
        "--with-tune=native"
        "--with-zstd=auto"
        "--without-included-gettext"
        "$cuda_check"
    )

    log "Configuring GCC $version"

    case "$short_version" in
        9|10|11) configure_options=("${common_options[*]}") ;;
        12) configure_options=("${common_options[*]}" --with-link-serialization=2) ;;
        13) configure_options=("${common_options[*]}" --disable-vtable-verify --enable-cet --enable-link-serialization=2 --enable-host-pie --with-arch-32=i686) ;;
        14) configure_options=("${common_options[*]}" --enable-year2038 --disable-vtable-verify --enable-cet --enable-link-serialization=2 --enable-host-pie --with-arch-32=i686) ;;
        *)  fail "GCC version not found. Line: $LINENO" ;;
    esac

    install_gcc "$version" "${configure_options[*]}"
    ld_linker_path "$short_version"
    create_additional_soft_links "$install_dir"
}

cleanup_build_folders() {
    log "Cleaning up leftover build folders from previous runs..."
    find "$build_dir" -mindepth 1 -maxdepth 1 -type d ! -name 'packages' ! -name 'workspace' -exec sudo rm -fr {} +
}

cleanup() {
    if [[ "$keep_build_dir" -ne 1 ]]; then
        log "Cleaning up..."
        sudo rm -fr "$build_dir"
        log "Removed temporary build directory: $build_dir"
    else
        log "Temporary build directory retained: $build_dir"
    fi
}

install_autoconf() {
    if ! command -v autoconf &> /dev/null; then
        if build "autoconf" "2.69"; then
            build_done "autoconf" "2.69"
        fi
    else
        log "autoconf is already installed."
    fi
}

select_versions() {
    local -a selected_versions=() versions=()
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
        build_gcc "$latest_version" "/usr/local/programs/gcc-$latest_version"
        create_symlinks "$latest_version"
    done
}

check_requirements() {
    local missing_tools=() tools=()
    tools=(curl make tar autoreconf autoupdate autoconf)
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
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
    echo -e "  ${YELLOW}Installed GCC version(s): ${CYAN}${selected_versions[*]}${NC}"
    echo -e "  ${YELLOW}Installation prefix: ${CYAN}/usr/local/programs/gcc-${selected_versions[*]}${NC}"
    echo -e "  ${YELLOW}Build directory: ${CYAN}$build_dir${NC}"
    echo -e "  ${YELLOW}Temporary build directory retained: ${CYAN}$([[ "$keep_build_dir" -eq 1 ]] && echo "Yes" || echo "No")${NC}"
    if [[ -z "$log_file" ]]; then
        echo -e "  ${YELLOW}Log file: ${CYAN}Not Enabled${NC}"
    else
        echo -e "  ${YELLOW}Log file: ${CYAN}$log_file${NC}"
    fi
}

ld_linker_path() {
    local version
    version=$1
    [[ -d "$install_dir/lib64" ]] && echo "$install_dir/lib64" | sudo tee "/etc/ld.so.conf.d/custom_gcc-$version.conf" >/dev/null
    [[ -d "$install_dir/lib" ]] && echo "$install_dir/lib" | sudo tee -a "/etc/ld.so.conf.d/custom_gcc-$version.conf" >/dev/null
    sudo ldconfig
}

create_additional_soft_links() {
    local install_dir="$1"

    if [[ -d "$install_dir/lib/pkgconfig" ]]; then
        find "$install_dir/lib/pkgconfig" -type f -name '*.pc' | while read -r file; do
            sudo ln -sf "$file" "/usr/local/lib/pkgconfig/"
        done
    fi
}

build_done() {
    local package version
    package=$1
    version=$2
    log "Successfully built $package $version."
}

main() {
    parse_args "$@"

    if [[ "$EUID" -eq 0 ]]; then
        echo "This script must be run without root or with sudo."
        exit 1
    fi

    mkdir -p "$packages" "$workspace"

    if [[ -f /proc/cpuinfo ]]; then
        threads=$(grep -c ^processor /proc/cpuinfo)
    else
        threads=$(nproc --all)
    fi

    set_path
    set_pkg_config_path
    set_environment
    install_deps
    
    # Only install autoconf if necessary
    install_autoconf

    cleanup_build_folders
    select_versions
    cleanup
    summary

    log "Build completed successfully!"
    echo -e "\\n${GREEN}Make sure to star this repository to show your support!${NC}"
    echo "https://github.com/slyfox1186/script-repo"
}

main "$@"
