#!/usr/bin/env bash

# --- KILL SERVICE ---
# Stops and optionally disables one or more systemd services.
# Usage: kill_service [-d] service1.service [service2.service ...]
kill_service() {
    local disable=false opt
    local error_occurred=false
    local OPTIND=1

    # --- Argument Parsing ---
    while getopts "d" opt; do
        case $opt in
            d) disable=true ;;
            *)
                echo "❌ Error: Invalid option -$OPTARG" >&2
                echo "Usage: kill_service [-d] service1.service [service2.service ...]" >&2
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    if [ $# -eq 0 ]; then
        echo "❌ Error: No service names provided." >&2
        echo "Usage: kill_service [-d] service1.service [service2.service ...]" >&2
        return 1
    fi

    local stopped_count=0
    local disabled_count=0
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

        # 2. Stop the service if it's active
        if sudo systemctl is-active --quiet "$service"; then
            echo "➡️ Stopping service..."
            if sudo systemctl stop "$service"; then
                echo "✅ Successfully stopped."
                stopped_count=$((stopped_count + 1))
            else
                echo "❌ Error: Failed to stop '$service'." >&2
                error_occurred=true
            fi
        else
            echo "⚪ Service is already inactive."
        fi

        # 3. Disable the service if -d flag was passed
        if [ "$disable" = true ]; then
            if sudo systemctl is-enabled --quiet "$service"; then
                echo "➡️ Disabling service..."
                if sudo systemctl disable "$service"; then
                    echo "✅ Successfully disabled."
                    disabled_count=$((disabled_count + 1))
                else
                    echo "❌ Error: Failed to disable '$service'." >&2
                    error_occurred=true
                fi
            else
                echo "⚪ Service is already disabled."
            fi
        fi
    done

    # --- Final Summary ---
    echo "========================================"
    echo "📊 Task Complete. Processed $services_processed service(s)."
    echo "👍 Confirmation: Successfully stopped $stopped_count service(s)."

    if [ "$disable" = true ]; then
        echo "👍 Confirmation: Successfully disabled $disabled_count service(s)."
    fi

    if [ "$error_occurred" = true ]; then
        echo "⚠️ Warning: One or more errors occurred during the operation."
        return 1
    fi
}
