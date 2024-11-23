# Advanced Chatbot with Memory Management

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

    Install the required Python packages using `pip`:

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

## Requirements

The project relies on several Python packages to ensure functionality, performance, and maintainability. Below is a detailed list of these packages along with their purposes and installation instructions.

### `requirements.txt`

```plaintext
flask>=2.0.0
llama-cpp-python>=0.2.0
pydantic>=2.0.0
sqlite3
asyncio
numpy>=1.24.0
psutil>=5.9.0
logging
traceback
datetime
pytz>=2023.3
pathlib
os
typing
json
torch>=2.0.0
python-dotenv>=1.0.0 
```

### Package Descriptions

1. **Flask (`flask>=2.0.0`)**
    - **Description:** A lightweight WSGI web application framework used to build the backend of the chatbot application.
    - **Installation:** Automatically installed via `pip install -r requirements.txt`.

2. **Llama C++ Python Bindings (`llama-cpp-python>=0.2.0`)**
    - **Description:** Provides Python bindings for interacting with the Llama C++ library, enabling efficient execution of large language models.
    - **Installation:** Automatically installed via `pip install -r requirements.txt`.

3. **Pydantic (`pydantic>=2.0.0`)**
    - **Description:** Used for data validation and settings management using Python type annotations.
    - **Installation:** Automatically installed via `pip install -r requirements.txt`.

4. **SQLite3 (`sqlite3`)**
    - **Description:** A C-language library that implements a small, fast, self-contained SQL database engine for managing memory storage.
    - **Installation:** Comes pre-installed with Python's standard library.

5. **Asyncio (`asyncio`)**
    - **Description:** Provides infrastructure for writing single-threaded concurrent code using coroutines, facilitating asynchronous processing.
    - **Installation:** Comes pre-installed with Python's standard library.

6. **NumPy (`numpy>=1.24.0`)**
    - **Description:** A fundamental package for scientific computing with Python, used here for efficient numerical operations.
    - **Installation:** Automatically installed via `pip install -r requirements.txt`.

7. **Psutil (`psutil>=5.9.0`)**
    - **Description:** Provides an interface for retrieving information on running processes and system utilization (CPU, memory, disks, network).
    - **Installation:** Automatically installed via `pip install -r requirements.txt`.

8. **Logging (`logging`)**
    - **Description:** Facilitates tracking events that happen when some software runs, essential for debugging and monitoring.
    - **Installation:** Comes pre-installed with Python's standard library.

9. **Traceback (`traceback`)**
    - **Description:** Provides utilities for extracting, formatting, and printing stack traces of Python programs, useful for error handling.
    - **Installation:** Comes pre-installed with Python's standard library.

10. **Datetime (`datetime`)**
     - **Description:** Supplies classes for manipulating dates and times, crucial for timestamping interactions.
     - **Installation:** Comes pre-installed with Python's standard library.

11. **Pytz (`pytz>=2023.3`)**
     - **Description:** Brings the Olson timezone database into Python, allowing accurate and cross-platform timezone calculations.
     - **Installation:** Automatically installed via `pip install -r requirements.txt`.

12. **Pathlib (`pathlib`)**
     - **Description:** Offers an object-oriented approach to handling filesystem paths, enhancing code readability and maintainability.
     - **Installation:** Comes pre-installed with Python's standard library.

13. **OS (`os`)**
     - **Description:** Provides a way of using operating system dependent functionality, such as reading environment variables.
     - **Installation:** Comes pre-installed with Python's standard library.

14. **Typing (`typing`)**
     - **Description:** Supports type hints as specified by PEP 484, improving code clarity and assisting in static type checking.
     - **Installation:** Comes pre-installed with Python's standard library.

15. **JSON (`json`)**
     - **Description:** Enables parsing and generating JSON data, essential for API communication.
     - **Installation:** Comes pre-installed with Python's standard library.

16. **Torch (`torch>=2.0.0`)**
     - **Description:** A deep learning framework providing tensors and dynamic neural networks in Python with strong GPU acceleration.
     - **Installation:** Automatically installed via `pip install -r requirements.txt`.

17. **Python Dotenv (`python-dotenv>=1.0.0`)**
     - **Description:** Reads key-value pairs from a `.env` file and sets them as environment variables, aiding in configuration management.
     - **Installation:** Automatically installed via `pip install -r requirements.txt`.

### Installing Dependencies Manually

While it's recommended to install all dependencies using the provided `requirements.txt` file, you can also install each package individually using `pip`. Here's how:

```bash
pip install flask>=2.0.0
pip install llama-cpp-python>=0.2.0
pip install pydantic>=2.0.0
pip install numpy>=1.24.0
pip install psutil>=5.9.0
pip install pytz>=2023.3
pip install torch>=2.0.0
pip install python-dotenv>=1.0.0
```

*Note:* Packages like `sqlite3`, `asyncio`, `logging`, `traceback`, `datetime`, `pathlib`, `os`, `typing`, and `json` are part of Python's standard library and do not require separate installation.

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

## Acknowledgements

- **Flask:** A lightweight WSGI web application framework.
- **Llama:** An advanced language model used for generating intelligent responses.
- **SQLite:** A C-language library that implements a small, fast, self-contained SQL database engine.
- **[Replete-LLM-V2.5-Qwen-14b-GGUF](https://huggingface.co/bartowski/Replete-LLM-V2.5-Qwen-14b-GGUF):** The chosen large language model for this application.

---

This project represents a significant effort in developing a memory-enhanced chatbot system. We are committed to advancing conversational AI technologies and appreciate your interest and support.
