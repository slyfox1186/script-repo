#!/usr/bin/env bash
#
# Bash wrapper for gemini_api.py. Provides a user-friendly command-line interface
# with robust argument parsing for interacting with the Gemini API.
#
# To install, add this function to your ~/.bashrc or ~/.zshrc,
# or save it as a file and source it.
#

# Main function, aliased as 'g' for convenience.
gemini() {
    # --- Configuration ---
    # The full path to the Python backend script.
    local GEMINI_SCRIPT="/usr/local/bin/gemini_api.py"

    # --- Pre-flight Checks ---
    if [[ ! -x "$GEMINI_SCRIPT" ]]; then
        echo "Error: Gemini script not found or not executable at '$GEMINI_SCRIPT'" >&2
        echo "Please ensure 'gemini_api.py' is installed and executable." >&2
        return 1
    fi
    if ! command -v getopt >/dev/null 2>&1; then
        echo "Error: 'getopt' command not found. Please install 'util-linux'." >&2
        return 1
    fi

    # --- Help/Usage Function ---
    _gemini_usage() {
        cat << EOF
Usage: gemini [options] "your question"
       gemini [management-options]

A CLI for Google's Gemini with session memory and file context.

Query Options:
  -q, --query TEXT        The query to send to Gemini. Can also be the last argument.
  -f, --file PATH         Include file content. Can be used multiple times.

Model Options:
  -p, --pro               Use the high-quality model (gemini-1.5-pro-latest).
      --flash             Use the fast model (gemini-1.5-flash-latest) [default].
  -m, --model ID          Specify a custom model ID.

Session & Memory:
  -s, --session NAME      Use a named session for conversation history (default: "default").
  -r, --reset, -n, --new  Start fresh (ignore history for this one call).

Management (mutually exclusive):
      --list-sessions     List all available sessions.
  -c, --clear-session NAME  Clear a session's history.
  -d, --delete-session NAME Delete a session file completely.

Other:
  -h, --help              Show this help message.

Examples:
  # Basic query (uses default 'flash' model)
  gemini "What is the capital of synergy?"

  # Use the more powerful 'pro' model
  gemini -p "Analyze the time complexity of this algorithm..."

  # Ask about a file
  gemini -f ./src/main.py "Find potential bugs in this Python code."

  # Use a named session to continue a conversation
  gemini -s 'project-alpha' "What were the key points from our last discussion?"

  # List all your conversations
  gemini --list-sessions
EOF
    }

    # --- Argument Parsing ---
    local short_opts="q:f:m:s:prnhc:d:"
    local long_opts="query:,file:,model:,session:,pro,flash,reset,new,help,list-sessions,clear-session:,delete-session:"
    
    local parsed_args
    if ! parsed_args=$(getopt -o "$short_opts" -l "$long_opts" -n "gemini" -- "$@"); then
        echo "Error: Invalid arguments. Use -h or --help for usage." >&2
        return 1
    fi
    eval set -- "$parsed_args"

    # Initialize variables
    local query=""
    local model=""
    local session="default"
    local reset=false
    local files=()
    local list_sessions=false
    local clear_session=""
    local delete_session=""
    
    local model_option_count=0

    while true; do
        case "$1" in
            -q|--query) query="$2"; shift 2 ;;
            -f|--file) files+=("$2"); shift 2 ;;
            -s|--session) session="$2"; shift 2 ;;
            -m|--model) model="$2"; ((model_option_count++)); shift 2 ;;
            -p|--pro) model="gemini-1.5-pro-latest"; ((model_option_count++)); shift ;;
            --flash) model="gemini-1.5-flash-latest"; ((model_option_count++)); shift ;;
            -r|-n|--reset|--new) reset=true; shift ;;
            --list-sessions) list_sessions=true; shift ;;
            -c|--clear-session) clear_session="$2"; shift 2 ;;
            -d|--delete-session) delete_session="$2"; shift 2 ;;
            -h|--help) _gemini_usage; return 0 ;;
            --) shift; break ;;
            *) echo "Internal error parsing arguments!" >&2; return 1 ;;
        esac
    done

    # Handle query passed as the last argument
    if [[ -z "$query" && $# -gt 0 ]]; then
        query="$*"
    elif [[ -n "$query" && $# -gt 0 ]]; then
        echo "Error: Query was provided with -q and as a trailing argument. Please use only one method." >&2
        return 1
    fi

    # --- Validate Arguments ---
    if (( model_option_count > 1 )); then
        echo "Error: Conflicting model options. Please specify only one of: -p, --pro, --flash, or -m." >&2
        return 1
    fi
    local management_ops=0
    [[ "$list_sessions" == "true" ]] && ((management_ops++))
    [[ -n "$clear_session" ]] && ((management_ops++))
    [[ -n "$delete_session" ]] && ((management_ops++))

    if (( management_ops > 1 )); then
        echo "Error: --list-sessions, --clear-session, and --delete-session are mutually exclusive." >&2
        return 1
    fi
    if (( management_ops > 0 )) && [[ -n "$query" ]]; then
        echo "Error: Cannot combine a query with a management operation." >&2
        return 1
    fi

    # --- Build and Execute Command ---
    local cmd=(python3 "$GEMINI_SCRIPT")

    # Handle management commands
    if [[ "$list_sessions" == "true" ]]; then
        cmd+=(--list-sessions)
    elif [[ -n "$clear_session" ]]; then
        cmd+=(--clear-session "$clear_session")
    elif [[ -n "$delete_session" ]]; then
        cmd+=(--delete-session "$delete_session")
    # Handle query command
    elif [[ -n "$query" ]]; then
        cmd+=("$query")
        [[ -n "$model" ]] && cmd+=(--model "$model")
        [[ "$session" != "default" ]] && cmd+=(--session "$session")
        [[ "$reset" == "true" ]] && cmd+=(--reset)
        for file in "${files[@]}"; do
            cmd+=(--file "$file")
        done
    else
        _gemini_usage
        return 1
    fi
    
    # Final check for API key before execution
    if [[ -z "$GEMINI_API_KEY" ]]; then
        echo "Error: GEMINI_API_KEY environment variable is not set." >&2
        echo "Please add it to your shell profile (e.g., ~/.bashrc):" >&2
        echo "  export GEMINI_API_KEY='your-api-key-here'" >&2
        return 1
    fi

    # Execute the Python script
    "${cmd[@]}"
}

# Optional: Create a shorter alias 'g' for the 'gemini' function.
alias g='gemini'
