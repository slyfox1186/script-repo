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
        read -p "Enter the GCC binary you wish to test (example: gcc-11): " choice
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
        read -p "Enter the Clang binary you wish to test (example: clang-11): " choice
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
    if ! sudo dpkg -l | grep -q cmake-curses-gui; then
        sudo apt -y install cmake-curses-gui
    fi
    echo

    if [[ -z "$1" ]]; then
        read -p "Enter the relative source directory: " dir
    else
        dir=$1
    fi

    cmake "$dir" -B build -G Ninja -Wno-dev
    ccmake "$dir"
}

## SHELLCHECK ##
sc() {
    local file files input_char line space
    local -f box_out_banner

    if [[ -z "$*" ]]; then
        read -p "Input the FILE path to check: " files
        echo
    else
        files=$@
    fi

    for file in ${files[@]}; do
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
    local find_rpath
    clear

    if [[ -z "$1" ]]; then
        read -p "Enter the full path to the binary/program: " find_rpath
    else
        find_rpath="$1"
    fi

    clear
    sudo chrpath -l "$(command -v ${find_rpath})"
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
    ls -1AvhF--color --group-directories-first
}

## PYTHON3 PIP ##
pipu() {
    # Step 1: Freeze current pip packages to pip.txt
    pip freeze > pip.txt

    # Step 2: Check if pip.txt was created successfully
    if [[ -f "pip.txt" ]]; then
        # Step 3: Use regex to remove version numbers and other unwanted text from pip.txt
        sed -i -E 's/(==.+|@.+)//g' pip.txt
        
        # Step 4: Run the upgrade command for all packages listed
        pip install --upgrade $(tr '\n' ' ' < pip.txt)

        echo "Packages have been upgraded successfully!"
    else
        echo "Failed to create pip.txt"
        exit 1
    fi
}

# Python Virtual Environment
venv() {
    local choice arg random_dir
    random_dir=$(mktemp -d)
    wget -cqO "$random_dir/pip-venv-installer.sh" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Misc/Python3/pip-venv-installer.sh"

    case "$#" in
        0)
            printf "\n%s\%s\%s\%s\%s\%s\%s\%s\%s\%s\n\n" \
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
            read -p "Choose a letter: " choice
            case "$choice" in
                h) arg="-h" ;;
                l) arg="-l" ;;
                i) arg="-i" ;;
                c) arg="-c" ;;
                u) arg="-u" ;;
                d) arg="-d" ;;
                a|U|r)
                    read -p "Enter package names (space-separated): " pkgs
                    arg="-$choice $pkgs"
                    ;;
                p) arg="-p" ;;
                *) clear && venv ;;
            esac
            ;;
        *)
            arg="$@"
            ;;
    esac

    bash "$random_dir/pip-venv-installer.sh" $arg
}