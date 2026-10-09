#!/usr/bin/env bash
# Child Bash processes evaluate the quoted source fragments below.
# shellcheck disable=SC2016
set -euo pipefail
ulimit -c 0

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scripts="$repo/Bash/installer-scripts/gnu-software"
sandbox=$(mktemp -d)
real_ln=$(command -v ln)
export REAL_LN="$real_ln"
trap 'rm -rf -- "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/run" "$sandbox/tmp"
export TEST_LOG="$sandbox/commands.log" TMPDIR="$sandbox/tmp"
export PATH="$sandbox/bin:$PATH"
export JOBS=2
checks=0
failures=0

check() {
    checks=$((checks + 1))
    if "$@"; then
        printf 'ok %s\n' "$checks"
    else
        printf 'FAIL %s: %s\n' "$checks" "$*" >&2
        failures=$((failures + 1))
    fi
}

# Every command that could download, compile, or modify the host is intercepted.
cat > "$sandbox/bin/mock" <<'MOCK'
#!/usr/bin/env bash
set -eu
name=${0##*/}
printf '%s' "$name" >> "$TEST_LOG"
printf ' <%s>' "$@" >> "$TEST_LOG"
printf '\n' >> "$TEST_LOG"
case "$name" in
    sudo) [[ ${FAIL_APT:-0} != 1 || $1 != apt* ]]; exit $? ;;
    apt|apt-get|dnf|pacman) exit 90 ;;
    dpkg-query) [[ ${MISSING_ALL:-0} != 1 ]] || exit 1; printf 'install ok installed'; exit 0 ;;
    dpkg) exit 0 ;;
    apt-cache) exit 0 ;;
    curl|wget)
        [[ ${FAIL_DOWNLOAD:-0} != 1 ]] || exit 22
        output=''
        url=''
        while (($#)); do
            case "$1" in
                -o|-O|--output) output=$2; shift ;;
                -Lso|-cqO) output=$2; shift ;;
                https://*|http://*) url=$1 ;;
            esac
            shift
        done
        if [[ -n $output ]]; then
            : > "$output"
        else
            program=${url%/}; program=${program##*/}
            printf '<a href="%s-999.12.34.tar.xz">archive</a>\n' "$program"
        fi
        ;;
    tar)
        [[ ${FAIL_EXTRACT:-0} != 1 ]] || exit 2
        dest=$PWD
        while (($#)); do
            if [[ $1 == -C ]]; then dest=$2; shift; fi
            shift
        done
        mkdir -p "$dest/build"
        cat > "$dest/configure" <<'CONFIGURE'
#!/usr/bin/env bash
printf 'configure <%s>\n' "$*" >> "$TEST_LOG"
exit "${FAIL_CONFIGURE:-0}"
CONFIGURE
        chmod +x "$dest/configure"
        : > "$dest/configure.ac"
        ;;
    make|ninja)
        [[ ${FAIL_BUILD:-0} != 1 ]] || exit 2
        [[ ${FAIL_CHECK:-0} != 1 || " $* " != *' check '* ]] || exit 2
        ;;
    cmake|meson) exit "${FAIL_CONFIGURE:-0}" ;;
    git)
        if [[ $1 == clone ]]; then
            dest=${*: -1}
            mkdir -p "$dest"
            cp "$MOCK_CONFIGURE" "$dest/configure"
            printf '#!/usr/bin/env bash\nexit 0\n' > "$dest/autogen.sh"
            chmod +x "$dest/autogen.sh"
        fi
        ;;
    find) exit 0 ;;
    gcc) printf 'x86_64-linux-gnu\n' ;;
    gpgv) exit "${FAIL_VERIFY:-0}" ;;
    ln|ldconfig|autoreconf|autoconf|autoupdate|clear|libtool) exit 0 ;;
    *) exit 91 ;;
esac
MOCK
chmod +x "$sandbox/bin/mock"
for name in sudo apt apt-get dnf pacman dpkg-query dpkg apt-cache curl wget tar \
            make ninja cmake meson git find gcc ln ldconfig autoreconf autoconf \
            autoupdate clear libtool gpgv; do
    ln -s mock "$sandbox/bin/$name"
done
cat > "$sandbox/configure" <<'CONFIGURE'
#!/usr/bin/env bash
printf 'configure <%s>\n' "$*" >> "$TEST_LOG"
exit "${FAIL_CONFIGURE:-0}"
CONFIGURE
chmod +x "$sandbox/configure"
export MOCK_CONFIGURE="$sandbox/configure"

run_script() {
    : > "$TEST_LOG"
    (cd "$sandbox/run" && timeout 5 bash "$scripts/$1" "${@:2}" </dev/null) \
        > "$sandbox/output" 2>&1
}

fails_before_build() {
    local script=$1 stage=$2
    if env "$stage=1" bash -c 'cd "$1"; timeout 5 bash "$2" </dev/null' \
        bash "$sandbox/run" "$scripts/$script" > "$sandbox/output" 2>&1; then
        return 1
    fi
    ! grep -Eq '^(make|ninja|sudo <make|sudo <ninja)' "$TEST_LOG"
}

for stage in FAIL_DOWNLOAD FAIL_EXTRACT FAIL_CONFIGURE; do
    : > "$TEST_LOG"
    check fails_before_build build-attr.sh "$stage"
done

cleanup_eof() {
    local source_file=$1 function_name=${2:-cleanup}
    awk -v name="$function_name" '
        $0 ~ "^" name "\\(\\) \\{" {printing=1}
        printing {print}
        printing && /^}/ {exit}
    ' "$source_file" > "$sandbox/function.sh"
    mkdir -p "$sandbox/keep"
    timeout 2 bash -c '
        cwd=$1; CWD=$1; build_dir=$1
        log() { :; }; warn() { :; }; log_msg() { :; }
        source "$2"
        "$3" </dev/null
    ' bash "$sandbox/keep" "$sandbox/function.sh" "$function_name" \
        > "$sandbox/cleanup-output" 2>&1 && [[ -d "$sandbox/keep" ]]
}
check cleanup_eof "$scripts/build-diffutils.sh"
check cleanup_eof "$scripts/build-autoconf-archive.sh"

invalid_program() {
    ! run_script build-all-gnu.sh -p '../../escape' && \
        ! grep -Eq '^(sudo|apt|wget|curl|make)' "$TEST_LOG"
}
check invalid_program

extract_function() {
    awk -v name="$2" '
        $0 ~ "^" name "\\(\\) \\{" {printing=1}
        printing {print}
        printing && /^}/ {exit}
    ' "$1"
}

gcc_dependencies() {
    : > "$TEST_LOG"
    extract_function "$scripts/build-gcc.sh" install_dependencies > "$sandbox/gcc-deps.sh"
    MISSING_ALL=1 bash -c '
        log() { :; }; fail() { exit 1; }; verbose_logging_cmd() { "$@"; }
        enable_multilib_flag=0; target_arch=x86_64-linux-gnu; dry_run=0
        source "$1"
        install_dependencies
    ' bash "$sandbox/gcc-deps.sh" > "$sandbox/output" 2>&1 &&
        grep -q 'sudo .*<install>.*<build-essential>' "$TEST_LOG"
}
check gcc_dependencies

gcc_missing_signature() {
    : > "$TEST_LOG"
    extract_function "$scripts/build-gcc.sh" gnu_curl > "$sandbox/gcc-verify.sh"
    extract_function "$scripts/build-gcc.sh" verify_checksum >> "$sandbox/gcc-verify.sh"
    ! FAIL_DOWNLOAD=1 bash -c '
        log() { :; }; fail() { exit 1; }
        source "$1"
        verify_checksum "$2/gcc-13.4.0.tar.xz" 13.4.0 https://ftp.gnu.org/gnu/gcc/gcc-13.4.0/gcc-13.4.0.tar.xz
    ' bash "$sandbox/gcc-verify.sh" "$sandbox" > "$sandbox/output" 2>&1
}
check gcc_missing_signature

gcc_verifies() {
    local verify_status=$1 expected=$2 status=0
    FAIL_VERIFY="$verify_status" bash -c '
        log() { :; }; fail() { exit 1; }
        source "$1"
        verify_checksum "$2/gcc-14.3.0.tar.xz" 14.3.0 https://ftp.gnu.org/gnu/gcc/gcc-14.3.0/gcc-14.3.0.tar.xz
    ' bash "$sandbox/gcc-verify.sh" "$sandbox" > "$sandbox/output" 2>&1 || status=$?
    [[ $status == "$expected" ]]
}
check gcc_verifies 0 0
check gcc_verifies 1 1

glibc_no_global_links() {
    : > "$TEST_LOG"
    extract_function "$scripts/build-glibc.sh" create_symlinks > "$sandbox/glibc-links.sh"
    bash -c 'log() { :; }; warn() { :; }; install_dir=$1; source "$2"; if declare -F create_symlinks >/dev/null; then create_symlinks; fi' \
        bash "$sandbox/glibc-prefix" "$sandbox/glibc-links.sh" > "$sandbox/output" 2>&1 &&
        ! grep -q '^ln' "$TEST_LOG"
}
check glibc_no_global_links

glibc_failed_checks_stop() {
    extract_function "$scripts/build-glibc.sh" build_glibc > "$sandbox/glibc-build.sh"
    mkdir -p "$sandbox/glibc-source/glibc-2.39"
    cp "$MOCK_CONFIGURE" "$sandbox/glibc-source/glibc-2.39/configure"
    ! FAIL_CHECK=1 bash -c '
        log() { :; }; warn() { :; }; fail() { exit 1; }
        working=$1; archive_dir=glibc-2.39; install_dir=$2
        CPU_CORES=2; CFLAGS=""; CXXFLAGS=""; LDFLAGS=""
        source "$3"
        build_glibc
    ' bash "$sandbox/glibc-source" "$sandbox/glibc-prefix" "$sandbox/glibc-build.sh" \
        > "$sandbox/output" 2>&1
}
check glibc_failed_checks_stop

link_publication() {
    local script=$1
    extract_function "$scripts/$script" gnu_link_dir > "$sandbox/link-function.sh"
    mkdir -p "$sandbox/link-source" "$sandbox/link-destination"
    touch "$sandbox/link-source/library.pc" "$sandbox/link-source/ignored.txt"
    bash -c '
        sudo() {
            if [[ $1 == ln ]]; then shift; "$REAL_LN" "$@"; else "$@"; fi
        }
        source "$1"
        gnu_link_dir "$2" "$3/new destination" "*.pc"
        [[ -L "$3/new destination/library.pc" && ! -e "$3/new destination/ignored.txt" ]]
        mkdir -p "$3/conflict/library.pc"
        if gnu_link_dir "$2" "$3/conflict" "*.pc"; then exit 1; fi
        mkdir -p "$2/empty"
        gnu_link_dir "$2/empty" "$3/empty"
        [[ ! -e "$3/empty" ]]
    ' bash "$sandbox/link-function.sh" "$sandbox/link-source" "$sandbox/link-destination" \
        > "$sandbox/output" 2>&1
}
for name in bash gawk findutils grep gzip nano readline sed tar binutils coreutils libtool \
            libiconv libiconv-gettext all-gnu pkg-config; do
    check link_publication "build-$name.sh"
done

invalid_compiler() {
    ! run_script "$1" --compiler '../escape' && ! grep -Eq '^(sudo|curl|wget|make)' "$TEST_LOG"
}
for name in bash findutils gawk grep gzip nano readline sed tar; do
    check invalid_compiler "build-$name.sh"
done

invalid_jobs() {
    ! JOBS=0 run_script build-attr.sh && ! grep -Eq '^(sudo|curl|wget|make)' "$TEST_LOG"
}
check invalid_jobs

private_workdirs() {
    extract_function "$scripts/build-attr.sh" gnu_new_workdir > "$sandbox/workdir-function.sh"
    bash -c '
        source "$1"
        first=$(gnu_new_workdir); second=$(gnu_new_workdir)
        [[ $first != "$second" && -d $first && -d $second ]]
        [[ $(stat -c "%a" "$first") == 700 && $(stat -c "%a" "$second") == 700 ]]
        if TMPDIR=relative gnu_new_workdir; then exit 1; fi
    ' bash "$sandbox/workdir-function.sh" > "$sandbox/output" 2>&1
}
check private_workdirs

libiconv_exports_compiler_flags() {
    extract_function "$scripts/build-libiconv.sh" set_env_vars > "$sandbox/libiconv-env.sh"
    bash -c '
        source "$1"
        set_env_vars
        bash -c '\''[[ "$CXXFLAGS" == "$CFLAGS" && -n "$CXXFLAGS" ]]'\''
    ' bash "$sandbox/libiconv-env.sh"
}
check libiconv_exports_compiler_flags

gcc_summary() {
    : > "$TEST_LOG"
    extract_function "$scripts/build-gcc.sh" main > "$sandbox/gcc-main.sh"
    bash -c '
        set -euo pipefail
        log() { printf "%s\\n" "$*" >> "$TEST_LOG"; }
        fail() { exit 1; }
        parse_args() { :; }; setup_logging() { :; }
        check_system_resources() { :; }; set_path() { :; }
        set_pkg_config_path() { :; }; set_environment() { :; }
        install_dependencies() { :; }; install_required_autoconf() { :; }
        check_disk_space_for_selected_versions() { :; }
        select_gcc_versions_to_build() { selected_versions=(13); }
        get_latest_gcc_release_version() { printf "13.4.0\\n"; }
        build_gcc_version() {
            mkdir -p "$user_prefix/gcc-$1/bin"
            printf "#!/usr/bin/env bash\\nprintf '\''gcc (GCC) 13.4.0\\\\n'\''\\n" > "$user_prefix/gcc-$1/bin/gcc-13"
            chmod +x "$user_prefix/gcc-$1/bin/gcc-13"
        }
        cleanup_temporary_folders() { rm -rf -- "$build_dir"; }
        user_prefix=$1; SCRIPT_VERSION=1.9; log_file=""; debug_mode=0
        dry_run=0; verbose=0; keep_build_dir=0; static_build=0; save_binaries=0
        optimization_level=-O2; target_arch=x86_64-linux-gnu
        YELLOW=""; GREEN=""; CYAN=""; RED=""; NC=""
        source "$2"
        main
    ' bash "$sandbox/gcc-prefix" "$sandbox/gcc-main.sh" > "$sandbox/output" 2>&1 &&
        grep -q 'Status: SUCCESS' "$TEST_LOG"
}
check gcc_summary

gcc_static_save() {
    extract_function "$scripts/build-gcc.sh" save_static_binaries > "$sandbox/gcc-save.sh"
    mkdir -p "$sandbox/gcc-save-prefix/gcc-13.4.0/bin" "$sandbox/gcc-save-work"
    for binary in cpp g++ gcc gcc-ar gcc-nm gcc-ranlib gcov gcov-dump gcov-tool gfortran; do
        touch "$sandbox/gcc-save-prefix/gcc-13.4.0/bin/$binary-13"
    done
    bash -c '
        set -euo pipefail
        log() { :; }; fail() { exit 1; }; sudo() { "$@"; }
        verbose_logging_cmd() { "$@"; }
        user_prefix=$1; saved_binary_root=$2; static_build=1; save_binaries=1; dry_run=0
        cd "$3"
        source "$4"
        save_static_binaries 13.4.0
        [[ -f "$saved_binary_root/gcc-13.4.0-static-binaries/gcc-13" ]]
        [[ ! -e "$PWD/gcc-13.4.0-static-binaries" ]]
    ' bash "$sandbox/gcc-save-prefix" "$sandbox/saved" "$sandbox/gcc-save-work" \
        "$sandbox/gcc-save.sh" > "$sandbox/output" 2>&1
}
check gcc_static_save

gcc_publish_success() {
    extract_function "$scripts/build-gcc.sh" create_symlinks |
        sed 's|symlink_target_dir="/usr/local/bin"|symlink_target_dir="$test_dest"|' > "$sandbox/gcc-links.sh"
    mkdir -p "$sandbox/gcc-link-prefix/gcc-13.4.0/bin" "$sandbox/gcc-link-target"
    cp "$MOCK_CONFIGURE" "$sandbox/gcc-link-prefix/gcc-13.4.0/bin/gcc-13"
    bash -c '
        set -euo pipefail
        log() { :; }; verbose_logging_cmd() { "$@"; }
        sudo() { if [[ $1 == ln ]]; then shift; "$REAL_LN" "$@"; else "$@"; fi; }
        user_prefix=$1; test_dest=$2; dry_run=0; verbose=0
        source "$3"
        create_symlinks 13.4.0
        [[ -L "$test_dest/gcc" && -L "$test_dest/gcc-13" ]]
    ' bash "$sandbox/gcc-link-prefix" "$sandbox/gcc-link-target" "$sandbox/gcc-links.sh" \
        > "$sandbox/output" 2>&1
}
check gcc_publish_success

gcc_prerequisite_downloads() {
    local fail_download=$1 expected=$2 status=0
    : > "$TEST_LOG"
    extract_function "$scripts/build-gcc.sh" download_gcc_prerequisites > "$sandbox/prerequisite-function.sh"
    mkdir -p "$sandbox/prerequisite-work"
    cat > "$sandbox/prerequisite-recipe" <<'RECIPE'
#!/usr/bin/env bash
set -e
wget -q -O "$TEST_LOG.archive" http://gcc.gnu.org/pub/gcc/infrastructure/gmp.tar.bz2
curl -fsSL -o "$TEST_LOG.archive" ftp://gcc.gnu.org/pub/gcc/infrastructure/mpfr.tar.bz2
RECIPE
    chmod +x "$sandbox/prerequisite-recipe"
    FAIL_DOWNLOAD="$fail_download" bash -c '
        log() { :; }; verbose_logging_cmd() { "$@"; }
        build_dir=$1
        source "$2"
        download_gcc_prerequisites "$3"
    ' bash "$sandbox/prerequisite-work" "$sandbox/prerequisite-function.sh" "$sandbox/prerequisite-recipe" \
        > "$sandbox/output" 2>&1 || status=$?
    [[ $status == "$expected" ]] &&
        grep -q '<https://gcc.gnu.org/pub/gcc/infrastructure/gmp.tar.bz2>' "$TEST_LOG" &&
        grep -q '<--user-agent=Mozilla/5.0' "$TEST_LOG" &&
        grep -q '<--timeout=30>' "$TEST_LOG"
}
check gcc_prerequisite_downloads 0 0
check gcc_prerequisite_downloads 1 22

selected_versions() {
    run_script build-parallel.sh -v 20231022 &&
        grep -q '<https://ftp.gnu.org/gnu/parallel/parallel-20231022.tar.bz2>' "$TEST_LOG"
}
check selected_versions

help_is_offline() {
    local script=$1
    run_script "$script" --help && ! grep -Eq '^(curl|wget|sudo)' "$TEST_LOG"
}
for name in bash findutils gawk grep gzip nano readline sed tar autoconf parallel emacs; do
    [[ $name != emacs ]] || continue
    check help_is_offline "build-$name.sh"
done

invalid_version() {
    ! run_script "$1" -v '../escape' && ! grep -Eq '^(sudo|curl|wget|make)' "$TEST_LOG"
}
for name in bash findutils gawk grep gzip nano readline sed tar autoconf parallel emacs make; do
    check invalid_version "build-$name.sh"
done

mkdir -p "$sandbox/run/attr-build-script"
touch "$sandbox/run/attr-build-script/keep-me"
for script in "$scripts"/*.sh; do
    name=${script##*/}
    case "$name" in
        build-gcc.sh|build-ninja.sh|build-wget.sh|build-glibc.sh|build-automake.sh) continue ;;
        build-all-gnu.sh) args=(-p autoconf) ;;
        *) args=() ;;
    esac
    if ! run_script "$name" "${args[@]}"; then
        printf '%s failed in sandbox:\n' "$name" >&2
        cat "$sandbox/output" >&2
        failures=$((failures + 1))
    fi
    checks=$((checks + 1))
    printf 'flow %s: %s\n' "$checks" "$name"
done
check test -f "$sandbox/run/attr-build-script/keep-me"

for script in "$scripts"/*.sh; do
    name=${script##*/}
    case "$name" in
        build-gcc.sh|build-ninja.sh|build-wget.sh|build-glibc.sh|build-automake.sh|build-all-gnu.sh) continue ;;
    esac
    for stage in FAIL_DOWNLOAD FAIL_EXTRACT FAIL_CONFIGURE; do
        [[ "$name" != build-isl.sh || "$stage" == FAIL_CONFIGURE ]] || continue
        : > "$TEST_LOG"
        check fails_before_build "$name" "$stage"
    done
done

printf '%s checks, %s failures\n' "$checks" "$failures"
((failures == 0))
