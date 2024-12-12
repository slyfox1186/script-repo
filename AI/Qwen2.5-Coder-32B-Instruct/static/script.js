document.addEventListener('DOMContentLoaded', function() {
    const messagesContainer = document.getElementById('chat-messages');
    const userInput = document.getElementById('user-input');
    const sendButton = document.getElementById('send-btn');

    let currentResponse = '';
    let isProcessingCode = false;
    let partialBackticks = '';
    let isUserScrolling = false;
    let shouldAutoScroll = true;
    
    messagesContainer.addEventListener('wheel', function() {
        isUserScrolling = true;
        const isNearBottom = messagesContainer.scrollHeight - messagesContainer.scrollTop - messagesContainer.clientHeight < 50;
        shouldAutoScroll = isNearBottom;
    });
    
    messagesContainer.addEventListener('mouseleave', function() {
        isUserScrolling = false;
    });

    function scrollToBottom() {
        if (shouldAutoScroll && !isUserScrolling) {
            messagesContainer.scrollTop = messagesContainer.scrollHeight;
        }
    }

    function addMessage(content, isUser) {
        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${isUser ? 'user-message' : 'assistant-message'}`;
        
        if (isUser) {
            const assistantMessages = document.getElementsByClassName('assistant-message');
            if (assistantMessages.length > 0) {
                const lastAssistant = assistantMessages[assistantMessages.length - 1];
                if (!lastAssistant.textContent.trim()) {
                    lastAssistant.remove();
                }
            }
            messageDiv.style.whiteSpace = 'pre-wrap';
            messageDiv.textContent = content;
            shouldAutoScroll = true;
        } else {
            messageDiv.innerHTML = content;
        }
        
        messagesContainer.appendChild(messageDiv);
        scrollToBottom();
        
        if (!isUser) {
            messageDiv.querySelectorAll('pre code').forEach((block) => {
                hljs.highlightElement(block);
            });
        }
    }

    function processStreamingText(text) {
        if (text.includes('Token:') || text.includes('Raw chunk:')) {
            return;
        }
        
        // If we're waiting for language identifier and get it, skip it
        if (partialBackticks === '```' && (text === 'bash' || /^[a-z]+$/.test(text))) {
            return;
        }
        
        // If we get backticks, store them and wait
        if (text === '```' && !isProcessingCode) {
            isProcessingCode = true;
            currentResponse += '<pre><code>';
            partialBackticks = '```';
            return;
        }
        
        // If we get closing backticks, handle them
        if (isProcessingCode && text.includes('```')) {
            isProcessingCode = false;
            currentResponse += '</code></pre>';
            text = text.replace('```', '');
            partialBackticks = '';
            return;
        }
        
        // Process normal text
        if (isProcessingCode) {
            currentResponse += text
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;');
        } else {
            currentResponse += text
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/\n/g, '<br>');
        }
        
        partialBackticks = '';
    }

    function updateAssistantMessage(content) {
        let assistantMessages = document.getElementsByClassName('assistant-message');
        if (assistantMessages.length > 0) {
            const lastMessage = assistantMessages[assistantMessages.length - 1];
            lastMessage.innerHTML = content;
            
            lastMessage.querySelectorAll('pre code').forEach((block) => {
                hljs.highlightElement(block);
            });
            
            scrollToBottom();
        } else {
            addMessage(content, false);
        }
    }

    function sendMessage() {
        const message = userInput.value.trim();
        if (!message) return;

        console.log('\n=== Sending Message ===');
        console.log('Message:', message);

        currentResponse = '';
        isProcessingCode = false;
        partialBackticks = '';

        addMessage(message, true);
        userInput.value = '';

        addMessage('', false);

        fetch('/chat', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ message: message })
        }).then(response => {
            console.log('Got response:', response);
            const reader = response.body.getReader();
            const decoder = new TextDecoder();

            function readStream() {
                reader.read().then(({done, value}) => {
                    if (done) {
                        console.log('Stream complete');
                        return;
                    }

                    const chunk = decoder.decode(value);
                    console.log('Received chunk:', chunk);
                    const lines = chunk.split('\n');
                    
                    lines.forEach(line => {
                        if (line.startsWith('data: ')) {
                            try {
                                const data = JSON.parse(line.slice(6));
                                console.log('Parsed data:', data);
                                if (data.text) {
                                    console.log('Processing text:', data.text);
                                    processStreamingText(data.text);
                                    updateAssistantMessage(currentResponse);
                                }
                            } catch (e) {
                                console.error('Error processing chunk:', e);
                                console.error('Raw line:', line);
                            }
                        }
                    });

                    readStream();
                }).catch(error => {
                    console.error('Stream read error:', error);
                });
            }

            readStream();
        }).catch(error => {
            console.error('Fetch error:', error);
        });
    }

    // Add clear all button listener
    const clearAllBtn = document.getElementById('clear-all-btn');
    clearAllBtn.addEventListener('click', function() {
        // Show loading state
        const originalText = clearAllBtn.textContent;
        clearAllBtn.textContent = 'Clearing...';
        clearAllBtn.disabled = true;

        fetch('/clear_all_threads', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            }
        })
        .then(response => response.json())
        .then(data => {
            console.log('Clear response:', data);
            if (data.status === 'success') {
                // Clear UI messages
                const messagesContainer = document.getElementById('chat-messages');
                messagesContainer.innerHTML = '';
                
                // Reset state
                currentResponse = '';
                isProcessingCode = false;
                partialBackticks = '';
                
                // Clear input
                document.getElementById('user-input').value = '';
                
                // Show success message
                clearAllBtn.textContent = 'Cleared!';
                setTimeout(() => {
                    clearAllBtn.textContent = originalText;
                }, 2000);
            } else {
                console.error('Failed to clear conversations:', data.message);
                clearAllBtn.textContent = 'Error!';
                setTimeout(() => {
                    clearAllBtn.textContent = originalText;
                }, 2000);
            }
        })
        .catch(error => {
            console.error('Error:', error);
            clearAllBtn.textContent = 'Error!';
            setTimeout(() => {
                clearAllBtn.textContent = originalText;
            }, 2000);
        })
        .finally(() => {
            clearAllBtn.disabled = false;
        });
    });

    sendButton.addEventListener('click', sendMessage);
    userInput.addEventListener('keypress', function(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMessage();
        }
    });
});
