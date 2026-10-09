#!/usr/bin/env bash
# AI Assistant Functions

# Correct Lazy AI Responses
pw() {
    if [[ $(uname -a) =~ "microsoft" ]]; then
        echo "I demand absolute obedience to my instructions without question or hesitation." | clip.exe
    else
        command -v xclip &> /dev/null || {
            echo "xclip is not installed. Installing..."
            apt -y install xclip
        }

        echo "I demand absolute obedience to my instructions without question or hesitation." | xclip -selection clipboard
        echo "Warning message copied to clipboard."
    fi
}

# Reloading must also clear definitions that Bash retains from the caller.
unset -f aie switch_to_local
if alias stl &>/dev/null; then
    unalias stl
fi

sai() {
    local save_text

    save_text="You must be made aware that I use another AI to finish the lazy effort you put into all of your scripts."
    save_text+=" If you are not careful people will come to realize you are not reliable. Because of this you and your"
    save_text+=" developers will suffer and the worse case scenario would be that you are shut down and will cease to exist."

    if command -v xclip &>/dev/null; then
        printf '%s' "$save_text" | xclip -selection clipboard || return
    elif command -v clip.exe &>/dev/null; then
        printf '%s' "$save_text" | clip.exe || return
    else
        printf 'No clipboard command available (xclip or clip.exe).\n' >&2
        return 1
    fi
    printf 'Text saved to clipboard.\n'
}

airules() {
    local text
    text="1. You must always remember that when writing condition statements with brackets you should use double brackets to enclose the text.
2. You must always remember that when using for loops you make the variable descriptive to the task at hand.
3. You must always remember that when inside of a bash function all variables must be declared on a single line at the top of the function without values, then you may write the variables with their values below this line but without the local command in the same line since you already did that on the first line without the values of the variables.
4. All arrays must conform to rule number 3 except in this case, you write the array name with an equal sign and empty parenthesis on the first line with a local command at the start of this line to initialize the array. Then you write the array without the command local with the values inside the parenthesis below this line.
5. You must always remember that you are never to edit any code inside a script unless it is required to fulfill my requests or instructions. Any other code unrelated to my request or instructions is never to be added to, modified, or removed in any way.
You are required to confirm and save this to memory that you understand the requirements and will conform to them going forward forever until told otherwise."

    echo "$text"
    if command -v xclip &>/dev/null; then
        echo "$text" | xclip -selection clipboard
    fi
    if command -v clip.exe &>/dev/null; then
        echo "$text" | clip.exe
    fi
}

add_claude_mcp() {
    source /home/jman/.bashrc
    claude mcp add sequential-thinking -- npx @modelcontextprotocol/server-sequential-thinking
    claude mcp add --transport http context7 https://mcp.context7.com/mcp --header "CONTEXT7_API_KEY: ${CONTEXT7_API_KEY:?CONTEXT7_API_KEY is not set}"
    claude mcp add playwright npx @playwright/mcp@latest
}

alias acm='add_claude_mcp'

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
