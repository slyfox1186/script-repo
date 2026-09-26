# $HOME/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc) for examples

# If not running interactively, don't do anything
case "$-" in
    *i*) ;;
      *) return ;;
esac

# Don't put duplicate lines or lines starting with space in the history.
HISTCONTROL="ignoreboth"

# Append to the history file, don't overwrite it
shopt -s histappend

# For setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=10000
HISTFILESIZE=20000

# Check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s globstar

# Make less more friendly for non-text input files, see lesspipe(1)
[[ -x /usr/bin/lesspipe ]] && eval "$(SHELL=/bin/sh lesspipe)"

# Set variable identifying the chroot you work in (used in the prompt below)
if [[ -z "${debian_chroot:-}" ]] && [[ -r "/etc/debian_chroot" ]]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# Set a fancy prompt (non-color, unless we know we "want" color)
case "${TERM-}" in
    xterm-color|*-256color) color_prompt="yes" ;;
esac

# Uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt="yes"

if [[ -n "$force_color_prompt" ]]; then
    if [[ -x /usr/bin/tput ]] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48 (ISO/IEC-6429)
        # Lack of such support is extremely rare, and such a case would tend to support setf rather than setaf.
        color_prompt="yes"
    else
        color_prompt=""
    fi
fi

if [[ "${color_prompt-}" == "yes" ]]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "${TERM-}" in
    xterm*|rxvt*) PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
                  ;;
               *) ;;
esac

# Enable color support of ls and also add handy aliases
if [[ -x "/usr/bin/dircolors" ]]; then
    if [[ -r "$HOME/.dircolors" ]]; then
        eval "$(dircolors -b "$HOME/.dircolors")"
    else
        eval "$(dircolors -b)"
    fi
    alias ls="ls --color=always --group-directories-first"
    alias grep="grep --color=always"
fi

# Colored GCC warnings and errors
GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
export GCC_COLORS

# Alias definitions.
# You may want to put all your additions into a separate file like
# $HOME/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [[ -f "$HOME/.bash_aliases" ]]; then
    # shellcheck source=/home/jman/.bash_aliases
    source "$HOME/.bash_aliases"
fi

# You don't need to enable this, if it's already enabled in
# /etc/bash.bashrc and /etc/profile sources /etc/bash.bashrc
if ! shopt -oq posix; then
    if [ -f "/usr/share/bash-completion/bash_completion" ]; then
        source "/usr/share/bash-completion/bash_completion"
    elif [ -f "/etc/bash_completion" ]; then
        source "/etc/bash_completion"
  fi
fi

####################
## CUSTOM SECTION ##
####################

if [[ -f "$HOME/.bash_functions" ]]; then
    # shellcheck source=/home/jman/.bash_functions
    source "$HOME/.bash_functions"
fi


if [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi

THREADS=$(nproc --all)
CPUS=$((THREADS > 1 ? THREADS / 2 : 1))
LAN=$(ip route get 1.2.3.4 | awk '{print $7}')
WAN=$(curl --connect-timeout 1 -fsS "https://checkip.amazonaws.com" 2>/dev/null || true)
PS1='\n\[\e[38;5;227m\]\w\n\[\e[38;5;215m\]\u\[\e[38;5;183;1m\]@\[\e[0;38;5;117m\]\h\[\e[97;1m\]\\$\[\e[0m\]'
PYTHONUTF8=1
MAGICK_THREAD_LIMIT=16
export CPUS LAN PS1 PYTHONUTF8 THREADS WAN MAGICK_THREAD_LIMIT

# Set the script's path variable
# Prioritize conda environments over ~/.local/bin
PATH="\
$HOME/.npm-global/bin:\
/usr/lib/ccache:\
/usr/local/bin:\
$HOME/miniconda3/condabin:\
$HOME/.local/bin:\
$HOME/.cargo/bin:\
/usr/local/sbin:\
/usr/local/cuda/bin:\
/usr/local/x86_64-linux-gnu/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin\
"
export PATH

GOROOT=$(for d in /usr/local/programs/golang-*/bin/go; do [[ -x "$d" ]] && dirname "$(dirname "$d")"; done | sort -rV | head -n1)
if [[ -n "$GOROOT" ]]; then
  PATH="$PATH:$GOROOT/bin"
  export GOROOT PATH
fi

# pyenv setup - only use shims when NOT in a conda environment
PYENV_ROOT="$HOME/.pyenv"
export PYENV_ROOT
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
# Use --path only to avoid shim conflicts with conda
# Shims are added dynamically only when no conda env is active
if command -v pyenv &>/dev/null; then
    eval "$(command pyenv init --path)"
fi

# shellcheck source=/dev/null
source "$HOME/.bash_functions.d/startup/pyenv.sh"

# Set nano as default editor
EDITOR=nano
VISUAL=nano
export EDITOR VISUAL

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
if __conda_setup="$(/home/jman/miniconda3/bin/conda shell.bash hook 2>/dev/null)"; then
    eval "$__conda_setup"
else
    if [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
        source "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
        PATH="$PATH:$HOME/miniconda3/bin"
        export PATH
    fi
fi
unset __conda_setup
if command -v conda &>/dev/null; then
    conda activate base
fi
# <<< conda initialize <<<
# nvm (load after conda so Node version stays consistent in interactive shells)
NVM_DIR="$HOME/.nvm"
export NVM_DIR
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # Prevent nvm incompatibility warning in shells that export npm prefix variables.
    unset npm_config_prefix NPM_CONFIG_PREFIX PREFIX
    . "$NVM_DIR/nvm.sh"
    nvm use --silent default >/dev/null 2>&1 || true
fi
[[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"

# VTE configuration for Tilix terminal (directory tracking, notifications)
# Required on Debian since profile.d scripts only run for login shells
if [[ -n "${TILIX_ID-}" || -n "${VTE_VERSION-}" ]]; then
    for vte_script in /etc/profile.d/vte-*.sh; do
        [[ -r "$vte_script" ]] || continue
        # shellcheck source=/dev/null
        source "$vte_script"
        break
    done
    unset vte_script
fi

# NCCL configuration for distributed vLLM (Ethernet, not InfiniBand)
NCCL_IB_DISABLE=1
NCCL_NET_GDR_LEVEL=0
NCCL_P2P_DISABLE=1
NCCL_DEBUG=WARN
export NCCL_DEBUG NCCL_P2P_DISABLE NCCL_NET_GDR_LEVEL NCCL_IB_DISABLE

# Claude Code
CLAUDE_CODE_MAX_OUTPUT_TOKENS=65536
export CLAUDE_CODE_MAX_OUTPUT_TOKENS

# codex-orchestrator
PATH="/home/jman/.codex-orchestrator/bin:$PATH"
PATH="$PATH:/home/jman/.npm/_npx/a92a6dbcf543fba6/node_modules/.bin"
export PATH

# CUDA / nvcc
export CUDA_HOME=/usr/local/cuda
export CUDACXX=/usr/local/cuda/bin/nvcc

# --- Pi / chat-app env loading -----------------------------------------------
# backend/.env holds the canonical chat web app secrets (Google OAuth, SerpAPI,
# Redis URL, etc.). Pi inherits these via shell env when launched by run_pi.py,
# so we export them with `set -a`. Auto-skipped if the file is missing.
# ~/.pi/secrets.env holds Pi-only secrets (EXA_API_KEY, GITHUB_PAT, METAMCP_*).
# It is sourced second so it can override any backend value if needed.
if [[ -f /home/jman/tmp/qwen3.6-gguf/backend/.env ]]; then
    if [[ -o allexport ]]; then
        # shellcheck source=/home/jman/tmp/qwen3.6-gguf/backend/.env
        source /home/jman/tmp/qwen3.6-gguf/backend/.env
    else
        set -a
        # shellcheck source=/home/jman/tmp/qwen3.6-gguf/backend/.env
        source /home/jman/tmp/qwen3.6-gguf/backend/.env
        set +a
    fi
fi
if [[ -f "$HOME/.pi/secrets.env" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.pi/secrets.env"
fi

# Claude Code MCP secrets (chmod 600)
if [[ -f "$HOME/.claude/secrets.env" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.claude/secrets.env"
fi

export COLORTERM='truecolor'
# opencode
export PATH=/home/jman/.opencode/bin:$PATH

# --- pip-aria2 wrapper (managed) ---
# shellcheck source=/dev/null
source "$HOME/.bash_functions.d/startup/pip.sh"
# --- end pip-aria2 wrapper ---
. "$HOME/.cargo/env"

# >>> cuda toolkit (managed by cuda.sh) >>>
export CUDA_HOME=/usr/local/cuda-13.4
case ":${PATH:-}:" in *":$CUDA_HOME/bin:"*) ;; *) export PATH="$CUDA_HOME/bin${PATH:+:$PATH}" ;; esac
# <<< cuda toolkit (managed by cuda.sh) <<<

# >>> gcc 15.3.0 (built from source) >>>
# Follows the /usr/local/programs/<name>-<version> convention used by the other
# source-built packages here. Deliberately NOT symlinked into /usr/local/bin: that
# would make gcc-15 the default compiler for sudo/cron/DKMS too, where the distro
# gcc 13.3 is expected. Kept LAST in this file so it wins over the earlier
# ccache/cuda/conda prepends. Runtime libs are found via RUNPATH baked in by the
# compiler's specs file, so no LD_LIBRARY_PATH is needed.
# To disable: comment out this block and open a new shell.
export GCC15_HOME=/usr/local/programs/gcc-15.3.0
if [[ -d "$GCC15_HOME/bin" ]]; then
    case ":${PATH:-}:" in
        *":$GCC15_HOME/bin:"*) ;;
        *) export PATH="$GCC15_HOME/bin${PATH:+:$PATH}" ;;
    esac
    export MANPATH="$GCC15_HOME/share/man${MANPATH:+:$MANPATH}"
fi
# <<< gcc 15.3.0 <<<

# OpenRouter API key for the orask / openrouter-mcp bridge.
# The secret lives in ~/.config/openrouter/env (chmod 600), not in this file.
if [ -r "$HOME/.config/openrouter/env" ]; then
    OPENROUTER_API_KEY=$(sed -n 's/^[[:space:]]*OPENROUTER_API_KEY[[:space:]]*=[[:space:]]*//p' "$HOME/.config/openrouter/env" | head -n 1 | tr -d "\"'")
    if [ -n "$OPENROUTER_API_KEY" ]; then
        export OPENROUTER_API_KEY
    else
        unset OPENROUTER_API_KEY
    fi
fi
