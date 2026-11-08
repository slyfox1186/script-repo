#!/usr/bin/env bash

# Purpose: install or update CMake, Ninja, Meson, and Go
# Target:  Ubuntu 24.04 (works on other Debian/Ubuntu releases as well)
# Script version: 5.5
#
# CMake and Ninja are compiled with the newest gcc installed, or with the
# newest clang when --clang is given.
#
# How each tool is installed, following its own project's documentation:
#   CMake  built from the release tarball with ./bootstrap, after the tarball
#          is checked against Kitware's signed SHA-256 list.
#   Ninja  built from the release tag with upstream's configure.py.
#   Meson  installed with pip into its own virtual environment under the
#          prefix. Meson's documentation advises against a system-wide
#          "sudo pip install", and this keeps it away from the system Python.
#   Go     the official binary release, checked against the SHA-256 that
#          go.dev publishes, placed in PREFIX/go (the documented location is
#          /usr/local/go) and never unpacked over an existing tree.
#
# Every installed path is recorded in a manifest per tool, so an upgrade
# removes the files the new version no longer ships and --uninstall removes
# exactly what was installed.

set -Eeuo pipefail

script_ver="5.5"
all_tools="ninja cmake meson go"
version_regex='^[0-9]+(\.[0-9]+)+$'
# The key ID that https://cmake.org/download/ lists for release signatures
cmake_key_id="2D2CEF1034921684"

# Defaults (all can be changed with command line options)
install_dir="/usr/local" compiler="gcc" action="install"
jobs="$(nproc 2>/dev/null || echo 2)"
tools="" pins="" build_base=""
portable=false keep_build=false force=false dry_run=false assume_yes=false debug=false
use_lto=true use_hardening=true verify=true install_deps=true

# Working state
state_dir="" work_dir="" probe_dir="" user_path="$PATH"
job_pid="" job_out="" job_text="" job_sh="/bin/sh" found_version="" login_search_path=""
made_temp_base=false created_build_base=false needs_root=false
progress_pid="" progress_on=false progress_label=""
CC="" CXX="" cc_base="" cc_suffix="" cc_version="" tool_prefix="" cc_ar="" cc_ranlib=""
cppflags="" cxxflags="" ldflags="" lto_flags=""
orig_args=() manifest=() skipped_flags=()
declare -A pin=() latest=() current=() plan=()

# Real escape characters, so messages can be printed with printf '%s' and
# backslashes inside paths are never interpreted. Color is used only on a
# terminal and is switched off by the NO_COLOR convention (https://no-color.org).
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    CYAN=$'\033[0;36m' GREEN=$'\033[0;32m' RED=$'\033[0;31m' YELLOW=$'\033[0;33m'
    BOLD=$'\033[1m' DIM=$'\033[2m' NC=$'\033[0m'
else
    CYAN='' GREEN='' RED='' YELLOW='' BOLD='' DIM='' NC=''
fi

# Glyphs for the live progress line of run_task. Braille and box drawing need
# a UTF-8 terminal and a font that has them; the Linux console's font has no
# braille. The empty part of the bar is the same heavy line in grey, or a
# light line when there is no color, so full and empty stay distinct.
TRACK="$DIM"
if [[ "$(locale charmap 2>/dev/null)" == UTF-8 && "${TERM:-}" != linux ]]; then
    spin_frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    bar_full="━" bar_half="╸" bar_track="━"
    [[ -n "$NC" ]] || bar_track="─"
else
    spin_frames=("|" "/" "-" "\\")
    bar_full="=" bar_half=">" bar_track="-"
fi
if [[ -n "$NC" ]] && (( $(tput colors 2>/dev/null || echo 0) >= 256 )); then
    TRACK=$'\033[38;5;238m'
fi

# ---------------------------------------------------------------------------
# Output. A run is grouped into steps, with the lines under each one indented.
#   step     a new stage of the run
#   item     one "label   value" line, labels in a fixed-width column
#   heading  the title of a sub-list, and block: its text wrapped to 80 columns
#   log      a plain line, warn: something to look at, fail: stop with an error
# ---------------------------------------------------------------------------
step()    { printf '\n%s==>%s %s%s%s\n' "$CYAN$BOLD" "$NC" "$BOLD" "$*" "$NC"; }
log()     { printf '    %s\n' "$*"; }
item()    { printf '    %s%-13s%s %s\n' "$CYAN" "$1" "$NC" "$2"; }
heading() { printf '    %s%s%s\n' "$CYAN" "$1" "$NC"; }
block()   { fold -s -w 68 <<<"$1" | sed 's/[[:space:]]*$//; s/^/        /'; }
warn()    { printf '    %s[WARN]%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
fail()    { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

trap 'fail "Command failed on line $LINENO: $BASH_COMMAND"' ERR

# run_task [--bar ID] LABEL LOGFILE COMMAND... runs a long command with its
# output sent to LOGFILE, and reports the result and how long it took on one
# line. On a terminal that line is live while the command runs: a spinner and
# the elapsed time, and with --bar a progress bar for the step ID (cmake or
# ninja). The command stays in the foreground, so Ctrl+C reaches it as
# before; only the drawing runs in the background. --debug turns the live
# line off, since the trace output would run through it.
#
# The bar is an estimate of the share of the step's time that has passed.
# The progress lines a build prints count steps, not time: CMake prints
# "[ NN%]" as each rule starts, so the final links of cmake, ctest and
# cpack, where link time optimization does most of its work, run on long
# after the last mark. So each successful step saves its timing: the
# highest new mark seen at each scan, when it was seen, and how long the
# step took (save_timing). The next run of the same step with the same
# compiler, LTO setting and job count moves the bar by that timing. Without
# a saved timing the bar follows the marks. Either way it stops at 99%
# until the command has really finished.
run_task() {
    local bar="" label logfile start="$SECONDS" status=0 offset interrupted=false
    local start_ms=-1 end_ms=-1 points="" profile="" key="" key_jobs="-"
    if [[ "$1" == --bar ]]; then
        bar="$2"
        shift 2
    fi
    label="$1" logfile="$2"
    shift 2
    printf '    %-44s ' "$label"
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && "$debug" != true ]]; then
        : >>"$logfile"
        offset="$(stat -c %s -- "$logfile" 2>/dev/null || true)"
        if [[ "$offset" =~ ^[0-9]+$ ]]; then
            if [[ -n "$bar" ]] && uptime_ms start_ms; then
                profile="$state_dir/$bar.timing-$cc_base"
                [[ "$bar" != cmake ]] || key_jobs="$jobs"
                printf -v key 'cc=%s ccv=%s lto=%s jobs=%s' "$CC" "${cc_version:-unknown}" \
                    "${lto_flags:-off}" "$key_jobs"
                points="$(mktemp "${work_dir:-${TMPDIR:-/tmp}}/$bar.points.XXXXXX" 2>/dev/null || true)"
            fi
            # A Ctrl+C before the PID is recorded is held back until it is,
            # so cleanup always knows what to stop
            trap 'interrupted=true' INT
            progress_monitor "$label" "$logfile" "$offset" "$bar" "$start" \
                "$start_ms" "$profile" "$points" "$key" 2>/dev/null &
            progress_pid=$! progress_on=true progress_label="$label"
            trap - INT
            [[ "$interrupted" != true ]] || kill -INT "$$"
        fi
    fi
    "$@" >>"$logfile" 2>&1 || status=$?
    if (( start_ms >= 0 )); then
        uptime_ms end_ms || end_ms=-1
    fi
    if [[ "$progress_on" == true ]]; then
        stop_progress
        printf '    %-44s ' "$label"
    fi
    if [[ -n "$points" ]]; then
        if (( status == 0 && start_ms >= 0 && end_ms > start_ms )); then
            save_timing "$profile" "$points" "$key" "$(( end_ms - start_ms ))" || true
        fi
        rm -f -- "$points" 2>/dev/null || true
    fi
    if (( status == 0 )); then
        printf '%sdone%s  %s%ss%s\n' "$GREEN" "$NC" "$DIM" "$(( SECONDS - start ))" "$NC"
    else
        printf '%sFAILED%s\n\n' "$RED" "$NC"
        printf '%sLast lines of %s%s\n' "$DIM" "$logfile" "$NC" >&2
        tail -n 40 "$logfile" >&2
        echo >&2
        fail "$label failed. Run again with --keep-build to keep the full log."
    fi
}

# uptime_ms VARIABLE sets VARIABLE to the milliseconds since boot, read from
# /proc/uptime with builtins. It is a monotonic clock, so a change of the
# system time cannot bend the timings, and it needs no process.
uptime_ms() {
    local up="" rest=""
    read -r up rest </proc/uptime 2>/dev/null || true
    [[ "$up" =~ ^([0-9]{1,9})\.([0-9]{2})$ ]] || return 1
    printf -v "$1" '%d' "$(( 10#${BASH_REMATCH[1]} * 1000 + 10#${BASH_REMATCH[2]} * 10 ))"
}

# save_timing PROFILE POINTS KEY TOTAL_MS saves the timing of a successful
# step: the marks the monitor recorded in POINTS, each no later than
# TOTAL_MS, under the compatibility KEY. The monitor ends POINTS with the
# line "complete" only when its final read reached the end of the log with
# no line left unfinished; a capture without it is not saved. The file is written beside the manifests
# under a temporary name and renamed over the old one, so a failure at any
# point leaves the old timing as it was. The timing only steers the
# progress bar, so failures here return 1 without a message. The caller
# runs this with "|| true", where errexit does not apply, so every step is
# checked here.
save_timing() {
    local profile="$1" points="$2" key="$3" total="$4" dir tmp line ms body="" count=0 complete=false
    (( total > 0 && total <= 999999999 )) || return 1
    [[ -f "$points" ]] || return 1
    while IFS= read -r line; do
        if [[ "$line" == complete ]]; then
            complete=true
            break
        fi
        [[ "$line" =~ ^([0-9]{1,3})\ ([0-9]{1,9})$ ]] || return 1
        ms=$(( 10#${BASH_REMATCH[2]} ))
        (( ms <= total )) || ms=$total
        body+="$(( 10#${BASH_REMATCH[1]} )) $ms"$'\n'
        count=$(( count + 1 ))
        (( count <= 101 )) || return 1
    done <"$points"
    [[ "$complete" == true ]] || return 1

    dir="${profile%/*}"
    if [[ ! -e "$dir" ]]; then
        mkdir -p -- "$dir" 2>/dev/null || return 1
    fi
    [[ -d "$dir" && ! -L "$dir" ]] || return 1
    tmp="$(mktemp "$dir/.${profile##*/}.XXXXXX" 2>/dev/null)" || return 1
    if printf 'build-tools-timing 1\n%s\nend %s\n%s' "$key" "$total" "$body" >"$tmp" 2>/dev/null \
        && chmod 0644 -- "$tmp" 2>/dev/null \
        && mv -fT -- "$tmp" "$profile" 2>/dev/null; then
        return 0
    fi
    rm -f -- "$tmp"
    return 1
}

# stop_progress [stopped] ends the live line of run_task, if one is running:
# it stops the drawing, clears the line and shows the cursor again. Cleanup
# calls it with "stopped", which only happens when the script is ended in
# the middle of a step (Ctrl+C, a signal); the line then keeps its label and
# says so, instead of vanishing. It prints nothing when no live line runs.
stop_progress() {
    [[ "$progress_on" == true ]] || return 0
    kill -TERM "$progress_pid" 2>/dev/null || true
    wait "$progress_pid" 2>/dev/null || true
    progress_pid="" progress_on=false
    printf '\r\033[K\033[?25h'
    if [[ "${1:-}" == stopped ]]; then
        printf '    %-44s %sstopped%s\n' "$progress_label" "$YELLOW" "$NC"
    fi
}

# progress_monitor LABEL LOGFILE OFFSET BAR START START_MS PROFILE POINTS KEY
# draws the live part of a run_task line ten times a second until it gets
# SIGTERM. It runs in the background, so nothing in it may stop the script:
# errors are not fatal here, and the log is read with builtins only, so a
# TERM is acted on at the next frame. OFFSET is the size of the log before
# the command started, so output of earlier steps in the same log is
# skipped. BAR is the step ID for a bar, or empty for a spinner only. With a
# bar it reads what the command appends, keeps the highest mark, records
# when each new highest mark appeared (milliseconds after START_MS) and, on
# TERM, writes that record to POINTS. A saved timing in PROFILE is used when
# its KEY matches. Bytes, not characters, are counted (LC_ALL=C); the glyphs
# are printed as bytes. The progress_ helpers work on the variables declared
# here.
progress_monitor() {
    local label="$1" log="$2" skip="$3" bar="$4" start="$5" start_ms="$6"
    local profile="$7" points="$8" key="$9" LC_ALL=C
    local stop=false resize=true cols=80 frame=0 pct=-1 shown=-1 tick_fd="" log_fd="" tty_fd=""
    local chunk="" carry="" skip_line=false at_eof=false drained=false n read_status=0 REPLY=""
    local prof_end=0 j=0 record="" recorded=0
    local -a prof_p=(-1) prof_t=(0) anchor=(0)
    trap - ERR INT
    set +e +x
    trap 'stop=true' TERM
    trap 'resize=true' WINCH

    # The wait between frames is a timed read on a pipe that never has data
    # (this shell holds its write end), so no sleep process runs per frame
    exec {tick_fd}<> <(:)
    # tput reads the window size from its standard input, which for a
    # background job is /dev/null, so it gets a copy of the terminal instead
    exec {tty_fd}>&1
    if [[ -n "$bar" ]] && exec {log_fd}<"$log"; then
        # read stops at a NUL byte and drops it, so a read that ended on
        # one (status 0, fewer bytes than asked) consumed one byte more
        while (( skip > 0 )); do
            n=$(( skip < 65536 ? skip : 65536 ))
            read_status=0
            IFS= read -r -d '' -n "$n" -u "$log_fd" chunk || read_status=$?
            (( read_status <= 1 )) || break
            skip=$(( skip - ${#chunk} ))
            (( read_status != 0 || ${#chunk} == n )) || skip=$(( skip - 1 ))
            (( read_status == 0 )) || break
        done
        chunk=""
        (( start_ms >= 0 )) && [[ -n "$profile" ]] && progress_load
    else
        bar=""
    fi

    printf '\033[?25l'
    while [[ "$stop" != true ]]; do
        if [[ "$resize" == true ]]; then
            resize=false
            cols="$(env -u COLUMNS -u LINES tput cols <&"$tty_fd" 2>/dev/null)"
            [[ "$cols" =~ ^[1-9][0-9]{0,4}$ ]] || cols=80
        fi
        if [[ -n "$bar" ]] && (( frame % 2 == 0 )); then
            progress_scan
        fi
        if [[ "$stop" != true ]]; then
            progress_estimate
            progress_frame
        fi
        read -r -t 0.1 -u "$tick_fd"
        frame=$(( frame + 1 ))
    done

    # Read what the command wrote after the last pass, then hand the record
    # over. It is marked complete only when the log was read to its end.
    if [[ -n "$bar" && -n "$points" ]] && (( start_ms >= 0 )); then
        for (( n = 0; n < 4; n++ )); do
            progress_scan
            if [[ "$at_eof" == true ]]; then
                [[ -n "$carry" || "$skip_line" == true ]] || drained=true
                break
            fi
        done
        [[ "$drained" != true ]] || record+=$'complete\n'
        printf '%s' "$record" >"$points"
    fi
}

# progress_load reads the saved timing in PROFILE into prof_p and prof_t
# (the mark, and the milliseconds after the start at which it appeared) and
# prof_end (the step's total). Point 0 stands for the start, before any
# mark. The file is used only when it is small, has this format and this
# run's key, and its marks rise and its times do not fall; otherwise the
# bar runs without it.
progress_load() {
    local fd="" text="" end p t last_p=-1 last_t=0 i read_status=0
    local -a lines=() ps=(-1) ts=(0)
    [[ -f "$profile" ]] || return 1
    exec {fd}<"$profile" || return 1
    # Only a read that ends at the end of the file is accepted: one that
    # stops at a NUL byte or at the size limit returns status 0
    IFS= read -r -d '' -n 8193 -u "$fd" text || read_status=$?
    exec {fd}<&-
    (( read_status == 1 && ${#text} <= 8192 )) || return 1
    mapfile -t lines <<<"$text"
    (( ${#lines[@]} >= 3 && ${#lines[@]} <= 105 )) || return 1
    [[ "${lines[0]}" == "build-tools-timing 1" && "${lines[1]}" == "$key" ]] || return 1
    [[ "${lines[2]}" =~ ^end\ ([0-9]{1,9})$ ]] || return 1
    end=$(( 10#${BASH_REMATCH[1]} ))
    (( end > 0 )) || return 1
    for (( i = 3; i < ${#lines[@]}; i++ )); do
        [[ -n "${lines[i]}" ]] || continue
        [[ "${lines[i]}" =~ ^([0-9]{1,3})\ ([0-9]{1,9})$ ]] || return 1
        p=$(( 10#${BASH_REMATCH[1]} )) t=$(( 10#${BASH_REMATCH[2]} ))
        (( p <= 100 && p > last_p && t >= last_t && t <= end )) || return 1
        ps+=("$p") ts+=("$t")
        last_p=$p last_t=$t
    done
    prof_p=("${ps[@]}") prof_t=("${ts[@]}") prof_end=$end
}

# progress_scan reads up to 256 KiB that the command appended to the log and
# raises pct to the highest mark found at the start of a line: CMake's
# Makefiles print "[ 42%]", Ninja prints "[12/34]". Each rise is recorded
# with its time, and moves j to the last point of the saved timing that this
# run has now reached, noting when it got there (anchor). A line that is
# still being written is kept for the next pass, unless it is already too
# long to be a progress line, in which case the rest of it is skipped.
# A NUL byte ends a read and is dropped, so reads repeat until 256 KiB were
# taken or the end of the log; at_eof says whether the end was reached.
progress_scan() {
    local line value total now=-1 before="$pct" part="" taken=0 read_status
    local -a lines=()
    chunk="" at_eof=false
    while (( taken < 262144 )); do
        read_status=0
        IFS= read -r -d '' -n "$(( 262144 - taken ))" -u "$log_fd" part || read_status=$?
        chunk+="$part"
        taken=$(( taken + ${#part} + (read_status == 0 && ${#part} < 262144 - taken ? 1 : 0) ))
        (( read_status != 1 )) || at_eof=true
        (( read_status == 0 )) || break
    done
    [[ -n "$chunk" ]] || return 0
    chunk="$carry$chunk" carry=""
    if [[ "$skip_line" == true ]]; then
        if [[ "$chunk" == *$'\n'* ]]; then
            chunk="${chunk#*$'\n'}" skip_line=false
        else
            return 0
        fi
    fi
    if [[ "$chunk" != *$'\n' ]]; then
        carry="${chunk##*$'\n'}"
        if [[ "$chunk" == *$'\n'* ]]; then chunk="${chunk%$'\n'*}"; else chunk=""; fi
        if (( ${#carry} > 256 )); then
            carry="" skip_line=true
        fi
    fi
    [[ -n "$chunk" ]] || return 0
    mapfile -t lines <<<"$chunk"
    for line in "${lines[@]}"; do
        line="${line:0:24}"
        if [[ "$line" =~ ^\[\ *([0-9]{1,3})%\] ]]; then
            value=$(( 10#${BASH_REMATCH[1]} ))
        elif [[ "$line" =~ ^\[([0-9]{1,9})/([0-9]{1,9})\] ]]; then
            total=$(( 10#${BASH_REMATCH[2]} ))
            (( total > 0 )) || continue
            value=$(( 10#${BASH_REMATCH[1]} * 100 / total ))
        else
            continue
        fi
        (( value <= 100 )) || value=100
        (( value <= pct )) || pct=$value
    done
    (( pct > before )) || return 0
    uptime_ms now || return 0
    now=$(( now - start_ms ))
    (( now >= 0 )) || now=0
    if (( recorded < 101 )); then
        record+="$pct $now"$'\n'
        recorded=$(( recorded + 1 ))
    fi
    while (( j + 1 < ${#prof_p[@]} )) && (( prof_p[j + 1] <= pct )); do
        j=$(( j + 1 ))
        anchor[j]=$now
    done
}

# progress_estimate sets shown, in tenths of a percent, or -1 while there is
# nothing to show. With a saved timing: from the last point reached, time
# runs on at the speed of this run so far (its time to that point over the
# saved time, between a third and three times), up to the next point's
# saved time; the share of the saved total is shown. Without one: the
# highest mark. shown never goes down and stays under 100% (990) while the
# command runs.
progress_estimate() {
    local now=-1 tj aj next r=1000 seg est=-1
    if (( prof_end > 0 )) && uptime_ms now; then
        now=$(( now - start_ms ))
        tj=${prof_t[j]} aj=${anchor[j]:-0}
        if (( tj >= 2000 && aj >= 2000 )); then
            r=$(( aj * 1000 / tj ))
            (( r >= 333 )) || r=333
            (( r <= 3000 )) || r=3000
        fi
        if (( j + 1 < ${#prof_t[@]} )); then next=${prof_t[j + 1]}; else next=$prof_end; fi
        seg=$(( (now - aj) * 1000 / r ))
        (( seg >= 0 )) || seg=0
        (( seg <= next - tj )) || seg=$(( next - tj ))
        est=$(( (tj + seg) * 1000 / prof_end ))
    elif (( pct >= 0 )); then
        est=$(( pct * 10 ))
    fi
    (( est <= 990 )) || est=990
    (( est >= shown )) || est=$shown
    shown=$est
}

# glyph_run VARIABLE COUNT GLYPH sets VARIABLE to GLYPH repeated COUNT times,
# without a subshell
glyph_run() {
    local -n glyph_out="$1"
    printf -v glyph_out '%*s' "$2" ''
    glyph_out="${glyph_out// /$3}"
}

# progress_frame draws one frame, laid out to end before the last terminal
# column so the line never wraps:
#   label   SPINNER BAR  64%  72s   when there is progress to show
#   label   SPINNER 23s             otherwise
# The bar gets what the label column and the text leave, up to 40 cells, and
# each cell shows two steps through a half-cell glyph at the edge. When that
# is under 10 cells, the label column gives up its padding first, then the
# bar is left out; when even the text does not fit, the label is shortened
# with "…", and below 30 columns nothing is drawn.
progress_frame() {
    local elapsed="$(( SECONDS - start ))s" spin width labelw=44 text="$label"
    local content tail tail_w=0 cells=0 steps full half filled empty
    spin="${spin_frames[frame % ${#spin_frames[@]}]}"
    width=$(( cols - 1 ))
    (( width >= 30 )) || return 0

    if (( shown >= 0 )); then
        printf -v tail ' %s%3d%%%s  %s%s%s' "$BOLD" "$(( shown / 10 ))" "$NC" "$DIM" "$elapsed" "$NC"
        # The time gets at least 4 columns ("999s"), so the bar does not
        # shrink each time the time gains a digit
        tail_w=$(( 7 + (${#elapsed} > 4 ? ${#elapsed} : 4) ))
        cells=$(( width - 5 - labelw - 2 - tail_w ))
        if (( cells < 10 )); then
            cells=$(( width - 5 - ${#label} - 2 - tail_w ))
            if (( cells >= 10 )); then
                labelw=${#label}
            else
                cells=0
            fi
        fi
        (( cells <= 40 )) || cells=40
    else
        printf -v tail '%s%s%s' "$DIM" "$elapsed" "$NC"
        tail_w=${#elapsed}
    fi

    # Shorten the label when the content does not fit beside it
    if (( 4 + labelw + 1 + 2 + cells + tail_w > width )); then
        labelw=$(( width - 5 - 2 - tail_w ))
        (( labelw >= 8 )) || return 0
        (( ${#label} <= labelw )) || text="${label:0:labelw - 1}…"
    fi

    content="$CYAN$spin$NC "
    if (( cells > 0 )); then
        steps=$(( shown * cells * 2 / 1000 ))
        full=$(( steps / 2 )) half=$(( steps % 2 ))
        glyph_run filled "$full" "$bar_full"
        glyph_run empty "$(( cells - full - half ))" "$bar_track"
        (( half == 0 )) || filled+="$bar_half"
        content+="$GREEN$filled$NC$TRACK$empty$NC"
    fi
    content+="$tail"
    printf '\r    %-*s %s\033[K' "$labelw" "$text" "$content"
}

# ---------------------------------------------------------------------------
# Options. This one table drives both the command line parser and the help
# screen, so an option is described in exactly one place.
#   short | long | VALUE (only if it takes one) | what to set | help lines...
# A line starting with "#" is a section title. A help line starting with "@"
# is shown as the default. A row with no help lines is an alias kept for
# compatibility with earlier versions of this script, and is not shown.
# ---------------------------------------------------------------------------
opt_table="$(cat <<EOF
#WHAT TO INSTALL
-t|--tools|LIST|tools|Comma separated list of tools to work on:|cmake, ninja, meson, go.|@all four
|--pin|LIST|pins|Use a specific version instead of the latest,|for example cmake=4.3.2,go=1.25.1
-i|--install-directory|DIR|install_dir|Install prefix, relative or absolute.|Binaries go in DIR/bin, shared files in|DIR/share, and Go in DIR/go.|@$install_dir
|--check||action=check|Show installed and latest versions and stop.|Exit status is 0 when everything is up to|date and 10 when an update exists.
#BUILD
|--clang||compiler=clang|Build with clang instead of gcc. Either way|the newest version installed in /usr/bin or|/usr/local/bin is used.
-p|--portable||portable=true|Build binaries that run on any CPU of the|same architecture. Without this the build|uses -march=native, which is tuned for this|PC and may not run on others.
|--no-lto||use_lto=false|Turn off link time optimization.
|--no-hardening||use_hardening=false|Turn off the security hardening flags.
-j|--jobs|N|jobs|Parallel build jobs.|@$jobs
-b|--build-directory|DIR|build_base|Where to download and compile.|@a new temporary directory
-k|--keep-build||keep_build=true|Keep the build directory when finished.
#BEHAVIOR
-f|--force||force=true|Reinstall even when the installed version is|already the wanted one.
-y|--yes||assume_yes=true|Do not prompt (passes -y to apt).
|--no-deps||install_deps=false|Do not check for or install APT packages.
|--skip-verify||verify=false|Do not check checksums and signatures of the|downloads. Not recommended.
|--dry-run||dry_run=true|Show what would be done and change nothing.
|--debug||debug=true|Print every shell command as it runs.
-u|--uninstall||action=uninstall|Remove the tools this script installed in|DIR (all of them, or those named by --tools).
-h|--help||action=help|Show this help.
|--latest||force=true
|--skip-deps||install_deps=false
|--no-cleanup||keep_build=true
EOF
)"

# Help output is kept within 80 columns. Option names are green, the values
# they take are cyan, section titles are bold yellow (color first, because the
# color code resets bold), and defaults are dim.
print_usage() {
    local -a f
    local flags pad line desc args
    printf '%s%s%s %sv%s%s\n%s\n' "$CYAN$BOLD" "build-tools.sh" "$NC" "$DIM" "$script_ver" "$NC" \
        "Install or update CMake, Ninja, Meson, and Go."
    printf '\n%sUSAGE%s\n  %s%s%s [%sOPTIONS%s]\n' "$YELLOW$BOLD" "$NC" "$BOLD" "${0##*/}" "$NC" "$CYAN" "$NC"

    while IFS='|' read -ra f; do
        if [[ "${f[0]}" == "#"* ]]; then
            printf '\n%s%s%s\n' "$YELLOW$BOLD" "${f[0]#"#"}" "$NC"
            continue
        fi
        (( ${#f[@]} > 4 )) || continue
        if [[ -n "${f[0]}" ]]; then flags="${f[0]}, ${f[1]}"; else flags="    ${f[1]}"; fi
        pad=$(( 30 - ${#flags} - ${#f[2]} ))
        [[ -n "${f[2]}" ]] && pad=$(( pad - 1 ))
        (( pad < 2 )) && pad=2
        printf '  %s%s%s%s%*s%s\n' "$GREEN" "$flags" "$NC" "${f[2]:+ $CYAN${f[2]}$NC}" "$pad" "" "${f[4]}"
        for line in "${f[@]:5}"; do
            [[ "$line" == "@"* ]] && line="${DIM}[default: ${line#@}]${NC}"
            printf '%32s%s\n' "" "$line"
        done
    done <<<"$opt_table"

    printf '\n%sEXAMPLES%s\n' "$YELLOW$BOLD" "$NC"
    while IFS='|' read -r desc args; do
        printf '  %s# %s%s\n  %s%s%s%s\n\n' "$DIM" "$desc" "$NC" "$BOLD" "${0##*/}" "$NC" "${args:+ $args}"
    done <<'EOF'
Install or update all four tools in /usr/local|
See what is installed and what would change|--check
Only CMake and Ninja, built with clang|-t cmake,ninja --clang
Per-user install, no sudo needed|-i "$HOME/.local"
Hold Go at one version and update the rest|--pin go=1.25.1
Remove Meson again|-u -t meson
EOF
    printf '%sColor is disabled when output is not a terminal or NO_COLOR is set.%s\n' "$DIM" "$NC"
}

parse_args() {
    local arg short long value target rest key tool entry tilde='~'
    local -A takes=() sets=()

    while IFS='|' read -r short long value target rest; do
        [[ -n "$long" ]] || continue
        for key in ${short:+"$short"} "$long"; do
            takes[$key]="$value"
            sets[$key]="$target"
        done
    done <<<"$opt_table"

    while (( $# )); do
        # Accept both "--option value" and "--option=value"
        if [[ "$1" == --*=* ]]; then
            arg="$1"
            shift
            set -- "${arg%%=*}" "${arg#*=}" "$@"
        fi
        case "$1" in
            -h|--help) print_usage; exit 0 ;;
            -j[0-9]*)  jobs="${1#-j}"; shift; continue ;;
            *)         ;;
        esac
        [[ -n "$1" && -n "${sets[$1]+known}" ]] || fail "Invalid option: $1 (use --help to see the options)"
        if [[ -n "${takes[$1]}" ]]; then
            [[ $# -ge 2 && -n "$2" ]] || fail "Option $1 requires a value."
            [[ "$2" != -* ]] || fail "Option $1 requires a value, but got another option: $2"
            declare -g "${sets[$1]}=$2"
            shift 2
        else
            declare -g "${sets[$1]}"
            shift
        fi
    done

    [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail "--jobs must be a positive integer, got: $jobs"

    # Keep the tools in build order whatever order they were named in
    arg=" ${tools//,/ } "
    for tool in $arg; do
        [[ " $all_tools " == *" $tool "* ]] || fail "--tools: unknown tool \"$tool\". Choose from: ${all_tools// /, }"
    done
    if [[ -n "${arg// }" ]]; then
        tools=""
        for tool in $all_tools; do
            [[ "$arg" == *" $tool "* ]] && tools+="${tools:+ }$tool"
        done
    else
        tools="$all_tools"
    fi

    for entry in ${pins//,/ }; do
        tool="${entry%%=*}" value="${entry#*=}"
        value="${value#v}"
        [[ "$entry" == *=* && " $all_tools " == *" $tool "* && "$value" =~ $version_regex ]] \
            || fail "--pin entries must look like cmake=4.3.2, got: $entry"
        pin[$tool]="$value"
    done

    # Resolve the prefix to an absolute path. A quoted or =style "~" is not
    # expanded by the shell, so handle it here.
    [[ "$install_dir" == "$tilde" || "$install_dir" == "$tilde"/* ]] && install_dir="$HOME${install_dir:1}"
    install_dir="$(realpath -m -- "$install_dir")"
    [[ "$install_dir" != "/" ]] || fail "Refusing to use / as the install prefix. Use /usr or /usr/local."
    [[ "$install_dir" != *[[:space:]]* ]] || fail "The install prefix cannot contain whitespace."
    state_dir="$install_dir/share/build-tools"
}

# ---------------------------------------------------------------------------
# Environment, privileges, and packages
# ---------------------------------------------------------------------------

# Build with the system toolchain only. An active conda or similar environment
# puts its own compilers and Python ahead of the system ones and exports search
# paths that would silently link the tools against its libraries. /usr/local is
# left out of PATH for the same reason. The compiler is the exception: one
# built from source usually links itself into /usr/local/bin, so that is
# searched too, and the compiler found is run by its full path.
setup_toolchain() {
    PATH="/usr/sbin:/usr/bin:/sbin:/bin"
    export PATH
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LIBS CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH \
          LIBRARY_PATH LD_LIBRARY_PATH AR RANLIB NM GOROOT CMAKE_GENERATOR CMAKE_PREFIX_PATH \
          NINJA_STATUS

    find_compiler
    cc_base="${CC##*/}"
    [[ "$cc_base" =~ -[0-9.]+$ ]] && cc_suffix="${BASH_REMATCH[0]}"
    # The archive tools that match, for example gcc-ar-15 for gcc-15 and
    # llvm-ar-21 for clang-21
    if [[ "$compiler" == clang ]]; then tool_prefix="llvm-"; else tool_prefix="gcc-"; fi
}

# compiler_version BIN prints the full version that a gcc or clang driver
# reports. GCC's -dumpversion gives only the major version (since GCC 7), so
# GCC is asked for -dumpfullversion. Clang's -dumpversion is the full version.
compiler_version() {
    local flag="-dumpversion" out
    [[ "$compiler" != gcc ]] || flag="-dumpfullversion"
    out="$("$1" "$flag" 2>/dev/null)" || return 1
    [[ "$out" =~ $version_regex ]] || return 1
    printf '%s\n' "$out"
}

# version_newer A B: true when version A is higher than version B
version_newer() {
    [[ "$1" != "$2" && "$(printf '%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ]]
}

# Sets CC and CXX to the newest installed pair of gcc and g++ (clang and
# clang++ with --clang), and cc_version to its version. A pair counts only
# when both drivers sit in the same directory and report the same version.
# On a tie the versioned name (gcc-15 over gcc) and the system directory win.
# With no pair installed, CC and CXX stay the plain names, which the package
# check then installs.
find_compiler() {
    local cxx_name="g++" name_regex="^$compiler(-[0-9]+(\.[0-9]+)*)?$" dir bin cxx ver cxx_ver
    [[ "$compiler" != clang ]] || cxx_name="clang++"
    CC="$compiler" CXX="$cxx_name" cc_version=""
    for dir in /usr/bin /bin /usr/local/bin; do
        for bin in "$dir/$compiler"-* "$dir/$compiler"; do
            [[ "${bin##*/}" =~ $name_regex ]] || continue
            cxx="$dir/$cxx_name${BASH_REMATCH[1]}"
            [[ -x "$bin" && -x "$cxx" ]] || continue
            ver="$(compiler_version "$bin")" || continue
            cxx_ver="$(compiler_version "$cxx")" || continue
            [[ "$cxx_ver" == "$ver" ]] || continue
            if [[ -z "$cc_version" ]] || version_newer "$ver" "$cc_version"; then
                CC="$bin" CXX="$cxx" cc_version="$ver"
            fi
        done
    done
}

# compiler_tool NAME prints the path of the archive tool NAME (ar or ranlib)
# that matches the compiler, looked for beside the compiler first, or nothing
compiler_tool() {
    local name="$tool_prefix$1$cc_suffix"
    if [[ "$CC" == */* && -x "${CC%/*}/$name" ]]; then
        printf '%s\n' "${CC%/*}/$name"
    else
        type -P "$name" || true
    fi
}

# Stop with an explanation and the exact command to run again with sudo.
# The script never calls sudo itself.
require_root() {
    local cmd
    [[ "$EUID" -eq 0 ]] && return 0
    printf -v cmd '%q ' "$0" "${orig_args[@]}"
    printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$1" >&2
    printf '        Run the script again with sudo:\n\n            %ssudo %s%s\n\n' "$BOLD" "${cmd% }" "$NC" >&2
    printf '        Or pick a prefix you own, which needs no sudo: -i "%s/.local"\n' "\$HOME" >&2
    exit 1
}

# check_prefix_access MESSAGE: root is only needed when the prefix is not
# writable by the current user. A dry run notes it and carries on.
check_prefix_access() {
    local probe="$install_dir"
    while [[ ! -e "$probe" ]]; do
        probe="$(dirname "$probe")"
    done
    [[ -w "$probe" ]] && return 0
    [[ "$EUID" -ne 0 ]] || fail "$probe is not writable, even as root."
    needs_root=true
    [[ "$dry_run" == true ]] || require_root "$1"
}

wants()  { [[ " $tools " == *" $1 "* ]]; }
fetch()  { curl -fsSL --connect-timeout 15 --retry 3 --retry-delay 2 "$@"; }
sha256() { sha256sum "$1" | cut -d' ' -f1; }

required_packages() {
    local -a pkgs=(ca-certificates curl git tar gzip python3) missing=() apt_opts=()
    local pkg
    [[ "$install_deps" == true ]] || return 0

    if wants cmake || wants ninja; then
        pkgs+=(build-essential)
        # A compiler in /usr/local did not come from APT
        [[ "$CC" == /usr/local/* ]] || case "$cc_base" in
            clang*) pkgs+=("clang$cc_suffix" "lld$cc_suffix" "llvm$cc_suffix") ;;
            gcc-*)  pkgs+=("$cc_base" "g++$cc_suffix") ;;
            *)      ;;
        esac
    fi
    # CMake bundles its other dependencies but not OpenSSL. gpgv and gnupg
    # check the signature on its checksum list.
    wants cmake && pkgs+=(libssl-dev gpgv gnupg)
    wants meson && pkgs+=(python3-venv)

    command -v dpkg-query >/dev/null || { warn "dpkg not found, skipping the package check."; return 0; }
    for pkg in "${pkgs[@]}"; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed" || missing+=("$pkg")
    done
    [[ "${#missing[@]}" -eq 0 ]] && return 0

    item "APT packages" "missing: ${missing[*]}"
    if [[ "$dry_run" == true ]]; then
        log "Dry run, so they were not installed."
        return 0
    fi
    require_root "Installing the missing APT packages needs root: ${missing[*]}"
    [[ "$assume_yes" == true ]] && apt_opts+=(-y)
    apt-get update
    apt-get install "${apt_opts[@]}" "${missing[@]}"
}

# ---------------------------------------------------------------------------
# Versions
# ---------------------------------------------------------------------------

# GitHub's /releases/latest page redirects to the release the maintainers
# marked as latest, which is never a release candidate. If it cannot be
# reached, fall back to the highest plain version tag.
github_latest() {
    local url tag
    url="$(curl -fsSLI --connect-timeout 15 -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" 2>/dev/null)" || url=""
    tag="${url##*/}"
    tag="${tag#v}"
    if [[ "$url" == */releases/tag/* && "$tag" =~ $version_regex ]]; then
        echo "$tag"
        return 0
    fi
    tag="$(git ls-remote --tags --refs "https://github.com/$1.git" 2>/dev/null | awk -F/ '{ sub(/^v/, "", $NF); print $NF }' \
        | grep -E "$version_regex" | sort -V | tail -n1)" || return 1
    echo "$tag"
}

latest_version() {
    case "$1" in
        cmake) github_latest "Kitware/CMake" ;;
        ninja) github_latest "ninja-build/ninja" ;;
        meson) fetch "https://pypi.org/pypi/meson/json" | python3 -c 'import json, sys; print(json.load(sys.stdin)["info"]["version"])' ;;
        go)    fetch "https://go.dev/dl/?mode=json" | python3 -c 'import json, sys; print(next(r["version"] for r in json.load(sys.stdin) if r["stable"])[2:])' ;;
        *)     return 1 ;;
    esac
}

# The timeout program for commands that may hang. GNU timeout stops the whole
# process group of the command. The uutils timeout that Ubuntu 26.04 installs
# as "timeout" stops only the command itself, so GNU's is preferred when it is
# installed (as gnutimeout there).
timeout_bin() { type -P gnutimeout || type -P timeout; }

# run_bounded SECONDS SEARCH_PATH COMMAND... runs COMMAND with its output in the
# file job_out, puts that output in job_text, and returns COMMAND's status.
#   SEARCH_PATH empty: COMMAND runs as this script, with this script's PATH.
#   Otherwise COMMAND gets SEARCH_PATH as its PATH and, under sudo, runs as the
#   person who called sudo, with their home, so their files never run as root.
# COMMAND gets a session of its own with no terminal (setsid). An interactive
# login shell that can reach the terminal takes it over, which hangs this
# script and sends Ctrl+C nowhere. The session leader first prints its PID,
# which is also the session ID of everything COMMAND starts, so end_job can
# kill the whole tree. COMMAND runs in the background and the script waits for
# it, because Ctrl+C interrupts that wait at once instead of after COMMAND
# ends; background commands ignore Ctrl+C themselves. The timeout stops
# COMMAND after SECONDS and kills it 5 seconds later if it ignores that.
run_bounded() {
    local secs="$1" search_path="$2" status=0 interrupted=false tool_timeout tool_setsid start
    local -a prefix=()
    shift 2
    tool_timeout="$(timeout_bin)" || return 1
    tool_setsid="$(type -P setsid)" || return 1
    if [[ -n "$search_path" ]]; then
        if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" ]]; then
            prefix=(runuser -u "$SUDO_USER" -- env -i "HOME=$(login_field 6)" "USER=$SUDO_USER"
                    "LOGNAME=$SUDO_USER" "PATH=$search_path" TERM=dumb)
        else
            prefix=(env "PATH=$search_path")
        fi
    fi
    # Shell code for the session leader: $$ and $@ are its own
    start="echo \"@@LEADER@@\$\$\"; exec \"\$@\""
    # A Ctrl+C between starting COMMAND and recording its PID is held back
    # until the PID is recorded, so cleanup always knows what to stop
    trap 'interrupted=true' INT
    "${prefix[@]}" "$tool_setsid" -w "$job_sh" -c "$start" sh "$tool_timeout" -k 5 "$secs" "$@" \
        </dev/null >"$job_out" 2>/dev/null &
    job_pid=$!
    trap - INT
    [[ "$interrupted" != true ]] || kill -INT "$$"
    wait "$job_pid" || status=$?
    end_job reaped
    job_text="$(sed '1{/^@@LEADER@@/d}' -- "$job_out")"
    return "$status"
}

# end_job [reaped] kills whatever the last run_bounded job left running: its
# whole session, found by the leader PID at the top of job_out. "reaped" means
# the job already ended and was waited for. Otherwise (cleanup, after Ctrl+C)
# the job may still be starting, so this waits up to 3 seconds for the leader
# PID, and without one tries the job PID and its children as session IDs. A
# number is a session ID only while a session leader or member uses it, so
# this cannot reach processes outside the job. Every step may fail because the
# job is already gone, and cleanup runs this, so none of them can stop the
# script or change its exit status.
end_job() {
    local leader="" pid tries=0
    [[ -n "$job_pid" ]] || return 0
    leader="$(sed -n '1s/^@@LEADER@@//p' -- "$job_out" 2>/dev/null || true)"
    if [[ "${1:-}" != reaped ]]; then
        while [[ -z "$leader" ]] && (( tries < 30 )) && kill -0 "$job_pid" 2>/dev/null; do
            sleep 0.1
            tries=$(( tries + 1 ))
            leader="$(sed -n '1s/^@@LEADER@@//p' -- "$job_out" 2>/dev/null || true)"
        done
    fi
    if [[ "$leader" =~ ^[0-9]+$ ]]; then
        pkill -KILL -s "$leader" 2>/dev/null || true
    elif [[ "${1:-}" != reaped ]]; then
        for pid in "$job_pid" $(pgrep -P "$job_pid" 2>/dev/null || true); do
            pkill -KILL -s "$pid" 2>/dev/null || true
        done
    fi
    if [[ "${1:-}" != reaped ]]; then
        kill -KILL "$job_pid" 2>/dev/null || true
        wait "$job_pid" 2>/dev/null || true
    fi
    job_pid=""
    return 0
}

# run_version BIN TOOL [SEARCH_PATH] sets found_version to the version that BIN
# reports, run as described for run_bounded. Status 0: it ran and printed a
# version. 1: it failed or timed out, even if it printed a version first.
# 2: it ran but printed no version.
run_version() {
    local bin="$1" tool="$2" search_path="${3:-}" status=0
    local -a cmd=("$bin" --version)
    found_version=""
    [[ "$tool" != go ]] || cmd=("$bin" version)
    run_bounded 10 "$search_path" "${cmd[@]}" || status=$?
    (( status == 0 )) || return 1
    [[ "${job_text%%$'\n'*}" =~ ([0-9]+(\.[0-9]+)+) ]] || return 2
    found_version="${BASH_REMATCH[1]}"
}

# Sets found_version to the version of TOOL that this prefix provides, or nothing
installed_version() {
    local bin="$install_dir/bin/$1"
    found_version=""
    [[ -x "$bin" ]] || return 0
    run_version "$bin" "$1" || true
}

# Fill in latest, current, and plan for every selected tool and print the table
make_plan() {
    local tool color
    step "Version plan"
    printf '    %s%-8s %-14s %-14s %s%s\n' "$CYAN" "Tool" "Installed" "Wanted" "Action" "$NC"
    for tool in $tools; do
        installed_version "$tool"
        current[$tool]="$found_version"
        latest[$tool]="${pin[$tool]:-}"
        if [[ -z "${latest[$tool]}" ]]; then
            latest[$tool]="$(latest_version "$tool")" || fail "Could not find the latest version of $tool. Check the network, or use --pin $tool=VERSION."
        fi
        [[ "${latest[$tool]}" =~ $version_regex ]] || fail "Got an unusable version for $tool: ${latest[$tool]}"
        if [[ -z "${current[$tool]}" ]]; then
            plan[$tool]="install" color="$GREEN"
        elif [[ "${current[$tool]}" != "${latest[$tool]}" ]]; then
            plan[$tool]="update" color="$YELLOW"
        elif [[ "$force" == true ]]; then
            plan[$tool]="reinstall" color="$YELLOW"
        else
            plan[$tool]="keep" color="$DIM"
        fi
        printf '    %-8s %-14s %-14s %s%s%s\n' "$tool" "${current[$tool]:-none}" "${latest[$tool]}${pin[$tool]:+ (pin)}" "$color" "${plan[$tool]}" "$NC"
    done
}

# ---------------------------------------------------------------------------
# Compiler and linker flags (used for CMake and Ninja, which are C++)
# ---------------------------------------------------------------------------

# probe FLAGS... returns 0 if a test program compiles and links with them.
# -Werror and --fatal-warnings turn "unknown option, ignored" into a failure,
# which is how clang and the linkers report options they do not support.
probe() {
    "$CXX" -O2 -Werror -Wl,--fatal-warnings "$@" -o "$probe_dir/probe" "$probe_dir/probe.cc" >/dev/null 2>&1
}

# add_flags VARIABLE EXTRA_PROBE_FLAGS GROUP...
# Each GROUP is one flag, or several that only make sense together. A group
# that passes the probe is appended to VARIABLE, the rest are remembered.
add_flags() {
    local -n target="$1"
    local extra="$2" group
    local -a words extra_words=()
    shift 2
    [[ -n "$extra" ]] && read -ra extra_words <<<"$extra"
    for group in "$@"; do
        read -ra words <<<"$group"
        if probe "${extra_words[@]}" "${words[@]}"; then
            target+="${target:+ }$group"
        else
            skipped_flags+=("$group")
        fi
    done
}

# The optimization level is left to each project (both use -O3 for release
# builds). The hardening set follows the OpenSSF Compiler Options Hardening
# Guide for C and C++ (https://best.openssf.org/Compiler-Hardening-Guides/).
# Its warning options are left out because they do not change the binary, and
# -fstrict-flex-arrays=3 is left out because it can turn legacy trailing
# arrays in third party code into runtime aborts.
select_flags() {
    local linker="" hard=""

    probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/build-tools-probe.XXXXXX")"
    printf '#include <cstdlib>\n#include <string>\nint main() { return std::string("x").size() == 1 ? EXIT_SUCCESS : EXIT_FAILURE; }\n' >"$probe_dir/probe.cc"
    probe || fail "The compiler $CXX cannot build a simple C++ program."
    cppflags="" cxxflags="-pipe" ldflags="" lto_flags="" skipped_flags=()

    # Link time optimization lets the compiler optimize across all source
    # files at once. GCC uses its own linker plugin. Clang needs the lld linker.
    if [[ "$use_lto" == true ]]; then
        if [[ "$cc_base" == clang* ]]; then lto_flags="-flto" linker="-fuse-ld=lld"; else lto_flags="-flto=auto"; fi
        cc_ar="$(compiler_tool ar)" cc_ranlib="$(compiler_tool ranlib)"
        if [[ -z "$cc_ar" || -z "$cc_ranlib" ]]; then
            warn "LTO turned off: ${tool_prefix}ar$cc_suffix and ${tool_prefix}ranlib$cc_suffix were not found."
            lto_flags="" linker=""
        elif ! probe $lto_flags $linker; then
            warn "LTO turned off: $CXX could not link a test program with $lto_flags $linker."
            lto_flags="" linker=""
        fi
    fi

    if [[ "$portable" == true ]]; then
        add_flags cxxflags "" "-mtune=generic"
    else
        add_flags cxxflags "" "-march=native"
    fi
    # Each function and data item goes in its own section so the linker can
    # drop the unused ones, and library calls skip the PLT
    add_flags cxxflags "" "-ffunction-sections -fdata-sections" "-fno-plt"
    ldflags="$linker"
    add_flags ldflags "$linker" "-Wl,-O1" "-Wl,--gc-sections" "-Wl,--as-needed" "-Wl,--no-copy-dt-needed-entries"

    if [[ "$use_hardening" == true ]]; then
        # Bounds checks in libc and libstdc++ calls. Undefine first so a
        # distribution default does not cause a redefinition warning.
        cppflags="-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS"
        add_flags hard "$linker" \
            "-fstack-protector-strong" "-fstack-clash-protection" "-fPIE -pie" \
            "-ftrivial-auto-var-init=zero" "-fzero-call-used-regs=used-gpr" \
            "-fno-delete-null-pointer-checks" "-fno-strict-overflow" "-fno-strict-aliasing"
        # -fPIE belongs to the compiler and -pie to the linker
        if [[ " $hard " == *" -fPIE -pie "* ]]; then
            hard="${hard/-fPIE -pie/-fPIE}"
            ldflags+="${ldflags:+ }-pie"
        fi
        # Control flow protection is specific to the CPU architecture
        case "$(uname -m)" in
            x86_64)  add_flags hard "" "-fcf-protection=full" ;;
            aarch64) add_flags hard "" "-mbranch-protection=standard" ;;
            *)       ;;
        esac
        cxxflags+="${hard:+ $hard}"
        add_flags ldflags "$linker" "-Wl,-z,relro" "-Wl,-z,now" "-Wl,-z,noexecstack"
    fi

    rm -rf -- "$probe_dir"
    probe_dir=""

    step "Compiler flags ($CXX)"
    heading "Compile"
    block "${cppflags:+$cppflags }$cxxflags"
    heading "Link"
    block "${ldflags:-(none)}"
    heading "Link time optimization"
    block "${lto_flags:-off}"
    if [[ "${#skipped_flags[@]}" -gt 0 ]]; then
        printf '    %sLeft out, not supported by this toolchain%s\n' "$YELLOW" "$NC"
        block "${skipped_flags[*]}"
    fi
}

# Read the result back out of a finished binary: where its shared libraries
# come from, and which hardening features are really present. Each hardening
# row is "label ; readelf option ; pattern that proves it is present".
binary_report() {
    local bin="$1" outside runpath lib label opt regex out rows
    outside="$(ldd "$bin" 2>/dev/null | awk '$3 ~ /^\// && $3 !~ /^\/(usr\/)?lib(64)?\// { print $3 }' || true)"
    runpath="$(readelf -dW "$bin" 2>/dev/null | grep -oP '(RPATH|RUNPATH).*\[\K[^]]+' || true)"
    if [[ -z "$outside$runpath" ]]; then
        item "Libraries" "${GREEN}all from the system${NC}, no search path baked in"
    fi
    for lib in $outside; do
        warn "Links against a library outside the system directories: $lib"
    done
    if [[ -n "$runpath" ]]; then
        warn "Has a library search path baked in: $runpath"
    fi

    if [[ "$use_hardening" != true ]] || ! command -v readelf >/dev/null; then
        return 0
    fi
    rows='Position independent (PIE);-h;Type:[[:space:]]+DYN
Read-only relocations (RELRO);-l;GNU_RELRO
Immediate binding (BIND_NOW);-d;BIND_NOW|[[:space:]]NOW
Non-executable stack;-l;GNU_STACK.*RW[[:space:]]
Stack protector;--dyn-syms;__stack_chk_fail
Fortified libc calls;--dyn-syms;_chk(@|$)'
    case "$(uname -m)" in
        x86_64)  rows+=$'\nControl flow protection (CET);-n;IBT.*SHSTK|SHSTK.*IBT' ;;
        aarch64) rows+=$'\nBranch protection (BTI, PAC);-n;BTI.*PAC|PAC.*BTI' ;;
        *)       ;;
    esac
    heading "Hardening found in the binary"
    while IFS=';' read -r label opt regex; do
        out="$(readelf "$opt" -W "$bin" 2>/dev/null || true)"
        if grep -qE -- "$regex" <<<"$out"; then
            printf '        %-34s %syes%s\n' "$label" "$GREEN" "$NC"
        else
            printf '        %-34s %sNO%s\n' "$label" "$RED" "$NC"
        fi
    done <<<"$rows"
}

# ---------------------------------------------------------------------------
# Manifests. One file per tool lists every path it installed. A line ending
# in "/" is a whole directory that belongs to this script.
# ---------------------------------------------------------------------------

# Entries are only trusted if they sit under the prefix and contain no ".."
# component. A directory entry must also be one of the two this script owns.
safe_entry() {
    [[ "$1" == "$install_dir/"* && "$1" != *"/../"* && "$1" != *"/.." ]] || return 1
    [[ "$1" != */ || "$1" == "$install_dir/go/" || "$1" == "$install_dir/lib/build-tools/"*/ ]]
}

# remove_entries PATH... deletes manifest entries, then any directories that
# were left empty by it
remove_entries() {
    local entry
    local -a files=() dirs=()
    for entry in "$@"; do
        safe_entry "$entry" || { warn "Ignoring unexpected manifest entry: $entry"; continue; }
        if [[ "$entry" == */ ]]; then
            rm -rf -- "${entry%/}"
        else
            files+=("$entry")
        fi
        dirs+=("$(dirname "${entry%/}")")
    done
    (( ${#files[@]} == 0 )) || printf '%s\0' "${files[@]}" | xargs -0 rm -f --
    (( ${#dirs[@]} == 0 )) || printf '%s\0' "${dirs[@]}" | sort -zu | xargs -0 rmdir -p --ignore-fail-on-non-empty -- 2>/dev/null || true
}

# commit_manifest TOOL records the paths collected in the manifest array and
# removes whatever the previous install of TOOL had that this one does not
commit_manifest() {
    local file="$state_dir/$1.manifest" entry
    local -a old=() stale=()
    local -A keep=()
    [[ -f "$file" ]] && mapfile -t old <"$file"
    for entry in "${manifest[@]}"; do keep[$entry]=1; done
    for entry in "${old[@]}"; do
        [[ -n "${keep[$entry]:-}" ]] || stale+=("$entry")
    done
    if (( ${#stale[@]} > 0 )); then
        remove_entries "${stale[@]}"
        item "Cleaned up" "${#stale[@]} paths from the previous install that this one does not provide"
    fi
    mkdir -p "$state_dir"
    printf '%s\n' "${manifest[@]}" >"$file"
    item "Installed" "${#manifest[@]} paths, listed in $file"
    manifest=()
}

# install_tree ROOT merges a staged copy of the prefix into the real one. tar
# replaces existing files and symlinks instead of writing through them, and
# --no-overwrite-dir leaves the permissions of existing directories alone.
install_tree() {
    local root="$1" path
    mkdir -p "$install_dir"
    tar -C "$root" -cf - . | tar -C "$install_dir" -xf - --no-same-owner --no-overwrite-dir
    while IFS= read -r -d '' path; do
        manifest+=("$install_dir/${path#./}")
    done < <(cd "$root" && find . \( -type f -o -type l \) -print0 | sort -z)
}

# The saved build timings of a tool (see save_timing) go with it. They are
# removed even without a manifest, since a step can save its timing and the
# install still fail later.
uninstall_tools() {
    local tool file entry noun found=false
    local -a entries timings
    check_prefix_access "Removing files from $install_dir needs root."
    step "Uninstall from $install_dir"
    for tool in $tools; do
        file="$state_dir/$tool.manifest"
        timings=()
        for entry in "$state_dir/$tool".timing-*; do
            if [[ -d "$entry" && ! -L "$entry" ]]; then
                warn "Leaving a directory where a saved build timing belongs: $entry"
                continue
            fi
            [[ ! -e "$entry" && ! -L "$entry" ]] || timings+=("$entry")
        done
        if (( ${#timings[@]} > 0 )); then
            noun="saved build timings"
            (( ${#timings[@]} > 1 )) || noun="saved build timing"
            if [[ "$dry_run" == true ]]; then
                item "$tool" "${YELLOW}would remove${NC} ${#timings[@]} $noun (dry run)"
            else
                rm -f -- "${timings[@]}"
                [[ -f "$file" ]] || item "$tool" "${GREEN}removed${NC} ${#timings[@]} $noun"
            fi
            [[ -f "$file" ]] || found=true
        fi
        if [[ ! -f "$file" ]]; then
            (( ${#timings[@]} > 0 )) || item "$tool" "not installed by this script, nothing to remove"
            continue
        fi
        found=true
        mapfile -t entries <"$file"
        if [[ "$dry_run" == true ]]; then
            item "$tool" "${YELLOW}would remove${NC} ${#entries[@]} paths (dry run)"
            continue
        fi
        remove_entries "${entries[@]}" "$file"
        item "$tool" "${GREEN}removed${NC}, ${#entries[@]} paths"
    done
    [[ "$dry_run" == true ]] || rmdir -- "$state_dir" 2>/dev/null || true
    [[ "$found" == true ]] || log "Nothing in $install_dir was installed by this script."
}

# ---------------------------------------------------------------------------
# The four tools. Each install_TOOL VERSION function downloads, verifies,
# builds if needed, installs, and commits its manifest.
# ---------------------------------------------------------------------------

# get_source REPO VERSION DIR [RELEASE_FILE] unpacks a GitHub source tarball
# into DIR. Some proxies block archive downloads, so a shallow clone of the
# tag is the fallback.
get_source() {
    local repo="$1" ver="$2" dir="$3" url="https://github.com/$1/archive/refs/tags/v$2.tar.gz"
    [[ -z "${4:-}" ]] || url="https://github.com/$repo/releases/download/v$ver/$4"
    mkdir -p "$dir"
    if fetch -o "$dir.tar.gz" "$url" 2>/dev/null; then
        tar -xzf "$dir.tar.gz" -C "$dir" --strip-components 1 || fail "Failed to extract $dir.tar.gz"
        item "Source" "$url"
    else
        rm -f -- "$dir.tar.gz"
        git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v$ver" "https://github.com/$repo.git" "$dir" \
            || fail "Could not download $repo $ver."
        item "Source" "git tag v$ver (the archive download was not reachable)"
    fi
}

install_ninja() {
    local ver="$1" src="$work_dir/ninja" stage="$work_dir/ninja-stage" pair
    local -a env_vars=("CXX=$CXX" "CXXFLAGS=${cppflags:+$cppflags }$cxxflags${lto_flags:+ $lto_flags}" "LDFLAGS=${lto_flags:+$lto_flags }$ldflags")
    [[ -z "$lto_flags" ]] || env_vars+=("AR=$cc_ar")

    # Upstream publishes no checksums or signatures for Ninja's source
    get_source "ninja-build/ninja" "$ver" "$src"
    cd "$src"
    run_task --bar ninja "Build ninja" "$work_dir/ninja.log" env -u CFLAGS "${env_vars[@]}" python3 ./configure.py --bootstrap
    [[ "$(./ninja --version)" == "$ver" ]] || fail "The new ninja reports version $(./ninja --version), expected $ver."

    # Run a real one-rule build before anything is installed
    mkdir -p smoke
    printf 'rule touch\n  command = touch %s\nbuild out.txt: touch\n' "\$out" >smoke/build.ninja
    ./ninja -C smoke >/dev/null && [[ -f smoke/out.txt ]] || fail "The new ninja failed a basic test build. Nothing was installed."
    item "Self test" "${GREEN}passed${NC}"
    binary_report "$src/ninja"

    # Upstream's install rule only copies the binary, so place the rest here.
    # Not every release ships every file, so missing ones are skipped.
    install -D -m 0755 -s ninja "$stage/bin/ninja"
    for pair in misc/bash-completion:share/bash-completion/completions/ninja misc/zsh-completion:share/zsh/site-functions/_ninja \
                misc/ninja.vim:share/vim/vimfiles/syntax/ninja.vim doc/manual.asciidoc:share/doc/ninja/manual.asciidoc \
                COPYING:share/doc/ninja/COPYING; do
        [[ ! -f "${pair%%:*}" ]] || install -D -m 0644 "${pair%%:*}" "$stage/${pair#*:}"
    done
    install_tree "$stage"
    commit_manifest ninja
}

# Prints the -isystem flags that make the C compiler read the system headers
# before /usr/local/include. Each directory is used only if it exists and a
# test compile works with it. This is for C only: with C++ it breaks the
# standard library's own header lookup.
c_system_includes() {
    local dir arch src
    local -a inc_flags=()
    src="$(mktemp --suffix=.c)"
    printf '#include <stdlib.h>\n#include <limits.h>\n#include <stdio.h>\nint main(void) { return 0; }\n' >"$src"
    arch="$("$CC" -print-multiarch 2>/dev/null || true)"
    for dir in ${arch:+"/usr/include/$arch"} /usr/include; do
        [[ -d "$dir" ]] || continue
        if "$CC" -Werror "${inc_flags[@]}" -isystem "$dir" -fsyntax-only "$src" >/dev/null 2>&1; then
            inc_flags+=(-isystem "$dir")
        fi
    done
    rm -f -- "$src"
    (( ${#inc_flags[@]} == 0 )) || printf ' %s' "${inc_flags[@]}"
}

# CMake's release page provides cmake-VERSION-SHA-256.txt and a detached
# signature for it. The tarball is always checked against the list. The
# signature on the list is checked when Kitware's key can be fetched from the
# keyserver the download page links to, and a bad signature is always fatal.
verify_cmake() {
    local dir="$1" ver="$2" base="https://github.com/Kitware/CMake/releases/download/v$2"
    local sums="$1/cmake-$2-SHA-256.txt" want key="$1/kitware.asc" out

    fetch -o "$sums" "$base/cmake-$ver-SHA-256.txt" || fail "Could not download the CMake checksum list. Use --skip-verify to build without it."
    want="$(awk -v f="cmake-$ver.tar.gz" '$2 == f { print $1 }' "$sums")"
    [[ -n "$want" && "$(sha256 "$dir/cmake.tar.gz")" == "$want" ]] || fail "SHA-256 mismatch for cmake-$ver.tar.gz. The file was not used."
    item "SHA-256" "${GREEN}matches${NC} Kitware's published list"

    if command -v gpg >/dev/null && command -v gpgv >/dev/null \
        && fetch -o "$sums.asc" "$base/cmake-$ver-SHA-256.txt.asc" 2>/dev/null \
        && fetch -o "$key" "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x$cmake_key_id" 2>/dev/null \
        && gpg --homedir "$dir" --batch --yes --dearmor -o "$dir/kitware.gpg" "$key" 2>/dev/null; then
        if out="$(gpgv --homedir "$dir" --keyring "$dir/kitware.gpg" "$sums.asc" "$sums" 2>&1)"; then
            item "Signature" "${GREEN}good${NC}, signed by $(grep -m1 -oP 'Good signature from "\K[^"]+' <<<"$out" || echo "Kitware's key $cmake_key_id")"
        elif grep -q "BAD signature" <<<"$out"; then
            fail "GPG signature check FAILED for the CMake checksum list. The file was not used."
        else
            item "Signature" "${YELLOW}not checked${NC}, the key from the keyserver did not match the signature"
        fi
    else
        item "Signature" "${YELLOW}not checked${NC}, could not get key $cmake_key_id from keyserver.ubuntu.com"
    fi
}

install_cmake() {
    local ver="$1" src="$work_dir/cmake" stage="$work_dir/cmake-stage" flags="${cppflags:+$cppflags }$cxxflags" cflags ignore
    local -a cmake_args=(-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DCMAKE_USE_OPENSSL=ON)
    # Use CMake's own switch for LTO, and the system OpenSSL when it is there
    [[ -z "$lto_flags" ]] || cmake_args+=(-DCMake_BUILD_LTO=ON)
    [[ ! -f /usr/include/openssl/ssl.h ]] || cmake_args+=(-DOPENSSL_ROOT_DIR=/usr)
    # Keep libraries that were built from source out of the build. CMake's
    # bundled libarchive looks for iconv, and both CMake's search and the
    # compiler look in /usr/local before /usr. A GNU libiconv installed there
    # would be linked in, with its directory baked into the binary, although
    # glibc already provides iconv. Two things are needed to prevent that:
    # CMake must not search those prefixes, and the C compiler must read the
    # system headers first.
    ignore="/usr/local"
    [[ "$install_dir" == /usr || "$install_dir" == /usr/local ]] || ignore+=";$install_dir"
    cmake_args+=("-DCMAKE_IGNORE_PREFIX_PATH=$ignore")
    cflags="$flags$(c_system_includes)"

    get_source "Kitware/CMake" "$ver" "$src" "cmake-$ver.tar.gz"
    if [[ "$verify" != true ]]; then
        item "Verification" "${YELLOW}skipped (--skip-verify)${NC}"
    elif [[ -f "$src.tar.gz" ]]; then
        verify_cmake "$work_dir" "$ver"
    else
        warn "The source came from git, so there is no tarball to check against Kitware's checksum list."
    fi

    cd "$src"
    # ./bootstrap, make, make install is the procedure in CMake's README.
    # Options after "--" are passed to CMake itself.
    run_task "Bootstrap cmake" "$work_dir/cmake.log" env "CC=$CC" "CXX=$CXX" "CFLAGS=$cflags" "CXXFLAGS=$flags" "LDFLAGS=$ldflags" \
        ./bootstrap --prefix="$install_dir" --parallel="$jobs" -- "${cmake_args[@]}"
    run_task --bar cmake "Compile cmake ($jobs jobs)" "$work_dir/cmake.log" make -j"$jobs"
    [[ "$(./bin/cmake --version | head -n1)" == "cmake version $ver" ]] || fail "The new cmake reports \"$(./bin/cmake --version | head -n1)\", expected version $ver."
    binary_report "$src/bin/cmake"
    run_task "Stage the files" "$work_dir/cmake.log" make install/strip DESTDIR="$stage"
    [[ -x "$stage$install_dir/bin/cmake" ]] || fail "Staging did not produce $stage$install_dir/bin/cmake"
    install_tree "$stage$install_dir"
    commit_manifest cmake
}

install_meson() {
    local ver="$1" venv="$install_dir/lib/build-tools/meson"
    # A fresh virtual environment each time, made with the system Python, so
    # nothing is left over from the previous version
    rm -rf -- "$venv"
    mkdir -p "$install_dir/bin" "${venv%/*}"
    run_task "Create the virtual environment" "$work_dir/meson.log" /usr/bin/python3 -m venv "$venv"
    run_task "pip install meson==$ver" "$work_dir/meson.log" \
        "$venv/bin/python" -m pip install --disable-pip-version-check --no-input "meson==$ver"
    [[ "$("$venv/bin/meson" --version)" == "$ver" ]] || fail "The new meson reports version $("$venv/bin/meson" --version), expected $ver."
    ln -sfn "$venv/bin/meson" "$install_dir/bin/meson"
    manifest=("$install_dir/bin/meson" "$venv/")
    commit_manifest meson
}

install_go() {
    local ver="$1" arch file want stage="$work_dir/go-stage"
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv6l)  arch="armv6l" ;;
        *)       fail "Go has no binary release for this architecture: $(uname -m)" ;;
    esac
    file="go$ver.linux-$arch.tar.gz"

    fetch -o "$work_dir/$file" "https://go.dev/dl/$file" || fail "Could not download https://go.dev/dl/$file"
    item "Download" "https://go.dev/dl/$file"
    if [[ "$verify" == true ]]; then
        want="$(fetch "https://go.dev/dl/?mode=json&include=all" | python3 -c 'import json, sys
print(next((f["sha256"] for r in json.load(sys.stdin) for f in r["files"] if f["filename"] == sys.argv[1]), ""))' "$file")" || want=""
        [[ -n "$want" ]] || fail "Could not get the published SHA-256 for $file. Use --skip-verify to install without it."
        [[ "$(sha256 "$work_dir/$file")" == "$want" ]] || fail "SHA-256 mismatch for $file. The file was not used."
        item "SHA-256" "${GREEN}matches${NC} the checksum published on go.dev"
    else
        item "Verification" "${YELLOW}skipped (--skip-verify)${NC}"
    fi

    # Unpack to the side and try the binary before touching the live install.
    # Go's install page says never to unpack over an existing tree.
    mkdir -p "$stage" "$install_dir/bin"
    tar -xzf "$work_dir/$file" -C "$stage" --no-same-owner
    [[ "$("$stage/go/bin/go" version)" == "go version go$ver "* ]] || fail "The downloaded Go does not run or reports the wrong version."
    rm -rf -- "$install_dir/go"
    mv "$stage/go" "$install_dir/go"
    ln -sfn ../go/bin/go "$install_dir/bin/go"
    ln -sfn ../go/bin/gofmt "$install_dir/bin/gofmt"
    manifest=("$install_dir/bin/go" "$install_dir/bin/gofmt" "$install_dir/go/")
    commit_manifest go
}

# ---------------------------------------------------------------------------
# Reports about the rest of the system
# ---------------------------------------------------------------------------

# login_field N prints field N of the passwd entry of the person running the
# script (the one who called sudo, under sudo): 6 is the home, 7 the shell
login_field() { getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f"$1"; }

# Sets login_search_path to the PATH a fresh login shell gives the person who
# called sudo. Their shell runs as them (see run_bounded), starting from the
# system PATH in /etc/environment, and only the marked line is read, so
# whatever their startup files print is ignored. No marked line (the shell
# failed, or the timeout stopped it first) is a failure.
login_path() {
    local shell line search_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    login_search_path=""
    shell="$(login_field 7)"
    [[ -x "$shell" ]] || return 1
    line="$(grep -m1 -E '^[[:space:]]*PATH=' /etc/environment 2>/dev/null || true)"
    line="${line#*PATH=}"
    line="${line//\"/}"
    [[ "$line" != /* ]] || search_path="$line"
    # $PATH is left for the login shell to expand
    line="printf '\n@@PATH@@%s\n' \"\$PATH\""
    run_bounded 15 "$search_path" "$shell" -lic "$line" || true
    line="$(sed -n 's/^@@PATH@@//p' <<<"$job_text" | tail -n1)"
    [[ "$line" == /* ]] || return 1
    login_search_path="$line"
}

# Another copy of a tool earlier in PATH (conda, pip, apt) hides the new one.
# Without sudo this checks the PATH the script was started with. Under sudo
# that PATH is root's, so it checks a fresh login shell of the person who
# called sudo. A copy that is ahead is run to show whether it works.
path_report() {
    local tool first status note where search_path="" shadowed=false
    if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" ]]; then
        where="a fresh login shell for $SUDO_USER"
        if login_path; then
            search_path="$login_search_path"
        fi
    else
        where="your current PATH"
        search_path="$user_path"
    fi
    step "First match in $where"
    if [[ -z "$search_path" ]]; then
        for tool in $tools; do
            printf '    %-8s %sunverified%s\n' "$tool" "$YELLOW" "$NC"
        done
        warn "Could not read the PATH of $SUDO_USER's login shell, so this was not checked."
        warn "Check it in your own terminal with:  type -a $tools"
        return 0
    fi

    for tool in $tools; do
        first="$(PATH="$search_path"; type -P "$tool" || true)"
        if [[ "$first" == "$install_dir/bin/$tool" ]]; then
            printf '    %-8s %s%s%s\n' "$tool" "$GREEN" "$first" "$NC"
            continue
        fi
        shadowed=true note=""
        if [[ -n "$first" ]]; then
            status=0
            run_version "$first" "$tool" "$search_path" || status=$?
            case "$status" in
                0) note=" (version $found_version)" ;;
                2) note=" (no version reported)" ;;
                *) note=" (does not run)" ;;
            esac
        fi
        printf '    %-8s %s%s%s%s\n' "$tool" "$YELLOW" "${first:-not found}" "$note" "$NC"
    done
    if [[ "$shadowed" == true ]]; then
        warn "The lines in yellow are not the copies in $install_dir/bin."
        warn "Remove the copy that is ahead, or put $install_dir/bin first by adding"
        warn "these two lines to the end of ~/.bashrc:"
        warn "    PATH=\"$install_dir/bin:\$PATH\""
        warn "    export PATH"
        warn "Then run this in every open terminal:  hash -r"
    fi
    log "A terminal with another conda environment active can still find a different copy."
}

# Earlier versions of this script installed into /usr/local/programs with
# symlinks, put Meson into the system Python with pip, and wrote a GOROOT
# block into ~/.bashrc. The block is removed here because it points Go at a
# directory that no longer holds the current install. The rest is reported
# and left for the user to remove.
legacy_cleanup() {
    local home bashrc tmp path
    local -a found=()
    home="$(login_field 6)"
    bashrc="${home:-$HOME}/.bashrc"

    if wants go && [[ -f "$bashrc" ]] && grep -q '^# >>> build-tools golang >>>' "$bashrc"; then
        tmp="$(mktemp)"
        sed '/^# >>> build-tools golang >>>/,/^# <<< build-tools golang <<</d' "$bashrc" >"$tmp"
        # Write through the existing file so its owner and permissions stay the same
        cat "$tmp" >"$bashrc"
        rm -f -- "$tmp"
        step "Old GOROOT setting"
        log "Removed the \"build-tools golang\" block from $bashrc."
        log "Go finds its own files and does not need GOROOT. Open a new terminal,"
        log "or run this in the current one:  unset GOROOT"
    fi

    for path in /usr/local/programs/cmake-* /usr/local/programs/ninja-* /usr/local/programs/golang-*; do
        [[ -e "$path" ]] && found+=("$path")
    done
    if (( ${#found[@]} > 0 )); then
        step "Leftovers from the old script"
        warn "These directories are no longer used. To remove them:"
        warn "    sudo rm -rf ${found[*]}"
    fi
    return 0
}

cleanup() {
    stop_progress stopped
    [[ -n "$probe_dir" ]] && rm -rf -- "$probe_dir"
    end_job
    [[ -z "$job_out" ]] || rm -f -- "$job_out"
    [[ "$keep_build" == true || -z "$work_dir" ]] && return 0
    # Leave the directory first, since it may be the one being removed
    cd / 2>/dev/null || true
    if [[ "$made_temp_base" == true ]]; then
        rm -rf -- "$build_base"
    else
        rm -rf -- "$work_dir"
        # A --build-directory that this run created is removed too, but only
        # if nothing else is in it. One that already existed is left alone.
        if [[ "$created_build_base" == true ]]; then
            rmdir -- "$build_base" 2>/dev/null || true
        fi
    fi
    [[ -e "$work_dir" ]] || item "Build files" "removed"
    return 0
}

main() {
    local tool todo=""

    orig_args=("$@")
    parse_args "$@"
    [[ "$debug" != true ]] || set -x
    if [[ "$action" == uninstall ]]; then
        uninstall_tools
        exit 0
    fi

    trap cleanup EXIT
    job_out="$(mktemp "${TMPDIR:-/tmp}/build-tools-job.XXXXXX")"
    setup_toolchain
    step "Prepare"
    item "Prefix" "$install_dir"
    item "Tools" "${tools// /, }"
    if wants cmake || wants ninja; then
        item "Compiler" "$CC and $CXX${cc_version:+, version $cc_version}"
        item "CPU target" "$([[ "$portable" == true ]] && echo "portable, any CPU of this architecture" || echo "native, tuned for this PC")"
    fi
    if [[ "$action" == install ]]; then
        # Fail now, before anything is downloaded or built
        check_prefix_access "Writing to $install_dir needs root."
        [[ "$install_dir" != "/usr" ]] || warn "Installing into /usr overwrites the files of APT packages."
        required_packages
    fi

    make_plan
    for tool in $tools; do
        [[ "${plan[$tool]}" == keep ]] || todo+="${todo:+ }$tool"
    done
    if [[ "$action" == check ]]; then
        [[ -z "$todo" ]] || exit 10
        exit 0
    fi
    if [[ -z "$todo" ]]; then
        log "Everything is up to date. Use --force to reinstall."
        path_report
        exit 0
    fi

    if [[ " $todo " == *" cmake "* || " $todo " == *" ninja "* ]] && command -v "$CXX" >/dev/null; then
        select_flags
    fi
    if [[ "$dry_run" == true ]]; then
        step "Dry run finished"
        [[ "$needs_root" != true ]] || item "Needs sudo" "yes, to write to $install_dir"
        log "Nothing was downloaded, built, or installed."
        exit 0
    fi

    if [[ -z "$build_base" ]]; then
        build_base="$(mktemp -d "${TMPDIR:-/tmp}/build-tools-script.XXXXXX")"
        made_temp_base=true
    else
        build_base="$(realpath -m -- "$build_base")"
        [[ -d "$build_base" ]] || created_build_base=true
        mkdir -p "$build_base"
    fi
    work_dir="$build_base/build-tools-work"
    rm -rf -- "$work_dir"
    mkdir -p "$work_dir"

    for tool in $todo; do
        step "${tool^} ${latest[$tool]}"
        "install_$tool" "${latest[$tool]}"
    done
    path_report
    legacy_cleanup

    step "Done"
    for tool in $todo; do
        item "$tool" "${GREEN}${latest[$tool]} installed${NC}${current[$tool]:+ (replaced ${current[$tool]})}"
    done
    item "Time" "${SECONDS}s"
    item "Uninstall" "${0##*/} --uninstall -i $install_dir"
    if [[ "$keep_build" == true ]]; then
        item "Build files" "kept at $work_dir"
    fi
}

main "$@"
