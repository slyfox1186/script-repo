#!/usr/bin/env bash

# ===============================================================
# Enhanced .bashrc for Arch Linux - Modular Version
# Author: slyfox1186 (https://github.com/slyfox1186/script-repo)
# ===============================================================

# If not running interactively, don't do anything
case "$-" in
    *i*) ;;
    *) return ;;
esac

# Fix getcwd error if current directory is deleted
cd ~ 2>/dev/null || true

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
/usr/lib/ccache:\
/usr/local/bin:\
/usr/local/sbin:\
/usr/local/cuda/bin:\
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

LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/cuda/lib64"
export LD_LIBRARY_PATH PATH

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
    [[ -n "$entry" ]] || return
    remove_path_entry "$entry"
    export PATH="$entry${PATH:+:$PATH}"
}

path_append() {
    local entry
    entry="$1"
    [[ -n "$entry" ]] || return
    remove_path_entry "$entry"
    export PATH="${PATH:+$PATH:}$entry"
}

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
export CONDA_AUTO_ACTIVATE_BASE=false
__conda_setup="$('/home/jman/miniconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/jman/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/home/jman/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/jman/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# Keep system-installed tools ahead of the Conda base bin directory.
if [[ -d "$HOME/miniconda3/bin" ]]; then
    path_append "$HOME/miniconda3/bin"
fi

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
    local exit_code=$?

    # Colors (wrapped in \[ \] for proper cursor positioning)
    local reset='\[\e[0m\]'
    local red='\[\e[0;31m\]'
    local green='\[\e[0;32m\]'
    local yellow='\[\e[0;33m\]'
    local blue='\[\e[0;34m\]'
    local purple='\[\e[0;35m\]'
    local cyan='\[\e[0;36m\]'
    local gray='\[\e[0;90m\]'

    # Git info
    local git_info=""
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

# MARVIN - AI Chief of Staff
marvin() {
    echo -e '\e[1;33m███╗   ███╗    █████╗    ██████╗   ██╗   ██╗  ██╗   ███╗   ██╗   \e[0m'
    echo -e '\e[1;33m████╗ ████║   ██╔══██╗   ██╔══██╗  ██║   ██║  ██║   ████╗  ██║   \e[0m'
    echo -e '\e[1;33m██╔████╔██║   ███████║   ██████╔╝  ██║   ██║  ██║   ██╔██╗ ██║   \e[0m'
    echo -e '\e[1;33m██║╚██╔╝██║   ██╔══██║   ██╔══██╗  ╚██╗ ██╔╝  ██║   ██║╚██╗██║   \e[0m'
    echo -e '\e[1;33m██║ ╚═╝ ██║██╗██║  ██║██╗██║  ██║██╗╚████╔╝██╗██║██╗██║ ╚████║██╗\e[0m'
    echo -e '\e[1;33m╚═╝     ╚═╝╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝ ╚═══╝ ╚═╝╚═╝╚═╝╚═╝  ╚═══╝╚═╝\e[0m'
    echo ''
    echo -e '\e[0;36m▖  ▖              ▄▖      ▘  ▗        ▗     \e[0m'
    echo -e '\e[0;36m▛▖▞▌▀▌▛▌▀▌▛▌█▌▛▘  ▌▌▛▌▛▌▛▌▌▛▌▜▘▛▛▌█▌▛▌▜▘▛▘   \e[0m'
    echo -e '\e[0;36m▌▝ ▌█▌▌▌█▌▙▌▙▖▄▌  ▛▌▙▌▙▌▙▌▌▌▌▐▖▌▌▌▙▖▌▌▐▖▄▌▗   \e[0m'
    echo -e '\e[0;36m          ▄▌        ▌ ▌                   ▘    \e[0m'
    echo -e '\e[0;36m▄▖     ▌    ▖▖    ▘        ▄▖         ▗     ▗   ▖ ▖  ▗ ▘▐▘▘    ▗ ▘      \e[0m'
    echo -e '\e[0;36m▙▘█▌▀▌▛▌▛▘  ▌▌▀▌▛▘▌▛▌▌▌▛▘  ▐ ▛▛▌▛▌▛▌▛▘▜▘▀▌▛▌▜▘  ▛▖▌▛▌▜▘▌▜▘▌▛▘▀▌▜▘▌▛▌▛▌▛▘\e[0m'
    echo -e '\e[0;36m▌▌▙▖█▌▙▌▄▌  ▚▘█▌▌ ▌▙▌▙▌▄▌  ▟▖▌▌▌▙▌▙▌▌ ▐▖█▌▌▌▐▖  ▌▝▌▙▌▐▖▌▐ ▌▙▖█▌▐▖▌▙▌▌▌▄▌\e[0m'
    echo -e '\e[0;36m                                ▌                                       \e[0m'
    echo ''
    cd "/home/jman/marvin" && claude
}


# MARVIN - Open in IDE
mcode() {
    claude "/home/jman/marvin"
}


# NCCL configuration for distributed vLLM (Ethernet, not InfiniBand)
export NCCL_IB_DISABLE=1
export NCCL_NET_GDR_LEVEL=0
export NCCL_P2P_DISABLE=1
export NCCL_DEBUG=WARN

# >>> build-tools golang >>>
export GOROOT="/usr/local/programs/golang-1.26.1"
export GOROOT
path_append "$GOROOT/bin"
# <<< build-tools golang <<<
