#!/usr/bin/env bash

usage() {
    printf 'Usage: %s [gcc-executable]\n' "${0##*/}"
    printf '%s\n' \
        'Print the architecture selected by GCC for this machine.' \
        'Defaults to the GCC environment variable, or gcc on PATH.' \
        'The compiler must be a single executable name or path, without flags.' \
        'Native detection requires support from the selected compiler and host.'
}

main() {
    local compiler=${GCC:-gcc}
    local target_options option value extra march=''

    if (( $# == 1 )) && [[ $1 == --help || $1 == -h ]]; then
        usage
        return 0
    fi
    if (( $# > 1 )) || { (( $# == 1 )) && [[ -z $1 || $1 == -* ]]; }; then
        usage >&2
        return 2
    fi
    if (( $# == 1 )); then
        compiler=$1
    fi
    if ! command -v -- "$compiler" >/dev/null 2>&1; then
        printf 'Error: GCC executable not found: %s\n' "$compiler" >&2
        return 1
    fi

    # The supported-name list describes the compiler, not the host CPU.
    if ! target_options=$(LC_ALL=C "$compiler" -march=native -Q --help=target </dev/null); then
        printf 'Error: %s could not detect the native architecture.\n' "$compiler" >&2
        return 1
    fi

    while read -r option value extra; do
        [[ $option == -march= ]] || continue
        if [[ -n $march || -n $extra || ! $value =~ ^[[:alnum:]][[:alnum:]_.+-]*$ ]]; then
            printf 'Error: %s returned an invalid or ambiguous -march value.\n' "$compiler" >&2
            return 1
        fi
        march=$value
    done <<< "$target_options"

    if [[ -z $march ]]; then
        printf 'Error: %s did not report a native -march value.\n' "$compiler" >&2
        return 1
    fi
    printf '%s\n' "$march"
}

main "$@"
