#!/usr/bin/env bash
# Compression and Archive Functions

## UNCOMPRESS FILES ##
untar() (
    local archive dirname ext item_dirname source_dir temp_dir
    local -a items

    for archive in *; do
        ext="${archive##*.}"
        case "$ext" in
            7z|bz2|gz|lz|tgz|xz|zip) ;;
            *) continue ;;
        esac

        dirname="${archive%.*}"
        [[ "$archive" =~ \.tar\.(gz|bz2|lz|xz)$ ]] && dirname="${dirname%.*}"
        mkdir -p "$dirname"

        case "$ext" in
            7z) 7z x -y -spe "$archive" -o"$dirname" ;;
            zip) temp_dir=$(mktemp -d) || return 1
                 item_dirname=""
                 if ! unzip -o "$archive" -d "$temp_dir"; then
                     rm -rf -- "$temp_dir"
                     return 1
                 fi
                 shopt -s nullglob dotglob
                 items=("$temp_dir"/*)
                 shopt -u nullglob dotglob
                 source_dir="$temp_dir"
                 if [[ "${#items[@]}" -eq 1 && -d "${items[0]}" ]]; then
                     item_dirname="${items[0]##*/}"
                 fi
                 if [[ "${#items[@]}" -eq 1 && "$item_dirname" == "$dirname" ]]; then
                     source_dir="${items[0]}"
                 fi
                 if ((${#items[@]} > 0)); then
                     if ! cp -a -- "$source_dir/." "$dirname/"; then
                         rm -rf -- "$temp_dir"
                         return 1
                     fi
                 fi
                 rm -rf -- "$temp_dir"
                 ;;
            gz|tgz|bz2|xz|lz)
                tar -xf "$archive" -C "$dirname" --strip-components 1 ;;
        esac
    done
)

# Gzip
gzip() {
    command gzip -d "$@"
}

# Create a tar.gz file with max compression settings
7z_gz() {
    local source output
    if [[ -n "$1" ]]; then
        if [[ -f "$1.tar.gz" ]]; then
            sudo rm "$1.tar.gz"
        fi
        7z a -ttar -so -an "$1" | 7z a -tgzip -mx9 -mpass1 -si "$1.tar.gz"
    else
        read -r -p "Please enter the source folder path: " source
        read -r -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [[ -f "$output.tar.gz" ]]; then
            sudo rm "$output.tar.gz"
        fi
        7z a -ttar -so -an "$source" | 7z a -tgzip -mx9 -mpass1 -si "$output.tar.gz"
    fi
}

# Create a tar.xz file with max compression settings using 7zip
7z_xz() {
    local source output
    if [[ -n "$1" ]]; then
        if [[ -f "$1.tar.xz" ]]; then
            sudo rm "$1.tar.xz"
        fi
        7z a -ttar -so -an "$1" | 7z a -txz -mx9 -si "$1.tar.xz"
    else
        read -r -p "Please enter the source folder path: " source
        read -r -p "Please enter the destination archive path (w/o extension): " output
        echo
        if [[ -f "$output.tar.xz" ]]; then
            sudo rm "$output.tar.xz"
        fi
        7z a -ttar -so -an "$source" | 7z a -txz -mx9 -si "$output.tar.xz"
    fi
}

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
