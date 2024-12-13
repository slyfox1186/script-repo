# AI Code Assistant
 - A powerful local AI coding assistant that leverages dual LLMs for intelligent code generation, debugging, and technical discussions. Built with Python and Flask, it provides a responsive web interface for real-time interaction.

## Examples

#### General
![General Example 1](https://i.imgur.com/CikPfBU.png)
![General Example 2](https://i.imgur.com/NPKGpi8.png)

#### Assistant Memory
![AI Memory Example](https://i.imgur.com/HlYnU38.png)

## Features

- **Intelligent Code Generation**
  - Real-time code completion and generation
  - Multi-language support with syntax highlighting
  - Context-aware code suggestions
  - File path and language detection

- **Dual LLM Architecture**
  - Primary 32B model for code generation
  - Secondary 1.5B model for fast context handling
  - Efficient GPU memory management
  - Automatic model switching based on query type

- **Interactive Interface**
  - Real-time streaming responses
  - Syntax-highlighted code blocks
  - Responsive web design
  - Clear conversation history management

- **Memory Management**
  - Persistent conversation history with backup system
  - Code response caching
  - Efficient token usage tracking
  - Automatic context pruning

## System Information

### Recommended Hardware
- **GPU**: NVIDIA GPU with 24GB+ VRAM
- **RAM**: 32GB minimum recommended
- **Storage**: 50GB+ free space for models and cache

### Required Models

1. **Code Generation Model**
   - Name: Qwen2.5-Coder-32B-Instruct
   - Size: 32B parameters (Q5_K_L quantized)
   - VRAM Usage: ~16GB
   - GPU Layers: 63 layers offloaded  
   [Download Link](https://huggingface.co/bartowski/Qwen2.5-Coder-32B-Instruct-GGUF/blob/main/Qwen2.5-Coder-32B-Instruct-Q5_K_L.gguf)

2. **Context Management Model**
   - Name: Qwen2.5-1.5B-Instruct
   - Size: 1.5B parameters (Q8_0 quantized)
   - VRAM Usage: ~2GB
   - GPU Layers: 29 layers offloaded  
   [Download Link](https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/blob/main/Qwen2.5-1.5B-Instruct-Q8_0.gguf)

## Quick Start

1. **Setup file structure**

2. **Create a Virtual Environment**
   ```bash
   python -m venv venv
   source venv/bin/activate  # Linux/Mac
   # or
   .\venv\Scripts\activate  # Windows
   ```

3. **Install Dependencies**
   ```bash
   pip install -r requirements.txt
   ```

4. **Download Models**
   ```bash
   mkdir models
   # Download models from the links provided above
   # and place them in the models/ directory
   ```

5. **Tune the script to your VRAM limits**
   - These options are located in the `persistent_memory.py` script
   ```bash
   # Set these according to the amount of VRAM you have available
   GPU_LAYERS_CODER = 63
   GPU_LAYERS_FAST = 29
   ```

6. **Run the Application**
   ```bash
   python app.py
   ```

7. **Access the Interface**
   - Open your browser and go to:  
     `http://localhost:5000`

## Technical Details

### Memory Management
- Dynamic VRAM allocation
- Main model: Maximum of 65 total layers
- Memory model: Maximum of 29 total layers
- Automatic context pruning
- Token usage optimization

### Browser Compatibility
- Firefox (Recommended)
- Chrome/Edge
- Safari

### Security Notes
- Runs locally with no external data transfers
- Models run entirely on your hardware
- Conversation history stored locally

## Troubleshooting

- **CUDA out of memory**: Reduce layer offload in `persistent_memory.py`
- **Slow responses**: Check GPU utilization and VRAM usage
- **Model loading errors**: Verify model paths in `app.py`

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.

