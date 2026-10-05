#!/usr/bin/env bash

# Purpose: install or update CMake, Ninja, Meson, and Go
# Target:  Ubuntu 24.04 (works on other Debian/Ubuntu releases as well)
# Script version: 5.0
#
# How each tool is installed, following its own project's documentation:
#   CMake  built from the release tarball with ./bootstrap, after the tarball
#          is checked against Kitware's signed SHA-256 list.
#   Ninja  built from the release tag with upstream's configure.py.
#   Meson  installed with pip into its own virtual environment under the
#          prefix. Meson's documentation advises against a system-wide
#          "sudo pip install", and this keeps it away from the system Python.
#   Go     the official binary release, checked against the SHA-256 that
#          go.dev publishes, placed in PREFIX/go (the documented location is
#          /usr/local/go) and never unpacked over an existing tree.
#
# Every installed path is recorded in a manifest per tool, so an upgrade
# removes the files the new version no longer ships and --uninstall removes
# exactly what was installed.

set -Eeuo pipefail

script_ver="5.0"
all_tools="ninja cmake meson go"
version_regex='^[0-9]+(\.[0-9]+)+$'
# The key ID that https://cmake.org/download/ lists for release signatures
cmake_key_id="2D2CEF1034921684"

# Defaults (all can be changed with command line options)
install_dir="/usr/local" compiler="gcc" action="install"
jobs="$(nproc 2>/dev/null || echo 2)"
tools="" pins="" build_base=""
portable=false keep_build=false force=false dry_run=false assume_yes=false debug=false
use_lto=true use_hardening=true verify=true install_deps=true

# Working state
state_dir="" work_dir="" probe_dir="" user_path="$PATH"
made_temp_base=false created_build_base=false needs_root=false
CC="" CXX="" cc_base="" cc_suffix="" tool_prefix=""
cppflags="" cxxflags="" ldflags="" lto_flags=""
orig_args=() manifest=() skipped_flags=()
declare -A pin=() latest=() current=() plan=()

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
#   log      a plain line, warn: something to look at, fail: stop with an error
# ---------------------------------------------------------------------------
step()    { printf '\n%s==>%s %s%s%s\n' "$CYAN$BOLD" "$NC" "$BOLD" "$*" "$NC"; }
log()     { printf '    %s\n' "$*"; }
item()    { printf '    %s%-13s%s %s\n' "$CYAN" "$1" "$NC" "$2"; }
heading() { printf '    %s%s%s\n' "$CYAN" "$1" "$NC"; }
block()   { fold -s -w 68 <<<"$1" | sed 's/[[:space:]]*$//; s/^/        /'; }
warn()    { printf '    %s[WARN]%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
fail()    { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

trap 'fail "Command failed on line $LINENO: $BASH_COMMAND"' ERR

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
# is shown as the default. A row with no help lines is an alias kept for
# compatibility with earlier versions of this script, and is not shown.
# ---------------------------------------------------------------------------
opt_table="$(cat <<EOF
#WHAT TO INSTALL
-t|--tools|LIST|tools|Comma separated list of tools to work on:|cmake, ninja, meson, go.|@all four
|--pin|LIST|pins|Use a specific version instead of the latest,|for example cmake=4.3.2,go=1.25.1
-i|--install-directory|DIR|install_dir|Install prefix, relative or absolute.|Binaries go in DIR/bin, shared files in|DIR/share, and Go in DIR/go.|@$install_dir
|--check||action=check|Show installed and latest versions and stop.|Exit status is 0 when everything is up to|date and 10 when an update exists.
#BUILD
-c|--compiler|NAME|compiler|gcc or clang, or an exact name such as|gcc-14 or clang-18.|@$compiler
-p|--portable||portable=true|Build binaries that run on any CPU of the|same architecture. Without this the build|uses -march=native, which is tuned for this|PC and may not run on others.
|--no-lto||use_lto=false|Turn off link time optimization.
|--no-hardening||use_hardening=false|Turn off the security hardening flags.
-j|--jobs|N|jobs|Parallel build jobs.|@$jobs
-b|--build-directory|DIR|build_base|Where to download and compile.|@a new temporary directory
-k|--keep-build||keep_build=true|Keep the build directory when finished.
#BEHAVIOR
-f|--force||force=true|Reinstall even when the installed version is|already the wanted one.
-y|--yes||assume_yes=true|Do not prompt (passes -y to apt).
|--no-deps||install_deps=false|Do not check for or install APT packages.
|--skip-verify||verify=false|Do not check checksums and signatures of the|downloads. Not recommended.
|--dry-run||dry_run=true|Show what would be done and change nothing.
|--debug||debug=true|Print every shell command as it runs.
-u|--uninstall||action=uninstall|Remove the tools this script installed in|DIR (all of them, or those named by --tools).
-h|--help||action=help|Show this help.
|--latest||force=true
|--skip-deps||install_deps=false
|--no-cleanup||keep_build=true
EOF
)"

# Help output is kept within 80 columns. Option names are green, the values
# they take are cyan, section titles are bold yellow (color first, because the
# color code resets bold), and defaults are dim.
print_usage() {
    local -a f
    local flags pad line desc args
    printf '%s%s%s %sv%s%s\n%s\n' "$CYAN$BOLD" "build-tools.sh" "$NC" "$DIM" "$script_ver" "$NC" \
        "Install or update CMake, Ninja, Meson, and Go."
    printf '\n%sUSAGE%s\n  %s%s%s [%sOPTIONS%s]\n' "$YELLOW$BOLD" "$NC" "$BOLD" "${0##*/}" "$NC" "$CYAN" "$NC"

    while IFS='|' read -ra f; do
        if [[ "${f[0]}" == "#"* ]]; then
            printf '\n%s%s%s\n' "$YELLOW$BOLD" "${f[0]#"#"}" "$NC"
            continue
        fi
        (( ${#f[@]} > 4 )) || continue
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
Install or update all four tools in /usr/local|
See what is installed and what would change|--check
Only CMake and Ninja, built with clang|-t cmake,ninja -c clang
Per-user install, no sudo needed|-i "$HOME/.local"
Hold Go at one version and update the rest|--pin go=1.25.1
Remove Meson again|-u -t meson
EOF
    printf '%sColor is disabled when output is not a terminal or NO_COLOR is set.%s\n' "$DIM" "$NC"
}

parse_args() {
    local arg short long value target rest key tool entry
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

    [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail "--jobs must be a positive integer, got: $jobs"

    # Keep the tools in build order whatever order they were named in
    arg=" ${tools//,/ } "
    for tool in $arg; do
        [[ " $all_tools " == *" $tool "* ]] || fail "--tools: unknown tool \"$tool\". Choose from: ${all_tools// /, }"
    done
    if [[ -n "${arg// }" ]]; then
        tools=""
        for tool in $all_tools; do
            [[ "$arg" == *" $tool "* ]] && tools+="${tools:+ }$tool"
        done
    else
        tools="$all_tools"
    fi

    for entry in ${pins//,/ }; do
        tool="${entry%%=*}" value="${entry#*=}"
        value="${value#v}"
        [[ "$entry" == *=* && " $all_tools " == *" $tool "* && "$value" =~ $version_regex ]] \
            || fail "--pin entries must look like cmake=4.3.2, got: $entry"
        pin[$tool]="$value"
    done

    # Resolve the prefix to an absolute path. A quoted or =style "~" is not
    # expanded by the shell, so handle it here.
    # shellcheck disable=SC2088
    [[ "$install_dir" == "~" || "$install_dir" == "~/"* ]] && install_dir="$HOME${install_dir:1}"
    install_dir="$(realpath -m -- "$install_dir")"
    [[ "$install_dir" != "/" ]] || fail "Refusing to use / as the install prefix. Use /usr or /usr/local."
    [[ "$install_dir" != *[[:space:]]* ]] || fail "The install prefix cannot contain whitespace."
    state_dir="$install_dir/share/build-tools"
}

# ---------------------------------------------------------------------------
# Environment, privileges, and packages
# ---------------------------------------------------------------------------

# Build with the system toolchain only. An active conda or similar environment
# puts its own compilers and Python ahead of the system ones and exports search
# paths that would silently link the tools against its libraries. /usr/local is
# left out of PATH for the same reason. A compiler that lives elsewhere can
# still be selected by giving --compiler its full path.
setup_toolchain() {
    PATH="/usr/sbin:/usr/bin:/sbin:/bin"
    export PATH
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LIBS CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH \
          LIBRARY_PATH LD_LIBRARY_PATH AR RANLIB NM GOROOT CMAKE_GENERATOR CMAKE_PREFIX_PATH

    case "$compiler" in
        g++*)     CC="gcc${compiler#g++}" ;;
        clang++*) CC="clang${compiler#clang++}" ;;
        *)        CC="$compiler" ;;
    esac
    cc_base="${CC##*/}"
    [[ "$cc_base" =~ -[0-9.]+$ ]] && cc_suffix="${BASH_REMATCH[0]}"
    # The C++ compiler and archive tools that match, for example g++-14 and
    # gcc-ar-14 for gcc-14, clang++-18 and llvm-ar-18 for clang-18
    if [[ "$cc_base" == clang* ]]; then
        CXX="${CC%"$cc_base"}clang++$cc_suffix" tool_prefix="llvm-"
    else
        CXX="${CC%"$cc_base"}g++$cc_suffix" tool_prefix="gcc-"
    fi
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

wants()  { [[ " $tools " == *" $1 "* ]]; }
fetch()  { curl -fsSL --connect-timeout 15 --retry 3 --retry-delay 2 "$@"; }
sha256() { sha256sum "$1" | cut -d' ' -f1; }

required_packages() {
    local -a pkgs=(ca-certificates curl git tar gzip python3) missing=() apt_opts=()
    local pkg
    [[ "$install_deps" == true ]] || return 0

    if wants cmake || wants ninja; then
        pkgs+=(build-essential)
        case "$cc_base" in
            clang*) pkgs+=("clang$cc_suffix" "lld$cc_suffix" "llvm$cc_suffix") ;;
            gcc-*)  pkgs+=("$cc_base" "g++$cc_suffix") ;;
            *)      ;;
        esac
    fi
    # CMake bundles its other dependencies but not OpenSSL. gpgv and gnupg
    # check the signature on its checksum list.
    wants cmake && pkgs+=(libssl-dev gpgv gnupg)
    wants meson && pkgs+=(python3-venv)

    command -v dpkg-query >/dev/null || { warn "dpkg not found, skipping the package check."; return 0; }
    for pkg in "${pkgs[@]}"; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed" || missing+=("$pkg")
    done
    [[ "${#missing[@]}" -eq 0 ]] && return 0

    item "APT packages" "missing: ${missing[*]}"
    if [[ "$dry_run" == true ]]; then
        log "Dry run, so they were not installed."
        return 0
    fi
    require_root "Installing the missing APT packages needs root: ${missing[*]}"
    [[ "$assume_yes" == true ]] && apt_opts+=(-y)
    apt-get update
    apt-get install "${apt_opts[@]}" "${missing[@]}"
}

# ---------------------------------------------------------------------------
# Versions
# ---------------------------------------------------------------------------

# GitHub's /releases/latest page redirects to the release the maintainers
# marked as latest, which is never a release candidate. If it cannot be
# reached, fall back to the highest plain version tag.
github_latest() {
    local url tag
    url="$(curl -fsSLI --connect-timeout 15 -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" 2>/dev/null)" || url=""
    tag="${url##*/}"
    tag="${tag#v}"
    if [[ "$url" == */releases/tag/* && "$tag" =~ $version_regex ]]; then
        echo "$tag"
        return 0
    fi
    tag="$(git ls-remote --tags --refs "https://github.com/$1.git" 2>/dev/null | awk -F/ '{ sub(/^v/, "", $NF); print $NF }' \
        | grep -E "$version_regex" | sort -V | tail -n1)" || return 1
    echo "$tag"
}

latest_version() {
    case "$1" in
        cmake) github_latest "Kitware/CMake" ;;
        ninja) github_latest "ninja-build/ninja" ;;
        meson) fetch "https://pypi.org/pypi/meson/json" | python3 -c 'import json, sys; print(json.load(sys.stdin)["info"]["version"])' ;;
        go)    fetch "https://go.dev/dl/?mode=json" | python3 -c 'import json, sys; print(next(r["version"] for r in json.load(sys.stdin) if r["stable"])[2:])' ;;
        *)     return 1 ;;
    esac
}

# The version of TOOL that this prefix provides, or nothing
installed_version() {
    local bin="$install_dir/bin/$1" out
    [[ -x "$bin" ]] || return 0
    if [[ "$1" == go ]]; then
        out="$("$bin" version 2>/dev/null || true)"
    else
        out="$("$bin" --version 2>/dev/null | head -n1 || true)"
    fi
    [[ "$out" =~ ([0-9]+(\.[0-9]+)+) ]] && echo "${BASH_REMATCH[1]}"
    return 0
}

# Fill in latest, current, and plan for every selected tool and print the table
make_plan() {
    local tool color
    step "Version plan"
    printf '    %s%-8s %-14s %-14s %s%s\n' "$CYAN" "Tool" "Installed" "Wanted" "Action" "$NC"
    for tool in $tools; do
        current[$tool]="$(installed_version "$tool")"
        latest[$tool]="${pin[$tool]:-}"
        if [[ -z "${latest[$tool]}" ]]; then
            latest[$tool]="$(latest_version "$tool")" || fail "Could not find the latest version of $tool. Check the network, or use --pin $tool=VERSION."
        fi
        [[ "${latest[$tool]}" =~ $version_regex ]] || fail "Got an unusable version for $tool: ${latest[$tool]}"
        if [[ -z "${current[$tool]}" ]]; then
            plan[$tool]="install" color="$GREEN"
        elif [[ "${current[$tool]}" != "${latest[$tool]}" ]]; then
            plan[$tool]="update" color="$YELLOW"
        elif [[ "$force" == true ]]; then
            plan[$tool]="reinstall" color="$YELLOW"
        else
            plan[$tool]="keep" color="$DIM"
        fi
        printf '    %-8s %-14s %-14s %s%s%s\n' "$tool" "${current[$tool]:-none}" "${latest[$tool]}${pin[$tool]:+ (pin)}" "$color" "${plan[$tool]}" "$NC"
    done
}

# ---------------------------------------------------------------------------
# Compiler and linker flags (used for CMake and Ninja, which are C++)
# ---------------------------------------------------------------------------

# probe FLAGS... returns 0 if a test program compiles and links with them.
# -Werror and --fatal-warnings turn "unknown option, ignored" into a failure,
# which is how clang and the linkers report options they do not support.
probe() {
    "$CXX" -O2 -Werror -Wl,--fatal-warnings "$@" -o "$probe_dir/probe" "$probe_dir/probe.cc" >/dev/null 2>&1
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

# The optimization level is left to each project (both use -O3 for release
# builds). The hardening set follows the OpenSSF Compiler Options Hardening
# Guide for C and C++ (https://best.openssf.org/Compiler-Hardening-Guides/).
# Its warning options are left out because they do not change the binary, and
# -fstrict-flex-arrays=3 is left out because it can turn legacy trailing
# arrays in third party code into runtime aborts.
select_flags() {
    local linker="" hard=""

    probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/build-tools-probe.XXXXXX")"
    printf '#include <cstdlib>\n#include <string>\nint main() { return std::string("x").size() == 1 ? EXIT_SUCCESS : EXIT_FAILURE; }\n' >"$probe_dir/probe.cc"
    probe || fail "The compiler $CXX cannot build a simple C++ program."
    cppflags="" cxxflags="-pipe" ldflags="" lto_flags="" skipped_flags=()

    # Link time optimization lets the compiler optimize across all source
    # files at once. GCC uses its own linker plugin. Clang needs the lld linker.
    if [[ "$use_lto" == true ]]; then
        if [[ "$cc_base" == clang* ]]; then lto_flags="-flto" linker="-fuse-ld=lld"; else lto_flags="-flto=auto"; fi
        if ! command -v "${tool_prefix}ar$cc_suffix" >/dev/null || ! command -v "${tool_prefix}ranlib$cc_suffix" >/dev/null; then
            warn "LTO turned off: ${tool_prefix}ar$cc_suffix and ${tool_prefix}ranlib$cc_suffix were not found."
            lto_flags="" linker=""
        elif ! probe $lto_flags $linker; then
            warn "LTO turned off: $CXX could not link a test program with $lto_flags $linker."
            lto_flags="" linker=""
        fi
    fi

    if [[ "$portable" == true ]]; then
        add_flags cxxflags "" "-mtune=generic"
    else
        add_flags cxxflags "" "-march=native"
    fi
    # Each function and data item goes in its own section so the linker can
    # drop the unused ones, and library calls skip the PLT
    add_flags cxxflags "" "-ffunction-sections -fdata-sections" "-fno-plt"
    ldflags="$linker"
    add_flags ldflags "$linker" "-Wl,-O1" "-Wl,--gc-sections" "-Wl,--as-needed" "-Wl,--no-copy-dt-needed-entries"

    if [[ "$use_hardening" == true ]]; then
        # Bounds checks in libc and libstdc++ calls. Undefine first so a
        # distribution default does not cause a redefinition warning.
        cppflags="-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS"
        add_flags hard "$linker" \
            "-fstack-protector-strong" "-fstack-clash-protection" "-fPIE -pie" \
            "-ftrivial-auto-var-init=zero" "-fzero-call-used-regs=used-gpr" \
            "-fno-delete-null-pointer-checks" "-fno-strict-overflow" "-fno-strict-aliasing"
        # -fPIE belongs to the compiler and -pie to the linker
        if [[ " $hard " == *" -fPIE -pie "* ]]; then
            hard="${hard/-fPIE -pie/-fPIE}"
            ldflags+="${ldflags:+ }-pie"
        fi
        # Control flow protection is specific to the CPU architecture
        case "$(uname -m)" in
            x86_64)  add_flags hard "" "-fcf-protection=full" ;;
            aarch64) add_flags hard "" "-mbranch-protection=standard" ;;
            *)       ;;
        esac
        cxxflags+="${hard:+ $hard}"
        add_flags ldflags "$linker" "-Wl,-z,relro" "-Wl,-z,now" "-Wl,-z,noexecstack"
    fi

    rm -rf -- "$probe_dir"
    probe_dir=""

    step "Compiler flags ($CXX)"
    heading "Compile"
    block "${cppflags:+$cppflags }$cxxflags"
    heading "Link"
    block "${ldflags:-(none)}"
    heading "Link time optimization"
    block "${lto_flags:-off}"
    if [[ "${#skipped_flags[@]}" -gt 0 ]]; then
        printf '    %sLeft out, not supported by this toolchain%s\n' "$YELLOW" "$NC"
        block "${skipped_flags[*]}"
    fi
}

# Read the result back out of a finished binary: where its shared libraries
# come from, and which hardening features are really present. Each hardening
# row is "label ; readelf option ; pattern that proves it is present".
binary_report() {
    local bin="$1" outside runpath lib label opt regex out rows
    outside="$(ldd "$bin" 2>/dev/null | awk '$3 ~ /^\// && $3 !~ /^\/(usr\/)?lib(64)?\// { print $3 }' || true)"
    runpath="$(readelf -dW "$bin" 2>/dev/null | grep -oP '(RPATH|RUNPATH).*\[\K[^]]+' || true)"
    if [[ -z "$outside$runpath" ]]; then
        item "Libraries" "${GREEN}all from the system${NC}, no search path baked in"
    fi
    for lib in $outside; do
        warn "Links against a library outside the system directories: $lib"
    done
    if [[ -n "$runpath" ]]; then
        warn "Has a library search path baked in: $runpath"
    fi

    if [[ "$use_hardening" != true ]] || ! command -v readelf >/dev/null; then
        return 0
    fi
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
        out="$(readelf "$opt" -W "$bin" 2>/dev/null || true)"
        if grep -qE -- "$regex" <<<"$out"; then
            printf '        %-34s %syes%s\n' "$label" "$GREEN" "$NC"
        else
            printf '        %-34s %sNO%s\n' "$label" "$RED" "$NC"
        fi
    done <<<"$rows"
}

# ---------------------------------------------------------------------------
# Manifests. One file per tool lists every path it installed. A line ending
# in "/" is a whole directory that belongs to this script.
# ---------------------------------------------------------------------------

# Entries are only trusted if they sit under the prefix and contain no ".."
# component. A directory entry must also be one of the two this script owns.
safe_entry() {
    [[ "$1" == "$install_dir/"* && "$1" != *"/../"* && "$1" != *"/.." ]] || return 1
    [[ "$1" != */ || "$1" == "$install_dir/go/" || "$1" == "$install_dir/lib/build-tools/"*/ ]]
}

# remove_entries PATH... deletes manifest entries, then any directories that
# were left empty by it
remove_entries() {
    local entry
    local -a files=() dirs=()
    for entry in "$@"; do
        safe_entry "$entry" || { warn "Ignoring unexpected manifest entry: $entry"; continue; }
        if [[ "$entry" == */ ]]; then
            rm -rf -- "${entry%/}"
        else
            files+=("$entry")
        fi
        dirs+=("$(dirname "${entry%/}")")
    done
    (( ${#files[@]} == 0 )) || printf '%s\0' "${files[@]}" | xargs -0 rm -f --
    (( ${#dirs[@]} == 0 )) || printf '%s\0' "${dirs[@]}" | sort -zu | xargs -0 rmdir -p --ignore-fail-on-non-empty -- 2>/dev/null || true
}

# commit_manifest TOOL records the paths collected in the manifest array and
# removes whatever the previous install of TOOL had that this one does not
commit_manifest() {
    local file="$state_dir/$1.manifest" entry
    local -a old=() stale=()
    local -A keep=()
    [[ -f "$file" ]] && mapfile -t old <"$file"
    for entry in "${manifest[@]}"; do keep[$entry]=1; done
    for entry in "${old[@]}"; do
        [[ -n "${keep[$entry]:-}" ]] || stale+=("$entry")
    done
    if (( ${#stale[@]} > 0 )); then
        remove_entries "${stale[@]}"
        item "Cleaned up" "${#stale[@]} paths from the previous install that this one does not provide"
    fi
    mkdir -p "$state_dir"
    printf '%s\n' "${manifest[@]}" >"$file"
    item "Installed" "${#manifest[@]} paths, listed in $file"
    manifest=()
}

# install_tree ROOT merges a staged copy of the prefix into the real one. tar
# replaces existing files and symlinks instead of writing through them, and
# --no-overwrite-dir leaves the permissions of existing directories alone.
install_tree() {
    local root="$1" path
    mkdir -p "$install_dir"
    tar -C "$root" -cf - . | tar -C "$install_dir" -xf - --no-same-owner --no-overwrite-dir
    while IFS= read -r -d '' path; do
        manifest+=("$install_dir/${path#./}")
    done < <(cd "$root" && find . \( -type f -o -type l \) -print0 | sort -z)
}

uninstall_tools() {
    local tool file found=false
    local -a entries
    check_prefix_access "Removing files from $install_dir needs root."
    step "Uninstall from $install_dir"
    for tool in $tools; do
        file="$state_dir/$tool.manifest"
        [[ -f "$file" ]] || { item "$tool" "not installed by this script, nothing to remove"; continue; }
        found=true
        mapfile -t entries <"$file"
        if [[ "$dry_run" == true ]]; then
            item "$tool" "${YELLOW}would remove${NC} ${#entries[@]} paths (dry run)"
            continue
        fi
        remove_entries "${entries[@]}" "$file"
        item "$tool" "${GREEN}removed${NC}, ${#entries[@]} paths"
    done
    [[ "$found" == true ]] || log "Nothing in $install_dir was installed by this script."
}

# ---------------------------------------------------------------------------
# The four tools. Each install_TOOL VERSION function downloads, verifies,
# builds if needed, installs, and commits its manifest.
# ---------------------------------------------------------------------------

# get_source REPO VERSION DIR [RELEASE_FILE] unpacks a GitHub source tarball
# into DIR. Some proxies block archive downloads, so a shallow clone of the
# tag is the fallback.
get_source() {
    local repo="$1" ver="$2" dir="$3" url="https://github.com/$1/archive/refs/tags/v$2.tar.gz"
    [[ -z "${4:-}" ]] || url="https://github.com/$repo/releases/download/v$ver/$4"
    mkdir -p "$dir"
    if fetch -o "$dir.tar.gz" "$url" 2>/dev/null; then
        tar -xzf "$dir.tar.gz" -C "$dir" --strip-components 1 || fail "Failed to extract $dir.tar.gz"
        item "Source" "$url"
    else
        rm -f -- "$dir.tar.gz"
        git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v$ver" "https://github.com/$repo.git" "$dir" \
            || fail "Could not download $repo $ver."
        item "Source" "git tag v$ver (the archive download was not reachable)"
    fi
}

install_ninja() {
    local ver="$1" src="$work_dir/ninja" stage="$work_dir/ninja-stage" pair
    local -a env_vars=("CXX=$CXX" "CXXFLAGS=${cppflags:+$cppflags }$cxxflags${lto_flags:+ $lto_flags}" "LDFLAGS=${lto_flags:+$lto_flags }$ldflags")
    [[ -z "$lto_flags" ]] || env_vars+=("AR=${tool_prefix}ar$cc_suffix")

    # Upstream publishes no checksums or signatures for Ninja's source
    get_source "ninja-build/ninja" "$ver" "$src"
    cd "$src"
    run_task "Build ninja" "$work_dir/ninja.log" env -u CFLAGS "${env_vars[@]}" python3 ./configure.py --bootstrap
    [[ "$(./ninja --version)" == "$ver" ]] || fail "The new ninja reports version $(./ninja --version), expected $ver."

    # Run a real one-rule build before anything is installed
    mkdir -p smoke
    # shellcheck disable=SC2016  # $out is ninja syntax, not a shell variable
    printf 'rule touch\n  command = touch $out\nbuild out.txt: touch\n' >smoke/build.ninja
    ./ninja -C smoke >/dev/null && [[ -f smoke/out.txt ]] || fail "The new ninja failed a basic test build. Nothing was installed."
    item "Self test" "${GREEN}passed${NC}"
    binary_report "$src/ninja"

    # Upstream's install rule only copies the binary, so place the rest here.
    # Not every release ships every file, so missing ones are skipped.
    install -D -m 0755 -s ninja "$stage/bin/ninja"
    for pair in misc/bash-completion:share/bash-completion/completions/ninja misc/zsh-completion:share/zsh/site-functions/_ninja \
                misc/ninja.vim:share/vim/vimfiles/syntax/ninja.vim doc/manual.asciidoc:share/doc/ninja/manual.asciidoc \
                COPYING:share/doc/ninja/COPYING; do
        [[ ! -f "${pair%%:*}" ]] || install -D -m 0644 "${pair%%:*}" "$stage/${pair#*:}"
    done
    install_tree "$stage"
    commit_manifest ninja
}

# CMake's release page provides cmake-VERSION-SHA-256.txt and a detached
# signature for it. The tarball is always checked against the list. The
# signature on the list is checked when Kitware's key can be fetched from the
# keyserver the download page links to, and a bad signature is always fatal.
verify_cmake() {
    local dir="$1" ver="$2" base="https://github.com/Kitware/CMake/releases/download/v$2"
    local sums="$1/cmake-$2-SHA-256.txt" want key="$1/kitware.asc" out

    fetch -o "$sums" "$base/cmake-$ver-SHA-256.txt" || fail "Could not download the CMake checksum list. Use --skip-verify to build without it."
    want="$(awk -v f="cmake-$ver.tar.gz" '$2 == f { print $1 }' "$sums")"
    [[ -n "$want" && "$(sha256 "$dir/cmake.tar.gz")" == "$want" ]] || fail "SHA-256 mismatch for cmake-$ver.tar.gz. The file was not used."
    item "SHA-256" "${GREEN}matches${NC} Kitware's published list"

    if command -v gpg >/dev/null && command -v gpgv >/dev/null \
        && fetch -o "$sums.asc" "$base/cmake-$ver-SHA-256.txt.asc" 2>/dev/null \
        && fetch -o "$key" "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x$cmake_key_id" 2>/dev/null \
        && gpg --homedir "$dir" --batch --yes --dearmor -o "$dir/kitware.gpg" "$key" 2>/dev/null; then
        if out="$(gpgv --homedir "$dir" --keyring "$dir/kitware.gpg" "$sums.asc" "$sums" 2>&1)"; then
            item "Signature" "${GREEN}good${NC}, signed by $(grep -m1 -oP 'Good signature from "\K[^"]+' <<<"$out" || echo "Kitware's key $cmake_key_id")"
        elif grep -q "BAD signature" <<<"$out"; then
            fail "GPG signature check FAILED for the CMake checksum list. The file was not used."
        else
            item "Signature" "${YELLOW}not checked${NC}, the key from the keyserver did not match the signature"
        fi
    else
        item "Signature" "${YELLOW}not checked${NC}, could not get key $cmake_key_id from keyserver.ubuntu.com"
    fi
}

install_cmake() {
    local ver="$1" src="$work_dir/cmake" stage="$work_dir/cmake-stage" flags="${cppflags:+$cppflags }$cxxflags"
    local -a cmake_args=(-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DCMAKE_USE_OPENSSL=ON)
    # Use CMake's own switch for LTO, and the system OpenSSL when it is there
    [[ -z "$lto_flags" ]] || cmake_args+=(-DCMake_BUILD_LTO=ON)
    [[ ! -f /usr/include/openssl/ssl.h ]] || cmake_args+=(-DOPENSSL_ROOT_DIR=/usr)

    get_source "Kitware/CMake" "$ver" "$src" "cmake-$ver.tar.gz"
    if [[ "$verify" != true ]]; then
        item "Verification" "${YELLOW}skipped (--skip-verify)${NC}"
    elif [[ -f "$src.tar.gz" ]]; then
        verify_cmake "$work_dir" "$ver"
    else
        warn "The source came from git, so there is no tarball to check against Kitware's checksum list."
    fi

    cd "$src"
    # ./bootstrap, make, make install is the procedure in CMake's README.
    # Options after "--" are passed to CMake itself.
    run_task "Bootstrap cmake" "$work_dir/cmake.log" env "CC=$CC" "CXX=$CXX" "CFLAGS=$flags" "CXXFLAGS=$flags" "LDFLAGS=$ldflags" \
        ./bootstrap --prefix="$install_dir" --parallel="$jobs" -- "${cmake_args[@]}"
    run_task "Compile cmake ($jobs jobs)" "$work_dir/cmake.log" make -j"$jobs"
    [[ "$(./bin/cmake --version | head -n1)" == "cmake version $ver" ]] || fail "The new cmake reports \"$(./bin/cmake --version | head -n1)\", expected version $ver."
    binary_report "$src/bin/cmake"
    run_task "Stage the files" "$work_dir/cmake.log" make install/strip DESTDIR="$stage"
    [[ -x "$stage$install_dir/bin/cmake" ]] || fail "Staging did not produce $stage$install_dir/bin/cmake"
    install_tree "$stage$install_dir"
    commit_manifest cmake
}

install_meson() {
    local ver="$1" venv="$install_dir/lib/build-tools/meson"
    # A fresh virtual environment each time, made with the system Python, so
    # nothing is left over from the previous version
    rm -rf -- "$venv"
    mkdir -p "$install_dir/bin" "${venv%/*}"
    run_task "Create the virtual environment" "$work_dir/meson.log" /usr/bin/python3 -m venv "$venv"
    run_task "pip install meson==$ver" "$work_dir/meson.log" \
        "$venv/bin/python" -m pip install --disable-pip-version-check --no-input "meson==$ver"
    [[ "$("$venv/bin/meson" --version)" == "$ver" ]] || fail "The new meson reports version $("$venv/bin/meson" --version), expected $ver."
    ln -sfn "$venv/bin/meson" "$install_dir/bin/meson"
    manifest=("$install_dir/bin/meson" "$venv/")
    commit_manifest meson
}

install_go() {
    local ver="$1" arch file want stage="$work_dir/go-stage"
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv6l)  arch="armv6l" ;;
        *)       fail "Go has no binary release for this architecture: $(uname -m)" ;;
    esac
    file="go$ver.linux-$arch.tar.gz"

    fetch -o "$work_dir/$file" "https://go.dev/dl/$file" || fail "Could not download https://go.dev/dl/$file"
    item "Download" "https://go.dev/dl/$file"
    if [[ "$verify" == true ]]; then
        want="$(fetch "https://go.dev/dl/?mode=json&include=all" | python3 -c 'import json, sys
print(next((f["sha256"] for r in json.load(sys.stdin) for f in r["files"] if f["filename"] == sys.argv[1]), ""))' "$file")" || want=""
        [[ -n "$want" ]] || fail "Could not get the published SHA-256 for $file. Use --skip-verify to install without it."
        [[ "$(sha256 "$work_dir/$file")" == "$want" ]] || fail "SHA-256 mismatch for $file. The file was not used."
        item "SHA-256" "${GREEN}matches${NC} the checksum published on go.dev"
    else
        item "Verification" "${YELLOW}skipped (--skip-verify)${NC}"
    fi

    # Unpack to the side and try the binary before touching the live install.
    # Go's install page says never to unpack over an existing tree.
    mkdir -p "$stage" "$install_dir/bin"
    tar -xzf "$work_dir/$file" -C "$stage" --no-same-owner
    [[ "$("$stage/go/bin/go" version)" == "go version go$ver "* ]] || fail "The downloaded Go does not run or reports the wrong version."
    rm -rf -- "$install_dir/go"
    mv "$stage/go" "$install_dir/go"
    ln -sfn ../go/bin/go "$install_dir/bin/go"
    ln -sfn ../go/bin/gofmt "$install_dir/bin/gofmt"
    manifest=("$install_dir/bin/go" "$install_dir/bin/gofmt" "$install_dir/go/")
    commit_manifest go
}

# ---------------------------------------------------------------------------
# Reports about the rest of the system
# ---------------------------------------------------------------------------

# Another copy of a tool earlier in PATH (conda, pip, apt) hides the new one.
# This looks at the PATH the script was started with, not the cleaned one.
path_report() {
    local tool first shadowed=false
    step "First match in your PATH"
    for tool in $tools; do
        first="$(PATH="$user_path"; type -P "$tool" || true)"
        if [[ "$first" == "$install_dir/bin/$tool" ]]; then
            printf '    %-8s %s%s%s\n' "$tool" "$GREEN" "$first" "$NC"
        else
            printf '    %-8s %s%s%s\n' "$tool" "$YELLOW" "${first:-not found}" "$NC"
            shadowed=true
        fi
    done
    if [[ "$shadowed" == true ]]; then
        warn "The lines in yellow are not the copies in $install_dir/bin."
        warn "Put that directory first by adding this to the end of ~/.bashrc:"
        warn "    export PATH=\"$install_dir/bin:\$PATH\""
        warn "or remove the copy that is ahead of it. Then run: hash -r"
    fi
    if [[ -n "${SUDO_USER:-}" ]]; then
        log "This used root's PATH because of sudo. To check your own shell, run:"
        log "    type -a $tools"
    fi
}

# Earlier versions of this script installed into /usr/local/programs with
# symlinks, put Meson into the system Python with pip, and wrote a GOROOT
# block into ~/.bashrc. The block is removed here because it points Go at a
# directory that no longer holds the current install. The rest is reported
# and left for the user to remove.
legacy_cleanup() {
    local home bashrc tmp path
    local -a found=()
    home="$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)"
    bashrc="${home:-$HOME}/.bashrc"

    if wants go && [[ -f "$bashrc" ]] && grep -q '^# >>> build-tools golang >>>' "$bashrc"; then
        tmp="$(mktemp)"
        sed '/^# >>> build-tools golang >>>/,/^# <<< build-tools golang <<</d' "$bashrc" >"$tmp"
        # Write through the existing file so its owner and permissions stay the same
        cat "$tmp" >"$bashrc"
        rm -f -- "$tmp"
        step "Old GOROOT setting"
        log "Removed the \"build-tools golang\" block from $bashrc."
        log "Go finds its own files and does not need GOROOT. Open a new terminal,"
        log "or run this in the current one:  unset GOROOT"
    fi

    for path in /usr/local/programs/cmake-* /usr/local/programs/ninja-* /usr/local/programs/golang-*; do
        [[ -e "$path" ]] && found+=("$path")
    done
    if (( ${#found[@]} > 0 )); then
        step "Leftovers from the old script"
        warn "These directories are no longer used. To remove them:"
        warn "    sudo rm -rf ${found[*]}"
    fi
    return 0
}

cleanup() {
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
    local tool todo=""

    orig_args=("$@")
    parse_args "$@"
    [[ "$debug" != true ]] || set -x
    if [[ "$action" == uninstall ]]; then
        uninstall_tools
        exit 0
    fi

    trap cleanup EXIT
    setup_toolchain
    step "Prepare"
    item "Prefix" "$install_dir"
    item "Tools" "${tools// /, }"
    if wants cmake || wants ninja; then
        item "Compiler" "$CC and $CXX"
        item "CPU target" "$([[ "$portable" == true ]] && echo "portable, any CPU of this architecture" || echo "native, tuned for this PC")"
    fi
    if [[ "$action" == install ]]; then
        # Fail now, before anything is downloaded or built
        check_prefix_access "Writing to $install_dir needs root."
        [[ "$install_dir" != "/usr" ]] || warn "Installing into /usr overwrites the files of APT packages."
        required_packages
    fi

    make_plan
    for tool in $tools; do
        [[ "${plan[$tool]}" == keep ]] || todo+="${todo:+ }$tool"
    done
    if [[ "$action" == check ]]; then
        [[ -z "$todo" ]] || exit 10
        exit 0
    fi
    if [[ -z "$todo" ]]; then
        log "Everything is up to date. Use --force to reinstall."
        path_report
        exit 0
    fi

    if [[ " $todo " == *" cmake "* || " $todo " == *" ninja "* ]] && command -v "$CXX" >/dev/null; then
        select_flags
    fi
    if [[ "$dry_run" == true ]]; then
        step "Dry run finished"
        [[ "$needs_root" != true ]] || item "Needs sudo" "yes, to write to $install_dir"
        log "Nothing was downloaded, built, or installed."
        exit 0
    fi

    if [[ -z "$build_base" ]]; then
        build_base="$(mktemp -d "${TMPDIR:-/tmp}/build-tools-script.XXXXXX")"
        made_temp_base=true
    else
        build_base="$(realpath -m -- "$build_base")"
        [[ -d "$build_base" ]] || created_build_base=true
        mkdir -p "$build_base"
    fi
    work_dir="$build_base/build-tools-work"
    rm -rf -- "$work_dir"
    mkdir -p "$work_dir"

    for tool in $todo; do
        step "${tool^} ${latest[$tool]}"
        "install_$tool" "${latest[$tool]}"
    done
    path_report
    legacy_cleanup

    step "Done"
    for tool in $todo; do
        item "$tool" "${GREEN}${latest[$tool]} installed${NC}${current[$tool]:+ (replaced ${current[$tool]})}"
    done
    item "Time" "${SECONDS}s"
    item "Uninstall" "${0##*/} --uninstall -i $install_dir"
    if [[ "$keep_build" == true ]]; then
        item "Build files" "kept at $work_dir"
    fi
}

main "$@"
