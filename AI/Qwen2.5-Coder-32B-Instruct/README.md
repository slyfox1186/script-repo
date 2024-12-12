# AI Code Assistant

![AI Code Assistant Interface](https://i.imgur.com/CikPfBU.png)

A powerful local AI coding assistant that leverages dual LLMs for intelligent code generation, debugging, and technical discussions. Built with Python and Flask, it provides a responsive web interface for real-time interaction.

## Features

- **Intelligent Code Generation**
  - Real-time code completion and generation
  - Multi-language support with syntax highlighting
  - Context-aware code suggestions
  - File path and language detection

- **Dual LLM Architecture**
  - Primary 32B model for code generation
  - Secondary 7B model for fast context handling
  - Efficient GPU memory management
  - Automatic model switching based on query type

- **Interactive Interface**
  - Real-time streaming responses
  - Syntax-highlighted code blocks
  - Responsive web design
  - Clear conversation history management

- **Memory Management**
  - Persistent conversation history
  - Context-aware responses
  - Efficient token usage tracking
  - Automatic garbage collection

## System Recommendations

### Hardware Requirements
- **GPU**: NVIDIA GeForce RTX 4090 (24GB VRAM) or equivalent
- **CPU**: AMD Ryzen 7950x or equivalent
- **RAM**: 64GB minimum recommended
- **Storage**: 100GB+ free space for models and cache

### Required Models

1. **Code Generation Model**
   - Name: Qwen2.5-Coder-32B-Instruct
   - Size: 32B parameters (Q5_K_L quantized)
   - VRAM Usage: ~16GB
   - [Download Link](https://huggingface.co/bartowski/Qwen2.5-Coder-32B-Instruct-GGUF/blob/main/Qwen2.5-Coder-32B-Instruct-Q5_K_L.gguf)

2. **Context Management Model**
   - Name: Replete-LLM-V2.5-Qwen-7b
   - Size: 7B parameters (Q8_0 quantized)
   - VRAM Usage: ~3GB
   - [Download Link](https://huggingface.co/bartowski/Replete-LLM-V2.5-Qwen-7b-GGUF/blob/main/Replete-LLM-V2.5-Qwen-7b-Q8_0.gguf)

## Quick Start

1. **Clone the Repository**   ```bash
   git clone https://github.com/yourusername/ai-code-assistant.git
   cd ai-code-assistant   ```

2. **Create Virtual Environment**   ```bash
   python -m venv venv
   source venv/bin/activate  # Linux/Mac
   # or
   .\venv\Scripts\activate  # Windows   ```

3. **Install Dependencies**   ```bash
   pip install -r requirements.txt   ```

4. **Download Models**   ```bash
   mkdir models
   # Download models from the links above and place in models/ directory   ```

5. **Run the Application**   ```bash
   python app.py   ```

6. **Access the Interface**
   - Open your browser to `http://localhost:5000`

## Technical Details

### Memory Management
- Dynamic VRAM allocation
- Main model: 49 layers GPU-offloaded
- Memory model: 24 layers GPU-offloaded
- Automatic context pruning
- Token usage optimization

### Browser Compatibility
- Chrome/Edge (Recommended)
- Firefox
- Safari

### Security Notes
- Runs locally - no data sent to external servers
- Models run entirely on your hardware
- Conversation history stored locally

## Troubleshooting

Common issues and solutions:
- CUDA out of memory: Reduce layer offload in `persistent_memory.py`
- Slow responses: Check GPU utilization and VRAM usage
- Model loading errors: Verify model paths in `app.py`

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) first.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
