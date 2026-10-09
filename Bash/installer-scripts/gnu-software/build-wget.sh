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
install_dir="/usr/local" compiler="gcc" ssl_backend="openssl" opt_level="2" action="install"
jobs="$(nproc 2>/dev/null || echo 2)"
version="" build_base="" mirror="" keyring_file=""
portable=false use_nls=false run_tests=false keep_build=false force=false dry_run=false assume_yes=false
use_lto=true use_hardening=true use_metalink=true verify_sig=true install_deps=true

# Working state
manifest_file="" work_dir="" src_dir="" deps_dir="" stage_dir="" probe_dir="" tmp_manifest=""
built_binary="" last_url="" user_path="$PATH"
made_temp_base=false created_build_base=false deps_checked=false needs_root=false
CC="" cc_base="" cc_suffix="" tool_prefix="" pkg_config="" pkg_config_path=""
cppflags="" cflags="" ldflags="" opt_cflags="" hard_cflags="" sys_cppflags="" fortify_flags=""
orig_args=() manifest=() skipped_flags=()

# Real escape characters, so messages can be printed with printf '%s' and
# backslashes inside paths are never interpreted. Color is used only on a
# terminal and is switched off by the NO_COLOR convention (https://no-color.org).
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    CYAN=$'\033[0;36m' GREEN=$'\033[0;32m' RED=$'\033[0;31m' YELLOW=$'\033[0;33m'
    BOLD=$'\033[1m' DIM=$'\033[2m' NC=$'\033[0m'
else
    CYAN='' GREEN='' RED='' YELLOW='' BOLD='' DIM='' NC=''
fi

# ---------------------------------------------------------------------------
# Output. A run is grouped into steps, with the lines under each one indented.
#   step     a new stage of the run
#   item     one "label   value" line, labels in a fixed-width column
#   heading  the title of a sub-list, and block: its text wrapped to 80 columns
#   mark     one file line with a colored +/- in front
#   log      a plain line, warn: something to look at, fail: stop with an error
# ---------------------------------------------------------------------------
step()    { printf '\n%s==>%s %s%s%s\n' "$CYAN$BOLD" "$NC" "$BOLD" "$*" "$NC"; }
log()     { printf '    %s\n' "$*"; }
item()    { printf '    %s%-13s%s %s\n' "$CYAN" "$1" "$NC" "$2"; }
heading() { printf '    %s%s%s\n' "$CYAN" "$1" "$NC"; }
block()   { fold -s -w 68 <<<"$1" | sed 's/[[:space:]]*$//; s/^/        /'; }
mark()    { printf '    %s%s%s %s\n' "$1" "$2" "$NC" "$3"; }
warn()    { printf '    %s[WARN]%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
fail()    { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

trap 'fail "Command failed on line $LINENO: $BASH_COMMAND"' ERR

# item_wrapped LABEL TEXT prints a long value across several lines, with the
# continuation lines lined up under the first
item_wrapped() {
    local label="$1" line
    while IFS= read -r line; do
        if [[ -n "$label" ]]; then item "$label" "$line"; else printf '%18s%s\n' "" "$line"; fi
        label=""
    done < <(fold -s -w 58 <<<"$2" | sed 's/[[:space:]]*$//')
}

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

# ---------------------------------------------------------------------------
# Options. This one table drives both the command line parser and the help
# screen, so an option is described in exactly one place.
#   short | long | VALUE (only if it takes one) | what to set | help lines...
# A line starting with "#" is a section title. A help line starting with "@"
# is shown as the default. The table is read once, before any option is
# applied, so the defaults in the help are the real defaults.
# ---------------------------------------------------------------------------
opt_table="$(cat <<EOF
#INSTALL LOCATION
-i|--install-directory|DIR|install_dir|Install prefix, relative or absolute.|The binary goes in DIR/bin, the man and info|pages in DIR/share, and the sample config|in DIR/etc/wgetrc.|@$install_dir
#VERSION
-v|--version|VERSION|version|Build a specific release, such as 1.24.5.|@latest stable
-l|--list||action=list|List the available releases.
|--check||action=check|Compare the version installed in DIR with|the latest release. Exit status is 0 when|up to date and 10 when an update exists.
#BUILD
-c|--compiler|NAME|compiler|gcc or clang, or an exact name such as|gcc-14 or clang-18.|@$compiler
-S|--ssl|BACKEND|ssl_backend|TLS library: openssl or gnutls.|@$ssl_backend
-O|--optimize|LEVEL|opt_level|Optimization level: 2, 3, or s (size).|@$opt_level
-p|--portable||portable=true|Build a binary that runs on any CPU of the|same architecture. Without this the build|uses -march=native, which is tuned for this|PC and may not run on others.
|--no-lto||use_lto=false|Turn off link time optimization.
|--no-hardening||use_hardening=false|Turn off the security hardening flags.
|--no-metalink||use_metalink=false|Build without Metalink support. Skips the|libmetalink build.
|--nls||use_nls=true|Include translations. The default build is|English only.
-j|--jobs|N|jobs|Parallel build jobs.|@$jobs
-t|--run-tests||run_tests=true|Run the upstream test suite and install only|if it passes. Adds several minutes.
-b|--build-directory|DIR|build_base|Where to download and compile.|@a new temporary directory
-k|--keep-build||keep_build=true|Keep the build directory when finished.
#DOWNLOAD
-m|--mirror|URL|mirror|GNU mirror to try first, for example|https://mirrors.kernel.org/gnu|@$gnu_mirror
|--keyring|FILE|keyring_file|Verify the signature with this binary GPG|keyring instead of downloading the GNU one.
|--skip-verify||verify_sig=false|Do not check the GPG signature of the wget|tarball. Not recommended.
#BEHAVIOR
-f|--force||force=true|Rebuild even if that version is already|installed in DIR.
-y|--yes||assume_yes=true|Do not prompt (passes -y to apt).
|--no-deps||install_deps=false|Do not check for or install APT packages.
|--dry-run||dry_run=true|Show what would be done and change nothing.
-u|--uninstall||action=uninstall|Remove a previous install from DIR, using|the manifest it left behind.
-h|--help||action=help|Show this help.
EOF
)"

# Help output is kept within 80 columns. Option names are green, the values
# they take are cyan, section titles are bold yellow (color first, because the
# color code resets bold), and defaults are dim.
print_usage() {
    local -a f
    local flags pad line desc args
    printf '%s%s%s %sv%s%s\n%s\n' "$CYAN$BOLD" "build-wget.sh" "$NC" "$DIM" "$script_ver" "$NC" \
        "Build and install GNU Wget from source."
    printf '\n%sUSAGE%s\n  %s%s%s [%sOPTIONS%s]\n' "$YELLOW$BOLD" "$NC" "$BOLD" "${0##*/}" "$NC" "$CYAN" "$NC"

    while IFS='|' read -ra f; do
        if [[ "${f[0]}" == "#"* ]]; then
            printf '\n%s%s%s\n' "$YELLOW$BOLD" "${f[0]#"#"}" "$NC"
            continue
        fi
        if [[ -n "${f[0]}" ]]; then flags="${f[0]}, ${f[1]}"; else flags="    ${f[1]}"; fi
        pad=$(( 30 - ${#flags} - ${#f[2]} ))
        [[ -n "${f[2]}" ]] && pad=$(( pad - 1 ))
        (( pad < 2 )) && pad=2
        printf '  %s%s%s%s%*s%s\n' "$GREEN" "$flags" "$NC" "${f[2]:+ $CYAN${f[2]}$NC}" "$pad" "" "${f[4]}"
        for line in "${f[@]:5}"; do
            [[ "$line" == "@"* ]] && line="${DIM}[default: ${line#@}]${NC}"
            printf '%32s%s\n' "" "$line"
        done
    done <<<"$opt_table"

    printf '\n%sEXAMPLES%s\n' "$YELLOW$BOLD" "$NC"
    while IFS='|' read -r desc args; do
        printf '  %s# %s%s\n  %s%s%s%s\n\n' "$DIM" "$desc" "$NC" "$BOLD" "${0##*/}" "$NC" "${args:+ $args}"
    done <<'EOF'
Latest release into /usr/local|
Per-user install, no sudo needed|-i "$HOME/.local"
Build with clang and GnuTLS, then run the tests|-c clang -S gnutls -t
A binary you can copy to other PCs|-p -i ./wget-portable
See whether an update is available|--check -i /usr/local
Uninstall|-u -i /usr/local
EOF
    printf '%sColor is disabled when output is not a terminal or NO_COLOR is set.%s\n' "$DIM" "$NC"
}

parse_args() {
    local arg short long value target rest key
    local -A takes=() sets=()

    while IFS='|' read -r short long value target rest; do
        [[ -n "$long" ]] || continue
        for key in ${short:+"$short"} "$long"; do
            takes[$key]="$value"
            sets[$key]="$target"
        done
    done <<<"$opt_table"

    while (( $# )); do
        # Accept both "--option value" and "--option=value"
        if [[ "$1" == --*=* ]]; then
            arg="$1"
            shift
            set -- "${arg%%=*}" "${arg#*=}" "$@"
        fi
        case "$1" in
            -h|--help) print_usage; exit 0 ;;
            -O[23s])   opt_level="${1#-O}"; shift; continue ;;
            -j[0-9]*)  jobs="${1#-j}"; shift; continue ;;
            *)         ;;
        esac
        [[ -n "$1" && -n "${sets[$1]+known}" ]] || fail "Invalid option: $1 (use --help to see the options)"
        if [[ -n "${takes[$1]}" ]]; then
            [[ $# -ge 2 && -n "$2" ]] || fail "Option $1 requires a value."
            [[ "$2" != -* ]] || fail "Option $1 requires a value, but got another option: $2"
            declare -g "${sets[$1]}=$2"
            shift 2
        else
            declare -g "${sets[$1]}"
            shift
        fi
    done
    version="${version#v}" mirror="${mirror%/}"

    [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail "--jobs must be a positive integer, got: $jobs"
    [[ -z "$version" || "$version" =~ $version_regex ]] || fail "--version must look like 1.25.0, got: $version"
    [[ "$ssl_backend" =~ ^(openssl|gnutls)$ ]] || fail "--ssl must be openssl or gnutls, got: $ssl_backend"
    [[ "$opt_level" =~ ^[23s]$ ]] || fail "--optimize must be 2, 3, or s, got: $opt_level"
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

# ---------------------------------------------------------------------------
# Environment, privileges, and packages
# ---------------------------------------------------------------------------

# Build with the system toolchain only. An active conda or similar environment
# puts its own compilers, pkg-config, and libraries ahead of the system ones
# and exports search paths that would silently link wget against them.
# /usr/local is left out of PATH on purpose: tools built from source and
# installed there (a pkg-config that does not know Ubuntu's library
# directories, for example) would replace the system ones. A compiler that
# lives there can still be selected by giving --compiler its full path.
setup_toolchain() {
    PATH="/usr/sbin:/usr/bin:/sbin:/bin"
    export PATH
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LIBS CPATH C_INCLUDE_PATH LIBRARY_PATH \
          LD_LIBRARY_PATH PKG_CONFIG_PATH PKG_CONFIG_LIBDIR AR RANLIB NM

    # Wget is written in C, so only a C compiler is needed
    case "$compiler" in
        g++|g++-*)         CC="gcc${compiler#g++}" ;;
        clang++|clang++-*) CC="clang${compiler#clang++}" ;;
        *)                 CC="$compiler" ;;
    esac
    # Link time optimization needs the archive tools that match the compiler,
    # for example gcc-ar-14 for gcc-14 and llvm-ar-18 for clang-18
    cc_base="${CC##*/}"
    [[ "$cc_base" =~ -[0-9.]+$ ]] && cc_suffix="${BASH_REMATCH[0]}"
    if [[ "$cc_base" == clang* ]]; then tool_prefix="llvm-"; else tool_prefix="gcc-"; fi
}

multiarch() {
    "$CC" -print-multiarch 2>/dev/null || dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true
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

# check_prefix_access MESSAGE: root is only needed when the prefix is not
# writable by the current user. A dry run notes it and carries on.
check_prefix_access() {
    local probe="$install_dir"
    while [[ ! -e "$probe" ]]; do
        probe="$(dirname "$probe")"
    done
    [[ -w "$probe" ]] && return 0
    [[ "$EUID" -ne 0 ]] || fail "$probe is not writable, even as root."
    needs_root=true
    [[ "$dry_run" == true ]] || require_root "$1"
}

fetch()  { curl -fsSL --connect-timeout 15 --retry 3 --retry-delay 2 "$@"; }
sha256() { sha256sum "$1" | cut -d' ' -f1; }

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
    local -a pkgs missing=() apt_opts=()
    local pkg

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
    case "$cc_base" in
        clang*) pkgs+=("clang$cc_suffix" "lld$cc_suffix" "llvm$cc_suffix") ;;
        gcc-*)  pkgs+=("$cc_base") ;;
        *)      ;;
    esac

    command -v dpkg-query >/dev/null || { warn "dpkg not found, skipping the package check."; return 0; }
    for pkg in "${pkgs[@]}"; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed" || missing+=("$pkg")
    done
    [[ "${#missing[@]}" -eq 0 ]] && return 0

    item_wrapped "APT packages" "missing: ${missing[*]}"
    if [[ "$dry_run" == true ]]; then
        log "Dry run, so they were not installed."
        return 0
    fi
    require_root "Installing the missing APT packages needs root: ${missing[*]}"
    [[ "$assume_yes" == true ]] && apt_opts+=(-y)
    apt-get update
    apt-get install "${apt_opts[@]}" "${missing[@]}"
}

# Fail early with a clear message instead of halfway through the build
require_commands() {
    local cmd arch
    local -a cmds=("$CC" make curl tar strip pod2man)
    [[ "$verify_sig" == true ]] && cmds+=(gpgv)
    [[ "$use_metalink" == true ]] && cmds+=(xz sha256sum)
    for cmd in "${cmds[@]}"; do
        command -v "$cmd" >/dev/null || fail "Required command not found: $cmd"
    done

    # Ubuntu keeps its .pc files in a per-architecture directory that a
    # pkg-config built from source does not search. Use the system pkg-config
    # by its full path, and name the system directories as well so that any
    # pkg-config finds the APT development packages.
    pkg_config="/usr/bin/pkg-config"
    [[ -x "$pkg_config" ]] || pkg_config="$(command -v pkg-config || true)"
    [[ -n "$pkg_config" ]] || fail "Required command not found: pkg-config"
    arch="$(multiarch)"
    pkg_config_path="${arch:+/usr/lib/$arch/pkgconfig:}/usr/lib/pkgconfig:/usr/share/pkgconfig"
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
    local lto="" linker="" arch dir

    probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/wget-flag-probe.XXXXXX")"
    printf '#include <stdlib.h>\n#include <limits.h>\n#include <stdio.h>\nint main(void) { return 0; }\n' >"$probe_dir/probe.c"
    probe || fail "The compiler $CC cannot build a simple program."

    cppflags="" cflags="" ldflags="" opt_cflags="" hard_cflags="" sys_cppflags="" fortify_flags=""
    skipped_flags=()

    # --- System headers first. The compiler normally reads /usr/local/include
    # before /usr/include, so a library built from source and installed there
    # (GNU libiconv is a common one) replaces the system header and drags its
    # own library into the link. Naming the system directories by their full
    # path puts them first. If a directory does not exist, or the compiler
    # cannot build with it named this way, the normal search order is kept.
    arch="$(multiarch)"
    for dir in ${arch:+"/usr/include/$arch"} /usr/include; do
        [[ -d "$dir" ]] || continue
        # shellcheck disable=SC2086  # the flags are meant to split into words
        if probe $sys_cppflags -isystem "$dir"; then
            sys_cppflags+="${sys_cppflags:+ }-isystem $dir"
        fi
    done

    # --- Link time optimization: lets the compiler optimize across all source
    # files at once. GCC uses its own linker plugin. Clang needs the lld linker.
    if [[ "$use_lto" == true ]]; then
        if [[ "$cc_base" == clang* ]]; then lto="-flto" linker="-fuse-ld=lld"; else lto="-flto=auto"; fi
        if ! command -v "${tool_prefix}ar$cc_suffix" >/dev/null || ! command -v "${tool_prefix}ranlib$cc_suffix" >/dev/null; then
            warn "LTO turned off: ${tool_prefix}ar$cc_suffix and ${tool_prefix}ranlib$cc_suffix were not found."
            lto="" linker=""
        elif ! probe $lto $linker; then
            warn "LTO turned off: $CC could not link a test program with $lto $linker."
            lto="" linker=""
        fi
    fi

    # --- Optimization. Each function and data item goes in its own section so
    # the linker can drop the ones wget never uses, and library calls skip the PLT.
    opt_cflags="-O$opt_level -pipe"
    if [[ "$portable" == true ]]; then
        add_flags opt_cflags "" "-mtune=generic"
    else
        add_flags opt_cflags "" "-march=native"
    fi
    opt_cflags+="${lto:+ $lto}"
    add_flags opt_cflags "" "-ffunction-sections -fdata-sections" "-fno-plt"
    ldflags="$lto${linker:+ $linker}"
    add_flags ldflags "$linker" "-Wl,-O1" "-Wl,--gc-sections" "-Wl,--as-needed" "-Wl,--no-copy-dt-needed-entries"

    # --- Hardening, following the OpenSSF Compiler Options Hardening Guide
    # for C and C++ (https://best.openssf.org/Compiler-Hardening-Guides/).
    # The guide's warning options are left out because they do not change the
    # binary, and -fstrict-flex-arrays=3 is left out because it can turn
    # legacy trailing arrays in third party code into runtime aborts.
    if [[ "$use_hardening" == true ]]; then
        # Bounds checks in libc calls. Undefine first so a distribution
        # default does not cause a redefinition warning.
        fortify_flags="-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3"
        add_flags hard_cflags "$linker" \
            "-fstack-protector-strong" "-fstack-clash-protection" "-fPIE -pie" \
            "-ftrivial-auto-var-init=zero" "-fzero-call-used-regs=used-gpr" \
            "-fno-delete-null-pointer-checks" "-fno-strict-overflow" "-fno-strict-aliasing"
        # -fPIE belongs to the compiler and -pie to the linker
        if [[ " $hard_cflags " == *" -fPIE -pie "* ]]; then
            hard_cflags="${hard_cflags/-fPIE -pie/-fPIE}"
            ldflags+="${ldflags:+ }-pie"
        fi
        # Control flow protection is specific to the CPU architecture
        case "$(uname -m)" in
            x86_64)  add_flags hard_cflags "" "-fcf-protection=full" ;;
            aarch64) add_flags hard_cflags "" "-mbranch-protection=standard" ;;
            *)       ;;
        esac
        add_flags ldflags "$linker" "-Wl,-z,relro" "-Wl,-z,now" "-Wl,-z,noexecstack" "-Wl,-z,nodlopen"
    fi

    cflags="$opt_cflags${hard_cflags:+ $hard_cflags}"
    cppflags="$sys_cppflags${fortify_flags:+${sys_cppflags:+ }$fortify_flags}"
    rm -rf -- "$probe_dir"
    probe_dir=""
}

show_flags() {
    local i
    local -a groups=(
        "Optimization"         "$opt_cflags"
        "Hardening"            "$fortify_flags${hard_cflags:+ $hard_cflags}"
        "System headers first" "$sys_cppflags"
        "Linker"               "${ldflags:-(none)}"
    )
    step "Compiler flags ($CC)"
    for (( i = 0; i < ${#groups[@]}; i += 2 )); do
        [[ -n "${groups[i+1]}" ]] || continue
        heading "${groups[i]}"
        block "${groups[i+1]}"
    done
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
    local name="$prog_name-$version.tar.gz"
    local tarball="$work_dir/$name" keyring="${keyring_file:-$work_dir/gnu-keyring.gpg}"

    step "Download and verify"
    download_gnu "$name" "$tarball" \
        || fail "Could not download wget $version. Run ${0##*/} --list to see the valid versions."
    item "Tarball" "$last_url"
    item "SHA-256" "$(sha256 "$tarball")"

    if [[ "$verify_sig" == true ]]; then
        download_gnu "$name.sig" "$tarball.sig" \
            || fail "Could not download the signature for wget $version. Use --skip-verify to build without checking it."
        # The keyring always comes from the GNU master site over HTTPS, never
        # from a mirror, because it is what the mirrors are checked against
        [[ -n "$keyring_file" ]] || fetch -o "$keyring" "$keyring_url" \
            || fail "Could not download $keyring_url. Use --keyring FILE or --skip-verify."
        # This is the command documented at https://ftp.gnu.org/
        # --homedir keeps gpgv from creating ~/.gnupg
        gpgv --homedir "$work_dir" --keyring "$keyring" "$tarball.sig" "$tarball" 2>"$work_dir/gpgv.log" || {
            cat "$work_dir/gpgv.log" >&2
            fail "GPG signature check FAILED for $name. The file was not used."
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
        printf '%s\n' "AR=${tool_prefix}ar$cc_suffix" "RANLIB=${tool_prefix}ranlib$cc_suffix" "NM=${tool_prefix}nm$cc_suffix"
    fi
}

build_libmetalink() {
    local tarball="$work_dir/libmetalink-$metalink_ver.tar.xz" dir="$work_dir/libmetalink" sum
    local -a vars

    fetch -o "$tarball" "$metalink_url" || fail "Could not download $metalink_url"
    sum="$(sha256 "$tarball")"
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
    local pc_path="$deps_dir/lib/pkgconfig:$pkg_config_path"
    local -a vars args

    mapfile -t vars < <(configure_vars)
    args=(
        --prefix="$install_dir"
        # Unknown options are an error, not a warning that scrolls past
        --enable-option-checking=fatal
        --disable-dependency-tracking
        --with-ssl="$ssl_backend"
        --with-cares
        # glibc already provides iconv and gettext. Do not go looking in the
        # install prefix for separate copies, and never bake a library search
        # path into the binary.
        --without-libiconv-prefix
        --without-libintl-prefix
        --disable-rpath
    )
    if [[ "$use_nls" == true ]]; then args+=(--enable-nls); else args+=(--disable-nls); fi
    if [[ "$use_metalink" == true ]]; then
        # A static libmetalink does not pull in expat by itself, so ask
        # pkg-config for the complete static link line
        args+=(
            --with-metalink
            "METALINK_CFLAGS=$(PKG_CONFIG_PATH="$pc_path" "$pkg_config" --cflags libmetalink)"
            "METALINK_LIBS=$(PKG_CONFIG_PATH="$pc_path" "$pkg_config" --static --libs libmetalink)"
        )
    else
        args+=(--without-metalink)
    fi

    mkdir -p "$src_dir/build"
    cd "$src_dir/build"
    run_task "Configure wget $version" "$work_dir/wget-configure.log" ../configure "${args[@]}" "${vars[@]}"
    run_task "Compile wget ($jobs jobs)" "$work_dir/wget-build.log" make -j"$jobs"
    built_binary="$src_dir/build/src/$prog_name"
    [[ -x "$built_binary" ]] || fail "The build finished but $built_binary was not found."
}

# Check the version and that every feature that was asked for is really in
# the binary. configure can quietly leave a feature out when a library is
# missing, and this is where that gets caught. Then report any shared library
# that would be loaded from outside the system directories, and any search
# path baked into the binary. Either one means the build picked up something
# from /usr/local or similar.
verify_binary() {
    local out flat feature outside runpath lib
    local -a expected=("+https" "+ssl/$ssl_backend" "+ipv6" "+iri" "+psl" "+cares" "+large-file" "+digest")
    [[ "$use_metalink" == true ]] && expected+=("+metalink")
    [[ "$use_nls" == true ]] && expected+=("+nls")

    step "Check the new binary"
    out="$("$built_binary" --version)" || fail "The new binary does not run."
    [[ "$(head -n1 <<<"$out")" == "GNU Wget $version "* ]] \
        || fail "Built binary reports \"$(head -n1 <<<"$out")\", expected version $version."
    flat=" $(tr '\n' ' ' <<<"$out") "
    for feature in "${expected[@]}"; do
        [[ "$flat" == *" $feature "* ]] || fail "The new binary is missing the feature $feature. Nothing was installed. Run again with --keep-build and see wget-configure.log."
    done
    item "Version" "$version"
    item_wrapped "Features" "${expected[*]}"

    outside="$(ldd "$built_binary" 2>/dev/null | awk '$3 ~ /^\// && $3 !~ /^\/(usr\/)?lib(64)?\// { print $3 }' || true)"
    runpath="$(readelf -dW "$built_binary" 2>/dev/null | grep -oP '(RPATH|RUNPATH).*\[\K[^]]+' || true)"
    if [[ -z "$outside$runpath" ]]; then
        item "Libraries" "${GREEN}all from the system${NC}, no search path baked in"
    fi
    for lib in $outside; do
        warn "Links against a library outside the system directories: $lib"
    done
    if [[ -n "$runpath" ]]; then
        warn "Has a library search path baked in: $runpath"
    fi
}

# Read the hardening properties back out of the finished binary. Each row is
# "label ; readelf option ; pattern that proves the protection is present".
hardening_report() {
    local label opt regex out rows
    command -v readelf >/dev/null || return 0
    rows='Position independent (PIE);-h;Type:[[:space:]]+DYN
Read-only relocations (RELRO);-l;GNU_RELRO
Immediate binding (BIND_NOW);-d;BIND_NOW|[[:space:]]NOW
Non-executable stack;-l;GNU_STACK.*RW[[:space:]]
Stack protector;--dyn-syms;__stack_chk_fail
Fortified libc calls;--dyn-syms;_chk(@|$)'
    case "$(uname -m)" in
        x86_64)  rows+=$'\nControl flow protection (CET);-n;IBT.*SHSTK|SHSTK.*IBT' ;;
        aarch64) rows+=$'\nBranch protection (BTI, PAC);-n;BTI.*PAC|PAC.*BTI' ;;
        *)       ;;
    esac

    heading "Hardening found in the binary"
    while IFS=';' read -r label opt regex; do
        out="$(readelf "$opt" -W "$built_binary" 2>/dev/null || true)"
        if grep -qE -- "$regex" <<<"$out"; then
            printf '        %-34s %syes%s\n' "$label" "$GREEN" "$NC"
        else
            printf '        %-34s %sNO%s\n' "$label" "$RED" "$NC"
        fi
    done <<<"$rows"
}

run_test_suite() {
    local summary
    step "Test suite"
    cd "$src_dir/build"
    run_task "Run the upstream tests (several minutes)" "$work_dir/wget-check.log" make -j"$jobs" check
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

# info_index [--delete] adds wget to, or removes it from, the shared index of info pages
info_index() {
    local info="$install_dir/share/info/$prog_name.info"
    if [[ -f "$info" ]] && command -v install-info >/dev/null; then
        install-info "$@" --info-dir="${info%/*}" "$info" 2>/dev/null || true
    fi
}

install_wget() {
    local root="$stage_dir$install_dir" src rel dest mode file stale=0 config_note=""
    local -a old_files=()
    local -A new_set=()

    # "make install" into a staging directory first. This gives an exact list
    # of what wget installs, so only finished files are copied into the prefix.
    step "Install into $install_dir"
    cd "$src_dir/build"
    run_task "Stage the files" "$work_dir/wget-install.log" make install-strip DESTDIR="$stage_dir"
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
                    install -D -m 0644 "$src" "$dest"
                    config_note="installed the sample $dest"
                fi
                continue
                ;;
            *)  ;;
        esac
        if [[ -x "$src" ]]; then mode=0755; else mode=0644; fi
        install -D -m "$mode" "$src" "$dest"
        manifest+=("$dest")
        new_set["$dest"]=1
    done < <(find "$root" \( -type f -o -type l \) -print0 | sort -z)
    manifest+=("$manifest_file")
    new_set["$manifest_file"]=1
    info_index

    # Remove files from the earlier install that this one no longer provides,
    # so an upgrade or a change of options leaves nothing orphaned
    for file in "${old_files[@]}"; do
        if safe_entry "$file" && [[ -z "${new_set["$file"]:-}" && ( -f "$file" || -L "$file" ) ]]; then
            rm -f -- "$file"
            stale=$(( stale + 1 ))
        fi
    done

    # List what was installed. Translations run to dozens of files, so past
    # the first few only the count is shown.
    for file in "${manifest[@]:0:8}"; do
        mark "$GREEN" "+" "$file"
    done
    (( ${#manifest[@]} > 8 )) && log "  and $(( ${#manifest[@]} - 8 )) more, all listed in $manifest_file"
    [[ -n "$config_note" ]] && item "Config" "$config_note"
    (( stale > 0 )) && item "Cleaned up" "$stale files from the previous install that this one does not provide"

    tmp_manifest="$(mktemp)"
    printf '%s\n' "${manifest[@]}" >"$tmp_manifest"
    install -D -m 0644 "$tmp_manifest" "$manifest_file"
}

uninstall_wget() {
    local file dir="$install_dir/share/$prog_name"
    local -a files=()

    [[ -f "$manifest_file" ]] || fail "No manifest at $manifest_file. This script did not install wget into $install_dir, so nothing was removed."
    check_prefix_access "Removing files from $install_dir needs root."
    mapfile -t files <"$manifest_file"
    step "Uninstall from $install_dir"

    [[ "$dry_run" == true ]] || info_index --delete
    for file in "${files[@]}"; do
        safe_entry "$file" || { warn "Ignoring unexpected manifest entry: $file"; continue; }
        if [[ "$dry_run" == true ]]; then
            mark "$YELLOW" "-" "$file $DIM(dry run, not removed)$NC"
        elif [[ -e "$file" || -L "$file" ]]; then
            rm -f -- "$file"
            mark "$RED" "-" "$file"
        fi
    done
    [[ "$dry_run" == true ]] && return 0

    # Remove the directory this script owns, but only if it is now empty
    if [[ -d "$dir" ]]; then
        rmdir --ignore-fail-on-non-empty -- "$dir"
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
    local first path ver target="$install_dir/bin/$prog_name"

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
    local path
    for path in /usr/local/programs/wget-* /etc/ld.so.conf.d/custom_wget.conf; do
        [[ -e "$path" ]] && found+=("$path")
    done
    [[ "${#found[@]}" -eq 0 ]] && return 0
    step "Leftovers from the old script"
    warn "Files from the old version of this script are still present:"
    for path in "${found[@]}"; do
        warn "    $path"
    done
    warn "They are no longer used. To remove them:"
    warn "    sudo rm -rf ${found[*]} && sudo ldconfig"
}

cleanup() {
    [[ -n "$tmp_manifest" ]] && rm -f -- "$tmp_manifest"
    [[ -n "$probe_dir" ]] && rm -rf -- "$probe_dir"
    [[ "$keep_build" == true || -z "$work_dir" ]] && return 0
    # Leave the directory first, since it may be the one being removed
    cd / 2>/dev/null || true
    if [[ "$made_temp_base" == true ]]; then
        rm -rf -- "$build_base"
    else
        rm -rf -- "$work_dir"
        # A --build-directory that this run created is removed too, but only
        # if nothing else is in it. One that already existed is left alone.
        if [[ "$created_build_base" == true ]]; then
            rmdir -- "$build_base" 2>/dev/null || true
        fi
    fi
    [[ -e "$work_dir" ]] || item "Build files" "removed"
    return 0
}

main() {
    local current versions

    orig_args=("$@")
    parse_args "$@"

    case "$action" in
        list)
            versions="$(list_versions)" || fail "Could not get the release list from the GNU servers."
            step "Stable releases of wget"
            block "$(tr '\n' ' ' <<<"$versions")" | sed 's/^    //'
            exit 0
            ;;
        check)     check_version || exit "$?"; exit 0 ;;
        uninstall) uninstall_wget; exit 0 ;;
        *)         ;;
    esac

    trap cleanup EXIT
    setup_toolchain

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

    # Fail now, before anything is downloaded or built
    check_prefix_access "Writing to $install_dir needs root."
    [[ "$install_dir" == "/usr" ]] && warn "Installing into /usr overwrites the files of the APT wget package."
    required_packages

    item "Compiler" "$CC"
    item "TLS library" "$ssl_backend"
    item "CPU target" "$([[ "$portable" == true ]] && echo "portable, any CPU of this architecture" || echo "native, tuned for this PC")"
    item "Options" "metalink: $use_metalink, translations: $use_nls, tests: $run_tests"

    if [[ "$dry_run" == true ]]; then
        item "Signature" "$([[ "$verify_sig" == true ]] && echo "will be checked with gpgv" || echo "will NOT be checked")"
        [[ "$needs_root" == true ]] && item "Needs sudo" "yes, to write to $install_dir"
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
    src_dir="$work_dir/src" deps_dir="$work_dir/deps" stage_dir="$work_dir/stage"
    rm -rf -- "$work_dir"
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
    if [[ "$keep_build" == true ]]; then
        item "Build files" "kept at $work_dir"
    fi
}

main "$@"
