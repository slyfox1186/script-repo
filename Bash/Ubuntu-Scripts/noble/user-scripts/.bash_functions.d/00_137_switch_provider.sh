#!/usr/bin/env bash

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

