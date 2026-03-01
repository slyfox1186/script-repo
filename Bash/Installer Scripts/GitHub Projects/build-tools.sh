#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose: Install or update CMake, Ninja, Meson, and Go.
# Designed for Debian/Ubuntu systems with sudo access.

SCRIPT_VERSION="4.0.2"
INSTALL_ROOT=/usr/local/programs
BIN_DIR=/usr/local/bin
CWD="$(pwd)"
WORK_DIR="${CWD}/build-tools-script"
SRC_DIR="${WORK_DIR}/src"
BUILD_DIR="${WORK_DIR}/build"

FORCE_REINSTALL=false
DEBUG=false
PROMPT_CLEANUP=true
SKIP_DEP_INSTALL=false

CONDA_CMD=""
CONDA_PYTHON=""
CONDA_MESON_BIN=""

detect_cpu_threads() {
    local threads
    threads=""

    # nproc (without --all) respects container/cgroup CPU limits.
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

# Allow explicit override via environment variable.
CPU_THREADS="${CPU_THREADS:-$(detect_cpu_threads)}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat <<'EOF'
Usage: build-tools.sh [options]

Options:
  --latest       Reinstall latest versions even when already installed
  --debug        Enable shell trace output
  --no-cleanup   Do not prompt to remove build workspace
  --skip-deps    Skip apt dependency installation
  -h, --help     Show this help message
EOF
}

log() {
    printf '%b[INFO]%b %s\n' "$GREEN" "$NC" "$*"
}

warn() {
    printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$*"
}

error() {
    printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$*" >&2
}

fail() {
    error "$*"
    exit 1
}

on_error() {
    local cmd exit_code line_no
    exit_code="$1"
    line_no="$2"
    cmd="$3"
    error "Command failed (exit ${exit_code}) at line ${line_no}: ${cmd}"
}
trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --latest)
                FORCE_REINSTALL=true
                ;;
            --debug)
                DEBUG=true
                ;;
            --no-cleanup)
                PROMPT_CLEANUP=false
                ;;
            --skip-deps)
                SKIP_DEP_INSTALL=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fail "Unknown option: $1 (run with --help)"
                ;;
        esac
        shift
    done
}

run() {
    log "Running: $*"
    "$@"
}

require_commands() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || fail "Missing required command: $cmd"
    done
}

setup_conda_context() {
    local conda_base

    CONDA_CMD="${CONDA_EXE:-}"
    if [[ -z "$CONDA_CMD" || ! -x "$CONDA_CMD" ]]; then
        CONDA_CMD="$(command -v conda 2>/dev/null || true)"
    fi

    if [[ -z "$CONDA_CMD" ]]; then
        return
    fi

    if [[ -n "${CONDA_PREFIX:-}" && -x "${CONDA_PREFIX}/bin/python" ]]; then
        CONDA_PYTHON="${CONDA_PREFIX}/bin/python"
        CONDA_MESON_BIN="${CONDA_PREFIX}/bin/meson"
        log "Conda detected. Using active environment at ${CONDA_PREFIX} for Meson."
        return
    fi

    conda_base="$("$CONDA_CMD" info --base 2>/dev/null || true)"
    if [[ -n "$conda_base" && -x "${conda_base}/bin/python" ]]; then
        CONDA_PYTHON="${conda_base}/bin/python"
        CONDA_MESON_BIN="${conda_base}/bin/meson"
        log "Conda detected. Using base environment at ${conda_base} for Meson."
        return
    fi

    warn "Conda detected but no usable Python was found. Falling back to system Python for Meson."
}

set_compiler_flags() {
    CC="${CC:-gcc}"
    CXX="${CXX:-g++}"
    CFLAGS="${CFLAGS:--O3 -pipe}"
    CXXFLAGS="${CXXFLAGS:-$CFLAGS}"
    CPPFLAGS="${CPPFLAGS:-}"
    LDFLAGS="${LDFLAGS:-}"
    export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}

ensure_sudo_access() {
    log "Validating sudo access..."
    run sudo -v
}

install_dependencies_apt() {
    if [[ "$SKIP_DEP_INSTALL" == true ]]; then
        warn "Skipping dependency installation (--skip-deps)."
        return
    fi

    local missing pkg pkgs

    pkgs=(
        autoconf
        automake
        build-essential
        ccache
        curl
        git
        jq
        libssl-dev
        libtool
        m4
        pkg-config
        python3
        python3-pip
        re2c
        tar
    )

    missing=()

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            missing+=("$pkg")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        log "Required apt packages are already installed."
        return
    fi

    log "Installing apt packages: ${missing[*]}"
    run sudo apt update
    run sudo apt install -y "${missing[@]}"
}

download_file() {
    local  out_files url
    url="$1"
    output_file="$2"

    mkdir -p "$(dirname "$output_file")"
    run curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused -o "$output_file" "$url"
}

extract_tarball() {
    local destination strip_components tarball
    tarball="$1"
    destination="$2"
    strip_components="${3:-1}"

    [[ -d "$destination" ]] && rm -rf "$destination"
    mkdir -p "$destination"
    run tar -xf "$tarball" -C "$destination" --strip-components="$strip_components"
}

github_latest_tag() {
    local  repo response tag
    repo="$1"

    response="$(curl -fsSL --retry 3 "https://api.github.com/repos/${repo}/releases/latest" || true)"
    if [[ -n "$response" ]]; then
        tag="$(printf '%s' "$response" | jq -r '.tag_name // empty' 2>/dev/null || true)"
    fi

    if [[ -z "$tag" ]]; then
        response="$(curl -fsSL --retry 3 "https://api.github.com/repos/${repo}/tags?per_page=1" || true)"
        tag="$(printf '%s' "$response" | jq -r '.[0].name // empty' 2>/dev/null || true)"
    fi

    [[ -n "$tag" ]] || fail "Unable to determine latest tag for ${repo}"
    printf '%s\n' "$tag"
}

latest_go_version() {
    local raw
    raw="$(curl -fsSL --retry 3 "https://go.dev/VERSION?m=text" | sed -n '1p' || true)"
    [[ "$raw" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "Unable to determine latest Go version"
    printf '%s\n' "${raw#go}"
}

get_installed_cmake_version() {
    local cmake_bin="${BIN_DIR}/cmake"
    if [[ -x "$cmake_bin" ]]; then
        "$cmake_bin" --version | awk 'NR==1 { print $3 }'
        return
    fi
    command -v cmake >/dev/null 2>&1 || return 1
    cmake --version | awk 'NR==1 { print $3 }'
}

get_installed_ninja_version() {
    local ninja_bin="${BIN_DIR}/ninja"
    if [[ -x "$ninja_bin" ]]; then
        "$ninja_bin" --version
        return
    fi
    command -v ninja >/dev/null 2>&1 || return 1
    ninja --version
}

get_installed_meson_version() {
    # Prefer managed/system installs over conda/venv wrappers in PATH.
    local meson_bin
    for meson_bin in "${CONDA_MESON_BIN:-}" "${BIN_DIR}/meson" "/usr/local/local/bin/meson"; do
        [[ -n "$meson_bin" ]] || continue
        if [[ -x "$meson_bin" ]] && "$meson_bin" --version >/dev/null 2>&1; then
            "$meson_bin" --version
            return
        fi
    done

    meson_bin="$(command -v meson 2>/dev/null || true)"
    [[ -n "$meson_bin" ]] || return 1
    "$meson_bin" --version 2>/dev/null || return 1
}

get_installed_go_version() {
    local go_bin goroot_resolved
    go_bin="${BIN_DIR}/go"
    if [[ ! -x "$go_bin" ]]; then
        go_bin="$(command -v go 2>/dev/null)" || return 1
    fi

    # Resolve the real GOROOT from the binary to avoid stale env GOROOT
    if [[ -L "$go_bin" ]]; then
        go_bin="$(readlink -f "$go_bin")"
    fi
    goroot_resolved="${go_bin%/bin/go}"

    GOROOT="$goroot_resolved" "$go_bin" version 2>/dev/null | awk '{print $3}' | sed 's/^go//'
}

cleanup_old_versions() {
    local current_prefix name old_dir
    name="$1"
    current_prefix="$2"

    for old_dir in "${INSTALL_ROOT}/${name}"-*; do
        [[ -d "$old_dir" ]] || continue
        [[ "$old_dir" == "$current_prefix" ]] && continue
        log "Removing old ${name} install: ${old_dir}"
        sudo rm -rf "$old_dir"
    done
}

should_install() {
    local current latest name
    name="$1"
    current="$2"
    latest="$3"

    if [[ "$FORCE_REINSTALL" == true ]]; then
        log "$name will be reinstalled (--latest enabled)."
        return 0
    fi

    if [[ -z "$current" ]]; then
        log "$name is not currently installed."
        return 0
    fi

    if [[ "$current" != "$latest" ]]; then
        log "$name update required: installed=${current}, latest=${latest}"
        return 0
    fi

    log "$name ${latest} is already up-to-date."
    return 1
}

install_cmake() {
    local archive prefix src version
    version="$1"
    archive="${WORK_DIR}/cmake-${version}.tar.gz"
    src="${SRC_DIR}/cmake-${version}"
    prefix="${INSTALL_ROOT}/cmake-${version}"

    log "Installing CMake ${version}"
    download_file "https://github.com/Kitware/CMake/archive/refs/tags/v${version}.tar.gz" "$archive"
    extract_tarball "$archive" "$src" 1

    cd "$src" >/dev/null
    run ./bootstrap --prefix="$prefix" --parallel="$CPU_THREADS" --enable-ccache -- -GNinja
    run ninja -j"$CPU_THREADS"
    run sudo ninja install
    cd - >/dev/null

    run sudo ln -sfn "${prefix}/bin/cmake" "${BIN_DIR}/cmake"
    [[ -x "${prefix}/bin/ctest" ]] && run sudo ln -sfn "${prefix}/bin/ctest" "${BIN_DIR}/ctest"
    [[ -x "${prefix}/bin/cpack" ]] && run sudo ln -sfn "${prefix}/bin/cpack" "${BIN_DIR}/cpack"
    cleanup_old_versions "cmake" "$prefix"
}

install_ninja() {
    local archive prefix src version
    version="$1"
    archive="${WORK_DIR}/ninja-${version}.tar.gz"
    src="${SRC_DIR}/ninja-${version}"
    prefix="${INSTALL_ROOT}/ninja-${version}"

    log "Installing Ninja ${version}"
    download_file "https://github.com/ninja-build/ninja/archive/refs/tags/v${version}.tar.gz" "$archive"
    extract_tarball "$archive" "$src" 1

    # Bootstrap with Python — no cmake or make needed
    cd "$src" >/dev/null
    run python3 configure.py --bootstrap
    cd - >/dev/null

    run sudo mkdir -p "${prefix}/bin"
    run sudo install -m 755 "$src/ninja" "${prefix}/bin/ninja"
    run sudo ln -sfn "${prefix}/bin/ninja" "${BIN_DIR}/ninja"
    cleanup_old_versions "ninja" "$prefix"
}

install_meson() {
    local py_minor sys_python version
    version="$1"

    # Prefer Conda when available.
    if [[ -n "${CONDA_PYTHON:-}" ]]; then
        log "Installing Meson ${version} with Conda Python (${CONDA_PYTHON})"
        run "$CONDA_PYTHON" -m pip install --verbose --upgrade "meson==${version}"

        if [[ -n "${CONDA_MESON_BIN:-}" && -x "${CONDA_MESON_BIN}" ]] \
            && "${CONDA_MESON_BIN}" --version >/dev/null 2>&1; then
            return
        fi

        fail "Meson install succeeded via Conda pip, but no runnable meson executable was found"
    fi

    # Fallback: use system Python explicitly.
    if [[ ! -x /usr/bin/python3 ]]; then
        fail "System Python not found at /usr/bin/python3"
    fi
    sys_python=/usr/bin/python3

    log "Installing Meson ${version} with system Python (${sys_python})"
    py_minor="$("$sys_python" -c 'import sys; print(sys.version_info.minor)')"

    # If /usr/local/bin/meson is a stale symlink/script, pip may not replace it cleanly.
    run sudo rm -f "${BIN_DIR}/meson"
    if [[ "$py_minor" -ge 12 ]]; then
        run sudo "$sys_python" -m pip install --verbose --upgrade --break-system-packages "meson==${version}"
    else
        run sudo "$sys_python" -m pip install --verbose --upgrade "meson==${version}"
    fi

    if ! "${BIN_DIR}/meson" --version >/dev/null 2>&1; then
        fail "Meson install did not produce a runnable ${BIN_DIR}/meson (system Python path)"
    fi
}

update_bashrc_go_path() {
    local version="$1"
    local bashrc="${HOME}/.bashrc"
    local go_root="${INSTALL_ROOT}/golang-${version}"

    touch "$bashrc"
    sed -i '/# >>> build-tools golang >>>/,/# <<< build-tools golang <<</d' "$bashrc"

    cat >>"$bashrc" <<EOF

# >>> build-tools golang >>>
export GOROOT="${go_root}"
export PATH="\$PATH:\$GOROOT/bin"
# <<< build-tools golang <<<
EOF

    export GOROOT="$go_root"
    export PATH="${PATH}:${GOROOT}/bin"
}

detect_go_arch() {
    local machine
    machine="$(uname -m)"
    case "$machine" in
        x86_64)  echo "amd64"  ;;
        aarch64) echo "arm64"  ;;
        armv6l)  echo "armv6l" ;;
        *)       fail "Unsupported architecture for Go: ${machine}" ;;
    esac
}

install_go() {
    local arch archive prefix staging version
    version="$1"
    arch="$(detect_go_arch)"
    archive="${WORK_DIR}/go-${version}.linux-${arch}.tar.gz"
    prefix="${INSTALL_ROOT}/golang-${version}"
    staging="${WORK_DIR}/golang-${version}-staging"

    log "Installing Go ${version} (linux/${arch})"
    download_file "https://go.dev/dl/go${version}.linux-${arch}.tar.gz" "$archive"

    # Atomic: extract to staging first, then swap into place
    [[ -d "$staging" ]] && rm -rf "$staging"
    mkdir -p "$staging" &>/dev/null
    run tar -xzf "$archive" -C "$staging" --strip-components=1

    # Verify the staged binary works before replacing the live install
    if ! "$staging/bin/go" version >/dev/null 2>&1; then
        rm -rf "$staging"
        fail "Staged Go ${version} binary failed verification"
    fi

    run sudo rm -rf "$prefix"
    run sudo mv "$staging" "$prefix"
    run sudo ln -sfn "${prefix}/bin/go" "${BIN_DIR}/go"
    run sudo ln -sfn "${prefix}/bin/gofmt" "${BIN_DIR}/gofmt"
    cleanup_old_versions "golang" "$prefix"
    update_bashrc_go_path "$version"
}

print_versions() {
    local cmake_version ninja_version meson_version go_version

    cmake_version="$(get_installed_cmake_version || true)"
    ninja_version="$(get_installed_ninja_version || true)"
    meson_version="$(get_installed_meson_version || true)"
    go_version="$(get_installed_go_version || true)"

    log "Installed versions:"
    printf '  CMake:  %s\n' "${cmake_version:-not installed}"
    printf '  Ninja:  %s\n' "${ninja_version:-not installed}"
    printf '  Meson:  %s\n' "${meson_version:-not installed}"
    printf '  Go:     %s\n' "${go_version:-not installed}"
}

cleanup_workspace() {
    local answer

    if [[ "$PROMPT_CLEANUP" != true ]]; then
        return
    fi

    while true; do
        read -r -p "Remove build workspace (${WORK_DIR})? [Y/n]: " answer || break
        case "${answer,,}" in
            ""|y|yes)
                rm -rf "$WORK_DIR"
                log "Removed ${WORK_DIR}"
                break
                ;;
            n|no)
                log "Keeping build workspace at ${WORK_DIR}"
                break
                ;;
            *)
                warn "Please answer yes or no."
                ;;
        esac
    done
}

main() {
    local current_cmake current_ninja current_meson current_go
    local latest_cmake latest_ninja latest_meson latest_go

    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        fail "Run this script as a regular user. It uses sudo only when required."
    fi

    # Sanitize stale GOROOT before any go commands run
    if [[ -n "${GOROOT:-}" && ! -d "$GOROOT" ]]; then
        warn "Stale GOROOT=${GOROOT} (directory missing). Unsetting."
        unset GOROOT
    fi

    mkdir -p "$WORK_DIR" "$SRC_DIR" "$BUILD_DIR"
    set_compiler_flags
    export PATH="${BIN_DIR}:${PATH}"
    setup_conda_context

    require_commands awk curl grep jq python3 sed sort sudo tar
    ensure_sudo_access

    if command -v apt-get >/dev/null 2>&1; then
        install_dependencies_apt
    else
        warn "apt-get not found; skipping dependency installation."
    fi

    current_cmake="$(get_installed_cmake_version || true)"
    current_ninja="$(get_installed_ninja_version || true)"
    current_meson="$(get_installed_meson_version || true)"
    current_go="$(get_installed_go_version || true)"

    log "Current versions:"
    printf '  CMake:  %s\n' "${current_cmake:-not installed}"
    printf '  Ninja:  %s\n' "${current_ninja:-not installed}"
    printf '  Meson:  %s\n' "${current_meson:-not installed}"
    printf '  Go:     %s\n' "${current_go:-not installed}"

    latest_cmake="$(github_latest_tag "Kitware/CMake")"
    latest_cmake="${latest_cmake#v}"
    latest_ninja="$(github_latest_tag "ninja-build/ninja")"
    latest_ninja="${latest_ninja#v}"
    latest_meson="$(github_latest_tag "mesonbuild/meson")"
    latest_meson="${latest_meson#v}"
    latest_go="$(latest_go_version)"

    log "Latest versions:"
    printf '  CMake:  %s\n' "$latest_cmake"
    printf '  Ninja:  %s\n' "$latest_ninja"
    printf '  Meson:  %s\n' "$latest_meson"
    printf '  Go:     %s\n' "$latest_go"

    # Ninja first — CMake's bootstrap uses it as the generator
    if should_install "Ninja" "${current_ninja:-}" "$latest_ninja"; then
        install_ninja "$latest_ninja"
    fi

    if should_install "CMake" "${current_cmake:-}" "$latest_cmake"; then
        install_cmake "$latest_cmake"
    fi

    if should_install "Meson" "${current_meson:-}" "$latest_meson"; then
        install_meson "$latest_meson"
    fi

    if should_install "Go" "${current_go:-}" "$latest_go"; then
        install_go "$latest_go"
    fi

    run sudo ldconfig
    print_versions
    cleanup_workspace
    log "Build-tools script completed successfully (v${SCRIPT_VERSION})."
}

parse_args "$@"
if [[ "$DEBUG" == true ]]; then
    set -x
fi

main
