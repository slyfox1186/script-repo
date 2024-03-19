#!/usr/bin/env bash
# Shellcheck disable=sc2162,sc2317

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-clang-17-gold
##  Purpose: Build LLVM Clang-17 with GOLD enabled
##  Updated: 03.06.24
##  Script version: 1.7

log() {
    echo "[LOG] $1"
}

fail_fn() {
    echo
    echo "[ERROR] $1"
    echo
    echo "For help or to report a bug create an issue at: $web_repo/issues"
    echo
    exit 1
}

# Function to check if running as root/sudo
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "You must run this script with root or sudo.privileges."
        echo
        exit 1
    fi
}

# Function to install required apt packages
install_required_packages() {
    local pkgs=(
        autoconf autoconf-archive automake autopoint binutils binutils-dev
        bison build-essential ccache clang cmake curl doxygen jq libc6 libc6-dev
        libedit-dev libtool libtool-bin libxml2-dev libzstd-dev m4 nasm ninja-build
        yasm zlib1g-dev
    )

    local missing_packages=()

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [ "${#Missing_packages[@]}" -gt 0 ]; then
        apt update
        apt install "${missing_packages[@]}"
    else
        log "All required packages are already installed."
    fi
}

# Function to fix missing x265 library symlink
fix_missing_x265_lib() {
    local link_in=$(find /usr/lib/x86_64-linux-gnu/ -type f -name 'libstdc++.so.6.0.*')
    local link_out="/usr/lib/x86_64-linux-gnu/libstdc++.so"

    if [[ ! -f "$link_out" ]] && [[ -f "$link_in" ]]; then
        ln -sf "$link_in" "$link_out"
    fi
}

find_highest_clang_version() {
    local clang_version

# Check if a specific version is installed, in descending order of preference
    for clang_version in 16 15 14 13; do
        if command -v "clang-$clang_version" &>/dev/null; then
            CC="clang-$clang_version"
            CXX="clang++-$clang_version"
            return
        fi
    done

# If none of the specific versions are found, fall back to "clang" if it's installed
    if command -v clang &>/dev/null; then
        CC="clang"
        CXX="clang++"
    else
        fail_fn "Clang is not installed."
    fi
}

# Function to download and extract a file
download_and_extract() {
    local url="$1"
    local target_dir="$2"
    local filename="${url##*/}"
    clear
    set -x
    echo $filename
    exit
    if [ -f "$target_dir/$filename" ]; then
        log "The file $filename is already downloaded."
    else
        log "Downloading $url saving as $filename"
        wget --show-progress -cqO "$target_dir/$filename" "$url"
        log "Download completed"

        if [[ "$filename" == *tar* ]]; then
            tar -zxf "$target_dir/$filename" -C "$target_dir/$filename" 2>&1
        else
            tar -zxf "$target_dir/$filename" -C "$target_dir/$filename" --strip-components 1 2>&1
        fi
        log "File extracted: $filename"
    fi
}

# Function to build and install llvm clang-17
build_and_install_llvm_clang() {
    local llvm_url="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-17.0.6.tar.gz"

# Specify the directory where you want to extract the llvm source code
    local llvm_code_dir="$workspace"
    local llvm_source_file_dir="$source_files_dir"

# Check if the source file already exists or download it
    local llvm_tar_url="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-17.0.6.tar.gz"
    local llvm_tar_filename="$llvm_source_file_dir/llvmorg-17.0.6.tar.gz"

    if [ -f "$llvm_tar_filename" ]; then
        log "The LLVM source file $llvm_tar_filename is already downloaded."
    else
        log "Downloading LLVM source from $llvm_tar_url..."
        wget --show-progress -cqO "$llvm_tar_filename" "$llvm_tar_url"
        log "Download completed"
    fi

# Extract the source file
    echo "Extracting LLVM source to $llvm_code_dir..."
    tar -zxf "$llvm_tar_filename" -C "$llvm_code_dir" --strip-components 1
    echo "LLVM source code extracted to $llvm_code_dir"

# Check if the source directory exists or clone llvm if not
    if [ ! -d "$llvm_code_dir" ]; then
        log "LLVM source directory not found. Cloning LLVM source..."
        download_and_extract "$llvm_url" "/tmp"
        mv "/tmp/llvm-project-llvmorg-17.0.6" "$llvm_code_dir"
        log "LLVM source code moved from /tmp to $llvm_code_dir"
    fi

    mkdir -p "$workspace/build"
    cd "$workspace" || exit 1

    echo
    if build "llvm" "17.0.6"; then
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
              -DLLVM_ENABLE_ZSTD=OFF \
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
        echo
        if ! ninja "-j$(nproc --all)" -C build; then
            fail_fn "Failed to execute ninja -j$(nproc --all)"
        fi
        echo
        if ! ninja -C build install; then
            fail_fn "Failed to execute ninja -C build install"
        fi
    fi
}

# Function to show installed clang version
show_installed_clang_version() {
    local clang_versions=("clang-17" "clang++-17" "clang++")

    log "The installed clang versions are:"

    for clang_version in "${clang_versions[@]}"; do
        local clang_path="$install_dir/bin/$clang_version"

        if [ -f "$clang_path" ]; then
            echo "$clang_version:"
            "$clang_path" --version
            echo
        fi
    done
}

# Function to prompt the user to clean up the build files
cleanup_build_files() {
    local choice
    echo
    log "Do you want to remove the build files?"
    echo
    echo "[1] Yes"
    echo "[2] No"
    echo
    read -p "Your choices are (1 or 2): " choice

    case "$choice" in
        1)  rm -fr "$workspace" ;;
        2)  ;;
        *)  unset choice
            clear
            cleanup_build_files
            ;;
    esac
}

# Display exit message
display_exit_message() {
    echo
    log "The script has completed."
    log "Make sure to star this repository to show your support:"
    log "$web_repo"
    exit 0
}

# Function to check if a package needs to be built
build() {
    local pkg_name="$1"
    local pkg_version="$2"

    if [ -f "$workspace/$pkg_name.done" ]; then
        if grep -Fx "$pkg_version" "$workspace/$pkg_name.done" >/dev/null; then
            echo "$pkg_name version $pkg_version already built. Remove $workspace/$pkg_name.done lockfile to rebuild it."
            return 1
        fi
    fi
    return 0
}

# Function to mark a package as built
build_done() {
    local pkg_name="$1"
    local pkg_version="$2"
    echo "$pkg_version" > "$workspace/$pkg_name.done"
}

# Check if running as root/sudo
check_root

# Set global variables
source_files_dir="$PWD/clang-17-build-script"
workspace="$PWD/clang-17-build-script/workspace"
install_dir="/usr/local"
web_repo="https://github.com/slyfox1186/script-repo"

# Remove files from previous attempts to keep things clean
if [ -d "$workspace" ]; then
    log "Removing files from previous attempts."
    rm -fr "$workspace"
fi

# Create output directories
mkdir -p "$workspace" "$source_files_dir"

# Set the cc/cxx compilers & the compiler optimization flags
CFLAGS="-g -O3 -pipe -fno-plt -march=native"
CXXFLAGS="-g -O3 -pipe -fno-plt -march=native"
LDFLAGS="-Wl,-rpath -Wl,/usr/local/lib -Wl,--as-needed"
export CC CFLAGS CXX CXXFLAGS LDFLAGS

# Set the path variable
PATH="\
/usr/lib/ccache:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/sbin:\
/usr/local/cuda/bin:\
/usr/local/x86_64-linux-gnu/bin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin\
"
export PATH

# Set the pkg_config_path variable
PKG_CONFIG_PATH="\
/usr/share/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/pkgconfig:\
/lib/pkgconfig\
"
export PKG_CONFIG_PATH

export -f log

# Install required apt packages
install_required_packages

# Fix missing 'x265' library symlink
fix_missing_x265_lib

# Refresh the ld linker library shared library files
ldconfig

# Get the highest installed clang version to use as our compiler
find_highest_clang_version

# Build and install llvm clang-17
build_and_install_llvm_clang

# Show the newly installed clang version
show_installed_clang_version

# Prompt the user to clean up the build files
cleanup_build_files

# Display exit message
display_exit_message
