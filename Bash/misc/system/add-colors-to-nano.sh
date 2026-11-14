#!/usr/bin/env bash
# Turn on nano's syntax and interface colors system-wide for every nano on PATH.
#
# All color settings live in /etc/nanorc. A nano built from source with only
# --prefix reads $prefix/etc/nanorc instead and silently ignores /etc/nanorc,
# so this script links that path to /etc/nanorc. It also installs a pinned,
# checksum-verified release of galenguyer/nano-syntax-highlighting for the
# languages nano lacks, and removes the per-file syntax includes that older
# versions of this script appended to ~/.nanorc (they override /etc/nanorc).
#
# Run it as your normal user; it calls sudo only for system files.
# Safe to run again: anything already correct is left untouched.

set -Eeuo pipefail
trap 'printf "Failed at line %s.\n" "$LINENO" >&2' ERR

# To move to a newer release, update the tag and the sha256 of its tarball.
syntax_tag="2026.11.01"
syntax_sha256="8b12b151e3f7550835b539c1bff33c30484a311df85adb6173fed1c43099da1c"
syntax_url="https://github.com/galenguyer/nano-syntax-highlighting/archive/refs/tags/$syntax_tag.tar.gz"
syntax_dir="/usr/local/share/nano-syntax-highlighting"
system_rc="/etc/nanorc"
user_rc="$HOME/.nanorc"
user_agent='Mozilla/5.0 (X11; Linux x86_64; rv:160.0) Gecko/20100101 Firefox/160.0'

# When two syntaxes claim the same file, the one included last wins: the extra
# set only fills gaps, nano's own syntaxes override it, and local files win.
include_dirs=("$syntax_dir" /usr/share/nano /usr/share/nano/extra /usr/local/share/nano)

check_only=false
reinstall=false
pending=0
work_dir=""

usage() {
    local name=${0##*/} h="" o="" v="" b="" d="" r=""
    # Color only a terminal, and honor NO_COLOR (https://no-color.org).
    # Magenta headings match the title and status bars this script gives nano.
    if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
        h=$'\e[1;35m'
        o=$'\e[1;36m'
        v=$'\e[33m'
        b=$'\e[1m'
        d=$'\e[2m'
        r=$'\e[0m'
    fi
    cat <<EOF
${b}${name}${r} turns on nano's syntax and interface colors for every
nano on PATH.

${h}Usage${r}
  ${b}${name}${r} [${o}--check${r}] [${o}--reinstall${r}]

${h}What it does${r}
  1. Links ${v}<prefix>/etc/nanorc${r} to ${v}$system_rc${r} for each source-built nano
     that would otherwise ignore ${v}$system_rc${r}.
  2. Installs extra syntax files from galenguyer/nano-syntax-highlighting
     release ${v}$syntax_tag${r}, checksum verified, into
     ${v}$syntax_dir${r}.
  3. Adds the syntax includes and interface colors to ${v}$system_rc${r}.
  4. Removes leftover syntax includes from ${v}~/.nanorc${r} that would override
     ${v}$system_rc${r}. Skipped when run as root.

  ${v}$system_rc${r} and ${v}~/.nanorc${r} are backed up before they change. Anything
  already correct is left alone, so the script is safe to run again.

${h}Options${r}
  ${o}--check${r}       Show what would change, with a diff for ${v}$system_rc${r},
                and change nothing.
  ${o}--reinstall${r}   Download and reinstall the syntax files even if release
                ${v}$syntax_tag${r} is already installed.
  ${o}-h${r}, ${o}--help${r}    Show this help and exit.

${h}Examples${r}
  ${d}# Preview the changes${r}
  ${name} ${o}--check${r}

  ${d}# Apply them${r}
  ${name}

${h}Exit status${r}
  ${b}0${r}   Success. With ${o}--check${r}, nothing needs to change.
  ${b}1${r}   With ${o}--check${r}, changes are needed. Errors also exit non-zero.

Run it as your normal user. It calls sudo only to change system files.
EOF
}

log() { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

cleanup() {
    if [[ -n $work_dir ]]; then
        rm -rf -- "$work_dir"
    fi
}
trap cleanup EXIT

run_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Record a needed change; in --check mode, report it instead of making it.
needs_change() {
    pending=$((pending + 1))
    if [[ $check_only == true ]]; then
        log "Would: $*"
        return 1
    fi
    log "Doing: $*"
}

# A source build compiles its config directory into the binary. Distro builds
# use /etc, so only a binary containing "$prefix/etc" reads somewhere else.
link_system_rc_for_each_nano() {
    local bin real prefix sysconfdir rc found=false
    local -A seen=()

    while IFS= read -r bin; do
        found=true
        real=$(readlink -f -- "$bin")
        [[ -z ${seen[$real]+set} ]] || continue
        seen[$real]=1

        prefix=${real%/bin/*}
        sysconfdir=/etc
        if [[ $prefix != "$real" ]] && grep -qaF -- "$prefix/etc" "$real"; then
            sysconfdir="$prefix/etc"
        fi

        if [[ $sysconfdir == /etc ]]; then
            log "OK: $real reads $system_rc"
            continue
        fi

        rc="$sysconfdir/nanorc"
        if [[ -L $rc && $(readlink -f -- "$rc") == "$(readlink -f -- "$system_rc")" ]]; then
            log "OK: $real reads $rc, which links to $system_rc"
        elif [[ -e $rc || -L $rc ]]; then
            warn "$real reads $rc, which is not $system_rc; left unchanged. Merge it by hand or replace it with a link."
        elif needs_change "link $rc to $system_rc so $real uses the system colors"; then
            run_root mkdir -p -- "$sysconfdir"
            run_root ln -s -- "$system_rc" "$rc"
        fi
    done < <(type -ap nano)

    [[ $found == true ]] || die "nano is not installed or not on PATH."
}

install_syntax_files() {
    local archive actual staged tool
    local -a files

    if [[ $reinstall == false && -f $syntax_dir/VERSION ]] &&
        grep -qxF "galenguyer/nano-syntax-highlighting tag $syntax_tag" "$syntax_dir/VERSION"; then
        log "OK: extra syntax files $syntax_tag are installed in $syntax_dir"
        return
    fi
    needs_change "install extra syntax files $syntax_tag into $syntax_dir" || return 0

    for tool in curl tar sha256sum; do
        command -v "$tool" >/dev/null || die "$tool is required to download the syntax files."
    done

    work_dir=$(mktemp -d)
    archive="$work_dir/syntax.tar.gz"
    curl -fsSL --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 15 \
        --user-agent "$user_agent" -o "$archive" "$syntax_url" ||
        die "Could not download $syntax_url"

    actual=$(sha256sum -- "$archive")
    actual=${actual%% *}
    [[ $actual == "$syntax_sha256" ]] ||
        die "Checksum mismatch for $syntax_url (expected $syntax_sha256, got $actual)."

    mkdir -- "$work_dir/src"
    tar -xzf "$archive" -C "$work_dir/src" --strip-components 1 --no-same-owner
    shopt -s nullglob
    files=("$work_dir/src"/*.nanorc)
    shopt -u nullglob
    [[ ${#files[@]} -gt 0 ]] || die "The downloaded release contains no .nanorc files."

    staged="$work_dir/stage"
    mkdir -- "$staged"
    cp -- "${files[@]}" "$staged/"
    cat > "$staged/VERSION" <<EOF
galenguyer/nano-syntax-highlighting tag $syntax_tag
$syntax_url
sha256 $syntax_sha256
installed $(date +%F); loaded by $system_rc below nano's built-in syntaxes
EOF

    # Build the new directory beside the old one and swap, so nano never sees
    # a half-installed set.
    run_root rm -rf -- "$syntax_dir.new" "$syntax_dir.old"
    run_root install -d -m 755 -- "$syntax_dir.new"
    run_root install -m 644 -- "$staged"/* "$syntax_dir.new/"
    if [[ -d $syntax_dir ]]; then
        run_root mv -- "$syntax_dir" "$syntax_dir.old"
    fi
    run_root mv -- "$syntax_dir.new" "$syntax_dir"
    run_root rm -rf -- "$syntax_dir.old"
    log "Installed ${#files[@]} syntax files into $syntax_dir"
}

is_managed_include() {
    local line=$1 dir
    for dir in "${include_dirs[@]}"; do
        if [[ $line == "include \"$dir/*.nanorc\"" || $line == "include $dir/*.nanorc" ]]; then
            return 0
        fi
    done
    return 1
}

# Rewrite /etc/nanorc so the syntax includes appear once, in precedence order,
# where the first of them already sits. Every other line is kept as it is.
update_system_rc() {
    local line dir placed=false candidate backup
    local -a lines=() wanted=() result=()

    for dir in "${include_dirs[@]}"; do
        if [[ $dir == "$syntax_dir" ]] || compgen -G "$dir/*.nanorc" >/dev/null; then
            wanted+=("include \"$dir/*.nanorc\"")
        fi
    done

    if [[ -f $system_rc ]]; then
        mapfile -t lines < "$system_rc"
    fi

    for line in "${lines[@]}"; do
        if is_managed_include "$line"; then
            if [[ $placed == false ]]; then
                result+=("${wanted[@]}")
                placed=true
            fi
            continue
        fi
        result+=("$line")
    done

    if [[ $placed == false ]]; then
        result+=(
            ""
            "## Syntax coloring. When two syntaxes claim the same file, the one"
            "## included last wins. ~/.nanorc must not include syntax files, or it"
            "## would override these."
            "${wanted[@]}"
        )
    fi

    if ! grep -qE '^[[:space:]]*set[[:space:]]+(titlecolor|statuscolor|keycolor)' <(printf '%s\n' "${lines[@]}"); then
        result+=(
            ""
            "## Paint the interface elements of nano."
            "set titlecolor bold,white,magenta"
            "set promptcolor black,yellow"
            "set statuscolor bold,white,magenta"
            "set errorcolor bold,white,red"
            "set spotlightcolor black,orange"
            "set selectedcolor lightwhite,cyan"
            "set stripecolor ,yellow"
            "set scrollercolor magenta"
            "set numbercolor magenta"
            "set keycolor lightmagenta"
            "set functioncolor magenta"
        )
    fi

    if [[ -z $work_dir ]]; then
        work_dir=$(mktemp -d)
    fi
    candidate="$work_dir/nanorc"
    printf '%s\n' "${result[@]}" > "$candidate"
    # Compare line by line so a missing final newline alone is not a change.
    printf '%s\n' "${lines[@]}" > "$work_dir/current"

    if [[ -f $system_rc ]] && cmp -s -- "$candidate" "$work_dir/current"; then
        log "OK: $system_rc has the syntax includes and interface colors"
        return
    fi

    if [[ $check_only == true ]]; then
        needs_change "update $system_rc as follows:" || true
        if [[ -f $system_rc ]]; then
            diff -u -- "$system_rc" "$candidate" || true
        else
            diff -u -- /dev/null "$candidate" || true
        fi
        return
    fi
    needs_change "update $system_rc with the syntax includes and interface colors"

    if [[ -f $system_rc ]]; then
        backup="$system_rc.$(date +%Y%m%d-%H%M%S).bak"
        run_root cp -p -- "$system_rc" "$backup"
        log "Backed up the old file to $backup"
    fi
    run_root install -m 644 -- "$candidate" "$system_rc"
}

# Earlier versions of this script appended one include per syntax file to
# ~/.nanorc. Those load after /etc/nanorc and override it, so remove them.
clean_user_rc() {
    local line backup
    local -a lines=() kept=() removed=() other=()

    if [[ $EUID -eq 0 ]]; then
        log "Skipped the ~/.nanorc check: run as your own user to check yours."
        return
    fi
    if [[ ! -f $user_rc ]]; then
        log "OK: no $user_rc"
        return
    fi

    mapfile -t lines < "$user_rc"
    for line in "${lines[@]}"; do
        if [[ $line =~ ^include\ (/usr/share/nano|$HOME/\.nano)/[^/[:space:]]+\.nanorc$ ]]; then
            removed+=("$line")
        else
            kept+=("$line")
            if [[ $line =~ ^[[:space:]]*include[[:space:]] ]]; then
                other+=("$line")
            fi
        fi
    done

    if [[ ${#other[@]} -gt 0 ]]; then
        warn "$user_rc has includes that override $system_rc; review them by hand:"
        printf '    %s\n' "${other[@]}" >&2
    fi

    if [[ ${#removed[@]} -eq 0 ]]; then
        log "OK: $user_rc has no leftover syntax includes"
    elif needs_change "remove ${#removed[@]} leftover syntax includes from $user_rc"; then
        backup=$(mktemp "${TMPDIR:-/tmp}/nanorc-backup.XXXXXX")
        cp -p -- "$user_rc" "$backup"
        printf '%s\n' "${kept[@]}" > "$user_rc"
        log "Backed up the old file to $backup"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) check_only=true ;;
        --reinstall) reinstall=true ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1. Run ${0##*/} --help to see the options." ;;
    esac
    shift
done

link_system_rc_for_each_nano
install_syntax_files
update_system_rc
clean_user_rc

if [[ $check_only == true ]]; then
    if [[ $pending -gt 0 ]]; then
        log "$pending change(s) needed. Run without --check to apply them."
        exit 1
    fi
    log "Everything is already set up."
elif [[ $pending -gt 0 ]]; then
    log "Done. Open a new nano session to see the colors."
else
    log "Everything was already set up; nothing changed."
fi
