#!/usr/bin/env bash
# File Analysis Functions

## List large files by type
# Usage: large_files [EXTENSION]
# Lists every file with EXTENSION under the current folder, largest first, with full paths.
large_files() {
    local choice="${1-}"

    if [[ -z "$choice" ]]; then
        read -r -p "Enter the file extension to search for (without a dot): " choice || return 1
    fi
    choice=${choice#.}
    if [[ -z "$choice" ]]; then
        printf 'Usage: large_files EXTENSION\n' >&2
        return 1
    fi

    find "$PWD" -type f -iname "*.$choice" -printf '%s\t%p\n' |
        sort -t $'\t' -k1,1nr |
        numfmt -d $'\t' --field=1 --to=iec |
        less -FRX
}

## GET FILE SIZES ##

big_files() {
    local count="${1-}"
    if [[ -z "$count" ]]; then
        read -r -p 'Number of results: ' count || return 1
    fi
    [[ "$count" =~ ^[1-9][0-9]*$ ]] || {
        printf 'Usage: big_files [POSITIVE_COUNT]\n' >&2
        return 1
    }
    printf 'Largest Folders:\n'
    (
        set -o pipefail
        du -h --max-depth=1 --null . | LC_ALL=C sort -zrh | sed -z -n "1,${count}p" | tr '\0' '\n'
    ) || return
    printf '\nLargest Files:\n'
    big_file "$count"
}

big_file() (
    local count="${1:-20}"

    [[ "$count" =~ ^[1-9][0-9]*$ ]] || {
        printf 'Usage: big_file [POSITIVE_COUNT]\n' >&2
        return 1
    }
    set -o pipefail
    find . -type f -print0 | du -h --null --files0-from=- | LC_ALL=C sort -zrh | sed -z -n "1,${count}p" | tr '\0' '\n'
)

# Sizes are disk usage, matching du: each hard-linked file counts once toward a total.
# When stderr is a terminal, a progress bar shows percent done, elapsed time and time left.
# A first pass counts entries without reading their metadata so that the bar has an end.
dsize() (
    local recurse=0 show=0 cols=${COLUMNS:-80} path abs status=0 errors skipped entries began
    local opt value kib min_kib='' max_kib=''
    local -a paths=()
    local usage='Usage: dsize [-r] [-min SIZE] [-max SIZE] [PATH...]
  Show the total size of each PATH (default: current directory) with its full path.
  -r         List every file beneath PATH, recursively, with full paths, largest first.
  -min SIZE  List only files of at least SIZE (implies -r).
  -max SIZE  List only files of at most SIZE (implies -r).
  SIZE is a number with an optional unit, case-insensitive: B, K/KB/KiB, M/MB/MiB, G, T, P
  or E, all 1024-based like the sizes shown (e.g. 500K, 1.5GB, 2g). No unit means bytes.'

    # Prints SIZE in KiB, the unit find reports disk usage in.
    size_kib() {
        local re='^([0-9]+([.][0-9]*)?|[.][0-9]+)[[:space:]]*([kmgtpe]?)(i?b)?$' power
        [[ ${1,,} =~ $re ]] || return 1
        [[ -z ${BASH_REMATCH[3]} && ${BASH_REMATCH[4]} == ib ]] && return 1
        case ${BASH_REMATCH[3]} in
            '') power=0 ;; k) power=1 ;; m) power=2 ;; g) power=3 ;;
            t) power=4 ;; p) power=5 ;; e) power=6 ;;
        esac
        gawk -v n="${BASH_REMATCH[1]}" -v p="$power" 'BEGIN { printf "%.6f\n", n * 1024 ^ (p - 1) }'
    }

    local awk_lib='@load "time"
function clock(s) {
    s = int(s)
    return s >= 3600 ? sprintf("%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : sprintf("%d:%02d", s / 60, s % 60)
}
# A line wider than the terminal would wrap, and \r could no longer redraw it in place.
function show_line(text) { printf "\r\033[K%s", substr(text, 1, cols - 1) > "/dev/stderr"; fflush("/dev/stderr") }
function due(  now) { now = gettimeofday(); if (now - last < 0.1) return 0; last = now; return 1 }
BEGIN { start = gettimeofday() }
'
    local count_awk='
show && NR % 1024 == 0 && due() { show_line(sprintf("Counting entries... %\047d  %s", NR, clock(gettimeofday() - start))) }
END { printf "%d %.6f\n", NR, start }
'
    # Input: type, link count, device:inode, KiB used, path. Output records sort with the
    # total (kind 0) first, then files (kind 1) largest first.
    local scan_awk='
function repeat(c, n,  s) { s = ""; while (n-- > 0) s = s c; return s }
function bar(  width, fill, elapsed, left) {
    if (NR > entries) entries = NR
    width = 30
    fill = int(NR / entries * width)
    elapsed = gettimeofday() - start
    left = NR < entries && elapsed >= 1 ? "~" clock(elapsed * (entries - NR) / NR) " left" : ""
    show_line(sprintf("[%s%s] %3d%%  %\047d/%\047d  %s elapsed  %s", repeat("#", fill), repeat("-", width - fill), NR * 100 / entries, NR, entries, clock(elapsed), left))
}
BEGIN {
    RS = "\0"; ORS = "\0"
    while ((getline rec) > 0) {
        match(rec, /^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t/, f)
        kb = f[4] + 0
        counted = f[1] == "d" || f[2] < 2 || !(f[3] in seen)
        if (counted) total += kb
        if (f[1] != "d" && f[2] > 1) seen[f[3]]
        if (recurse && f[1] == "f" && (min_kib == "" || kb >= min_kib + 0) && (max_kib == "" || kb <= max_kib + 0)) {
            print "1\t" kb "\t" substr(rec, RLENGTH + 1)
            matched++
            if (counted) matched_kb += kb
        }
        if (show && (NR == 1 || due())) bar()
    }
    print "0\t" total "\t" NR "\t" matched_kb + 0 "\t" matched + 0
    if (show) { bar(); show_line(recurse ? "Sorting..." : "") }
}
'
    # Rounds like du -h: up, with one decimal below 10.
    local format_awk='
function ceil(x) { return x == int(x) ? x : int(x) + 1 }
function human(kb,  v, i) {
    if (kb == 0) return "0"
    i = 0
    for (v = kb + 0; v >= 1024 && i < 5; i++) v /= 1024
    if (v < 10 && (v = ceil(v * 10) / 10) < 10) return sprintf("%.1f%s", v, U[i])
    if ((v = ceil(v)) >= 1024 && i < 5) return sprintf("1.0%s", U[i + 1])
    return v U[i]
}
BEGIN {
    RS = "\0"
    split("K M G T P E", U, " ")
    for (i = 1; i <= 6; i++) U[i - 1] = U[i]
    while ((getline rec) > 0) {
        if (NR == 1 && show) show_line("")
        sep = index(rec, "\t"); kind = substr(rec, 1, sep - 1); rest = substr(rec, sep + 1)
        sep = index(rest, "\t"); kb = substr(rest, 1, sep - 1); rest = substr(rest, sep + 1)
        if (kind == 0) {
            split(rest, t, "\t")
            scanned = t[1]
            print (recurse ? "Total: " : "") human(kb) "\t" ENVIRON["DSIZE_PATH"]
            if (filtered) printf "Matching: %s in %\047d file(s)\n", human(t[2]), t[3]
        } else {
            print human(kb) "\t" rest
        }
    }
    if (recurse) print ""
    if (show) printf "dsize: scanned %\047d entries in %s\n", scanned, clock(gettimeofday() - began) > "/dev/stderr"
}
'

    command -v gawk > /dev/null || { printf 'dsize: gawk is required.\n' >&2; return 1; }
    while (($#)); do
        case "$1" in
            -r) recurse=1 ;;
            -min|--min|-max|--max|-min=*|--min=*|-max=*|--max=*)
                opt=${1%%=*} opt=${opt##*-}
                if [[ $1 == *=* ]]; then
                    value=${1#*=}
                elif (($# >= 2)); then
                    value=$2
                    shift
                else
                    printf 'dsize: -%s needs a size.\n%s\n' "$opt" "$usage" >&2
                    return 2
                fi
                kib=$(size_kib "$value") || {
                    printf 'dsize: invalid size for -%s: %s\n%s\n' "$opt" "$value" "$usage" >&2
                    return 2
                }
                if [[ $opt == min ]]; then min_kib=$kib; else max_kib=$kib; fi
                recurse=1
                ;;
            -h|--help) printf '%s\n' "$usage"; return 0 ;;
            --) shift; paths+=("$@"); break ;;
            -*) printf 'dsize: unknown option: %s\n%s\n' "$1" "$usage" >&2; return 2 ;;
            *) paths+=("$1") ;;
        esac
        shift
    done
    ((${#paths[@]})) || paths=(.)
    if [[ -n $min_kib && -n $max_kib ]] && gawk -v a="$min_kib" -v b="$max_kib" 'BEGIN { exit !(a + 0 > b + 0) }'; then
        printf 'dsize: -min is larger than -max.\n' >&2
        return 2
    fi
    [[ -t 2 ]] && show=1

    errors=$(mktemp) || return
    trap 'rm -f -- "$errors"; ((show)) && printf "\r\033[K" >&2' EXIT
    trap 'exit 130' INT
    set -o pipefail

    for path in "${paths[@]}"; do
        abs=$(realpath -e -- "$path") || { status=1; continue; }
        entries=0 began=0
        if ((show)); then
            read -r entries began < <(command find "$abs" -printf '\n' 2> /dev/null |
                gawk -v show=1 -v cols="$cols" "$awk_lib$count_awk")
        fi
        command find "$abs" -printf '%y\t%n\t%D:%i\t%k\t%p\0' 2>> "$errors" |
            gawk -v show="$show" -v cols="$cols" -v recurse="$recurse" -v entries="$entries" \
                -v min_kib="$min_kib" -v max_kib="$max_kib" "$awk_lib$scan_awk" |
            LC_ALL=C sort -z -t $'\t' -k1,1n -k2,2nr |
            DSIZE_PATH=$abs gawk -v show="$show" -v cols="$cols" -v recurse="$recurse" -v began="$began" \
                -v filtered="$([[ -n $min_kib$max_kib ]] && echo 1)" \
                "$awk_lib$format_awk" ||
            status=1
    done

    skipped=$(wc -l < "$errors")
    if ((skipped > 0)); then
        printf 'dsize: %d path(s) could not be read and were skipped.\n' "$skipped" >&2
        status=1
    fi
    return "$status"
)

big_vids() {
    local count="${1-}"
    if [[ -z "$count" ]]; then
        read -r -p "Enter the max number of results: " count || return 1
        echo
    fi
    if [[ ! "$count" =~ ^[1-9][0-9]*$ ]]; then
        printf 'Usage: big_vids [POSITIVE_COUNT]\n' >&2
        return 1
    fi
    echo "Listing the $count largest videos"
    echo
    find "$PWD" -type f \( -iname '*.mkv' -o -iname '*.mp4' \) -exec du -h -- {} + | sort -hr | head -n "$count"
}

_jpg_files_over_size() {
    local size="$1"
    [[ "$size" =~ ^[0-9]+$ ]] || {
        printf 'Image size must be a nonnegative whole number of MiB.\n' >&2
        return 1
    }
    find "$PWD" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -size "+${size}M"
}

big_img() {
    _jpg_files_over_size "${1:-10}"
}

jpgsize() {
    local size="${1-}"
    if [[ -z "$size" ]]; then
        read -r -p 'Minimum image size (MiB): ' size || return 1
    fi
    _jpg_files_over_size "$size"
}
