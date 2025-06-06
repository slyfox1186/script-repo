# Command execution utilities - ADD TO SCRIPT

# Execute command with automatic retry logic
execute_with_retry() {
    local max_attempts="${1:-3}"
    local wait_time="${2:-5}"
    shift 2
    local cmd=("$@")
    
    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        log "DEBUG" "Attempt $attempt/$max_attempts: ${cmd[*]}"
        
        if "${cmd[@]}"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log "WARNING" "Command failed, retrying in ${wait_time}s..."
            sleep "$wait_time"
        fi
    done
    
    fail "Command failed after $max_attempts attempts: ${cmd[*]}"
}

# Execute command with specific user (sudo/regular)
execute_as() {
    local user="$1"
    shift
    local cmd=("$@")
    
    case "$user" in
        "sudo"|"root")
            verbose_logging_cmd sudo "${cmd[@]}"
            ;;
        "user"|"")
            verbose_logging_cmd "${cmd[@]}"
            ;;
        *)
            verbose_logging_cmd sudo -u "$user" "${cmd[@]}"
            ;;
    esac
}

# Execute command with timeout
execute_with_timeout() {
    local timeout_seconds="$1"
    shift
    local cmd=("$@")
    
    if command -v timeout >/dev/null 2>&1; then
        verbose_logging_cmd timeout "$timeout_seconds" "${cmd[@]}"
    else
        # Fallback for systems without timeout
        verbose_logging_cmd "${cmd[@]}"
    fi
}

# Parallel command execution
execute_parallel() {
    local -a commands=("$@")
    local -a pids=()
    local failed_commands=()
    
    # Start all commands in background
    for cmd in "${commands[@]}"; do
        eval "$cmd" &
        pids+=($!)
    done
    
    # Wait for all and collect failures
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            failed_commands+=("${commands[$i]}")
        fi
    done
    
    if [[ ${#failed_commands[@]} -gt 0 ]]; then
        fail "Parallel execution failed for: ${failed_commands[*]}"
    fi
}

# Download with progress and resume
download_file() {
    local url="$1"
    local output_path="$2"
    local max_attempts="${3:-3}"
    
    local wget_options=(
        "--progress=bar:force:noscroll"
        "--timeout=60"
        "--tries=$max_attempts"
        "--continue"
        "--output-document=$output_path"
    )
    
    execute_with_retry "$max_attempts" 5 wget "${wget_options[@]}" "$url"
}