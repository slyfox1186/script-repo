#!/usr/bin/env bash
set -Eeuo pipefail

## Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-python3.sh
## Purpose: Install Python 3 from the official source releases at https://www.python.org/downloads
## Features: Source build, OpenSSL backend
## Updated: 03.20.2026
## Script version: 2.9

script_ver="2.9"
prog_name="python3"
web_repo="https://github.com/slyfox1186/script-repo"
python_version=""
archive_url=""
archive_name=""
install_dir=""
cwd=""
src_dir=""
build_dir=""
openssl_prefix=""
compiler="gcc"
lto="no"
CPU_THREADS=""
RUN_CMD_CONTEXT=""

usage() {
    cat <<'EOF'
Usage: build-python3.sh [OPTIONS]

Options:
  -v, --version <ver>  Set the Python version to install
  -l, --list           List available Python 3 versions
  -c, --clang          Use clang instead of gcc
  -t, --lto <mode>     Set LTO mode: yes, no, thin, full
  -h, --help           Display this help message
EOF
}

log() {
    printf '[INFO] %s\n' "$1"
}

warn() {
    printf '[WARN] %s\n' "$1" >&2
}

error() {
    printf '[ERROR] %s\n' "$1" >&2
}

fail() {
    error "$1"
    printf 'Please report errors at: %s/issues\n' "$web_repo" >&2
    exit 1
}

on_error() {
    local cmd exit_code line_no
    exit_code="$1"
    line_no="$2"
    cmd="$3"
    if [[ "$cmd" == '"$@"' && -n "$RUN_CMD_CONTEXT" ]]; then
        cmd="$RUN_CMD_CONTEXT"
    fi
    error "Command failed (exit ${exit_code}) at line ${line_no}: ${cmd}"
}
trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

run() {
    local rendered
    printf -v rendered '%q ' "$@"
    printf '[CMD ] %s\n' "${rendered% }" >&2
    RUN_CMD_CONTEXT="${rendered% }"
    "$@"
    RUN_CMD_CONTEXT=""
}

require_commands() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || fail "Missing required command: $cmd"
    done
}

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

fetch_url() {
    local url
    url="$1"
    run wget -qO- --tries=3 --waitretry=2 "$url"
}

remote_file_exists() {
    local url
    url="$1"
    wget -q --spider --tries=3 --waitretry=2 "$url"
}

download_file() {
    local url destination
    url="$1"
    destination="$2"
    run wget -O "$destination" --tries=3 --waitretry=2 "$url"
}

ensure_sudo_access() {
    log "Validating sudo access..."
    run sudo -v
}

resolve_build_root() {
    printf '%s\n' "$(mktemp -d "${TMPDIR:-/tmp}/python3-build-script.XXXXXX")"
}

validate_lto_mode() {
    case "$lto" in
        yes|no|thin|full) ;;
        *)
            fail "Unsupported LTO mode: $lto. Use one of: yes, no, thin, full."
            ;;
    esac

    if [[ "$lto" == "thin" && "$compiler" != "clang" ]]; then
        fail "LTO mode 'thin' can only be used with clang."
    fi
}

list_versions() {
    fetch_url "https://www.python.org/ftp/python/" \
        | grep -oP 'href="\K[0-9]+\.[0-9]+\.[0-9]+(?=/")' \
        | sort -uV
}

detect_latest_python_version() {
    local archive_url_candidate version

    while IFS= read -r version; do
        [[ -n "$version" ]] || continue
        archive_url_candidate="https://www.python.org/ftp/python/${version}/Python-${version}.tar.xz"
        if remote_file_exists "$archive_url_candidate"; then
            printf '%s\n' "$version"
            return
        fi
    done < <(
        fetch_url "https://www.python.org/ftp/python/" \
            | grep -oP 'href="\K[0-9]+\.[0-9]+\.[0-9]+(?=/")' \
            | sort -uVr
    )

    fail "Failed to detect a downloadable Python 3 release from python.org."
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version)
                [[ $# -ge 2 && -n "$2" ]] || fail "The --version option requires a value."
                python_version="$2"
                shift 2
                ;;
            -l|--list)
                list_versions
                exit 0
                ;;
            -c|--clang)
                compiler="clang"
                shift
                ;;
            -t|--lto)
                [[ $# -ge 2 && -n "$2" ]] || fail "The --lto option requires a value."
                lto="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
}

resolve_version_metadata() {
    if [[ -z "$python_version" ]]; then
        python_version="$(detect_latest_python_version)"
    fi

    archive_name="Python-$python_version"
    archive_url="https://www.python.org/ftp/python/$python_version/${archive_name}.tar.xz"
    install_dir="/usr/local/programs/${prog_name}-${python_version}"
}

resolve_python_mm() {
    printf '%s\n' "${python_version%.*}"
}

resolve_openssl_prefix() {
    local openssl_bin prefix
    openssl_bin="$(readlink -f "$(command -v openssl)")"
    prefix="$(dirname "$(dirname "$openssl_bin")")"

    if [[ -d "$prefix/include/openssl" ]] && { [[ -d "$prefix/lib" ]] || [[ -d "$prefix/lib64" ]]; }; then
        printf '%s\n' "$prefix"
        return
    fi

    if [[ -d /usr/include/openssl ]]; then
        printf '%s\n' "/usr"
        return
    fi

    fail "Unable to determine a usable OpenSSL prefix."
}

install_required_packages() {
    local -a apt_cmd install_cmd missing_packages pkgs
    local pkg

    apt_cmd=(sudo env DEBIAN_FRONTEND=noninteractive apt)
    pkgs=(
        build-essential
        ccache
        clang
        libbz2-dev
        libdb5.3-dev
        libexpat1-dev
        libffi-dev
        libgdbm-compat-dev
        libgdbm-dev
        liblzma-dev
        libncursesw5-dev
        libnsl-dev
        libreadline-dev
        libsqlite3-dev
        libssl-dev
        libtirpc-dev
        pkg-config
        tk-dev
        uuid-dev
        wget
        xz-utils
        zlib1g-dev
    )

    missing_packages=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ "${#missing_packages[@]}" -eq 0 ]]; then
        log "All required packages are already installed."
        return
    fi

    log "Installing missing packages: ${missing_packages[*]}"
    install_cmd=("${apt_cmd[@]}" install -y "${missing_packages[@]}")
    if ! run "${install_cmd[@]}"; then
        warn "Direct apt install failed; refreshing package metadata and retrying."
        run "${apt_cmd[@]}" update
        run "${install_cmd[@]}"
    fi
}

prepare_environment() {
    log "Python3 Build Script - v${script_ver}"
    CPU_THREADS="$(detect_cpu_threads)"
    cwd="$(resolve_build_root)"
    src_dir="${cwd}/${archive_name}"
    build_dir="${src_dir}/build"

    mkdir -p "$cwd"

    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/local/cuda/lib64/pkgconfig:/usr/local/cuda/lib/pkgconfig:/opt/cuda/lib64/pkgconfig:/opt/cuda/lib/pkgconfig"
    PKG_CONFIG_PATH+=":/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig"
    export PATH PKG_CONFIG_PATH
}

set_compiler_flags() {
    if [[ "$compiler" == "clang" ]]; then
        CC="clang"
        CXX="clang++"
        if command -v llvm-ar >/dev/null 2>&1; then
            export AR="llvm-ar"
        fi
        if command -v llvm-ranlib >/dev/null 2>&1; then
            export RANLIB="llvm-ranlib"
        fi
    else
        CC="gcc"
        CXX="g++"
    fi

    CFLAGS="-O3 -fPIE -pipe -mtune=native -fstack-protector-strong"
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security"
    LDFLAGS="-Wl,-O1 -Wl,--as-needed -Wl,-z,relro -Wl,-z,now -Wl,--enable-new-dtags -Wl,-rpath=${install_dir}/lib"
    export CC CFLAGS CXX CXXFLAGS CPPFLAGS LDFLAGS
}

download_and_extract_python() {
    local tar_file
    tar_file="${cwd}/${archive_name}.tar.xz"

    if [[ ! -f "$tar_file" ]]; then
        log "Downloading Python ${python_version}..."
        download_file "$archive_url" "$tar_file"
    fi

    rm -rf "$src_dir"
    mkdir -p "$src_dir"
    run tar -xf "$tar_file" -C "$src_dir" --strip-components=1
    mkdir -p "$build_dir"
}

ld_linker_path() {
    local python_mm
    python_mm="$(resolve_python_mm)"
    echo "${install_dir}/lib/python${python_mm}/lib-dynload" | sudo tee "/etc/ld.so.conf.d/custom_${prog_name}.conf" >/dev/null
    run sudo ldconfig
}

create_soft_links() {
    local file link_name pc_file

    if [[ -d "${install_dir}/bin" ]]; then
        for file in "${install_dir}/bin/"*; do
            [[ -e "$file" ]] || continue
            link_name="/usr/local/bin/${file##*/}"
            run sudo ln -sfn "$file" "$link_name"
        done
    fi

    if [[ -d "${install_dir}/lib/pkgconfig" ]]; then
        run sudo mkdir -p /usr/local/lib/pkgconfig
        for pc_file in "${install_dir}/lib/pkgconfig/"*.pc; do
            [[ -e "$pc_file" ]] || continue
            run sudo ln -sfn "$pc_file" "/usr/local/lib/pkgconfig/${pc_file##*/}"
        done
    fi

    if [[ -d "${install_dir}/include" ]]; then
        local include_dir
        include_dir="${install_dir}/include/python$(resolve_python_mm)"
        if [[ -d "$include_dir" ]]; then
            run sudo ln -sfn "$include_dir" "/usr/local/include/$(basename "$include_dir")"
        fi
    fi
}

create_user_site() {
    local python_mm
    python_mm="$(resolve_python_mm)"
    mkdir -p "$HOME/.local/lib/python${python_mm}/site-packages"
}

build_python() {
    local -a configure_args

    log "Build Python3 - v${python_version}"

    cd "$build_dir" || fail "Failed to change directory to $build_dir"

    configure_args=(
        "../configure"
        "--prefix=${install_dir}"
        "--disable-ipv6"
        "--disable-test-modules"
        "--enable-optimizations"
        "--with-ensurepip=install"
        "--with-lto=${lto}"
        "--with-openssl-rpath=auto"
        "--with-openssl=${openssl_prefix}"
        "--with-pkg-config=yes"
        "--with-ssl-default-suites=openssl"
        "--with-valgrind"
    )

    run "${configure_args[@]}"
    run make -j"$CPU_THREADS"
    run sudo make install
}

show_ver_fn() {
    local python_bin python_mm
    python_mm="$(resolve_python_mm)"
    python_bin="${install_dir}/bin/python${python_mm}"

    if [[ -x "$python_bin" ]]; then
        printf '\nThe newly installed version is: %s\n' "$("$python_bin" --version 2>&1)"
    else
        warn "Unable to find installed interpreter at ${python_bin}"
    fi
}

cleanup() {
    [[ -n "$cwd" && -d "$cwd" ]] || return

    if rm -rf "$cwd" 2>/dev/null; then
        return
    fi

    case "$cwd" in
        "${TMPDIR:-/tmp}"/python3-build-script.*)
            warn "Build workspace contains root-owned artifacts; removing it with sudo."
            run sudo rm -rf "$cwd"
            ;;
        *)
            fail "Refusing to remove unexpected cleanup path: $cwd"
            ;;
    esac
}

exit_function() {
    printf '\n%s\n%s\n\n' "Make sure to star this repository to show your support!" "$web_repo"
}

main() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        fail "You must run this script without root or sudo."
    fi

    parse_arguments "$@"
    validate_lto_mode
    resolve_version_metadata

    require_commands apt dpkg-query grep sed sort sudo tar wget xz
    ensure_sudo_access
    install_required_packages
    require_commands "$([[ "$compiler" == "clang" ]] && printf '%s' clang || printf '%s' gcc)" openssl perl pkg-config

    openssl_prefix="$(resolve_openssl_prefix)"

    prepare_environment
    set_compiler_flags
    download_and_extract_python
    build_python

    if [[ -d "${install_dir}/lib" ]]; then
        ld_linker_path
    fi

    create_soft_links
    create_user_site
    show_ver_fn
    cleanup
    exit_function
}

main "$@"
