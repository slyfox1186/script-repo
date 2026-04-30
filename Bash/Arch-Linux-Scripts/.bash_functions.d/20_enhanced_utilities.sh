#!/usr/bin/env bash
# Enhanced Arch Linux Utility Functions

## SYSTEM MONITORING & DIAGNOSTICS ##

# Real-time system monitoring dashboard
sys_monitor() {
    local refresh_rate="${1:-2}"
    
    while true; do
        clear
        echo "🖥️  SYSTEM MONITOR - Refresh: ${refresh_rate}s (Ctrl+C to exit)"
        echo "================================================================"
        echo
        
        # System info
        echo "📊 SYSTEM INFO:"
        echo "  Hostname: $(hostname)"
        echo "  Uptime: $(uptime -p)"
        echo "  Load: $(uptime | awk -F'load average:' '{print $2}')"
        echo
        
        # CPU info
        echo "🔧 CPU USAGE:"
        top -bn1 | grep "Cpu(s)" | awk '{printf "  CPU: %s\n", $2}'
        echo
        
        # Memory info
        echo "🧠 MEMORY USAGE:"
        free -h | awk 'NR==2{printf "  Memory: %s/%s (%.1f%%)\n", $3, $2, ($3/$2)*100}'
        free -h | awk 'NR==3{printf "  Swap: %s/%s\n", $3, $2}'
        echo
        
        # Disk usage
        echo "💾 DISK USAGE:"
        df -h / | awk 'NR==2{printf "  Root: %s/%s (%s)\n", $3, $2, $5}'
        echo
        
        # Top processes
        echo "⚡ TOP PROCESSES (CPU):"
        ps aux --sort=-%cpu | head -6 | tail -5 | awk '{printf "  %-12s %5s%% %s\n", $1, $3, $11}'
        echo
        
        # Network connections
        echo "🌐 NETWORK CONNECTIONS:"
        netstat -tun | grep ESTABLISHED | wc -l | awk '{printf "  Active connections: %s\n", $1}'
        
        sleep "$refresh_rate"
    done
}

# Find large files consuming disk space
find_large() {
    local size_threshold="${1:-100M}"
    local search_path="${2:-.}"
    
    echo "🔍 Finding files larger than $size_threshold in $search_path"
    echo "=============================================================="
    echo
    
    find "$search_path" -type f -size +"$size_threshold" -exec ls -lh {} \; 2>/dev/null | \
    awk '{
        size = $5
        path = $0
        gsub(/.*[0-9] /, "", path)
        printf "%-10s %s\n", size, path
    }' | sort -hr
    
    echo
    echo "💡 Tip: Use 'find_large 500M /home' to find files >500MB in /home"
}

# Quick system cleanup
sys_cleanup() {
    echo "🧹 System Cleanup Starting..."
    echo "============================="
    echo
    
    # Clean pacman cache
    echo "📦 Cleaning pacman cache..."
    sudo pacman -Rns $(pacman -Qdtq) 2>/dev/null || true
    sudo pacman -Scc --noconfirm
    
    # Clean systemd journal logs
    echo "📜 Cleaning old journal logs..."
    sudo journalctl --vacuum-time=7d
    
    # Clean temporary files
    echo "🗂️  Cleaning temporary files..."
    sudo find /tmp -type f -atime +7 -delete 2>/dev/null
    
    # Clean thumbnail cache
    echo "🖼️  Cleaning thumbnail cache..."
    rm -rf "$HOME/.cache/thumbnails"/*
    
    # Clean browser caches (if they exist)
    echo "🌐 Cleaning browser caches..."
    [[ -d "$HOME/.cache/google-chrome" ]] && rm -rf "$HOME/.cache/google-chrome/Default/Cache"/*
    [[ -d "$HOME/.cache/mozilla" ]] && rm -rf "$HOME/.cache/mozilla/firefox/*/cache2"/*
    
    echo
    echo "✅ System cleanup completed!"
    echo "💾 Disk space freed:"
    df -h / | awk 'NR==2{print "  Available: " $4}'
}

# Quick backup utility
quick_backup() {
    local source_path="$1"
    local backup_name="${2:-backup_$(date +%Y%m%d_%H%M%S)}"
    local backup_dir="$HOME/backups"
    
    if [[ -z "$source_path" ]]; then
        echo "Usage: quick_backup <source_path> [backup_name]"
        echo "Example: quick_backup /home/user/project my_project_backup"
        return 1
    fi
    
    if [[ ! -e "$source_path" ]]; then
        echo "❌ Source path does not exist: $source_path"
        return 1
    fi
    
    # Create backup directory if it doesn't exist
    [[ ! -d "$backup_dir" ]] && mkdir -p "$backup_dir"
    
    echo "💾 Creating backup: $backup_name"
    echo "================================="
    echo "📁 Source: $source_path"
    echo "📁 Destination: $backup_dir/$backup_name.tar.gz"
    echo
    
    # Create compressed backup
    if tar -czf "$backup_dir/$backup_name.tar.gz" -C "$(dirname "$source_path")" "$(basename "$source_path")"; then
        local backup_size=$(du -h "$backup_dir/$backup_name.tar.gz" | cut -f1)
        echo "✅ Backup created successfully!"
        echo "📊 Size: $backup_size"
        echo "📍 Location: $backup_dir/$backup_name.tar.gz"
    else
        echo "❌ Backup failed!"
        return 1
    fi
}

# List all backups
list_backups() {
    local backup_dir="$HOME/backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        echo "❌ No backup directory found at $backup_dir"
        return 1
    fi
    
    echo "💾 Available Backups"
    echo "==================="
    
    if [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        echo "📂 No backups found"
        return 0
    fi
    
    ls -lht "$backup_dir" | awk 'NR>1 {
        size = $5
        date = $6 " " $7 " " $8
        name = $9
        printf "%-15s %-20s %s\n", size, date, name
    }'
}

## NETWORK UTILITIES ##

# Enhanced network information
net_info() {
    echo "🌐 Network Information"
    echo "====================="
    echo
    
    # IP addresses
    echo "📍 IP ADDRESSES:"
    ip addr show | awk '/inet / && !/127.0.0.1/ {
        iface = $NF
        ip = $2
        printf "  %-10s %s\n", iface ":", ip
    }'
    echo
    
    # Default gateway
    echo "🚪 DEFAULT GATEWAY:"
    ip route | awk '/default/ {printf "  Gateway: %s via %s\n", $3, $5}'
    echo
    
    # DNS servers
    echo "🔍 DNS SERVERS:"
    grep nameserver /etc/resolv.conf | awk '{printf "  DNS: %s\n", $2}'
    echo
    
    # Active connections
    echo "🔗 ACTIVE CONNECTIONS:"
    netstat -tun | grep ESTABLISHED | wc -l | awk '{printf "  TCP connections: %s\n", $1}'
    
    # Listening ports
    echo
    echo "👂 LISTENING PORTS:"
    netstat -tlnp 2>/dev/null | awk 'NR>2 && /LISTEN/ {
        split($4, addr, ":")
        port = addr[length(addr)]
        printf "  Port %s: %s\n", port, $1
    }' | sort -n
}

# Quick port scanner
port_scan() {
    local target="${1:-localhost}"
    local port_range="${2:-1-1000}"
    
    echo "🔍 Scanning ports on $target"
    echo "Port range: $port_range"
    echo "=========================="
    echo
    
    IFS='-' read -r start_port end_port <<< "$port_range"
    
    for port in $(seq "$start_port" "$end_port"); do
        if timeout 1 bash -c "echo >/dev/tcp/$target/$port" 2>/dev/null; then
            echo "✅ Port $port: OPEN"
        fi
    done 2>/dev/null
    
    echo "🏁 Scan completed"
}

# Network speed test (using curl)
speed_test() {
    echo "⚡ Network Speed Test"
    echo "===================="
    echo
    
    # Test download speed
    echo "📥 Testing download speed..."
    local download_url="http://speedtest.tele2.net/10MB.zip"
    curl -o /dev/null -s -w "Download: %{speed_download} bytes/sec (%.2f KB/s)\n" "$download_url" | \
    awk '{printf "Download: %.2f KB/s (%.2f Mbps)\n", $2/1024, ($2*8)/(1024*1024)}'
    
    echo
    echo "🌐 Testing connectivity..."
    
    # Test connectivity to common sites
    local sites=("google.com" "github.com" "stackoverflow.com")
    for site in "${sites[@]}"; do
        local response_time=$(ping -c 1 "$site" 2>/dev/null | awk -F'time=' 'NR==2{print $2}' | awk '{print $1}')
        if [[ -n "$response_time" ]]; then
            echo "  $site: ${response_time}ms"
        else
            echo "  $site: unreachable"
        fi
    done
}

## GIT UTILITIES ##

# Git status for all repositories in current directory
git_status_all() {
    echo "📋 Git Status for All Repositories"
    echo "=================================="
    echo
    
    local found_repos=0
    
    for dir in */; do
        if [[ -d "$dir/.git" ]]; then
            ((found_repos++))
            echo "📁 Repository: $dir"
            echo "$(printf '─%.0s' {1..40})"
            
            cd "$dir" || continue
            
            # Check if repo is clean
            if git diff-index --quiet HEAD --; then
                echo "✅ Clean working directory"
            else
                echo "⚠️  Uncommitted changes:"
                git status --porcelain | head -5
            fi
            
            # Check for unpushed commits
            local unpushed=$(git log --oneline @{u}.. 2>/dev/null | wc -l)
            if [[ $unpushed -gt 0 ]]; then
                echo "📤 Unpushed commits: $unpushed"
            fi
            
            cd ..
            echo
        fi
    done
    
    if [[ $found_repos -eq 0 ]]; then
        echo "❌ No Git repositories found in current directory"
    else
        echo "✅ Checked $found_repos repositories"
    fi
}

# Quick git commit with automatic message
git_quick_commit() {
    local message="$1"
    
    if [[ -z "$message" ]]; then
        # Generate automatic commit message based on changes
        local added=$(git diff --cached --name-only | wc -l)
        local modified=$(git diff --name-only | wc -l)
        message="Quick update: $added added, $modified modified files"
    fi
    
    echo "📝 Quick Git Commit"
    echo "==================="
    echo "Message: $message"
    echo
    
    git add -A
    git commit -m "$message"
    
    echo "✅ Commit completed"
    echo "📊 Repository status:"
    git status --short
}

## DOCKER UTILITIES ##

# Enhanced Docker cleanup
docker_cleanup() {
    echo "🐳 Docker Cleanup"
    echo "================"
    echo
    
    # Stop all running containers
    echo "⏹️  Stopping all running containers..."
    docker stop $(docker ps -q) 2>/dev/null || echo "No running containers"
    
    # Remove all stopped containers
    echo "🗑️  Removing stopped containers..."
    docker container prune -f
    
    # Remove unused images
    echo "🖼️  Removing unused images..."
    docker image prune -f
    
    # Remove unused volumes
    echo "💾 Removing unused volumes..."
    docker volume prune -f
    
    # Remove unused networks
    echo "🌐 Removing unused networks..."
    docker network prune -f
    
    echo
    echo "✅ Docker cleanup completed!"
    echo "📊 Remaining Docker usage:"
    docker system df
}

# Docker container manager
docker_manager() {
    echo "🐳 Docker Container Manager"
    echo "============================"
    echo
    
    local containers=$(docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}")
    
    if [[ $(echo "$containers" | wc -l) -eq 1 ]]; then
        echo "❌ No Docker containers found"
        return 0
    fi
    
    echo "$containers"
    echo
    
    read -p "Enter container name to manage (or 'q' to quit): " container_name
    
    if [[ "$container_name" == "q" ]]; then
        return 0
    fi
    
    echo
    echo "Container: $container_name"
    echo "Actions: [s]tart [st]op [r]estart [l]ogs [e]xec [d]elete"
    read -p "Choose action: " action
    
    case "$action" in
        s) docker start "$container_name" ;;
        st) docker stop "$container_name" ;;
        r) docker restart "$container_name" ;;
        l) docker logs -f "$container_name" ;;
        e) docker exec -it "$container_name" /bin/bash ;;
        d) docker rm "$container_name" ;;
        *) echo "Invalid action" ;;
    esac
}

## PERFORMANCE MONITORING ##

# System performance snapshot
perf_snapshot() {
    echo "📊 System Performance Snapshot"
    echo "==============================="
    echo "Timestamp: $(date)"
    echo
    
    # CPU usage
    echo "🔧 CPU Usage:"
    top -bn1 | grep "Cpu(s)" | awk '{printf "  %s\n", $2}'
    
    # Memory usage
    echo
    echo "🧠 Memory Usage:"
    free -h | awk 'NR==2{printf "  Used: %s/%s (%.1f%%)\n", $3, $2, ($3/$2)*100}'
    
    # Load average
    echo
    echo "⚖️  Load Average:"
    uptime | awk -F'load average:' '{printf "  %s\n", $2}'
    
    # Disk I/O
    echo
    echo "💾 Disk Usage:"
    df -h / | awk 'NR==2{printf "  Root: %s/%s (%s)\n", $3, $2, $5}'
    
    # Top processes by CPU
    echo
    echo "⚡ Top CPU Processes:"
    ps aux --sort=-%cpu | head -6 | tail -5 | awk '{printf "  %-12s %5s%% %s\n", $1, $3, $11}'
    
    # Top processes by memory
    echo
    echo "🧠 Top Memory Processes:"
    ps aux --sort=-%mem | head -6 | tail -5 | awk '{printf "  %-12s %5s%% %s\n", $1, $4, $11}'
}

# Monitor specific process
monitor_process() {
    local process_name="$1"
    local refresh_rate="${2:-2}"
    
    if [[ -z "$process_name" ]]; then
        echo "Usage: monitor_process <process_name> [refresh_rate]"
        return 1
    fi
    
    while true; do
        clear
        echo "👁️  Monitoring Process: $process_name"
        echo "======================================"
        echo "Refresh rate: ${refresh_rate}s (Ctrl+C to exit)"
        echo
        
        local pids=$(pgrep "$process_name")
        
        if [[ -z "$pids" ]]; then
            echo "❌ Process '$process_name' not found"
            sleep "$refresh_rate"
            continue
        fi
        
        echo "📊 Process Statistics:"
        ps -p "$pids" -o pid,ppid,pcpu,pmem,etime,cmd --no-headers | \
        while read -r line; do
            echo "  $line"
        done
        
        echo
        echo "📈 Resource Usage Over Time:"
        ps -p "$pids" -o pcpu,pmem --no-headers | \
        awk '{printf "  CPU: %s%%  Memory: %s%%\n", $1, $2}'
        
        sleep "$refresh_rate"
    done
}

## LOG ANALYSIS ##

# Analyze system logs
analyze_logs() {
    local log_file="${1:-/var/log/syslog}"
    local lines="${2:-100}"
    
    echo "📜 Log Analysis: $log_file"
    echo "=========================="
    echo "Analyzing last $lines lines"
    echo
    
    if [[ ! -f "$log_file" ]]; then
        echo "❌ Log file not found: $log_file"
        return 1
    fi
    
    # Error summary
    echo "❌ ERRORS:"
    tail -n "$lines" "$log_file" | grep -i error | head -5
    
    echo
    echo "⚠️  WARNINGS:"
    tail -n "$lines" "$log_file" | grep -i warning | head -5
    
    echo
    echo "📊 LOG STATISTICS:"
    tail -n "$lines" "$log_file" | awk '{
        errors += gsub(/[Ee]rror/, "")
        warnings += gsub(/[Ww]arning/, "")
        total++
    }
    END {
        printf "  Total lines: %d\n", total
        printf "  Errors: %d\n", errors
        printf "  Warnings: %d\n", warnings
    }'
}

# Watch log file in real-time
watch_log() {
    local log_file="${1:-/var/log/syslog}"
    
    if [[ ! -f "$log_file" ]]; then
        echo "❌ Log file not found: $log_file"
        return 1
    fi
    
    echo "👁️  Watching log file: $log_file"
    echo "Press Ctrl+C to stop"
    echo "================================"
    
    tail -f "$log_file" | while read -r line; do
        # Color code different log levels
        if [[ "$line" =~ [Ee]rror ]]; then
            echo -e "\033[31m$line\033[0m"  # Red for errors
        elif [[ "$line" =~ [Ww]arning ]]; then
            echo -e "\033[33m$line\033[0m"  # Yellow for warnings
        elif [[ "$line" =~ [Ii]nfo ]]; then
            echo -e "\033[32m$line\033[0m"  # Green for info
        else
            echo "$line"
        fi
    done
}