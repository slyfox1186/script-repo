#!/usr/bin/env bash
# Optimized versions of existing functions with modern bash practices

## OPTIMIZED FILE OPERATIONS ##

# Enhanced file creation with templates
mf_enhanced() {
    local file="$1"
    local template="$2"
    local -A templates
    
    # Define file templates
    templates=(
        ["bash"]="#!/usr/bin/env bash\n\n# Description: \n# Author: $(whoami)\n# Date: $(date +%Y-%m-%d)\n\n"
        ["python"]="#!/usr/bin/env python3\n\n\"\"\"\nDescription: \nAuthor: $(whoami)\nDate: $(date +%Y-%m-%d)\n\"\"\"\n\n"
        ["html"]="<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n    <meta charset=\"UTF-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n    <title>Document</title>\n</head>\n<body>\n    \n</body>\n</html>"
        ["js"]="/**\n * Description: \n * Author: $(whoami)\n * Date: $(date +%Y-%m-%d)\n */\n\n"
    )
    
    if [[ -z "$file" ]]; then
        read -p "Enter filename: " file
        echo "Available templates: ${!templates[*]}"
        read -p "Enter template type (or press Enter for none): " template
    fi
    
    if [[ -f "$file" ]]; then
        echo "⚠️  File already exists: $file"
        read -p "Overwrite? (y/N): " confirm
        [[ "$confirm" != "y" ]] && return 1
    fi
    
    # Create file with template if specified
    if [[ -n "$template" && -n "${templates[$template]}" ]]; then
        echo -e "${templates[$template]}" > "$file"
        echo "✅ Created $file with $template template"
    else
        touch "$file"
        echo "✅ Created empty file: $file"
    fi
    
    chmod 755 "$file"
    clear; ls -1AhFv --color --group-directories-first
}

# Smart directory creation with git init option
mdir_enhanced() {
    local dir="$1"
    local init_git="$2"
    
    if [[ -z "$dir" ]]; then
        read -p "Enter directory name: " dir
        read -p "Initialize git repository? (y/N): " init_git
    fi
    
    if [[ -d "$dir" ]]; then
        echo "⚠️  Directory already exists: $dir"
        read -p "Continue anyway? (y/N): " confirm
        [[ "$confirm" != "y" ]] && return 1
    fi
    
    mkdir -p "$dir"
    cd "$dir" || return 1
    
    if [[ "$init_git" == "y" ]]; then
        git init
        echo "# $(basename "$PWD")" > README.md
        echo "📝 Created README.md"
        
        # Create basic .gitignore
        cat > .gitignore << 'EOF'
# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Editor files
*.swp
*.swo
*~

# Log files
*.log

# Temporary files
*.tmp
*.temp
EOF
        echo "📄 Created .gitignore"
    fi
    
    echo "✅ Created directory: $dir"
    clear; ls -1AhFv --color --group-directories-first
}

## ENHANCED SEARCH FUNCTIONS ##

# Improved find with better error handling and features
ffind_enhanced() {
    local fname="$1"
    local ftype="$2"
    local fpath="${3:-.}"
    local max_depth="$4"
    local case_sensitive="$5"
    local -a find_args
    
    # Interactive mode if no arguments
    if [[ "$#" -eq 0 ]]; then
        echo "🔍 Enhanced Find Utility"
        echo "======================="
        read -p "Search term: " fname
        echo "File types: [f]ile, [d]irectory, [l]ink, [any]"
        read -p "Type (default: any): " ftype
        read -p "Search path (default: current dir): " fpath
        read -p "Max depth (default: unlimited): " max_depth
        read -p "Case sensitive? (y/N): " case_sensitive
        
        fpath="${fpath:-.}"
    fi
    
    # Validate search path
    if [[ ! -d "$fpath" ]]; then
        echo "❌ Invalid search path: $fpath"
        return 1
    fi
    
    # Build find command
    find_args=("$fpath")
    
    # Add max depth
    if [[ -n "$max_depth" && "$max_depth" =~ ^[0-9]+$ ]]; then
        find_args+=(-maxdepth "$max_depth")
    fi
    
    # Add name search (case sensitivity)
    if [[ "$case_sensitive" == "y" ]]; then
        find_args+=(-name "$fname")
    else
        find_args+=(-iname "$fname")
    fi
    
    # Add type filter
    case "$ftype" in
        f|file) find_args+=(-type f) ;;
        d|dir|directory) find_args+=(-type d) ;;
        l|link) find_args+=(-type l) ;;
    esac
    
    echo "🔍 Searching for '$fname' in $fpath..."
    echo "Command: find ${find_args[*]}"
    echo
    
    # Execute find and format output
    local results=0
    while IFS= read -r result; do
        ((results++))
        
        # Get file info
        if [[ -f "$result" ]]; then
            local size=$(du -h "$result" 2>/dev/null | cut -f1)
            local modified=$(stat -c '%Y' "$result" 2>/dev/null | xargs -I {} date -d '@{}' '+%Y-%m-%d %H:%M')
            echo "📄 $result ($size, modified: $modified)"
        elif [[ -d "$result" ]]; then
            local items=$(find "$result" -maxdepth 1 2>/dev/null | wc -l)
            echo "📁 $result ($((items-1)) items)"
        else
            echo "🔗 $result"
        fi
    done < <(find "${find_args[@]}" 2>/dev/null)
    
    echo
    if [[ $results -eq 0 ]]; then
        echo "❌ No results found"
    else
        echo "✅ Found $results result(s)"
    fi
}

# Smart file search with content preview
search_files() {
    local search_term="$1"
    local file_pattern="${2:-*}"
    local search_path="${3:-.}"
    local show_content="${4:-n}"
    
    if [[ -z "$search_term" ]]; then
        echo "Usage: search_files <search_term> [file_pattern] [path] [show_content]"
        echo "Example: search_files 'function' '*.sh' /home/user y"
        return 1
    fi
    
    echo "🔍 Searching for '$search_term' in $file_pattern files"
    echo "Path: $search_path"
    echo "=================================================="
    echo
    
    local results=0
    while IFS= read -r file; do
        ((results++))
        local matches=$(grep -c "$search_term" "$file" 2>/dev/null)
        echo "📄 $file ($matches matches)"
        
        if [[ "$show_content" == "y" ]]; then
            echo "   Preview:"
            grep -n "$search_term" "$file" 2>/dev/null | head -3 | sed 's/^/   /'
            echo
        fi
    done < <(find "$search_path" -name "$file_pattern" -type f -exec grep -l "$search_term" {} \; 2>/dev/null)
    
    if [[ $results -eq 0 ]]; then
        echo "❌ No files found containing '$search_term'"
    else
        echo "✅ Found $results file(s) containing '$search_term'"
    fi
}

## ENHANCED SYSTEM UTILITIES ##

# Advanced system information
sys_info() {
    echo "🖥️  System Information"
    echo "====================="
    echo
    
    # Basic system info
    echo "📋 BASIC INFO:"
    echo "  Hostname: $(hostname)"
    echo "  OS: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2- | tr -d '"')"
    echo "  Kernel: $(uname -r)"
    echo "  Architecture: $(uname -m)"
    echo "  Uptime: $(uptime -p)"
    echo
    
    # Hardware info
    echo "🔧 HARDWARE:"
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    local cpu_cores=$(nproc)
    local total_mem=$(free -h | awk 'NR==2{print $2}')
    echo "  CPU: $cpu_model ($cpu_cores cores)"
    echo "  Memory: $total_mem"
    echo
    
    # Storage info
    echo "💾 STORAGE:"
    df -h --output=source,size,used,avail,pcent,target | grep -E '^(/dev|tmpfs)' | \
    while read -r source size used avail pcent target; do
        echo "  $target: $used/$size ($pcent)"
    done
    echo
    
    # Network info
    echo "🌐 NETWORK:"
    ip addr show | awk '/inet / && !/127.0.0.1/ {
        iface = $NF
        ip = $2
        printf "  %s: %s\n", iface, ip
    }'
    echo
    
    # Process count
    echo "⚙️  PROCESSES:"
    local total_processes=$(ps aux | wc -l)
    local running_processes=$(ps aux | grep -c " R ")
    echo "  Total: $total_processes"
    echo "  Running: $running_processes"
}

# Enhanced process management
proc_manager() {
    local action="$1"
    local process_name="$2"
    
    if [[ -z "$action" ]]; then
        echo "🔧 Process Manager"
        echo "=================="
        echo "Actions: list, kill, monitor, info"
        read -p "Choose action: " action
    fi
    
    case "$action" in
        list)
            echo "📋 Running Processes:"
            ps aux --sort=-%cpu | head -20 | awk 'NR==1{print "  " $0} NR>1{printf "  %-8s %5s%% %5s%% %s\n", $1, $3, $4, $11}'
            ;;
        kill)
            if [[ -z "$process_name" ]]; then
                read -p "Enter process name or PID: " process_name
            fi
            
            if [[ "$process_name" =~ ^[0-9]+$ ]]; then
                # It's a PID
                echo "Killing process PID: $process_name"
                kill "$process_name"
            else
                # It's a process name
                local pids=$(pgrep "$process_name")
                if [[ -n "$pids" ]]; then
                    echo "Found processes: $pids"
                    read -p "Kill all? (y/N): " confirm
                    if [[ "$confirm" == "y" ]]; then
                        pkill "$process_name"
                        echo "✅ Processes killed"
                    fi
                else
                    echo "❌ No processes found matching '$process_name'"
                fi
            fi
            ;;
        monitor)
            if [[ -z "$process_name" ]]; then
                read -p "Enter process name: " process_name
            fi
            monitor_process "$process_name"
            ;;
        info)
            if [[ -z "$process_name" ]]; then
                read -p "Enter process name or PID: " process_name
            fi
            
            echo "📊 Process Information: $process_name"
            echo "===================================="
            
            if [[ "$process_name" =~ ^[0-9]+$ ]]; then
                ps -p "$process_name" -o pid,ppid,user,pcpu,pmem,etime,cmd
            else
                ps aux | grep "$process_name" | grep -v grep
            fi
            ;;
        *)
            echo "❌ Invalid action. Use: list, kill, monitor, info"
            ;;
    esac
}

## DEVELOPMENT UTILITIES ##

# Enhanced Git utilities
git_utils() {
    local command="$1"
    
    if [[ -z "$command" ]]; then
        echo "🔧 Git Utilities"
        echo "==============="
        echo "Commands: status-all, clean-branches, create-branch, quick-commit"
        read -p "Choose command: " command
    fi
    
    case "$command" in
        status-all)
            git_status_all
            ;;
        clean-branches)
            echo "🧹 Cleaning merged branches..."
            git branch --merged | grep -v "\*\|main\|master" | xargs -n 1 git branch -d
            echo "✅ Cleaned merged branches"
            ;;
        create-branch)
            read -p "Branch name: " branch_name
            read -p "Base branch (default: main): " base_branch
            base_branch="${base_branch:-main}"
            
            git checkout "$base_branch"
            git pull origin "$base_branch"
            git checkout -b "$branch_name"
            echo "✅ Created and switched to branch: $branch_name"
            ;;
        quick-commit)
            git_quick_commit "$2"
            ;;
        *)
            echo "❌ Invalid command"
            ;;
    esac
}

# Project template creator
create_project() {
    local project_name="$1"
    local project_type="$2"
    local -A templates
    
    # Define project templates
    templates=(
        ["bash"]="Bash script project"
        ["python"]="Python project with virtual environment"
        ["node"]="Node.js project with package.json"
        ["html"]="Static HTML/CSS/JS project"
    )
    
    if [[ -z "$project_name" ]]; then
        read -p "Project name: " project_name
        echo "Available templates: ${!templates[*]}"
        read -p "Project type: " project_type
    fi
    
    if [[ -d "$project_name" ]]; then
        echo "❌ Directory already exists: $project_name"
        return 1
    fi
    
    echo "🚀 Creating $project_type project: $project_name"
    echo "=============================================="
    
    mkdir -p "$project_name"
    cd "$project_name" || return 1
    
    # Initialize git
    git init
    
    case "$project_type" in
        bash)
            echo "#!/usr/bin/env bash" > "$project_name.sh"
            echo "# $project_name - Bash script" >> "$project_name.sh"
            echo >> "$project_name.sh"
            chmod +x "$project_name.sh"
            ;;
        python)
            echo "# $project_name" > README.md
            echo "#!/usr/bin/env python3" > main.py
            echo '"""Main module for '"$project_name"'"""' >> main.py
            echo >> main.py
            python3 -m venv venv
            echo "venv/" > .gitignore
            echo "__pycache__/" >> .gitignore
            echo "*.pyc" >> .gitignore
            ;;
        node)
            cat > package.json << EOF
{
  "name": "$project_name",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "author": "$(whoami)",
  "license": "MIT"
}
EOF
            echo "console.log('Hello from $project_name');" > index.js
            echo "node_modules/" > .gitignore
            echo "*.log" >> .gitignore
            ;;
        html)
            cat > index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$project_name</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <h1>$project_name</h1>
    <script src="script.js"></script>
</body>
</html>
EOF
            echo "/* Styles for $project_name */" > style.css
            echo "body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }" >> style.css
            echo "// JavaScript for $project_name" > script.js
            echo "console.log('$project_name loaded');" >> script.js
            ;;
    esac
    
    # Create common files
    echo "# $project_name" > README.md
    echo >> README.md
    echo "${templates[$project_type]}" >> README.md
    
    # Initial commit
    git add .
    git commit -m "Initial commit: $project_name project setup"
    
    echo "✅ Project created successfully!"
    echo "📁 Location: $(pwd)"
    ls -la
}

## SHORTCUT ALIASES FOR ENHANCED FUNCTIONS ##

# Create convenient aliases
alias mf='mf_enhanced'
alias mdir='mdir_enhanced'
alias ffind='ffind_enhanced'
alias sysinfo='sys_info'
alias procman='proc_manager'
alias gitutils='git_utils'