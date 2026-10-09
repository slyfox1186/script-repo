#!/usr/bin/env bash

gnu_curl() {
    command curl -q --fail --location --show-error --retry 3 --retry-delay 2 \
        --connect-timeout 15 --max-time 600 --proto '=https' --proto-redir '=https' \
        --user-agent 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36' "$@"
}

# Purpose: build the latest stable release of the Ninja build system from source
# Target:  Ubuntu 24.04 (works on other Debian/Ubuntu releases as well)
# Source:  https://github.com/ninja-build/ninja
# Script version: 1.0
#
# Ninja's upstream install rule only copies the binary, so this script also
# installs the files from misc/ and doc/ (shell completions, vim syntax file,
# manual, license) under the chosen prefix and records every installed path in
# a manifest so that --uninstall removes exactly what was installed.

set -Eeuo pipefail

script_ver="1.0"
prog_name="ninja"
repo_url="https://github.com/ninja-build/ninja"
version_regex='^[0-9]+\.[0-9]+\.[0-9]+$'

# Defaults (all can be changed with command line options)
install_dir="/usr/local"
version=""
compiler="gcc"
build_method="cmake"
build_base=""
jobs="$(nproc 2>/dev/null || echo 2)"
run_tests=false
static_link=false
portable=false
keep_build=false
force=false
install_deps=true
install_extras=true
dry_run=false
assume_yes=false
action="install"

manifest_file=""
work_dir=""
tar_file=""
tmp_manifest=""
built_binary=""
made_temp_base=false
deps_checked=false
SUDO=""
manifest=()

# Real escape characters, so messages can be printed with printf '%s' and
# backslashes inside paths are never interpreted. Color is used only on a
# terminal and is switched off by the NO_COLOR convention (https://no-color.org).
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    CYAN=$'\033[0;36m' GREEN=$'\033[0;32m' RED=$'\033[0;31m' YELLOW=$'\033[0;33m'
    BOLD=$'\033[1m' DIM=$'\033[2m' NC=$'\033[0m'
else
    CYAN='' GREEN='' RED='' YELLOW='' BOLD='' DIM='' NC=''
fi

log()  { printf '%s[INFO]%s %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
fail() { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

trap 'fail "Command failed on line $LINENO: $BASH_COMMAND"' ERR

# Help output is kept within 80 columns. Option names are green, the values
# they take are cyan, section titles are bold yellow (color first, because the color code resets bold), and defaults are dim.
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
    printf '%s%s%s %sv%s%s\n' "$CYAN$BOLD" "build-ninja.sh" "$NC" "$DIM" "$script_ver" "$NC"
    printf '%s\n' "Build and install the Ninja build system from source."

    help_section "USAGE"
    printf '  %s%s%s [%sOPTIONS%s]\n' "$BOLD" "${0##*/}" "$NC" "$CYAN" "$NC"

    help_section "INSTALL LOCATION"
    help_opt "-i" "--install-directory" "DIR" \
        "Install prefix, relative or absolute." \
        "The binary goes in DIR/bin and the shared" \
        "files go in DIR/share." \
        "$(help_default "$install_dir")"

    help_section "VERSION"
    help_opt "-v" "--version" "VERSION" \
        "Build a specific release, such as 1.12.1." \
        "$(help_default "latest stable")"
    help_opt "-l" "--list" "" \
        "List the available stable releases."
    help_opt "" "--check" "" \
        "Compare the version installed in DIR with" \
        "the latest release. Exit status is 0 when" \
        "up to date and 10 when an update exists."

    help_section "BUILD"
    help_opt "-c" "--compiler" "NAME" \
        "gcc or clang, or an exact name such as" \
        "g++-14 or clang++-18." \
        "$(help_default "$compiler")"
    help_opt "-m" "--method" "METHOD" \
        "cmake or bootstrap. bootstrap runs upstream's" \
        "configure.py and needs only python3." \
        "$(help_default "$build_method")"
    help_opt "-j" "--jobs" "N" \
        "Parallel build jobs (cmake method)." \
        "$(help_default "$jobs")"
    help_opt "-t" "--run-tests" "" \
        "Run the upstream unit tests and install only" \
        "if they pass (cmake method)."
    help_opt "-s" "--static" "" \
        "Link the binary statically."
    help_opt "-p" "--portable" "" \
        "Build a binary that runs on any CPU of the" \
        "same architecture. Without this the build" \
        "uses -march=native, which is tuned for this" \
        "PC and may not run on others. Add --static" \
        "to also drop the system library dependency."
    help_opt "-b" "--build-directory" "DIR" \
        "Where to download and compile." \
        "$(help_default "a new temporary directory")"
    help_opt "-k" "--keep-build" "" \
        "Keep the build directory when finished."

    help_section "BEHAVIOR"
    help_opt "-f" "--force" "" \
        "Rebuild even if that version is already" \
        "installed in DIR."
    help_opt "-y" "--yes" "" \
        "Do not prompt (passes -y to apt)."
    help_opt "" "--no-deps" "" \
        "Do not check for or install APT packages."
    help_opt "" "--no-extras" "" \
        "Install only the binary. Skips completions," \
        "vim syntax, and docs."
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
    help_example "Build with clang and run the tests first" "-i /usr/local -c clang -t"
    help_example "A specific release into a relative path" "-v 1.12.1 -i ./ninja-1.12.1"
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
            -m|--method)            need_value "$@"; build_method="$2"; shift 2 ;;
            -j[0-9]*)               jobs="${1#-j}"; shift ;;
            -j|--jobs)              need_value "$@"; jobs="$2"; shift 2 ;;
            -b|--build-directory)   need_value "$@"; build_base="$2"; shift 2 ;;
            -l|--list)              action="list"; shift ;;
            --check)                action="check"; shift ;;
            -u|--uninstall)         action="uninstall"; shift ;;
            -t|--run-tests)         run_tests=true; shift ;;
            -s|--static)            static_link=true; shift ;;
            -p|--portable)          portable=true; shift ;;
            -k|--keep-build)        keep_build=true; shift ;;
            -f|--force)             force=true; shift ;;
            --no-deps)              install_deps=false; shift ;;
            --no-extras)            install_extras=false; shift ;;
            --dry-run)              dry_run=true; shift ;;
            -y|--yes)               assume_yes=true; shift ;;
            -h|--help)              print_usage; exit 0 ;;
            *)                      fail "Invalid option: $1 (use --help to see the options)" ;;
        esac
    done

    [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail "--jobs must be a positive integer, got: $jobs"
    [[ -z "$version" || "$version" =~ $version_regex ]] || fail "--version must look like 1.13.2, got: $version"
    case "$build_method" in
        cmake|bootstrap) ;;
        *) fail "--method must be cmake or bootstrap, got: $build_method" ;;
    esac
    if [[ "$run_tests" == true && "$build_method" == bootstrap ]]; then
        fail "--run-tests needs the cmake method."
    fi

    # Resolve the prefix to an absolute path. A quoted or =style "~" is not
    # expanded by the shell, so handle it here.
    # shellcheck disable=SC2088
    [[ "$install_dir" == "~" || "$install_dir" == "~/"* ]] && install_dir="$HOME${install_dir:1}"
    install_dir="$(realpath -m -- "$install_dir")"
    [[ "$install_dir" != "/" ]] || fail "Refusing to use / as the install prefix. Use /usr or /usr/local."
    manifest_file="$install_dir/share/$prog_name/install_manifest.txt"
}

# Map the --compiler value to a C++ compiler (Ninja is C++ only)
set_compiler() {
    case "$compiler" in
        gcc|g++)       CXX="g++" ;;
        clang|clang++) CXX="clang++" ;;
        gcc-*)         CXX="g++-${compiler#gcc-}" ;;
        clang-*)       CXX="clang++-${compiler#clang-}" ;;
        *)             CXX="$compiler" ;;
    esac
    export CXX
}

# Use sudo only when the prefix is not writable by the current user
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
        command -v sudo >/dev/null || fail "$install_dir is not writable and sudo is not available."
        SUDO="sudo"
    fi
}

as_root() {
    if [[ -n "$SUDO" ]]; then sudo "$@"; else "$@"; fi
}

# Stable releases are tagged vMAJOR.MINOR.PATCH. Listing the tags with git
# avoids the GitHub API rate limit. The API is the fallback when git is missing.
list_versions() {
    local out=""
    if command -v git >/dev/null; then
        out="$(git ls-remote --tags --refs "$repo_url.git" 2>/dev/null | awk -F/ '{print $NF}')" || out=""
    fi
    if [[ -z "$out" ]] && command -v curl >/dev/null; then
        out="$(gnu_curl -fsSL --connect-timeout 15 "https://api.github.com/repos/ninja-build/ninja/tags?per_page=100" 2>/dev/null \
            | grep -oP '"name":\s*"\K[^"]+')" || out=""
    fi
    [[ -n "$out" ]] || return 1
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$out" | sed 's/^v//' | sort -ruV
}

# GitHub's /releases/latest page redirects to the release the maintainers
# marked as latest, which never points at a pre-release or a bare tag. Use
# that first, and fall back to the highest stable tag if it cannot be reached.
latest_version() {
    local url="" tag="" versions
    if command -v curl >/dev/null; then
        url="$(gnu_curl -fsSLI --connect-timeout 15 -o /dev/null -w '%{url_effective}' "$repo_url/releases/latest" 2>/dev/null)" || url=""
        tag="${url##*/}"
        tag="${tag#v}"
        if [[ "$url" == */releases/tag/* && "$tag" =~ $version_regex ]]; then
            echo "$tag"
            return 0
        fi
    fi
    versions="$(list_versions)" || return 1
    head -n1 <<<"$versions"
}

installed_version() {
    [[ -x "$install_dir/bin/$prog_name" ]] || return 1
    "$install_dir/bin/$prog_name" --version 2>/dev/null
}

required_packages() {
    local -a pkgs missing_pkgs=() apt_cmd=(apt-get) apt_opts=()
    local pkg cxx_pkg=""

    [[ "$install_deps" == true && "$deps_checked" == false ]] || return 0
    deps_checked=true

    pkgs=(build-essential ca-certificates curl git)
    [[ "$build_method" == cmake ]] && pkgs+=(cmake)
    [[ "$build_method" == bootstrap ]] && pkgs+=(python3)
    [[ "$run_tests" == true ]] && pkgs+=(libgtest-dev)
    case "$CXX" in
        clang++)   cxx_pkg="clang" ;;
        clang++-*) cxx_pkg="clang-${CXX#clang++-}" ;;
        g++-*)     cxx_pkg="$CXX" ;;
        *)         ;;
    esac
    [[ -n "$cxx_pkg" ]] && pkgs+=("$cxx_pkg")

    command -v dpkg-query >/dev/null || { warn "dpkg not found, skipping the package check."; return 0; }

    for pkg in "${pkgs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done
    [[ "${#missing_pkgs[@]}" -eq 0 ]] && return 0

    log "Missing APT packages: ${missing_pkgs[*]}"
    if [[ "$dry_run" == true ]]; then
        log "[dry run] Would install: ${missing_pkgs[*]}"
        return 0
    fi
    [[ "$EUID" -eq 0 ]] || apt_cmd=(sudo apt-get)
    [[ "$assume_yes" == true ]] && apt_opts+=(-y)
    "${apt_cmd[@]}" update
    "${apt_cmd[@]}" install "${apt_opts[@]}" "${missing_pkgs[@]}"
}

# Fail early with a clear message instead of halfway through the build
require_commands() {
    local cmd
    local -a cmds=("$CXX" strip)
    [[ "$build_method" == cmake ]] && cmds+=(cmake make)
    [[ "$build_method" == bootstrap ]] && cmds+=(python3)
    for cmd in "${cmds[@]}"; do
        command -v "$cmd" >/dev/null || fail "Required command not found: $cmd"
    done
    command -v curl >/dev/null || command -v git >/dev/null || fail "Either curl or git is needed to download the source."
}

download_and_extract() {
    local url="$repo_url/archive/refs/tags/v$version.tar.gz"
    log "Downloading $url"
    if command -v curl >/dev/null \
        && gnu_curl -fsSL --connect-timeout 15 --retry 3 --retry-delay 2 -o "$tar_file" "$url"; then
        mkdir -p "$work_dir"
        tar -xzf "$tar_file" -C "$work_dir" --strip-components 1 || fail "Failed to extract $tar_file"
    elif command -v git >/dev/null; then
        # Some proxies block GitHub archive downloads, so fall back to a shallow clone of the tag
        warn "Archive download failed, cloning the v$version tag with git instead."
        rm -f -- "$tar_file"
        git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v$version" "$repo_url.git" "$work_dir" \
            || fail "Could not get ninja $version. Run ${0##*/} --list to see the valid versions."
    else
        fail "Failed to download $url. Run ${0##*/} --list to see the valid versions."
    fi
}

build_ninja() {
    # Optimization level is left to upstream: -O3 with LTO for the CMake
    # Release build, -O2 for configure.py. By default the build targets this
    # PC's CPU. --portable leaves the compiler's baseline target in place, so
    # the binary runs on any CPU of the same architecture.
    local cxxflags="-pipe" ldflags=""
    [[ "$portable" == false ]] && cxxflags+=" -march=native"
    [[ "$static_link" == true ]] && ldflags="-static"

    cd "$work_dir"
    if [[ "$build_method" == cmake ]]; then
        local testing=OFF
        [[ "$run_tests" == true ]] && testing=ON
        # Flags are passed explicitly so that CXXFLAGS and LDFLAGS exported by
        # an active conda environment cannot leak into the build
        cmake -S . -B build -G "Unix Makefiles" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_CXX_COMPILER="$CXX" \
            -DCMAKE_CXX_FLAGS="$cxxflags" \
            -DCMAKE_EXE_LINKER_FLAGS="$ldflags" \
            -DBUILD_TESTING="$testing"
        cmake --build build --parallel "$jobs"
        built_binary="$work_dir/build/$prog_name"
        if [[ "$run_tests" == true ]]; then
            log "Running the unit tests"
            (cd build && ./ninja_test) || fail "The unit tests failed. Nothing was installed."
        fi
    else
        # configure.py appends both CFLAGS and CXXFLAGS, so set only one of them
        env -u CFLAGS CXXFLAGS="$cxxflags" LDFLAGS="$ldflags" python3 ./configure.py --bootstrap
        built_binary="$work_dir/$prog_name"
    fi

    [[ -x "$built_binary" ]] || fail "The build finished but $built_binary was not found."
    local built_ver
    built_ver="$("$built_binary" --version)"
    [[ "$built_ver" == "$version" ]] || fail "Built binary reports version $built_ver, expected $version."
    log "Built ninja $built_ver"
}

# Run a real one-rule build with the new binary before anything is installed
smoke_test() {
    local dir="$work_dir/smoke-test"
    mkdir -p "$dir"
    cat >"$dir/build.ninja" <<'EOF'
rule touch
  command = touch $out
build out.txt: touch
EOF
    "$built_binary" -C "$dir" >/dev/null && [[ -f "$dir/out.txt" ]] \
        || fail "The new binary failed a basic test build. Nothing was installed."
    log "Smoke test passed"
}

# Manifest entries are only trusted if they sit under the prefix and contain no ".." component
safe_entry() {
    [[ "$1" == "$install_dir/"* && "$1" != *"/../"* && "$1" != *"/.." ]]
}

# install_file MODE SOURCE DESTINATION
install_file() {
    local mode="$1" src="$2" dest="$3"
    # Not every release ships every file (ninja-mode.el left the repo in 1.13), so skip quietly
    [[ -f "$src" ]] || return 0
    as_root install -D -m "$mode" "$src" "$dest"
    manifest+=("$dest")
}

install_ninja() {
    local share="$install_dir/share" file
    local -a old_files=()

    # Remember what an earlier run of this script installed here
    [[ -f "$manifest_file" ]] && mapfile -t old_files <"$manifest_file"

    log "Installing into $install_dir${SUDO:+ (using sudo)}"
    as_root install -D -m 0755 -s "$built_binary" "$install_dir/bin/$prog_name"
    manifest+=("$install_dir/bin/$prog_name")

    if [[ "$install_extras" == true ]]; then
        install_file 0644 "$work_dir/misc/bash-completion" "$share/bash-completion/completions/$prog_name"
        install_file 0644 "$work_dir/misc/zsh-completion"  "$share/zsh/site-functions/_$prog_name"
        install_file 0644 "$work_dir/misc/ninja.vim"       "$share/vim/vimfiles/syntax/$prog_name.vim"
        install_file 0644 "$work_dir/misc/ninja-mode.el"   "$share/emacs/site-lisp/ninja-mode.el"
        install_file 0644 "$work_dir/doc/manual.asciidoc"  "$share/doc/$prog_name/manual.asciidoc"
        install_file 0644 "$work_dir/README.md"            "$share/doc/$prog_name/README.md"
        install_file 0644 "$work_dir/COPYING"              "$share/doc/$prog_name/COPYING"
    fi
    manifest+=("$manifest_file")

    # Remove files from the earlier install that this one no longer provides,
    # so an upgrade or a switch to --no-extras leaves nothing orphaned
    for file in "${old_files[@]}"; do
        safe_entry "$file" || continue
        if [[ ! " ${manifest[*]} " == *" $file "* && -f "$file" ]]; then
            as_root rm -f -- "$file"
            log "Removed stale file from the previous install: $file"
        fi
    done

    tmp_manifest="$(mktemp)"
    printf '%s\n' "${manifest[@]}" >"$tmp_manifest"
    as_root install -D -m 0644 "$tmp_manifest" "$manifest_file"
}

uninstall_ninja() {
    local file dir
    local -a files=()

    [[ -f "$manifest_file" ]] || fail "No manifest at $manifest_file. This script did not install ninja into $install_dir, so nothing was removed."
    set_sudo
    mapfile -t files <"$manifest_file"

    for file in "${files[@]}"; do
        safe_entry "$file" || { warn "Ignoring unexpected manifest entry: $file"; continue; }
        if [[ "$dry_run" == true ]]; then
            log "[dry run] Would remove $file"
        elif [[ -e "$file" || -L "$file" ]]; then
            as_root rm -f -- "$file"
            log "Removed $file"
        fi
    done
    [[ "$dry_run" == true ]] && return 0

    # Remove the directories this script owns, but only if they are now empty
    for dir in "$install_dir/share/doc/$prog_name" "$install_dir/share/$prog_name"; do
        if [[ -d "$dir" ]]; then
            as_root rmdir --ignore-fail-on-non-empty -- "$dir"
        fi
    done
    log "ninja has been uninstalled from $install_dir"
}

check_version() {
    local latest current
    latest="$(latest_version)" || fail "Could not get the release list from $repo_url"
    if current="$(installed_version)"; then
        log "Installed in $install_dir: $current"
    else
        current=""
        log "Installed in $install_dir: none"
    fi
    log "Latest stable release: $latest"
    if [[ "$current" == "$latest" ]]; then
        log "Up to date."
        return 0
    fi
    log "Run ${0##*/} -i $install_dir to install $latest"
    return 10
}

# Other copies of ninja earlier in PATH (conda, pip, apt) will hide the new one
path_report() {
    local first path ver
    local target="$install_dir/bin/$prog_name"

    first="$(type -P "$prog_name" || true)"
    echo
    log "ninja binaries found in PATH, in lookup order:"
    while IFS= read -r path; do
        ver="$("$path" --version 2>/dev/null || echo unknown)"
        if [[ "$path" == "$target" ]]; then
            printf '    %s%s  (%s)  <- installed by this script%s\n' "$GREEN" "$path" "$ver" "$NC"
        else
            printf '    %s  (%s)\n' "$path" "$ver"
        fi
    done < <(type -aP "$prog_name" | awk '!seen[$0]++')

    if [[ "$first" != "$target" ]]; then
        echo
        if [[ -n "$first" ]]; then
            warn "Running \"ninja\" will start $first, not $target."
        else
            warn "$install_dir/bin is not in PATH."
        fi
        warn "Put the new one first by adding this to the end of ~/.bashrc:"
        warn "    export PATH=\"$install_dir/bin:\$PATH\""
        warn "or remove the copy that is ahead of it. Then run: hash -r"
    fi
}

cleanup() {
    [[ -n "$tmp_manifest" ]] && rm -f -- "$tmp_manifest"
    [[ "$keep_build" == true ]] && return 0
    if [[ "$made_temp_base" == true && -n "$build_base" ]]; then
        rm -rf -- "$build_base"
    else
        [[ -n "$work_dir" && -d "$work_dir" ]] && rm -rf -- "$work_dir"
        [[ -n "$tar_file" && -f "$tar_file" ]] && rm -f -- "$tar_file"
    fi
    return 0
}

main() {
    local current rc

    parse_args "$@"

    case "$action" in
        list)
            log "Stable releases of ninja:"
            list_versions || fail "Could not get the release list from $repo_url"
            exit 0
            ;;
        check)
            rc=0
            check_version || rc=$?
            exit "$rc"
            ;;
        uninstall) uninstall_ninja; exit 0 ;;
        *)         ;;
    esac

    if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" ]]; then
        warn "No need to start this script with sudo. It asks for sudo itself, and only for the install step."
    fi

    set_compiler

    # The version lookup needs curl or git. On a bare system install the packages first.
    if ! command -v curl >/dev/null && ! command -v git >/dev/null; then
        required_packages
    fi

    if [[ -z "$version" ]]; then
        version="$(latest_version)" || fail "Could not get the release list from $repo_url. Use --version to pick one."
        log "Latest stable release: $version"
    fi

    # Check this before touching APT so that repeat runs are fast and change nothing
    if current="$(installed_version)" && [[ "$current" == "$version" && "$force" == false ]]; then
        log "ninja $version is already installed in $install_dir. Use --force to rebuild."
        path_report
        exit 0
    fi

    set_sudo
    [[ "$install_dir" == "/usr" ]] && warn "Installing into /usr overwrites the files of the APT ninja-build package."
    required_packages

    if [[ "$dry_run" == true ]]; then
        log "[dry run] Version:       $version${current:+ (replaces $current)}"
        log "[dry run] Prefix:        $install_dir${SUDO:+ (needs sudo)}"
        log "[dry run] Binary:        $install_dir/bin/$prog_name"
        log "[dry run] Shared files:  $([[ "$install_extras" == true ]] && echo "$install_dir/share" || echo "skipped")"
        log "[dry run] Compiler:      $CXX"
        log "[dry run] Method:        $build_method, $jobs jobs, tests: $run_tests, static: $static_link"
        log "[dry run] CPU target:    $([[ "$portable" == true ]] && echo "portable (any CPU of this architecture)" || echo "native (-march=native, this PC)")"
        exit 0
    fi

    require_commands

    # Ask for the sudo password now, so the script does not stop and wait for
    # it after the build, and so a refusal costs nothing
    if [[ -n "$SUDO" ]]; then
        log "sudo is needed to write to $install_dir"
        sudo -v || fail "sudo authentication failed."
    fi

    trap cleanup EXIT
    if [[ -z "$build_base" ]]; then
        build_base="$(mktemp -d "${TMPDIR:-/tmp}/ninja-build-script.XXXXXX")"
        made_temp_base=true
    else
        build_base="$(realpath -m -- "$build_base")"
        mkdir -p "$build_base"
    fi
    work_dir="$build_base/$prog_name-$version"
    tar_file="$build_base/$prog_name-$version.tar.gz"
    [[ -d "$work_dir" ]] && rm -rf -- "$work_dir"

    download_and_extract
    build_ninja
    smoke_test
    install_ninja

    log "Installed ninja $version${current:+ (replaced $current)}:"
    printf '    %s\n' "${manifest[@]}"
    [[ "$keep_build" == true ]] && log "Build directory kept at $work_dir"
    path_report
    echo
    log "${CYAN}Done.${NC} To remove it later: ${0##*/} --uninstall -i $install_dir"
}

main "$@"
