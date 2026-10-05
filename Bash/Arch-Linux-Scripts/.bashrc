#!/usr/bin/env bash

# ===============================================================
# Enhanced .bashrc for Arch Linux - Modular Version
# Author: slyfox1186 (https://github.com/slyfox1186/script-repo)
# ===============================================================

# If not running interactively, don't do anything
case "$-" in
    *i*) ;;
    *) return 0 ;;
esac

# Recover only when the inherited working directory no longer exists. Keep the
# caller's intended directory for every normal interactive shell.
if ! pwd -P >/dev/null 2>&1; then
    cd "$HOME" 2>/dev/null || return 0
fi

# Check if bashrc directory exists, create if not
BASHRC_DIR="$HOME/.bashrc.d"
[[ ! -d "$BASHRC_DIR" ]] && mkdir -p "$BASHRC_DIR"

# System info variables (used in modules and welcome message)
threads=$(nproc --all 2>/dev/null || echo "unknown")
cpus=$((threads / 2))
lan=$(ip route get 1.2.3.4 2>/dev/null | awk '{print $7}' || echo "unknown")
wan=$(curl --connect-timeout 1 -fsS "https://checkip.amazonaws.com" 2>/dev/null || echo "unknown")

# Export common variables for modules to use
export threads cpus lan wan

# Source all bashrc modules
for module in "$BASHRC_DIR"/*.sh; do
    if [[ -f "$module" ]]; then
        source "$module"
    fi
done

export PATH="\
$HOME/.npm-global/bin:\
/usr/lib/ccache:\
/usr/local/bin:\
/usr/local/sbin:\
/opt/cuda/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin\
"

[[ -s "$HOME/.nvm/nvm.sh" ]] && source "$HOME/.nvm/nvm.sh"
[[ -s "$HOME/.nvm/bash_completion" ]] && source "$HOME/.nvm/bash_completion"

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
if [[ -d "$PNPM_HOME" ]]; then
    case ":$PATH:" in
      *":$PNPM_HOME:"*) ;;
      *) export PATH="$PNPM_HOME:$PATH" ;;
    esac
fi
# pnpm end

# Machine-specific values (sss folders, database names) that stay out of published copies
[[ -r "$HOME/.bash_private.sh" ]] && source "$HOME/.bash_private.sh"

# Source bash functions and aliases
if [[ -d "$HOME/.bash_functions.d" ]]; then
    for f in "$HOME/.bash_functions.d"/*.sh; do
        [[ -r "$f" ]] && source "$f"
    done
fi

if [[ -d "$HOME/.bash_aliases.d" ]]; then
    for f in "$HOME/.bash_aliases.d"/*.sh; do
        [[ -r "$f" ]] && source "$f"
    done
fi


if [[ -n "$PS1" ]]; then
    echo "Welcome, $(whoami)! Terminal ready at $(date '+%H:%M:%S')"
    echo "System: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2- | tr -d '"')"
    echo "Kernel: $(uname -sr)"
    echo "CPU cores: $threads (Physical: $cpus)"
    echo -e "IP: $lan (LAN), $wan (WAN)\n"
fi

remove_path_entry() {
    local entry new_path path_part
    entry="$1"
    new_path=""

    while IFS=: read -r -d ':' path_part; do
        [[ -n "$path_part" ]] || continue
        [[ "$path_part" == "$entry" ]] && continue
        if [[ -n "$new_path" ]]; then
            new_path+=":$path_part"
        else
            new_path="$path_part"
        fi
    done < <(printf '%s:' "$PATH")

    PATH="$new_path"
}

path_prepend() {
    local entry
    entry="$1"
    [[ -n "$entry" ]] || return 0
    remove_path_entry "$entry"
    export PATH="$entry${PATH:+:$PATH}"
}

path_append() {
    local entry
    entry="$1"
    [[ -n "$entry" ]] || return 0
    remove_path_entry "$entry"
    export PATH="${PATH:+$PATH:}$entry"
}

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/jman/miniconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [[ "$?" -eq 0 ]]; then
    eval "$__conda_setup"
else
    if [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
        source "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/jman/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

### Source rustup
[[ -s "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
[[ -f "$HOME/.deno/env" ]] && . "$HOME/.deno/env"
[[ -f "$HOME/.local/share/bash-completion/completions/deno.bash" ]] && source "$HOME/.local/share/bash-completion/completions/deno.bash"
path_prepend "$HOME/.local/bin"

# ===============================================================
# Steam/Mesa Shader Cache Configuration
# ===============================================================
# Limit Mesa shader cache to 2GB to prevent excessive disk usage
export MESA_SHADER_CACHE_MAX_SIZE=2G

# ===============================================================
# Custom PS1 Prompt
# ===============================================================

__prompt_command() {
    local exit_code git_info reset red green yellow blue purple cyan gray
    exit_code="$?"

    # Colors (wrapped in \[ \] for proper cursor positioning)
    reset='\[\e[0m\]'
    red='\[\e[0;31m\]'
    green='\[\e[0;32m\]'
    yellow='\[\e[0;33m\]'
    blue='\[\e[0;34m\]'
    purple='\[\e[0;35m\]'
    cyan='\[\e[0;36m\]'
    gray='\[\e[0;90m\]'

    # Git info
    git_info=""
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        local branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
        local dirty=""
        git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null || dirty="*"
        git_info=" ${purple}(${branch}${dirty})${reset}"
    fi

    # Exit code (only show if non-zero)
    local exit_info=""
    [[ $exit_code -ne 0 ]] && exit_info=" ${red}[${exit_code}]${reset}"

    # Virtual env
    local venv=""
    if [[ -n "$CONDA_DEFAULT_ENV" ]]; then
        venv="${yellow}(${CONDA_DEFAULT_ENV})${reset} "
    elif [[ -n "$VIRTUAL_ENV" ]]; then
        venv="${yellow}($(basename "$VIRTUAL_ENV"))${reset} "
    fi

    # Build prompt
    PS1="${venv}${blue}\w${reset}${git_info}${exit_info}\n${green}\u${reset}@${cyan}\h${reset} \$ "
}

PROMPT_COMMAND=__prompt_command

# NCCL configuration for distributed vLLM (Ethernet, not InfiniBand)
export NCCL_IB_DISABLE=1
export NCCL_NET_GDR_LEVEL=0
export NCCL_P2P_DISABLE=1
export NCCL_DEBUG=WARN

# >>> build-tools golang >>>
# 2026-06-22: the manual Go at /usr/local/programs/golang-1.26.1 was gone (whole dir
# missing), so this stale GOROOT broke ALL go builds (e.g. yay). Switched to the distro
# 'go' package: its binary is in /usr/bin (already on PATH) and self-locates GOROOT in
# /usr/lib/go, so no GOROOT export is needed. To return to a pinned manual Go, reinstall
# it under /usr/local/programs and uncomment the two lines below.
#export GOROOT="/usr/local/programs/golang-1.26.1"
#path_append "$GOROOT/bin"
# <<< build-tools golang <<<

# The next line updates PATH for the Google Cloud SDK.
if [[ -f /home/jman/google-cloud-sdk/path.bash.inc ]]; then
    source /home/jman/google-cloud-sdk/path.bash.inc
fi

# The next line enables shell command completion for gcloud.
if [[ -f /home/jman/google-cloud-sdk/completion.bash.inc ]]; then
    source /home/jman/google-cloud-sdk/completion.bash.inc
fi

source "$HOME/.cargo/env"

# >>> context7 >>>
# The key lives in ~/.config/environment.d/60-context7.conf so the graphical session gets it
# too. systemd does not feed that file to SSH logins or plain shells, so pull it in here when
# it is missing. Rotate the key in that file only: ~/.claude.json and ~/.codex/config.toml
# reference this variable rather than storing a copy.
if [[ -z "$CONTEXT7_API_KEY" && -r "$HOME/.config/environment.d/60-context7.conf" ]]; then
    export CONTEXT7_API_KEY="$(sed -n "s/^CONTEXT7_API_KEY=//p" "$HOME/.config/environment.d/60-context7.conf")"
fi
# <<< context7 <<<
