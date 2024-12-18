const DEBUG = true;

const HIGHLIGHT_OPTIONS = {
    theme: 'dracula',
    ignoreIllegals: true
};

function log(...args) {
    if (DEBUG) {
        console.log(`[${new Date().toISOString()}]`, ...args);
    }
}

// Global variables and configuration
const scrollDebounceTime = 100;  // ms
let scrollTimeout = null;
let lastScrollHeight = 0;
let userScrolledUp = false;

// Global state and utilities
const state = {
    currentResponseController: null,
    isProcessing: false,
    elements: null,
    currentThreadId: 'default',
    streamBuffer: {
        raw: '',           
        content: '',       
        isStreaming: false,
        isProcessingCode: false,
        codeBlockDepth: 0,  
        contentParts: {
            text: [],      
            math: [],      
            code: [],      
            list: []       
        },
        partial: {
            math: '',
            code: '',
            list: ''
        },
        messageElement: null
    },
    streaming: {
        active: false,
        softTransition: false,
        interruptedBy: null,
        allowInterruption: true
    },
    requests: {
        current: null,
        pending: null,
        processingCount: 0,
        maxConcurrent: 1
    }
};

// Initialize elements after DOM load
function initializeElements() {
    state.elements = {
        chatWindow: document.querySelector('#chat-messages'),
        userInput: document.querySelector('#user-input'),
        sendButton: document.querySelector('#send-button'),
        clearButton: document.querySelector('#clear-all-btn'),
        allButtons: document.querySelectorAll('button')
    };
    
    // Debug element search
    console.log("Found elements:", {
        chatWindow: !!state.elements.chatWindow,
        userInput: !!state.elements.userInput,
        sendButton: !!state.elements.sendButton,
        clearButton: !!state.elements.clearButton,
        numButtons: state.elements.allButtons.length
    });
}

// Add FlowLogger before DOMContentLoaded
const FlowLogger = {
    depth: 0,
    log(message, type = 'info') {
        const indent = '  '.repeat(this.depth);
        const timestamp = new Date().toISOString();
        console.log(`${timestamp} [${type.toUpperCase()}] ${indent}${message}`);
    },
    start(message) {
        this.log(`⮕ START: ${message}`);
        this.depth++;
    },
    end(message) {
        this.depth--;
        this.log(`⮜ END: ${message}`);
    },
    error(message, error) {
        this.log(`❌ ERROR: ${message} - ${error.message}`, 'error');
        console.error(error);
    }
};

// Add processMarkdown before DOMContentLoaded
async function processMarkdown(content) {
    try {
        if (!content) return '';

        // First process any math expressions
        const processed = await MathProcessor.processText(content);
        
        // Process markdown with marked
        if (processed && marked) {
            return marked.parse(processed);
        }
        
        return content;
    } catch (e) {
        console.error('Error in processMarkdown:', e);
        return content || '';
    }
}

// Add MathProcessor before DOMContentLoaded
const MathProcessor = {
    placeholders: new Map(),
    counter: 0,

    async processText(text) {
        FlowLogger.start('MathProcessor.processText');
        
        if (!text) return '';
        
        // First protect all math expressions
        const mathRegex = /(\$\$[\s\S]*?\$\$|\$[^\$\n]*?\$|\\\[[\s\S]*?\\\]|\\\([^\)]*?\\\))/g;
        let protectedText = text;
        const expressions = [];
        
        // Find all math expressions and replace with placeholders
        let match;
        while ((match = mathRegex.exec(text)) !== null) {
            const id = `MATH_${this.counter++}`;
            const expr = match[0];
            expressions.push({
                id,
                expression: expr,
                isBlock: expr.startsWith('$$') || expr.startsWith('\\['),
                index: match.index
            });
            // Create a placeholder that won't be affected by markdown processing
            protectedText = protectedText.slice(0, match.index) + 
                          `@@MATH_PLACEHOLDER_${id}@@` + 
                          protectedText.slice(match.index + expr.length);
            mathRegex.lastIndex = match.index + `@@MATH_PLACEHOLDER_${id}@@`.length;
        }
        
        // Process markdown with protected math expressions
        let processed = marked.parse(protectedText);
        
        // Restore math expressions in order
        for (const {id, expression, isBlock} of expressions) {
            const placeholder = `@@MATH_PLACEHOLDER_${id}@@`;
            const rendered = await this.renderMathExpression(expression, isBlock);
            processed = processed.replace(placeholder, rendered);
        }
        
        // Apply syntax highlighting to code blocks
        const tempDiv = document.createElement('div');
        tempDiv.innerHTML = processed;
        tempDiv.querySelectorAll('pre code').forEach((block) => {
            hljs.highlightElement(block);
        });
        
        FlowLogger.end('MathProcessor.processText');
        return tempDiv.innerHTML;
    },

    async renderMathExpression(mathExpr, isBlock) {
        const tempDiv = document.createElement('div');
        tempDiv.style.visibility = 'hidden';
        document.body.appendChild(tempDiv);
        
        try {
            // Clean up the math expression
            let cleanMath = mathExpr.trim();
            if (cleanMath.startsWith('$') && cleanMath.endsWith('$')) {
                cleanMath = cleanMath.slice(1, -1);
            } else if (cleanMath.startsWith('$$') && cleanMath.endsWith('$$')) {
                cleanMath = cleanMath.slice(2, -2);
            } else if (cleanMath.startsWith('\\[') && cleanMath.endsWith('\\]')) {
                cleanMath = cleanMath.slice(2, -2);
            } else if (cleanMath.startsWith('\\(') && cleanMath.endsWith('\\)')) {
                cleanMath = cleanMath.slice(2, -2);
            }

            // Add proper delimiters back with correct wrapper
            if (isBlock) {
                tempDiv.innerHTML = `<div class="display-math">\\[${cleanMath}\\]</div>`;
            } else {
                tempDiv.innerHTML = `<span class="inline-math">\\(${cleanMath}\\)</span>`;
            }
            
            // Render math
            await MathJax.typesetPromise([tempDiv]);
            
            return tempDiv.innerHTML;
        } finally {
            document.body.removeChild(tempDiv);
        }
    }
};

function smoothScrollToBottom() {
    const chatWindow = document.querySelector('#chat-messages');
    if (!chatWindow || userScrolledUp) return;

    // Only scroll if content height changed
    const newScrollHeight = chatWindow.scrollHeight;
    if (newScrollHeight === lastScrollHeight) return;
    lastScrollHeight = newScrollHeight;

    // Clear existing timeout
    if (scrollTimeout) clearTimeout(scrollTimeout);

    // Debounce the scroll
    scrollTimeout = setTimeout(() => {
        const scrollTarget = chatWindow.scrollHeight - chatWindow.clientHeight;
        chatWindow.scrollTo({
            top: scrollTarget,
            behavior: 'smooth'
        });
    }, scrollDebounceTime);
}

// Add scroll event listener outside DOMContentLoaded
document.addEventListener('scroll', function(e) {
    if (e.target.id === 'chat-messages') {
        const chatWindow = e.target;
        const isNearBottom = chatWindow.scrollHeight - chatWindow.scrollTop - chatWindow.clientHeight < 100;
        const scrollingUp = chatWindow.lastScrollTop > chatWindow.scrollTop;
        chatWindow.lastScrollTop = chatWindow.scrollTop;

        if (scrollingUp) {
            userScrolledUp = true;
        } else if (isNearBottom) {
            userScrolledUp = false;
        }
    }
}, true);

// Update sendMessage to handle interruptions gracefully
async function sendMessage() {
    FlowLogger.start('sendMessage()');
    const message = state.elements.userInput.value.trim();
    
    if (!message) {
        FlowLogger.log('Empty message, returning');
        FlowLogger.end('sendMessage()');
        return;
    }

    // If already processing, handle as interruption
    if (state.streaming.active) {
        FlowLogger.log('Interrupting current stream');
        state.streaming.interruptedBy = message;
        state.streaming.softTransition = true;
        
        if (state.currentResponseController) {
            state.currentResponseController.abort();
        }
        
        // Clear input immediately
        state.elements.userInput.value = '';
        return;
    }

    // Start new request
    try {
        state.streaming.active = true;
        state.currentResponseController = new AbortController();
        state.isProcessing = true;

        // Add user message to UI
        await addMessage(message, true);
        
        // Initialize or reset stream buffer
        state.streamBuffer.content = '';
        state.streamBuffer.raw = '';
        state.streamBuffer.isProcessingCode = false;
        state.streamBuffer.codeBlockDepth = 0;
        state.streamBuffer.messageElement = null;
        state.streamBuffer.isStreaming = true;

        // Process request
        const response = await fetch('/chat', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                message: message,
                thread_id: state.currentThreadId
            }),
            signal: state.currentResponseController.signal
        });

        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        
        const messageDiv = await addMessage('', false);
        state.streamBuffer.messageElement = messageDiv.querySelector('.message-content');
        
        const reader = response.body.getReader();
        
        while (state.streamBuffer.isStreaming) {
            const {done, value} = await reader.read();
            
            if (done || state.streaming.softTransition) {
                FlowLogger.log('Stream ending: ' + (done ? 'complete' : 'interrupted'));
                break;
            }

            const chunk = new TextDecoder().decode(value);
            await processStreamingContent(chunk);
        }

    } catch (error) {
        if (error.name === 'AbortError') {
            FlowLogger.log('Stream interrupted by new request');
        } else {
            FlowLogger.error('Message processing failed', error);
            await addMessage('Error: Failed to send message', false);
        }
    } finally {
        // Cleanup
        state.isProcessing = false;
        state.currentResponseController = null;
        state.streamBuffer.isStreaming = false;
        state.streaming.active = false;

        // Handle any interrupting message
        if (state.streaming.interruptedBy) {
            const nextMessage = state.streaming.interruptedBy;
            state.streaming.interruptedBy = null;
            state.streaming.softTransition = false;
            
            // Process interrupting message after brief delay
            setTimeout(() => {
                state.elements.userInput.value = nextMessage;
                sendMessage();
            }, 50);
        }
    }
    
    FlowLogger.end('sendMessage()');
}

// Update addMessage to use state.elements
async function addMessage(content, isUser) {
    const messageDiv = document.createElement('div');
    messageDiv.className = `message ${isUser ? 'user-message' : 'assistant-message'}`;
    
    const contentDiv = document.createElement('div');
    contentDiv.className = 'message-content markdown-body';
    contentDiv.style.textAlign = 'left';
    
    if (isUser) {
        contentDiv.textContent = content;
    } else {
        const processed = await processMarkdown(content);
        contentDiv.innerHTML = processed;
    }
    
    messageDiv.appendChild(contentDiv);
    state.elements.chatWindow.appendChild(messageDiv);
    smoothScrollToBottom();
    
    return messageDiv;
}

// Update DOMContentLoaded handler
document.addEventListener('DOMContentLoaded', function() {
    console.log("=== DOM LOADED ===");
    
    // Initialize elements
    initializeElements();
    
    // Initialize event listeners
    if (state.elements.sendButton && state.elements.userInput) {
        // Send button click
        state.elements.sendButton.addEventListener('click', () => sendMessage());
        
        // Enter key press (without shift)
        state.elements.userInput.addEventListener('keypress', function(e) {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                sendMessage();
            }
        });
    } else {
        console.error('Required chat elements not found:', {
            sendButton: !!state.elements.sendButton,
            userInput: !!state.elements.userInput
        });
    }
    
    // Add clear all button listener
    if (state.elements.clearButton) {
        state.elements.clearButton.addEventListener('click', clearAllConversations);
    } else {
        console.error('Clear button not found');
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
        if (data.success) {
            // Clear UI messages
            document.querySelector('#chat-messages').innerHTML = '';
            
            // Reset state
            state.currentThreadId = 'default';
            if (state.streamBuffer) {
                state.streamBuffer.content = '';
                state.streamBuffer.raw = '';
                state.streamBuffer.isProcessingCode = false;
                state.streamBuffer.codeBlockDepth = 0;
                state.streamBuffer.contentParts.text = [];
                state.streamBuffer.contentParts.code = [];
                state.streamBuffer.contentParts.math = [];
                state.streamBuffer.contentParts.list = [];
                state.streamBuffer.partial.math = '';
                state.streamBuffer.partial.code = '';
                state.streamBuffer.partial.list = '';
            }
            
            // Clear input
            document.querySelector('#user-input').value = '';
            
            // Show success message
            clearButton.textContent = 'Cleared!';
            setTimeout(() => {
                clearButton.textContent = originalText;
                clearButton.disabled = false;
            }, 2000);
        } else {
            console.error('Failed to clear conversations:', data.message);
            clearButton.textContent = 'Error!';
            setTimeout(() => {
                clearButton.textContent = originalText;
                clearButton.disabled = false;
            }, 2000);
        }
    })
    .catch(error => {
        console.error('Error:', error);
        clearButton.textContent = 'Error!';
        setTimeout(() => {
            clearButton.textContent = originalText;
            clearButton.disabled = false;
        }, 2000);
    });
}

function repr(str) {
    return JSON.stringify(str);
}

function processMathContent(text) {
    log("Processing math content:", repr(text));
    
    // Queue the math content
    mathQueue.push(text);
    
    // If we're not currently processing, start processing the queue
    if (!isMathProcessing) {
        processMathQueue();
    }
}

async function processMathQueue() {
    if (isMathProcessing || mathQueue.length === 0) return;
    
    isMathProcessing = true;
    log("Processing math queue of length:", mathQueue.length);
    
    try {
        const content = mathQueue.join('');
        log("Combined math content:", repr(content));
        
        // Check for complete math expression
        if (isCompleteMathExpression(content)) {
            log("Complete math expression found");
            currentResponse += content;
            mathQueue = [];
            
            // Update display and render math
            const element = updateAssistantMessage(currentResponse);
            if (element) {
                await renderMathInElement(element);
            }
        }
    } catch (e) {
        log("Math processing error:", e);
    } finally {
        isMathProcessing = false;
        
        // If there's more in the queue, process it
        if (mathQueue.length > 0) {
            processMathQueue();
        }
    }
}

function isCompleteMathExpression(text) {
    const pairs = {
        '\\[': '\\]',
        '\\(': '\\)',
        '$$': '$$',
        '$': '$'
    };
    
    const stack = [];
    let i = 0;
    while (i < text.length) {
        for (const [open, close] of Object.entries(pairs)) {
            if (text.slice(i).startsWith(open)) {
                stack.push(close);
                i += open.length;
                continue;
            }
            if (text.slice(i).startsWith(close)) {
                if (stack.length === 0 || stack.pop() !== close) {
                    return false;
                }
                i += close.length;
                continue;
            }
        }
        i++;
    }
    return stack.length === 0;
}

function isCompleteCodeBlock(text) {
    const matches = text.match(/```/g);
    return matches && matches.length % 2 === 0;
}

function processCodeBlock(text) {
    // Process code block with proper formatting
    const lines = text.split('\n');
    const lang = lines[0].slice(3);
    const code = lines.slice(1, -1).join('\n');
    return `<pre><code class="language-${lang}">${code}</code></pre>`;
}

function isCompleteContent(text) {
    if (!text || typeof text !== 'string') return false;
    
    try {
        // Check for incomplete headers
        const headerLines = text.split('\n').filter(line => line.trim().startsWith('#'));
        for (const line of headerLines) {
            // Header should have space after #s and some content
            const match = line.match(/^(#{1,6})\s*(.*)/);
            if (!match || !match[2].trim()) {
                return false;
            }
        }
        
        // Check for incomplete code blocks
        const codeMatches = text.match(/```/g);
        if (codeMatches) {
            // Must have even number of backticks
            if (codeMatches.length % 2 !== 0) return false;
            
            // Check each code block is properly formed
            const blocks = text.split('```');
            // First and last elements should be non-code content
            for (let i = 1; i < blocks.length; i += 2) {
                // Each code block should have a language identifier
                if (!blocks[i].trim()) return false;
            }
        }
        
        // Check for incomplete list items
        const listLines = text.split('\n').filter(line => /^[\s]*[-*+]/.test(line) || /^[\s]*\d+\./.test(line));
        for (const line of listLines) {
            // List items should have content after the marker
            if (!line.match(/^[\s]*[-*+]\s+\S+/) && !line.match(/^[\s]*\d+\.\s+\S+/)) {
                return false;
            }
        }
        
        return true;
    } catch (e) {
        console.error('Error checking content completeness:', e);
        return false;
    }
}

// Add cleanup flag to prevent multiple cleanups
let isCleaningUp = false;

// Update event listeners for cleanup
window.addEventListener('beforeunload', cleanup_handler);
window.addEventListener('unload', cleanup_handler);

function handleStreamedResponse(response) {
    const reader = response.body.getReader();
    let accumulatedText = '';
    let messageDiv = null;
    
    return new Promise((resolve, reject) => {
        function processText({ done, value }) {
            if (done) {
                console.log("Stream complete, final text:", accumulatedText);
                resolve(accumulatedText);
                return;
            }
            
            // Convert the chunk to text
            const chunk = new TextDecoder().decode(value);
            console.log("Received chunk:", chunk);  // Debug log
            
            const lines = chunk.split('\n');
            
            // Process each line
            lines.forEach(line => {
                if (line.startsWith('data: ')) {
                    const data = line.slice(5);
                    if (data === '[DONE]') {
                        console.log("Received DONE signal");
                        resolve(accumulatedText);
                        return;
                    }
                    try {
                        const parsed = JSON.parse(data);
                        if (parsed.text) {
                            accumulatedText += parsed.text;
                            // Create or update message div
                            if (!messageDiv) {
                                messageDiv = createAssistantMessage(accumulatedText);
                            } else {
                                messageDiv.textContent = accumulatedText;
                            }
                        }
                    } catch (e) {
                        console.error('Error parsing chunk:', e, 'Line:', line);
                    }
                }
            });
            
            return reader.read().then(processText);
        }
        
        reader.read().then(processText);
    });
}

// Add queue for math processing
const mathQueue = {
    pending: [],
    processing: false
};

function queueMathProcessing(text, contentDiv) {
    return new Promise((resolve) => {
        if (text.includes('$') || text.includes('\\[') || text.includes('\\(')) {
            // Queue this chunk for MathJax processing
            mathQueue.pending.push({
                element: contentDiv,
                text: text,
                resolve: resolve
            });
            processMathQueue();
        } else {
            resolve(text);
        }
    });
}

async function processMathQueue() {
    if (mathQueue.processing || mathQueue.pending.length === 0) return;
    
    mathQueue.processing = true;
    
    try {
        const item = mathQueue.pending.shift();
        if (window.MathJax && window.MathJax.typesetPromise) {
            await window.MathJax.typesetPromise([item.element]);
            item.resolve();
        }
    } finally {
        mathQueue.processing = false;
        if (mathQueue.pending.length > 0) {
            processMathQueue();
        }
    }
}

// Update processStreamingContent to handle interruptions
async function processStreamingContent(chunk) {
    if (!state.streamBuffer.isStreaming || state.streaming.softTransition) {
        return;
    }

    try {
        state.streamBuffer.raw += chunk;
        const messages = state.streamBuffer.raw.split('\n\n');
        state.streamBuffer.raw = messages.pop();
        
        for (const msg of messages) {
            // Check for interruption after each message
            if (!state.streamBuffer.isStreaming || state.streaming.softTransition) {
                return;
            }

            if (!msg.startsWith('data: ')) continue;
            
            try {
                const jsonStr = msg.slice(6).trim();
                if (!jsonStr || jsonStr === '[DONE]') {
                    if (state.streamBuffer.content) {
                        const processed = await MathProcessor.processText(state.streamBuffer.content);
                        if (state.streamBuffer.messageElement) {
                            state.streamBuffer.messageElement.innerHTML = processed;
                        }
                    }
                    if (jsonStr === '[DONE]') {
                        state.streamBuffer.isStreaming = false;
                    }
                    continue;
                }
                
                const data = JSON.parse(jsonStr);
                if (!data?.text) continue;
                
                // Track code block state
                if (data.text.includes('```')) {
                    state.streamBuffer.isProcessingCode = !state.streamBuffer.isProcessingCode;
                    state.streamBuffer.codeBlockDepth += state.streamBuffer.isProcessingCode ? 1 : -1;
                }
                
                state.streamBuffer.content += data.text;
                
                if (!state.streamBuffer.messageElement) {
                    const newMessage = document.createElement('div');
                    newMessage.className = 'message assistant-message';
                    const contentDiv = document.createElement('div');
                    contentDiv.className = 'message-content markdown-body';
                    newMessage.appendChild(contentDiv);
                    state.elements.chatWindow.appendChild(newMessage);
                    state.streamBuffer.messageElement = contentDiv;
                }

                // Process content immediately, even during code block streaming
                const processed = await MathProcessor.processText(state.streamBuffer.content);
                state.streamBuffer.messageElement.innerHTML = processed;
                
                smoothScrollToBottom();
                
            } catch (e) {
                FlowLogger.error('Message processing error', e);
            }
        }
    } catch (e) {
        FlowLogger.error('Stream processing error', e);
    }
}

// New unified rendering function
async function renderContent(content) {
    // First protect math expressions
    const { text: protectedText, expressions } = await MathProcessor.processText(content);
    
    // Process markdown
    let processed = marked.parse(protectedText);
    
    // Restore and render math expressions
    for (const { id, expression, isBlock } of expressions) {
        const placeholder = `@@MATH_PLACEHOLDER_${id}@@`;
        const rendered = await renderMathExpression(expression, isBlock);
        processed = processed.replace(placeholder, rendered);
    }
    
    // Apply syntax highlighting to code blocks
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = processed;
    tempDiv.querySelectorAll('pre code').forEach((block) => {
        hljs.highlightElement(block);
    });
    
    return tempDiv.innerHTML;
}

// Add helper function to check for complete math expressions
function hasCompleteMathExpressions(text) {
    // Check for complete block math
    const blockRegex = /(\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\])/g;
    let modifiedText = text;
    
    // Remove complete block math expressions
    modifiedText = modifiedText.replace(blockRegex, '');
    
    // Check remaining inline math
    const inlineRegex = /(\$[^\$\n]*?\$|\\\([^\)]*?\\\))/g;
    const matches = modifiedText.match(/[\$\\]/g) || [];
    
    // If we have an odd number of delimiters, we have incomplete expressions
    return matches.length % 2 === 0;
}

// Add renderMathExpression function
async function renderMathExpression(mathExpr, isBlock) {
    const tempDiv = document.createElement('div');
    tempDiv.style.visibility = 'hidden';
    document.body.appendChild(tempDiv);
    
    try {
        // Clean up the math expression
        let cleanMath = mathExpr.trim();
        if (cleanMath.startsWith('$') && cleanMath.endsWith('$')) {
            cleanMath = cleanMath.slice(1, -1);
        } else if (cleanMath.startsWith('$$') && cleanMath.endsWith('$$')) {
            cleanMath = cleanMath.slice(2, -2);
        } else if (cleanMath.startsWith('\\[') && cleanMath.endsWith('\\]')) {
            cleanMath = cleanMath.slice(2, -2);
        } else if (cleanMath.startsWith('\\(') && cleanMath.endsWith('\\)')) {
            cleanMath = cleanMath.slice(2, -2);
        }

        // Add proper delimiters back with correct wrapper
        if (isBlock) {
            tempDiv.innerHTML = `<div class="display-math">\\[${cleanMath}\\]</div>`;
        } else {
            tempDiv.innerHTML = `<span class="inline-math">\\(${cleanMath}\\)</span>`;
        }
        
        // Render math
        await MathJax.typesetPromise([tempDiv]);
        
        return tempDiv.innerHTML;
    } finally {
        document.body.removeChild(tempDiv);
    }
}

// Add cleanup handler
function cleanup_handler(event) {
    if (state.isCleaningUp) return;
    
    state.isCleaningUp = true;
    console.log("Starting graceful shutdown");
    
    try {
        // Cancel any ongoing request
        if (state.currentResponseController) {
            state.currentResponseController.abort();
            state.currentResponseController = null;
        }
        
        state.isProcessing = false;

        // Clear any remaining timeouts
        if (scrollTimeout) {
            clearTimeout(scrollTimeout);
            scrollTimeout = null;
        }

        // Reset stream buffer
        if (state.streamBuffer) {
            state.streamBuffer.isStreaming = false;
            state.streamBuffer.content = '';
            state.streamBuffer.raw = '';
            state.streamBuffer.messageElement = null;
            state.streamBuffer.isProcessingCode = false;
            state.streamBuffer.codeBlockDepth = 0;
        }

        // Clear math queue
        if (typeof mathQueue !== 'undefined' && mathQueue) {
            mathQueue.pending = [];
            mathQueue.processing = false;
        }
        
        // Clear chat window
        if (state.elements?.chatWindow) {
            state.elements.chatWindow.innerHTML = '';
        }
        
    } catch (e) {
        console.error("Cleanup error:", e);
    } finally {
        console.log("Shutdown complete");
        state.isCleaningUp = false;
    }
}

// Add event listeners for cleanup
window.addEventListener('beforeunload', cleanup_handler);
window.addEventListener('unload', cleanup_handler);
