document.addEventListener('DOMContentLoaded', function() {
    // Initialize highlight.js with Dracula theme
    hljs.configure({
        theme: 'dracula',
        languages: [
            'python', 'javascript', 'bash', 'css', 'html', 'json',
            'typescript', 'java', 'c', 'cpp', 'csharp', 'ruby', 'go',
            'rust', 'sql', 'xml', 'yaml', 'markdown', 'shell'
        ]
    });
    
    // DOM element management
    const elements = {
        messagesContainer: null,
        userInput: null,
        sendButton: null
    };

    function refreshElements() {
        const newElements = {
            messagesContainer: document.getElementById('chat-messages'),
            userInput: document.getElementById('user-input'),
            sendButton: document.getElementById('send-button')
        };
        
        // Validate all required elements
        let missingElements = [];
        for (const [key, element] of Object.entries(newElements)) {
            if (!element) {
                missingElements.push(key);
                console.warn(`Missing element: #${key.replace(/([A-Z])/g, '-$1').toLowerCase()}`);
            }
        }
        
        if (missingElements.length > 0) {
            console.error(`Missing required elements: ${missingElements.join(', ')}`);
            return false;
        }
        
        // Update elements object
        Object.assign(elements, newElements);
        return true;
    }

    // Initial element setup
    if (!refreshElements()) {
        console.error('Failed to initialize required elements');
        return;
    }
    
    // State management
    let isProcessing = false;
    
    // Clear messages container on page load
    elements.messagesContainer.innerHTML = '';
    
    // Clear chat history on server with retry mechanism
    async function clearChatHistory(retries = 3) {
        const statusDiv = document.createElement('div');
        statusDiv.className = 'system-message';
        elements.messagesContainer.appendChild(statusDiv);
        
        for (let i = 0; i < retries; i++) {
            try {
                statusDiv.textContent = `Clearing chat history... (Attempt ${i + 1}/${retries})`;
                const response = await fetch('/clear_history', { method: 'POST' });
                
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                
                statusDiv.textContent = 'Chat history cleared successfully';
                setTimeout(() => statusDiv.remove(), 3000);
                return true;
            } catch (error) {
                console.warn(`Attempt ${i + 1}/${retries} to clear chat history failed:`, error);
                if (i === retries - 1) {
                    statusDiv.textContent = 'Failed to clear chat history. Please try again later.';
                    setTimeout(() => statusDiv.remove(), 5000);
                    return false;
                }
                statusDiv.textContent = `Retrying in ${i + 1} second(s)...`;
                await new Promise(resolve => setTimeout(resolve, 1000 * (i + 1))); // Exponential backoff
            }
        }
        return false;
    }
    
    clearChatHistory();

    const MESSAGE_CONFIG = {
        MAX_LENGTH: 4000,
        MIN_INTERVAL: 1000, // Minimum time between messages in ms
        lastMessageTime: 0
    };

    function setLoadingState(isLoading) {
        elements.sendButton.disabled = isLoading;
        elements.userInput.disabled = isLoading;
        elements.sendButton.innerHTML = isLoading ? 
            '<span class="loading-spinner"></span>' : 
            'Send';
    }

    // Cleanup management
    const cleanup = {
        timeouts: new Set(),
        eventSources: new Set(),
        
        addTimeout(timeout) {
            this.timeouts.add(timeout);
            return timeout;
        },
        
        addEventSource(eventSource) {
            this.eventSources.add(eventSource);
            return eventSource;
        },
        
        clear() {
            // Clear all timeouts
            this.timeouts.forEach(clearTimeout);
            this.timeouts.clear();
            
            // Close all event sources
            this.eventSources.forEach(es => {
                if (es.readyState !== EventSource.CLOSED) {
                    es.close();
                }
            });
            this.eventSources.clear();
        }
    };

    // Add cleanup to window unload
    window.addEventListener('unload', () => cleanup.clear());

    async function handleSubmit(event) {
        if (event) event.preventDefault();
        if (isProcessing) return;

        // Clear any existing timeouts/connections
        cleanup.clear();

        const message = elements.userInput.value.trim();
        if (!message) return;

        try {
            isProcessing = true;
            setLoadingState(true);

            // Clear input and add user message
            elements.userInput.value = '';
            const userMessageDiv = document.createElement('div');
            userMessageDiv.className = 'message user-message';
            userMessageDiv.textContent = message;
            elements.messagesContainer.appendChild(userMessageDiv);

            // Create assistant message container
            const assistantMessageDiv = document.createElement('div');
            assistantMessageDiv.className = 'message assistant-message';
            assistantMessageDiv.innerHTML = '<span class="loading-dots">Thinking</span>';
            elements.messagesContainer.appendChild(assistantMessageDiv);
            elements.messagesContainer.scrollTop = elements.messagesContainer.scrollHeight;

            // First ensure the message is saved with credentials
            const postResponse = await fetch('/chat', {
                method: 'POST',
                headers: { 
                    'Content-Type': 'application/json',
                    'X-Requested-With': 'XMLHttpRequest'
                },
                credentials: 'same-origin',
                body: JSON.stringify({ message })
            });

            if (!postResponse.ok) {
                throw new Error('Failed to save message');
            }

            // Create EventSource with credentials
            const eventSourceUrl = new URL('/chat', window.location.origin);
            eventSourceUrl.searchParams.append('message', encodeURIComponent(message));
            
            // Add timestamp to prevent caching
            eventSourceUrl.searchParams.append('_', Date.now().toString());
            
            const eventSource = new EventSource(eventSourceUrl);
            let messageContent = '';
            let hasReceivedMessage = false;

            cleanup.addEventSource(eventSource);

            eventSource.onopen = function() {
                console.log('Stream connected');
                hasReceivedMessage = false;
            };

            eventSource.onmessage = function(event) {
                try {
                    const data = JSON.parse(event.data);
                    hasReceivedMessage = true;
                    
                    // Remove loading indicator on first message
                    const loadingElement = assistantMessageDiv.querySelector('.loading-dots');
                    if (loadingElement) {
                        loadingElement.remove();
                    }

                    if (data.error) {
                        assistantMessageDiv.innerHTML = `<span class="error">Error: ${data.error}</span>`;
                        cleanup.eventSources.delete(eventSource);
                        eventSource.close();
                        return;
                    }

                    if (!data.token) return;
                    messageContent += data.token;

                    // Handle completion
                    if (data.token.includes("<|im_end|>")) {
                        messageContent = messageContent.replace("<|im_end|>", "");
                        assistantMessageDiv.innerHTML = marked.parse(messageContent);
                        assistantMessageDiv.querySelectorAll('pre code').forEach(block => {
                            hljs.highlightElement(block);
                        });
                        cleanup.eventSources.delete(eventSource);
                        eventSource.close();
                        return;
                    }

                    // Regular update
                    assistantMessageDiv.innerHTML = marked.parse(messageContent);
                    assistantMessageDiv.querySelectorAll('pre code').forEach(block => {
                        hljs.highlightElement(block);
                    });
                    elements.messagesContainer.scrollTop = elements.messagesContainer.scrollHeight;
                } catch (error) {
                    console.error('Error processing message:', error);
                    assistantMessageDiv.innerHTML = `<span class="error">Error: ${error.message}</span>`;
                    cleanup.eventSources.delete(eventSource);
                    eventSource.close();
                }
            };

            eventSource.onerror = function(error) {
                console.error('EventSource error:', error);
                
                // Only show error if we haven't received any messages
                if (!hasReceivedMessage) {
                    const errorMessage = error.target.readyState === EventSource.CLOSED 
                        ? 'Connection closed. Retrying...' 
                        : 'Connection error. Retrying...';
                        
                    if (!assistantMessageDiv.innerHTML.includes('error')) {
                        assistantMessageDiv.innerHTML = messageContent 
                            ? marked.parse(messageContent) 
                            : `<span class="error">${errorMessage}</span>`;
                    }
                    
                    // If we're still processing and haven't received any messages, retry the POST
                    if (isProcessing && !hasReceivedMessage) {
                        fetch('/chat', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ message })
                        }).catch(console.error);
                    }
                } else {
                    // If we've received messages but lost connection, close and cleanup
                    cleanup.eventSources.delete(eventSource);
                    eventSource.close();
                }
            };

        } catch (error) {
            console.error('Error:', error);
            appendMessage('system', `<span class="error">Error: ${error.message}</span>`);
        } finally {
            isProcessing = false;
            setLoadingState(false);
        }
    }
    
    function appendMessage(role, content) {
        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${role}-message`;
        messageDiv.innerHTML = content;
        elements.messagesContainer.appendChild(messageDiv);
        elements.messagesContainer.scrollTop = elements.messagesContainer.scrollHeight;
    }
    
    // Event listeners
    elements.sendButton.addEventListener('click', handleSubmit);
    
    elements.userInput.addEventListener('keypress', function(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            handleSubmit();
        }
    });
    
    // Auto-resize textarea with debouncing
    let resizeTimeout;
    elements.userInput.addEventListener('input', function() {
        clearTimeout(resizeTimeout);
        resizeTimeout = setTimeout(() => {
            this.style.height = 'auto';
            this.style.height = this.scrollHeight + 'px';
        }, 100);
    });
}); 
