document.addEventListener('DOMContentLoaded', function() {
    const form = document.getElementById('equation-form');
    const equationInput = document.getElementById('equation');
    const loadingOverlay = document.querySelector('.loading-overlay');
    const resultContainer = document.getElementById('result-container');
    const renderedEquation = document.getElementById('rendered-equation');
    const errorMessage = document.getElementById('error-message');
    const copyLatexButton = document.getElementById('copy-latex');
    const clearButton = document.getElementById('clear-button');
    const equationHistory = document.getElementById('equation-history');

    let latexEquation = '';

    form.addEventListener('submit', function(e) {
        e.preventDefault();
        renderEquation();
    });

    clearButton.addEventListener('click', function() {
        equationInput.value = '';
        resultContainer.style.display = 'none';
        errorMessage.style.display = 'none';
    });

    copyLatexButton.addEventListener('click', function() {
        navigator.clipboard.writeText(latexEquation).then(function() {
            alert('LaTeX copied to clipboard!');
        });
    });

    equationInput.addEventListener('keydown', function(e) {
        if (e.ctrlKey && e.key === 'Enter') {
            e.preventDefault();
            renderEquation();
        }
    });

    function renderEquation() {
        const equation = equationInput.value;
        loadingOverlay.style.display = 'block';
        errorMessage.style.display = 'none';

        fetch('/render', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({equation: equation}),
        })
        .then(response => response.json())
        .then(data => {
            loadingOverlay.style.display = 'none';
            if (data.error) {
                errorMessage.textContent = data.error;
                errorMessage.style.display = 'block';
                resultContainer.style.display = 'none';
            } else {
                renderedEquation.innerHTML = `\\[${data.latex}\\]`;
                latexEquation = data.latex;
                resultContainer.style.display = 'block';
                addToHistory(equation, `\\[${data.latex}\\]`);
                
                // Render step-by-step solution
                const stepByStepSolution = document.getElementById('step-by-step-solution');
                stepByStepSolution.innerHTML = data.steps.map(step => `\\[${step}\\]`).join('');
                
                // Trigger MathJax to reprocess the page
                MathJax.typesetPromise([renderedEquation, stepByStepSolution]).then(() => {
                    console.log('MathJax rendering complete');
                }).catch((err) => console.log('MathJax rendering failed: ' + err.message));
            }
        })
        .catch(error => {
            loadingOverlay.style.display = 'none';
            errorMessage.textContent = 'An error occurred. Please try again.';
            errorMessage.style.display = 'block';
            resultContainer.style.display = 'none';
        });
    }

    function addToHistory(equation, rendered) {
        const li = document.createElement('li');
        li.innerHTML = `<span class="history-equation">${equation}</span> <span class="history-rendered">${rendered}</span>`;
        li.addEventListener('click', function() {
            equationInput.value = equation;
            renderEquation();
        });
        equationHistory.prepend(li);
        if (equationHistory.children.length > 5) {
            equationHistory.removeChild(equationHistory.lastChild);
        }
    }
});