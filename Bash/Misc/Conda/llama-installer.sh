#!/usr/bin/env bash

# Function to detect conda in multiple ways
detect_conda() {
    # Try the standard way first
    if type -P conda &>/dev/null; then
        return 0
    fi
    
    echo "Conda not found in PATH. Searching common locations..."
    
    # Check common conda installation locations first (fast check)
    local conda_paths=(
        "$HOME/miniconda/bin/conda"
        "$HOME/miniconda3/bin/conda"
        "$HOME/anaconda3/bin/conda"
        "/opt/conda/bin/conda"
        "/usr/local/anaconda/bin/conda"
        "/usr/local/miniconda/bin/conda"
        "/usr/local/miniconda3/bin/conda"
    )
    
    for conda_path in "${conda_paths[@]}"; do
        if [[ -x "$conda_path" ]]; then
            echo "Found conda at $conda_path"
            # Add conda to PATH for this script
            export PATH="$(dirname "$conda_path"):$PATH"
            return 0
        fi
    done
    
    # Check if conda is available but not in PATH via environment variables
    if [[ -n "$CONDA_EXE" && -x "$CONDA_EXE" ]]; then
        echo "Found conda via CONDA_EXE at $CONDA_EXE"
        export PATH="$(dirname "$CONDA_EXE"):$PATH"
        return 0
    fi
    
    # If conda is still not found, use find command with reasonable constraints
    echo "Searching for conda using find (this may take a moment)..."
    # Search in home directory and some common system directories with depth limit
    # and timeout after 15 seconds
    local found_conda
    found_conda=$(timeout 15 find "$HOME" /usr/local /opt /usr -maxdepth 5 -type f -name conda -executable 2>/dev/null | grep -v "conda-env\|conda-build" | head -n1)
    
    if [[ -n "$found_conda" && -x "$found_conda" ]]; then
        echo "Found conda using find at $found_conda"
        export PATH="$(dirname "$found_conda"):$PATH"
        return 0
    fi
    
    return 1
}

# Function to handle environment switching and continue script execution
switch_and_exec() {
    local target_env=$1
    echo "Switching to environment: $target_env"
    # Create a new script that activates the environment and runs the rest of this script
    TEMP_SCRIPT=$(mktemp)
    cat > "$TEMP_SCRIPT" << EOF
#!/bin/bash
source "\$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$target_env"
if [[ "\$?" -ne 0 ]]; then
    echo "Failed to activate conda environment: $target_env"
    exit 1
fi
echo "Successfully activated $target_env environment"
export CONDA_ENV_SWITCHED=1
$(cat "$0" | grep -v "^#!/usr/bin/env bash" | grep -v "# Function to detect conda in multiple ways" | grep -v "detect_conda()" | grep -v -A 30 "local conda_paths=" | tail -n +30)
EOF
    chmod +x "$TEMP_SCRIPT"
    exec "$TEMP_SCRIPT"
    exit 0
}

# Skip environment check if already switched
if [[ -z "$CONDA_ENV_SWITCHED" ]]; then
    if [[ "$EUID" -eq 0 ]]; then
        echo "You must run this script without sudo or as root."
        exit 1
    fi

    echo "Checking for conda installation..."
    if ! detect_conda; then
        echo "Conda not found in PATH or common locations."
        echo "You must install conda to run this script."
        echo
        read -p "Do you want to install conda (y/n): install_conda.sh ?" answer
        if [[ -n "$answer" ]]; then
            bash <(curl -fsSL https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Misc/Conda/install_conda.sh)
            # After installation, try to detect conda again
            if ! detect_conda; then
                echo "Failed to detect conda after installation. Please restart your terminal and try again."
                exit 1
            fi
        else
            echo "Conda is required for this script. Exiting."
            exit 1
        fi
    fi
    
    echo "Conda detected successfully."

    # Initialize conda for shell script use if needed
    if [[ -z "$CONDA_SHLVL" || "$CONDA_SHLVL" -eq 0 ]]; then
        echo "Initializing conda for this script..."
        # Source conda.sh to enable conda activation in this script
        CONDA_BASE=$(conda info --base 2>/dev/null)
        if [[ -z "$CONDA_BASE" ]]; then
            echo "Failed to get conda base directory. Using default detection method."
            # Try common locations for conda.sh
            for conda_sh in "$HOME/miniconda3/etc/profile.d/conda.sh" "$HOME/anaconda3/etc/profile.d/conda.sh" "/opt/conda/etc/profile.d/conda.sh"; do
                if [[ -f "$conda_sh" ]]; then
                    echo "Found conda.sh at $conda_sh"
                    source "$conda_sh"
                    break
                fi
            done
        else
            source "$CONDA_BASE/etc/profile.d/conda.sh"
        fi
        
        # Verify conda is now properly initialized
        if ! type -P conda &>/dev/null; then
            echo "WARNING: Failed to initialize conda properly. Some features may not work."
        fi
    fi

    # Properly detect the actual active conda environment
    # After sourcing conda.sh, this should accurately report the environment
    if [[ -z "$CONDA_DEFAULT_ENV" || "$CONDA_DEFAULT_ENV" == "base" ]]; then
        active_env="base"
    else
        active_env="$CONDA_DEFAULT_ENV"
    fi
    
    echo "Detected active conda environment: $active_env"
    
    # Check if using base conda environment and offer to switch
    if [[ "$active_env" == "base" ]]; then
        echo "You are currently using the 'base' conda environment."
        read -p "Would you like to switch to a different environment? (y/n): " switch_env
        
        if [[ "$switch_env" == "y" || "$switch_env" == "Y" ]]; then
            echo
            echo "Choose one of the following options:"
            echo "1. Display available conda environments"
            echo "2. Enter the name of the environment to use"
            read -p "Enter your choice (1 or 2): " env_choice
            
            if [[ "$env_choice" == "1" ]]; then
                echo
                echo "Available conda environments:"
                conda env list
                echo
                read -p "Enter the name of the environment to use: " target_env
            elif [[ "$env_choice" == "2" ]]; then
                read -p "Enter the name of the environment to use: " target_env
            else
                echo "Invalid choice. Continuing with 'base' environment."
                target_env="base"
            fi
            
            if [[ "$target_env" != "base" ]]; then
                # Check if the environment exists
                if conda env list | grep -q "$target_env"; then
                    # This will switch environments and continue execution
                    switch_and_exec "$target_env"
                else
                    echo "Environment '$target_env' not found. Continuing with 'base' environment."
                fi
            fi
        else
            echo "Continuing with 'base' environment."
        fi
    else
        echo "Using non-base environment: $active_env"
    fi
fi

# Set CUDA environment variables
CUDA_HOME="/usr/local/cuda"
PATH="$PATH:/usr/lib/x86_64-linux-gnu:$CUDA_HOME/bin"
LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$CUDA_HOME/lib64:/usr/lib/x86_64-linux-gnu"
export CUDA_HOME LD_LIBRARY_PATH PATH

# Detect if running in WSL/WSL2
is_wsl=0
if grep -qi microsoft /proc/version || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    echo "Detected Windows Subsystem for Linux (WSL/WSL2)"
    is_wsl=1
else
    echo "Detected native Linux system"
fi

# Install gcc 12 if not already installed
if ! type -P gcc-12 &>/dev/null; then
    sudo apt update
    sudo apt -y install gcc-12 g++-12
fi

# Debug environment
printf "\n%s\n%s\n" "Set environment variables" "--------------------------------"
echo "CUDA_HOME: $CUDA_HOME"
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "PATH: $PATH"

printf "\n%s\n%s\n" "Installing pytorch" "--------------------------------"
pip install torch torchvision torchaudio
echo

# Set CUDA architecture based on system type
if [[ "$is_wsl" -eq 1 ]]; then
    CUDA_ARCH="all"
    echo "Setting CUDA architecture to 'all' for WSL/WSL2 compatibility"
else
    CUDA_ARCH="native"
    echo "Setting CUDA architecture to 'native' for native Linux system"
fi

# Install with CUDA support in editable mode
printf "\n%s\n%s\n" "Installing llama-cpp-python" "--------------------------------"
CMAKE_ARGS="-DGGML_CUDA=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES=$CUDA_ARCH \
    -DCMAKE_LIBRARY_PATH=$CUDA_HOME/lib64:/usr/lib/x86_64-linux-gnu \
    -DCMAKE_CUDA_HOST_COMPILER=$(type -P gcc-12)" \
CUDACXX="$CUDA_HOME/bin/nvcc" \
CUDA_PATH="$CUDA_HOME" \
pip install llama-cpp-python --force-reinstall --no-cache-dir --upgrade --verbose || (
    printf "\n%s\n%s\n" "[ERROR] Failed to install llama-cpp-python." \
                    "Exiting the script."
    exit 1
)
