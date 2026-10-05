#!/usr/bin/env bash
# Utility Functions

## SOURCE FILES ##
sbrc() {
    # Sourcing ~/.bashrc can cd to $HOME, so put the cwd back afterwards.
    local _pwd="$PWD"
    source "$HOME/.bashrc"
    [[ "$PWD" != "$_pwd" && -d "$_pwd" ]] && { cd "$_pwd" || return; }
    clear; ls -1AhFv --color --group-directories-first
}

spro() {
    if source "$HOME/.profile"; then
        echo "The command was a success!"
    else
        echo "The command failed!"
    fi
    clear; ls -1AhFv --color --group-directories-first
}

## Reddit Downvote Calculator
rdvc() {
    declare -A args
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -u|--upvotes) args["total_upvotes"]="$2"; shift 2 ;;
            -p|--percentage) args["upvote_percentage"]="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: rdvc [OPTIONS]"
                echo "Calculate Reddit downvotes based on total upvotes and upvote percentage."
                echo
                echo "Options:"
                echo "  -u, --upvotes       Set the total number of upvotes"
                echo "  -p, --percentage    Set the upvote percentage"
                echo "  -h, --help          Display this help message"
                echo
                return 0
                ;;
            *)
                echo "Error: Unknown option '$1'."
                echo "Use -h or --help for usage information."
                return 1
                ;;
        esac
    done

    if [[ -z ${args["total_upvotes"]} || -z ${args["upvote_percentage"]} ]]; then
        echo "Error: Missing required arguments."
        echo "Use -h or --help for usage information."
        return 1
    fi

    local total_upvotes="${args["total_upvotes"]}"
    local upvote_percentage="${args["upvote_percentage"]}"
    local upvote_percentage_decimal total_votes total_votes_rounded downvotes
    local i lower_limit next_lower_limit next_lower_limit_adjusted

    upvote_percentage_decimal=$(bc <<< "scale=2; $upvote_percentage / 100")
    total_votes=$(bc <<< "scale=2; $total_upvotes / $upvote_percentage_decimal")
    total_votes_rounded=$(bc <<< "($total_votes + 0.5) / 1")
    downvotes=$(bc <<< "$total_votes_rounded - $total_upvotes")

    echo -e "Upvote percentage ranges for the first $total_upvotes downvotes:"
    for ((i=1; i<=total_upvotes; i++)); do
        lower_limit=$(bc <<< "scale=2; $total_upvotes / ($total_upvotes + $i) * 100")
        if [[ $i -lt $total_upvotes ]]; then
            next_lower_limit=$(bc <<< "scale=2; $total_upvotes / ($total_upvotes + $i + 1) * 100")
            next_lower_limit_adjusted=$(bc <<< "scale=2; $next_lower_limit + 0.01")
            echo "Downvotes $i: ${lower_limit}% to $next_lower_limit_adjusted%"
        else
            echo "Downvotes $i: ${lower_limit}% and lower"
        fi
    done

    echo
    echo "Total upvotes: $total_upvotes"
    echo "Upvote percentage: $upvote_percentage%"
    echo "Calculated downvotes: $downvotes"
}

display_help() {
    cat <<EOF
Usage: ${FUNCNAME[0]} [OPTIONS]

Calculate the number of downvotes on a Reddit post.

Options:
  -u, --upvotes <number>         Total number of upvotes on the post
  -p, --percentage <number>      Upvote percentage (without the % sign)
  -h, --help                     Display this help message and exit

Examples:
  ${FUNCNAME[0]} --upvotes 8 --percentage 83
EOF
}

# AI help tools
airules() {
    local text
    text="1. You must always remember that when writing condition statements with brackets you should use double brackets to enclose the text.
2. You must always remember that when using for loops you make the variable descriptive to the task at hand.
3. You must always remember that when inside of a bash function all variables must be declared on a single line at the top of the function without values, then you may write the variables with their values below this line but without the local command in the same line since you already did that on the first line without the values of the variables.
4. All arrays must conform to rule number 3 except in this case, you write the array name with an equal sign and empty parenthesis on the first line with a local command at the start of this line to initialize the array. Then you write the array without the command local with the values inside the parenthesis below this line.
5. You must always remember that you are never to edit any code inside a script unless it is required to fulfill my requests or instructions. Any other code unrelated to my request or instructions is never to be added to, modified, or removed in any way.
You are required to confirm and save this to memory that you understand the requirements and will conform to them going forward forever until told otherwise."

    echo "$text"
    if command -v xclip &>/dev/null; then
        echo "$text" | xclip -selection clipboard
    fi
    if command -v clip.exe &>/dev/null; then
        echo "$text" | clip.exe
    fi
}

aie() {
    local arg1="$1" arg2="$2"
    
    [[ ! -f $HOME/custom-scripts/instructions-existing.sh ]] && {
        echo "Please create or install the bash script: $HOME/custom-scripts/instructions-existing.sh"
        return 1
    }
    
    bash "$HOME/custom-scripts/instructions-existing.sh" "$arg1" "$arg2"
}

# GitHub Script-Repo Script Menu
script_repo() {
  echo "Select a script to install:"
  options=(
    [1]="Linux Build Menu"
    [2]="Build All GNU Scripts"
    [3]="Build All GitHub Scripts"
    [4]="Install GCC Latest Version"
    [5]="Install Clang"
    [6]="Install Latest 7-Zip Version"
    [7]="Install ImageMagick 7"
    [8]="Compile FFmpeg from Source"
    [9]="Install OpenSSL Latest Version"
    [10]="Install Rust Programming Language"
    [11]="Install Essential Build Tools"
    [12]="Install Aria2 with Enhanced Configurations"
    [13]="Update Pacman Mirrorlist"
    [14]="Customize Your Shell Environment"
    [15]="Install Adobe Fonts System-Wide"
    [16]="Arch Package Downloader"
    [17]="Install Tilix"
    [18]="Install Python 3.12.0"
    [19]="Update WSL2 with the Latest Linux Kernel"
    [20]="Enhance GParted with Extra Functionality"
    [21]="Quit"
  )

  select opt in "${options[@]}"; do
    case "$opt" in
      "Linux Build Menu")
        bash <(curl -fsSL "https://build-menu.optimizethis.net")
        break
        ;;
      "Build All GNU Scripts")
        bash <(curl -fsSL "https://build-all-gnu.optimizethis.net")
        break
        ;;
      "Build All GitHub Scripts")
        bash <(curl -fsSL "https://build-all-git.optimizethis.net")
        break
        ;;
      "Install GCC Latest Version")
        wget --show-progress -cqO build-gcc.sh "https://gcc.optimizethis.net"
        sudo bash build-gcc.sh
        break
        ;;
      "Install Clang")
        wget --show-progress -cqO build-clang.sh "https://build-clang.optimizethis.net"
        sudo bash build-clang.sh --help
        echo
        local clang_args_str
        local -a clang_args_arr
        read -rp "Enter your chosen arguments: (e.g. -c -v 17.0.6): " clang_args_str
        # shellcheck disable=SC2206
        read -ra clang_args_arr <<< "$clang_args_str"
        sudo bash build-clang.sh "${clang_args_arr[@]}"
        break
        ;;
      "Install Latest 7-Zip Version")
        bash <(curl -fsSL "https://7z.optimizethis.net")
        break
        ;;
      "Install ImageMagick 7")
        wget --show-progress -cqO build-magick.sh "https://imagick.optimizethis.net"
        sudo bash build-magick.sh
        break
        ;;
      "Compile FFmpeg from Source")
        git clone "https://github.com/slyfox1186/ffmpeg-build-script.git"
        local ff_args_str
        local -a ff_args_arr
        (
            cd ffmpeg-build-script || exit 1
            clear
            sudo ./build-ffmpeg.sh -h
            read -rp "Enter your chosen arguments: (e.g. --build --gpl-and-nonfree --latest): " ff_args_str
            # shellcheck disable=SC2206
            read -ra ff_args_arr <<< "$ff_args_str"
            sudo ./build-ffmpeg.sh "${ff_args_arr[@]}"
        ) || return 1
        break
        ;;
      "Install OpenSSL Latest Version")
        wget --show-progress -cqO build-openssl.sh "https://ossl.optimizethis.net"
        echo
        local openssl_args_str
        local -a openssl_args_arr
        read -rp "Enter arguments for OpenSSL (e.g., '-v 3.1.5'): " openssl_args_str
        # shellcheck disable=SC2206
        read -ra openssl_args_arr <<< "$openssl_args_str"
        sudo bash build-openssl.sh "${openssl_args_arr[@]}"
        break
        ;;
      "Install Rust Programming Language")
        bash <(curl -fsSL "https://rust.optimizethis.net")
        break
        ;;
      "Install Essential Build Tools")
        wget --show-progress -cqO build-tools.sh "https://build-tools.optimizethis.net"
        sudo bash build-tools.sh
        break
        ;;
      "Install Aria2 with Enhanced Configurations")
        sudo wget --show-progress -cqO build-aria2.sh "https://aria2.optimizethis.net"
        sudo bash build-aria2.sh
        break
        ;;
      "Update Pacman Mirrorlist")
        sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
        break
        ;;
      "Customize Your Shell Environment")
        bash <(curl -fsSL "https://user-scripts.optimizethis.net")
        break
        ;;
      "Install Adobe Fonts System-Wide")
        bash <(curl -fsSL "https://adobe-fonts.optimizethis.net")
        break
        ;;
      "Arch Package Downloader")
        local pkg_name
        read -rp "Enter a package name (e.g., clang): " pkg_name
        sudo pacman -S "$pkg_name"
        break
        ;;
      "Install Tilix")
        wget --show-progress -cqO build-tilix.sh "https://tilix.optimizethis.net"
        sudo bash build-tilix.sh
        break
        ;;
      "Install Python 3.12.0")
        wget --show-progress -cqO build-python3.sh "https://python3.optimizethis.net"
        sudo bash build-python3.sh
        break
        ;;
      "Update WSL2 with the Latest Linux Kernel")
        wget --show-progress -cqO build-wsl2-kernel.sh "https://wsl.optimizethis.net"
        sudo bash build-wsl2-kernel.sh
        break
        ;;
      "Enhance GParted with Extra Functionality")
        bash <(curl -fsSL "https://gparted.optimizethis.net")
        break
        ;;
      "Quit")
        break
        ;;
      *) echo "Invalid option $REPLY";;
    esac
  done
}

# Download GitHub scripts
dlfs() {
    local file
    local -a scripts
    clear

    wget --show-progress -qN - -i "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/favorite-installer-scripts.txt"

    scripts=(build-ffmpeg build-all-git-safer build-all-gnu-safer build-magick)

    for file in "${scripts[@]}"; do
        [[ -e "$file" ]] || continue
        chown -R "$USER:$USER" "$file"
        chmod 744 "$file"
        if [[ "$file" == "build-all-git-safer" || "$file" == "build-all-gnu-safer" ]]; then
            mv "$file" "${file%-safer}"
        fi
    done

    [[ -f favorite-installer-scripts.txt ]] && sudo rm favorite-installer-scripts.txt

    clear
    ls -1AhFv --color --group-directories-first
}

gitdl() {
    clear
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/build-ffmpeg"
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/build-magick"
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc"
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/repo.sh"
    sudo chmod 755 build-gcc build-magick build-ffmpeg repo.sh
    sudo chown "$USER:$USER" build-gcc build-magick build-ffmpeg repo.sh
    clear
    ls -1AvhF --color --group-directories-first
}

# NOTE: list_loaded_functions() and list_func() used to live here but were dead
# code. 00_master_functions.sh defines `alias list_loaded_functions='func_list'`
# and `alias list_func='func_help'`, and aliases always win over same-named
# functions at the prompt, so these bodies were unreachable (and one still
# referenced the no-longer-sourced ~/.bash_functions). Use func_help / func_list
# / func_info for function discovery.

kill_pid() {
    if [[ -z "$1" ]]; then
        echo "Usage: kill_pid <PID>"
        return 1
    fi

    local PID_TO_KILL
    PID_TO_KILL="$1"

    clear
    sudo kill -9 "$PID_TO_KILL"
    echo "Sent kill signal to PID $PID_TO_KILL."
}
