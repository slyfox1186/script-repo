#!/usr/bin/env bash

if [[ $EUID -eq 0 ]]; then
    echo "You must run this script without sudo or as root."
    exit 1
fi

if ! type -P conda &>/dev/null; then
    printf "%s\n" "You must install conda to run this script."
    read -p "Do you want to install conda (y/n): install_conda.sh ?" answer
    if [[ -n "$answer" ]]; then
		curl -fsSL 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh' > conda_install.sh
	else
		echo "You MUST install conda to continue."
		exit 1
	fi
    [[ -f conda_install.sh ]] && bash conda_install.sh
fi

# Set CUDA environment variables — use system CUDA, not conda's
CC=$(which gcc)
CXX=$(which g++)
CUDA_HOME=/opt/cuda
PATH="$CUDA_HOME/bin:/usr/lib/x86_64-linux-gnu:$PATH"
LD_LIBRARY_PATH="$CUDA_HOME/lib64:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
export CC CXX CUDA_HOME LD_LIBRARY_PATH PATH

# Install system dependencies
sudo pacman -Syu
echo yes | sudo pacman -S base-devel cmake curl gcc libcurl-gnutls ninja pciutils

# Debug environment
printf "\n%s\n" "CUDA_HOME is set to: $CUDA_HOME"
echo "LD_LIBRARY_PATH is set to: $LD_LIBRARY_PATH"
printf "%s\n" "PATH is set to: $PATH"

# Clone or update llama.cpp repository
if [[ -d llama.cpp/ ]]; then
    printf "\n%s\n\n" "llama.cpp directory already exists. Pulling latest changes..."
    git -C llama.cpp/ pull || {
        printf "\n%s\n" "[ERROR] Failed to git pull."
        exit 1
    }
else
    printf "\n%s\n" "Cloning llama.cpp repository..."
    git clone 'https://github.com/ggml-org/llama.cpp' || {
        printf "\n%s\n" "[ERROR] Failed to clone llama.cpp."
        exit 1
    }
fi

printf "\n%s\n\n" "Building llama.cpp with CUDA support..."

# Remove stale CMake cache to pick up compiler changes
rm -rf llama.cpp/build/CMakeCache.txt llama.cpp/build/CMakeFiles

# Configure CMake with CUDA support (out-of-source build)
# Explicitly point to system CUDA to avoid conda's incomplete toolkit (missing cublas)
cmake llama.cpp \
    -B llama.cpp/build \
    -G Ninja \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_CUDA=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=$CC \
    -DCMAKE_CXX_COMPILER=$CXX \
    -DCMAKE_CUDA_COMPILER=$CUDA_HOME/bin/nvcc \
    -DCMAKE_CUDA_HOST_COMPILER=$CXX \
    -DCUDAToolkit_ROOT=$CUDA_HOME \
    -DCMAKE_CUDA_ARCHITECTURES=native || {
        printf "\n%s\n%s\n" "[ERROR] CMake configuration failed." "Exiting the script."
        exit 1
    }

# Build specific targets with clean-first
cmake \
    --build llama.cpp/build \
    --config Release \
    -j$(nproc) \
    --clean-first \
    --target llama-cli llama-mtmd-cli llama-server llama-gguf-split || {
        printf "\n%s\n%s\n" "[ERROR] Build failed." "Exiting the script."
        exit 1
    }

# Copy built binaries to llama.cpp root for easy access
cp -f llama.cpp/build/bin/llama-* llama.cpp/

printf "\n%s\n" "llama.cpp built successfully in llama.cpp/build/bin"

# Install binaries to /usr/local/bin
printf "\n%s\n" "Installing binaries to /usr/local/bin (requires sudo)..."

if [[ -d llama.cpp/build/bin/ ]]; then
    sudo cp -f llama.cpp/build/bin/llama-* /usr/local/bin/ || {
        printf "\n%s\n%s\n" "[ERROR] Failed to copy binaries to /usr/local/bin." "Exiting the script."
        exit 1
    }
    printf "%s\n" "Binaries installed successfully."
else
    printf "\n%s\n%s\n" "[ERROR] Build directory 'llama.cpp/build/bin' not found." "Cannot install binaries."
    exit 1
fi

# Prompt to clean up cloned repo after successful install
if [[ -d llama.cpp/ ]]; then
    read -p "Delete the llama.cpp source directory? (y/n): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        if rm -rf llama.cpp/; then
			printf "%s\n" "Source directory removed."
		else
			printf "%s\n" "Failed to remove the source directory."
		fi
    else
        printf "%s\n" "Source directory kept at $(pwd)/llama.cpp"
    fi
fi

printf "\n%s\n" "Installation and build complete."
