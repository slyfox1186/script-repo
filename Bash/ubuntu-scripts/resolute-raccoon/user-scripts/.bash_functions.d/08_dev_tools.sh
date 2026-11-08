#!/usr/bin/env bash
# Development Tools Functions

## TEST GCC & CLANG ##

# Usage: _test_c_compiler COMPILER [EXTRA_FLAGS...]
# Compiles and runs a hello-world program in a private temporary directory.
_test_c_compiler() {
    local compiler="$1" status work_dir
    shift
    if [[ -z "$compiler" ]] || ! command -v -- "$compiler" > /dev/null; then
        printf 'Compiler not found: %s\n' "$compiler" >&2
        return 1
    fi
    work_dir=$(mktemp -d) || return
    printf '#include <stdio.h>\nint main(void)\n{\n    printf("Hello World!\\n");\n    return 0;\n}\n' > "$work_dir/hello.c"
    "$compiler" "$@" -v "$work_dir/hello.c" -o "$work_dir/hello" && "$work_dir/hello"
    status=$?
    rm -rf -- "$work_dir"
    return "$status"
}

test_gcc() {
    local choice="${1-}"
    if [[ -z "$choice" ]]; then
        read -r -p "Enter the GCC binary you wish to test (example: gcc-11): " choice || return 1
        echo
    fi
    _test_c_compiler "$choice" -Q
}

test_clang() {
    local choice="${1-}"
    if [[ -z "$choice" ]]; then
        read -r -p "Enter the Clang binary you wish to test (example: clang-11): " choice || return 1
        echo
    fi
    _test_c_compiler "$choice"
}

gcc_native() {
    echo "Checking GCC default target..."
    gcc -dumpmachine

    echo "Checking GCC version..."
    gcc --version

    echo "Resolving -march=native..."
    gcc -march=native -Q --help=target | grep -E '^[[:space:]]+-march='
}

## CMAKE commands
c_cmake() {
    local dir="${1-}"
    if [[ $(dpkg-query -W -f='${Status}' cmake-curses-gui 2>/dev/null) != "install ok installed" ]]; then
        sudo apt -y install cmake-curses-gui || return
        echo
    fi

    if [[ -z "$dir" ]]; then
        read -r -p "Enter the relative source directory: " dir || return 1
    fi

    cmake -S "$dir" -B build -G Ninja -Wno-dev || return
    ccmake -S "$dir" -B build
}

########################
## PKG-CONFIG COMMAND ##
########################

# SHOW THE PATHS PKG-CONFIG COMMAND SEARCHES BY DEFAULT
pkg-config-path() {
    clear
    pkg-config --variable pc_path pkg-config | tr ":" "\n"
}

######################################
## SHOW BINARY RUNPATH IF IT EXISTS ##
######################################

show_rpath() {
    local binary find_rpath="${1-}"
    clear

    if [[ -z "$find_rpath" ]]; then
        read -r -p "Enter the command name or path to the binary: " find_rpath || return 1
    fi

    clear
    if ! binary=$(command -v -- "$find_rpath"); then
        printf 'Command not found: %s\n' "$find_rpath" >&2
        return 1
    fi
    if ! readelf -d -- "$binary" | grep -E '\((RPATH|RUNPATH)\)'; then
        printf 'No RPATH or RUNPATH in %s\n' "$binary"
    fi
}

## SHELLCHECK ##
sc() {
    local file
    local -a files

    if (($# == 0)); then
        read -r -a files -p "Input the file path(s) to check: "
        echo
    else
        files=("$@")
    fi

    for file in "${files[@]}"; do
        box_out_banner "Parsing: $file"
        echo
        shellcheck --color=always -x --severity=warning --source-path="$PATH:$HOME/tmp:/etc:/usr/local/lib64:/usr/local/lib:/usr/local64:/usr/lib:/lib64:/lib:/lib32" "$file"
        echo
    done
}

#################
## PYTHON3 PIP ##
#################

pipu() {
    pipua "$@"
}

pipua() {
    local outdated_json package_names pip_location
    local -a packages

    # pip upgrades in the conda base environment replace conda's own dependencies.
    pip_location=$(type -P pip)
    if [[ "${CONDA_DEFAULT_ENV-}" == base || "$pip_location" == "$HOME/miniconda3/bin/pip" ]]; then
        printf 'pipua: refusing to pip-upgrade the conda base environment; use "conda update --all" there.\n' >&2
        return 1
    fi

    if ! outdated_json=$(pip list --outdated --exclude-editable --format=json); then
        return 1
    fi

    if ! package_names=$("$HOME/miniconda3/bin/python" -c '
import json
import sys

for package in json.load(sys.stdin):
    print(package["name"])
' <<< "$outdated_json"); then
        printf '%s\n' 'pipua: failed to parse the list of outdated packages' >&2
        return 1
    fi

    if [[ -z "$package_names" ]]; then
        printf '%s\n' 'All non-editable packages are up to date.'
        return 0
    fi

    # Resolve all upgrades together, then verify the installed dependency set.
    mapfile -t packages <<< "$package_names"
    pip install --upgrade -- "${packages[@]}" || return
    pip check
}
