#!/usr/bin/env bash

# Script to build LLVM Clang-18 with GOLD enabled
# Updated: 03.16.24
# Script version: 1.2

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

fail() {
    echo -e "${RED}[ERROR] Bash: $1${NC}"
    echo "For help or to report a bug, create an issue at: $web_repo/issues"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING] Bash: $1${NC}"
}

log() {
    echo -e "${GREEN}[INFO] Bash: $1${NC}"
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        fail "Do not run this script as root or with sudo."
    fi
}

install_required_packages() {
    local pkgs=(
        autoconf autoconf-archive automake autopoint binutils binutils-dev bison
        build-essential ccache cmake curl doxygen jq libc6-dev libedit-dev
        libxml2-dev libzstd-dev ninja-build
    )

    local missing_packages=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [ "${#missing_packages[@]}" -gt 0 ]; then
        sudo apt update
        sudo apt install -y "${missing_packages[@]}"
    else
        log "All required packages are already installed."
    fi
}

set_compiler_flags() {
    CC=$(command -v clang)
    CXX=$(command -v clang++)
    CFLAGS="-g -O3 -pipe -march=native"
    CXXFLAGS="-g -O3 -pipe -march=native"
    LDFLAGS="-Wl,-rpath,/usr/local/lib -Wl,--as-needed"
    export CC CXX CFLAGS CXXFLAGS LDFLAGS
}

build_llvm_clang() {
    local llvm_url="https://github.com/llvm/llvm-project.git"
    local llvm_version=$(curl -sH "Content-Type: text/plain" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Misc/source-git-repo-version.sh" | bash -s "$llvm_url")

    local llvm_code_dir="$workspace"
    local llvm_source_file_dir="$source_files_dir"
    local llvm_tar_url="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-$llvm_version.tar.gz"
    local llvm_tar_filename="$llvm_source_file_dir/llvmorg-$llvm_version.tar.gz"

    if [ -f "$llvm_tar_filename" ]; then
        log "The LLVM source file $llvm_tar_filename is already downloaded."
    else
        log "Downloading LLVM source from $llvm_tar_url..."
        wget --show-progress -cqO "$llvm_tar_filename" "$llvm_tar_url"
        log "Download completed"
    fi

    log "Extracting LLVM source to $llvm_code_dir..."
    tar -zxf "$llvm_tar_filename" -C "$llvm_code_dir" --strip-components 1
    log "LLVM source code extracted to $llvm_code_dir"

    mkdir -p "$workspace/build"
    cd "$workspace" || fail "Failed to change directory to $workspace"

    cmake -S llvm -B build \
          -DBENCHMARK_BUILD_32_BITS=OFF \
          -DBENCHMARK_DOWNLOAD_DEPENDENCIES=OFF \
          -DBENCHMARK_ENABLE_ASSEMBLY_TESTS=OFF \
          -DBENCHMARK_ENABLE_DOXYGEN=OFF \
          -DBENCHMARK_ENABLE_EXCEPTIONS=OFF \
          -DBENCHMARK_ENABLE_GTEST_TESTS=OFF \
          -DBENCHMARK_ENABLE_INSTALL=OFF \
          -DBENCHMARK_ENABLE_LIBPFM=OFF \
          -DBENCHMARK_ENABLE_LTO=OFF \
          -DBENCHMARK_ENABLE_TESTING=OFF \
          -DBENCHMARK_ENABLE_WERROR=OFF \
          -DBENCHMARK_FORCE_WERROR=OFF \
          -DBENCHMARK_INSTALL_DOCS=OFF \
          -DBENCHMARK_USE_BUNDLED_GTEST=OFF \
          -DBENCHMARK_USE_LIBCXX=OFF \
          -DBUILD_SHARED_LIBS=OFF \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_CXX_COMPILER="$CXX" \
          -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
          -DCMAKE_C_COMPILER="$CC" \
          -DCMAKE_C_FLAGS="$CFLAGS" \
          -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
          -DCMAKE_INSTALL_PREFIX="$install_dir" \
          -DGOLD_EXECUTABLE=$(type -P ld.gold) \
          -DHAVE_STD_REGEX=ON \
          -DLLVM_ALLOW_PROBLEMATIC_CONFIGURATIONS=OFF \
          -DLLVM_APPEND_VC_REV=ON \
          -DLLVM_BINUTILS_INCDIR=/usr/include \
          -DLLVM_BUILD_32_BITS=OFF \
          -DLLVM_BUILD_BENCHMARKS=OFF \
          -DLLVM_BUILD_DOCS=OFF \
          -DLLVM_BUILD_EXAMPLES=OFF \
          -DLLVM_BUILD_EXTERNAL_COMPILER_RT=OFF \
          -DLLVM_BUILD_LLVM_DYLIB=OFF \
          -DLLVM_BUILD_RUNTIME=ON \
          -DLLVM_BUILD_RUNTIMES=ON \
          -DLLVM_BUILD_TESTS=OFF \
          -DLLVM_BUILD_TOOLS=ON \
          -DLLVM_BUILD_UTILS=ON \
          -DLLVM_BYE_LINK_INTO_TOOLS=OFF \
          -DLLVM_CCACHE_BUILD=ON \
          -DLLVM_DEPENDENCY_DEBUGGING=OFF \
          -DLLVM_DYLIB_COMPONENTS=all \
          -DLLVM_ENABLE_ASSERTIONS=OFF \
          -DLLVM_ENABLE_BACKTRACES=ON \
          -DLLVM_ENABLE_BINDINGS=ON \
          -DLLVM_ENABLE_CRASH_DUMPS=OFF \
          -DLLVM_ENABLE_CRASH_OVERRIDES=ON \
          -DLLVM_ENABLE_CURL=ON \
          -DLLVM_ENABLE_DAGISEL_COV=OFF \
          -DLLVM_ENABLE_DOXYGEN=ON \
          -DLLVM_ENABLE_DUMP=OFF \
          -DLLVM_ENABLE_EH=OFF \
          -DLLVM_ENABLE_EXPENSIVE_CHECKS=OFF \
          -DLLVM_ENABLE_FFI=OFF \
          -DLLVM_ENABLE_GISEL_COV=OFF \
          -DLLVM_ENABLE_HTTPLIB=OFF \
          -DLLVM_ENABLE_IDE=OFF \
          -DLLVM_ENABLE_LIBCXX=ON \
          -DLLVM_ENABLE_LIBEDIT=ON \
          -DLLVM_ENABLE_LIBPFM=ON \
          -DLLVM_ENABLE_LIBXML2=ON \
          -DLLVM_ENABLE_LLD=OFF \
          -DLLVM_ENABLE_LLVM_LIBC=OFF \
          -DLLVM_ENABLE_LOCAL_SUBMODULE_VISIBILITY=ON \
          -DLLVM_ENABLE_LTO=OFF \
          -DLLVM_ENABLE_MODULES=OFF \
          -DLLVM_ENABLE_MODULE_DEBUGGING=OFF \
          -DLLVM_ENABLE_NEW_PASS_MANAGER=ON \
          -DLLVM_ENABLE_OCAMLDOC=OFF \
          -DLLVM_ENABLE_PEDANTIC=ON \
          -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
          -DLLVM_ENABLE_PIC=ON \
          -DLLVM_ENABLE_PLUGINS=ON \
          -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra" \
          -DLLVM_ENABLE_RTTI=OFF \
          -DLLVM_ENABLE_SPHINX=OFF \
          -DLLVM_ENABLE_STRICT_FIXED_SIZE_VECTORS=OFF \
          -DLLVM_ENABLE_TERMINFO=ON \
          -DLLVM_ENABLE_THREADS=ON \
          -DLLVM_ENABLE_UNWIND_TABLES=ON \
          -DLLVM_ENABLE_WARNINGS=OFF \
          -DLLVM_ENABLE_WERROR=OFF \
          -DLLVM_ENABLE_Z3_SOLVER=OFF \
          -DLLVM_ENABLE_ZLIB=ON \
          -DLLVM_ENABLE_ZSTD=ON \
          -DLLVM_EXAMPLEIRTRANSFORMS_LINK_INTO_TOOLS=OFF \
          -DLLVM_EXPORT_SYMBOLS_FOR_PLUGINS=OFF \
          -DLLVM_EXTERNALIZE_DEBUGINFO=OFF \
          -DLLVM_FORCE_ENABLE_STATS=OFF \
          -DLLVM_FORCE_USE_OLD_TOOLCHAIN=OFF \
          -DLLVM_HAVE_TFLITE=OFF \
          -DLLVM_INCLUDE_BENCHMARKS=ON \
          -DLLVM_INCLUDE_DOCS=OFF \
          -DLLVM_INCLUDE_EXAMPLES=ON \
          -DLLVM_INCLUDE_RUNTIMES=ON \
          -DLLVM_INCLUDE_TESTS=OFF \
          -DLLVM_INCLUDE_TOOLS=ON \
          -DLLVM_INCLUDE_UTILS=ON \
          -DLLVM_NATIVE_ARCH=$(uname -m) \
          -DLLVM_OMIT_DAGISEL_COMMENTS=ON \
          -DLLVM_OPTIMIZED_TABLEGEN=ON \
          -DLLVM_OPTIMIZE_SANITIZED_BUILDS=ON \
          -DLLVM_TARGET_ARCH=host \
          -DLLVM_TEMPORARILY_ALLOW_OLD_TOOLCHAIN=OFF \
          -DLLVM_TOOL_BOLT_BUILD=OFF \
          -DLLVM_TOOL_CLANG_BUILD=OFF \
          -DLLVM_TOOL_COMPILER_RT_BUILD=OFF \
          -DLLVM_TOOL_CROSS_PROJECT_TESTS_BUILD=OFF \
          -DLLVM_TOOL_DRAGONEGG_BUILD=OFF \
          -DLLVM_TOOL_FLANG_BUILD=OFF \
          -DLLVM_TOOL_LIBCXXABI_BUILD=OFF \
          -DLLVM_TOOL_LIBCXX_BUILD=OFF \
          -DLLVM_TOOL_LIBC_BUILD=OFF \
          -DLLVM_TOOL_LIBUNWIND_BUILD=ON \
          -DLLVM_TOOL_LLDB_BUILD=OFF \
          -DLLVM_TOOL_LLD_BUILD=OFF \
          -DLLVM_TOOL_MLIR_BUILD=OFF \
          -DLLVM_TOOL_OPENMP_BUILD=OFF \
          -DLLVM_TOOL_POLLY_BUILD=OFF \
          -DLLVM_TOOL_PSTL_BUILD=OFF \
          -DLLVM_UNREACHABLE_OPTIMIZE=ON \
          -DLLVM_USE_FOLDERS=ON \
          -DLLVM_USE_LINKER=gold \
          -DLLVM_USE_SYMLINKS=ON \
          -DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=ON \
          -DPY_PYGMENTS_FOUND=ON \
          -DPY_PYGMENTS_LEXERS_C_CPP_FOUND=ON \
          -DPY_YAML_FOUND=ON \
          -G Ninja

    if ! ninja "-j$(nproc --all)" -C build; then
        fail "Failed to execute ninja -j$(nproc --all)"
    fi

    if ! sudo ninja -C build install; then
        fail "Failed to execute sudo ninja -C build install"
    fi
}

create_symlinks() {
    local llvm_version=$(curl -sH "Content-Type: text/plain" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Misc/source-git-repo-version.sh" | bash -s "https://github.com/llvm/llvm-project.git")
    local install_dir="/usr/local/llvm-$llvm_version"
    local symlink_dir="/usr/local/bin"

    for binary in "$install_dir/bin/"*; do
        local binary_name=${binary##*/}
        sudo ln -sf "$binary" "$symlink_dir/${binary_name%-*}"
    done
}

cleanup_build_files() {
    read -p "Do you want to remove the build files? [y/N]: " choice
    case "$choice" in
        y|Y) rm -fr "$workspace" ;;
        *) ;;
    esac
}

display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help    Display this help message"
    echo "  -c, --cleanup Remove build files after installation"
    echo
    echo "Description:"
    echo "  This script builds LLVM Clang-18 with GOLD enabled from source code."
    echo "  It downloads the source code, installs required dependencies, and"
    echo "  compiles the program with optimized settings."
    echo
    echo "Examples:"
    echo "  $0            # Build LLVM Clang-18 with default settings"
    echo "  $0 -c         # Build LLVM Clang-18 and remove build files afterwards"
    echo
    exit 0
}

main() {
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                display_help
                ;;
            -c|--cleanup)
                cleanup=true
                ;;
            *)
                warn "Invalid argument: $1"
                display_help
                ;;
        esac
        shift
    done

    check_root
    install_required_packages
    set_compiler_flags

    source_files_dir="$HOME/clang-18-build-script"
    workspace="$source_files_dir/workspace"
    web_repo="https://github.com/slyfox1186/script-repo"

    mkdir -p "$workspace" "$source_files_dir"

    build_llvm_clang
    create_symlinks

    if [ "$cleanup" = true ]; then
        cleanup_build_files
    fi

    log "The script has completed."
    log "Make sure to star this repository to show your support:"
    log "$web_repo"
}

main "$@"
