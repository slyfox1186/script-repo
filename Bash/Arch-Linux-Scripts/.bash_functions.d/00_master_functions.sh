#!/usr/bin/env bash
# Master Functions - Enhanced function discovery and management

## ENHANCED MASTER FUNCTION LIBRARY ##

# Enhanced function listing with categories, search, and better UX
func_help() {
    local search_term="$1"
    local show_category="$2"
    local show_definitions=""
    local -A categories
    local -A func_descriptions
    
    # Function categories and descriptions
    categories=(
        ["01_gui_apps.sh"]="🖥️  GUI Applications"
        ["02_filesystem.sh"]="📁 File System Operations"
        ["03_text_processing.sh"]="📝 Text Processing"
        ["04_compression.sh"]="🗜️  Archive & Compression"
        ["06_process_management.sh"]="⚙️  Process Management"
        ["07_dev_tools.sh"]="🔧 Development Tools"
        ["08_file_analysis.sh"]="🔍 File Analysis"
        ["09_security.sh"]="🔒 Security Functions"
        ["10_networking.sh"]="🌐 Network Tools"
        ["11_multimedia.sh"]="🎵 Multimedia"
        ["12_utilities.sh"]="🛠️  System Utilities"
        ["13_database.sh"]="🗃️  Database Functions"
        ["14_docker.sh"]="🐳 Docker Utilities"
        ["15_package_manager.sh"]="📦 Package Management"
        ["16_redis_and_npm.sh"]="🔄 Redis & NPM"
        ["17_other.sh"]="🔧 Miscellaneous"
        ["18_sed.sh"]="✂️  Advanced Sed"
        ["19_grep.sh"]="🔎 Enhanced Grep"
        ["00_master_functions.sh"]="🎯 Master Functions"
        ["20_enhanced_utilities.sh"]="⚡ Enhanced Utilities"
        ["21_optimized_functions.sh"]="🚀 Optimized Functions"
    )
    
    # Function descriptions (comprehensive list)
    func_descriptions=(
        # Master functions
        ["func_help"]="🎯 Enhanced function discovery and help system"
        ["func_search"]="🔍 Quick function search by term"
        ["func_cat"]="📂 Show functions by category"
        ["func_list"]="📋 List all available functions"
        ["func_info"]="ℹ️  Detailed information about specific function"
        ["func_stats"]="📊 Statistics about function library"
        
        # System monitoring & diagnostics
        ["sys_monitor"]="📊 Real-time system monitoring dashboard"
        ["find_large"]="🔍 Find large files consuming disk space"
        ["sys_cleanup"]="🧹 Comprehensive system cleanup"
        ["sys_info"]="🖥️  Advanced system information display"
        ["perf_snapshot"]="📸 System performance snapshot"
        ["monitor_process"]="👁️  Monitor specific process in real-time"
        
        # Backup & recovery
        ["quick_backup"]="💾 Quick file/directory backup utility"
        ["list_backups"]="📋 List all available backups"
        
        # Network utilities
        ["net_info"]="📡 Enhanced network information display"
        ["port_scan"]="🌐 Quick port scanner with range support"
        ["speed_test"]="⚡ Network speed and connectivity test"
        
        # Git utilities
        ["git_status_all"]="📋 Git status for all repositories in directory"
        ["git_quick_commit"]="⚡ Quick git commit with auto-generated messages"
        ["git_utils"]="🔧 Comprehensive git utility functions"
        
        # Docker utilities
        ["docker_cleanup"]="🐳 Enhanced Docker cleanup (containers, images, volumes)"
        ["docker_manager"]="🐳 Interactive Docker container manager"
        
        # Log analysis
        ["analyze_logs"]="📜 Analyze system logs for errors and patterns"
        ["watch_log"]="👁️  Watch log files in real-time with color coding"
        
        # Enhanced file operations
        ["mf_enhanced"]="📄 Enhanced file creation with templates"
        ["mdir_enhanced"]="📁 Smart directory creation with git init option"
        ["ffind_enhanced"]="🔍 Advanced find with better features and UI"
        ["search_files"]="🔎 Smart file search with content preview"
        
        # Project management
        ["create_project"]="🚀 Create new projects with templates (bash/python/node/html)"
        ["proc_manager"]="⚙️  Enhanced process management utility"
        
        # Existing system utilities
        ["sbrc"]="🔄 Refresh bash configuration and display directory"
        ["fs_info"]="💾 Display filesystem usage with color coding and options"
        ["test_gcc"]="🔧 Test GCC compiler installation"
        ["test_clang"]="🔧 Test Clang compiler installation"
        ["sc"]="✅ Shellcheck validation with enhanced output"
        ["ffind"]="🔍 Safe find command with interactive prompts"
        ["mf"]="📄 Create file with proper permissions"
        ["mdir"]="📁 Create directory and navigate to it"
        ["town"]="👤 Take ownership of files/directories"
        ["toa"]="👤 Take ownership of all files in current directory"
        ["fix_up"]="🔧 Fix user folder permissions (SSH, GPG)"
        ["count_dir"]="📊 Count files in directory (non-recursive)"
        ["count_dirr"]="📊 Count files in directory (recursive)"
        ["countf"]="📊 Count items in current folder"
        ["rmd"]="🗑️  Remove directory with confirmation"
        ["rmf"]="🗑️  Remove file with confirmation"
        ["cpf"]="📋 Copy file to ~/tmp with proper ownership"
        ["mvf"]="📦 Move file to ~/tmp with proper ownership"
        ["ls_interactive"]="📂 Interactive directory listing with sort options"
        
        # Development tools
        ["gcc_native"]="🔧 Check GCC native compilation settings"
        ["c_cmake"]="🏗️  CMake configuration with curses GUI"
        ["pkg-config-path"]="📍 Show pkg-config search paths"
        ["show_rpath"]="🔍 Show binary runpath information"
        ["dl_clang"]="⬇️  Download Clang installer scripts"
        ["pipu"]="🐍 Update all pip packages"
        ["venv"]="🐍 Python virtual environment manager"
        
        # Utility functions
        ["rdvc"]="🧮 Reddit downvote calculator"
        ["airules"]="🤖 AI helper rules for bash scripting"
        ["pw"]="📋 Copy warning message to clipboard"
        ["sai"]="💬 Save AI improvement message"
        ["script_repo"]="📚 GitHub script repository installer menu"
        ["dlfs"]="⬇️  Download favorite scripts from GitHub"
        ["gitdl"]="⬇️  Download common development scripts"
        ["rftn"]="🖼️  Refresh thumbnail cache"
    )
    
    # Display usage if no arguments
    if [[ $# -eq 0 ]]; then
        echo "🎯 Function Help - Enhanced Bash Function Discovery"
        echo "=================================================="
        echo
        echo "Usage: func_help [search_term] [category]"
        echo
        echo "Examples:"
        echo "  func_help                    # Show all functions by category"
        echo "  func_help git               # Search for functions containing 'git'"
        echo "  func_help '' dev_tools      # Show all development tools"
        echo "  func_help docker            # Search for docker-related functions"
        echo
        echo "Available categories:"
        for file in "${!categories[@]}"; do
            echo "  • ${categories[$file]}"
        done
        echo
        echo "Quick shortcuts:"
        echo "  • func_list          # Simple function list"
        echo "  • func_search <term> # Quick search"
        echo "  • func_cat <category># Show category"
        return 0
    fi
    
    # Parse arguments
    case "$1" in
        -d|--definitions) show_definitions="true"; shift ;;
    esac
    
    # Header
    echo "🎯 Bash Function Library"
    echo "========================"
    echo
    
    # If searching for specific term
    if [[ -n "$search_term" && "$search_term" != "''" ]]; then
        echo "🔍 Search results for: '$search_term'"
        echo "-----------------------------------"
        _search_functions "$search_term"
        return 0
    fi
    
    # If showing specific category
    if [[ -n "$show_category" ]]; then
        echo "📂 Category: $show_category"
        echo "------------------------"
        _show_category "$show_category"
        return 0
    fi
    
    # Show all functions by category
    echo "📚 All Functions by Category"
    echo "----------------------------"
    
    local bash_func_dir="$HOME/.bash_functions.d"
    [[ ! -d "$bash_func_dir" ]] && { echo "❌ Bash functions directory not found"; return 1; }
    
    shopt -s nullglob
    for script in "$bash_func_dir"/*.sh; do
        local filename=$(basename "$script")
        local category="${categories[$filename]:-📄 Unknown Category}"
        
        echo
        echo "$category ($filename)"
        echo "$(printf '─%.0s' {1..50})"
        
        # Extract function names and show with descriptions
        while IFS= read -r func_name; do
            local desc="${func_descriptions[$func_name]:-📌 Function: $func_name}"
            printf "  %-20s %s\n" "$func_name" "$desc"
        done < <(grep -oP '^(?:function\s+)?\s*[\w-]+\s*\(\)' "$script" | sed -E 's/^(function[[:space:]]+)?\s*([a-zA-Z0-9_-]+)\s*\(\)/\2/' | sort)
    done
    
    echo
    echo "💡 Tip: Use 'func_help <search_term>' to find specific functions"
    echo "💡 Tip: Use 'func_help '' <category>' to show specific category"
}

# Quick function search
func_search() {
    local search_term="$1"
    [[ -z "$search_term" ]] && { echo "Usage: func_search <search_term>"; return 1; }
    
    func_help "$search_term"
}

# Show functions by category
func_cat() {
    local category="$1"
    [[ -z "$category" ]] && { echo "Usage: func_cat <category>"; return 1; }
    
    func_help "" "$category"
}

# Simple function list (replaces list_loaded_functions)
func_list() {
    echo "📋 All Available Functions"
    echo "========================="
    declare -F | awk '{print $3}' | sort | nl -w3 -s'. '
    echo
    echo "Total functions: $(declare -F | wc -l)"
}

# Helper function to search functions
_search_functions() {
    local search_term="$1"
    local bash_func_dir="$HOME/.bash_functions.d"
    local found=0
    
    shopt -s nullglob
    for script in "$bash_func_dir"/*.sh; do
        local filename=$(basename "$script")
        
        # Search function names
        while IFS= read -r func_name; do
            if [[ "$func_name" =~ $search_term ]]; then
                local desc="${func_descriptions[$func_name]:-📌 Function in $filename}"
                printf "  %-20s %s\n" "$func_name" "$desc"
                ((found++))
            fi
        done < <(grep -oP '^(?:function\s+)?\s*[\w-]+\s*\(\)' "$script" | sed -E 's/^(function[[:space:]]+)?\s*([a-zA-Z0-9_-]+)\s*\(\)/\2/')
        
        # Search function content if function name doesn't match
        if grep -q "$search_term" "$script" 2>/dev/null; then
            while IFS= read -r func_name; do
                if ! [[ "$func_name" =~ $search_term ]]; then
                    local func_body=$(sed -n "/^$func_name()/,/^}/p" "$script" 2>/dev/null)
                    if [[ "$func_body" =~ $search_term ]]; then
                        local desc="${func_descriptions[$func_name]:-📌 Contains '$search_term' in $filename}"
                        printf "  %-20s %s\n" "$func_name" "$desc"
                        ((found++))
                    fi
                fi
            done < <(grep -oP '^(?:function\s+)?\s*[\w-]+\s*\(\)' "$script" | sed -E 's/^(function[[:space:]]+)?\s*([a-zA-Z0-9_-]+)\s*\(\)/\2/')
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        echo "❌ No functions found matching '$search_term'"
    else
        echo
        echo "✅ Found $found function(s) matching '$search_term'"
    fi
}

# Helper function to show category
_show_category() {
    local category="$1"
    local bash_func_dir="$HOME/.bash_functions.d"
    
    # Find the file matching the category
    shopt -s nullglob
    for script in "$bash_func_dir"/*.sh; do
        local filename=$(basename "$script")
        if [[ "$filename" =~ $category ]] || [[ "${categories[$filename]}" =~ $category ]]; then
            echo "📁 Functions in $filename:"
            echo
            
            while IFS= read -r func_name; do
                local desc="${func_descriptions[$func_name]:-📌 Function: $func_name}"
                printf "  %-20s %s\n" "$func_name" "$desc"
            done < <(grep -oP '^(?:function\s+)?\s*[\w-]+\s*\(\)' "$script" | sed -E 's/^(function[[:space:]]+)?\s*([a-zA-Z0-9_-]+)\s*\(\)/\2/' | sort)
            
            return 0
        fi
    done
    
    echo "❌ Category '$category' not found"
}

# Function to show detailed information about a specific function
func_info() {
    local func_name="$1"
    [[ -z "$func_name" ]] && { echo "Usage: func_info <function_name>"; return 1; }
    
    # Check if function exists
    if ! declare -F "$func_name" &>/dev/null; then
        echo "❌ Function '$func_name' not found"
        return 1
    fi
    
    echo "🔍 Function Information: $func_name"
    echo "=================================="
    echo
    
    # Find the source file
    local bash_func_dir="$HOME/.bash_functions.d"
    local source_file=""
    
    shopt -s nullglob
    for script in "$bash_func_dir"/*.sh; do
        if grep -q "^$func_name()" "$script" 2>/dev/null; then
            source_file="$script"
            break
        fi
    done
    
    if [[ -n "$source_file" ]]; then
        echo "📄 Source file: $(basename "$source_file")"
        echo "📍 Full path: $source_file"
        echo
        
        # Show function definition
        echo "📝 Function definition:"
        echo "----------------------"
        declare -f "$func_name"
        echo
        
        # Show description if available
        local desc="${func_descriptions[$func_name]}"
        if [[ -n "$desc" ]]; then
            echo "📖 Description: $desc"
        fi
    else
        echo "⚠️  Source file not found in $bash_func_dir"
        echo "📝 Function definition:"
        echo "----------------------"
        declare -f "$func_name"
    fi
}

# Quick stats about the function library
func_stats() {
    echo "📊 Bash Function Library Statistics"
    echo "==================================="
    echo
    
    local bash_func_dir="$HOME/.bash_functions.d"
    local total_files=0
    local total_functions=0
    
    shopt -s nullglob
    for script in "$bash_func_dir"/*.sh; do
        ((total_files++))
        local func_count=$(grep -c '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*()' "$script" 2>/dev/null || echo 0)
        total_functions=$((total_functions + func_count))
        
        local filename=$(basename "$script")
        local category="${categories[$filename]:-📄 Unknown}"
        printf "  %-30s %2d functions\n" "$category" "$func_count"
    done
    
    echo
    echo "📈 Summary:"
    echo "  • Total files: $total_files"
    echo "  • Total functions: $total_functions"
    echo "  • Average functions per file: $((total_functions / total_files))"
    echo
    echo "💡 Use 'func_help' to explore available functions"
}

# Alias for backward compatibility
alias list_func='func_help'
alias list_loaded_functions='func_list'