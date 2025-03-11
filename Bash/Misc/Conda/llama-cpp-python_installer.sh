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

printf "\n%s\n\n" "Installing conda packages."
conda install -c pytorch pytorch torchvision torchaudio -y

# Install pip packages
printf "%s\n\n" "Installing pip packages."
pip install bs4 markdown2 nltk psutil pytest \
python-dotenv sentencepiece spacy textblob tqdm \
unidecode peft apscheduler redis fake_useragent \
flask flask_cors langdetect "numpy<2.0.0,>=1.25.0" \
"scipy>=1.6.0" "threadpoolctl>=3.1.0" "tzdata>=2022.7" \
"python-dateutil>=2.8.2"

# Install with CUDA support in editable mode
CMAKE_ARGS="-DGGML_CUDA=ON \
           -DCMAKE_CUDA_ARCHITECTURES=native \
           -DCMAKE_LIBRARY_PATH=$CUDA_HOME/lib64:/usr/lib/x86_64-linux-gnu \
           -DCMAKE_CUDA_HOST_COMPILER=$(type -P gcc-12)" \
CUDACXX="$CUDA_HOME/bin/nvcc" \
CUDA_PATH="$CUDA_HOME" \
pip install llama-cpp-python --force-reinstall --no-cache-dir --upgrade --verbose || (
    echo "Failed to install llama-cpp-python. Exiting..."
    exit 1
)
