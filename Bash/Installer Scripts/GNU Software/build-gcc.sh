#!/usr/bin/env bash

# shellcheck disable=SC2162 source=/dev/null

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc.sh
# Purpose: Build GNU GCC
# GCC versions available: 10-14
# Features: Automatically sources the latest release of each version.
# Updated: 07.03.24
# Script version: 1.4

build_dir="/tmp/gcc-build-script"
packages="$build_dir/packages"
workspace="$build_dir/workspace"
target_arch="x86_64-linux-gnu"
keep_build_dir=0
log_file=""
save_binaries=0
selected_versions=()
enable_multilib=0
verbose=0
version=""
versions=(10 11 12 13 14)
static_build=0
optimization_level="-O2"
debug_mode=0
dry_run=0

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
    echo "  -s, --save                 Save static binaries (only works with --static)"
    echo "  -v, --verbose              Enable verbose logging"
    echo "  --static                   Build static GCC executables"
    echo "  -O LEVEL                   Set optimization level (0, 1, 2, 3, fast, g, s)"
    echo "  --debug                    Enable debug mode"
    echo "  --dry-run                  Perform a dry run without making any changes"
    echo "  --enable-multilib          Enable multilib support (disabled by default)"
    echo "  -g, --generic              Use generic tuning instead of native"
    echo
    exit 0
}

log() {
    if [[ "$verbose" -eq 1 ]]; then
        echo -e "${GREEN}[INFO $(date +"%I:%M:%S %p")]${NC} $1"
    fi
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

# Error Handling and Logging
parse_args() {
    local generic_build=0
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -s|--save)
                save_binaries=1
                shift
                ;;
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
            --static)
                static_build=1
                shift
                ;;
            -O)
                optimization_level="-O$2"
                shift 2
                ;;
            --debug)
                debug_mode=1
                shift
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            --enable-multilib)
                enable_multilib=1
                shift
                ;;
            -g|--generic)
                generic_build=1
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)  fail "Unknown option: $1. Use -h or --help for usage information." ;;
        esac
    done

    if [[ "$save_binaries" -eq 1 && "$static_build" -eq 0 ]]; then
        fail "The --save option can only be used with --static."
    fi
}

execute() {
    echo "$ $*"

    if [[ "$dry_run" -eq 1 ]]; then
        log "Dry run: would execute $*"
        return 0
    fi

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
    CC="gcc"
    CXX="g++"
    if [[ "$generic_build" -eq 1 ]]; then
        CFLAGS="$optimization_level -pipe -march=generic -mtune=generic -fstack-protector-strong"
    else
        CFLAGS="$optimization_level -pipe -march=native -mtune=native -fstack-protector-strong"
    fi
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2"
    if [[ "$static_build" -eq 1 ]]; then
        LDFLAGS="-static -L/usr/lib/x86_64-linux-gnu -Wl,-z,relro -Wl,-z,now"
    else
        LDFLAGS="-L/usr/lib/x86_64-linux-gnu -Wl,-rpath,$install_dir/lib64 -Wl,-rpath,$install_dir/lib -Wl,-z,relro -Wl,-z,now"
    fi
    export CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS

    # Find nvcc and set CUDA check flag
    if find /usr/local/ /opt/ -type f -name nvcc 2>/dev/null | grep -q 'nvcc'; then
        cuda_check="--enable-offload-targets=nvptx-none"
        log "CUDA support enabled"
    else
        cuda_check=""
        log "CUDA support not found"
    fi
}

build() {
    local package version options
    package=$1
    version=$2
    options=$3
    log "Building $package $version..."

    # Change to the build directory
    cd "$build_dir" || fail "Failed to change directory to $build_dir"

    case "$package" in
        gcc)
            check_disk_space 5000
            download "https://ftp.gnu.org/gnu/gcc/gcc-$version/gcc-$version.tar.xz" || fail "Failed to download gcc-$version.tar.xz"
            tar -Jxf "gcc-$version.tar.xz" || fail "Failed to extract the source code files to the directory gcc-$version"
            cd "gcc-$version" || fail "Failed to change directory to gcc-$version"
            execute ./contrib/download_prerequisites
            mkdir -p build && cd build || fail "Failed to create and enter build directory"
            execute ../configure $options
            execute make "-j$threads"
            execute sudo make install-strip || fail "Failed to execute 'sudo make install-strip'"
            ;;
        autoconf)
            download "https://ftp.gnu.org/gnu/autoconf/autoconf-$version.tar.xz"
            tar -xf "autoconf-$version.tar.xz"
            cd "autoconf-$version" || fail "Failed to change directory to autoconf-$version"
            execute ./configure --prefix="$workspace"
            execute make "-j$threads"
            execute sudo make install || fail "Failed to execute 'sudo make install'"
            ;;
        *)
            fail "Unsupported package: $package"
            ;;
    esac

    return 0
}

verify_checksum() {
    local file=$1
    local version=$2
    local sig_url="https://ftp.gnu.org/gnu/gcc/gcc-${version}/gcc-${version}.tar.xz.sig"
    local expected_checksum

    if ! expected_checksum=$(curl -fsSL "$sig_url" | grep -oP '(?<=SHA512 CHECKSUM: )[a-f0-9]+'); then
        log "Failed to retrieve checksum from $sig_url"
        return 1
    fi

    if [[ -z "$expected_checksum" ]]; then
        log "No checksum found in the signature file"
        return 1
    fi

    local actual_checksum
    actual_checksum=$(sha512sum "$file" | awk '{print $1}')

    if [[ "$expected_checksum" != "$actual_checksum" ]]; then
        log "Checksum mismatch:"
        log "Expected: $expected_checksum"
        log "Actual:   $actual_checksum"
        return 1
    fi

    return 0
}

check_disk_space() {
    local required_space=$1  # in MB
    local available_space

    available_space=$(df -m "$build_dir" | awk 'NR==2 {print $4}')
    if [[ $available_space -lt $required_space ]]; then
        fail "Insufficient disk space. Required: ${required_space}MB, Available: ${available_space}MB"
    fi
}

trim_binaries() {
    local version=$1
    local install_dir="/usr/local/programs/gcc-$version"
    local bin_dir="$install_dir/bin"
    
    log "Trimming binary filenames in $bin_dir"
    
    for file in "$bin_dir"/x86_64-linux-gnu-*; do
        if [[ -f "$file" ]]; then
            local new_name="${file##*/}"
            new_name="${new_name#x86_64-linux-gnu-}"
            sudo mv "$file" "$bin_dir/$new_name"
            log "Renamed $file to $new_name"
        fi
    done
}

save_static_binaries() {
    local version=$1
    local install_dir="/usr/local/programs/gcc-$version"
    local save_dir="./gcc-${version}-saved-binaries"
    
    if [[ "$static_build" -eq 1 && "$save_binaries" -eq 1 ]]; then
        log "Saving static binaries to $save_dir"
        mkdir -p "$save_dir"
        
        local programs=(
            "cpp-$version" "c++-$version" "gccgo-$version" "gcc-$version"
            "gcc-ar-$version" "gcc-nm-$version" "gcc-ranlib-$version" "gcov-$version"
            "gcov-dump-$version" "gcov-tool-$version" "gfortran-$version" "gnatbind-$version"
            "gnatchop-$version" "gnatclean-$version" "gnatkr-$version" "gnatlink-$version"
            "gnatls-$version" "gnatmake-$version" "gnatname-$version" "gnatprep-$version"
            "gnat-$version" "gofmt-$version" "go-$version" "g++-$version"
        )

        for program in "${programs[@]}"; do
            local source_file="$install_dir/bin/$program"
            if [[ -f "$source_file" ]]; then
                cp "$source_file" "$save_dir/$program"
            else
                warn "Binary not found: $source_file"
            fi
        done
        
        log "Static binaries saved to $save_dir"
    fi
}

download() {
    local url file version
    url=$1
    file=${url##*/}
    version=$(echo "$file" | grep -oP 'gcc-\K[0-9.]+(?=\.tar\.xz)')
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if [[ -f "$build_dir/$file" ]]; then
            log "File $file already exists, but will be verified during extraction."
            return 0
        fi

        log "Downloading $file from $url..."
        if [[ "$dry_run" -eq 0 ]]; then
            if curl -fsSL "$url" -o "$build_dir/$file"; then
                log "Successfully downloaded $file"
                return 0
            else
                log "Failed to download $file"
            fi
        else
            log "Dry run: would download $file from $url"
            return 0
        fi

        ((attempt++))
    done

    fail "Failed to download $file after $max_attempts attempts"
}

create_symlinks() {
    local version=$1
    local install_dir="/usr/local/programs/gcc-$version"
    local bin_dir="$install_dir/bin"
    
    log "Creating symlinks for GCC $version..."
    
    for file in "$bin_dir"/*; do
        if [[ -f "$file" && ! -L "$file" ]]; then
            local base_name="${file##*/}"
            sudo ln -sf "$file" "/usr/local/bin/$base_name"
            log "Created symlink for $base_name"
        fi
    done
}

install_deps() {
    local -a missing_pkgs=() pkgs=()
    local pkg
    
    log "Installing dependencies..."

    pkgs=(
        autoconf autoconf-archive automake binutils bison
        build-essential ccache curl flex gawk gcc gnat libc6-dev
        libisl-dev libtool make m4 patch texinfo zlib1g-dev libzstd-dev
        libc6-dev libc6-dev-i386 linux-libc-dev linux-libc-dev:i386
    )

    if [[ "$dry_run" -eq 0 ]]; then
        sudo dpkg --add-architecture i386
    else
        log "Dry run: would add i386 architecture"
    fi

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ -n "${missing_pkgs[*]}" ]]; then
        if [[ "$dry_run" -eq 0 ]]; then
            sudo apt update
            sudo apt install "${missing_pkgs[@]}"
        else
            log "Dry run: would install ${missing_pkgs[*]}"
        fi
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

post_build_tasks() {
    local short_version version
    version=$1
    short_version="${version%%.*}"
    install_dir="/usr/local/programs/gcc-$version"

    if [[ -d "$install_dir/libexec/gcc/x86_64-pc-linux-gnu/$short_version" ]]; then
        execute sudo libtool --finish "$install_dir/libexec/gcc/x86_64-pc-linux-gnu/$short_version"
    elif [[ -d "$install_dir/libexec/gcc/x86_64-linux-gnu/$short_version" ]]; then
        execute sudo libtool --finish "$install_dir/libexec/gcc/x86_64-linux-gnu/$short_version"
    elif [[ -d "$install_dir/libexec/gcc/$pc_type/$short_version" ]]; then
        execute sudo libtool --finish "$install_dir/libexec/gcc/$pc_type/$short_version"
    else
        fail "The script could not find the correct folder for libtool to run --finish on. Line: $LINENO"
    fi

    create_symlinks "$version"
}

build_gcc() {
    local -a common_options=() configure_options=()
    local version install_dir
    version=$1
    install_dir="/usr/local/programs/gcc-$version"

    pc_type=$(gcc -dumpmachine) || fail "Failed to determine machine type."

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
        "--enable-threads=posix"
        "--libdir=$install_dir/lib"
        "--libexecdir=$install_dir/libexec"
        "--program-prefix=$pc_type-"
        "--program-suffix=-$short_version"
        "--with-abi=m64"
        "--with-default-libstdcxx-abi=new"
        "--with-gcc-major-version-only"
        "--with-isl=/usr"
        "--with-system-zlib"
        "--with-target-system-zlib=auto"
        "$cuda_check"
    )

    if [[ "$generic_build" -eq 1 ]]; then
        common_options+=("--with-tune=generic")
    else
        common_options+=("--with-tune=native")
    fi

    if [[ "$enable_multilib" -eq 1 ]]; then
        common_options+=("--enable-multilib" "--with-arch-32=i686")
    else
        common_options+=("--disable-multilib")
    fi

    if [[ "$static_build" -eq 1 ]]; then
        common_options+=(
            "--disable-shared"
            "--enable-static"
            "--disable-plugin"
        )
    else
        common_options+=(
            "--enable-shared"
            "--enable-plugin"
            "--enable-bootstrap"
        )
    fi

    log "Configuring GCC $version"

    case "$short_version" in
        9|10|11) configure_options=("${common_options[*]}") ;;
        12) configure_options=("${common_options[*]}" --with-link-serialization=2) ;;
        13|14) configure_options=("${common_options[*]}" --disable-vtable-verify --enable-cet --enable-link-serialization=2 --enable-host-pie) ;;
        *)  fail "GCC version not found. Line: $LINENO" ;;
    esac

    build gcc "$version" "${configure_options[*]}"
    post_build_tasks "$version"
    ld_linker_path "$short_version"
    trim_binaries "$version"
    save_static_binaries "$version"
    create_symlinks "$version"
}

cleanup() {
    if [[ "$keep_build_dir" -ne 1 ]]; then
        log "Cleaning up..."
        if [[ "$dry_run" -eq 0 ]]; then
            sudo rm -fr "$build_dir"
            log "Removed temporary build directory: $build_dir"
        else
            log "Dry run: would remove temporary build directory: $build_dir"
        fi
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
    echo -e "  ${YELLOW}Save static binaries: ${CYAN}$([[ "$save_binaries" -eq 1 && "$static_build" -eq 1 ]] && echo "Yes" || echo "No")${NC}"
    echo -e "  ${YELLOW}Temporary build directory retained: ${CYAN}$([[ "$keep_build_dir" -eq 1 ]] && echo "Yes" || echo "No")${NC}"
    echo -e "  ${YELLOW}Static build: ${CYAN}$([[ "$static_build" -eq 1 ]] && echo "Yes" || echo "No")${NC}"
    echo -e "  ${YELLOW}Optimization level: ${CYAN}$optimization_level${NC}"
    echo -e "  ${YELLOW}Debug mode: ${CYAN}$([[ "$debug_mode" -eq 1 ]] && echo "Enabled" || echo "Disabled")${NC}"
    echo -e "  ${YELLOW}Dry run: ${CYAN}$([[ "$dry_run" -eq 1 ]] && echo "Yes" || echo "No")${NC}"
    echo -e "  ${YELLOW}Multilib support: ${CYAN}$([[ "$enable_multilib" -eq 1 ]] && echo "Enabled" || echo "Disabled")${NC}"
    if [[ -z "$log_file" ]]; then
        echo -e "  ${YELLOW}Log file: ${CYAN}Not Enabled${NC}"
    else
        echo -e "  ${YELLOW}Log file: ${CYAN}$log_file${NC}"
    fi
}

ld_linker_path() {
    local version
    version=$1
    if [[ "$dry_run" -eq 0 ]]; then
        [[ -d "$install_dir/lib64" ]] && echo "$install_dir/lib64" | sudo tee "/etc/ld.so.conf.d/custom_gcc-$version.conf" >/dev/null
        [[ -d "$install_dir/lib" ]] && echo "$install_dir/lib" | sudo tee -a "/etc/ld.so.conf.d/custom_gcc-$version.conf" >/dev/null
        sudo ldconfig
    else
        log "Dry run: would update ld.so.conf and run ldconfig"
    fi
}

create_additional_soft_links() {
    local install_dir="$1"

    if [[ -d "$install_dir/lib/pkgconfig" ]]; then
        if [[ "$dry_run" -eq 0 ]]; then
            find "$install_dir/lib/pkgconfig" -type f -name '*.pc' | while read -r file; do
                sudo ln -sf "$file" "/usr/local/lib/pkgconfig/"
            done
        else
            log "Dry run: would create additional soft links in /usr/local/lib/pkgconfig/"
        fi
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

    cleanup_build_folders

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

    select_versions
    cleanup
    summary

    log "Build completed successfully!"
    echo -e "\\n${GREEN}Make sure to star this repository to show your support!${NC}"
    echo "https://github.com/slyfox1186/script-repo"
}

main "$@"
