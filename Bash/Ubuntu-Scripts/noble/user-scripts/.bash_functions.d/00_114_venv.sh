#!/usr/bin/env bash

# Python Virtual Environment
venv() {
    local choice random_dir
    local -a package_names venv_args
    random_dir=$(mktemp -d)
    if ! wget -cqO "$random_dir/pip-venv-installer.sh" "https://raw.githubusercontent.com/slyfox1186/script-repo/main/Bash/Misc/Python3/pip-venv-installer.sh"; then
        rm -rf -- "$random_dir"
        return 1
    fi

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
            read -r -p "Choose a letter: " choice
            case "$choice" in
                h) venv_args=(-h) ;;
                l) venv_args=(-l) ;;
                i) venv_args=(-i) ;;
                c) venv_args=(-c) ;;
                u) venv_args=(-u) ;;
                d) venv_args=(-d) ;;
                a|U|r)
                    read -r -a package_names -p "Enter package names (space-separated): "
                    venv_args=("-$choice" "${package_names[@]}")
                    ;;
                p) venv_args=(-p) ;;
                *)
                    clear
                    rm -rf -- "$random_dir"
                    return 1
                    ;;
            esac
            ;;
        *)
            venv_args=("$@")
            ;;
    esac

    bash "$random_dir/pip-venv-installer.sh" "${venv_args[@]}"
    local status
    status=$?
    rm -rf -- "$random_dir"
    return "$status"
}
