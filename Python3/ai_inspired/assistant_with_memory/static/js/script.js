// Path: static/js/script.js
class ChatInterface {
    constructor() {
        // Initialize DOM elements with correct IDs from HTML
        this.messageContainer = document.querySelector('.chat-container .chat-messages');
        this.userInput = document.getElementById('userInput');
        this.sendButton = document.getElementById('sendButton');
        this.errorContainer = document.getElementById('error-container');
        
        // Initialize session management
        this.initializeSession();
        
        // Set up event listeners
        this.setupEventListeners();
        
        // Initialize marked.js for markdown rendering
        marked.setOptions({
            highlight: function(code, language) {
                if (language && hljs.getLanguage(language)) {
                    return hljs.highlight(code, { language }).value;
                }
                return code;
            },
            breaks: true
        });
        
        // Debug mode for development
        this.debug = true;
        this.log("Chat interface initialized");
        
        // Verify DOM elements
        if (!this.messageContainer) {
            this.showError("Chat messages container not found");
        }
        if (!this.userInput) {
            this.showError("User input element not found");
        }
        if (!this.sendButton) {
            this.showError("Send button not found");
        }
    }

    showError(message) {
        if (this.errorContainer) {
            this.errorContainer.textContent = message;
            this.errorContainer.style.display = 'block';
        }
        this.log("Error:", message);
    }

    initializeSession() {
        // Initialize or restore session data
        this.sessionId = localStorage.getItem('sessionId') || crypto.randomUUID();
        this.userId = localStorage.getItem('userId') || crypto.randomUUID();
        this.threadId = localStorage.getItem('threadId') || crypto.randomUUID();
        this.messageCount = parseInt(localStorage.getItem('messageCount') || '0');
        this.lastSummaryAt = parseInt(localStorage.getItem('lastSummaryAt') || '0');
        
        // Save session data
        localStorage.setItem('sessionId', this.sessionId);
        localStorage.setItem('userId', this.userId);
        localStorage.setItem('threadId', this.threadId);
        localStorage.setItem('messageCount', this.messageCount.toString());
        localStorage.setItem('lastSummaryAt', this.lastSummaryAt.toString());
        
        this.log("Session initialized", {
            sessionId: this.sessionId,
            userId: this.userId,
            threadId: this.threadId
        });
    }

    setupEventListeners() {
        if (this.sendButton) {
            this.sendButton.addEventListener('click', () => this.sendMessage());
        }
        
        if (this.userInput) {
            this.userInput.addEventListener('keypress', (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    this.sendMessage();
                }
            });
        }
    }

    async sendMessage() {
        if (!this.messageContainer || !this.userInput) {
            this.showError("Required DOM elements not found");
            return;
        }

        const message = this.userInput.value.trim();
        if (!message) return;

        try {
            // Clear input and show user message
            this.userInput.value = '';
            this.appendMessage(message, true);

            // Create container for AI response
            const aiMessageContainer = document.createElement('div');
            aiMessageContainer.className = 'message ai-message';
            this.messageContainer.appendChild(aiMessageContainer);

            // Create EventSource for SSE
            const response = await fetch('/api/message', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-Thread-Id': this.threadId,
                    'X-User-Id': this.userId,
                    'X-Session-Id': this.sessionId,
                    'X-Message-Count': this.messageCount.toString(),
                    'X-Last-Summary': this.lastSummaryAt.toString()
                },
                body: JSON.stringify({ message })
            });

            // Create a ReadableStream from the response
            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let aiResponse = '';

            while (true) {
                const { done, value } = await reader.read();
                if (done) break;

                // Decode the chunk and process SSE format
                const chunk = decoder.decode(value);
                const lines = chunk.split('\n');

                for (const line of lines) {
                    if (line.startsWith('data: ')) {
                        try {
                            const data = JSON.parse(line.slice(6));
                            
                            switch (data.type) {
                                case 'start':
                                    this.log("Stream started");
                                    break;
                                    
                                case 'token':
                                    if (data.token) {
                                        aiResponse += data.token;
                                        this.updateAIResponse(aiResponse, aiMessageContainer);
                                    }
                                    break;
                                    
                                case 'done':
                                    this.messageCount++;
                                    localStorage.setItem('messageCount', this.messageCount.toString());
                                    this.log("Stream completed");
                                    break;
                                    
                                case 'error':
                                    throw new Error(data.error);
                            }
                        } catch (e) {
                            this.log("Error parsing SSE data", e);
                            aiMessageContainer.textContent = "Error: Unable to process response";
                        }
                    }
                }
            }

        } catch (error) {
            this.log("Error in sendMessage", error);
            this.appendMessage('Sorry, there was an error processing your request.', false);
        }
    }

    appendMessage(content, isUser = false) {
        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${isUser ? 'user-message' : 'ai-message'}`;
        messageDiv.textContent = content;
        this.messageContainer.appendChild(messageDiv);
        this.scrollToBottom();
    }

    updateAIResponse(content, messageElement) {
        try {
            // Render markdown and sanitize
            const renderedContent = marked.parse(content);
            const sanitizedContent = this.sanitizeHTML(renderedContent);
            messageElement.innerHTML = sanitizedContent;

            // Apply syntax highlighting
            messageElement.querySelectorAll('pre code').forEach((block) => {
                hljs.highlightElement(block);
            });

            this.scrollToBottom();
        } catch (error) {
            this.log("Error updating AI response", error);
            messageElement.textContent = content;
        }
    }

    sanitizeHTML(html) {
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        
        // Remove potentially dangerous elements and attributes
        const sanitize = (node) => {
            if (node.nodeType === Node.ELEMENT_NODE) {
                // Remove all attributes except those explicitly allowed
                const allowedAttributes = ['class', 'id'];
                Array.from(node.attributes).forEach(attr => {
                    if (!allowedAttributes.includes(attr.name)) {
                        node.removeAttribute(attr.name);
                    }
                });
                
                // Recursively sanitize child nodes
                Array.from(node.childNodes).forEach(sanitize);
            }
            return node;
        };
        
        sanitize(doc.body);
        return doc.body.innerHTML;
    }

    scrollToBottom() {
        if (this.messageContainer) {
            this.messageContainer.scrollTop = this.messageContainer.scrollHeight;
        }
    }

    log(message, data = null) {
        if (this.debug) {
            if (data) {
                console.log(`[Chat] ${message}:`, data);
            } else {
                console.log(`[Chat] ${message}`);
            }
        }
    }

    clearSession() {
        localStorage.clear();
        this.initializeSession();
        if (this.messageContainer) {
            this.messageContainer.innerHTML = '';
        }
        this.log("Session cleared");
    }
}

// Initialize chat interface when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.chatInterface = new ChatInterface();
});