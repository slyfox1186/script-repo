#!/usr/bin/env python3
"""
Enhanced Gemini query script with conversation memory.
"""

import os
import sys
import json
import argparse
from pathlib import Path
from google import genai

# Configuration
MAX_FILE_SIZE_BYTES = 1_000_000  # 1MB limit per file


def get_config_dir():
    """Get the configuration directory for storing session files."""
    config_dir = Path.home() / ".config" / "gemini-quick-call"
    config_dir.mkdir(parents=True, exist_ok=True)
    return config_dir


def get_session_path(session_name="default"):
    """Get the path to a specific session file."""
    # Sanitize session name to be a valid filename
    safe_session_name = "".join(c for c in session_name if c.isalnum() or c in ('-', '_')).rstrip()
    if not safe_session_name:
        safe_session_name = "default"
    return get_config_dir() / f"{safe_session_name}.json"


def list_sessions():
    """List all available session files."""
    config_dir = get_config_dir()
    sessions = []
    for file_path in config_dir.glob("*.json"):
        sessions.append(file_path.stem)
    return sorted(sessions)


def load_history(session_path, reset=False):
    """Load conversation history from a session file."""
    if reset or not session_path.exists():
        return []
    
    try:
        with open(session_path, 'r') as f:
            data = json.load(f)
            return data.get("history", [])
    except (json.JSONDecodeError, IOError) as e:
        print(f"Warning: Could not read history from {session_path}. Starting fresh.")
        print(f"Error details: {e}", file=sys.stderr)
        return []


def save_history(session_path, history):
    """Save conversation history to a session file."""
    # Limit history to last 40 messages (20 exchanges) to avoid token limits
    if len(history) > 40:
        history = history[-40:]
    
    try:
        with open(session_path, 'w') as f:
            json.dump({"history": history}, f, indent=2)
    except IOError as e:
        print(f"Warning: Could not save history to {session_path}")
        print(f"Error details: {e}", file=sys.stderr)


def clear_session(session_name):
    """Clear a specific session file."""
    session_path = get_session_path(session_name)
    if session_path.exists():
        try:
            session_path.unlink()
            print(f"Cleared session: {session_name}")
        except OSError as e:
            print(f"Error clearing session {session_name}: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        print(f"Session not found: {session_name}")


def get_language_hint(file_path):
    """Get language hint for markdown code blocks based on file extension."""
    extension_map = {
        '.py': 'python',
        '.js': 'javascript',
        '.ts': 'typescript',
        '.jsx': 'jsx',
        '.tsx': 'tsx',
        '.html': 'html',
        '.css': 'css',
        '.scss': 'scss',
        '.sass': 'sass',
        '.java': 'java',
        '.cpp': 'cpp',
        '.c': 'c',
        '.h': 'c',
        '.hpp': 'cpp',
        '.cs': 'csharp',
        '.php': 'php',
        '.rb': 'ruby',
        '.go': 'go',
        '.rs': 'rust',
        '.sh': 'bash',
        '.bash': 'bash',
        '.zsh': 'zsh',
        '.fish': 'fish',
        '.ps1': 'powershell',
        '.sql': 'sql',
        '.json': 'json',
        '.xml': 'xml',
        '.yaml': 'yaml',
        '.yml': 'yaml',
        '.toml': 'toml',
        '.ini': 'ini',
        '.cfg': 'ini',
        '.conf': 'conf',
        '.md': 'markdown',
        '.txt': 'text',
        '.log': 'text',
        '.dockerfile': 'dockerfile',
        '.gitignore': 'gitignore',
        '.env': 'bash'
    }
    
    suffix = Path(file_path).suffix.lower()
    return extension_map.get(suffix, 'text')


def read_and_validate_file(file_path_str):
    """
    Reads a file, validating its size and content type.
    Returns file content as a string, or None if validation fails.
    """
    try:
        # Security: Resolve the path to prevent traversal attacks
        # and handle user-provided paths like `~/...`
        path = Path(file_path_str).expanduser().resolve(strict=True)
        
        # Validation 1: File size
        if path.stat().st_size > MAX_FILE_SIZE_BYTES:
            print(f"⚠️  Warning: Skipping '{file_path_str}' (>{MAX_FILE_SIZE_BYTES / 1e6:.1f}MB).")
            return None
        
        # Validation 2: Binary content
        # We read bytes first, then try to decode.
        with open(path, 'rb') as f:
            content_bytes = f.read()
        try:
            return content_bytes.decode('utf-8')
        except UnicodeDecodeError:
            print(f"⚠️  Warning: Skipping binary file '{file_path_str}'.")
            return None
    
    except FileNotFoundError:
        print(f"❌ Error: File not found at '{file_path_str}'.")
        return None
    except PermissionError:
        print(f"❌ Error: Permission denied for '{file_path_str}'.")
        return None
    except Exception as e:
        print(f"❌ Error: An unexpected error occurred with '{file_path_str}': {e}")
        return None


def create_file_context(file_paths):
    """Create formatted context from multiple files for Gemini."""
    if not file_paths:
        return ""
    
    file_contents = []
    for path in file_paths:
        content = read_and_validate_file(path)
        if content:
            language_hint = get_language_hint(path)
            file_contents.append(
f"""---
File: `{path}`
---
```{language_hint}
{content}
```""")
    
    if not file_contents:
        return ""
    
    # Add a preamble
    preamble = "Please use the following file(s) as context for your response:\n\n"
    return preamble + "\n\n".join(file_contents)


def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description='Query Gemini API with conversation memory')
    
    # Query argument (optional for list/clear operations)
    parser.add_argument('query', nargs='?', help='The query to send to Gemini')
    
    # API and model options
    parser.add_argument('--api-key',
                        help='Gemini API key (or set GEMINI_API_KEY env var)')
    parser.add_argument('--model',
                        default='gemini-2.5-flash-preview-05-20',
                        help='Model to use (default: gemini-2.5-flash-preview-05-20)')
    
    # Session management options
    parser.add_argument('--session', '-s',
                        default='default',
                        help='Session name for conversation history (default: default)')
    parser.add_argument('--reset', '-r',
                        action='store_true',
                        help='Start a fresh conversation (ignores history for this call)')
    parser.add_argument('--new', '-n',
                        action='store_true',
                        help='Alias for --reset')
    parser.add_argument('--list-sessions',
                        action='store_true',
                        help='List all available sessions')
    parser.add_argument('--clear-session',
                        nargs='?',
                        const='default',
                        help='Clear a session (default: current session)')
    
    # File input options
    parser.add_argument('-f', '--file',
                        action='append',
                        help='Path to a file to include in the prompt. Can be specified multiple times.')
    
    args = parser.parse_args()
    
    # Handle list sessions
    if args.list_sessions:
        sessions = list_sessions()
        if sessions:
            print("Available sessions:")
            for session in sessions:
                print(f"  - {session}")
        else:
            print("No sessions found.")
        return
    
    # Handle clear session
    if args.clear_session is not None:
        session_to_clear = args.clear_session
        clear_session(session_to_clear)
        return
    
    # Check if query was provided for normal operation
    if not args.query:
        print("Error: Query is required (unless using --list-sessions or --clear-session)")
        parser.print_help()
        sys.exit(1)
    
    # Get API key from args or environment
    api_key = args.api_key or os.environ.get('GEMINI_API_KEY')
    if not api_key:
        print("Error: No API key provided. Set GEMINI_API_KEY environment "
              "variable or use --api-key")
        sys.exit(1)
    
    try:
        # Initialize client
        client = genai.Client(api_key=api_key)
        
        # Load conversation history
        session_path = get_session_path(args.session)
        reset = args.reset or args.new
        history = load_history(session_path, reset)
        
        # Create chat session with history
        chat = client.chats.create(
            model=args.model,
            history=history
        )
        
        # Prepare the message with file context if provided
        file_context = create_file_context(args.file or [])
        
        # Construct the final prompt
        if file_context:
            final_prompt = f"{file_context}\n\n---\n\nUser Query: {args.query}"
        else:
            final_prompt = args.query
        
        # Send the new message
        response = chat.send_message(final_prompt)
        
        # Print the response
        print(response.text)
        
        # Update history with the new exchange (use original query, not file context)
        history.append({
            "role": "user",
            "parts": [{"text": args.query}]
        })
        history.append({
            "role": "model", 
            "parts": [{"text": response.text}]
        })
        
        # Save updated history
        if not reset:
            save_history(session_path, history)
    
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
