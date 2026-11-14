#!/usr/bin/env bash

# Keep these helpers local so a downloaded installer remains standalone.
set -Ee -o pipefail
trap 'printf "Build failed at line %s. Build files were retained for inspection.\n" "$LINENO" >&2; exit 1' ERR

gnu_curl() {
    command curl -q --fail --location --show-error --retry 3 --retry-delay 2 \
        --connect-timeout 15 --max-time 600 --proto '=https' --proto-redir '=https' \
        --user-agent 'Mozilla/5.0 (X11; Linux x86_64; rv:160.0) Gecko/20100101 Firefox/160.0' "$@"
}

gnu_wget() {
    command wget --timeout=30 --tries=3 --https-only \
        --user-agent='Mozilla/5.0 (X11; Linux x86_64; rv:160.0) Gecko/20100101 Firefox/160.0' "$@"
}

gnu_link_dir() {
    local source_dir="$1" destination="$2" pattern="${3:-*}" file target
    [[ -d "$source_dir" ]] || return 0
    for file in "$source_dir"/*; do
        [[ -e "$file" || -L "$file" ]] || continue
        # The caller supplies a filename glob, for example *.pc.
        # shellcheck disable=SC2053
        [[ "${file##*/}" == $pattern ]] || continue
        target="$destination/${file##*/}"
        [[ ! -d "$target" || -L "$target" ]] || { printf 'Cannot replace directory %s with a symlink.\n' "$target" >&2; return 1; }
        sudo mkdir -p -- "$destination"
        sudo ln -sfn -- "$file" "$target"
    done
}

gnu_new_workdir() {
    local base="${TMPDIR:-/tmp}"
    [[ "$base" == /* && -d "$base" ]] || { printf 'TMPDIR must be an existing absolute directory.\n' >&2; return 1; }
    mktemp -d -- "$base/${0##*/}.XXXXXX"
}

gnu_jobs="${JOBS:-$(nproc)}"
[[ "$gnu_jobs" =~ ^[1-9][0-9]*$ ]] || { printf 'JOBS must be a positive integer.\n' >&2; exit 1; }

# GitHub: https://github.com/slyfox1186/script-repo/blob/main/Bash/installer-scripts/gnu-software/build-all-gnu.sh
# Purpose: Build various GNU programs from source code
# Updated: 06.22.24
# Version: 1.4

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    CYAN=$'\033[0;36m'
    GREEN=$'\033[0;32m'
    RED=$'\033[0;31m'
    YELLOW=$'\033[0;33m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    NC=$'\033[0m'
else
    CYAN=""
    GREEN=""
    RED=""
    YELLOW=""
    BOLD=""
    DIM=""
    NC=""
fi

# List of available programs
available_programs=(
    autoconf autoconf-archive bash gawk grep gzip libtool
    make nano parallel pkg-config sed tar texinfo wget which
)

# Consolidated list of required packages for all programs
MASTER_PKGS="ca-certificates wget pkg-config autoconf autoconf-archive automake build-essential bzip2 ccache curl libc6-dev"
MASTER_PKGS+=" libintl-perl libtool lzip lzma lzma-dev m4 texinfo xz-utils zlib1g-dev"

# Specific package lists for each program (excluding those already in MASTER_PKGS)
BASH_PKGS="libacl1-dev libattr1-dev liblzma-dev libzstd-dev lzip lzop"
GAWK_PKGS="libgmp-dev libmpfr-dev libreadline-dev libsigsegv-dev lzip"
GREP_PKGS="libltdl-dev libsigsegv-dev"
GZIP_PKGS="libzstd-dev zstd"
MAKE_PKGS="libdmalloc-dev"
NANO_PKGS="libncurses-dev"
PKG_CONFIG_PKGS="libglib2.0-dev libpopt-dev patch"
SED_PKGS="autopoint autotools-dev libaudit-dev librust-polling-dev valgrind"
TAR_PKGS="libacl1-dev libattr1-dev libbz2-dev liblzma-dev libzstd-dev lzip lzop patch"
PARALLEL_PKGS="autogen binutils bison lzip yasm"
WGET_PKGS="libc-ares-dev libidn2-dev libpcre2-dev libpsl-dev libssl-dev libunistring-dev perl uuid-dev"
WHICH_PKGS="curl gcc make tar"

# Enhanced logging and error handling
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

show_dependency_progress() {
    local current="$1" total="$2" package="$3"
    local width=20 filled percent filled_bar empty_bar
    [[ -t 1 ]] || return 0
    filled=$((current * width / total))
    percent=$((current * 100 / total))
    printf -v filled_bar '%*s' "$filled" ''
    printf -v empty_bar '%*s' "$((width - filled))" ''
    filled_bar="${filled_bar// /#}"
    empty_bar="${empty_bar// /-}"
    printf '\r%b[INFO]%b Dependencies [%s%s] %d/%d (%d%%) %-20s\033[K' \
        "$GREEN" "$NC" "$filled_bar" "$empty_bar" "$current" "$total" "$percent" "$package"
    ((current < total)) || printf '\n'
}

fail() {
    echo
    echo -e "${RED}[ERROR]${NC} $1"
    echo -e "To report a bug, create an issue at: https://github.com/slyfox1186/script-repo/issues"
    exit 1
}

apply_pkg_config_c23_fix() {
    local source_dir="$1" source_file="$1/glib/glib/goption.c"
    [[ -f "$source_file" ]] || fail "Bundled GLib source is missing: $source_file"

    # Backport GNOME GLib 9e320e1c43a4770ed1532248fe5416eb0c618120 for C23.
    if grep -Fq 'gboolean bool;' "$source_file"; then
        patch -d "$source_dir" -p1 <<'PATCH' || fail "Failed to apply the GLib C23 compatibility fix. Line: $LINENO"
--- a/glib/glib/goption.c
+++ b/glib/glib/goption.c
@@ -166,7 +166,7 @@ typedef struct
   gpointer arg_data;
   union
   {
-    gboolean bool;
+    gboolean boolean;
     gint integer;
     gchar *str;
     gchar **array;
@@ -1600,7 +1600,7 @@ free_changes_list (GOptionContext *context,
           switch (change->arg_type)
             {
             case G_OPTION_ARG_NONE:
-              *(gboolean *)change->arg_data = change->prev.bool;
+              *(gboolean *)change->arg_data = change->prev.boolean;
               break;
             case G_OPTION_ARG_INT:
               *(gint *)change->arg_data = change->prev.integer;
PATCH
    fi

    grep -Fq 'gboolean boolean;' "$source_file" || fail "The GLib C23 declaration fix was not applied."
    grep -Fq 'change->prev.boolean;' "$source_file" || fail "The GLib C23 field-access fix was not applied."
    ! grep -Fq 'gboolean bool;' "$source_file" || fail "The obsolete GLib bool declaration remains."
    ! grep -Fq 'change->prev.bool;' "$source_file" || fail "The obsolete GLib bool field access remains."
}

apply_tar_libiconv_fix() {
    [[ "$version" == "1.35" ]] || return 0
    local source_dir="$1" makefile_am makefile_in
    makefile_am="$source_dir/src/Makefile.am"
    makefile_in="$source_dir/src/Makefile.in"
    [[ -f "$makefile_am" && -f "$makefile_in" ]] || fail "The tar build makefiles are missing."

    if grep -Fq '$(LIBINTL) $(LIBICONV)' "$makefile_am" &&
       grep -Fq '$(LIBINTL) $(LIBICONV)' "$makefile_in"; then
        return 0
    fi

    # Backport GNU tar 8632df398b2f548465ebe68b8f494c0d6f8d913d.
    patch -d "$source_dir" -p1 <<'PATCH' || fail "Failed to apply the upstream libiconv link fix. Line: $LINENO"
--- a/src/Makefile.am
+++ b/src/Makefile.am
@@ -55 +55,2 @@
- $(LIB_SELINUX) $(LIB_SETLOCALE_NULL)
+ $(LIB_SELINUX) $(LIB_SETLOCALE_NULL) \
+ $(LIBINTL) $(LIBICONV)
--- a/src/Makefile.in
+++ b/src/Makefile.in
@@ -1796 +1796,2 @@
- $(LIB_SELINUX) $(LIB_SETLOCALE_NULL)
+ $(LIB_SELINUX) $(LIB_SETLOCALE_NULL) \
+ $(LIBINTL) $(LIBICONV)
PATCH

    grep -Fq '$(LIBINTL) $(LIBICONV)' "$makefile_am" || fail "The upstream libiconv fix was not applied to Makefile.am."
    grep -Fq '$(LIBINTL) $(LIBICONV)' "$makefile_in" || fail "The upstream libiconv fix was not applied to Makefile.in."
}

print_program_grid() {
    local i
    for ((i = 0; i < ${#available_programs[@]}; i += 4)); do
        printf '    %b%-18s %-18s %-18s %s%b\n' \
            "$GREEN" \
            "${available_programs[i]:-}" \
            "${available_programs[i + 1]:-}" \
            "${available_programs[i + 2]:-}" \
            "${available_programs[i + 3]:-}" \
            "$NC"
    done
}

show_usage() {
    printf '\n%b%s%b\n' "${BOLD}${CYAN}" 'GNU SOFTWARE BUILD MANAGER' "$NC"
    printf '%b%s%b\n' "$DIM" 'Build and install GNU tools from official source releases.' "$NC"

    printf '\n%bUSAGE%b\n' "${BOLD}${CYAN}" "$NC"
    printf '  %b%s%b %b[OPTIONS]%b\n' "$GREEN" "${0##*/}" "$NC" "$YELLOW" "$NC"

    printf '\n%bOPTIONS%b\n' "${BOLD}${CYAN}" "$NC"
    printf '  %b-h, --help%b           Show this help menu and exit.\n' "$GREEN" "$NC"
    printf '  %b-p, --programs LIST%b  Build the comma-separated programs in LIST.\n' "$GREEN" "$NC"
    printf '                       Use %ball%b to select every available program.\n' "$YELLOW" "$NC"

    printf '\n%bPROGRAMS (%d)%b\n' "${BOLD}${CYAN}" "${#available_programs[@]}" "$NC"
    print_program_grid

    printf '\n%bEXAMPLES%b\n' "${BOLD}${CYAN}" "$NC"
    printf '  %b%s -p all%b\n' "$GREEN" "${0##*/}" "$NC"
    printf '      Build every available program.\n'
    printf '  %b%s -p bash,make,grep%b\n' "$GREEN" "${0##*/}" "$NC"
    printf '      Build only Bash, Make, and Grep.\n'
    printf '  %b%s%b\n' "$GREEN" "${0##*/}" "$NC"
    printf '      Choose programs interactively.\n'

    printf '\n%bColor is disabled for redirected output and when NO_COLOR is set.%b\n' "$DIM" "$NC"
}

# Parse command-line options
programs=""
version=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -p|--programs)
            [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || fail "Option $1 requires a program list."
            shift
            programs="$1"
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
    shift
done

# Check for the root user
if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without root or sudo."
    exit 1
fi

# Display available programs and prompt for programs if not specified via arguments
if [[ -z "$programs" ]]; then
    printf '\n%bAvailable programs (%d):%b\n' "${BOLD}${CYAN}" "${#available_programs[@]}" "$NC"
    print_program_grid
    printf "\nEnter the programs to build (comma-separated), or %b'all'%b: " "$YELLOW" "$NC"
    read -r programs || exit 1
    [[ ! -t 1 ]] || clear
fi

# Function to check and install required packages
required_packages() {
    local -a pkgs
    local pkg prog extra
    local -a additions
    local -A seen=()

    read -r -a pkgs <<< "$MASTER_PKGS"

    if [[ "$1" == "all" ]]; then
        pkgs+=("$BASH_PKGS" "$GAWK_PKGS" "$GREP_PKGS" "$GZIP_PKGS" "$MAKE_PKGS" "$NANO_PKGS" "$PKG_CONFIG_PKGS" "$SED_PKGS" "$TAR_PKGS" "$PARALLEL_PKGS" "$WGET_PKGS" "$WHICH_PKGS")
    else
        for prog in "${progs[@]}"; do
            case "$prog" in
                bash)
                    pkgs+=("$BASH_PKGS")
                    ;;
                gawk)
                    pkgs+=("$GAWK_PKGS")
                    ;;
                grep)
                    pkgs+=("$GREP_PKGS")
                    ;;
                gzip)
                    pkgs+=("$GZIP_PKGS")
                    ;;
                make)
                    pkgs+=("$MAKE_PKGS")
                    ;;
                nano)
                    pkgs+=("$NANO_PKGS")
                    ;;
                pkg-config)
                    pkgs+=("$PKG_CONFIG_PKGS")
                    ;;
                sed)
                    pkgs+=("$SED_PKGS")
                    ;;
                tar)
                    pkgs+=("$TAR_PKGS")
                    ;;
                parallel)
                    pkgs+=("$PARALLEL_PKGS")
                    ;;
                wget)
                    pkgs+=("$WGET_PKGS")
                    ;;
                which)
                    pkgs+=("$WHICH_PKGS")
                    ;;
            esac
        done
    fi

    # Remove duplicate packages and sort alphabetically
    extra="${pkgs[*]}"
    read -r -a additions <<< "$extra"
    local total current=0
    pkgs=()
    for pkg in "${additions[@]}"; do
        [[ -z ${seen[$pkg]:-} ]] || continue
        seen[$pkg]=1
        pkgs+=("$pkg")
    done

    total="${#pkgs[@]}"
    local -a available_pkgs=()
    for pkg in "${pkgs[@]}"; do
        current=$((current + 1))
        show_dependency_progress "$current" "$total" "$pkg"
        if apt-cache show "$pkg" &> /dev/null; then
            available_pkgs+=("$pkg")
        else
            [[ ! -t 1 ]] || printf '\r\033[K'
            log "Package $pkg is not available in the apt database and will be skipped."
        fi
    done

    log "Dependency scan complete: $total packages checked; ${#available_pkgs[@]} available for installation."

    if [[ "${#available_pkgs[@]}" -gt 0 ]]; then
        log "Refreshing APT metadata and installing available build dependencies."
        sudo apt update
        sudo apt install -y "${available_pkgs[@]}"
    fi
}

set_compiler_flags() {
    CC="gcc"
    CXX="g++"
    CFLAGS="-O2 -pipe -march=native"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-Wl,-rpath=$install_dir/lib"
    PATH="/usr/lib/ccache:$PATH"
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig"
    export CC CXX CFLAGS CXXFLAGS LDFLAGS PATH PKG_CONFIG_PATH
}

get_latest_version_url() {
    local prog_name version
    prog_name=$1
    if [[ "$prog_name" == "pkg-config" ]]; then
        version=$(gnu_curl -fsS "https://pkgconfig.freedesktop.org/releases/" | grep -oP 'pkg-config-\K[0-9]+\.[0-9\.]+(?=\.tar\.gz)' | sort -ruV | sed -n '1p')
    else
        version=$(gnu_curl -fsS "https://ftp.gnu.org/gnu/$prog_name/" | grep -oP "$prog_name-\K([0-9.]+)(?=\.tar\.)" | sort -ruV | sed -n '1p')
    fi
    if [[ -z "$version" ]]; then
        fail "Failed to find the latest version for $prog_name. Please check the program name or the respective server."
    fi
    echo "$version"
}

download_and_extract() {
    local archive_url found=false

    if [[ "$prog_name" == "pkg-config" ]]; then
        archive_url="https://pkgconfig.freedesktop.org/releases/pkg-config-$version.tar.gz"
    else
        archive_url="https://ftp.gnu.org/gnu/$prog_name/$prog_name-$version.tar"
        for ext in xz bz2 gz lz; do
            if gnu_wget --spider "$archive_url.$ext" &>/dev/null; then
                archive_url+=".$ext"
                found=true
                break
            fi
        done
        [[ "$found" == true ]] || fail "No supported archive was found for $prog_name $version."
    fi

    gnu_wget --show-progress -cqO "$cwd/$archive_name.${archive_url##*.}" "$archive_url" || fail "Failed to download archive with WGET. Line: $LINENO"
    tar -xf "$cwd/$archive_name.${archive_url##*.}" -C "$cwd/$archive_name" --strip-components 1 || fail "Failed to extract: $cwd/$archive_name.${archive_url##*.}"
}

configure_build() {
    cd "$cwd/$archive_name" || fail "Failed to cd into $cwd/$archive_name. Line: $LINENO"

    case "$prog_name" in
        autoconf)
            ./configure --prefix="$install_dir" || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        bash)
            ./configure --prefix="$install_dir" --enable-static-link --enable-multibyte || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        findutils)
            ./configure --prefix="$install_dir" --enable-threads=posix --disable-nls || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        gawk)
            ./configure --prefix="$install_dir" --disable-nls --with-readline=/usr --with-mpfr=/usr || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        grep)
            ./configure --prefix="$install_dir" --disable-nls --enable-threads=posix --with-libsigsegv --with-libsigsegv-prefix=/usr || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        gzip)
            ./configure --prefix="$install_dir" --disable-gcc-warnings --enable-silent-rules || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        libtool)
            ./configure --prefix="$install_dir" --enable-ltdl-install || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        make)
            ./configure --prefix="$install_dir" --enable-option-checking=fatal --disable-nls \
                        --enable-year2038 --with-dmalloc || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        nano)
            ./configure --prefix="$install_dir" --enable-utf8 || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        pkg-config)
            apply_pkg_config_c23_fix "$cwd/$archive_name"
            ./configure CPPFLAGS="-isystem /usr/include${CPPFLAGS:+ $CPPFLAGS}" \
                        --prefix="$install_dir" --with-internal-glib --disable-nls || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        sed)
            ./configure --prefix="$install_dir" --enable-threads=posix --disable-nls || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        tar)
            apply_tar_libiconv_fix "$cwd/$archive_name"
            ./configure --prefix="$install_dir" --disable-nls --disable-gcc-warnings --with-bzip2="$(command -v bzip2)" \
                        --with-lzip="$(command -v lzip)" --with-lzma="$(command -v lzma)" --with-xz="$(command -v xz)" \
                        --with-zstd="$(command -v zstd)" --with-lzop="$(command -v lzop)" --with-gzip="$(command -v gzip)" || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        wget)
            ./configure --prefix="$install_dir" --enable-option-checking=fatal --with-ssl=openssl \
                        --without-metalink --with-cares --with-libunistring-prefix=/usr \
                        --disable-nls || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        which)
            autoconf || fail "Failed to execute: autoconf. Line: $LINENO"
            ./configure --prefix="$install_dir" || fail "Failed to execute: configure. Line: $LINENO"
            ;;
        *)

            ./configure --prefix="$install_dir" --disable-nls || fail "Failed to execute: configure. Line: $LINENO"
            ;;
    esac
}

compile_and_install() {
    make "-j$gnu_jobs" || fail "Failed to execute: make build. Line: $LINENO"
    sudo make install || fail "Failed execute: make install. Line: $LINENO"
}

create_soft_links() {
    gnu_link_dir "$install_dir/bin" /usr/local/bin
    gnu_link_dir "$install_dir/lib/pkgconfig" /usr/local/lib/pkgconfig '*.pc'
    gnu_link_dir "$install_dir/include" /usr/local/include
}

ld_linker_path() {
    local ld_file="/etc/ld.so.conf.d/custom_libs.conf"
    if [[ ! -f "$ld_file" ]]; then
        echo -e "$install_dir/lib" | sudo tee "$ld_file" >/dev/null
    else
        grep -qxF "$install_dir/lib" "$ld_file" || echo "$install_dir/lib" | sudo tee -a "$ld_file" >/dev/null
    fi
    sudo ldconfig
}

cleanup() {
    rm -rf -- "$cwd"
}

build_program() {
    local prog_name version previous_dir
    prog_name="$1"
    version="$2"
    previous_dir="$PWD"

    echo
    log "Building $prog_name"
    if [[ -z "$version" ]]; then
        version=$(get_latest_version_url "$prog_name")
    fi
    archive_name="$prog_name-$version"
    install_dir="/usr/local/programs/$archive_name"
    cwd=$(gnu_new_workdir)
    mkdir -p "$cwd/$archive_name/build"
    set_compiler_flags
    download_and_extract
    configure_build
    compile_and_install "$version"
    ld_linker_path
    create_soft_links
    cd "$previous_dir" || fail "Failed to return to $previous_dir. Line: $LINENO"
    cleanup
}

# Build each specified program
IFS=',' read -ra progs <<< "$programs"
if [[ "$programs" == "all" ]]; then
    progs=("${available_programs[@]}")
fi

[[ -n "$programs" && "$programs" != ,* && "$programs" != *, && "$programs" != *,,* ]] || fail "Enter a nonempty program list."
for prog in "${progs[@]}"; do
    valid=false
    for available in "${available_programs[@]}"; do
        if [[ "$prog" == "$available" ]]; then valid=true; break; fi
    done
    [[ "$valid" == true ]] || fail "Unknown program: $prog. Use --help to list supported programs."
done

if [[ "$programs" == "all" ]]; then
    log "Selected all ${#progs[@]} programs."
else
    log "Selected programs: ${progs[*]}"
fi
log "Checking build dependencies."
required_packages "${progs[@]}"

for prog in "${progs[@]}"; do
    build_program "$prog" "$version"
done

echo
log "All specified programs have been built and installed successfully."
