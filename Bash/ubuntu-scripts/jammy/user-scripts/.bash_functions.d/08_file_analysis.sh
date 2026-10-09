#!/usr/bin/env bash
# File Analysis Functions

## UNIFIED FILE SIZE FINDER ##
# A unified function to find large files or directories with flexible options.
# Replaces big_files, big_file, big_vids, big_img, jpgsize, large_files.
find_large() {
    local count=10
    local min_size=""
    local type_filter=""
    local search_mode="file" # 'file' or 'dir'

    # Simple and portable argument parsing
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -c|--count) count="$2"; shift ;;
            -s|--min-size) min_size="$2"; shift ;;
            -t|--type) type_filter="$2"; shift ;;
            --dir) search_mode="dir" ;;
            -h|--help)
                echo "Usage: find_large [options]"
                echo "Options:"
                echo "  -c, --count N        Show top N results (default: 10)."
                echo "  -s, --min-size SIZE  Filter by minimum size (e.g., 10M, 1G)."
                echo "  -t, --type EXT       Filter by file extension (e.g., jpg, mp4)."
                echo "  --dir                Search for directories instead of files."
                echo "  -h, --help           Show this help message."
                return 0
                ;;
            *) echo "Unknown parameter: $1" >&2; return 1 ;;
        esac
        shift
    done

    if [[ "$search_mode" == "dir" ]]; then
        echo "Searching for top ${count} largest directories..."
        # du is best for finding directory sizes. -d 1 limits to current level.
        du -h -d 1 . 2>/dev/null | sort -hr | head -n "${count}"
    else
        echo "Searching for files..."
        local -a find_cmd=(find . -type f)
        [[ -n "$type_filter" ]] && find_cmd+=(-name "*.${type_filter}")
        [[ -n "$min_size" ]] && find_cmd+=(-size "+${min_size}")

        # -printf is efficient. We sort by size (%s) and then format output.
        "${find_cmd[@]}" -printf '%s %p\n' 2>/dev/null |
        sort -rn |
        head -n "${count}" |
        awk '{
            size=$1;
            path="";
            for(i=2; i<=NF; i++) { path=(path=="" ? "" : path " ") $i };
            # Human-readable size conversion
            split("B KB MB GB TB", units, " ");
            i=1;
            while (size > 1024 && i < 5) { size/=1024; i++; }
            printf "%.2f %s\t%s\n", size, units[i], path;
        }' | column -t
    fi
}

## TARGETED LINE COUNT ##
# Count lines (and optionally words / chars / bytes) of one or more *specific*
# files passed via -f/--file or as positional arguments. Unlike find_large
# (which searches), this operates only on the files you hand it.
file_size() {
    local ascending=0 no_sort=0 top_n=0
    local show_words=0 show_chars=0 show_bytes=0
    local no_blanks=0 no_total=0 quiet=0
    local -a files=()
    local -a _split

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--file)
                if [[ -z "${2:-}" ]]; then
                    echo "file_size: $1 requires a value" >&2
                    return 1
                fi
                IFS=',' read -r -a _split <<< "$2"
                # Shell-expands the first ~ in $2 but not the ones after each
                # comma — fix that so `-f ~/a,~/b` works as expected.
                local _i
                for ((_i=0; _i<${#_split[@]}; _i++)); do
                    case "${_split[_i]}" in
                        '~')   _split[_i]="$HOME" ;;
                        '~/'*) _split[_i]="$HOME/${_split[_i]#'~/'}" ;;
                    esac
                done
                files+=("${_split[@]}")
                shift 2
                ;;
            -a|--ascending) ascending=1; shift ;;
            -n|--no-sort)   no_sort=1; shift ;;
            -t|--top)
                if ! [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                    echo "file_size: --top requires a positive integer" >&2
                    return 1
                fi
                top_n="$2"; shift 2 ;;
            -w|--words)     show_words=1; shift ;;
            -c|--chars)     show_chars=1; shift ;;
            -b|--bytes)     show_bytes=1; shift ;;
            -B|--no-blanks) no_blanks=1; shift ;;
            -T|--no-total)  no_total=1; shift ;;
            -q|--quiet)     quiet=1; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: file_size -f FILES [options]
       file_size [options] FILE [FILE...]

Count lines (and optionally words / chars / bytes) of one or more target files.

File specification (at least one required):
  -f, --file FILES   Single file or comma-separated list of files. May be
                     repeated. Positional file args are also accepted and are
                     combined with any -f values (so globs like *.sh work).

Sorting:
  -a, --ascending    Sort smallest to largest (default: largest to smallest).
  -n, --no-sort      Preserve input order (no sort).
  -t, --top N        After sorting, keep only the top N rows.

Extra columns:
  -w, --words        Also show word count.
  -c, --chars        Also show character count (multibyte aware, wc -m).
  -b, --bytes        Also show byte count (file size on disk, wc -c).

Counting:
  -B, --no-blanks    Exclude blank/whitespace-only lines from the line count.

Output:
  -T, --no-total     Suppress the grand-total row when listing 2+ files.
  -q, --quiet        Print only line counts, one per line (script-friendly).
  -h, --help         Show this help message.

Examples:
  file_size -f script.sh
  file_size -f a.py,b.py,c.py --ascending
  file_size *.sh -w -b --top 5
  file_size --no-blanks -f main.go
  file_size *.md -q | paste -sd+ - | bc       # sum line counts across files
EOF
                return 0
                ;;
            --) shift; files+=("$@"); break ;;
            -*) echo "file_size: unknown option: $1 (try --help)" >&2; return 1 ;;
            *)  files+=("$1"); shift ;;
        esac
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "file_size: no files specified (try --help)" >&2
        return 1
    fi

    # Validate input — skip non-existent / unreadable / directory entries.
    local -a valid=()
    local f
    for f in "${files[@]}"; do
        if [[ ! -e "$f" ]]; then
            echo "file_size: skipping (not found): $f" >&2
        elif [[ -d "$f" ]]; then
            echo "file_size: skipping (is a directory): $f" >&2
        elif [[ ! -r "$f" ]]; then
            echo "file_size: skipping (not readable): $f" >&2
        else
            valid+=("$f")
        fi
    done

    if [[ ${#valid[@]} -eq 0 ]]; then
        echo "file_size: no valid files to process" >&2
        return 1
    fi

    # Collect metrics into TSV rows: lines<TAB>words<TAB>chars<TAB>bytes<TAB>path
    local -a rows=()
    local lines words chars bytes
    local total_lines=0 total_words=0 total_chars=0 total_bytes=0
    for f in "${valid[@]}"; do
        if (( no_blanks )); then
            # grep -c always prints a count; exit 1 when zero matches is fine.
            lines=$(grep -cvE '^[[:space:]]*$' -- "$f" 2>/dev/null || true)
        else
            lines=$(wc -l < "$f" 2>/dev/null)
        fi
        words=$(wc -w < "$f" 2>/dev/null)
        chars=$(wc -m < "$f" 2>/dev/null)
        bytes=$(wc -c < "$f" 2>/dev/null)
        # Strip whitespace that wc/grep may leave on the numbers.
        lines=${lines//[[:space:]]/}
        words=${words//[[:space:]]/}
        chars=${chars//[[:space:]]/}
        bytes=${bytes//[[:space:]]/}
        : "${lines:=0}" "${words:=0}" "${chars:=0}" "${bytes:=0}"
        rows+=("${lines}"$'\t'"${words}"$'\t'"${chars}"$'\t'"${bytes}"$'\t'"${f}")
        total_lines=$((total_lines + lines))
        total_words=$((total_words + words))
        total_chars=$((total_chars + chars))
        total_bytes=$((total_bytes + bytes))
    done

    # Sort by line count (column 1) unless suppressed.
    local sorted
    if (( no_sort )); then
        sorted=$(printf '%s\n' "${rows[@]}")
    else
        local sort_flag="-rn"
        (( ascending )) && sort_flag="-n"
        sorted=$(printf '%s\n' "${rows[@]}" | sort -t$'\t' -k1,1 "$sort_flag")
    fi

    # Limit to top N.
    if (( top_n > 0 )); then
        sorted=$(printf '%s\n' "$sorted" | head -n "$top_n")
    fi

    # Quiet mode: just the line counts, one per row, in current order.
    if (( quiet )); then
        printf '%s\n' "$sorted" | awk -F'\t' '{print $1}'
        return 0
    fi

    # Pretty table. Columns: LINES [WORDS] [CHARS] [BYTES] FILE
    {
        local hdr="LINES"
        (( show_words )) && hdr+=$'\t'"WORDS"
        (( show_chars )) && hdr+=$'\t'"CHARS"
        (( show_bytes )) && hdr+=$'\t'"BYTES"
        hdr+=$'\t'"FILE"
        printf '%s\n' "$hdr"

        printf '%s\n' "$sorted" | awk -F'\t' -v OFS='\t' \
            -v sw="$show_words" -v sc="$show_chars" -v sb="$show_bytes" '
            {
                out = $1
                if (sw) out = out OFS $2
                if (sc) out = out OFS $3
                if (sb) out = out OFS $4
                print out OFS $5
            }'

        if (( ! no_total )) && (( ${#valid[@]} > 1 )); then
            local trow="$total_lines"
            (( show_words )) && trow+=$'\t'"$total_words"
            (( show_chars )) && trow+=$'\t'"$total_chars"
            (( show_bytes )) && trow+=$'\t'"$total_bytes"
            trow+=$'\t'"TOTAL (${#valid[@]} files)"
            printf '%s\n' "$trow"
        fi
    } | column -t -s $'\t'
}

## DEPRECATED FILE SIZE FUNCTIONS ##
# The functions below are deprecated - use find_large instead
big_files() {
  local num_results full_path size folder file suffix
  # Check if an argument is provided
  if [[ -n "$1" && "$1" =~ ^[0-9]+$ ]]; then
    num_results=$1
  else
    # Prompt the user to enter the number of results
    read -rp "Enter the number of results to display: " num_results
    while ! [[ "$num_results" =~ ^[0-9]+$ ]]; do
      read -rp "Invalid input. Enter a valid number: " num_results
    done
  fi
  echo "Largest Folders:"
  du -h -d 1 2>/dev/null | sort -hr | head -n "$num_results" | while read -r size folder; do
    full_path=$(realpath "$folder")
    suffix="${size: -1}"
    size=$(echo "${size%?}" | awk '{printf "%d.%02d", $1, int(($1-int($1))*100)}')
    printf "%-80s %14s%s\n" "$full_path" "$size" "$suffix"
  done | column -t
  echo
  echo "Largest Files:"
  find . -type f -exec du -h {} + 2>/dev/null | sort -hr | head -n "$num_results" | while read -r size file; do
    full_path=$(realpath "$file")
    suffix="${size: -1}"
    size=$(echo "${size%?}" | awk '{printf "%d.%02d", $1, int(($1-int($1))*100)}')
    printf "%-80s %14s%s\n" "$full_path" "$size" "$suffix"
  done | column -t
}

big_file() {
    find . -type f -print0 | du -ha --files0-from=- | LC_ALL='C' sort -rh | head -n "$1"
}

big_vids() {
    local count
    if [[ -n "$1" ]]; then
        count=$1
    else
        read -rp "Enter the max number of results: " count
        echo
    fi
    echo "Listing the $count largest videos"
    echo
    sudo find "$PWD" -type f \( -iname "*.mkv" -o -iname "*.mp4" \) -exec du -Sh {} + | grep -Ev "\(x265\)" | sort -hr | head -n "$count"
}

big_img() {
    clear
    sudo find . -size +10M -type f -name "*.jpg" 2>/dev/null
}

jpgsize() {
    local random_dir size

    random_dir=$(mktemp -d)
    read -rp "Enter the image size (units in MB): " size
    find . -size +"$size"M -type f -iname "*.jpg" > "$random_dir/img-sizes.txt"
    sed -i "s/^..//g" "$random_dir/img-sizes.txt"
    sed -i "s|^|$PWD\/|g" "$random_dir/img-sizes.txt"
    echo
    nohup gnome-text-editor "$random_dir/img-sizes.txt" &>/dev/null &
}

##########################
## SORT IMAGES BY WIDTH ##
##########################

jpgs() {
    local random_dir
    random_dir=$(mktemp -d)
    # shellcheck disable=SC2024 # writing to the user-owned mktemp dir is intentional; only find needs sudo
    sudo find . -type f -iname "*.jpg" -exec identify -format " $PWD/%f: %wx%h " {} \; > "$random_dir/img-sizes.txt"
    sed 's/\s\//\n\//g' "$random_dir/img-sizes.txt" | sort -h
    rm -fr "$random_dir"
}

###################################
## FFPROBE LIST IMAGE DIMENSIONS ##
###################################

ffp() {
    [[ -f 00-pic-sizes.txt ]] && sudo rm 00-pic-sizes.txt
    sudo find "$PWD" -type f -iname "*.jpg" -exec bash -c 'identify -format "%wx%h" "$1"; echo "$1"' _ {} \; | sudo tee 00-pic-sizes.txt >/dev/null
}

## List large files by type
large_files() {
    local choice
    clear

    if [[ -z "$1" ]]; then
        echo "Input the FILE extension to search for without a dot: "
        read -rp "Enter your choice: " choice
        clear
    else
        choice=$1
    fi

    sudo find "$PWD" -type f -name "*.$choice" -printf "%s %h\n" | sort -ru -o "large-files.txt"

    if [[ -f "large-files.txt" ]]; then
        sudo gnome-text-editor "large-files.txt"
        sudo rm "large-files.txt"
    fi
}

## MediaInfo
mi() {
    local file

    if [[ -z "$1" ]]; then
        ls -1AhFv --color --group-directories-first
        echo
        read -rp "Please enter the relative FILE path: " file
        echo
        mediainfo "$file"
    else
        mediainfo "$1"
    fi
}
