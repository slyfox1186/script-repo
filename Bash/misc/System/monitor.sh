#!/usr/bin/env bash

# Live, color-coded view of filesystem events under a directory tree.
# Based on: https://github.com/slyfox1186/script-repo/blob/main/Bash/Misc/System/monitor.sh
# Script version: 2.0
# Last update: 09-29-26
#
# Arguments take priority over the defaults below.

readonly VERSION="2.0"
readonly PROG="${0##*/}"

monitor_dir="$PWD"
events="create,delete,modify,move"
include_access=false
log_file=""
exclude_re=""
include_re=""
full_paths=false
show_date=false
collapse=true
use_color=true

readonly KNOWN_EVENTS=(access modify attrib close_write close_nowrite close open
                       moved_to moved_from move move_self create delete delete_self unmount)
# Display order for the help legend and the exit summary.
readonly EVENT_ORDER=(CREATE DELETE MODIFY CLOSE_WRITE ATTRIB MOVED_FROM MOVED_TO
                      ACCESS OPEN CLOSE_NOWRITE DELETE_SELF MOVE_SELF UNMOUNT)

init_colors() {
    if [[ $use_color == true ]]; then
        R=$'\e[0m' B=$'\e[1m'
        C_HEAD=$'\e[1;93m' C_FLAG=$'\e[92m' C_ARG=$'\e[96m' C_DEF=$'\e[38;5;245m'
        C_TIME=$'\e[38;5;242m' C_PATH=$'\e[38;5;246m' C_FILE=$'\e[1;97m' C_DIR=$'\e[1;94m'
        C_OBJ=$'\e[38;5;180m' C_TMP=$'\e[38;5;243m' C_COUNT=$'\e[1;33m'
        C_ERR=$'\e[1;91m' C_OK=$'\e[92m' C_NOTE=$'\e[38;5;244m'
    else
        R='' B='' C_HEAD='' C_FLAG='' C_ARG='' C_DEF='' C_TIME='' C_PATH=''
        C_FILE='' C_DIR='' C_OBJ='' C_TMP='' C_COUNT='' C_ERR='' C_OK='' C_NOTE=''
    fi

    MARK=x
    [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} =~ [Uu][Tt][Ff]-?8 ]] && MARK=$'\u00d7'

    declare -gA EV_COLOR=()
    [[ $use_color == true ]] || return 0
    EV_COLOR=(
        [CREATE]=$'\e[1;92m'        [DELETE]=$'\e[1;91m'
        [MODIFY]=$'\e[93m'          [CLOSE_WRITE]=$'\e[32m'
        [ATTRIB]=$'\e[33m'          [MOVED_FROM]=$'\e[95m'
        [MOVED_TO]=$'\e[1;95m'      [ACCESS]=$'\e[36m'
        [OPEN]=$'\e[34m'            [CLOSE_NOWRITE]=$'\e[38;5;67m'
        [DELETE_SELF]=$'\e[1;97;41m' [MOVE_SELF]=$'\e[1;97;45m'
        [UNMOUNT]=$'\e[1;97;41m'
    )
}

die() {
    printf '%s%s:%s %s\n' "$C_ERR" "error" "$R" "$1" >&2
    [[ -n ${2:-} ]] && printf '%s%s%s\n' "$C_NOTE" "$2" "$R" >&2
    exit 1
}

# Prints one aligned option row; widths are measured on the uncolored text.
help_opt() {
    local short=$1 long=$2 arg=$3 desc=$4 note=${5:-} plain colored
    if [[ -n $short ]]; then
        plain="$short, $long"
        colored="$C_FLAG$short$R, $C_FLAG$long$R"
    else
        plain="    $long"
        colored="    $C_FLAG$long$R"
    fi
    if [[ -n $arg ]]; then
        plain+=" $arg"
        colored+=" $C_ARG$arg$R"
    fi
    printf '  %s%*s%s' "$colored" $((24 - ${#plain})) '' "$desc"
    [[ -n $note ]] && printf '  %s%s%s' "$C_DEF" "$note" "$R"
    printf '\n'
}

display_help() {
    local f=$C_FLAG a=$C_ARG d=$C_DEF h=$C_HEAD ev

    printf '%s%s%s %sv%s%s\n' "$B" "$PROG" "$R" "$d" "$VERSION" "$R"
    printf 'Watch a directory tree and print each file event as one colored line.\n\n'

    printf '%sUSAGE%s\n' "$h" "$R"
    printf '  %s %s[options]%s %s[directory]%s\n\n' "$PROG" "$f" "$R" "$a" "$R"

    printf '%sWHAT TO WATCH%s\n' "$h" "$R"
    help_opt -d --directory PATH  "Directory to watch" "(default: current directory)"
    help_opt -a --access    ""    "Also show ACCESS (file reads)" "(very noisy during builds)"
    help_opt -e --events    LIST  "Comma list of events, or all" "(default: $events)"
    help_opt -x --exclude   REGEX "Ignore paths matching REGEX"
    help_opt -i --include   REGEX "Only show paths matching REGEX"
    printf '\n%sOUTPUT%s\n' "$h" "$R"
    help_opt -l --log         FILE "Append every event to FILE as plain text"
    help_opt -f --full-paths  ""   "Show absolute paths" "(default: relative to the watched dir)"
    help_opt -D --date        ""   "Add the date to each timestamp"
    help_opt -C --no-collapse ""   "Print repeats on separate lines" "(default: fold them into ${MARK}N)"
    help_opt "" --no-color    ""   "Plain output" "(also off with NO_COLOR or when piped)"
    help_opt -h --help        ""   "Show this help"
    help_opt -V --version     ""   "Show the version"

    printf '\n%sEVENT COLORS%s\n' "$h" "$R"
    for ev in "${EVENT_ORDER[@]}"; do
        printf '  %s%-13s%s  %s\n' "${EV_COLOR[$ev]:-}" "$ev" "$R" "$(event_help "$ev")"
    done

    printf '\n%sFILE NAME COLORS%s\n' "$h" "$R"
    printf '  %s%-13s%s  %s\n' "$C_DIR" "src/" "$R" "directory" \
                              "$C_OBJ" "main.o" "$R" "object file or library (.o .a .so .pyc ...)" \
                              "$C_TMP" "notes.swp" "$R" "temp, swap, lock or partial download" \
                              "$C_FILE" "main.c" "$R" "any other file"

    printf '\n%sLINE FORMAT%s\n' "$h" "$R"
    printf '  %s05:15:51 AM%s  %s%-13s%s  %sbuild/prev-gcc/%s%sspecs%s  %s%s3%s\n' \
        "$C_TIME" "$R" "${EV_COLOR[MODIFY]:-}" MODIFY "$R" "$C_PATH" "$R" "$C_FILE" "$R" "$C_COUNT" "$MARK" "$R"
    printf '  %s%-11s  %-13s  %-20s  %s%s\n' "$d" time event "directory + file" repeats "$R"

    printf '\n%sEXAMPLES%s\n' "$h" "$R"
    printf '  %s# Watch the current directory%s\n' "$d" "$R"
    printf '  %s\n\n' "$PROG"
    printf '  %s# Watch a build tree with reads, skipping object files%s\n' "$d" "$R"
    printf '  %s %s-a -x%s %s%s%s %s~/src/project/build%s\n\n' "$PROG" "$f" "$R" "$a" "'\.o\$'" "$R" "$a" "$R"
    printf '  %s# Only finished writes, creates and deletes, logged to disk%s\n' "$d" "$R"
    printf '  %s %s-e%s %sclose_write,create,delete%s %s-l%s %s~/monitor.log%s %s/srv/uploads%s\n\n' \
        "$PROG" "$f" "$R" "$a" "$R" "$f" "$R" "$a" "$R" "$a" "$R"
    printf '  %s# Everything that happens%s\n' "$d" "$R"
    printf '  %s %s-e%s %sall%s %s/tmp%s\n\n' "$PROG" "$f" "$R" "$a" "$R" "$a" "$R"
    printf '%sCtrl-C stops watching and prints a count of each event type.%s\n' "$d" "$R"
}

event_help() {
    case $1 in
        CREATE)        echo "file or directory created" ;;
        DELETE)        echo "file or directory deleted" ;;
        MODIFY)        echo "contents written" ;;
        CLOSE_WRITE)   echo "closed after writing (file is complete)" ;;
        ATTRIB)        echo "permissions, owner or timestamps changed" ;;
        MOVED_FROM)    echo "renamed or moved away from here" ;;
        MOVED_TO)      echo "renamed or moved into here" ;;
        ACCESS)        echo "contents read" ;;
        OPEN)          echo "opened" ;;
        CLOSE_NOWRITE) echo "closed after reading only" ;;
        DELETE_SELF)   echo "the watched directory itself was deleted" ;;
        MOVE_SELF)     echo "the watched directory itself was moved" ;;
        UNMOUNT)       echo "the filesystem was unmounted" ;;
    esac
}

need_arg() {
    [[ -n ${2:-} ]] || die "option $1 needs a value" "Run '$PROG --help' for usage."
}

parse_arguments() {
    local want_help=false dir_set=false
    while (( $# )); do
        # Accept --opt=value as well as --opt value.
        if [[ $1 == --*=* ]]; then
            set -- "${1%%=*}" "${1#*=}" "${@:2}"
        fi
        case $1 in
            -a|--access)      include_access=true; shift ;;
            -d|--directory)   need_arg "$1" "${2:-}"; monitor_dir=$2; dir_set=true; shift 2 ;;
            -e|--events)      need_arg "$1" "${2:-}"; events=${2,,}; shift 2 ;;
            -x|--exclude)     need_arg "$1" "${2:-}"; exclude_re=$2; shift 2 ;;
            -i|--include)     need_arg "$1" "${2:-}"; include_re=$2; shift 2 ;;
            -l|--log)         need_arg "$1" "${2:-}"; log_file=$2; shift 2 ;;
            -f|--full-paths)  full_paths=true; shift ;;
            -D|--date)        show_date=true; shift ;;
            -C|--no-collapse) collapse=false; shift ;;
            --no-color)       use_color=false; shift ;;
            -h|--help)        want_help=true; shift ;;
            -V|--version)     echo "$PROG $VERSION"; exit 0 ;;
            --)               shift; break ;;
            -*)               init_colors; die "unknown option: $1" "Run '$PROG --help' for usage." ;;
            *)
                [[ $dir_set == true ]] && { init_colors; die "more than one directory given: $1"; }
                monitor_dir=$1; dir_set=true; shift ;;
        esac
    done
    if (( $# )); then
        [[ $dir_set == true || $# -gt 1 ]] && { init_colors; die "more than one directory given"; }
        monitor_dir=$1
    fi

    [[ -n ${NO_COLOR:-} || ! -t 1 ]] && use_color=false
    [[ -t 1 ]] || collapse=false
    init_colors

    if [[ $want_help == true ]]; then
        display_help
        exit 0
    fi
}

validate() {
    command -v inotifywait &>/dev/null ||
        die "inotifywait is not installed." "Install the inotify-tools package (Arch: sudo pacman -S inotify-tools)."

    [[ -d $monitor_dir ]] || die "not a directory: $monitor_dir"
    [[ -r $monitor_dir && -x $monitor_dir ]] || die "no permission to read: $monitor_dir"
    monitor_dir=$(cd -- "$monitor_dir" && pwd) || die "cannot open: $monitor_dir"

    events=${events// /}
    if [[ $events != all ]]; then
        local ev list=() bad=()
        IFS=, read -ra list <<< "$events"
        for ev in "${list[@]}"; do
            [[ -z $ev ]] && continue
            [[ " ${KNOWN_EVENTS[*]} " == *" $ev "* ]] || bad+=("$ev")
        done
        (( ${#bad[@]} )) && die "unknown event(s): ${bad[*]}" "Valid: ${KNOWN_EVENTS[*]} all"
        if [[ $include_access == true && ,$events, != *,access,* ]]; then
            events+=",access"
        fi
    fi

    if [[ -n $log_file ]]; then
        { exec {log_fd}>>"$log_file"; } 2>/dev/null || die "cannot write to log file: $log_file"
    fi
}

# Tints inotifywait's own status and error lines so they stand apart from events.
relay_stderr() {
    local line
    while IFS= read -r line; do
        case $line in
            *"upper limit"*|*"max_user_watches"*)
                printf '%s%s%s\n' "$C_ERR" "$line" "$R"
                printf '%sRaise the limit with: sudo sysctl fs.inotify.max_user_watches=524288%s\n' "$C_NOTE" "$R" ;;
            *[Ff]ailed*|*[Ee]rror*|*"Couldn't"*|*"No such"*)
                printf '%s%s%s\n' "$C_ERR" "$line" "$R" ;;
            "Watches established.")
                printf '%s%s%s\n' "$C_OK" "$line" "$R" ;;
            *)
                printf '%s%s%s\n' "$C_NOTE" "$line" "$R" ;;
        esac
    done >&2
}

print_header() {
    printf '%s%s%s %sv%s%s  watching %s%s%s\n' "$B" "$PROG" "$R" "$C_DEF" "$VERSION" "$R" "$C_DIR" "$monitor_dir" "$R"
    printf '%sevents:%s %s' "$C_NOTE" "$R" "$events"
    [[ -n $exclude_re ]] && printf '   %sexclude:%s %s' "$C_NOTE" "$R" "$exclude_re"
    [[ -n $include_re ]] && printf '   %sinclude:%s %s' "$C_NOTE" "$R" "$include_re"
    [[ -n $log_file ]]   && printf '   %slog:%s %s' "$C_NOTE" "$R" "$log_file"
    printf '   %sCtrl-C to stop%s\n' "$C_NOTE" "$R"
}

print_summary() {
    local total=0 ev n elapsed=$SECONDS
    for n in "${EV_COUNT[@]}"; do (( total += n )); done
    printf '\n%sStopped after %dm %02ds, %d event(s)%s\n' "$B" $((elapsed / 60)) $((elapsed % 60)) "$total" "$R"
    (( total )) || return 0
    local -A shown=()
    for ev in "${EVENT_ORDER[@]}" "${!EV_COUNT[@]}"; do
        [[ -n ${EV_COUNT[$ev]:-} && -z ${shown[$ev]:-} ]] || continue
        shown[$ev]=1
        printf '  %s%-13s%s %8d\n' "${EV_COLOR[$ev]:-}" "$ev" "$R" "${EV_COUNT[$ev]}"
    done
}

cleanup() {
    trap - EXIT INT TERM
    [[ -n ${iw_pid:-} ]] && kill "$iw_pid" 2>/dev/null
    [[ $use_color == true ]] && printf '%s' "$R"
    print_summary
}

monitor_directory() {
    local -a iw_args=(-m -r --timefmt '%m-%d-%Y %I:%M:%S %p'
                      --format '%T%0%w%0%e%0%f%0' --no-newline)
    [[ $events != all ]] && iw_args+=(-e "$events")
    [[ -n $exclude_re ]] && iw_args+=(--exclude "$exclude_re")
    [[ -n $include_re ]] && iw_args+=(--include "$include_re")

    declare -gA EV_COUNT=()
    print_header

    exec {iw_fd}< <(exec inotifywait "${iw_args[@]}" -- "$monitor_dir" 2> >(relay_stderr))
    iw_pid=$!
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    local cols
    cols=$(tput cols 2>/dev/null) || cols=80
    trap 'cols=$(tput cols 2>/dev/null) || cols=80' WINCH


    local root_prefix="$monitor_dir/"
    [[ $monitor_dir == / ]] && root_prefix=/

    local ts dir ev name kind shown_dir time name_color line plain key last_key="" last_plain=""
    local repeat=1

    while IFS= read -r -d '' -u "$iw_fd" ts &&
          IFS= read -r -d '' -u "$iw_fd" dir &&
          IFS= read -r -d '' -u "$iw_fd" ev &&
          IFS= read -r -d '' -u "$iw_fd" name; do

        kind=${ev%%,*}
        [[ $kind == ISDIR ]] && { kind=${ev#*,}; kind=${kind%%,*}; }
        (( EV_COUNT[$kind]++ ))

        [[ -n ${log_fd:-} ]] && printf '[%s] %-13s %s%s\n' "$ts" "$ev" "$dir" "$name" >&"$log_fd"

        if [[ $show_date == true ]]; then time=$ts; else time=${ts#* }; fi
        if [[ $full_paths == true ]]; then shown_dir=$dir; else shown_dir=${dir#"$root_prefix"}; fi

        if [[ -z $name ]]; then
            # Event on a watched directory itself: show it as parent/ + dir/.
            name=${shown_dir%/}
            name=${name##*/}
            shown_dir=${shown_dir%"$name"/}
            name=${name:-.}/
            name_color=$C_DIR
        elif [[ ,$ev, == *,ISDIR,* ]]; then
            name+=/
            name_color=$C_DIR
        else
            case $name in
                *.o|*.a|*.so|*.so.*|*.lo|*.la|*.gch|*.pyc|*.obj|*.dll) name_color=$C_OBJ ;;
                *.tmp|*.temp|*.swp|*.swx|*~|*.part|.#*|*.lock|*.crdownload) name_color=$C_TMP ;;
                *) name_color=$C_FILE ;;
            esac
        fi

        printf -v line '%s%s%s  %s%-13s%s  %s%s%s%s%s%s' \
            "$C_TIME" "$time" "$R" \
            "${EV_COLOR[$kind]:-$B}" "$kind" "$R" \
            "$C_PATH" "$shown_dir" "$R" "$name_color" "$name" "$R"

        key="$ev/$dir/$name"
        if [[ $collapse == true && $key == "$last_key" ]]; then
            (( repeat++ ))
            printf -v plain '%s  %-13s  %s%s  %s%d' "$time" "$kind" "$shown_dir" "$name" "$MARK" "$repeat"
            if (( ${#plain} < cols && ${#last_plain} < cols )); then
                printf '\e[1A\r\e[2K%s  %s%s%d%s\n' "$line" "$C_COUNT" "$MARK" "$repeat" "$R"
                last_plain=$plain
                continue
            fi
        else
            repeat=1
        fi

        printf '%s\n' "$line"
        last_key=$key
        printf -v last_plain '%s  %-13s  %s%s' "$time" "$kind" "$shown_dir" "$name"
    done

    local status=0
    wait "$iw_pid" 2>/dev/null || status=$?
    iw_pid=""
    (( status == 0 )) || printf '%sinotifywait exited with status %d%s\n' "$C_ERR" "$status" "$R" >&2
    return "$status"
}

parse_arguments "$@"
validate
monitor_directory
