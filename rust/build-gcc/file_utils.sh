# File operations utilities - ADD TO SCRIPT

# File validation functions
validate_file() {
    local file="$1"
    local validation_type="${2:-exists}"
    
    case "$validation_type" in
        "exists")
            [[ -f "$file" ]]
            ;;
        "readable")
            [[ -r "$file" ]]
            ;;
        "writable")
            [[ -w "$file" ]]
            ;;
        "executable")
            [[ -x "$file" ]]
            ;;
        "tarball")
            tar -tf "$file" >/dev/null 2>&1
            ;;
        "checksum")
            local expected_checksum="$3"
            local actual_checksum
            actual_checksum=$(sha512sum "$file" | cut -d' ' -f1)
            [[ "$expected_checksum" == "$actual_checksum" ]]
            ;;
        *)
            fail "Unknown validation type: $validation_type"
            ;;
    esac
}

# Extract archive with automatic format detection
extract_archive() {
    local archive="$1"
    local destination="${2:-.}"
    local strip_components="${3:-0}"
    
    local extract_cmd
    case "$archive" in
        *.tar.xz|*.txz)
            extract_cmd="tar -Jxf"
            ;;
        *.tar.gz|*.tgz)
            extract_cmd="tar -zxf"
            ;;
        *.tar.bz2|*.tbz2)
            extract_cmd="tar -jxf"
            ;;
        *.tar)
            extract_cmd="tar -xf"
            ;;
        *.zip)
            extract_cmd="unzip -q"
            ;;
        *)
            fail "Unsupported archive format: $archive"
            ;;
    esac
    
    if [[ "$archive" == *.tar* ]]; then
        $extract_cmd "$archive" -C "$destination" --strip-components="$strip_components"
    else
        $extract_cmd "$archive" -d "$destination"
    fi
}

# Create symbolic links with conflict detection
create_symlink() {
    local target="$1"
    local link_path="$2"
    local force="${3:-false}"
    local use_sudo="${4:-false}"
    
    local ln_cmd="ln -sf"
    [[ "$use_sudo" == "true" ]] && ln_cmd="sudo $ln_cmd"
    
    # Check for conflicts
    if [[ -e "$link_path" && "$force" != "true" ]]; then
        if [[ -L "$link_path" ]]; then
            local current_target
            current_target=$(readlink "$link_path")
            if [[ "$current_target" == "$target" ]]; then
                log "DEBUG" "Symlink already correct: $link_path -> $target"
                return 0
            fi
        else
            log "WARNING" "Non-symlink file exists at $link_path, skipping"
            return 1
        fi
    fi
    
    if [[ "$dry_run" -eq 1 ]]; then
        log "INFO" "Dry run: would create symlink $link_path -> $target"
        return 0
    fi
    
    $ln_cmd "$target" "$link_path"
    log "DEBUG" "Created symlink: $link_path -> $target"
}

# File size and disk space utilities
get_file_size() {
    local file="$1"
    local unit="${2:-bytes}"
    
    if [[ ! -f "$file" ]]; then
        echo "0"
        return
    fi
    
    case "$unit" in
        "bytes"|"b")
            stat -c%s "$file"
            ;;
        "kb")
            echo $(($(stat -c%s "$file") / 1024))
            ;;
        "mb")
            echo $(($(stat -c%s "$file") / 1024 / 1024))
            ;;
        "gb")
            echo $(($(stat -c%s "$file") / 1024 / 1024 / 1024))
            ;;
        *)
            fail "Unknown size unit: $unit"
            ;;
    esac
}

get_available_space() {
    local path="$1"
    local unit="${2:-gb}"
    
    case "$unit" in
        "gb")
            df -BG "$path" | awk 'NR==2 {print $4}' | sed 's/G//'
            ;;
        "mb")
            df -BM "$path" | awk 'NR==2 {print $4}' | sed 's/M//'
            ;;
        "kb")
            df -BK "$path" | awk 'NR==2 {print $4}' | sed 's/K//'
            ;;
        *)
            fail "Unknown space unit: $unit"
            ;;
    esac
}