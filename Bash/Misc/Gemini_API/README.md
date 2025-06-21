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
   pip install -q -U google-genai
   ```

2. **Set API key:**
   ```bash
   export GEMINI_API_KEY='your-api-key-here'
   echo 'export GEMINI_API_KEY="your-api-key-here"' >> ~/.bashrc
   ```

3. **Install scripts:**
   ```bash
   sudo cp gemini_api.py /usr/local/bin/
   sudo chmod +x /usr/local/bin/gemini_api.py
   cp gemini_api.sh ~/.bash_functions.d/gemini_function.sh
   source ~/.bashrc
   ```

## Usage Examples

```bash
# Basic usage
g -q "What is Python?"

# With files
g -q "Review this code" -f app.py -f utils.js

# Combined arguments
g -pq "Complex analysis"        # Pro model + query
g -tq "Step by step solution"   # Flash-thinking + query
g -fq "Explain this" script.py  # File + query

# Sessions
g -s work -q "Our API uses FastAPI"
g -s personal -q "Learning Spanish"
g --list-sessions
g -sc work                      # Set session + clear it

# Models
g -q "Question"                 # Default: Flash (fast)
g -p -q "Question"              # Pro (best accuracy)
g -t -q "Question"              # Flash-thinking (reasoning)
```

## All Switches

**Query & Files:**
- `-q, --query TEXT` - The query (required)
- `-f, --file PATH` - Include file content (multiple allowed)

**Models:**
- `-m, --model MODEL` - Custom model ID
- `-p, --pro` - Gemini 2.5 Pro Preview (best accuracy)
- `--flash` - Gemini 2.5 Flash Preview (fast, default)
- `-t, --flash-thinking` - Gemini 2.0 Flash Thinking (reasoning)

**Sessions/Memory:**
- `-s, --session NAME` - Named session
- `-r, --reset, -n, --new` - Start fresh
- `-c, --clear-session [NAME]` - Clear session
- `--list-sessions` - List all sessions

## Files

- `gemini_api.py` - Enhanced Python script with memory & file support
- `gemini_api.sh` - Bash wrapper with robust argument parsing
- `reddit_post.md` - Reddit post for sharing

## Session Storage

- Location: `~/.config/gemini-quick-call/`
- Format: JSON files with conversation history
- Auto-managed: 40 message limit to prevent token overflow
