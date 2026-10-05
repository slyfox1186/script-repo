#!/usr/bin/env bash

# Purpose: build the latest stable release of GNU Wget from source
# Target:  Ubuntu 24.04 (works on other Debian/Ubuntu releases as well)
# Source:  https://ftp.gnu.org/gnu/wget/
# Script version: 2.0
#
# What this script does, in order:
#   1. Finds the newest release on the GNU servers (or uses --version).
#   2. Downloads the tarball and checks its GPG signature against the GNU
#      keyring, which is the procedure documented at https://ftp.gnu.org/.
#   3. Builds libmetalink as a private static library, so nothing but wget
#      itself is installed and no ld.so.conf or rpath changes are needed.
#   4. Builds wget with an optimized, hardened set of compiler and linker
#      flags. Every flag is test compiled first and dropped if the compiler
#      or linker does not support it.
#   5. Checks the new binary (version, features, hardening) before installing.
#   6. Installs through a staging directory and records every installed path
#      in a manifest, so --uninstall removes exactly what was installed.

set -Eeuo pipefail

script_ver="2.0"
prog_name="wget"
version_regex='^[0-9]+(\.[0-9]+)+$'

# GNU asks that downloads go through the mirror redirector. ftp.gnu.org is the
# master site and is used as the fallback, and first for the release list
# because a mirror can lag behind it.
gnu_mirror="https://ftpmirror.gnu.org"
gnu_master="https://ftp.gnu.org/gnu"
keyring_url="https://ftp.gnu.org/gnu/gnu-keyring.gpg"

# libmetalink has had no release since 0.1.3 and Ubuntu 24.04 has no package
# for it, so it is built here. The checksum pins the exact file.
metalink_ver="0.1.3"
metalink_url="https://github.com/metalink-dev/libmetalink/releases/download/release-$metalink_ver/libmetalink-$metalink_ver.tar.xz"
metalink_sha256="86312620c5b64c694b91f9cc355eabbd358fa92195b3e99517504076bf9fe33a"

# Defaults (all can be changed with command line options)
install_dir="/usr/local"
version=""
compiler="gcc"
ssl_backend="openssl"
opt_level="2"
jobs="$(nproc 2>/dev/null || echo 2)"
build_base=""
mirror=""
keyring_file=""
portable=false
use_lto=true
use_hardening=true
use_metalink=true
use_nls=false
run_tests=false
verify_sig=true
keep_build=false
force=false
install_deps=true
dry_run=false
assume_yes=false
action="install"

manifest_file=""
work_dir=""
src_dir=""
deps_dir=""
stage_dir=""
probe_dir=""
tmp_manifest=""
built_binary=""
made_temp_base=false
created_build_base=false
deps_checked=false
user_path="$PATH"
SUDO=""
orig_args=()
CC=""
tool_ar="" tool_ranlib="" tool_nm=""
pkg_config="" pkg_config_path=""
cppflags="" cflags="" ldflags="" opt_cflags="" hard_cflags=""
last_url=""
manifest=()
skipped_flags=()

# Real escape characters, so messages can be printed with printf '%s' and
# backslashes inside paths are never interpreted. Color is used only on a
# terminal and is switched off by the NO_COLOR convention (https://no-color.org).
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    CYAN=$'\033[0;36m' GREEN=$'\033[0;32m' RED=$'\033[0;31m' YELLOW=$'\033[0;33m'
    BOLD=$'\033[1m' DIM=$'\033[2m' NC=$'\033[0m'
else
    CYAN='' GREEN='' RED='' YELLOW='' BOLD='' DIM='' NC=''
fi

# Output is grouped into steps. Each step has a bold title, and the lines
# under it are indented:
#   step  a new stage of the run
#   item  one "label   value" line, labels in a fixed-width column
#   log   a plain line
#   warn  something to look at (yellow), fail: stop with an error (red)
step() { printf '\n%s==>%s %s%s%s\n' "$CYAN$BOLD" "$NC" "$BOLD" "$*" "$NC"; }
log()  { printf '    %s\n' "$*"; }
item() { printf '    %s%-13s%s %s\n' "$CYAN" "$1" "$NC" "$2"; }
warn() { printf '    %s[WARN]%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
fail() { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

# item_wrapped LABEL TEXT prints a long value across several lines, with the
# continuation lines lined up under the first
item_wrapped() {
    local label="$1" line first=true
    while IFS= read -r line; do
        if [[ "$first" == true ]]; then
            item "$label" "$line"
            first=false
        else
            printf '%18s%s\n' "" "$line"
        fi
    done < <(fold -s -w 58 <<<"$2" | sed 's/[[:space:]]*$//')
}

# heading TITLE and block TEXT print a sub-list inside a step, such as a set
# of compiler flags, wrapped to fit an 80 column terminal
heading() { printf '    %s%s%s\n' "$CYAN" "$1" "$NC"; }
block()   { fold -s -w 68 <<<"$1" | sed 's/[[:space:]]*$//; s/^/        /'; }

# run_task LABEL LOGFILE COMMAND... runs a long command with its output sent
# to LOGFILE, and reports the result and how long it took on one line
run_task() {
    local label="$1" logfile="$2" start="$SECONDS"
    shift 2
    printf '    %-44s ' "$label"
    if "$@" >>"$logfile" 2>&1; then
        printf '%sdone%s  %s%ss%s\n' "$GREEN" "$NC" "$DIM" "$(( SECONDS - start ))" "$NC"
    else
        printf '%sFAILED%s\n\n' "$RED" "$NC"
        printf '%sLast lines of %s%s\n' "$DIM" "$logfile" "$NC" >&2
        tail -n 40 "$logfile" >&2
        echo >&2
        fail "$label failed. Run again with --keep-build to keep the full log."
    fi
}

trap 'fail "Command failed on line $LINENO: $BASH_COMMAND"' ERR

# Help output is kept within 80 columns. Option names are green, the values
# they take are cyan, section titles are bold yellow (color first, because the
# color code resets bold), and defaults are dim.
help_section() {
    printf '\n%s%s%s\n' "$YELLOW$BOLD" "$1" "$NC"
}

# help_opt SHORT LONG VALUE DESCRIPTION [MORE_LINES...]
help_opt() {
    local short="$1" long="$2" value="$3" flags pad line
    shift 3
    if [[ -n "$short" ]]; then flags="$short, $long"; else flags="    $long"; fi
    pad=$(( 30 - ${#flags} - ${#value} ))
    [[ -n "$value" ]] && pad=$(( pad - 1 ))
    (( pad < 2 )) && pad=2
    printf '  %s%s%s%s%*s%s\n' "$GREEN" "$flags" "$NC" "${value:+ $CYAN$value$NC}" "$pad" "" "$1"
    shift
    for line in "$@"; do
        printf '%32s%s\n' "" "$line"
    done
}

help_default() {
    printf '%s[default: %s]%s' "$DIM" "$1" "$NC"
}

# help_example DESCRIPTION ARGUMENTS
help_example() {
    printf '  %s# %s%s\n  %s%s%s%s\n\n' "$DIM" "$1" "$NC" "$BOLD" "${0##*/}" "$NC" "${2:+ $2}"
}

print_usage() {
    printf '%s%s%s %sv%s%s\n' "$CYAN$BOLD" "build-wget.sh" "$NC" "$DIM" "$script_ver" "$NC"
    printf '%s\n' "Build and install GNU Wget from source."

    help_section "USAGE"
    printf '  %s%s%s [%sOPTIONS%s]\n' "$BOLD" "${0##*/}" "$NC" "$CYAN" "$NC"

    help_section "INSTALL LOCATION"
    help_opt "-i" "--install-directory" "DIR" \
        "Install prefix, relative or absolute." \
        "The binary goes in DIR/bin, the man and info" \
        "pages in DIR/share, and the sample config" \
        "in DIR/etc/wgetrc." \
        "$(help_default "$install_dir")"

    help_section "VERSION"
    help_opt "-v" "--version" "VERSION" \
        "Build a specific release, such as 1.24.5." \
        "$(help_default "latest stable")"
    help_opt "-l" "--list" "" \
        "List the available releases."
    help_opt "" "--check" "" \
        "Compare the version installed in DIR with" \
        "the latest release. Exit status is 0 when" \
        "up to date and 10 when an update exists."

    help_section "BUILD"
    help_opt "-c" "--compiler" "NAME" \
        "gcc or clang, or an exact name such as" \
        "gcc-14 or clang-18." \
        "$(help_default "$compiler")"
    help_opt "-S" "--ssl" "BACKEND" \
        "TLS library: openssl or gnutls." \
        "$(help_default "$ssl_backend")"
    help_opt "-O" "--optimize" "LEVEL" \
        "Optimization level: 2, 3, or s (size)." \
        "$(help_default "$opt_level")"
    help_opt "-p" "--portable" "" \
        "Build a binary that runs on any CPU of the" \
        "same architecture. Without this the build" \
        "uses -march=native, which is tuned for this" \
        "PC and may not run on others."
    help_opt "" "--no-lto" "" \
        "Turn off link time optimization."
    help_opt "" "--no-hardening" "" \
        "Turn off the security hardening flags."
    help_opt "" "--no-metalink" "" \
        "Build without Metalink support. Skips the" \
        "libmetalink build."
    help_opt "" "--nls" "" \
        "Include translations. The default build is" \
        "English only."
    help_opt "-j" "--jobs" "N" \
        "Parallel build jobs." \
        "$(help_default "$jobs")"
    help_opt "-t" "--run-tests" "" \
        "Run the upstream test suite and install only" \
        "if it passes. Adds several minutes."
    help_opt "-b" "--build-directory" "DIR" \
        "Where to download and compile." \
        "$(help_default "a new temporary directory")"
    help_opt "-k" "--keep-build" "" \
        "Keep the build directory when finished."

    help_section "DOWNLOAD"
    help_opt "-m" "--mirror" "URL" \
        "GNU mirror to try first, for example" \
        "https://mirrors.kernel.org/gnu" \
        "$(help_default "$gnu_mirror")"
    help_opt "" "--keyring" "FILE" \
        "Verify the signature with this binary GPG" \
        "keyring instead of downloading the GNU one."
    help_opt "" "--skip-verify" "" \
        "Do not check the GPG signature of the wget" \
        "tarball. Not recommended."

    help_section "BEHAVIOR"
    help_opt "-f" "--force" "" \
        "Rebuild even if that version is already" \
        "installed in DIR."
    help_opt "-y" "--yes" "" \
        "Do not prompt (passes -y to apt)."
    help_opt "" "--no-deps" "" \
        "Do not check for or install APT packages."
    help_opt "" "--dry-run" "" \
        "Show what would be done and change nothing."
    help_opt "-u" "--uninstall" "" \
        "Remove a previous install from DIR, using" \
        "the manifest it left behind."
    help_opt "-h" "--help" "" \
        "Show this help."

    help_section "EXAMPLES"
    help_example "Latest release into /usr/local" ""
    # shellcheck disable=SC2016
    help_example "Per-user install, no sudo needed" '-i "$HOME/.local"'
    help_example "Build with clang and GnuTLS, then run the tests" "-c clang -S gnutls -t"
    help_example "A binary you can copy to other PCs" "-p -i ./wget-portable"
    help_example "See whether an update is available" "--check -i /usr/local"
    help_example "Uninstall" "-u -i /usr/local"

    printf '%sColor is disabled when output is not a terminal or NO_COLOR is set.%s\n' "$DIM" "$NC"
}

need_value() {
    [[ $# -ge 2 && -n "$2" ]] || fail "Option $1 requires a value."
    [[ "$2" != -* ]] || fail "Option $1 requires a value, but got another option: $2"
}

parse_args() {
    local arg
    while [[ $# -gt 0 ]]; do
        # Accept both "--option value" and "--option=value"
        if [[ "$1" == --*=* ]]; then
            arg="$1"
            shift
            set -- "${arg%%=*}" "${arg#*=}" "$@"
        fi
        case "$1" in
            -i|--install-directory) need_value "$@"; install_dir="$2"; shift 2 ;;
            -v|--version)           need_value "$@"; version="${2#v}"; shift 2 ;;
            -c|--compiler)          need_value "$@"; compiler="$2"; shift 2 ;;
            -S|--ssl)               need_value "$@"; ssl_backend="$2"; shift 2 ;;
            -O[23s])                opt_level="${1#-O}"; shift ;;
            -O|--optimize)          need_value "$@"; opt_level="$2"; shift 2 ;;
            -j[0-9]*)               jobs="${1#-j}"; shift ;;
            -j|--jobs)              need_value "$@"; jobs="$2"; shift 2 ;;
            -b|--build-directory)   need_value "$@"; build_base="$2"; shift 2 ;;
            -m|--mirror)            need_value "$@"; mirror="${2%/}"; shift 2 ;;
            --keyring)              need_value "$@"; keyring_file="$2"; shift 2 ;;
            --skip-verify)          verify_sig=false; shift ;;
            -l|--list)              action="list"; shift ;;
            --check)                action="check"; shift ;;
            -u|--uninstall)         action="uninstall"; shift ;;
            -p|--portable)          portable=true; shift ;;
            --no-lto)               use_lto=false; shift ;;
            --no-hardening)         use_hardening=false; shift ;;
            --no-metalink)          use_metalink=false; shift ;;
            --nls)                  use_nls=true; shift ;;
            -t|--run-tests)         run_tests=true; shift ;;
            -k|--keep-build)        keep_build=true; shift ;;
            -f|--force)             force=true; shift ;;
            --no-deps)              install_deps=false; shift ;;
            --dry-run)              dry_run=true; shift ;;
            -y|--yes)               assume_yes=true; shift ;;
            -h|--help)              print_usage; exit 0 ;;
            *)                      fail "Invalid option: $1 (use --help to see the options)" ;;
        esac
    done

    [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail "--jobs must be a positive integer, got: $jobs"
    [[ -z "$version" || "$version" =~ $version_regex ]] || fail "--version must look like 1.25.0, got: $version"
    case "$ssl_backend" in
        openssl|gnutls) ;;
        *) fail "--ssl must be openssl or gnutls, got: $ssl_backend" ;;
    esac
    case "$opt_level" in
        2|3|s) ;;
        *) fail "--optimize must be 2, 3, or s, got: $opt_level" ;;
    esac
    [[ -z "$mirror" || "$mirror" =~ ^https?:// ]] || fail "--mirror must be an http or https URL, got: $mirror"
    if [[ -n "$keyring_file" ]]; then
        keyring_file="$(realpath -m -- "$keyring_file")"
        [[ -r "$keyring_file" ]] || fail "Keyring file not readable: $keyring_file"
    fi

    # Resolve the prefix to an absolute path. A quoted or =style "~" is not
    # expanded by the shell, so handle it here.
    # shellcheck disable=SC2088
    [[ "$install_dir" == "~" || "$install_dir" == "~/"* ]] && install_dir="$HOME${install_dir:1}"
    install_dir="$(realpath -m -- "$install_dir")"
    [[ "$install_dir" != "/" ]] || fail "Refusing to use / as the install prefix. Use /usr or /usr/local."
    [[ "$install_dir" != *[[:space:]]* ]] || fail "The install prefix cannot contain whitespace (a limit of the GNU build system)."
    manifest_file="$install_dir/share/$prog_name/install_manifest.txt"
}

# Build with the system toolchain only. An active conda or similar environment
# puts its own compilers, pkg-config, and libraries ahead of the system ones
# and exports search paths that would silently link wget against them.
clean_environment() {
    # /usr/local is left out on purpose: tools built from source and installed
    # there (a pkg-config that does not know Ubuntu's library directories, for
    # example) would replace the system ones. A compiler that lives there can
    # still be selected by giving --compiler its full path.
    PATH="/usr/sbin:/usr/bin:/sbin:/bin"
    export PATH
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LIBS CPATH C_INCLUDE_PATH LIBRARY_PATH \
          LD_LIBRARY_PATH PKG_CONFIG_PATH PKG_CONFIG_LIBDIR AR RANLIB NM
}

# Wget is written in C, so only a C compiler is needed
set_compiler() {
    local base suffix=""
    case "$compiler" in
        g++|g++-*)         CC="gcc${compiler#g++}" ;;
        clang++|clang++-*) CC="clang${compiler#clang++}" ;;
        *)                 CC="$compiler" ;;
    esac

    # Link time optimization needs the archive tools that match the compiler
    base="${CC##*/}"
    [[ "$base" =~ -[0-9.]+$ ]] && suffix="${BASH_REMATCH[0]}"
    if [[ "$base" == clang* ]]; then
        tool_ar="llvm-ar$suffix" tool_ranlib="llvm-ranlib$suffix" tool_nm="llvm-nm$suffix"
    else
        tool_ar="gcc-ar$suffix" tool_ranlib="gcc-ranlib$suffix" tool_nm="gcc-nm$suffix"
    fi
}

# Ubuntu keeps its .pc files in a per-architecture directory that a pkg-config
# built from source does not search. Use the system pkg-config by its full
# path, and name the system directories as well so that any pkg-config finds
# the APT development packages.
set_pkg_config() {
    local multiarch=""
    if [[ -x /usr/bin/pkg-config ]]; then
        pkg_config="/usr/bin/pkg-config"
    else
        pkg_config="$(command -v pkg-config || true)"
    fi
    multiarch="$("$CC" -print-multiarch 2>/dev/null || true)"
    [[ -n "$multiarch" ]] || multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
    pkg_config_path="${multiarch:+/usr/lib/$multiarch/pkgconfig:}/usr/lib/pkgconfig:/usr/share/pkgconfig"
}

# Stop with an explanation and the exact command to run again with sudo.
# The script never calls sudo itself.
require_root() {
    local cmd
    [[ "$EUID" -eq 0 ]] && return 0
    printf -v cmd '%q ' "$0" "${orig_args[@]}"
    printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$1" >&2
    printf '        Run the script again with sudo:\n\n            %ssudo %s%s\n\n' "$BOLD" "${cmd% }" "$NC" >&2
    # shellcheck disable=SC2016
    printf '        Or pick a prefix you own, which needs no sudo: -i "$HOME/.local"\n' >&2
    exit 1
}

# Root is only needed when the prefix is not writable by the current user
set_sudo() {
    local probe="$install_dir"
    while [[ ! -e "$probe" ]]; do
        probe="$(dirname "$probe")"
    done
    if [[ -w "$probe" ]]; then
        SUDO=""
    elif [[ "$EUID" -eq 0 ]]; then
        fail "$probe is not writable, even as root."
    else
        SUDO="needed"
    fi
}

as_root() {
    "$@"
}

fetch() {
    curl -fsSL --connect-timeout 15 --retry 3 --retry-delay 2 "$@"
}

# Everything under gnu/ on the GNU servers is a stable release. Test releases
# are published on alpha.gnu.org instead. "wget2" is a different program and
# does not match the pattern.
list_versions() {
    local base page versions
    for base in ${mirror:+"$mirror"} "$gnu_master" "$gnu_mirror"; do
        page="$(fetch "$base/$prog_name/" 2>/dev/null)" || continue
        versions="$(grep -oP 'wget-\K[0-9]+(\.[0-9]+)+(?=\.tar\.gz)' <<<"$page" | sort -ruV)" || continue
        if [[ -n "$versions" ]]; then
            echo "$versions"
            return 0
        fi
    done
    return 1
}

latest_version() {
    local versions
    versions="$(list_versions)" || return 1
    head -n1 <<<"$versions"
}

installed_version() {
    local out
    [[ -x "$install_dir/bin/$prog_name" ]] || return 1
    out="$("$install_dir/bin/$prog_name" --version 2>/dev/null | head -n1)" || return 1
    [[ "$out" =~ ([0-9]+(\.[0-9]+)+) ]] || return 1
    echo "${BASH_REMATCH[1]}"
}

required_packages() {
    local -a pkgs missing_pkgs=() apt_cmd=(apt-get) apt_opts=()
    local pkg base suffix=""

    [[ "$install_deps" == true && "$deps_checked" == false ]] || return 0
    deps_checked=true

    # Release tarballs ship a ready configure script, so the autotools are not
    # needed. perl provides pod2man, which generates the man page.
    pkgs=(
        build-essential pkg-config perl ca-certificates curl gpgv
        zlib1g-dev libpsl-dev libidn2-dev libunistring-dev libpcre2-dev
        uuid-dev libc-ares-dev
    )
    if [[ "$ssl_backend" == openssl ]]; then pkgs+=(libssl-dev); else pkgs+=(libgnutls28-dev nettle-dev); fi
    [[ "$use_metalink" == true ]] && pkgs+=(libexpat1-dev libgpgme-dev xz-utils)
    [[ "$run_tests" == true ]] && pkgs+=(python3 libhttp-daemon-perl libio-socket-ssl-perl)

    base="${CC##*/}"
    [[ "$base" =~ -[0-9.]+$ ]] && suffix="${BASH_REMATCH[0]}"
    case "$base" in
        clang*) pkgs+=("clang$suffix" "lld$suffix" "llvm$suffix") ;;
        gcc-*)  pkgs+=("$base") ;;
        *)      ;;
    esac

    command -v dpkg-query >/dev/null || { warn "dpkg not found, skipping the package check."; return 0; }

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done
    [[ "${#missing_pkgs[@]}" -eq 0 ]] && return 0

    item_wrapped "APT packages" "missing: ${missing_pkgs[*]}"
    if [[ "$dry_run" == true ]]; then
        log "Dry run, so they were not installed."
        return 0
    fi
    require_root "Installing the missing APT packages needs root: ${missing_pkgs[*]}"
    [[ "$assume_yes" == true ]] && apt_opts+=(-y)
    "${apt_cmd[@]}" update
    "${apt_cmd[@]}" install "${apt_opts[@]}" "${missing_pkgs[@]}"
}

# Fail early with a clear message instead of halfway through the build
require_commands() {
    local cmd
    local -a cmds=("$CC" make curl tar strip pod2man)
    set_pkg_config
    [[ -n "$pkg_config" ]] || fail "Required command not found: pkg-config"
    [[ "$verify_sig" == true ]] && cmds+=(gpgv)
    [[ "$use_metalink" == true ]] && cmds+=(xz sha256sum)
    for cmd in "${cmds[@]}"; do
        command -v "$cmd" >/dev/null || fail "Required command not found: $cmd"
    done
}

# ---------------------------------------------------------------------------
# Compiler and linker flags
# ---------------------------------------------------------------------------

# probe FLAGS... returns 0 if a test program compiles and links with them.
# -Werror and --fatal-warnings turn "unknown option, ignored" into a failure,
# which is how clang and the linkers report options they do not support.
probe() {
    "$CC" -O2 -Werror -Wl,--fatal-warnings "$@" -o "$probe_dir/probe" "$probe_dir/probe.c" >/dev/null 2>&1
}

# add_flags VARIABLE EXTRA_PROBE_FLAGS GROUP...
# Each GROUP is one flag, or several that only make sense together. A group
# that passes the probe is appended to VARIABLE, the rest are remembered.
add_flags() {
    local -n target="$1"
    local extra="$2" group
    local -a words extra_words=()
    shift 2
    [[ -n "$extra" ]] && read -ra extra_words <<<"$extra"
    for group in "$@"; do
        read -ra words <<<"$group"
        if probe "${extra_words[@]}" "${words[@]}"; then
            target+="${target:+ }$group"
        else
            skipped_flags+=("$group")
        fi
    done
}

select_flags() {
    local arch lto="" linker=""
    arch="$(uname -m)"

    probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/wget-flag-probe.XXXXXX")"
    printf 'int main(void) { return 0; }\n' >"$probe_dir/probe.c"
    probe || fail "The compiler $CC cannot build a simple program."

    cppflags="" cflags="" ldflags="" opt_cflags="" hard_cflags=""
    skipped_flags=()

    # --- Link time optimization: lets the compiler optimize across all source
    # files at once. GCC uses its own linker plugin. Clang needs the lld linker.
    if [[ "$use_lto" == true ]]; then
        if [[ "${CC##*/}" == clang* ]]; then
            lto="-flto" linker="-fuse-ld=lld"
        else
            lto="-flto=auto"
        fi
        if ! command -v "$tool_ar" >/dev/null || ! command -v "$tool_ranlib" >/dev/null; then
            warn "LTO turned off: $tool_ar and $tool_ranlib were not found."
            lto="" linker=""
        elif ! probe $lto $linker; then
            warn "LTO turned off: $CC could not link a test program with $lto $linker."
            lto="" linker=""
        fi
    fi

    # --- Optimization
    opt_cflags="-O$opt_level -pipe"
    if [[ "$portable" == true ]]; then
        add_flags opt_cflags "" "-mtune=generic"
    else
        add_flags opt_cflags "" "-march=native"
    fi
    [[ -n "$lto" ]] && opt_cflags+=" $lto"
    # Put each function and data item in its own section so the linker can
    # drop the ones wget never uses, and skip the PLT for library calls.
    add_flags opt_cflags "" "-ffunction-sections -fdata-sections" "-fno-plt"

    [[ -n "$lto" ]] && ldflags="$lto${linker:+ $linker}"
    add_flags ldflags "$linker" "-Wl,-O1" "-Wl,--gc-sections" "-Wl,--as-needed" "-Wl,--no-copy-dt-needed-entries"

    # --- Hardening, following the OpenSSF Compiler Options Hardening Guide
    # for C and C++ (https://best.openssf.org/Compiler-Hardening-Guides/).
    # The guide's warning options are left out because they do not change the
    # binary, and -fstrict-flex-arrays=3 is left out because it can turn
    # legacy trailing arrays in third party code into runtime aborts.
    if [[ "$use_hardening" == true ]]; then
        # Bounds checks in libc calls. Undefine first so a distribution
        # default does not cause a redefinition warning.
        cppflags="-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3"
        add_flags hard_cflags "$linker" \
            "-fstack-protector-strong" \
            "-fstack-clash-protection" \
            "-fPIE -pie" \
            "-ftrivial-auto-var-init=zero" \
            "-fzero-call-used-regs=used-gpr" \
            "-fno-delete-null-pointer-checks" \
            "-fno-strict-overflow" \
            "-fno-strict-aliasing"
        # -fPIE belongs to the compiler and -pie to the linker
        if [[ " $hard_cflags " == *" -fPIE -pie "* ]]; then
            hard_cflags="${hard_cflags/-fPIE -pie/-fPIE}"
            ldflags+="${ldflags:+ }-pie"
        fi
        # Control flow protection is specific to the CPU architecture
        case "$arch" in
            x86_64)  add_flags hard_cflags "" "-fcf-protection=full" ;;
            aarch64) add_flags hard_cflags "" "-mbranch-protection=standard" ;;
            *)       ;;
        esac
        add_flags ldflags "$linker" \
            "-Wl,-z,relro" "-Wl,-z,now" "-Wl,-z,noexecstack" "-Wl,-z,nodlopen"
    fi

    cflags="$opt_cflags${hard_cflags:+ $hard_cflags}"
    rm -rf -- "$probe_dir"
    probe_dir=""
}

show_flags() {
    step "Compiler flags ($CC)"
    heading "Optimization"
    block "$opt_cflags"
    if [[ "$use_hardening" == true ]]; then
        heading "Hardening"
        block "$cppflags $hard_cflags"
    fi
    heading "Linker"
    block "${ldflags:-(none)}"
    if [[ "${#skipped_flags[@]}" -gt 0 ]]; then
        printf '    %sLeft out, not supported by this toolchain%s\n' "$YELLOW" "$NC"
        block "${skipped_flags[*]}"
    fi
}

# ---------------------------------------------------------------------------
# Download and verification
# ---------------------------------------------------------------------------

# download_gnu FILE DESTINATION tries the chosen mirror, then the GNU mirror
# redirector, then the master site.
download_gnu() {
    local file="$1" dest="$2" base
    for base in ${mirror:+"$mirror"} "$gnu_mirror" "$gnu_master"; do
        if fetch -o "$dest" "$base/$prog_name/$file" 2>/dev/null; then
            last_url="$base/$prog_name/$file"
            return 0
        fi
    done
    rm -f -- "$dest"
    return 1
}

download_wget() {
    local tarball="$work_dir/$prog_name-$version.tar.gz"
    local sig="$tarball.sig" keyring="$work_dir/gnu-keyring.gpg"

    step "Download and verify"
    download_gnu "$prog_name-$version.tar.gz" "$tarball" \
        || fail "Could not download wget $version. Run ${0##*/} --list to see the valid versions."
    item "Tarball" "$last_url"
    item "SHA-256" "$(sha256sum "$tarball" | cut -d' ' -f1)"

    if [[ "$verify_sig" == true ]]; then
        download_gnu "$prog_name-$version.tar.gz.sig" "$sig" \
            || fail "Could not download the signature for wget $version. Use --skip-verify to build without checking it."
        if [[ -n "$keyring_file" ]]; then
            keyring="$keyring_file"
        else
            # The keyring always comes from the GNU master site over HTTPS,
            # never from a mirror, because it is what the mirrors are checked against
            fetch -o "$keyring" "$keyring_url" \
                || fail "Could not download $keyring_url. Use --keyring FILE or --skip-verify."
        fi
        # This is the command documented at https://ftp.gnu.org/
        # --homedir keeps gpgv from creating ~/.gnupg
        gpgv --homedir "$work_dir" --keyring "$keyring" "$sig" "$tarball" 2>"$work_dir/gpgv.log" || {
            cat "$work_dir/gpgv.log" >&2
            fail "GPG signature check FAILED for $prog_name-$version.tar.gz. The file was not used."
        }
        item "Signature" "${GREEN}good${NC}, signed by $(grep -m1 -oP 'Good signature from "\K[^"]+' "$work_dir/gpgv.log" || echo "a key in the GNU keyring")"
    else
        item "Signature" "${YELLOW}not checked (--skip-verify)${NC}"
    fi

    mkdir -p "$src_dir"
    tar -xzf "$tarball" -C "$src_dir" --strip-components 1 || fail "Failed to extract $tarball"
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

# Arguments shared by both configure runs. Passing the variables as arguments
# (not through the environment) is what the Autoconf manual recommends,
# because config.status then remembers them.
configure_vars() {
    printf '%s\n' "CC=$CC" "CPPFLAGS=$cppflags" "CFLAGS=$cflags" "LDFLAGS=$ldflags" \
        "PKG_CONFIG=$pkg_config" "PKG_CONFIG_PATH=$pkg_config_path"
    # LTO objects in a static library need the compiler's own archive tools
    if [[ "$cflags" == *"-flto"* ]]; then
        printf '%s\n' "AR=$tool_ar" "RANLIB=$tool_ranlib" "NM=$tool_nm"
    fi
}

build_libmetalink() {
    local tarball="$work_dir/libmetalink-$metalink_ver.tar.xz" dir="$work_dir/libmetalink" sum
    local -a vars

    fetch -o "$tarball" "$metalink_url" || fail "Could not download $metalink_url"
    sum="$(sha256sum "$tarball" | cut -d' ' -f1)"
    [[ "$sum" == "$metalink_sha256" ]] || fail "Checksum mismatch for libmetalink. Expected $metalink_sha256, got $sum."

    mkdir -p "$dir"
    tar -xJf "$tarball" -C "$dir" --strip-components 1 || fail "Failed to extract $tarball"
    mapfile -t vars < <(configure_vars)

    cd "$dir"
    # Static and position independent, so it links straight into the wget
    # binary. Installed into the build directory only, never into the prefix.
    run_task "Configure libmetalink $metalink_ver" "$work_dir/libmetalink-configure.log" \
        ./configure --prefix="$deps_dir" --disable-shared --enable-static --with-pic \
        --with-libexpat --without-libxml2 --disable-dependency-tracking "${vars[@]}"
    run_task "Compile libmetalink (static, private)" "$work_dir/libmetalink-build.log" \
        make -j"$jobs"
    make install >>"$work_dir/libmetalink-build.log" 2>&1 || fail "libmetalink staging install failed."
}

build_wget() {
    local -a vars args

    mapfile -t vars < <(configure_vars)
    args=(
        --prefix="$install_dir"
        # Unknown options are an error, not a warning that scrolls past
        --enable-option-checking=fatal
        --disable-dependency-tracking
        --with-ssl="$ssl_backend"
        --with-cares
    )
    if [[ "$use_nls" == true ]]; then args+=(--enable-nls); else args+=(--disable-nls); fi
    if [[ "$use_metalink" == true ]]; then
        # A static libmetalink does not pull in expat by itself, so ask
        # pkg-config for the complete static link line
        args+=(
            --with-metalink
            "METALINK_CFLAGS=$(PKG_CONFIG_PATH="$deps_dir/lib/pkgconfig:$pkg_config_path" "$pkg_config" --cflags libmetalink)"
            "METALINK_LIBS=$(PKG_CONFIG_PATH="$deps_dir/lib/pkgconfig:$pkg_config_path" "$pkg_config" --static --libs libmetalink)"
        )
    else
        args+=(--without-metalink)
    fi

    mkdir -p "$src_dir/build"
    cd "$src_dir/build"
    run_task "Configure wget $version" "$work_dir/wget-configure.log" \
        ../configure "${args[@]}" "${vars[@]}"
    run_task "Compile wget ($jobs jobs)" "$work_dir/wget-build.log" \
        make -j"$jobs"
    built_binary="$src_dir/build/src/$prog_name"
    [[ -x "$built_binary" ]] || fail "The build finished but $built_binary was not found."
}

# Check the version and that every feature that was asked for is really in
# the binary. configure can quietly leave a feature out when a library is
# missing, and this is where that gets caught.
verify_binary() {
    local out flat feature
    local -a expected=("+https" "+ssl/$ssl_backend" "+ipv6" "+iri" "+psl" "+cares" "+large-file" "+digest")

    step "Check the new binary"
    out="$("$built_binary" --version)" || fail "The new binary does not run."
    [[ "$(head -n1 <<<"$out")" == "GNU Wget $version "* ]] \
        || fail "Built binary reports \"$(head -n1 <<<"$out")\", expected version $version."

    if [[ "$use_metalink" == true ]]; then expected+=("+metalink"); fi
    if [[ "$use_nls" == true ]]; then expected+=("+nls"); fi
    flat=" $(tr '\n' ' ' <<<"$out") "
    for feature in "${expected[@]}"; do
        [[ "$flat" == *" $feature "* ]] || fail "The new binary is missing the feature $feature. Nothing was installed. See $work_dir/wget-configure.log (use --keep-build to keep it)."
    done
    item "Version" "$version"
    item_wrapped "Features" "${expected[*]}"
}

# Read the hardening properties back out of the finished binary
hardening_report() {
    local hdr segs dyn syms notes
    command -v readelf >/dev/null || return 0

    hdr="$(readelf -hW "$built_binary")"
    segs="$(readelf -lW "$built_binary")"
    dyn="$(readelf -dW "$built_binary")"
    syms="$(readelf --dyn-syms -W "$built_binary")"
    notes="$(readelf -nW "$built_binary" 2>/dev/null || true)"

    report_item() {
        if [[ "$2" == yes ]]; then
            printf '        %-34s %syes%s\n' "$1" "$GREEN" "$NC"
        else
            printf '        %-34s %sNO%s\n' "$1" "$RED" "$NC"
        fi
    }
    has() { if grep -qE -- "$1" <<<"$2"; then echo yes; else echo no; fi; }

    heading "Hardening found in the binary"
    report_item "Position independent (PIE)"     "$(has 'Type:[[:space:]]+DYN' "$hdr")"
    report_item "Read-only relocations (RELRO)"  "$(has 'GNU_RELRO' "$segs")"
    report_item "Immediate binding (BIND_NOW)"   "$(has 'BIND_NOW|[[:space:]]NOW' "$dyn")"
    report_item "Non-executable stack"           "$(has 'GNU_STACK.*RW[[:space:]]' "$segs")"
    report_item "Stack protector"                "$(has '__stack_chk_fail' "$syms")"
    report_item "Fortified libc calls"           "$(has '_chk(@|$)' "$syms")"
    case "$(uname -m)" in
        x86_64)  report_item "Control flow protection (CET)" "$(has 'IBT.*SHSTK|SHSTK.*IBT' "$notes")" ;;
        aarch64) report_item "Branch protection (BTI, PAC)"  "$(has 'BTI.*PAC|PAC.*BTI' "$notes")" ;;
        *)       ;;
    esac
}

run_test_suite() {
    local summary
    step "Test suite"
    cd "$src_dir/build"
    run_task "Run the upstream tests (several minutes)" "$work_dir/wget-check.log" \
        make -j"$jobs" check
    # Automake prints one summary per test directory, so add them up
    summary="$(awk '/^# (TOTAL|PASS|SKIP|XFAIL|FAIL|XPASS|ERROR):/ { gsub(":", "", $2); n[$2] += $3 }
        END { printf "%d run, %d passed, %d skipped, %d expected failures, %d failed", n["TOTAL"], n["PASS"], n["SKIP"], n["XFAIL"], n["FAIL"] + n["XPASS"] + n["ERROR"] }' "$work_dir/wget-check.log")"
    item "Result" "${GREEN}passed${NC}: $summary"
}

# ---------------------------------------------------------------------------
# Install and uninstall
# ---------------------------------------------------------------------------

# Manifest entries are only trusted if they sit under the prefix and contain no ".." component
safe_entry() {
    [[ "$1" == "$install_dir/"* && "$1" != *"/../"* && "$1" != *"/.." ]]
}

install_wget() {
    local root src rel dest mode file stale=0 shown=0 config_note="" info="$install_dir/share/info/$prog_name.info"
    local -a old_files=()
    local -A new_set=()

    # "make install" into a staging directory first. This runs as the normal
    # user, gives an exact list of what wget installs, and means root is only
    # used to copy finished files.
    step "Install into $install_dir"
    cd "$src_dir/build"
    make install-strip DESTDIR="$stage_dir" >"$work_dir/wget-install.log" 2>&1 \
        || { tail -n 30 "$work_dir/wget-install.log" >&2; fail "Staging install failed."; }
    root="$stage_dir$install_dir"
    [[ -x "$root/bin/$prog_name" ]] || fail "Staging install did not produce $root/bin/$prog_name"

    # Remember what an earlier run of this script installed here
    [[ -f "$manifest_file" ]] && mapfile -t old_files <"$manifest_file"

    while IFS= read -r -d '' src; do
        rel="${src#"$root"/}"
        dest="$install_dir/$rel"
        case "$rel" in
            share/info/dir)
                # The shared index of all info pages. Updated with install-info below.
                continue
                ;;
            etc/wgetrc)
                # A config file belongs to the admin: never overwrite it, never uninstall it
                if [[ -e "$dest" ]]; then
                    config_note="kept your existing $dest"
                else
                    as_root install -D -m 0644 "$src" "$dest"
                    config_note="installed the sample $dest"
                fi
                continue
                ;;
            *)  ;;
        esac
        if [[ -x "$src" ]]; then mode=0755; else mode=0644; fi
        as_root install -D -m "$mode" "$src" "$dest"
        manifest+=("$dest")
        new_set["$dest"]=1
    done < <(find "$root" \( -type f -o -type l \) -print0 | sort -z)
    manifest+=("$manifest_file")
    new_set["$manifest_file"]=1

    if [[ -f "$info" ]] && command -v install-info >/dev/null; then
        as_root install-info --info-dir="$install_dir/share/info" "$info" 2>/dev/null || true
    fi

    # Remove files from the earlier install that this one no longer provides,
    # so an upgrade or a change of options leaves nothing orphaned
    for file in "${old_files[@]}"; do
        safe_entry "$file" || continue
        if [[ -z "${new_set["$file"]:-}" && ( -f "$file" || -L "$file" ) ]]; then
            as_root rm -f -- "$file"
            stale=$(( stale + 1 ))
        fi
    done

    # List what was installed. Translations run to dozens of files, so past
    # the first few only the count is shown.
    for file in "${manifest[@]}"; do
        if (( shown < 8 )); then
            printf '    %s+%s %s\n' "$GREEN" "$NC" "$file"
            shown=$(( shown + 1 ))
        fi
    done
    (( ${#manifest[@]} > shown )) && log "  and $(( ${#manifest[@]} - shown )) more, all listed in $manifest_file"
    [[ -n "$config_note" ]] && item "Config" "$config_note"
    (( stale > 0 )) && item "Cleaned up" "$stale files from the previous install that this one does not provide"

    tmp_manifest="$(mktemp)"
    printf '%s\n' "${manifest[@]}" >"$tmp_manifest"
    as_root install -D -m 0644 "$tmp_manifest" "$manifest_file"
}

uninstall_wget() {
    local file dir info="$install_dir/share/info/$prog_name.info"
    local -a files=()

    [[ -f "$manifest_file" ]] || fail "No manifest at $manifest_file. This script did not install wget into $install_dir, so nothing was removed."
    set_sudo
    if [[ -n "$SUDO" && "$dry_run" == false ]]; then
        require_root "Removing files from $install_dir needs root."
    fi
    mapfile -t files <"$manifest_file"
    step "Uninstall from $install_dir"

    if [[ "$dry_run" == false && -f "$info" ]] && command -v install-info >/dev/null; then
        as_root install-info --delete --info-dir="$install_dir/share/info" "$info" 2>/dev/null || true
    fi

    for file in "${files[@]}"; do
        safe_entry "$file" || { warn "Ignoring unexpected manifest entry: $file"; continue; }
        if [[ "$dry_run" == true ]]; then
            printf '    %s-%s %s %s(dry run, not removed)%s\n' "$YELLOW" "$NC" "$file" "$DIM" "$NC"
        elif [[ -e "$file" || -L "$file" ]]; then
            as_root rm -f -- "$file"
            printf '    %s-%s %s\n' "$RED" "$NC" "$file"
        fi
    done
    [[ "$dry_run" == true ]] && return 0

    # Remove the directory this script owns, but only if it is now empty
    dir="$install_dir/share/$prog_name"
    if [[ -d "$dir" ]]; then
        as_root rmdir --ignore-fail-on-non-empty -- "$dir"
    fi
    if [[ -f "$install_dir/etc/wgetrc" ]]; then
        item "Config" "kept $install_dir/etc/wgetrc, delete it yourself if you no longer want it"
    fi
    item "Result" "${GREEN}wget has been uninstalled${NC}"
}

check_version() {
    local latest current
    latest="$(latest_version)" || fail "Could not get the release list from the GNU servers."
    current="$(installed_version)" || current=""
    step "Version check"
    item "Installed" "${current:-none} in $install_dir"
    item "Latest" "$latest"
    if [[ "$current" == "$latest" ]]; then
        item "Result" "${GREEN}up to date${NC}"
        return 0
    fi
    item "Result" "${YELLOW}update available${NC}, run: ${0##*/} -i $install_dir"
    return 10
}

# Other copies of wget earlier in PATH (conda, apt) will hide the new one.
# This looks at the PATH the script was started with, not the cleaned one.
path_report() {
    local first path ver
    local target="$install_dir/bin/$prog_name"

    first="$(PATH="$user_path"; type -P "$prog_name" || true)"
    step "wget in your PATH, in lookup order"
    while IFS= read -r path; do
        ver="$("$path" --version 2>/dev/null | head -n1 || true)"
        [[ "$ver" =~ ([0-9]+(\.[0-9]+)+) ]] && ver="${BASH_REMATCH[1]}"
        if [[ "$path" == "$target" ]]; then
            printf '    %s%-28s %-8s installed by this script%s\n' "$GREEN" "$path" "${ver:-unknown}" "$NC"
        else
            printf '    %-28s %s\n' "$path" "${ver:-unknown}"
        fi
    done < <( (PATH="$user_path"; type -aP "$prog_name" || true) | awk '!seen[$0]++')

    if [[ "$first" != "$target" ]]; then
        echo
        if [[ -n "$first" ]]; then
            warn "Running \"wget\" will start $first, not $target."
        else
            warn "$install_dir/bin is not in PATH."
        fi
        warn "Put the new one first by adding this to the end of ~/.bashrc:"
        warn "    export PATH=\"$install_dir/bin:\$PATH\""
        warn "or remove the copy that is ahead of it. Then run: hash -r"
    fi
}

# Versions 1.x of this script installed into /usr/local/programs/wget-VERSION
# with symlinks and an ld.so.conf.d entry. Point those out, but leave the
# decision to remove them to the user.
legacy_notice() {
    local -a found=()
    local item
    for item in /usr/local/programs/wget-* /etc/ld.so.conf.d/custom_wget.conf; do
        [[ -e "$item" ]] && found+=("$item")
    done
    [[ "${#found[@]}" -eq 0 ]] && return 0
    step "Leftovers from the old script"
    warn "Files from the old version of this script are still present:"
    for item in "${found[@]}"; do
        warn "    $item"
    done
    warn "They are no longer used. To remove them:"
    warn "    sudo rm -rf ${found[*]} && sudo ldconfig"
}

cleanup() {
    [[ -n "$tmp_manifest" ]] && rm -f -- "$tmp_manifest"
    [[ -n "$probe_dir" ]] && rm -rf -- "$probe_dir"
    [[ "$keep_build" == true ]] && return 0
    # Leave the directory first, since it may be the one being removed
    cd / 2>/dev/null || true
    if [[ "$made_temp_base" == true && -n "$build_base" ]]; then
        rm -rf -- "$build_base"
    elif [[ -n "$work_dir" && -d "$work_dir" ]]; then
        rm -rf -- "$work_dir"
        # A --build-directory that this run created is removed too, but only
        # if nothing else is in it. One that already existed is left alone.
        if [[ "$created_build_base" == true ]]; then
            rmdir -- "$build_base" 2>/dev/null || true
        fi
    fi
    [[ -n "$work_dir" && ! -e "$work_dir" ]] && item "Build files" "removed"
    return 0
}

main() {
    local current rc versions

    orig_args=("$@")
    parse_args "$@"

    case "$action" in
        list)
            versions="$(list_versions)" || fail "Could not get the release list from the GNU servers."
            step "Stable releases of wget"
            block "$(tr '\n' ' ' <<<"$versions")" | sed 's/^    //'
            exit 0
            ;;
        check)
            rc=0
            check_version || rc=$?
            exit "$rc"
            ;;
        uninstall) uninstall_wget; exit 0 ;;
        *)         ;;
    esac

    trap cleanup EXIT
    clean_environment
    set_compiler

    # The version lookup needs curl. On a bare system install the packages first.
    command -v curl >/dev/null || required_packages

    step "Prepare"
    if [[ -z "$version" ]]; then
        version="$(latest_version)" || fail "Could not get the release list from the GNU servers. Use --version to pick one."
        item "Version" "$version (latest stable release)"
    else
        item "Version" "$version"
    fi
    current="$(installed_version)" || current=""
    item "Installed" "${current:-none} in $install_dir"

    # Check this before touching APT so that repeat runs are fast and change nothing
    if [[ "$current" == "$version" && "$force" == false ]]; then
        item "Result" "${GREEN}already up to date${NC}, use --force to rebuild"
        path_report
        exit 0
    fi

    set_sudo
    # Fail now, before anything is downloaded or built
    if [[ -n "$SUDO" && "$dry_run" == false ]]; then
        require_root "Writing to $install_dir needs root."
    fi
    [[ "$install_dir" == "/usr" ]] && warn "Installing into /usr overwrites the files of the APT wget package."
    required_packages

    item "Compiler" "$CC"
    item "TLS library" "$ssl_backend"
    item "CPU target" "$([[ "$portable" == true ]] && echo "portable, any CPU of this architecture" || echo "native, tuned for this PC")"
    item "Options" "metalink: $use_metalink, translations: $use_nls, tests: $run_tests"

    if [[ "$dry_run" == true ]]; then
        item "Signature" "$([[ "$verify_sig" == true ]] && echo "will be checked with gpgv" || echo "will NOT be checked")"
        [[ -n "$SUDO" ]] && item "Needs sudo" "yes, to write to $install_dir"
        if command -v "$CC" >/dev/null; then
            select_flags
            show_flags
        else
            log "Compiler flags are chosen once $CC is installed."
        fi
        step "Dry run finished"
        log "Nothing was downloaded, built, or installed."
        exit 0
    fi

    require_commands


    if [[ -z "$build_base" ]]; then
        build_base="$(mktemp -d "${TMPDIR:-/tmp}/wget-build-script.XXXXXX")"
        made_temp_base=true
    else
        build_base="$(realpath -m -- "$build_base")"
        [[ -d "$build_base" ]] || created_build_base=true
        mkdir -p "$build_base"
    fi
    work_dir="$build_base/$prog_name-$version-build"
    src_dir="$work_dir/src"
    deps_dir="$work_dir/deps"
    stage_dir="$work_dir/stage"
    [[ -d "$work_dir" ]] && rm -rf -- "$work_dir"
    mkdir -p "$work_dir"

    download_wget
    select_flags
    show_flags
    step "Build"
    [[ "$use_metalink" == true ]] && build_libmetalink
    build_wget
    verify_binary
    [[ "$use_hardening" == true ]] && hardening_report
    [[ "$run_tests" == true ]] && run_test_suite
    install_wget

    path_report
    legacy_notice

    step "Done"
    item "Result" "${GREEN}wget $version installed${NC}${current:+ (replaced $current)} in ${SECONDS}s"
    item "Uninstall" "${0##*/} --uninstall -i $install_dir"
    [[ "$keep_build" == true ]] && item "Build files" "kept at $work_dir"
}

main "$@"
