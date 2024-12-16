document.addEventListener('DOMContentLoaded', function() {
    const generateBtn = document.getElementById('generate-btn');
    const promptInput = document.getElementById('prompt');
    const widthInput = document.getElementById('width');
    const heightInput = document.getElementById('height');
    const stepsInput = document.getElementById('steps');
    const aspectRatioSelect = document.getElementById('aspect-ratio');
    const generatedImage = document.getElementById('generated-image');
    const loading = document.getElementById('loading');
    const error = document.getElementById('error');
    const guidanceScaleInput = document.getElementById('guidance-scale');
    const guidanceValue = document.getElementById('guidance-value');
    const seedInput = document.getElementById('seed');
    const saveImagesInput = document.getElementById('save-images');
    const resetBtn = document.getElementById('reset-btn');
    const progressBar = document.getElementById('progress-bar');
    const progressText = document.getElementById('progress-text');
    const realisticModeInput = document.getElementById('realistic-mode');

    // Load saved values from localStorage or use defaults
    function loadSavedValue(inputElement, defaultValue) {
        const savedValue = localStorage.getItem(inputElement.id);
        return savedValue !== null ? savedValue : defaultValue;
    }

    // Initialize inputs with saved values
    widthInput.value = loadSavedValue(widthInput, '768');
    heightInput.value = loadSavedValue(heightInput, '768');
    stepsInput.value = loadSavedValue(stepsInput, '4');
    guidanceScaleInput.value = loadSavedValue(guidanceScaleInput, '0.8');
    guidanceValue.textContent = guidanceScaleInput.value;
    seedInput.value = loadSavedValue(seedInput, '-1');
    saveImagesInput.checked = localStorage.getItem('save-images') !== 'false'; // default to true
    realisticModeInput.checked = localStorage.getItem('realistic-mode') === 'true'; // default to false
    aspectRatioSelect.value = loadSavedValue(aspectRatioSelect, 'custom');
    promptInput.value = loadSavedValue(promptInput, '');

    // Save values to localStorage when they change
    function saveValue(element) {
        if (element.type === 'checkbox') {
            localStorage.setItem(element.id, element.checked);
        } else {
            localStorage.setItem(element.id, element.value);
        }
    }

    // Add save functionality to all inputs
    [widthInput, heightInput, stepsInput, guidanceScaleInput, seedInput, 
     saveImagesInput, realisticModeInput, aspectRatioSelect, promptInput].forEach(element => {
        element.addEventListener('change', () => saveValue(element));
    });

    // Special handling for range input to update in real-time
    guidanceScaleInput.addEventListener('input', function() {
        guidanceValue.textContent = this.value;
        saveValue(this);
    });

    // Aspect ratio presets with ratios instead of fixed dimensions
    const aspectRatios = {
        'custom': null,
        '1:1': { ratio: 1 / 1 },
        '4:3': { ratio: 4 / 3 },
        '16:9': { ratio: 16 / 9 },
        '2:3': { ratio: 2 / 3 },
        '3:2': { ratio: 3 / 2 }
    };

    // Handle aspect ratio selection
    aspectRatioSelect.addEventListener('change', function() {
        const ratio = this.value;
        if (ratio === 'custom') return;

        // Get the aspect ratio
        const preset = aspectRatios[ratio];
        if (preset) {
            const currentWidth = parseInt(widthInput.value);
            const currentHeight = parseInt(heightInput.value);
            
            // Determine which dimension to keep based on which is larger
            if (currentWidth >= currentHeight) {
                // Keep width, calculate new height
                let newHeight = Math.round(currentWidth / preset.ratio);
                // Clamp height to valid range
                newHeight = Math.min(Math.max(newHeight, 128), 2048);
                heightInput.value = newHeight;
            } else {
                // Keep height, calculate new width
                let newWidth = Math.round(currentHeight * preset.ratio);
                // Clamp width to valid range
                newWidth = Math.min(Math.max(newWidth, 128), 2048);
                widthInput.value = newWidth;
            }
            
            saveValue(widthInput);
            saveValue(heightInput);
        }
    });

    // Function to maintain aspect ratio when width/height changes
    function maintainAspectRatio(changedInput, otherInput) {
        const selectedRatio = aspectRatioSelect.value;
        if (selectedRatio !== 'custom') {
            const ratio = aspectRatios[selectedRatio];
            if (changedInput === widthInput) {
                let newHeight = Math.round(parseInt(widthInput.value) / ratio.ratio);
                // Clamp height to valid range
                newHeight = Math.min(Math.max(newHeight, 128), 2048);
                heightInput.value = newHeight;
                saveValue(heightInput);
            } else {
                let newWidth = Math.round(parseInt(heightInput.value) * ratio.ratio);
                // Clamp width to valid range
                newWidth = Math.min(Math.max(newWidth, 128), 2048);
                widthInput.value = newWidth;
                saveValue(widthInput);
            }
        }
    }

    // Update width/height when inputs change
    widthInput.addEventListener('input', function() {
        if (aspectRatioSelect.value !== 'custom') {
            maintainAspectRatio(widthInput, heightInput);
        }
    });

    heightInput.addEventListener('input', function() {
        if (aspectRatioSelect.value !== 'custom') {
            maintainAspectRatio(heightInput, widthInput);
        }
    });

    // Only switch to custom when user explicitly changes both values
    widthInput.addEventListener('change', function() {
        if (this.value !== aspectRatios[aspectRatioSelect.value]?.width) {
            aspectRatioSelect.value = 'custom';
        }
    });

    heightInput.addEventListener('change', function() {
        if (this.value !== aspectRatios[aspectRatioSelect.value]?.height) {
            aspectRatioSelect.value = 'custom';
        }
    });

    // Function to enhance prompt for realism
    function enhancePromptForRealism(originalPrompt) {
        const realisticTerms = [
            "photorealistic",
            "highly detailed",
            "professional photography",
            "8k uhd",
            "realistic lighting",
            "natural colors"
        ];
        
        // Only add terms if they're not already in the prompt
        const enhancedTerms = realisticTerms.filter(term => 
            !originalPrompt.toLowerCase().includes(term.toLowerCase())
        );
        
        if (enhancedTerms.length > 0) {
            return `${originalPrompt}, ${enhancedTerms.join(", ")}`;
        }
        return originalPrompt;
    }

    // Handle realistic mode toggle
    realisticModeInput.addEventListener('change', function() {
        if (this.checked) {
            // When realistic mode is enabled, adjust guidance scale
            guidanceScaleInput.value = "1.2";  // Higher guidance for more accurate prompt following
            guidanceValue.textContent = guidanceScaleInput.value;
            saveValue(guidanceScaleInput);
        }
    });

    generateBtn.addEventListener('click', async function() {
        console.log('Generate button clicked');
        let prompt = promptInput.value.trim();
        
        if (!prompt) {
            showError('Please enter a prompt');
            return;
        }

        // Enhance prompt if realistic mode is enabled
        if (realisticModeInput.checked) {
            prompt = enhancePromptForRealism(prompt);
            console.log('Enhanced prompt:', prompt);
        }

        // Show loading state and reset progress
        loading.style.display = 'block';
        error.style.display = 'none';
        generatedImage.style.display = 'none';
        generateBtn.disabled = true;
        progressBar.style.width = '0%';
        progressText.textContent = 'Generating... 0%';

        const requestData = {
            prompt: prompt,
            width: parseInt(widthInput.value),
            height: parseInt(heightInput.value),
            steps: parseInt(stepsInput.value),
            guidance_scale: parseFloat(guidanceScaleInput.value),
            seed: parseInt(seedInput.value),
            save_image: saveImagesInput.checked
        };
        console.log('Sending request with data:', requestData);

        try {
            // Set up Server-Sent Events connection
            const eventSource = new EventSource('/progress');
            
            eventSource.onmessage = function(event) {
                const progress = JSON.parse(event.data);
                const percent = progress.percent;
                progressBar.style.width = `${percent}%`;
                progressText.textContent = `Generating... ${percent}%`;
            };
            
            eventSource.onerror = function() {
                eventSource.close();
            };

            const response = await fetch('/generate', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(requestData)
            });

            console.log('Received response:', response);
            const data = await response.json();
            console.log('Response data:', data);

            if (data.status === 'success') {
                generatedImage.src = `data:image/png;base64,${data.image}`;
                progressBar.style.width = '100%';
                progressText.textContent = 'Generation Complete!';
                generatedImage.style.display = 'block';
                loading.style.display = 'none';
            } else {
                showError(data.message);
                loading.style.display = 'none';
            }
        } catch (err) {
            console.error('Error during fetch:', err);
            showError('An error occurred while generating the image');
            loading.style.display = 'none';
        } finally {
            generateBtn.disabled = false;
            eventSource.close();
        }
    });

    function showError(message) {
        console.error('Error:', message);
        error.textContent = message;
        error.style.display = 'block';
    }

    resetBtn.addEventListener('click', function() {
        localStorage.clear();
        location.reload();
    });
}); 
