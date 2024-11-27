#!/usr/bin/env bash

# Set CUDA environment variables
CUDA_HOME="/usr/local/cuda"
PATH="$PATH:/usr/lib/x86_64-linux-gnu:$CUDA_HOME/bin"
LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$CUDA_HOME/lib64:/usr/lib/x86_64-linux-gnu"
export CUDA_HOME LD_LIBRARY_PATH PATH

# Debug environment
echo
echo "CUDA_HOME is set to: $CUDA_HOME"
echo "LD_LIBRARY_PATH is set to: $LD_LIBRARY_PATH"
echo "PATH is set to: $PATH"
echo

# Install conda packages
conda install -y bs4 bitsandbytes langdetect markdown2 nltk psutil pytest-asyncio pytest python-dotenv \
                 scikit-learn sentencepiece spacy textblob tiktoken tqdm transformers unidecode

# Install pip packages
pip install accelerate cloud-tpu-client fake_useragent "numpy<2.1.0,>=2.0.0"

# Install llama-cpp-python with verbose output for debugging
CMAKE_ARGS="-DGGML_CUDA=ON \
           -DCMAKE_CUDA_ARCHITECTURES=all \
           -DCMAKE_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu \
           -DCMAKE_CUDA_HOST_COMPILER=$(type -P gcc-12)" \
CUDACXX="/usr/local/cuda/bin/nvcc" \
CUDA_PATH="/usr/local/cuda" \
pip install llama-cpp-python --upgrade --force-reinstall --no-cache-dir --verbose || (
    echo "Failed to install llama-cpp-python. Exiting..."
    exit 1
)

