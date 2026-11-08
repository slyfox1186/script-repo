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
    # 24-bit RGB values, so the terminal theme's palette cannot change these colors.
    local env_gray='\[\e[38;2;167;167;167m\]'
    local path_yellow='\[\e[38;2;255;255;95m\]'
    local user_orange='\[\e[38;2;255;175;95m\]'
    local at_lilac='\[\e[38;2;215;175;255m\]'
    local host_blue='\[\e[38;2;135;215;255m\]'
    local dollar_white='\[\e[38;2;255;255;255m\]'

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

    PS1="${env_gray}"'${__prompt_venv}'"${path_yellow}\w${reset}${exit_info}\n${user_orange}\u${at_lilac}@${host_blue}\h${reset} ${dollar_white}\$${reset} "
}

PROMPT_COMMAND=__prompt_command
