#!/bin/bash
# External tools and dependencies

# ====================
# EXTERNAL FILES
# ====================
# Load aliases
if [[ -f "$HOME/.bash_aliases" ]]; then
    source "$HOME/.bash_aliases"
fi

# Load functions
if [[ -f "$HOME/.bash_functions" ]]; then
    source "$HOME/.bash_functions"
fi

# Enable bash completion
if ! shopt -oq posix; then
    if [[ -f "/usr/share/bash-completion/bash_completion" ]]; then
        source "/usr/share/bash-completion/bash_completion"
    elif [[ -f "/etc/bash_completion" ]]; then
        source "/etc/bash_completion"
    fi
fi

# ====================
# ADDITIONAL DEPENDENCIES
# ====================
# Load cargo environment if available
if [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi

# ====================
# NVM CONFIGURATION
# ====================
# Set up NVM (Node Version Manager) - Fixed duplicates
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    source "$NVM_DIR/nvm.sh"  # This loads nvm
    
    # Load bash completion for nvm if available
    if [[ -s "$NVM_DIR/bash_completion" ]]; then
        source "$NVM_DIR/bash_completion"
    fi
    
    # Use LTS version by default
    if type nvm &>/dev/null; then
        nvm use lts/hydrogen &>/dev/null && node -v
    fi
fi

# ====================
# CONDA CONFIGURATION
# ====================
# Initialize conda if available
__conda_setup="$("$HOME/miniconda3/bin/conda" 'shell.bash' 'hook' 2>/dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup

# ====================
# WSL SPECIFIC FIXES
# ====================
# Fix CUDA library symlinks in WSL
if [[ -f /usr/lib/wsl/lib/libcuda.so.1.1 ]] && [[ ! -L /usr/lib/wsl/lib/libcuda.so.1 ]]; then
    sudo ln -sf /usr/lib/wsl/lib/libcuda.so.1.1 /usr/lib/wsl/lib/libcuda.so.1
fi