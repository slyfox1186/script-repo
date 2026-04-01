#!/usr/bin/env bash

MY_PW="${SSH_PW:?Set SSH_PW environment variable}"

sss() {
    # Helper function for displaying usage instructions.
    _sss_help() {
        echo "Usage: sss [OPTION] | [DESTINATION_PATH]"
        echo ""
        echo "Syncs screenshots to a remote server using rsync over SSH."
        echo ""
        echo "Options:"
        echo "  -g              Set destination to \$HOME/tmp/gemmabot/"
        echo "  -glm            Set destination to \$HOME/tmp/glm-4.7-flash-awq-4bit/"
        echo "  -qt             Set destination to \$HOME/tmp/qwen3-30b-a3b-thinking-2507/"
        echo "  -qi             Set destination to \$HOME/tmp/qwen3-30b-a3b-instruct-2507/"
        echo "  -f              Set destination to \$HOME/tmp/flux-dev/"
        echo "  -k              Set destination to \$HOME/tmp/kortex/"
        echo "  -m              Set destination to \$HOME/tmp/myron_website/"
        echo "  -mg             Set destination to \$HOME/tmp/magnolia-builders/"
        echo "  -c              Set destination to \$HOME/tmp/claude-code-openrouter/"
        echo "  -t              Set destination to the remote home directory (\$HOME/)"
        echo "  -tt             Set destination to \$HOME/tmp/tongyi-deepresearch-30b-A3b/"
        echo "  -a              Set destination to \$HOME/tmp/aisle-scout/"
        echo "  -q27            Set destination to \$HOME/tmp/qwen3.5-27b-awq-4bit/"
        echo "  -d              Set destination to \$HOME/tmp/devstral-small-2-24B-instruct-2512/"
        echo "  -h, --help      Display this help message and exit."
        echo ""
        echo "If no option flag is used, a custom DESTINATION_PATH can be provided."
        echo "If no arguments are provided, this help menu is displayed."
    }

    local destination=""
    local show_help=0

    # Parse command-line arguments.
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -g|-glm|-qt|-qi|-q27|-f|-c|-k|-m|-mg|-t|-tt|-d|-a)
                if [[ -n "$destination" ]]; then
                    echo "Error: Only one destination can be specified." >&2
                    return 1
                fi
                case "$1" in
                    -g) destination="$HOME/tmp/gemmabot/";;
                    -glm) destination="$HOME/tmp/glm-4.7-flash-awq-4bit/";;
                    -qt) destination="$HOME/tmp/qwen3-30b-a3b-thinking-2507";;
                    -qi) destination="$HOME/tmp/qwen3-30b-a3b-instruct-2507/";;
                    -q27) destination="$HOME/tmp/qwen3.5-27b-awq-4bit/";;
                    -f) destination="$HOME/tmp/flux-dev/";;
                    -k) destination="$HOME/tmp/kortex/";;
                    -m) destination="$HOME/tmp/myron_website/";;
                    -mg) destination="$HOME/tmp/magnolia-builders/";;
                    -c) destination="$HOME/tmp/claude-code-openrouter/";;
                    -t) destination="$HOME/tmp/";;
                    -tt) destination="$HOME/tmp/tongyi-deepresearch-30b-A3b/";;
                    -a) destination="$HOME/tmp/aisle-scout/";;
                    -d) destination="$HOME/tmp/devstral-small-2-24B-instruct-2512/";;
                esac
                shift
                ;;
            -h|--help)
                show_help=1
                shift
                ;;
            -*) # Catch any other unknown options.
                echo "Error: Unknown option '$1'" >&2
                _sss_help
                return 1
                ;;
            *) # Handle a positional argument for the destination.
                if [[ -n "$destination" ]]; then
                    echo "Error: Cannot specify a path when a destination flag is already used." >&2
                    return 1
                fi
                destination="$1"
                shift
                ;;
        esac
    done

    # Display help if requested or if no destination was provided.
    if [[ "$show_help" -eq 1 || -z "$destination" ]]; then
        # Clear screen only if called with no arguments.
        if [[ -z "$destination" && "$show_help" -eq 0 ]]; then
            clear
        fi
        _sss_help
        return 0
    fi

    # Execute the rsync command.
    sshpass -p "$MY_PW" rsync -avz -e "ssh -p 28500" "$HOME/Pictures/Screenshots/" "jman@192.168.50.169:$destination"
}

cssh() {
    clear
    if [[ $# -eq 0 ]]; then
        # No arguments - interactive SSH session
        if ! sshpass -p "$MY_PW" ssh -o StrictHostKeyChecking=accept-new jman@192.168.50.169 -p 28500; then
            sshpass -p "$MY_PW" ssh -o StrictHostKeyChecking=accept-new jman@192.168.50.169 -p 28500
        fi
    else
        # Arguments provided - run command then stay in interactive shell
        if ! sshpass -p "$MY_PW" ssh -t -o StrictHostKeyChecking=accept-new jman@192.168.50.169 -p 28500 "bash -ic '${*}; exec bash'"; then
            sshpass -p "$MY_PW" ssh -t -o StrictHostKeyChecking=accept-new jman@192.168.50.169 -p 28500 "bash -ic '${*}; exec bash'"
        fi
    fi
}
