#!/usr/bin/env bash

deploy_tensor_dock() {
    clear
    local script_path="$HOME/tmp/Myron_Labs/gemmabot-local-qwen-30b-3b-instruct-1.1/scripts/deploy-tensordock.sh"

    if [[ -z "$1" ]]; then
        echo "You must pass a minimum of 1 argument."
        echo "Usage: dtd <command> [args...]"
        echo "Examples:"
        echo "  dtd status"
        echo "  dtd exec 'nvidia-smi'"
        echo "  dtd logs vllm 100"
        return 1
    fi

    # Execute the deployment script with all provided arguments
    if ! bash "$script_path" "$@"; then
        echo "The command failed!"
        return 1
    fi
}

alias dtd='deploy_tensor_dock'

get_bot_health() {
    local host="${TENSORDOCK_HOST:?Set TENSORDOCK_HOST environment variable}"
    if ! curl -fsSL "http://${host}/health"; then
        echo "The command failed!"
    fi
}

alias gbh='get_bot_health'
