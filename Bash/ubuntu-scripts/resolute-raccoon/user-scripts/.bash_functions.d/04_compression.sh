#!/usr/bin/env bash
# Compression and Archive Functions

## UNCOMPRESS FILES ##

# Extracts every supported archive in the current folder. Multi-file archives go into a folder
# named after the archive; when an archive holds a single top-level folder, its contents are
# placed there directly. Single-file .gz, .bz2, .xz and .lz files are decompressed beside the
# original, which is kept. Returns 1 if any archive failed.
untar() (
    local archive dirname lower source_dir staging status=0
    local -a items

    shopt -s nullglob dotglob
    for archive in *; do
        [[ -f "$archive" ]] || continue
        lower=${archive,,}
        case "$lower" in
            *.tar.gz|*.tar.bz2|*.tar.xz|*.tar.lz|*.tar.zst) dirname=${archive%.*}; dirname=${dirname%.*} ;;
            *.tgz|*.tbz2|*.txz|*.tar|*.zip|*.7z) dirname=${archive%.*} ;;
            *.gz) gzip -dk -- "$archive" || status=1; continue ;;
            *.bz2) bzip2 -dk -- "$archive" || status=1; continue ;;
            *.xz) xz -dk -- "$archive" || status=1; continue ;;
            *.lz) lzip -dk -- "$archive" || status=1; continue ;;
            *) continue ;;
        esac

        staging=$(mktemp -d "./.untar.XXXXXX") || return 1
        case "$lower" in
            *.zip) unzip -q -o -- "$archive" -d "$staging" ;;
            *.7z) 7z x -y -bd -o"$staging" -- "$archive" > /dev/null ;;
            *) tar -xf "$archive" -C "$staging" ;;
        esac || {
            printf 'Extraction failed: %s\n' "$archive" >&2
            rm -rf -- "$staging"
            status=1
            continue
        }

        items=("$staging"/*)
        source_dir=$staging
        if ((${#items[@]} == 1)) && [[ -d "${items[0]}" && ! -L "${items[0]}" ]]; then
            source_dir=${items[0]}
        fi
        if mkdir -p -- "$dirname" && cp -a -- "$source_dir/." "$dirname/"; then
            printf 'Extracted: %s -> %s/\n' "$archive" "$dirname"
        else
            status=1
        fi
        rm -rf -- "$staging"
    done
    return "$status"
)

# Usage: _7z_tarball FORMAT EXTENSION [SOURCE]
# Streams SOURCE through 7-Zip's tar writer into SOURCE.tar.EXTENSION at maximum compression.
_7z_tarball() (
    local format="$1" extension="$2" source="${3-}" output=""

    set -o pipefail
    if [[ -z "$source" ]]; then
        read -r -p "Please enter the source folder path: " source || return 1
        read -r -p "Please enter the destination archive path (w/o extension, blank to use the source path): " output || return 1
        echo
    fi
    while [[ "$source" != / && "$source" == */ ]]; do
        source=${source%/}
    done
    if [[ "$source" == / || ! -e "$source" ]]; then
        printf 'Invalid source: %s\n' "$source" >&2
        return 1
    fi
    while [[ "$output" == */ ]]; do
        output=${output%/}
    done
    output="${output:-$source}.tar.$extension"
    if [[ -e "$output" || -L "$output" ]]; then
        printf 'Archive already exists; refusing to overwrite: %s\n' "$output" >&2
        return 1
    fi

    if ! 7z a -ttar -so -an -- "$source" | 7z a "-t$format" -mx9 -si -- "$output" > /dev/null; then
        rm -f -- "$output"
        printf 'Compression failed: %s\n' "$source" >&2
        return 1
    fi
    printf 'Created: %s\n' "$output"
)

# Create a tar.gz file with max compression settings using 7zip
7z_gz() { _7z_tarball gzip gz "$@"; }

# Create a tar.xz file with max compression settings using 7zip
7z_xz() { _7z_tarball xz xz "$@"; }

# Shared implementation; the public names remain compression-level presets.
_7z_dir_snapshot() (
    set -o pipefail
    find "$1" -printf '%P\t%y\t%s\t%T@\t%C@\t%l\0' | LC_ALL=C sort -z | sha256sum
)

_7z_archive() (
    local level="$1" source_dir="${2-}" archive_name choice snapshot current_snapshot staging_dir

    if (($# > 2)); then
        printf 'Usage: 7z_1|7z_5|7z_9 [DIRECTORY]\n' >&2
        return 1
    fi
    case "$level" in
        1|5|9) ;;
        *) return 1 ;;
    esac
    if [[ -z "$source_dir" ]]; then
        read -r -p 'Source directory: ' source_dir || return 1
    fi
    while [[ "$source_dir" != / && "$source_dir" == */ ]]; do
        source_dir=${source_dir%/}
    done
    if [[ -L "$source_dir" ]]; then
        printf 'Use the real directory path instead of a symbolic link.\n' >&2
        return 1
    fi
    if [[ ! -d "$source_dir" ]]; then
        printf 'Invalid directory: %s\n' "$source_dir" >&2
        return 1
    fi
    source_dir=$(realpath -e -- "$source_dir") || return
    case "$source_dir" in
        /|"$HOME")
            printf 'Refusing to archive and offer deletion of %s.\n' "$source_dir" >&2
            return 1 ;;
    esac
    archive_name="$(pwd -P)/${source_dir##*/}.7z"
    case "$archive_name" in
        "$source_dir"/*)
            printf 'Run this command outside the source directory.\n' >&2
            return 1 ;;
    esac
    if [[ -e "$archive_name" || -L "$archive_name" ]]; then
        printf 'Archive already exists; refusing to overwrite: %s\n' "$archive_name" >&2
        return 1
    fi
    snapshot=$(_7z_dir_snapshot "$source_dir") || return
    staging_dir=$(mktemp -d -- "${archive_name%/*}/.7z-archive.XXXXXX") || return
    trap 'rm -r -- "$staging_dir"' EXIT

    # Archive from inside the folder to include hidden files without a shell glob.
    builtin cd -- "$source_dir" || return
    if ! 7z a -t7z -m0=lzma2 "-mx$level" -- "$staging_dir/archive.7z" .; then
        printf 'Compression failed. Source directory retained.\n' >&2
        return 1
    fi
    if ! 7z t -- "$staging_dir/archive.7z"; then
        printf 'Archive verification failed. Source directory retained.\n' >&2
        return 1
    fi
    current_snapshot=$(_7z_dir_snapshot "$source_dir") || return
    if [[ "$current_snapshot" != "$snapshot" ]]; then
        printf 'Source changed during compression. Source directory retained.\n' >&2
        return 1
    fi
    # A hard link publishes on the same filesystem without replacing an existing file.
    ln -- "$staging_dir/archive.7z" "$archive_name" || return
    printf '\nArchive verified: %s\n' "$archive_name"
    read -r -p "Delete $source_dir? [1] Yes [2] No (default): " choice || choice=2
    case "$choice" in
        1)
            current_snapshot=$(_7z_dir_snapshot "$source_dir") || return
            if [[ "$current_snapshot" != "$snapshot" ]]; then
                printf 'Source changed after compression. Source directory retained.\n' >&2
                return 1
            fi
            builtin cd -- / || return
            rm -rf -- "$source_dir" || return
            printf 'Original directory deleted.\n' ;;
        *) printf 'Original directory retained.\n' ;;
    esac
)

7z_1() { _7z_archive 1 "$@"; }
7z_5() { _7z_archive 5 "$@"; }
7z_9() { _7z_archive 9 "$@"; }

## RECURSIVELY UNZIP ZIP FILES AND NAME THE OUTPUT FOLDER THE SAME NAME AS THE ZIP FILE
zipr() {
    clear
    find . -type f -iname '*.zip' -exec sh -c 'for archive do unzip -o -d "${archive%.*}" "$archive" && trash-put "$archive"; done' sh {} +
}
