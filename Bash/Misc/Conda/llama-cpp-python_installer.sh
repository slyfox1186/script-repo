#!/usr/bin/env bash

# Set CUDA environment variables
CUDA_HOME="/usr/local/cuda"
PATH="$PATH:/usr/lib/x86_64-linux-gnu:$CUDA_HOME/bin"
LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$CUDA_HOME/lib64:/usr/lib/x86_64-linux-gnu"
export CUDA_HOME LD_LIBRARY_PATH PATH

# Install gcc 12 if not already installed
if ! type -P gcc-12 &>/dev/null; then
    sudo apt update
    sudo apt -y install gcc-12 g++-12
fi

# Debug environment
echo
echo "CUDA_HOME is set to: $CUDA_HOME"
echo "LD_LIBRARY_PATH is set to: $LD_LIBRARY_PATH"
echo "PATH is set to: $PATH"

# Install required pip packages
printf "\n%s\n\n" "Installing required pip packages."
pip install apscheduler redis flask

# Clone and install llama-cpp-python
printf "\n%s\n\n" "Cloning and installing llama-cpp-python."
[[ -d 'llama-cpp-python' ]] && rm -fr llama-cpp-python
git clone 'https://github.com/abetlen/llama-cpp-python.git'
cd llama-cpp-python || exit 1
git submodule update --init --recursive

# Install with CUDA support in editable mode
CMAKE_ARGS="-DGGML_CUDA=ON \
           -DCMAKE_CUDA_ARCHITECTURES=native \
           -DCMAKE_LIBRARY_PATH=$CUDA_HOME/lib64:/usr/lib/x86_64-linux-gnu \
           -DCMAKE_CUDA_HOST_COMPILER=$(type -P gcc-12)" \
CUDACXX="$CUDA_HOME/bin/nvcc" \
CUDA_PATH="$CUDA_HOME" \
pip install . --force-reinstall --no-cache-dir --upgrade --verbose || (
    echo "Failed to install llama-cpp-python. Exiting..."
    exit 1
)
