#!/usr/bin/env bash

if [[ "$EUID" -eq 0 ]]; then
    echo "You must run this script without sudo or as root."
    exit 1
fi

if ! type -P conda &>/dev/null; then
    echo "You must install conda to run this script."
    echo
    read -p "Do you want to install conda (y/n): install_conda.sh ?" answer
    if [[ -n "$answer" ]]; then
        bash <(curl -fsSL https://raw.githubusercontent.com/slyfox1186/script-repo/refs/heads/main/Bash/Misc/Conda/install_conda.sh)
    fi
fi

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

printf "\n%s\n\n" "Installing conda packages."
conda install -y -c pytorch pytorch torchvision torchaudio

# Install pip packages
printf "%s\n\n" "Installing pip packages."
pip install aiohttp apscheduler bs4 fake_useragent fastapi flask flask_cors \
langdetect markdown2 nltk "numpy<2.0.0,>=1.25.0" peft psutil pytest \
"python-dateutil>=2.8.2" python-dotenv pytz redis "scipy>=1.6.0" sentencepiece \
spacy textblob "threadpoolctl>=3.1.0" tqdm "tzdata>=2022.7" unidecode utils uvicorn

# Install with CUDA support in editable mode
CMAKE_ARGS="-DGGML_CUDA=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES=native \
    -DCMAKE_LIBRARY_PATH=$CUDA_HOME/lib64:/usr/lib/x86_64-linux-gnu \
    -DCMAKE_CUDA_HOST_COMPILER=$(type -P gcc-12)" \
CUDACXX="$CUDA_HOME/bin/nvcc" \
CUDA_PATH="$CUDA_HOME" \
pip install llama-cpp-python --force-reinstall --no-cache-dir --upgrade --verbose || (
    printf "\n%s\n%s\n" "[ERROR] Failed to install llama-cpp-python." \
                    "Exiting the script."
    exit 1
)
