#!/usr/bin/env bash
# Enhanced Gemini quick query function with memory support and robust argument parsing
# Add this to your ~/.bash_functions.d/ directory

claude_code_search() {
  # --- Pre-flight Checks ---

  # Check if package.json exists
  if [[ ! -f "package.json" ]]; then
    echo "Error: package.json not found in the current directory." >&2
    return 1
  fi

  # Check if the 'type-check' script is defined in package.json
  if ! grep -q '"type-check":' "package.json"; then
    echo "Error: A 'type-check' script is not defined in your package.json." >&2
    return 1
  fi

  # --- Command Execution ---

  # Store the search pattern provided by the user ($1)
  local search_pattern="$1"

  # Announce the action
  echo "Running TypeScript type check..."
  echo "--------------------------------"

  # Execute the type-check, redirecting stderr to stdout (2>&1)
  # Then, pipe to 'tr' to squeeze (remove) consecutive newlines.
  local output
  output=$(npm run type-check --silent 2>&1 | tr -s '\n')

  # --- Output Filtering ---

  # Check if a search pattern was provided
  if [[ -n "$search_pattern" ]]; then
    # If yes, filter the output with grep, using the provided pattern.
    # The '--color=auto' flag adds color to the matched text.
    echo "Filtering for lines containing: '$search_pattern'"
    echo "--------------------------------"
    echo "$output" | grep --color=auto -E "$search_pattern"
  else
    # If no, simply print the cleaned output.
    echo "$output"
  fi

  # Return the exit code of the grep command if used, or 0 otherwise
  return $?
}

alias ccs='claude_code_search'

# Choose a provider switcher, then enter its arguments with shell-style quoting.
switch_provider() {
  local choice script arguments
  local provider_python='/home/jman/miniconda3/bin/python'

  printf '1) Codex\n2) Claude Code\nq) Cancel\n\n'
  while true; do
    IFS= read -r -p 'Input: ' choice || {
      printf '\nCancelled.\n'
      return 1
    }
    case "$choice" in
      1) script="$HOME/.codex/switch_provider_codex.py"; break ;;
      2) script="$HOME/.claude/switch_provider_claude.py"; break ;;
      q|Q) printf 'Cancelled.\n'; return 0 ;;
      *) printf 'Please choose 1, 2, or q.\n' ;;
    esac
  done

  if [[ -t 1 ]]; then
    clear || :
  fi

  if [[ ! -x "$provider_python" || ! -f "$script" || ! -r "$script" ]]; then
    printf 'Cannot run switcher: check %s and %s.\n' "$provider_python" "$script" >&2
    return 1
  fi

  case "$choice" in
    1) printf '\nCODEX\n-----\n\n--openai      Use OpenAI\n' ;;
    2) printf '\nCLAUDE CODE\n-----------\n\n--claude      Use Anthropic\n' ;;
  esac
  printf '%s\n' '--glm         Use Z.ai GLM'
  printf '%s\n' '--status      Show current provider'
  printf '%s\n' '--set-key     Enter your Z.ai API key'
  printf '%s\n' '--help        Show all options'
  printf '\nEXAMPLES\n\n'
  printf '%-22s%s\n' '--glm --effort high' 'Switch to GLM with high effort'
  printf '%-22s%s\n' '--set-key' 'Enter API key in a hidden prompt'
  printf '\nType arguments below, or press Enter to cancel.\n\n'
  IFS= read -e -r -p 'Arguments > ' arguments || {
    printf '\nCancelled.\n'
    return 1
  }

  # shlex preserves quoted arguments without eval, globbing, or command expansion.
  # exec retains stdin for the switcher's own prompts and propagates its exit code.
  "$provider_python" -c '
import os
import shlex
import sys

try:
    arguments = shlex.split(sys.argv[2])
except ValueError as error:
    print(f"Invalid argument quoting: {error}", file=sys.stderr)
    sys.exit(2)
if not arguments:
    print("Cancelled.")
    sys.exit(0)
os.execv(sys.executable, [sys.executable, sys.argv[1], *arguments])
' "$script" "$arguments"
}
