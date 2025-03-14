#!/usr/bin/env bash
# Docker Related Functions

drp() {
    local choice restart_policy
    clear

    printf "%s\n\n%s\n%s\n%s\n%s\n\n" \
        "Change the Docker restart policy" \
        "[1] Restart Always" \
        "[2] Restart Unless Stopped " \
        "[3] On Failure" \
        "[4] No"
    read -p "Your choices are (1 to 4): " choice
    clear

    case "$choice" in
        1)      restart_policy="always" ;;
        2)      restart_policy="unless-stopped" ;;
        3)      restart_policy="on-failure" ;;
        4)      restart_policy="no" ;;
        *)
                clear
                printf "%s\n\n" "Bad user input. Please try again..."
                return 1
                ;;
    esac

    docker update --restart="${restart_policy}"
}