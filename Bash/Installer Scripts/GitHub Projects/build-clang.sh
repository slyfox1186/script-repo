#!/usr/bin/env bash

# Script to build LLVM Clang
# Updated: 09.23.24
# Script version: 2.5
# Modified to dynamically set LLVM_TARGETS_TO_BUILD based on host architecture
# Enhanced to handle Conda environments and ensure Python shared library is used

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Bind variables
cleanup=true
custom_version=""
python_include_dir=""
python_shared_lib=""

python_executable="${python_executable:-$( [[ -x /usr/bin/python3 ]] && echo /usr/bin/python3 || ([[ -x /usr/local/bin/python3 ]] && echo /usr/local/bin/python3))}"
if [[ -z "$python_executable" ]]; then
    echo "Neither /usr/bin/python3 nor /usr/local/bin/python3 exists or is executable."
    exit 1
else
    printf "%s\n\n" "The Python executable is: $python_executable"
fi

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "For help or to report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

check_root() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "You must run this script without root or sudo."
    fi
}

get_system_python() {
    python_executable=$(type -P python3)
    if [[ -z "$python_executable" ]]; then
        fail "python3 not found in the system. Please install python3."
    fi
    echo "$python_executable"
}

install_required_packages() {
    local -a missing_packages
    local pkg pkgs
    pkgs=(
        autoconf autoconf-archive automake autopoint binutils binutils-dev
        build-essential ccache cmake curl doxygen jq libc6-dev libedit-dev
        libffi-dev libgmp-dev libomp-dev libpfm4-dev librust-atom-dev
        libtool libxml2-dev libzstd-dev m4 ninja-build python3-dev rsync
        swig zlib1g-dev nvidia-cuda-toolkit librocm-smi64-1 rocm-cmake rocm-smi
    )

    missing_packages=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ "${#missing_packages[@]}" -gt 0 ]]; then
        log "Installing missing packages: ${missing_packages[*]}"
        apt-get update
        apt-get install -y "${missing_packages[@]}" || fail "Failed to install required packages."
    else
        log "All required packages are already installed."
        echo
    fi
}

set_highest_clang_version() {
    local available_versions highest_version
    available_versions=($(apt-cache search --names-only '^clang-[0-9]+$' | cut -d' ' -f1 | sort -rV))
    if [[ ${#available_versions[@]} -eq 0 ]]; then
        fail "No clang versions found in the package manager."
    fi

    highest_version=${available_versions[0]}
    if ! dpkg-query -W -f='${Status}' "$highest_version" 2>/dev/null | grep -q "ok installed"; then
        log "Installing $highest_version..."
        apt-get -y install "$highest_version" || fail "Failed to install $highest_version."
    fi

    CC="/usr/bin/$highest_version"
    CXX="/usr/bin/clang++-${highest_version#clang-}"
    export CC CXX
}

get_llvm_release_version() {
    if [[ -n "$custom_version" ]]; then
        llvm_version="$custom_version"
    else
        llvm_version=$(curl -fsS "https://github.com/llvm/llvm-project/tags/" | grep -oP 'llvmorg-\K\d+\.\d+\.\d+' | sort -ruV | head -n1)
        if [[ -z "$llvm_version" ]]; then
            fail "Unable to fetch the latest LLVM release version."
        fi
    fi
    log "Selected LLVM version: $llvm_version"
}

get_llvm_targets_to_build() {
    local arch llvm_targets

    arch=$(uname -m)
    case "$arch" in
        x86_64)
            llvm_targets="X86;NVPTX;AMDGPU"
            ;;
        aarch64|arm64)
            llvm_targets="ARM;NVPTX;AMDGPU"
            ;;
        s390x)
            llvm_targets="SystemZ;NVPTX;AMDGPU"
            ;;
        ppc64le)
            llvm_targets="PowerPC;NVPTX;AMDGPU"
            ;;
        riscv64)
            llvm_targets="RISCV;NVPTX;AMDGPU"
            ;;
        *)
            warn "Unknown architecture '$arch'. Defaulting LLVM_TARGETS_TO_BUILD to 'X86'."
            read -p "Do you want to continue using: X86? (y/n): " choice_unknown_arch
            case "$choice_unknown_arch" in
                [yY]*)
                    llvm_targets="X86"
                    ;;
                [nN]*)
                    printf "\n%s\n\n" "Exiting script..."
                    exit 0
                    ;;
                *)
                    printf "\n%s\n\n" "Bad user input, restart the script."
                    exit 1
                    ;;
            esac
            ;;
    esac

    echo "$llvm_targets"
}

set_compiler_flags() {
    CFLAGS="-O2 -fPIE -mtune=native -DNDEBUG -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wno-unused-parameter"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-rpath,$install_dir/lib -Wl,--as-needed"
    export CC CXX CFLAGS CXXFLAGS LDFLAGS
}

find_python_shared_lib() {
    local python_library_dir python_ldlibrary python_library_path

    python_library_dir=$(python3-config --prefix)/lib
    python_ldlibrary=$(python3-config --ldflags | grep -oP '(-lpython3\.12)' | cut -d'=' -f2)

    if [[ -z "$python_ldlibrary" ]]; then
        # Attempt to find the shared library directly
        python_library_path=$(find "$python_library_dir" -name "libpython3*.so" | head -n1)
    else
        python_library_path="/usr/local/programs/python3-3.12.4/lib/libpython3.12.so"
    fi

    if [[ -f "$python_library_path" ]]; then
        echo "$python_library_path"
    else
        # Attempt to locate in the current Python environment
        python_library_path=$(python3 -c 'import sysconfig; import os; print(os.path.join(sysconfig.get_config_var("LIBDIR"), "libpython3.12.so"))')
        if [[ -f "$python_library_path" ]]; then
            echo "$python_library_path"
        else
            # Search in common directories
            python_library_path=$(find "$(dirname "$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("LIBDIR"))')")" -name "libpython3*.so" | head -n1)
            if [[ -f "$python_library_path" ]]; then
                echo "$python_library_path"
            else
                fail "Shared Python library not found. Please ensure Python is built with shared library support (e.g., install python3-dev)."
            fi
        fi
    fi
}

parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --python)
                if [[ -n "$2" ]]; then
                    python_executable="$2"
                    shift
                else
                    warn "The --python option requires a non-empty option argument."
                    display_help
                fi
                ;;
            -h|--help)
                display_help
                ;;
            -k|--keep)
                cleanup=false
                ;;
            -v|--version)
                if [[ -n "$2" ]]; then
                    custom_version="$2"
                    shift
                else
                    warn "Version argument requires a value"
                    display_help
                fi
                ;;
            -l|--list)
                list_llvm_versions
                ;;
            *)
                warn "Invalid argument: $1"
                display_help
                ;;
        esac
        shift
    done
}

build_llvm_clang() {
    local llvm_tar_filename llvm_tar_url system_triplet llvm_targets_to_build

    llvm_tar_url="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-$llvm_version.tar.gz"
    llvm_tar_filename="$cwd/llvmorg-$llvm_version.tar.gz"

    if [[ -f "$llvm_tar_filename" ]]; then
        log "The LLVM source file $llvm_tar_filename is already downloaded."
    else
        log "Downloading LLVM source from $llvm_tar_url..."
        wget --show-progress -cqO "$llvm_tar_filename" "$llvm_tar_url" || fail "Failed to download LLVM source."
        log "Download completed"
        echo
    fi

    log "Extracting LLVM source to $workspace..."
    tar -zxf "$llvm_tar_filename" -C "$workspace" --strip-components 1 || fail "Failed to extract LLVM source."
    log "LLVM source code extracted to $workspace"
    echo

    system_triplet=$(curl -fsS "https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess" | bash) || fail "Failed to determine system triplet."

    # Define Python executable, shared library and include directory
    if [[ -n "$python_executable" ]]; then
        # User-specified Python
        if [[ ! -x "$python_executable" ]]; then
            fail "Specified Python executable '$python_executable' is not executable."
        fi
        log "Using specified Python executable: $python_executable"
    else
        # Use system or active Conda environment's Python
        python_executable=$(get_system_python)
        log "Using detected Python executable: $python_executable"
    fi

    python_shared_lib=$(find_python_shared_lib)
    python_include_dir=$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["include"])')

    if [[ ! -f "$python_shared_lib" ]]; then
        fail "Shared Python library not found at $python_shared_lib. Please ensure Python is built with shared library support."
    fi

    if [[ ! -d "$python_include_dir" ]]; then
        fail "Python include directory not found at $python_include_dir."
    fi

    # Determine LLVM_TARGETS_TO_BUILD dynamically
    llvm_targets_to_build=$(get_llvm_targets_to_build)

    cd "$workspace" || fail "Failed to change directory to $workspace"

    log "Configuring Clang with CMake"
    echo

    cmake -S llvm -B build \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_CXX_COMPILER="$CXX" \
          -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
          -DCMAKE_C_COMPILER="$CC" \
          -DCMAKE_C_FLAGS="$CFLAGS" \
          -DCMAKE_INSTALL_PREFIX="$install_dir" \
          -DLLVM_TARGETS_TO_BUILD="$llvm_targets_to_build" \
          -DLLVM_BUILD_DOCS=OFF \
          -DLLVM_BUILD_EXAMPLES=OFF \
          -DLLVM_BUILD_TESTS=OFF \
          -DLLVM_BUILD_TOOLS=ON \
          -DLLVM_CCACHE_BUILD=ON \
          -DLLVM_ENABLE_ASSERTIONS=OFF \
          -DLLVM_ENABLE_LTO=OFF \
          -DLLVM_ENABLE_PIC=ON \
          -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra;openmp" \
          -DLLVM_ENABLE_RTTI=OFF \
          -DLLVM_ENABLE_ZLIB=ON \
          -DLLVM_ENABLE_ZSTD=ON \
          -DLLVM_INCLUDE_EXAMPLES=OFF \
          -DLLVM_INCLUDE_RUNTIMES=ON \
          -DLLVM_INCLUDE_TESTS=ON \
          -DLLVM_INCLUDE_TOOLS=ON \
          -DLLVM_NATIVE_ARCH="$(uname -m)" \
          -DLLVM_OPTIMIZED_TABLEGEN=ON \
          -DLLVM_DEFAULT_TARGET_TRIPLE="$system_triplet" \
          -G Ninja -Wno-dev || fail "CMake configuration failed."
    echo
    log "Building Clang with Ninja"
    ninja "-j$(nproc --all)" -C build || fail "Failed to execute ninja -j$(nproc --all)"
    echo
    log "Installing Clang with Ninja"
    sudo ninja -C build install || fail "Failed to execute ninja -C build install"
}

create_symlinks() {
    local llvm_version_trim non_versioned_tool tool tools versioned_clang versioned_clangpp
    llvm_version_trim="${llvm_version%%.*}"
    versioned_clang="clang-$llvm_version_trim"
    versioned_clangpp="clang++-$llvm_version_trim"

    tools=(
        clang-$llvm_version_trim clang++-$llvm_version_trim clang-format
        clang-tidy clangd llvm-ar llvm-nm llvm-objdump llvm-dis llc lli opt
    )

    for tool in "${tools[@]}"; do
        if [[ "$tool" == "clang++-$llvm_version_trim" ]]; then
            ln -sf "$install_dir/bin/clang++" "/usr/local/bin/$tool" || warn "Failed to create symlink for $tool."
        else
            ln -sf "$install_dir/bin/$tool" "/usr/local/bin/$tool" || warn "Failed to create symlink for $tool."
            non_versioned_tool="${tool%-*}"
            if [[ "$tool" != "$non_versioned_tool" ]]; then
                ln -sf "$install_dir/bin/$tool" "/usr/local/bin/$non_versioned_tool" || warn "Failed to create symlink for $non_versioned_tool."
            fi
        fi
    done
}

create_linker_config_file() {
    local linker_config_file
    linker_config_file="/etc/ld.so.conf.d/custom_clang_$llvm_version.conf"
    {
        echo "$install_dir/lib"
        echo "$(dirname "$python_shared_lib")"
    } | tee "$linker_config_file" >/dev/null || fail "Failed to create linker config file."

    ldconfig || fail "Failed to run ldconfig."
}

cleanup_build() {
    rm -fr "$cwd"
    log "Cleaned up the build directory."
}

list_llvm_versions() {
    echo "Fetching the list of available LLVM versions..."
    echo
    curl -fsS "https://github.com/llvm/llvm-project/tags/" | grep -oP 'llvmorg-\K\d+\.\d+\.\d+' | sort -ruV
    exit 0
}

set_ccache_dir() {
    if [[ -d "/usr/lib/ccache/bin" ]]; then
        ccache_dir="/usr/lib/ccache/bin"
    else
        ccache_dir="/usr/lib/ccache"
    fi
    echo "$ccache_dir"
}

display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --python <path>        Specify the Python executable to use (default: system or active Conda env's python3)"
    echo "  -h, --help             Display this help message"
    echo "  -k, --keep             Keep the build files after installation"
    echo "  -l, --list             List available LLVM versions"
    echo "  -v, --version <ver>    Specify a custom version of Clang to download and build"
    echo
    echo "Description:"
    echo "  This script builds LLVM Clang from source code."
    echo "  It downloads the source code, installs the required"
    echo "  dependencies, and compiles the program with optimized settings."
    echo
    echo "Examples:"
    echo "  $0                           # Build the latest release version of LLVM Clang available"
    echo "  $0 -k -v 19.1.0              # Build LLVM Clang version 19.1.0 and then clean up the build files"
    echo "  $0 --python /usr/bin/python3  # Use a specific Python executable for building"
    echo "  $0 -l                        # List available LLVM versions"
    echo
    exit 0
}

main() {
    # Parse command-line arguments
    parse_arguments "$@"

    # Set PATH to include ccache directory
    PATH="$(set_ccache_dir):$PATH"
    export PATH

    cwd="$PWD/llvm-build-script"
    workspace="$cwd/workspace"

    [[ -d "$workspace" ]] && rm -fr "$workspace"
    mkdir -p "$workspace/build" || fail "Failed to create workspace/build directory."

    check_root
    install_required_packages
    set_highest_clang_version
    get_llvm_release_version

    install_dir="/usr/local/programs/llvm-$llvm_version"

    set_compiler_flags
    build_llvm_clang
    create_symlinks
    create_linker_config_file

    [[ "$cleanup" == "true" ]] && cleanup_build

    echo
    log "The script has completed successfully."
    echo
    log "Make sure to star this repository to show your support:"
    log "https://github.com/slyfox1186/script-repo"
}

main "$@"
