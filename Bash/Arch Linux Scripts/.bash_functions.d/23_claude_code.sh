#!/usr/bin/env bash
# Enhanced Gemini quick query function with memory support and robust argument parsing
# Add this to your ~/.bash_functions.d/ directory

claude_code_search() {
  # --- Pre-flight Checks ---

  # Check if package.json exists
  if [ ! -f "package.json" ]; then
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
  if [ -n "$search_pattern" ]; then
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

