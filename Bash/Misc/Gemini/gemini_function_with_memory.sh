#!/usr/bin/env bash
# Enhanced Gemini quick query function with memory support and robust argument parsing
# Add this to your ~/.bash_functions.d/ directory

# Help function to eliminate duplication
_gemini_usage() {
    echo "Usage: gemini [options] -q \"your question\""
    echo ""
    echo "Query Options:"
    echo "  -q, --query TEXT        The query to send to Gemini (required for queries)"
    echo "  -f, --file PATH         Include file content in prompt (can be used multiple times)"
    echo ""
    echo "Model Options:"
    echo "  -m, --model MODEL       Specify custom model ID"
    echo "  -p, --pro               Use Gemini 2.5 Pro Preview (best accuracy)"
    echo "  --flash                 Use Gemini 2.5 Flash Preview (fast, default)"
    echo "  -t, --flash-thinking    Use Gemini 2.0 Flash Thinking (reasoning)"
    echo ""
    echo "Session/Memory Options:"
    echo "  -s, --session NAME      Use a named session for conversation history"
    echo "  -r, --reset, -n, --new  Start fresh (ignore history for this call)"
    echo "  --list-sessions         List all available sessions"
    echo "  -c, --clear-session [NAME]  Clear a session (default: current session)"
    echo ""
    echo "Default model: gemini-2.5-flash-preview-05-20"
    echo "Default session: default"
    echo ""
    echo "Examples:"
    echo "  gemini -q \"What is Python?\""
    echo "  gemini -s work -q \"Tell me about our project\""
    echo "  gemini -rq \"Start a new topic\"  # Reset + query"
    echo "  gemini --list-sessions"
    echo "  gemini --clear-session work"
    echo "  gemini -sc work         # Set session + clear it"
    echo "  gemini -fq \"Review this code\" app.py  # File + query"
    echo "  gemini -pq \"Complex question\"  # Pro model + query"
    echo "  gemini -tq \"Reasoning task\"    # Flash-thinking + query"
}

# Function to quickly query Gemini API with conversation memory
gemini() {
    # Constants
    local GEMINI_SCRIPT_ENHANCED="/usr/local/bin/gemini_query_with_memory.py"
    local GEMINI_SCRIPT_BASIC="/usr/local/bin/gemini_query.py"
    
    # Initialize variables
    local query=""
    local model=""
    local session="default"
    local reset=false
    local list_sessions=false
    local clear_session=""
    local files=()
    
    # Model selection flags (for conflict detection)
    local pro_flag=false
    local flash_thinking_flag=false
    local model_flag=false
    
    # Use getopt for robust argument parsing
    local short_opts="q:m:s:f:rcnpht"
    local long_opts="query:,model:,session:,file:,reset,clear-session::,new,pro,flash,flash-thinking,list-sessions,help"
    
    # Parse arguments with getopt
    local parsed_args
    if ! parsed_args=$(getopt -o "$short_opts" -l "$long_opts" -n "gemini" -- "$@"); then
        echo "Use -h or --help for usage information"
        return 1
    fi
    
    # Set parsed arguments
    eval set -- "$parsed_args"
    
    # Process arguments
    while true; do
        case "$1" in
            -q|--query)
                query="$2"
                shift 2
                ;;
            -m|--model)
                model="$2"
                model_flag=true
                shift 2
                ;;
            -s|--session)
                session="$2"
                shift 2
                ;;
            -f|--file)
                files+=("$2")
                shift 2
                ;;
            -r|--reset)
                reset=true
                shift
                ;;
            -c|--clear-session)
                if [[ -n "$2" ]]; then
                    clear_session="$2"
                    shift 2
                else
                    clear_session="current"
                    shift
                fi
                ;;
            -n|--new)
                reset=true
                shift
                ;;
            -p|--pro)
                model="gemini-2.5-pro-preview-06-05"
                pro_flag=true
                shift
                ;;
            --flash)
                model="gemini-2.5-flash-preview-05-20"
                shift
                ;;
            -t|--flash-thinking)
                model="gemini-2.0-flash-thinking-exp"
                flash_thinking_flag=true
                shift
                ;;
            --list-sessions)
                list_sessions=true
                shift
                ;;
            -h|--help)
                _gemini_usage
                return 0
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Error: Unknown option: $1"
                _gemini_usage
                return 1
                ;;
        esac
    done
    
    # Validate conflicting model options
    local model_count=0
    [[ "$pro_flag" == "true" ]] && ((model_count++))
    [[ "$flash_thinking_flag" == "true" ]] && ((model_count++))
    [[ "$model_flag" == "true" ]] && ((model_count++))
    
    if (( model_count > 1 )); then
        echo "Error: Please specify only one model option (-p, -t, or -m)."
        return 1
    fi
    
    # Handle list sessions
    if [[ "$list_sessions" == "true" ]]; then
        if [[ -f "$GEMINI_SCRIPT_ENHANCED" ]]; then
            python3 "$GEMINI_SCRIPT_ENHANCED" --list-sessions
        else
            echo "Error: Enhanced Gemini script not found at $GEMINI_SCRIPT_ENHANCED"
            return 1
        fi
        return 0
    fi
    
    # Handle clear session
    if [[ -n "$clear_session" ]]; then
        if [[ -f "$GEMINI_SCRIPT_ENHANCED" ]]; then
            # If "current" was specified, use the session name
            if [[ "$clear_session" == "current" ]]; then
                python3 "$GEMINI_SCRIPT_ENHANCED" --clear-session "$session"
            else
                python3 "$GEMINI_SCRIPT_ENHANCED" --clear-session "$clear_session"
            fi
        else
            echo "Error: Enhanced Gemini script not found at $GEMINI_SCRIPT_ENHANCED"
            return 1
        fi
        return 0
    fi
    
    # Check if query was provided for normal operation
    if [[ -z "$query" ]]; then
        echo "Error: Query is required"
        echo "Usage: gemini -q \"your question here\" [options]"
        echo "Use -h or --help for more information"
        return 1
    fi
    
    # Determine which script to use
    local GEMINI_SCRIPT="$GEMINI_SCRIPT_ENHANCED"
    if [[ ! -f "$GEMINI_SCRIPT" ]]; then
        GEMINI_SCRIPT="$GEMINI_SCRIPT_BASIC"
        if [[ "$session" != "default" ]] || [[ "$reset" == "true" ]] || [[ ${#files[@]} -gt 0 ]]; then
            echo "Warning: Memory and file features not available. Install gemini_query_with_memory.py"
        fi
    fi
    
    # Check if script exists
    if [[ ! -f "$GEMINI_SCRIPT" ]]; then
        echo "Error: Gemini script not found at $GEMINI_SCRIPT"
        echo ""
        echo "To install the enhanced script with memory support, run:"
        echo "  sudo cp /path/to/gemini_query_with_memory.py /usr/local/bin/"
        echo "  sudo chmod +x /usr/local/bin/gemini_query_with_memory.py"
        echo ""
        echo "Make sure you have installed the required Python package:"
        echo "  pip install -q -U google-genai"
        return 1
    fi
    
    # Check if API key is set
    if [[ -z "$GEMINI_API_KEY" ]]; then
        echo "Error: GEMINI_API_KEY environment variable is not set"
        echo "Add to your ~/.bashrc: export GEMINI_API_KEY='your-api-key-here'"
        return 1
    fi
    
    # Build command
    local cmd=(python3 "$GEMINI_SCRIPT" "$query")
    
    # Add model if specified
    if [[ -n "$model" ]]; then
        cmd+=(--model "$model")
    fi
    
    # Add session and other options if using enhanced script
    if [[ "$GEMINI_SCRIPT" == "$GEMINI_SCRIPT_ENHANCED" ]]; then
        if [[ "$session" != "default" ]]; then
            cmd+=(--session "$session")
        fi
        if [[ "$reset" == "true" ]]; then
            cmd+=(--reset)
        fi
        # Add file arguments
        for file in "${files[@]}"; do
            cmd+=(--file "$file")
        done
    fi
    
    # Execute the command
    "${cmd[@]}"
}

# Optional: Alias for shorter command
alias g='gemini'
