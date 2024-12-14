document.addEventListener('DOMContentLoaded', function() {
    console.log("=== DOM LOADED ===");
    console.log("Searching for elements...");
    
    // Debug element search
    const elements = {
        chatWindow: document.querySelector('#chat-messages'),
        userInput: document.querySelector('#user-input'),
        sendButton: document.querySelector('#send-button'),
        clearButton: document.querySelector('#clear-all-btn'),
        allButtons: document.querySelectorAll('button')
    };
    
    // Log what we found
    console.log("Found elements:", {
        chatWindow: !!elements.chatWindow,
        userInput: !!elements.userInput,
        sendButton: !!elements.sendButton,
        clearButton: !!elements.clearButton,
        numButtons: elements.allButtons.length
    });
    
    // Log all buttons for debugging
    elements.allButtons.forEach((btn, i) => {
        console.log(`Button ${i}:`, {
            id: btn.id,
            class: btn.className,
            text: btn.textContent
        });
    });
    
    let currentThreadId = 'default';
    let currentResponse = '';
    let isProcessingCode = false;
    let partialBackticks = '';
    let isUserScrolling = false;
    let shouldAutoScroll = true;
    let headerBuffer = '';
    let isProcessingHeader = false;
    
    if (elements.chatWindow) {
        elements.chatWindow.addEventListener('wheel', function() {
            isUserScrolling = true;
            const isNearBottom = elements.chatWindow.scrollHeight - elements.chatWindow.scrollTop - elements.chatWindow.clientHeight < 50;
            shouldAutoScroll = isNearBottom;
        });
    }
    
    elements.chatWindow.addEventListener('mouseleave', function() {
        isUserScrolling = false;
    });

    function scrollToBottom() {
        if (shouldAutoScroll && !isUserScrolling) {
            elements.chatWindow.scrollTop = elements.chatWindow.scrollHeight;
        }
    }

    function addMessage(content, isUser) {
        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${isUser ? 'user-message' : 'assistant-message'}`;
        
        const contentDiv = document.createElement('div');
        contentDiv.className = 'message-content';
        contentDiv.style.textAlign = 'left';
        
        if (isUser) {
            contentDiv.textContent = content;
            messageDiv.appendChild(contentDiv);
            elements.chatWindow.appendChild(messageDiv);
        } else {
            if (!content.trim()) return;
            
            try {
                console.log("=== PROCESSING MESSAGE ===");
                console.log("Raw content:", content);
                const rendered = processMarkdown(content);
                contentDiv.innerHTML = rendered;
                
                // Check if there's already an assistant message
                const existingAssistant = elements.chatWindow.querySelector('.assistant-message');
                if (existingAssistant) {
                    existingAssistant.remove();
                }
                
                messageDiv.appendChild(contentDiv);
                elements.chatWindow.appendChild(messageDiv);
            } catch (e) {
                console.error("Markdown parsing failed:", e);
                contentDiv.textContent = content;
                messageDiv.appendChild(contentDiv);
                elements.chatWindow.appendChild(messageDiv);
            }
        }
        
        scrollToBottom();
        
        if (!isUser) {
            messageDiv.querySelectorAll('pre code:not(.highlighted)').forEach((block) => {
                hljs.highlightElement(block);
                block.classList.add('highlighted');
            });
        }
    }

    function processStreamingText(text) {
        if (text.includes('Token:') || text.includes('Raw chunk:')) {
            return;
        }
        
        // Handle code block start/end
        if (text === '```') {
            if (!isProcessingCode) {
                // Start new code block
                isProcessingCode = true;
                currentResponse += text;
                partialBackticks = '```';
                headerBuffer = '';
            } else {
                // End current code block
                isProcessingCode = false;
                currentResponse += text;
                partialBackticks = '';
            }
            return;
        }
        
        // Handle code block headers
        if (partialBackticks === '```') {
            headerBuffer += text;
            
            // Check if we have a complete language header
            if (/^[\w-]+:?[\w\/./-]*$/i.test(headerBuffer)) {
                currentResponse += headerBuffer + '\n';
                partialBackticks = '';
                headerBuffer = '';
                return;
            }
            return;  // Keep buffering header
        }
        
        // Add text to response
        currentResponse += text;
        updateAssistantMessage(currentResponse);
    }

    function processMarkdown(content) {
        // First pass: Process regular markdown outside of code blocks
        let processedContent = content;
        
        // Handle code blocks specially to preserve formatting
        const codeBlockRegex = /```([\w-]*:?[\w\/.-]*)\n([\s\S]*?)```/g;
        processedContent = processedContent.replace(codeBlockRegex, (match, lang, code) => {
            // Preserve exact whitespace and newlines in code
            code = code.trimEnd();  // Only trim trailing whitespace
            return `<pre><code class="language-${lang}">${code}</code></pre>`;
        });
        
        // Process remaining markdown
        processedContent = marked.parse(processedContent);
        
        return `<div class="markdown-body">${processedContent}</div>`;
    }

    function updateAssistantMessage(content) {
        let assistantMessages = document.getElementsByClassName('assistant-message');
        
        if (assistantMessages.length === 0) {
            // Create new message
            const messageDiv = document.createElement('div');
            messageDiv.className = 'message assistant-message';
            
            const contentDiv = document.createElement('div');
            contentDiv.className = 'message-content';
            contentDiv.style.textAlign = 'left';
            
            try {
                console.log("=== PROCESSING CONTENT ===");
                console.log("Raw content:", content);
                const rendered = processMarkdown(content);
                console.log("Processed content:", rendered);
                contentDiv.innerHTML = rendered;
                
                // Apply syntax highlighting
                contentDiv.querySelectorAll('pre code').forEach((block) => {
                    hljs.highlightElement(block);
                });
                
            } catch (e) {
                console.error("Content processing failed:", e);
                contentDiv.textContent = content;
            }
            
            messageDiv.appendChild(contentDiv);
            
            // Simply append to chat window - no special insertion logic
            elements.chatWindow.appendChild(messageDiv);
        } else {
            // Update existing message
            const lastMessage = assistantMessages[assistantMessages.length - 1];
            const contentDiv = lastMessage.querySelector('.message-content');
            if (contentDiv) {
                try {
                    console.log("=== UPDATING MARKDOWN ===");
                    console.log("Updated content:", content);
                    
                    const newRendered = processMarkdown(content);
                    if (contentDiv.innerHTML !== newRendered) {
                        contentDiv.innerHTML = newRendered;
                        
                        // Re-apply syntax highlighting
                        contentDiv.querySelectorAll('pre code').forEach((block) => {
                            hljs.highlightElement(block);
                        });
                    }
                } catch (e) {
                    console.error("Markdown update failed:", e);
                    contentDiv.textContent = content;
                }
            }
        }
        
        scrollToBottom();
    }

    async function sendMessage() {
        const message = elements.userInput.value.trim();
        if (!message) return;
        
        // Clear input
        elements.userInput.value = '';
        
        try {
            // Add user message first
            const userMessageDiv = document.createElement('div');
            userMessageDiv.className = 'message user-message';
            const userContentDiv = document.createElement('div');
            userContentDiv.className = 'message-content';
            userContentDiv.style.textAlign = 'left';
            userContentDiv.textContent = message;
            userMessageDiv.appendChild(userContentDiv);
            elements.chatWindow.appendChild(userMessageDiv);
            scrollToBottom();
            
            // Create a new assistant message container
            const assistantMessageDiv = document.createElement('div');
            assistantMessageDiv.className = 'message assistant-message';
            const assistantContentDiv = document.createElement('div');
            assistantContentDiv.className = 'message-content';
            assistantContentDiv.style.textAlign = 'left';
            assistantMessageDiv.appendChild(assistantContentDiv);
            elements.chatWindow.appendChild(assistantMessageDiv);
            
            // Make API call
            const response = await fetch('/chat', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    message: message,
                    thread_id: currentThreadId
                })
            });
            
            currentResponse = '';
            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let buffer = '';
            
            while (true) {
                const {value, done} = await reader.read();
                if (done) break;
                
                const chunk = decoder.decode(value, {stream: true});
                buffer += chunk;
                
                const messages = buffer.split('\n\n');
                buffer = messages.pop();
                
                for (const msg of messages) {
                    if (msg.startsWith('data: ')) {
                        try {
                            const data = JSON.parse(msg.slice(6));
                            
                            if (data.text) {
                                currentResponse += data.text;
                                assistantContentDiv.innerHTML = processMarkdown(currentResponse);
                                // Apply syntax highlighting to new code blocks
                                assistantContentDiv.querySelectorAll('pre code:not(.highlighted)').forEach((block) => {
                                    hljs.highlightElement(block);
                                    block.classList.add('highlighted');
                                });
                                scrollToBottom();
                            }
                        } catch (e) {
                            console.error('Error processing message:', e);
                        }
                    }
                }
            }
            
        } catch (error) {
            console.error('Stream error:', error);
            const errorDiv = document.createElement('div');
            errorDiv.className = 'message system-message';
            errorDiv.textContent = 'Error: Failed to get response';
            elements.chatWindow.appendChild(errorDiv);
        }
    }

    // Add clear all button listener
    if (elements.clearButton) {
        elements.clearButton.addEventListener('click', clearAllConversations);
    } else {
        console.error('Clear button not found');
    }

    // Initialize event listeners after DOM is ready
    if (elements.sendButton && elements.userInput) {
        elements.sendButton.addEventListener('click', sendMessage);
        elements.userInput.addEventListener('keypress', function(e) {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                sendMessage();
            }
        });
    } else {
        console.error('Required chat elements not found:', {
            sendButton: !!elements.sendButton,
            userInput: !!elements.userInput,
            html: document.body.innerHTML
        });
    }
});

function clearAllConversations() {
    // Show loading state
    const clearButton = document.querySelector('#clear-all-btn');
    const originalText = clearButton.textContent;
    clearButton.textContent = 'Clearing...';
    clearButton.disabled = true;
    
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
            document.querySelector('#chat-messages').innerHTML = '';
            
            // Reset state
            currentResponse = '';
            isProcessingCode = false;
            partialBackticks = '';
            
            // Clear input
            document.querySelector('#user-input').value = '';
            
            // Show success message
            clearButton.textContent = 'Cleared!';
            setTimeout(() => {
                clearButton.textContent = originalText;
            }, 2000);
        } else {
            console.error('Failed to clear conversations:', data.message);
            clearButton.textContent = 'Error!';
            setTimeout(() => {
                clearButton.textContent = originalText;
            }, 2000);
        }
    })
    .catch(error => {
        console.error('Error:', error);
        clearButton.textContent = 'Error!';
        setTimeout(() => {
            clearButton.textContent = originalText;
        }, 2000);
    })
    .finally(() => {
        clearButton.disabled = false;
    });
}
