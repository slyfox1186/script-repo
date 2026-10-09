#!/usr/bin/env bash
set -Eeuo pipefail

# Script to build LLVM Clang
# Updated: 09.23.24
# Script version: 2.6
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

detect_cpu_threads() {
    local threads
    threads=""

    if command -v nproc >/dev/null 2>&1; then
        threads="$(nproc 2>/dev/null || true)"
    fi

    if [[ -z "$threads" || ! "$threads" =~ ^[0-9]+$ || "$threads" -lt 1 ]]; then
        threads="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
    fi

    if [[ -z "$threads" || ! "$threads" =~ ^[0-9]+$ || "$threads" -lt 1 ]]; then
        threads="1"
    fi

    printf '%s\n' "$threads"
}

CPU_THREADS="${CPU_THREADS:-$(detect_cpu_threads)}"

python_executable="${python_executable:-}"
if [[ -z "$python_executable" ]]; then
    if [[ -x /usr/bin/python3 ]]; then
        python_executable="/usr/bin/python3"
    elif [[ -x /usr/local/bin/python3 ]]; then
        python_executable="/usr/local/bin/python3"
    fi
fi
if [[ -z "$python_executable" ]]; then
    echo "Neither /usr/bin/python3 nor /usr/local/bin/python3 exists or is executable."
    exit 1
else
    printf "%s\n\n" "The Python executable is: $python_executable"
fi

fail() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo "For help or to report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

run() {
    local rendered
    printf -v rendered '%q ' "$@"
    printf "%b[CMD ]%b %s\n" "$GREEN" "$NC" "${rendered% }" >&2
    "$@"
}

require_commands() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || fail "Required command not found: $cmd"
    done
}

fetch_url() {
    local url
    url="$1"
    run wget -qO- --tries=3 --waitretry=2 "$url"
}

download_file() {
    local destination url
    url="$1"
    destination="$2"
    run wget -O "$destination" --tries=3 --waitretry=2 "$url"
}

check_root() {
    if [[ "$EUID" -eq 0 ]]; then
        fail "You must run this script without root or sudo."
    fi
}

ensure_sudo_access() {
    log "Validating sudo access..."
    run sudo -v
}

get_system_python() {
    python_executable=$(type -P python3)
    if [[ -z "$python_executable" ]]; then
        fail "python3 not found in the system. Please install python3."
    fi
    echo "$python_executable"
}

install_required_packages() {
    local -a apt_cmd install_cmd missing_packages
    local pkg pkgs
    apt_cmd=(sudo env DEBIAN_FRONTEND=noninteractive apt)
    pkgs=(
        autoconf autoconf-archive automake autopoint binutils binutils-dev
        build-essential ccache cmake doxygen jq libc6-dev libedit-dev
        libffi-dev libgmp-dev libomp-dev libpfm4-dev librust-atom-dev
        libtool libxml2-dev libzstd-dev m4 ninja-build python3-dev rsync
        swig zlib1g-dev nvidia-cuda-toolkit librocm-smi64-1 rocm-cmake rocm-smi
        wget
    )

    missing_packages=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ "${#missing_packages[@]}" -gt 0 ]]; then
        log "Installing missing packages: ${missing_packages[*]}"
        install_cmd=("${apt_cmd[@]}" install -y "${missing_packages[@]}")
        if run "${install_cmd[@]}"; then
            return
        fi

        warn "Direct apt install failed; refreshing package metadata and retrying."
        run "${apt_cmd[@]}" update
        run "${install_cmd[@]}"
    else
        log "All required packages are already installed."
        echo
    fi
}

set_highest_clang_version() {
    local -a available_versions
    local highest_version
    mapfile -t available_versions < <(apt-cache search --names-only '^clang-[0-9]+$' | cut -d' ' -f1 | sort -rV)
    if [[ ${#available_versions[@]} -eq 0 ]]; then
        fail "No clang versions found in the package manager."
    fi

    highest_version=${available_versions[0]}
    if ! dpkg-query -W -f='${Status}' "$highest_version" 2>/dev/null | grep -q "ok installed"; then
        log "Installing $highest_version..."
        run sudo env DEBIAN_FRONTEND=noninteractive apt install -y "$highest_version"
    fi

    CC="/usr/bin/$highest_version"
    CXX="/usr/bin/clang++-${highest_version#clang-}"
    export CC CXX
}

get_llvm_release_version() {
    if [[ -n "$custom_version" ]]; then
        llvm_version="$custom_version"
    else
        if command -v jq >/dev/null 2>&1; then
            llvm_version="$(
                fetch_url "https://api.github.com/repos/llvm/llvm-project/tags?per_page=100" \
                    | jq -r '.[].name' \
                    | sed -n 's/^llvmorg-//p' \
                    | sort -ruV \
                    | head -n1
            )"
        else
            llvm_version="$(
                fetch_url "https://github.com/llvm/llvm-project/tags/" \
                    | grep -oP 'llvmorg-\K\d+\.\d+\.\d+' \
                    | sort -ruV \
                    | head -n1
            )"
        fi
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
            read -r -p "Do you want to continue using: X86? (y/n): " choice_unknown_arch
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

get_llvm_native_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64) printf '%s\n' "X86" ;;
        aarch64|arm64) printf '%s\n' "AArch64" ;;
        s390x) printf '%s\n' "SystemZ" ;;
        ppc64le) printf '%s\n' "PowerPC" ;;
        riscv64) printf '%s\n' "RISCV" ;;
        *)
            warn "Unknown architecture '$arch'. Using LLVM native arch X86."
            printf '%s\n' "X86"
            ;;
    esac
}

set_compiler_flags() {
    CFLAGS="-fPIE -mtune=native -fstack-protector-strong -D_FORTIFY_SOURCE=2"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-rpath,$install_dir/lib -Wl,--as-needed"
    export CC CXX CFLAGS CXXFLAGS LDFLAGS
}

find_python_shared_lib() {
    local python_library_path python_prefix

    python_library_path="$("$python_executable" - <<'PY'
import os
import sysconfig

version = sysconfig.get_config_var("VERSION") or ""
abiflags = sysconfig.get_config_var("ABIFLAGS") or ""
libdir_candidates = []

for key in ("LIBDIR", "LIBPL"):
    value = sysconfig.get_config_var(key)
    if value and value not in libdir_candidates:
        libdir_candidates.append(value)

prefix = sysconfig.get_config_var("prefix") or sysconfig.get_config_var("base")
if prefix:
    prefix_lib = os.path.join(prefix, "lib")
    if prefix_lib not in libdir_candidates:
        libdir_candidates.append(prefix_lib)

library_names = []
for value in (
    sysconfig.get_config_var("LDLIBRARY"),
    sysconfig.get_config_var("LIBRARY"),
    f"libpython{version}{abiflags}.so" if version else "",
    f"libpython{version}.so" if version else "",
):
    if value and value not in library_names:
        library_names.append(value)

for directory in libdir_candidates:
    for library_name in library_names:
        candidate = os.path.join(directory, library_name)
        if os.path.isfile(candidate):
            print(candidate)
            raise SystemExit(0)

print("")
PY
)"

    if [[ -n "$python_library_path" && -f "$python_library_path" ]]; then
        echo "$python_library_path"
        return
    fi

    python_prefix="$("$python_executable" -c 'import sysconfig; print(sysconfig.get_config_var("prefix") or sysconfig.get_config_var("base") or "")')"
    if [[ -n "$python_prefix" ]]; then
        python_library_path="$(find "$python_prefix" -type f -name 'libpython3*.so*' 2>/dev/null | head -n1 || true)"
        if [[ -n "$python_library_path" && -f "$python_library_path" ]]; then
            echo "$python_library_path"
            return
        fi
    fi

    fail "Shared Python library not found for ${python_executable}. Please ensure Python is built with shared library support (e.g., install python3-dev)."
}

detect_system_triplet() {
    local config_guess

    for config_guess in /usr/share/misc/config.guess /usr/share/automake-*/config.guess; do
        if [[ -x "$config_guess" ]]; then
            "$config_guess"
            return
        fi
    done

    config_guess="${cwd}/config.guess"
    download_file "https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess" "$config_guess"
    chmod +x "$config_guess"
    "$config_guess"
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
    local c_release_flags cxx_release_flags llvm_force_vc_repository llvm_native_arch llvm_tar_filename llvm_tar_url system_triplet llvm_targets_to_build

    llvm_tar_url="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-$llvm_version.tar.gz"
    llvm_tar_filename="$cwd/llvmorg-$llvm_version.tar.gz"

    if [[ -f "$llvm_tar_filename" ]]; then
        log "The LLVM source file $llvm_tar_filename is already downloaded."
    else
        log "Downloading LLVM source from $llvm_tar_url..."
        download_file "$llvm_tar_url" "$llvm_tar_filename"
        log "Download completed"
        echo
    fi

    log "Extracting LLVM source to $workspace..."
    tar -zxf "$llvm_tar_filename" -C "$workspace" --strip-components 1 || fail "Failed to extract LLVM source."
    log "LLVM source code extracted to $workspace"
    echo

    system_triplet="$(detect_system_triplet)" || fail "Failed to determine system triplet."

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
    python_include_dir="$("$python_executable" -c 'import sysconfig; print(sysconfig.get_paths()["include"])')"

    if [[ ! -f "$python_shared_lib" ]]; then
        fail "Shared Python library not found at $python_shared_lib. Please ensure Python is built with shared library support."
    fi

    if [[ ! -d "$python_include_dir" ]]; then
        fail "Python include directory not found at $python_include_dir."
    fi

    # Determine LLVM_TARGETS_TO_BUILD dynamically
    llvm_targets_to_build=$(get_llvm_targets_to_build)
    llvm_native_arch=$(get_llvm_native_arch)
    llvm_force_vc_repository="https://github.com/llvm/llvm-project.git"
    c_release_flags="-O3 -DNDEBUG"
    cxx_release_flags="$c_release_flags"

    cd "$workspace" || fail "Failed to change directory to $workspace"

    log "Configuring Clang with CMake"
    echo

    rm -rf build

    run cmake -S llvm -B build \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_CXX_COMPILER="$CXX" \
          -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
          -DCMAKE_CXX_FLAGS_RELEASE="$cxx_release_flags" \
          -DCMAKE_C_COMPILER="$CC" \
          -DCMAKE_C_FLAGS="$CFLAGS" \
          -DCMAKE_C_FLAGS_RELEASE="$c_release_flags" \
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
          -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra" \
          -DLLVM_ENABLE_RUNTIMES="openmp" \
          -DLLVM_ENABLE_RTTI=OFF \
          -DLLVM_ENABLE_ZLIB=ON \
          -DLLVM_ENABLE_ZSTD=ON \
          -DLLVM_INCLUDE_EXAMPLES=OFF \
          -DLLVM_INCLUDE_RUNTIMES=ON \
          -DLLVM_INCLUDE_TESTS=ON \
          -DLLVM_INCLUDE_TOOLS=ON \
          -DLLVM_NATIVE_ARCH="$llvm_native_arch" \
          -DLLVM_OPTIMIZED_TABLEGEN=ON \
          -DLLVM_DEFAULT_TARGET_TRIPLE="$system_triplet" \
          -DLLVM_FORCE_VC_REPOSITORY="$llvm_force_vc_repository" \
          -G Ninja -Wno-dev
    echo
    log "Building Clang with Ninja"
    run cmake --build build --parallel "$CPU_THREADS"
    echo
    log "Installing Clang with Ninja"
    run sudo cmake --install build
}

create_symlinks() {
    local llvm_version_trim tool
    local -a tools
    llvm_version_trim="${llvm_version%%.*}"
    tools=(
        "clang-format" "clang-tidy" "clangd" "llvm-ar" "llvm-nm"
        "llvm-objdump" "llvm-dis" "llc" "lli" "opt"
    )

    echo
    log "Creating Soft Links..."
    echo

    run sudo ln -sfn "$install_dir/bin/clang" "/usr/local/bin/clang-$llvm_version_trim"
    run sudo ln -sfn "$install_dir/bin/clang++" "/usr/local/bin/clang++-$llvm_version_trim"
    run sudo ln -sfn "$install_dir/bin/clang" "/usr/local/bin/clang"
    run sudo ln -sfn "$install_dir/bin/clang++" "/usr/local/bin/clang++"

    for tool in "${tools[@]}"; do
        if [[ -x "$install_dir/bin/$tool" ]]; then
            run sudo ln -sfn "$install_dir/bin/$tool" "/usr/local/bin/$tool"
        else
            warn "Expected tool not found: $install_dir/bin/$tool"
        fi
    done
}

create_linker_config_file() {
    local linker_config_file
    linker_config_file="/etc/ld.so.conf.d/custom_clang_$llvm_version.conf"
    {
        echo "$install_dir/lib"
        dirname "$python_shared_lib"
    } | sudo tee "$linker_config_file" >/dev/null || fail "Failed to create linker config file."

    sudo ldconfig || fail "Failed to run ldconfig."
}

cleanup_build() {
    rm -fr "$cwd"
    log "Cleaned up the build directory."
}

list_llvm_versions() {
    echo "Fetching the list of available LLVM versions..."
    echo
    if command -v jq >/dev/null 2>&1; then
        fetch_url "https://api.github.com/repos/llvm/llvm-project/tags?per_page=100" \
            | jq -r '.[].name' \
            | sed -n 's/^llvmorg-//p' \
            | sort -ruV
    else
        fetch_url "https://github.com/llvm/llvm-project/tags/" \
            | grep -oP 'llvmorg-\K\d+\.\d+\.\d+' \
            | sort -ruV
    fi
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

resolve_build_root() {
    local base_dir

    base_dir="$PWD"
    if [[ "$base_dir" == *" "* ]]; then
        base_dir="${TMPDIR:-/tmp}"
        warn "Current directory contains spaces. Using space-safe build root: ${base_dir}"
    fi

    printf '%s\n' "${base_dir}/llvm-build-script"
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

    check_root
    require_commands apt apt-cache cut dpkg-query find grep sed sort sudo tar wget
    ensure_sudo_access

    # Set PATH to include ccache directory
    PATH="$(set_ccache_dir):$PATH"
    export PATH

    cwd="$(resolve_build_root)"
    workspace="$cwd/workspace"

    [[ -d "$workspace" ]] && rm -fr "$workspace"
    mkdir -p "$workspace/build" || fail "Failed to create workspace/build directory."

    install_required_packages
    require_commands cmake jq ninja python3-config rsync swig
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
