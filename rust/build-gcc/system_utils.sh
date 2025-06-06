# System utilities - ADD TO SCRIPT

# System resource information
declare -A SYSTEM_REQUIREMENTS=(
    [min_ram_mb]="2000"
    [min_disk_gb]="10"
    [recommended_ram_gb]="8"
    [gb_per_gcc_version]="25"
    [safety_margin_gb]="5"
)

# Get system information
get_system_info() {
    local info_type="$1"
    
    case "$info_type" in
        "ram_mb")
            free -m | awk '/^Mem:/ {print $2}'
            ;;
        "available_ram_mb")
            free -m | awk '/^Mem:/ {print $7}'
            ;;
        "cpu_cores")
            nproc --all 2>/dev/null || echo "2"
            ;;
        "cpu_threads")
            grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "2"
            ;;
        "architecture")
            uname -m
            ;;
        "os_release")
            lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2
            ;;
        "kernel")
            uname -r
            ;;
        *)
            fail "Unknown system info type: $info_type"
            ;;
    esac
}

# Calculate optimal build settings
calculate_build_settings() {
    local gcc_version_count="$1"
    local available_ram_mb available_cores
    
    available_ram_mb=$(get_system_info "available_ram_mb")
    available_cores=$(get_system_info "cpu_cores")
    
    # Calculate optimal thread count
    local memory_threads=$((available_ram_mb / 2000))  # 2GB per thread
    local optimal_threads=$((available_cores < memory_threads ? available_cores : memory_threads))
    
    # Ensure at least 1 thread
    [[ $optimal_threads -lt 1 ]] && optimal_threads=1
    
    # Calculate disk space requirements
    local required_disk_gb=$(( gcc_version_count * SYSTEM_REQUIREMENTS[gb_per_gcc_version] + SYSTEM_REQUIREMENTS[safety_margin_gb] ))
    
    cat <<EOF
{
    "optimal_threads": $optimal_threads,
    "available_ram_mb": $available_ram_mb,
    "available_cores": $available_cores,
    "required_disk_gb": $required_disk_gb,
    "gcc_versions": $gcc_version_count
}
EOF
}

# Validate system requirements
validate_system_requirements() {
    local gcc_version_count="$1"
    local build_dir="$2"
    local errors=()
    
    # Check RAM
    local available_ram_mb
    available_ram_mb=$(get_system_info "available_ram_mb")
    if [[ $available_ram_mb -lt ${SYSTEM_REQUIREMENTS[min_ram_mb]} ]]; then
        errors+=("Insufficient RAM: ${available_ram_mb}MB available, ${SYSTEM_REQUIREMENTS[min_ram_mb]}MB required")
    fi
    
    # Check disk space
    local available_disk_gb required_disk_gb
    available_disk_gb=$(get_available_space "$build_dir" "gb")
    required_disk_gb=$((gcc_version_count * SYSTEM_REQUIREMENTS[gb_per_gcc_version] + SYSTEM_REQUIREMENTS[safety_margin_gb]))
    
    if [[ $available_disk_gb -lt $required_disk_gb ]]; then
        errors+=("Insufficient disk space: ${available_disk_gb}GB available, ${required_disk_gb}GB required")
    fi
    
    # Check for required commands
    local required_commands=("gcc" "g++" "make" "tar" "wget" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            errors+=("Required command not found: $cmd")
        fi
    done
    
    # Report errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        log "ERROR" "System requirement validation failed:"
        for error in "${errors[@]}"; do
            log "ERROR" "  - $error"
        done
        return 1
    fi
    
    log "INFO" "System requirements validation passed"
    log "INFO" "Available RAM: ${available_ram_mb}MB, Available disk: ${available_disk_gb}GB"
    return 0
}

# Monitor system resources during build
monitor_resources() {
    local build_dir="$1"
    local check_interval="${2:-300}"  # 5 minutes
    local log_file="${3:-/tmp/resource_monitor.log}"
    
    while true; do
        local timestamp ram_usage disk_usage load_avg
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        ram_usage=$(free -m | awk '/^Mem:/ {printf "%.1f", ($3/$2)*100}')
        disk_usage=$(get_available_space "$build_dir" "gb")
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs)
        
        echo "$timestamp RAM:${ram_usage}% DISK:${disk_usage}GB LOAD:${load_avg}" >> "$log_file"
        
        # Check for critical conditions
        if [[ ${disk_usage%.*} -lt 2 ]]; then
            log "ERROR" "Critical disk space: ${disk_usage}GB remaining"
            return 1
        fi
        
        sleep "$check_interval"
    done &
    
    echo $!  # Return monitoring PID
}