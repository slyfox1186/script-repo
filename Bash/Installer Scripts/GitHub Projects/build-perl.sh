#!/usr/bin/env bash
set -Eeuo pipefail

## GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/Installer%20Scripts/GitHub%20Projects/build-perl.sh
## Purpose: Install the latest even Perl version from source code
## Updated: 03.20.2026
## Script version: 2.0

base_url="https://github.com/Perl/perl5"
install_dir="/usr/local/programs/perl"
bin_dir="/usr/local/bin"
build_root=""
src_dir=""
perl_version=""
archive_url=""
log_file=""
cpu_threads=""
RUN_CMD_CONTEXT=""

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
    printf 'Please report errors at: %s/issues\n' "https://github.com/slyfox1186/script-repo" >&2
    exit 1
}

on_error() {
    local exit_code line_no cmd
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
    printf '%s\n' "$(mktemp -d "${TMPDIR:-/tmp}/perl-build-script.XXXXXX")"
}

install_required_packages() {
    local -a apt_cmd install_cmd missing_packages packages
    local pkg

    apt_cmd=(sudo env DEBIAN_FRONTEND=noninteractive apt)
    packages=(
        build-essential
        ca-certificates
        git
        make
        tar
        wget
    )

    missing_packages=()
    for pkg in "${packages[@]}"; do
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

get_latest_even_version() {
    local latest_version
    latest_version="$(
        run git ls-remote --tags --refs "${base_url}.git" \
            | sed 's#.*refs/tags/##' \
            | grep -E '^v[0-9]+\.[0-9]*[02468]\.[0-9]+$' \
            | sort -uV \
            | tail -n1 \
            || true
    )"

    [[ -n "$latest_version" ]] || fail "Unable to determine the latest even Perl release."
    printf '%s\n' "$latest_version"
}

resolve_version_metadata() {
    perl_version="$(get_latest_even_version)"
    archive_url="${base_url}/archive/refs/tags/${perl_version}.tar.gz"
}

prepare_environment() {
    log "Perl Build Script - v2.0"
    cpu_threads="$(detect_cpu_threads)"
    build_root="$(resolve_build_root)"
    log_file="${build_root}/perl_install.log"
    : >"$log_file"
    log "Build workspace: ${build_root}"
}

download_and_extract() {
    local tarball
    tarball="${build_root}/${perl_version}.tar.gz"

    log "Downloading Perl ${perl_version}..."
    download_file "$archive_url" "$tarball"

    log "Verifying archive integrity..."
    run tar -tzf "$tarball" >/dev/null

    log "Extracting Perl ${perl_version}..."
    run tar -xzf "$tarball" -C "$build_root"

    src_dir="$(find "$build_root" -mindepth 1 -maxdepth 1 -type d -name 'perl5-*' | head -n1)"
    [[ -n "$src_dir" && -d "$src_dir" ]] || fail "Unable to locate extracted Perl source directory."
}

build_and_install() {
    log "Configuring Perl ${perl_version}..."
    cd "$src_dir" || fail "Failed to change directory to ${src_dir}"

    run ./Configure -des -Dprefix="$install_dir"

    log "Building Perl ${perl_version}..."
    run make -j"$cpu_threads"

    log "Installing Perl ${perl_version}..."
    run sudo make install
}

create_symlink() {
    local perl_bin
    perl_bin="${install_dir}/bin/perl"

    [[ -x "$perl_bin" ]] || fail "Perl binary not found at ${perl_bin}."
    run sudo ln -sfn "$perl_bin" "${bin_dir}/perl"
}

show_version() {
    local perl_bin installed_version
    perl_bin="${install_dir}/bin/perl"
    [[ -x "$perl_bin" ]] || return

    installed_version="$("$perl_bin" -e 'print $^V')"
    printf '\nThe newly installed version is: Perl %s\n' "${installed_version#v}"
}

cleanup() {
    [[ -n "$build_root" && -d "$build_root" ]] || return

    if rm -rf "$build_root" 2>/dev/null; then
        return
    fi

    case "$build_root" in
        "${TMPDIR:-/tmp}"/perl-build-script.*)
            warn "Build workspace contains root-owned artifacts; removing it with sudo."
            run sudo rm -rf "$build_root"
            ;;
        *)
            fail "Refusing to remove unexpected cleanup path: $build_root"
            ;;
    esac
}

main() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        fail "You must run this script without root or sudo."
    fi

    require_commands apt dpkg-query find git grep head make sed sort sudo tar wget
    ensure_sudo_access
    install_required_packages
    require_commands gcc make tar wget

    resolve_version_metadata
    prepare_environment
    download_and_extract
    build_and_install
    create_symlink
    show_version
    cleanup
}

main "$@"
