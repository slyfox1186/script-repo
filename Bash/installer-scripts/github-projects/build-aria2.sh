#!/usr/bin/env bash

##  Github Script: https://github.com/slyfox1186/script-repo/blob/main/Bash/installer-scripts/github-projects/build-aria2.sh
##  Purpose: Build aria2 from source code with hardening options
##  Updated: 11.07.26
##  Script version: 2.9

script_ver="2.9"

echo "aria2 build script - version $script_ver"
echo "==============================================="
echo

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

readonly INSTALL_PREFIX="/usr/local"
readonly CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
readonly USER_AGENT="Mozilla/5.0 (X11; Linux x86_64; rv:159.0) Gecko/20100101 Firefox/159.0"

ARIA2_STATIC="no"
CFLAGS_OPTION="-march=native"
temp_dir=""

log() { echo -e "${GREEN}[LOG]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $*" >&2; }
fail() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

display_help() {
    cat <<EOF
Usage: $0 [OPTION]...
Build aria2 from source code with hardening options.

Options:
  -h, --help          Display this help message and exit
  -d, --debug         Enable debug mode for more detailed output
  -g, --generic       Set CFLAGS to -O2 -pipe -mtune=generic
  -n, --native        Set CFLAGS to -O2 -pipe -march=native (default)
  -s, --static        Link aria2 statically (ARIA2_STATIC=yes). A static binary
                      is not position independent, so it gets no ASLR for its
                      own code.

Examples:
  $0                     # Build aria2 from source
  $0 --debug --generic   # Build aria2 with CFLAGS set to -O2 -pipe -mtune=generic
  $0 --static            # Build a statically linked aria2
  $0 -d -g -s            # Build aria2 with debug mode, generic tuning, and static linking
EOF
    exit "${1:-0}"
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            -d|--debug)   set -x ;;
            -s|--static)  ARIA2_STATIC="yes" ;;
            -g|--generic) CFLAGS_OPTION="-mtune=generic" ;;
            -n|--native)  CFLAGS_OPTION="-march=native" ;;
            -h|--help)    display_help 0 ;;
            *)
                echo "Unknown option: $1" >&2
                display_help 1 >&2
                ;;
        esac
        shift
    done
}

# An active conda env puts its own tclsh, xml2-config and libraries first on
# PATH; they must not leak into a system build.
remove_conda_from_path() {
    local conda_root entry new_path=""
    local -a entries
    [[ -n "${CONDA_EXE:-}" ]] || return 0
    conda_root="${CONDA_EXE%/bin/conda}"
    IFS=: read -ra entries <<< "$PATH"
    for entry in "${entries[@]}"; do
        [[ "$entry" == "$conda_root" || "$entry" == "$conda_root"/* ]] && continue
        new_path+="${new_path:+:}${entry}"
    done
    PATH="$new_path"
    export PATH
    log "Removed conda directories under ${conda_root} from PATH for this build."
}

setup_tools() {
    remove_conda_from_path
    if [[ -d /usr/lib/ccache && ":$PATH:" != *":/usr/lib/ccache:"* ]]; then
        PATH="/usr/lib/ccache:$PATH"
        export PATH
    fi
    PKG_CONFIG=$(type -P pkg-config) || fail "pkg-config not found in PATH."
    export PKG_CONFIG
    unset PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR
}

# Debian/Ubuntu gcc already builds PIE executables by default, and libtool and
# sqlite add -fPIC on their own when they build shared objects. Never pass
# -fPIC and -fPIE together: the last one wins, and PIE objects cannot be
# linked into a shared library.
set_compiler_options() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe $CFLAGS_OPTION -DNDEBUG -fstack-protector-strong -fstack-clash-protection -Wno-unused-parameter"
    if [[ "$(uname -m)" == "x86_64" ]]; then
        CFLAGS+=" -fcf-protection=full"
    fi
    CXXFLAGS="$CFLAGS"
    CPPFLAGS="-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3"
    LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now,-z,noexecstack -Wl,-rpath,${INSTALL_PREFIX}/lib"
    export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}

print_env() {
    echo
    log "Environment variables:"
    log "CC=$CC"
    log "CXX=$CXX"
    log "CFLAGS=$CFLAGS"
    log "CXXFLAGS=$CXXFLAGS"
    log "CPPFLAGS=$CPPFLAGS"
    log "LDFLAGS=$LDFLAGS"
    log "PKG_CONFIG=$PKG_CONFIG"
    log "ARIA2_STATIC=$ARIA2_STATIC"
    echo
}

install_packages() {
    local pkg
    local -a pkgs missing_pkgs=()
    pkgs=(
        build-essential ca-certificates ccache curl libgoogle-perftools-dev
        libssl-dev libxml2-dev pkg-config xz-utils zlib1g-dev
    )
    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${db:Status-Status}\n' "$pkg" 2>/dev/null | grep -qx installed; then
            missing_pkgs+=("$pkg")
        fi
    done
    if (( ${#missing_pkgs[@]} == 0 )); then
        log "All required packages are already installed."
        return 0
    fi
    log "Installing missing packages: ${missing_pkgs[*]}"
    sudo apt-get update || fail "apt-get update failed."
    sudo apt-get install -y "${missing_pkgs[@]}" || fail "Failed to install: ${missing_pkgs[*]}"
}

check_ca_bundle() {
    [[ -s "$CA_BUNDLE" ]] || fail "CA bundle ${CA_BUNDLE} is missing. Run: sudo update-ca-certificates"
}

# Prints the version behind https://github.com/REPO/releases/latest, whose tag
# must be TAG_PREFIX followed by X.Y.Z.
latest_github_release_version() {
    local repo="$1" tag_prefix="$2" url
    if ! url=$(curl -fsSLI -A "$USER_AGENT" -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest"); then
        fail "Could not look up the latest ${repo} release."
    fi
    if [[ ! "$url" =~ ^https://github\.com/"$repo"/releases/tag/"$tag_prefix"([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        fail "Unexpected latest-release URL for ${repo}: ${url}"
    fi
    printf '%s\n' "${BASH_REMATCH[1]}"
}

# The sqlite GitHub mirror publishes tags but no releases.
latest_sqlite_version() {
    local page version
    if ! page=$(curl -fsSL -A "$USER_AGENT" "https://github.com/sqlite/sqlite/tags"); then
        fail "Could not fetch the sqlite tag list."
    fi
    version=$(grep -oP 'version-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.gz)' <<< "$page" | sort -uV | tail -n1)
    [[ -n "$version" ]] || fail "Could not find a sqlite version in the GitHub tag list."
    printf '%s\n' "$version"
}

# Downloads and unpacks URL into temp_dir and prints the source directory.
fetch_source() {
    local name="$1" version="$2" url="$3" archive src_dir
    archive="${temp_dir}/${url##*/}"
    src_dir="${temp_dir}/${name}-${version}"
    curl -fsSL -A "$USER_AGENT" -o "$archive" "$url" || fail "Failed to download ${url}"
    mkdir "$src_dir" || fail "Failed to create ${src_dir}"
    tar -xf "$archive" -C "$src_dir" --strip-components 1 || fail "Failed to extract ${archive}"
    printf '%s\n' "$src_dir"
}

# Builds a static dependency into temp_dir. Remaining arguments go to configure.
build_dependency() {
    local name="$1" version="$2" url="$3" src_dir
    shift 3
    echo
    log "Building ${name} ${version}..."
    src_dir=$(fetch_source "$name" "$version" "$url") || exit 1
    (
        cd "$src_dir" || fail "Failed to enter ${src_dir}"
        ./configure "$@" || fail "Failed to configure ${name}."
        make -j"$(nproc)" || fail "Failed to build ${name}."
        make install || fail "Failed to install ${name}."
    ) || exit 1
}

# aria2 must link the static sqlite3 and c-ares from temp_dir, together with
# their private dependencies, instead of system copies or none at all.
use_temp_dependencies() {
    local pc pc_dir
    PKG_CONFIG_PATH="${temp_dir}/lib/pkgconfig"
    export PKG_CONFIG_PATH
    for pc in sqlite3 libcares; do
        pc_dir=$("$PKG_CONFIG" --variable=pcfiledir "$pc") || fail "pkg-config cannot find ${pc}."
        [[ "$pc_dir" == "$PKG_CONFIG_PATH" ]] || fail "pkg-config resolved ${pc} to ${pc_dir}, not ${PKG_CONFIG_PATH}."
        log "Using ${pc} $("$PKG_CONFIG" --modversion "$pc") from ${pc_dir}"
    done
    SQLITE3_LIBS=$("$PKG_CONFIG" --static --libs sqlite3) || fail "pkg-config --libs sqlite3 failed."
    LIBCARES_LIBS=$("$PKG_CONFIG" --static --libs libcares) || fail "pkg-config --libs libcares failed."
    export SQLITE3_LIBS LIBCARES_LIBS
}

build_aria2() {
    local version src_dir patch_file
    local -a configure_args
    version=$(latest_github_release_version aria2/aria2 release-) || exit 1
    echo
    log "Building aria2 ${version}..."
    src_dir=$(fetch_source aria2 "$version" "https://github.com/aria2/aria2/releases/download/release-${version}/aria2-${version}.tar.xz") || exit 1

    # Raise the --max-connection-per-server limit from 16 to 128.
    patch_file="${src_dir}/src/OptionHandlerFactory.cc"
    [[ "$(grep -c '1, 16' "$patch_file")" == "1" ]] || fail "max-connection-per-server patch target not found exactly once in ${patch_file}."
    sed -i 's/1, 16/1, 128/' "$patch_file" || fail "Failed to patch ${patch_file}."

    use_temp_dependencies
    export ARIA2_STATIC

    configure_args=(
        --prefix="$INSTALL_PREFIX"
        --disable-nls
        --without-gnutls
        --with-openssl
        --with-libxml2
        --with-sqlite3
        --with-libcares
        --with-libz
        --with-tcmalloc
        --with-ca-bundle="$CA_BUNDLE"
    )
    (
        cd "$src_dir" || fail "Failed to enter ${src_dir}"
        ./configure "${configure_args[@]}" || fail "Failed to configure aria2."
        make -j"$(nproc)" || fail "Failed to build aria2."
        sudo make install || fail "Failed to install aria2."
    ) || exit 1
}

verify_install() {
    local aria2c="${INSTALL_PREFIX}/bin/aria2c" resolved
    [[ -x "$aria2c" ]] || fail "${aria2c} was not installed."
    echo
    "$aria2c" --version | grep -E '^(aria2 version|Enabled Features|Libraries|Compiler)'
    hash -r
    resolved=$(type -P aria2c)
    if [[ "$resolved" != "$aria2c" ]]; then
        warn "'aria2c' in PATH resolves to ${resolved}, not ${aria2c}."
    fi
}

report_failure() {
    local status=$?
    if (( status != 0 )) && [[ -n "$temp_dir" && -d "$temp_dir" ]]; then
        echo -e "${RED}[ERROR]${NC} Build files kept for inspection in ${temp_dir}" >&2
    fi
}

start_build() {
    local cares_version sqlite_version
    temp_dir=$(mktemp -d -t aria2-build.XXXXXXXX) || fail "Failed to create a temporary build directory."
    trap report_failure EXIT
    log "Build directory: ${temp_dir}"

    cares_version=$(latest_github_release_version c-ares/c-ares v) || exit 1
    build_dependency c-ares "$cares_version" "https://github.com/c-ares/c-ares/releases/download/v${cares_version}/c-ares-${cares_version}.tar.gz" --prefix="$temp_dir" --enable-static --disable-shared

    sqlite_version=$(latest_sqlite_version) || exit 1
    build_dependency sqlite3 "$sqlite_version" "https://github.com/sqlite/sqlite/archive/refs/tags/version-${sqlite_version}.tar.gz" --prefix="$temp_dir" --enable-static --disable-shared --disable-tcl

    build_aria2
}

main() {
    if [[ "$EUID" -eq 0 ]]; then
        echo "This script must be run without root or sudo."
        exit 1
    fi

    parse_args "$@"
    setup_tools
    set_compiler_options
    print_env
    install_packages
    check_ca_bundle
    start_build
    verify_install

    if ! rm -rf "$temp_dir"; then
        warn "Could not remove the build directory ${temp_dir}."
    fi
    echo
    log "Aria2 build process completed successfully."
}

main "$@"
