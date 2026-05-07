#!/usr/bin/env bash
# Development Tools Functions

## TEST GCC & CLANG ##
test_gcc() {
    local choice random_dir

    # CREATE A TEMPORARY C FILE TO RUN OUR TESTS AGAINST
    random_dir=$(mktemp -d)
    cat > "$random_dir/hello.c" <<'EOF'
#include <stdio.h>
int main(void)
{
   printf("Hello World!\n");
   return 0;
}
EOF

    if [[ -n "$1" ]]; then
        "$1" -Q -v "$random_dir/hello.c"
    else
        read -rp "Enter the GCC binary you wish to test (example: gcc-11): " choice
        echo
        "$choice" -Q -v "$random_dir/hello.c"
    fi
    sudo rm -fr "$random_dir"
}

test_clang() {
    local choice random_dir

    # CREATE A TEMPORARY C FILE TO RUN OUR TESTS AGAINST
    random_dir=$(mktemp -d)
    cat > "$random_dir/hello.c" <<'EOF'
#include <stdio.h>
int main(void)
{
   printf("Hello World!\n");
   return 0;
}
EOF

    if [[ -n "$1" ]]; then
        "$1" -v "$random_dir/hello.c" -o "$random_dir/hello" && "$random_dir/hello"
    else
        read -rp "Enter the Clang binary you wish to test (example: clang-11): " choice
        echo
        "$choice" -v "$random_dir/hello.c" -o "$random_dir/hello" && "$random_dir/hello"
    fi
    sudo rm -fr "$random_dir"
}

gcc_native() {
    echo "Checking GCC default target..."
    gcc -dumpmachine

    echo "Checking GCC version..."
    gcc --version

    echo "Inspecting GCC verbose output for -march=native..."
    # Create a temporary empty file
    local temp_source
    temp_source=$(mktemp /tmp/dummy_source.XXXXXX.c)
    trap 'rm -f "$temp_source"' EXIT

    # Using echo to create an empty file
    echo "" > "$temp_source"

    # Using GCC with -v to get verbose information, including the default march
    gcc -march=native -v -E "$temp_source" 2>&1 | grep -- '-march='
}

## CMAKE commands
c_cmake() {
    local dir
    if ! pacman -Qi ccmake &>/dev/null; then
        sudo pacman -S --noconfirm cmake
    fi
    echo

    if [[ -z "$1" ]]; then
        read -rp "Enter the relative source directory: " dir
    else
        dir=$1
    fi

    cmake "$dir" -B build -G Ninja -Wno-dev
    ccmake "$dir"
}

## SHELLCHECK ##
sc() {
    local file input
    local -a files

    if [[ "$#" -eq 0 ]]; then
        read -rp "Input the FILE path to check: " input
        # shellcheck disable=SC2206
        read -ra files <<< "$input"
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

## PKG-CONFIG COMMAND ##

# SHOW THE PATHS PKG-CONFIG COMMAND SEARCHES BY DEFAULT
pkg-config-path() {
    clear
    pkg-config --variable pc_path pkg-config | tr ":" "\n"
}

## SHOW BINARY RUNPATH IF IT EXISTS ##
show_rpath() {
    local find_rpath resolved
    clear

    if [[ -z "$1" ]]; then
        read -rp "Enter the full path to the binary/program: " find_rpath
    else
        find_rpath="$1"
    fi

    resolved="$(command -v "$find_rpath")"
    if [[ -z "$resolved" ]]; then
        echo "Could not resolve: $find_rpath" >&2
        return 1
    fi

    clear
    sudo chrpath -l "$resolved"
}

## DOWNLOAD CLANG INSTALLER SCRIPTS ##
dl_clang() {
    clear
    if [[ ! -d "$HOME/tmp" ]]; then
        mkdir -p "$HOME/tmp"
    fi
    wget --show-progress -cqO "$HOME/tmp/build-clang-16" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/build-clang-16"
    wget --show-progress -cqO "$HOME/tmp/build-clang-17" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GitHub%20Projects/build-clang-17"
    sudo chmod rwx "$HOME/tmp/build-clang-16" "$HOME/tmp/build-clang-17"
    sudo chown "$USER":"$USER" "$HOME/tmp/build-clang-16" "$HOME/tmp/build-clang-17"
    clear
    ls -1AvhF --color --group-directories-first
}

## PYTHON3 PIP ##
pipu() {
    local -a packages
    local pkg

    # Step 1: Freeze current pip packages to pip.txt
    pip freeze > pip.txt

    if [[ ! -f "pip.txt" ]]; then
        echo "Failed to create pip.txt"
        return 1
    fi

    # Step 2: Strip version pins / VCS refs
    sed -i -E 's/(==.+|@.+)//g' pip.txt

    # Step 3: Read into an array, dropping blanks
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && packages+=("$pkg")
    done < pip.txt

    if (( ${#packages[@]} == 0 )); then
        echo "No packages to upgrade."
        return 0
    fi

    pip install --upgrade "${packages[@]}"
    echo "Packages have been upgraded successfully!"
}

# Python Virtual Environment
venv() {
    local choice pkgs random_dir
    local -a venv_args extra_pkgs
    random_dir=$(mktemp -d)
    wget -cqO "$random_dir/pip-venv-installer.sh" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Misc/Python3/pip-venv-installer.sh"

    case "$#" in
        0)
            printf "\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n\n" \
                "[h]elp" \
                "[l]ist" \
                "[i]mport" \
                "[c]reate" \
                "[u]pdate" \
                "[d]elete" \
                "[a]dd" \
                "[U]pgrade" \
                "[r]emove" \
                "[p]ath"
            read -rp "Choose a letter: " choice
            case "$choice" in
                h) venv_args=("-h") ;;
                l) venv_args=("-l") ;;
                i) venv_args=("-i") ;;
                c) venv_args=("-c") ;;
                u) venv_args=("-u") ;;
                d) venv_args=("-d") ;;
                a|U|r)
                    read -rp "Enter package names (space-separated): " pkgs
                    # shellcheck disable=SC2206
                    read -ra extra_pkgs <<< "$pkgs"
                    venv_args=("-$choice" "${extra_pkgs[@]}")
                    ;;
                p) venv_args=("-p") ;;
                *) clear && venv && return ;;
            esac
            ;;
        *)
            venv_args=("$@")
            ;;
    esac

    bash "$random_dir/pip-venv-installer.sh" "${venv_args[@]}"
}
