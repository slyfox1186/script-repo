#!/usr/bin/env bash

# --- START SERVICE ---
# Starts and optionally enables one or more systemd services.
# Usage: start_service [-s] [-e] [-h] service1.service [service2.service ...]
start_service() {
    local start=false opt
    local enable=false
    local show_help=false
    local error_occurred=false
    local OPTIND=1

    # --- Argument Parsing ---
    while getopts ":seh" opt; do
        case $opt in
            s) start=true ;;
            e) enable=true ;;
            h) show_help=true ;;
            \?) echo "❌ Error: Invalid option -$OPTARG" >&2
                _start_service_usage
                return 1
                ;;
        esac
    done

    # If -h was passed, show the help menu and exit immediately.
    if [ "$show_help" = true ]; then
        _start_service_usage
        return 0
    fi

    shift $((OPTIND - 1))

    # --- Argument Validation ---
    if [ $# -eq 0 ]; then
        echo "❌ Error: No service names provided." >&2
        _start_service_usage
        return 1
    fi

    # Check if no action flags were provided.
    if [[ "$start" = false && "$enable" = false ]]; then
        echo "🤔 No action flags (-s or -e) provided. Nothing to do." >&2
        _start_service_usage
        return 1
    fi

    local started_count=0
    local enabled_count=0
    local services_processed=0

    # --- Service Processing Loop ---
    for service in "$@"; do
        services_processed=$((services_processed + 1))
        echo "--- Processing '$service' ---"

        # 1. Check if the service unit file exists
        if ! sudo systemctl list-unit-files | grep -q "^$service"; then
            echo "⚠️ Warning: Service '$service' does not exist. Skipping."
            continue
        fi

        # 2. Start the service if -s was passed and it's not already active
        if [ "$start" = true ]; then
            if ! sudo systemctl is-active --quiet "$service"; then
                echo "➡️ Starting service..."
                if sudo systemctl start "$service"; then
                    echo "✅ Successfully started."
                    started_count=$((started_count + 1))
                else
                    echo "❌ Error: Failed to start '$service'." >&2
                    error_occurred=true
                fi
            else
                echo "⚪ Service is already active."
            fi
        fi

        # 3. Enable the service if -e was passed and it's not already enabled
        if [ "$enable" = true ]; then
            if ! sudo systemctl is-enabled --quiet "$service"; then
                echo "➡️ Enabling service..."
                if sudo systemctl enable "$service"; then
                    echo "✅ Successfully enabled."
                    enabled_count=$((enabled_count + 1))
                else
                    echo "❌ Error: Failed to enable '$service'." >&2
                    error_occurred=true
                fi
            else
                echo "⚪ Service is already enabled."
            fi
        fi
    done

    # --- Final Summary ---
    echo "========================================"
    echo "📊 Task Complete. Processed $services_processed service(s)."

    if [ "$start" = true ]; then
        echo "👍 Started $started_count service(s)."
    fi
    if [ "$enable" = true ]; then
        echo "👍 Enabled $enabled_count service(s)."
    fi

    if [ "$error_occurred" = true ]; then
        echo "⚠️ Warning: One or more errors occurred during the operation."
        return 1
    fi
    return 0
}
