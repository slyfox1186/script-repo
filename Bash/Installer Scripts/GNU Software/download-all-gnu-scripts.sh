#!/usr/bin/env bash

clear

cwd="$PWD"/gnu-installers

if [ ! -d "$cwd"/completed ]; then
    mkdir -p "$cwd"/completed
fi

exit_fn()
{
    printf "\n%s\n\n%s\n\n" \
        'Make sure to star this repository to show your support!' \
        "$repo"
    exit 0
}

fail_fn()
{
    printf "\n%s\n\n%s\n\n" \
        "$1" \
        "To report a bug create an issue at: $repo/issues"
    exit 1
}

cleanup_fn()
{
    local answer

    printf "\n%s\n%s\n%s\n\n%s\n%s\n\n" \
        '============================================' \
        '  Do you want to clean up the build files?  ' \
        '============================================' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' answer

    case "$answer" in
        1)      sudo rm -fr "$cwd" "$0";;
        2)      echo;;
        *)
                printf "\n%s\n\n" 'Bad user input.'
                read -p 'Press enter to try again.'
                echo
                cleanup_fn
                ;;
    esac
}

install_scripts_fn()
{
    local i
    clear

    for i in *
    do
        if bash "$i"; then
            mv "$i" "$cwd"/completed
            printf "\n%s\n\n" "Script finished: $i"
        else
            fail_fn "Failed to install: $i"
        fi
        sleep 2
    done
}

install_choice_fn()
{
    printf "%s\n\n" \
        'Do you want to install all of the scripts now?' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' answer

    case "$answer" in
        1)      install_scripts_fn;;
        2)      clear;;
        *)
                printf "%s\n\n" 'Bad user input... Resetting script.'
                sleep 3
                unset answer
                clear
                install_choice_fn
    esac
}

dl_fn()
{
    if [ ! -f "$1" ]; then
        wget --show-progress -cq "$2"
    fi
}

dl_fn 'build-coreutils' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-coreutils'
dl_fn 'build-diffutils' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-diffutils'
dl_fn 'build-gawk' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-gawk'
dl_fn 'build-gcc' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-gcc'
dl_fn 'build-gettext-libiconv' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-gettext-libiconv'
dl_fn 'build-gparted' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-gparted'
dl_fn 'build-grep' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-grep'
dl_fn 'build-imath' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-imath'
dl_fn 'build-isl' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-isl'
dl_fn 'build-make' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-make'
dl_fn 'build-nettle' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-nettle'
dl_fn 'build-pkg-config' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-pkg-config'
dl_fn 'build-systemd' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-systemd'
dl_fn 'build-texinfo' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-texinfo'
dl_fn 'build-wget' 'https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Installer%20Scripts/GNU%20Software/build-wget'

clear

# DOWNLOAD ALL SCRIPTS
dl_fn

# ASK THE USER IF THEY WANT TO INSTALL ALL OF THE SCRIPTS
install_choice_fn

# CLEANUP THE FILES
cleanup_fn

# SHOW EXIT MESSAGE
exit_fn
