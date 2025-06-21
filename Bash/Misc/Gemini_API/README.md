# Gemini Quick Call CLI with Memory

A powerful CLI tool for Gemini API with conversation memory, file input, and robust argument parsing.

## Features

- **Conversation Memory**: Persistent sessions stored locally
- **File Input**: Include multiple files in prompts with syntax highlighting
- **Combined Arguments**: Use `-pq "question"` instead of `-p -q "question"`
- **Multiple Sessions**: Organize conversations by topic/project
- **Robust Parsing**: Uses `getopt` for proper Unix-style argument handling

## Quick Setup

1. **Install Python dependencies:**
   ```bash
   pip install -q -U google-generativeai
   ```

2. **Set API key:**
   ```bash
   export GEMINI_API_KEY='your-api-key-here'
   echo 'export GEMINI_API_KEY="your-api-key-here"' >> ~/.bashrc
   ```

3. **Install scripts:**
   ```bash
   # Install the Python script
   sudo cp gemini_api.py /usr/local/bin/
   sudo chmod +x /usr/local/bin/gemini_api.py
   
   # Install the shell wrapper (choose one method):
   
   # Method 1: Add to a functions directory (if you have one)
   cp gemini_api.sh ~/.bash_functions.d/gemini_function.sh
   
   # Method 2: Add directly to your shell config
   cat gemini_api.sh >> ~/.bashrc
   
   # Method 3: Create a standalone script and source it
   cp gemini_api.sh ~/bin/gemini_function.sh
   echo 'source ~/bin/gemini_function.sh' >> ~/.bashrc
   ```

4. **Activate the shell function:**
   ```bash
   # IMPORTANT: Source your shell configuration to activate the 'g' alias
   source ~/.bashrc
   
   # Or for zsh users:
   source ~/.zshrc
   ```

## Usage Examples

```bash
# Basic usage
g "What is Python?"
g -q "What is Python?"

# With files
g -q "Review this code" -f app.py -f utils.js
g "Review this code" -f app.py -f utils.js

# Combined arguments (Note: -t is not implemented)
g -pq "Complex analysis"        # Pro model + query
g -fq "Explain this" script.py  # File + query

# Sessions
g -s work "Our API uses FastAPI"
g -s personal "Learning Spanish"
g --list-sessions
g -c work                       # Clear session
g -d work                       # Delete session

# Models
g "Question"                    # Default: Flash (fast)
g -p "Question"                 # Pro (best accuracy)
g --flash "Question"            # Flash explicitly
g -m gemini-1.5-flash-latest "Question"  # Custom model
```

## All Switches

**Query & Files:**
- `-q, --query TEXT` - The query (can also be the last argument)
- `-f, --file PATH` - Include file content (multiple allowed)

**Models:**
- `-m, --model MODEL` - Custom model ID
- `-p, --pro` - Use gemini-1.5-pro-latest (best accuracy)
- `--flash` - Use gemini-1.5-flash-latest (fast, default)

**Sessions/Memory:**
- `-s, --session NAME` - Named session (default: "default")
- `-r, --reset, -n, --new` - Start fresh (ignore history)
- `-c, --clear-session NAME` - Clear a session's history
- `-d, --delete-session NAME` - Delete a session completely
- `--list-sessions` - List all sessions

**Other:**
- `-h, --help` - Show help message

## Files

- `gemini_api.py` - Enhanced Python script with memory & file support
- `gemini_api.sh` - Bash wrapper with robust argument parsing
- `reddit_post.md` - Reddit post for sharing

## Session Storage

- Location: `~/.config/gemini-cli/`
- Format: JSON files with conversation history
- Auto-managed: 50 message limit (25 exchanges) to prevent token overflow
- File locking: Prevents corruption from concurrent access
