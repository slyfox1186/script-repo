#!/usr/bin/env bash
set -Eeuo pipefail

readonly MIN_MIRRORS=5

print_help() {
    cat <<'EOF'
Usage: update_mirrorlist.sh [options]

Rank, validate, and safely install an Arch Linux mirrorlist.

Options:
  -h, --help                  Display this help message.
  -a, --age HOURS             Maximum synchronization age (default: 12).
  -c, --country COUNTRIES     Comma-separated country filter (default: United States).
  -f, --fastest NUMBER        Number of mirrors to retain (default: 5; minimum: 5).
  -t, --timeout SECONDS       Per-download timeout (default: 5).
  -l, --latest NUMBER         Optionally limit by most recent synchronization.
      --score NUMBER          Mirror Status score shortlist (default: 20).
  -p, --protocols https       Mirror protocol; only HTTPS is accepted.
  -s, --save ABSOLUTE_PATH    Destination (default: /etc/pacman.d/mirrorlist).
      --non-interactive       Do not display configuration prompts.
      --dry-run               Validate candidates without installing them.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_value() {
    (($# >= 2)) && [[ -n $2 ]] || die "$1 requires a value"
}

require_positive_integer() {
    [[ $2 =~ ^[1-9][0-9]*$ ]] || die "$1 must be a positive integer"
}

if ((EUID == 0)); then
    as_root=()
else
    as_root=(sudo)
fi

age=12
country='United States'
fastest=5
timeout=5
latest=
score=20
protocols=https
save=/etc/pacman.d/mirrorlist
non_interactive=false
dry_run=false

while (($#)); do
    case $1 in
        -h|--help)
            print_help
            exit 0
            ;;
        -a|--age|-c|--country|-f|--fastest|-t|--timeout|-l|--latest|--score|-p|--protocols|-s|--save)
            require_value "$@"
            option=$1
            value=$2
            shift 2
            case $option in
                -a|--age) age=$value ;;
                -c|--country) country=$value ;;
                -f|--fastest) fastest=$value ;;
                -t|--timeout) timeout=$value ;;
                -l|--latest) latest=$value ;;
                --score) score=$value ;;
                -p|--protocols) protocols=$value ;;
                -s|--save) save=$value ;;
            esac
            ;;
        --non-interactive)
            non_interactive=true
            shift
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        --)
            shift
            (($# == 0)) || die "unexpected argument: $1"
            ;;
        *) die "unknown option: $1" ;;
    esac
done

require_positive_integer age "$age"
require_positive_integer fastest "$fastest"
require_positive_integer timeout "$timeout"
[[ -z $latest ]] || require_positive_integer latest "$latest"
require_positive_integer score "$score"
((fastest >= MIN_MIRRORS)) || die "--fastest must be at least $MIN_MIRRORS"
[[ -z $latest ]] || ((latest >= fastest)) || die '--latest must be greater than or equal to --fastest'
[[ $protocols == https ]] || die '--protocols must be https'
[[ $save == /* ]] || die '--save must be an absolute path'
[[ -n $country ]] || die '--country must not be empty'
if ! $non_interactive; then
    printf 'Selecting the %s fastest HTTPS mirrors from %s synchronized within %s hours.\n' \
        "$fastest" "$country" "$age"
fi

if ! command -v reflector >/dev/null 2>&1; then
    printf 'Reflector is not installed; installing it with a full system upgrade.\n'
    "${as_root[@]}" pacman -Syu --needed --noconfirm reflector
fi

candidate=$(mktemp "${TMPDIR:-/tmp}/arch-mirrorlist.XXXXXX")
verified_candidate=$(mktemp "${TMPDIR:-/tmp}/arch-mirrorlist-verified.XXXXXX")
cleanup() {
    rm -f -- "$candidate" "$verified_candidate"
}
trap cleanup EXIT

printf 'Ranking current mirrors...\n'
candidate_count=$((fastest * 2))
reflector_args=(
    --age "$age"
    --number "$candidate_count"
    --download-timeout "$timeout"
    --score "$score"
    --protocol "$protocols"
    --completion-percent 100
    --ipv4
    --exclude '(cicku\.me|mirrors\.misaka\.one|zackmyers\.io)'
    --save "$candidate"
    --sort rate
)
[[ -n $country ]] && reflector_args+=(--country "$country")
[[ -n $latest ]] && reflector_args+=(--latest "$latest")
reflector "${reflector_args[@]}"

mapfile -t servers < <(awk '
    /^[[:space:]]*Server[[:space:]]*=/ {
        sub(/^[[:space:]]*Server[[:space:]]*=[[:space:]]*/, "")
        if (!seen[$0]++) print
    }
' "$candidate")

((${#servers[@]} >= MIN_MIRRORS)) || die "Reflector returned fewer than $MIN_MIRRORS distinct mirrors"
for server in "${servers[@]}"; do
    [[ $server == https://* ]] || die "candidate contains a non-HTTPS server: $server"
done

pending_artifacts=()
while IFS='|' read -r repo location; do
    case $repo in
        core|extra|multilib)
            filename=${location##*/}
            [[ -n $filename ]] && pending_artifacts+=("$repo|$filename")
            ;;
    esac
done < <(pacman -Sup --print-format '%r|%l' 2>/dev/null || true)

printf 'Checking ranked mirrors against enabled repositories and pending packages...\n'
{
    printf '################################################################################\n'
    printf '############ Arch Linux mirrorlist validated by update_mirrorlist.sh ###########\n'
    printf '################################################################################\n\n'
} >"$verified_candidate"
verified_count=0
for server in "${servers[@]}"; do
    mirror_ok=true
    for repo in core extra multilib; do
        probe=${server//\$repo/$repo}
        probe=${probe//\$arch/x86_64}
        probe=${probe%/}/${repo}.db
        if ! curl --fail --silent --show-error --location --head \
            --connect-timeout "$timeout" --max-time "$((timeout * 2))" -- "$probe" >/dev/null; then
            mirror_ok=false
            printf 'Rejected %s: %s metadata was unavailable.\n' "$server" "$repo" >&2
            break
        fi
    done
    if $mirror_ok; then
        for artifact in "${pending_artifacts[@]}"; do
            repo=${artifact%%|*}
            filename=${artifact#*|}
            base=${server//\$repo/$repo}
            base=${base//\$arch/x86_64}
            for suffix in '' .sig; do
                probe=${base%/}/${filename}${suffix}
                if ! curl --fail --silent --show-error --location --head \
                    --connect-timeout "$timeout" --max-time "$((timeout * 2))" -- "$probe" >/dev/null; then
                    mirror_ok=false
                    printf 'Rejected %s: pending artifact %s%s was unavailable.\n' \
                        "$server" "$filename" "$suffix" >&2
                    break 2
                fi
            done
        done
    fi
    if $mirror_ok; then
        printf 'Server = %s\n' "$server" >>"$verified_candidate"
        verified_count=$((verified_count + 1))
        ((verified_count >= fastest)) && break
    fi
done
((verified_count >= fastest)) || die "fewer than $fastest mirrors served all repository metadata and pending artifacts"
mv -- "$verified_candidate" "$candidate"

if $dry_run; then
    printf 'Validated %s HTTPS mirrors; dry run left %s unchanged.\n' "$verified_count" "$save"
    sed -n '1,80p' "$candidate"
    exit 0
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
staged="${save}.new.$$"
if "${as_root[@]}" test -e "$save"; then
    backup="${save}.backup-${timestamp}"
    "${as_root[@]}" cp --archive -- "$save" "$backup"
    printf 'Backed up the existing mirrorlist to %s.\n' "$backup"
fi

"${as_root[@]}" install --owner=root --group=root --mode=0644 -- "$candidate" "$staged"
if ! "${as_root[@]}" mv -- "$staged" "$save"; then
    "${as_root[@]}" rm -f -- "$staged"
    die 'failed to install the validated mirrorlist'
fi

printf 'Installed %s validated HTTPS mirrors in %s.\n' "$verified_count" "$save"
