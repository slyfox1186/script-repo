import socketio
from llama_cpp import Llama

def load_model():
    """Load the LLM from the GGUF file."""
    model_path = "./models/name.gguf"  # Path to DeepSeek-R1-Distill-Qwen-14B-GGUF
    # Load the model; adjust n_ctx if needed for longer contexts
    model = Llama(model_path, n_ctx=2048)
    return model

def generate_response(model, history):
    """Generate a response based on the conversation history."""
    # Extract the debate query from the first history entry
    query = history[0].replace("Query: ", "")
    # Combine previous statements (if any)
    previous_statements = "\n".join(history[1:]) if len(history) > 1 else "None yet"
    # Construct the prompt with a debate instruction
    prompt = (
        "You are participating in a debate. Respond to the following topic and previous statements "
        "in a concise, argumentative manner.\n\n"
        f"Debate Topic: {query}\n"
        f"Previous Statements:\n{previous_statements}\n"
        "Your Response:"
    )
    # Generate response with the model
    response = model.create_completion(
        prompt,
        max_tokens=None,
        temperature=0.6,
        top_p=0.95,
        top_k=40,
        repeat_penalty=1.2,
        stream=True,
        echo=False,
        stop=["<｜User｜>", "<｜Assistant｜>"]
    )
    # Extract and clean the generated text
    return response['choices'][0]['text'].strip()

# Initialize SocketIO client
sio = socketio.Client()

# Load the model once at startup
model = load_model()

@sio.event
def connect():
    """Handle connection to the server."""
    print("Connected to server")

@sio.event
def generate_response(data):
    """Receive history from server and send back a response."""
    history = data['history']
    response = generate_response(model, history)
    sio.emit('response', {'response': response})

if __name__ == '__main__':
    server_url = 'http://<server_ip>:5000'  # Replace with the server's IP address
    sio.connect(server_url)
    sio.wait()  # Keep the client running
