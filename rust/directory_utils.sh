# Directory management utilities - ADD TO SCRIPT

# Create directory with proper error handling and logging
create_directory() {
    local dir="$1"
    local description="${2:-directory}"
    local use_sudo="${3:-false}"
    
    if [[ "$dry_run" -eq 1 ]]; then
        log "INFO" "Dry run: would create $description: $dir"
        return 0
    fi
    
    local cmd="mkdir -p"
    [[ "$use_sudo" == "true" ]] && cmd="sudo $cmd"
    
    if $cmd "$dir"; then
        log "DEBUG" "Created $description: $dir"
    else
        fail "Failed to create $description: $dir"
    fi
}

# Create multiple directories at once
create_directories() {
    local -a dirs=("$@")
    local failed_dirs=()
    
    for dir in "${dirs[@]}"; do
        if ! mkdir -p "$dir" 2>/dev/null; then
            failed_dirs+=("$dir")
        fi
    done
    
    if [[ ${#failed_dirs[@]} -gt 0 ]]; then
        fail "Failed to create directories: ${failed_dirs[*]}"
    fi
    
    log "DEBUG" "Created directories: ${dirs[*]}"
}

# Check if directory exists and is writable
check_directory_writable() {
    local dir="$1"
    local description="${2:-directory}"
    
    if [[ ! -d "$dir" ]]; then
        create_directory "$dir" "$description"
    elif [[ ! -w "$dir" ]]; then
        fail "$description $dir exists but is not writable"
    fi
}