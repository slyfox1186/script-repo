```markdown
# Advanced Chatbot with Memory Management

![Project Logo](static/logo.png)

## Overview

Welcome to the **Advanced Chatbot with Memory Management** repository. This project presents a sophisticated chatbot application built using Flask, leveraging cutting-edge large language models (LLMs) to deliver intelligent and context-aware conversations. Designed with a strong emphasis on memory management, this system ensures persistent and relevant interactions, making it suitable for both academic research and real-world applications.

## Features

- **Intelligent Conversations:** Utilizes state-of-the-art LLMs to generate coherent and contextually appropriate responses.
- **Memory Management:** Implements a robust memory system to retain and utilize past interactions, enhancing the chatbot's ability to provide personalized experiences.
- **Scalable Architecture:** Built with Flask, ensuring scalability and ease of deployment.
- **Asynchronous Processing:** Employs asynchronous programming paradigms for efficient handling of concurrent user interactions.
- **Comprehensive Logging:** Integrated logging mechanisms for monitoring, debugging, and performance analysis.
- **Database Integrity:** Ensures data consistency and integrity with a well-structured SQLite backend.
- **Modular Design:** Organized into distinct modules for chat management, memory handling, and model interfacing, facilitating maintenance and future enhancements.

## Architecture

The application is structured into several key components:

1. **`app.py`:** The main Flask application that handles HTTP requests, manages routes, and orchestrates interactions between different modules.
2. **`chat/`:** Contains the `ChatManager` responsible for managing chat sessions, processing user messages, and interfacing with the LLM.
3. **`memory/`:** Manages user memories with modules like `MemoryManager`, `SQLiteStore`, and memory types definitions to ensure persistent and relevant data storage.
4. **`models/`:** Houses the `ChatLLM` class, which interfaces with the chosen large language model (e.g., Llama) to generate responses.
5. **`config.py`:** Centralized configuration settings, including model paths, memory directories, and Flask settings.

## Installation

Follow the steps below to set up the project locally:

### Prerequisites

- **Python 3.8 or higher**
- **Git**
- **Virtual Environment (optional but recommended)**

### Steps

1. **Clone the Repository**

   ```bash
   git clone https://github.com/yourusername/advanced-chatbot-memory.git
   cd advanced-chatbot-memory
   ```

2. **Set Up a Virtual Environment**

   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```

3. **Install Dependencies**

   ```bash
   pip install -r requirements.txt
   ```

4. **Configure the Application**

   - **Model Setup:**
     - Ensure you have downloaded the required LLM model [`Replete-LLM-V2.5-Qwen-14b-GGUF`](https://huggingface.co/bartowski/Replete-LLM-V2.5-Qwen-14b-GGUF) and placed it in the `models/` directory.
     - If using a different model, update the `CHOSEN_MODEL` variable in `config.py` accordingly.

   - **Memory Directory:**
     - The application uses a SQLite database for memory storage located at `memory_store/memory.db`. Ensure the `memory_store/` directory exists or is created automatically.

5. **Run Database Migrations**

   The application initializes the database schema automatically on the first run. No manual migrations are required.

6. **Start the Application**

   ```bash
   python app.py
   ```

   The application will be accessible at `http://localhost:5000`.

## Usage

- **Home Page:** Navigate to `http://localhost:5000` to access the chatbot interface.
- **API Endpoint:** Send POST requests to `/api/message` with a JSON payload containing the user message to interact programmatically.

### Example API Request

```bash
POST /api/message
Content-Type: application/json
X-User-Id: user123

{
  "message": "Hello, how are you?"
}
```

### Response

The API responds with a Server-Sent Events (SSE) stream containing the chatbot's response tokens, allowing for real-time streaming of messages.

## Contributing

We welcome contributions from the community to enhance the functionality and performance of this chatbot application. Please follow the guidelines below:

1. **Fork the Repository**
2. **Create a Feature Branch**

   ```bash
   git checkout -b feature/YourFeature
   ```

3. **Commit Your Changes**

   ```bash
   git commit -m "Add Your Feature"
   ```

4. **Push to the Branch**

   ```bash
   git push origin feature/YourFeature
   ```

5. **Create a Pull Request**

## License

This project is licensed under the [MIT License](LICENSE).

## Acknowledgements

- **Flask:** A lightweight WSGI web application framework.
- **Llama:** An advanced language model used for generating intelligent responses.
- **SQLite:** A C-language library that implements a small, fast, self-contained SQL database engine.
- **[Replete-LLM-V2.5-Qwen-14b-GGUF](https://huggingface.co/bartowski/Replete-LLM-V2.5-Qwen-14b-GGUF):** The chosen large language model for this application.

## Contact

For any inquiries or support, please contact [your.email@example.com](mailto:your.email@example.com).

---

*This project represents a significant effort in developing a memory-enhanced chatbot system. We are committed to advancing conversational AI technologies and appreciate your interest and support.*
```