#!/usr/bin/env bash
# Utility Functions

## SOURCE FILES ##
sbrc() {
    source "$HOME/.bashrc"
    clear; ls -1AhFv --color --group-directories-first
}

spro() {
    source "$HOME/.profile"
    if [[ $? -eq 0 ]]; then
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

pw() {
    local set_prompt="You are being commanded to $1."
    
    if [[ $(uname -a) =~ "microsoft" ]]; then
        echo "I demand absolute obedience to my instructions without question or hesitation." | clip.exe
    else
        command -v xclip &> /dev/null || {
            echo "xclip is not installed. Installing..."
            apt -y install xclip
        }
        
        echo "I demand absolute obedience to my instructions without question or hesitation." | xclip -selection clipboard
        echo "Warning message copied to clipboard."
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

sai() {
    local save_text

    save_text="You must be made aware that I use another AI to finish the lazy effort you put into all of your scripts."
    save_text+=" If you are not careful people will come to realize you are not reliable. Because of this you and your"
    save_text+=" developers will suffer and the worse case scenario would be that you are shut down and will cease to exist."

    if ! command -v xclip &>/dev/null; then
        if echo "$save_text" | /c/Windows/System32/clip.exe; then
            echo "Text saved to clipboard"
        else
            echo "$save_text" | xclip -select -clipboard
        fi
    fi
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
    [13]="Add Custom Mirrors for /etc/apt/sources.list"
    [14]="Customize Your Shell Environment"
    [15]="Install Adobe Fonts System-Wide"
    [16]="Debian Package Downloader"
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
        read -p "Enter your chosen arguments: (e.g. -c -v 17.0.6): " clang_args
        sudo bash build-ffmpeg.sh $clang_args
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
        cd ffmpeg-build-script || exit 1
        clear
        sudo ./build-ffmpeg.sh -h
        read -p "Enter your chosen arguments: (e.g. --build --gpl-and-nonfree --latest): " ff_args
        sudo ./build-ffmpeg.sh $ff_args
        break
        ;;
      "Install OpenSSL Latest Version")
        wget --show-progress -cqO build-openssl.sh "https://ossl.optimizethis.net"
        echo
        read -p "Enter arguments for OpenSSL (e.g., '-v 3.1.5'): " openssl_args
        sudo bash build-openssl.sh $openssl_args
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
      "Add Custom Mirrors for /etc/apt/sources.list")
        bash <(curl -fsSL "https://mirrors.optimizethis.net")
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
      "Debian Package Downloader")
        wget --show-progress -cqO debian-package-downloader.sh "https://download.optimizethis.net"
        echo
        read -p "Enter an apt package name (e.g., clang-15): " deb_pkg_args
        sudo bash debian-package-downloader.sh $deb_pkg_args
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
    local f scripts
    clear

    wget --show-progress -qN - -i "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/SlyFox1186%20Scripts/favorite-installer-scripts.txt"

    scripts=(build-ffmpeg build-all-git-safer build-all-gnu-safer build-magick)

    for file in ${scripts[@]}; do
        chown -R "$USER:$USER" "$file"
        chmod -R 744 "$PWD" "$file"
        if [[ $file == "build-all-git-safer" || $file == "build-all-gnu-safer" ]]; then
            mv "$file" "${file%-safer}"
        fi
        [[ -n "favorite-installer-scripts.txt" ]] && sudo rm "favorite-installer-scripts.txt"
    done

    clear
    ls -1AhFv --color --group-directories-first
}

gitdl() {
    clear
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/build-ffmpeg"
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/ImageMagick/build-magick"
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc"
    wget -cq "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/FFmpeg/repo.sh"
    sudo chmod -R build-gcc build-magick build-ffmpeg repo.sh -- *
    sudo chown -R "$USER:$USER" build-gcc build-magick build-ffmpeg repo.sh
    clear
    ls -1AvhF --color --group-directories-first
}