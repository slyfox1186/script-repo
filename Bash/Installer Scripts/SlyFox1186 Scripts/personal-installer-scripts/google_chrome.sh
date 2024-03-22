#!/usr/bin/env bash

clear

parent_dir="${PWD}"
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
chrome_url='https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb'

printf "%s\n%s\n\n"                     \
    'Installing Google Chrome Browser'  \
    '======================================='
sleep 2

bash <(curl -A "${user_agent}" -fsSL 'https://7z.optimizethis.net')
if [ ! -f 'google-chrome.deb' ]; then
    wget --show-progress -U "${user_agent}" -cqO 'google-chrome.deb' "${chrome_url}"
fi

google_chrome_fn()
{
    local choice

    printf "%s\n\n%s\n%s\n%s\n\n"                         \
        'Do you want to backup or restore google chrome?' \
        '[1] Backup'                                      \
        '[2] Restore'                                     \
        '[3] Skip'
        read -p 'Your choices are (1 or 3): ' choice
	clear

    case "${choice}" in
        1)
                if [ -f 'chrome-profile.7z' ]; then
                    sudo rm 'chrome-profile.7z'
                fi
                cd "${HOME}"/.config || exit 1
                7z a -t7z -m0=lzma2 -mx9 "${parent_dir}"/chrome-profile.7z ./google-chrome/*
                ;;
        2)

                sudo apt -y install ./'google-chrome.deb'
                cp -f "${parent_dir}"/chrome-profile.7z "${HOME}"/.config
                cd "${HOME}"/.config || exit 1
                7z x -y -o"${PWD}"/google-chrome "${PWD}"/chrome-profile.7z
                sudo rm chrome-profile.7z
                ;;
        3)      return 0;;
        *)
                unset choice
                clear
                google_chrome_fn
                ;;
    esac
}
google_chrome_fn
