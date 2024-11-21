#!/usr/bin/env bash

file="/tmp/requirements.txt"

cat > $file <<'EOF'
accelerate
bs4
bitsandbytes
cloud-tpu-client
fake_useragent
langdetect
markdown2
nltk
numpy
pandas
psutil
pydantic
pytest-asyncio
pytest
python-dotenv
pyyaml
scikit-learn
sentencepiece
spacy
tenacity
tensorflow
textblob
tf-keras
tiktoken
torch
torchaudio
torchvision
tqdm
transformers
unidecode
wikipedia
EOF

# Install regular requirements
pip install -r $file

# Set CUDA environment variables
export CUDA_HOME="/usr/local/cuda"
export PATH="$PATH:$CUDA_HOME/bin"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$CUDA_HOME/lib64:/usr/lib/x86_64-linux-gnu"

# Debug environment
echo "CUDA_HOME is set to: $CUDA_HOME"
echo "LD_LIBRARY_PATH is set to: $LD_LIBRARY_PATH"
echo "PATH is set to: $PATH"

# Install llama-cpp-python with verbose output for debugging
CMAKE_ARGS="-DGGML_CUDA=ON \
           -DCMAKE_CUDA_ARCHITECTURES=all \
           -DCMAKE_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu \
           -DCMAKE_CUDA_HOST_COMPILER=$(type -P gcc-12)" \
CUDACXX="/usr/local/cuda/bin/nvcc" \
CUDA_PATH="/usr/local/cuda" \
pip install llama-cpp-python --no-cache-dir -v || (
    echo "Failed to install llama-cpp-python. Exiting..."
    exit 1
)

# Clean up
[[ -f $file ]] && rm $file
stall -r $file

# Set CUDA environment variables
export CUDA_HOME="/usr/local/cuda"
export PATH="$PATH:$CUDA_HOME/bin"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$CUDA_HOME/lib64:/usr/lib/x86_64-linux-gnu"

# Debug environment
echo "CUDA_HOME is set to: $CUDA_HOME"
echo "LD_LIBRARY_PATH is set to: $LD_LIBRARY_PATH"
echo "PATH is set to: $PATH"

# Install llama-cpp-python with verbose output for debugging
CMAKE_ARGS="-DGGML_CUDA=ON \
           -DCMAKE_CUDA_ARCHITECTURES=all \
           -DCMAKE_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu \
           -DCMAKE_CUDA_HOST_COMPILER=$(type -P gcc-12)" \
CUDACXX="/usr/local/cuda/bin/nvcc" \
CUDA_PATH="/usr/local/cuda" \
if ! pip install llama-cpp-python --no-cache-dir -v; then
    echo "Failed to install llama-cpp-python. Exiting..."
    exit 1
fi

# Clean up
[[ -f $file ]] && rm $file
