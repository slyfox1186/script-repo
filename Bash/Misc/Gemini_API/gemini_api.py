#!/usr/bin/env python3
"""
Optimized and enhanced Gemini query script with robust conversation memory,
file locking, and improved error handling.
"""

import os
import sys
import json
import argparse
import errno
import time
import signal
import atexit
from pathlib import Path
from typing import List, Dict, Any, Optional, NoReturn

# --- Pre-flight Checks ---
if sys.version_info < (3, 8):
    print("Error: Python 3.8 or higher is required for this script.", file=sys.stderr)
    sys.exit(1)

try:
    import fcntl
    HAS_FCNTL = True
except ImportError:
    HAS_FCNTL = False  # Platform is likely Windows

try:
    import google.generativeai as genai
    from google.api_core import exceptions as google_exceptions
except ImportError:
    print("Error: The 'google-generativeai' package is not installed.", file=sys.stderr)
    print("Please install it with: pip install -q -U google-generativeai", file=sys.stderr)
    sys.exit(1)

# --- Configuration ---
MAX_FILE_SIZE_BYTES = 2_000_000   # 2MB limit per file
MAX_TOTAL_FILE_SIZE = 10_000_000  # 10MB total limit for all files
LOCK_TIMEOUT = 10                 # Seconds to wait for a file lock
API_TIMEOUT = int(os.environ.get("GEMINI_TIMEOUT", 90)) # Seconds for API response

# --- Global State ---
_cleanup_handlers: List[callable] = []
_config_dir_checked: bool = False


def _cleanup_handler(signum: Optional[int] = None, frame: Optional[Any] = None) -> None:
    """Universal cleanup handler for signals and atexit."""
    for handler in reversed(_cleanup_handlers):
        try:
            handler()
        except Exception as e:
            # Non-critical, but useful for debugging
            # print(f"Debug: Error in cleanup handler: {e}", file=sys.stderr)
            pass
    if signum:
        # Exit with error code on signal interruption
        sys.exit(128 + signum)


class FileLock:
    """
    A robust, cross-platform file locking context manager.
    Uses fcntl on Unix and a time-based stale lock check on Windows.
    """
    def __init__(self, file_path: Path, timeout: int = LOCK_TIMEOUT):
        self.lock_file = file_path.with_suffix(f"{file_path.suffix}.lock")
        self.timeout = timeout
        self.lock_fd = None

    def _acquire_unix_lock(self) -> None:
        """Acquire lock using fcntl."""
        start_time = time.monotonic()
        while time.monotonic() - start_time < self.timeout:
            try:
                self.lock_fd = self.lock_file.open('w')
                fcntl.flock(self.lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                _cleanup_handlers.append(self._release_lock)
                return
            except (IOError, OSError):
                if self.lock_fd:
                    self.lock_fd.close()
                time.sleep(0.1)
        raise TimeoutError(f"Could not acquire lock on {self.lock_file} after {self.timeout}s.")

    def _acquire_windows_lock(self) -> None:
        """Acquire lock using atomic file creation (O_CREAT|O_EXCL)."""
        start_time = time.monotonic()
        while time.monotonic() - start_time < self.timeout:
            try:
                # 'x' mode is atomic create-and-open
                self.lock_fd = self.lock_file.open('x')
                _cleanup_handlers.append(self._release_lock)
                return
            except FileExistsError:
                # Lock file exists, check if it's stale
                try:
                    if self.lock_file.stat().st_mtime < time.time() - self.timeout:
                        self.lock_file.unlink() # Stale lock, remove it
                        continue # Retry immediately
                except FileNotFoundError:
                    continue # Race condition: another process removed it
                except OSError as e:
                    raise IOError(f"Failed to check or remove stale lock: {e}") from e
                time.sleep(0.1)
        raise TimeoutError(f"Could not acquire lock on {self.lock_file} after {self.timeout}s.")

    def _release_lock(self) -> None:
        """Release the acquired lock."""
        if self.lock_fd:
            if HAS_FCNTL:
                fcntl.flock(self.lock_fd, fcntl.LOCK_UN)
            self.lock_fd.close()
            self.lock_fd = None
        try:
            # Best-effort removal of the lock file
            self.lock_file.unlink(missing_ok=True)
        except OSError:
            pass

    def __enter__(self) -> 'FileLock':
        if HAS_FCNTL:
            self._acquire_unix_lock()
        else:
            self._acquire_windows_lock()
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self._release_lock()


def get_config_dir() -> Path:
    """Get or create the configuration directory for storing session files."""
    global _config_dir_checked
    try:
        config_dir = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "gemini-cli"
    except (RuntimeError, KeyError):
        print("Error: Could not determine home directory.", file=sys.stderr)
        sys.exit(1)
        
    if not _config_dir_checked:
        try:
            config_dir.mkdir(parents=True, exist_ok=True)
        except (PermissionError, OSError) as e:
            print(f"Error: Cannot create config directory at '{config_dir}': {e}", file=sys.stderr)
            sys.exit(1)
        _config_dir_checked = True
    return config_dir


def get_session_path(session_name: str = "default", warn_sanitized: bool = False) -> Path:
    """Get the sanitized path to a specific session file."""
    original_name = session_name
    safe_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    safe_session_name = "".join(c for c in session_name if c in safe_chars).strip()
    
    if len(safe_session_name) > 64:
        safe_session_name = safe_session_name[:64]
    
    if not safe_session_name:
        safe_session_name = "default"
        if warn_sanitized and original_name != "default":
            print(f"Warning: Session name '{original_name}' sanitized to 'default'.", file=sys.stderr)
            
    if warn_sanitized and original_name != safe_session_name:
        print(f"Warning: Session name '{original_name}' sanitized to '{safe_session_name}'.", file=sys.stderr)
        
    return get_config_dir() / f"{safe_session_name}.json"


def list_sessions() -> None:
    """List all available and valid session files."""
    config_dir = get_config_dir()
    sessions, corrupted = [], []
    
    for file_path in config_dir.glob("*.json"):
        try:
            with file_path.open('r', encoding='utf-8') as f:
                data = json.load(f)
                if isinstance(data, dict) and isinstance(data.get("history"), list):
                    sessions.append(file_path.stem)
                else:
                    corrupted.append(file_path.stem)
        except (json.JSONDecodeError, IOError):
            corrupted.append(file_path.stem)

    if sessions:
        print("Available sessions:")
        for session in sorted(sessions):
            print(f"  - {session}")
    else:
        print("No sessions found.")

    if corrupted:
        print(f"\nWarning: Found {len(corrupted)} corrupted session file(s):")
        for name in sorted(corrupted):
            print(f"  - {name} (corrupted)")


def load_history(session_path: Path, reset: bool) -> List[Dict[str, Any]]:
    """Load conversation history, handling potential corruption or large files."""
    if reset or not session_path.exists():
        return []
    
    try:
        with FileLock(session_path):
            with session_path.open('r', encoding='utf-8') as f:
                data = json.load(f)
            history = data.get("history", [])
            if not isinstance(history, list):
                raise json.JSONDecodeError("History is not a list", "", 0)
            return history
    except TimeoutError:
        print("Warning: Session file is locked. Starting with empty history.", file=sys.stderr)
    except (json.JSONDecodeError, IOError) as e:
        print(f"Warning: Could not read/parse history from {session_path}. Starting fresh.", file=sys.stderr)
        print(f"         Error details: {e}", file=sys.stderr)
    return []


def save_history(session_path: Path, history: List[Dict[str, Any]]) -> None:
    """Save conversation history atomically to a session file."""
    # Trim history to prevent it from growing indefinitely
    if len(history) > 50: # Keep last 25 exchanges
        history = history[-50:]

    temp_path = session_path.with_suffix('.json.tmp')
    try:
        with FileLock(session_path):
            with temp_path.open('w', encoding='utf-8') as f:
                json.dump({"history": history}, f, indent=2)
            temp_path.replace(session_path)
    except TimeoutError:
        print("Warning: Session locked. History not saved.", file=sys.stderr)
    except IOError as e:
        print(f"Warning: Could not save history: {e}", file=sys.stderr)
    finally:
        # Ensure temp file is removed on failure
        temp_path.unlink(missing_ok=True)


def clear_session(session_name: str) -> None:
    """Clear a session's history by overwriting it with an empty history."""
    session_path = get_session_path(session_name, warn_sanitized=True)
    if not session_path.exists():
        print(f"Session not found: {session_name}")
        return

    try:
        save_history(session_path, [])
        print(f"Cleared history for session: {session_name}")
    except Exception as e:
        print(f"Error: Could not clear session '{session_name}': {e}", file=sys.stderr)
        sys.exit(1)


def delete_session(session_name: str) -> None:
    """Delete a session file completely after performing security checks."""
    session_path = get_session_path(session_name, warn_sanitized=True)
    if not session_path.exists():
        print(f"Session not found: {session_name}")
        return

    try:
        # Security: ensure we are deleting a file inside our config directory
        config_dir = get_config_dir().resolve()
        resolved_path = session_path.resolve()
        if config_dir not in resolved_path.parents:
            print(f"Error: Refusing to delete session '{session_name}' outside config directory for security.", file=sys.stderr)
            sys.exit(1)

        with FileLock(session_path):
            session_path.unlink()
        print(f"Deleted session: {session_name}")
    except (PermissionError, OSError, TimeoutError) as e:
        print(f"Error deleting session '{session_name}': {e}", file=sys.stderr)
        sys.exit(1)


def get_language_hint(file_path: Path) -> str:
    """Get language hint for markdown code blocks based on file extension."""
    suffix = file_path.suffix.lower()
    return {
        '.py': 'python', '.js': 'javascript', '.ts': 'typescript', '.java': 'java',
        '.cpp': 'cpp', '.c': 'c', '.h': 'c', '.cs': 'csharp', '.go': 'go',
        '.rs': 'rust', '.rb': 'ruby', '.php': 'php', '.sh': 'bash', '.ps1': 'powershell',
        '.html': 'html', '.css': 'css', '.scss': 'scss', '.sql': 'sql', '.json': 'json',
        '.xml': 'xml', '.yaml': 'yaml', '.yml': 'yaml', '.toml': 'toml', '.md': 'markdown',
        '.dockerfile': 'dockerfile'
    }.get(suffix, 'text')


def create_file_context(file_paths: Optional[List[str]]) -> str:
    """Create formatted context from multiple files, validating size and content."""
    if not file_paths:
        return ""
    
    file_contents, included_files, skipped_files = [], [], []
    total_size = 0
    
    for path_str in file_paths:
        try:
            path = Path(path_str).expanduser().resolve(strict=True)
            
            if path.stat().st_size > MAX_FILE_SIZE_BYTES:
                skipped_files.append(f"{path_str} (too large)")
                continue
            
            content_bytes = path.read_bytes()
            content = content_bytes.decode('utf-8')
            content_size = len(content_bytes)
            
            if total_size + content_size > MAX_TOTAL_FILE_SIZE:
                skipped_files.append(f"{path_str} (total size limit exceeded)")
                continue

            total_size += content_size
            included_files.append(path_str)
            lang = get_language_hint(path)
            file_contents.append(f"---\nFile: `{path_str}`\n---\n```{lang}\n{content}\n```")

        except UnicodeDecodeError:
            skipped_files.append(f"{path_str} (binary file)")
        except (FileNotFoundError, PermissionError, OSError) as e:
            skipped_files.append(f"{path_str} ({e.__class__.__name__})")

    if included_files:
        print(f"✓ Included {len(included_files)} file(s): {', '.join(included_files)}")
    if skipped_files:
        print(f"⚠️  Skipped {len(skipped_files)} file(s): {', '.join(skipped_files)}")

    if not file_contents:
        return ""
        
    preamble = "Please use the following file(s) as context for your response:\n\n"
    return preamble + "\n\n".join(file_contents)


def exit_with_error(message: str, code: int = 1) -> NoReturn:
    """Print an error message to stderr and exit."""
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(code)


def main() -> None:
    """Main execution function."""
    parser = argparse.ArgumentParser(
        description='Query the Gemini API with conversation memory and file context.',
        epilog='Set GEMINI_API_KEY environment variable. Use -h for more details.'
    )
    parser.add_argument('query', nargs='?', help='The query to send to Gemini.')
    parser.add_argument('--model', default='gemini-1.5-flash-latest', help='Model to use (default: gemini-1.5-flash-latest).')
    parser.add_argument('--session', '-s', default='default', help='Session name for conversation history.')
    parser.add_argument('--reset', '-r', '--new', '-n', action='store_true', help='Ignore history for this call.')
    parser.add_argument('--list-sessions', action='store_true', help='List all available sessions.')
    parser.add_argument('--clear-session', '-c', metavar='SESSION', help='Clear a session\'s history.')
    parser.add_argument('--delete-session', '-d', metavar='SESSION', help='Delete a session file completely.')
    parser.add_argument('-f', '--file', action='append', help='Path to a file to include (can be used multiple times).')
    
    args = parser.parse_args()
    
    # --- Handle non-query operations ---
    if args.list_sessions:
        list_sessions()
        return
    if args.clear_session:
        clear_session(args.clear_session)
        return
    if args.delete_session:
        delete_session(args.delete_session)
        return
        
    if not args.query:
        parser.print_help()
        exit_with_error("Query is required for this operation.")

    # --- Setup for query operation ---
    if not os.environ.get('GEMINI_API_KEY'):
        exit_with_error("GEMINI_API_KEY environment variable is not set.")

    signal.signal(signal.SIGINT, _cleanup_handler)
    signal.signal(signal.SIGTERM, _cleanup_handler)
    atexit.register(_cleanup_handler)

    try:
        genai.configure(api_key=os.environ['GEMINI_API_KEY'])
        session_path = get_session_path(args.session)
        history = load_history(session_path, args.reset)
        
        model = genai.GenerativeModel(args.model, system_instruction=[
            "You are a helpful and concise assistant running in a command-line interface.",
            "Format your responses using Markdown for terminal readability.",
            "For code, always use Markdown code blocks with the correct language identifier."
        ])
        chat = model.start_chat(history=history)

        file_context = create_file_context(args.file)
        if args.file and not file_context:
            exit_with_error("No files could be read successfully. Aborting.")
        
        final_prompt = f"{file_context}\n\n{args.query}" if file_context else args.query
        
        response = chat.send_message(final_prompt, request_options={'timeout': API_TIMEOUT})
        
        print(response.text)

        # Update and save history if not a reset call
        if not args.reset:
            # We use the full chat history which is automatically updated
            save_history(session_path, chat.history)

    except google_exceptions.DeadlineExceeded:
        exit_with_error(f"API request timed out after {API_TIMEOUT} seconds.")
    except google_exceptions.PermissionDenied as e:
        exit_with_error(f"API Permission Denied. Check your API key and permissions. Details: {e}")
    except google_exceptions.ResourceExhausted as e:
        exit_with_error(f"API quota exceeded. Please check your billing or usage limits. Details: {e}")
    except Exception as e:
        exit_with_error(f"An unexpected error occurred: {e}")


if __name__ == "__main__":
    main()
