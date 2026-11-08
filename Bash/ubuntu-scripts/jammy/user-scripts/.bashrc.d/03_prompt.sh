#!/bin/bash
# Prompt settings and appearance

# Prompt: "(env) path [exit code]" on line 1, "user@host $ " on line 2.
# __prompt_command draws the env name, so conda's own prefix is kept off.
CONDA_CHANGEPS1=false
export CONDA_CHANGEPS1

__prompt_command() {
    # Must stay the first statement: any command before it, even "local", resets $?.
    local exit_code=$?
    local reset='\[\e[0m\]'
    local red='\[\e[0;31m\]'
    local green='\[\e[0;32m\]'
    local yellow='\[\e[0;33m\]'
    local blue='\[\e[0;34m\]'
    local cyan='\[\e[0;36m\]'

    # The env name goes through this global rather than being pasted into PS1, so a name
    # containing "$(cmd)" is shown as text instead of being run.
    __prompt_venv=""
    if [[ -n "${CONDA_DEFAULT_ENV-}" ]]; then
        __prompt_venv="(${CONDA_DEFAULT_ENV}) "
    elif [[ -n "${VIRTUAL_ENV-}" ]]; then
        __prompt_venv="(${VIRTUAL_ENV##*/}) "
    fi

    local exit_info=""
    if (( exit_code != 0 )); then
        exit_info=" ${red}[${exit_code}]${reset}"
    fi

    PS1="${yellow}"'${__prompt_venv}'"${blue}\w${reset}${exit_info}\n${green}\u${reset}@${cyan}\h${reset} \$ "
}

PROMPT_COMMAND=__prompt_command
