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

    // Load saved values from localStorage or use defaults
    function loadSavedValue(inputElement, defaultValue) {
        const savedValue = localStorage.getItem(inputElement.id);
        return savedValue !== null ? savedValue : defaultValue;
    }

    // Initialize inputs with saved values
    widthInput.value = loadSavedValue(widthInput, '768');
    heightInput.value = loadSavedValue(heightInput, '768');
    stepsInput.value = loadSavedValue(stepsInput, '4');
    guidanceScaleInput.value = loadSavedValue(guidanceScaleInput, '7.5');
    guidanceValue.textContent = guidanceScaleInput.value;
    seedInput.value = loadSavedValue(seedInput, '-1');
    saveImagesInput.checked = localStorage.getItem('save-images') !== 'false'; // default to true
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
     saveImagesInput, aspectRatioSelect, promptInput].forEach(element => {
        element.addEventListener('change', () => saveValue(element));
    });

    // Special handling for range input to update in real-time
    guidanceScaleInput.addEventListener('input', function() {
        guidanceValue.textContent = this.value;
        saveValue(this);
    });

    // Aspect ratio presets with common resolutions
    const aspectRatios = {
        'custom': null,
        '1:1': { width: 768, height: 768 },
        '4:3': { width: 1024, height: 768 },
        '16:9': { width: 1024, height: 576 },
        '2:3': { width: 512, height: 768 },
        '3:2': { width: 768, height: 512 }
    };

    // Handle aspect ratio selection
    aspectRatioSelect.addEventListener('change', function() {
        const ratio = this.value;
        if (ratio === 'custom') return;

        // Get preset dimensions for the selected ratio
        const preset = aspectRatios[ratio];
        if (preset) {
            widthInput.value = preset.width;
            heightInput.value = preset.height;
            saveValue(widthInput);
            saveValue(heightInput);
        }
    });

    // Function to maintain aspect ratio
    function maintainAspectRatio(changedInput, otherInput) {
        const selectedRatio = aspectRatioSelect.value;
        if (selectedRatio !== 'custom') {
            const ratio = aspectRatios[selectedRatio];
            const aspectRatio = ratio.width / ratio.height;
            
            if (changedInput === widthInput) {
                heightInput.value = Math.round(parseInt(widthInput.value) / aspectRatio);
                saveValue(heightInput);
            } else {
                widthInput.value = Math.round(parseInt(heightInput.value) * aspectRatio);
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

    generateBtn.addEventListener('click', async function() {
        console.log('Generate button clicked');
        const prompt = promptInput.value.trim();
        
        if (!prompt) {
            showError('Please enter a prompt');
            return;
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
            guidance_scale: 15 - parseFloat(guidanceScaleInput.value),
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
                
                // Update progress text based on generation phases
                if (percent <= 10) {
                    progressText.textContent = 'Loading model...';
                } else if (percent <= 20) {
                    progressText.textContent = 'Optimizing memory...';
                } else if (percent < 100) {
                    const totalSteps = parseInt(stepsInput.value);
                    const currentStep = Math.ceil(((percent - 20) / 80) * totalSteps);
                    progressText.textContent = `Generation step ${currentStep}/${totalSteps}...`;
                } else {
                    progressText.textContent = 'Generation Complete!';
                }
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
                generatedImage.style.display = 'block';
                progressBar.style.width = '100%';
                progressText.textContent = 'Generation Complete!';
            } else {
                showError(data.message);
            }
        } catch (err) {
            console.error('Error during fetch:', err);
            showError('An error occurred while generating the image');
        } finally {
            loading.style.display = 'none';
            generateBtn.disabled = false;
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
