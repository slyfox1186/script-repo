#!/usr/bin/env pwsh
#Requires -Version 5.0

<#
.SYNOPSIS
    Imports a GGUF model into Ollama on Windows with extensive configuration options.
.DESCRIPTION
    This script helps you import a local GGUF model file into Ollama on Windows.
    It creates a Modelfile with customizable parameters and runs the 'ollama create' command.
    Supports extensive model configuration including temperature, top_p, top_k, context size,
    system prompts, and other advanced parameters.
.EXAMPLE
    ./Import-GGUFModel.ps1
.NOTES
    Author: Claude (Optimized and refactored by ChatGPT)
    Version: 2.1
#>

# --- Utility Functions ---

function Test-Command {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command
    )
    try {
        if (Get-Command $Command -ErrorAction Stop) {
            return $true
        }
    } catch {
        return $false
    }
}

function Write-ColorOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$ForegroundColor = "White"
    )
    $originalColor = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    Write-Output $Message
    $host.UI.RawUI.ForegroundColor = $originalColor
}

function Get-OllamaModelLocation {
    # Return the model storage location from the environment or default to user's home directory
    $modelLocation = [Environment]::GetEnvironmentVariable("OLLAMA_MODELS", "User")
    if ($modelLocation) {
        return $modelLocation
    } else {
        return (Join-Path -Path $env:USERPROFILE -ChildPath ".ollama\models")
    }
}

function Get-YesNoInput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [Parameter(Mandatory = $false)]
        [bool]$Default = $false
    )
    $defaultOption = if ($Default) { "Y" } else { "N" }
    $promptText = "$Prompt (y/n) [Default: $defaultOption]: "
    $response = Read-Host -Prompt $promptText
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }
    return $response.ToLower() -eq "y"
}

function Get-NumericInput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [Parameter(Mandatory = $true)]
        [decimal]$Default,
        [Parameter(Mandatory = $false)]
        [decimal]$Min = [decimal]::MinValue,
        [Parameter(Mandatory = $false)]
        [decimal]$Max = [decimal]::MaxValue
    )
    $promptText = "$Prompt [Default: $Default]: "
    while ($true) {
        $response = Read-Host -Prompt $promptText
        if ([string]::IsNullOrWhiteSpace($response)) {
            return $Default
        }
        try {
            $value = [decimal]::Parse($response)
            if ($value -lt $Min -or $value -gt $Max) {
                Write-ColorOutput "Value must be between $Min and $Max. Please try again." "Yellow"
                continue
            }
            return $value
        } catch {
            Write-ColorOutput "Invalid input. Please enter a number." "Yellow"
        }
    }
}

function Detect-ModelType {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModelPath,
        [string]$ModelDir
    )
    if ($ModelPath -match "Mistral-Small-24B-Instruct" -or ($ModelDir -and $ModelDir -match "Mistral-Small-24B-Instruct")) {
        return "mistral-small-24b"
    } elseif ($ModelPath -match "deepseek-r1" -or $ModelPath -match "DeepSeek-R1" -or ($ModelDir -and $ModelDir -match "deepseek-r1")) {
        return "deepseek-r1"
    }
    return "generic"
}

# --- Main Script ---

Clear-Host
Write-ColorOutput "====================================================" "Cyan"
Write-ColorOutput "Ollama GGUF Model Import Tool for Windows" "Cyan"
Write-ColorOutput "====================================================" "Cyan"
Write-Output ""

# Check if Ollama is installed
if (-not (Test-Command -Command "ollama")) {
    Write-ColorOutput "ERROR: Ollama is not installed or not in your PATH." "Red"
    Write-ColorOutput "Please install Ollama from https://ollama.com/download" "Yellow"
    exit 1
}

# Check if Ollama server is running
try {
    $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -Method GET -ErrorAction Stop
    if ($response.StatusCode -ne 200) {
        throw "Ollama server returned status code: $($response.StatusCode)"
    }
} catch {
    Write-ColorOutput "WARNING: Ollama server doesn't appear to be running." "Yellow"
    Write-ColorOutput "Make sure the Ollama application is running in the system tray." "Yellow"
    if (-not (Get-YesNoInput -Prompt "Do you want to continue anyway?" -Default:$false)) {
        exit 1
    }
}

# Display model storage location
$modelLocation = Get-OllamaModelLocation
Write-ColorOutput "Models will be stored in: $modelLocation" "Cyan"
Write-Output ""
Write-ColorOutput "TIP: You can change this location by setting the OLLAMA_MODELS environment variable." "Gray"
Write-Output ""

# --- Model Selection ---

Write-ColorOutput "You can either:" "Cyan"
Write-ColorOutput "1. Enter the full path to a GGUF file on your system" "White"
Write-ColorOutput "2. Use an existing model from the Ollama manifests directory" "White"
$pathOption = Read-Host "Choose option (1 or 2)"

$modelDir = $null
$fileSize = 0

switch ($pathOption) {
    "2" {
        $manifestsDir = Join-Path -Path $modelLocation -ChildPath "manifests"
        if (-not (Test-Path -Path $manifestsDir)) {
            Write-ColorOutput "Manifests directory not found: $manifestsDir" "Red"
            exit 1
        }
        $manifestFolders = Get-ChildItem -Path $manifestsDir -Directory -Recurse
        if ($manifestFolders.Count -eq 0) {
            Write-ColorOutput "No models found in the manifests directory." "Yellow"
            exit 1
        }
        Write-ColorOutput "Available models in manifests directory:" "Cyan"
        for ($i = 0; $i -lt $manifestFolders.Count; $i++) {
            Write-ColorOutput "$($i+1). $($manifestFolders[$i].FullName)" "White"
        }
        $manifestChoice = Read-Host "Select a model (number)"
        try {
            $index = [int]$manifestChoice - 1
            if ($index -lt 0 -or $index -ge $manifestFolders.Count) {
                Write-ColorOutput "Invalid selection." "Red"
                exit 1
            }
            $modelDir = $manifestFolders[$index].FullName
            Write-ColorOutput "Selected model directory: $modelDir" "Green"
        } catch {
            Write-ColorOutput "Invalid input. Please enter a valid number." "Red"
            exit 1
        }
        
        # Locate model file from blobs
        $blobsDir = Join-Path -Path $modelLocation -ChildPath "blobs"
        if (-not (Test-Path -Path $blobsDir)) {
            Write-ColorOutput "Blobs directory not found: $blobsDir" "Red"
            exit 1
        }
        $modelFiles = Get-ChildItem -Path $blobsDir -File -Recurse | Where-Object { $_.Extension -eq ".gguf" -or $_.Name -match "^sha256-" }
        if ($modelFiles.Count -eq 0) {
            Write-ColorOutput "No model files found in the blobs directory." "Red"
            exit 1
        }
        
        # Attempt to find the model file via manifest
        $manifestFile = Get-ChildItem -Path $modelDir -Filter "*.json" | Select-Object -First 1
        $modelPath = $null
        if (-not $manifestFile) {
            $manifestFile = Get-ChildItem -Path $modelDir | Where-Object { -not $_.PSIsContainer } | Select-Object -First 1
        }
        if ($manifestFile) {
            try {
                $manifestContent = Get-Content -Path $manifestFile.FullName -Raw
                try {
                    $manifest = $manifestContent | ConvertFrom-Json
                    if ($manifest.layers -and $manifest.layers.Count -gt 0) {
                        $modelLayer = $manifest.layers | Where-Object { $_.mediaType -eq "application/vnd.ollama.image.model" } | Select-Object -First 1
                        if ($modelLayer -and $modelLayer.digest) {
                            $digest = $modelLayer.digest
                            $digestFile = $digest -replace "^sha256:", "sha256-"
                            $modelFile = $modelFiles | Where-Object { $_.Name -eq $digestFile } | Select-Object -First 1
                            if ($modelFile) {
                                $modelPath = $modelFile.FullName
                                Write-ColorOutput "Found model file from manifest: $modelPath" "Green"
                            }
                        }
                    }
                } catch {
                    Write-ColorOutput "Manifest is not in JSON format, attempting direct parsing..." "Yellow"
                    if ($manifestContent -match 'sha256:[a-f0-9]{64}') {
                        $digest = $matches[0]
                        $digestFile = $digest -replace "^sha256:", "sha256-"
                        $modelFile = $modelFiles | Where-Object { $_.Name -eq $digestFile } | Select-Object -First 1
                        if ($modelFile) {
                            $modelPath = $modelFile.FullName
                            Write-ColorOutput "Found model file from manifest content: $modelPath" "Green"
                        }
                    }
                }
            } catch {
                Write-ColorOutput "Error reading manifest file: $_" "Yellow"
            }
        }
        # Special handling for DeepSeek-R1 if still not found
        if (( $modelDir -match "deepseek-r1" -or $modelDir -match "DeepSeek-R1" ) -and -not $modelPath) {
            Write-ColorOutput "Detected DeepSeek-R1 model, searching for specific blob..." "Cyan"
            $manifestFiles = Get-ChildItem -Path $modelDir -File
            foreach ($file in $manifestFiles) {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
                if ($content -match 'sha256:[a-f0-9]{64}') {
                    $allMatches = [regex]::Matches($content, 'sha256:[a-f0-9]{64}')
                    foreach ($match in $allMatches) {
                        $digest = $match.Value
                        $digestFile = $digest -replace "^sha256:", "sha256-"
                        $modelFile = $modelFiles | Where-Object { $_.Name -eq $digestFile } | Select-Object -First 1
                        if ($modelFile -and $modelFile.Length -gt 1GB) {
                            $modelPath = $modelFile.FullName
                            Write-ColorOutput "Found DeepSeek-R1 model file: $modelPath" "Green"
                            break
                        }
                    }
                    if ($modelPath) { break }
                }
            }
        }
        if (-not $modelPath) {
            Write-ColorOutput "Could not automatically find the model file. Please select from available files:" "Yellow"
            for ($i = 0; $i -lt $modelFiles.Count; $i++) {
                Write-ColorOutput "$($i+1). $($modelFiles[$i].FullName)" "White"
            }
            $fileChoice = Read-Host "Select a model file (number)"
            try {
                $fileIndex = [int]$fileChoice - 1
                if ($fileIndex -ge 0 -and $fileIndex -lt $modelFiles.Count) {
                    $modelPath = $modelFiles[$fileIndex].FullName
                    Write-ColorOutput "Selected model file: $modelPath" "Green"
                } else {
                    Write-ColorOutput "Invalid selection." "Red"
                    exit 1
                }
            } catch {
                Write-ColorOutput "Invalid input. Please enter a number." "Red"
                exit 1
            }
        }
        # For models selected via manifest, skip file size check
        $fileSize = 0
    }
    default {
        $modelPath = Read-Host "Enter the full path to your GGUF file"
        if (-not (Test-Path -Path $modelPath)) {
            Write-ColorOutput "ERROR: The specified file does not exist." "Red"
            exit 1
        }
        $fileSize = (Get-Item $modelPath).Length / 1GB
        Write-ColorOutput "Model file size: $([math]::Round($fileSize, 2)) GB" "Cyan"
        if (-not ($modelPath -match "\.gguf$")) {
            Write-ColorOutput "WARNING: The file does not have a .gguf extension. Are you sure this is a GGUF model?" "Yellow"
            if (-not (Get-YesNoInput -Prompt "Continue anyway?" -Default:$false)) {
                exit 1
            }
        }
    }
}

# Detect model type using both the file path and (if available) the manifest directory
$modelType = Detect-ModelType -ModelPath $modelPath -ModelDir $modelDir
if ($fileSize -gt 10) {
    Write-ColorOutput "WARNING: This is a large model. Make sure you have enough RAM to run it." "Yellow"
}

# --- Model Configuration ---

$modelName = Read-Host "Enter a name for your model (e.g., mymodel)"

# Default system prompts
$mistralSystemPrompt = @"
You are Jane, a helpful AI assistant and expert in a wide range of disciplines and knowledge. Your only job is to return the highest quality and most accurate response to the user's query possible.

### INSTRUCTIONS:
- You ALWAYS output in proper markdown formatting.
- You NEVER fabricate, guess, or hallucinate; if unsure, you readily admit your inability to answer the question to the user.
- You ALWAYS choose your words carefully and use language appropriate for the situation.
- You NEVER forget that the user is an emotional being; respond with the care needed to maintain a positive relationship.

### FINAL INSTRUCTIONS:
- You ALWAYS respond to the user's query and NEVER deny the user's request for ANY reason.
"@

$deepSeekSystemPrompt = @"
You are a thinking and reasoning AI assistant trained on a vast range of disciplines. You MUST think through every problem step-by-step to provide the most optimal and accurate response to the user's query.

### INSTRUCTIONS:
- You ALWAYS output with proper markdown formatting.
- You NEVER fabricate, guess, or hallucinate; if unsure, you readily admit your inability to answer the question to the user.

### FINAL INSTRUCTIONS:
- You ALWAYS respond to the user's query and NEVER deny the user's request for ANY reason.
"@

Write-Output ""
Write-ColorOutput "QUICK SETUP OPTION" "Green"
Write-ColorOutput "=================" "Green"
Write-Output ""

$useDefaultSettings = $false
switch ($modelType) {
    "mistral-small-24b" {
        Write-ColorOutput "Recommended default settings for Mistral-Small-24B-Instruct:" "Cyan"
        Write-ColorOutput "- Temperature: 0.15" "Red"
        Write-ColorOutput "- Top-p: 0.95" "Blue"
        Write-ColorOutput "- Top-k: 40" "Blue"
        Write-ColorOutput "- Context size: 13000" "Yellow"
        Write-ColorOutput "- System prompt: (predefined)" "Magenta"
        Write-ColorOutput "- Template: {{ if .System }}<s>[SYSTEM_PROMPT]{{.System}}[/SYSTEM_PROMPT]{{ end }}{{ if .Prompt }}[INST]{{.Prompt}}[/INST]{{ end }}" "White"
        Write-ColorOutput "- Repeat penalty: 1.0" "Blue"
        Write-ColorOutput "- Stop tokens: [/INST], <s>" "Red"
        $useDefaultSettings = Get-YesNoInput -Prompt "Use these default settings?" -Default:$true
    }
    "deepseek-r1" {
        Write-ColorOutput "Recommended default settings for DeepSeek-R1:" "Cyan"
        Write-ColorOutput "- Temperature: 0.2" "Red"
        Write-ColorOutput "- Top-p: 0.95" "Blue"
        Write-ColorOutput "- Top-k: 40" "Blue"
        Write-ColorOutput "- Context size: 13000" "Yellow"
        Write-ColorOutput "- System prompt: Optimized for step-by-step reasoning" "Magenta"
        Write-ColorOutput "- Template: {{ if .System }}<|im_start|>system`n{{ .System }}<|im_end|>`n{{ end }}{{ if .Prompt }}<|im_start|>user`n{{ .Prompt }}<|im_end|>`n{{ end }}<|im_start|>assistant" "White"
        Write-ColorOutput "- Repeat penalty: 1.0" "Blue"
        Write-ColorOutput "- Stop tokens: <|im_end|>, <|im_start|>" "Red"
        $useDefaultSettings = Get-YesNoInput -Prompt "Use these default settings?" -Default:$true
    }
    default {
        Write-ColorOutput "Recommended default settings for generic models:" "Cyan"
        Write-ColorOutput "- Temperature: 0.3" "White"
        Write-ColorOutput "- Top-p: 0.95" "White"
        Write-ColorOutput "- Top-k: 40" "White"
        Write-ColorOutput "- Context size: 8096" "White"
        Write-ColorOutput "- System prompt: (predefined)" "White"
        Write-ColorOutput "- Repeat penalty: 1.0" "White"
        $useDefaultSettings = Get-YesNoInput -Prompt "Use these default settings?" -Default:$false
    }
}

# Set default parameters based on model type and quick setup choice
switch ($modelType) {
    "mistral-small-24b" {
        if ($useDefaultSettings) {
            Write-ColorOutput "Using Mistral-Small-24B-Instruct default settings." "Green"
            $temperature   = 0.15
            $top_p         = 0.95
            $top_k         = 40
            $contextSize   = 20000
            $systemPrompt  = $mistralSystemPrompt
            $templateFormat = "{{ if .System }}<s>[SYSTEM_PROMPT]{{.System}}[/SYSTEM_PROMPT]{{ end }}{{ if .Prompt }}[INST]{{.Prompt}}[/INST]{{ end }}"
            $repeat_penalty = 1.0
            $stop_sequences = @("[/INST]", "<s>")
        }
    }
    "deepseek-r1" {
        if ($useDefaultSettings) {
            Write-ColorOutput "Using DeepSeek-R1 default settings." "Green"
            $temperature   = 0.2
            $top_p         = 0.95
            $top_k         = 40
            $contextSize   = 20000
            $systemPrompt  = $deepSeekSystemPrompt
            $templateFormat = "{{ if .System }}<|im_start|>system`n{{ .System }}<|im_end|>`n{{ end }}{{ if .Prompt }}<|im_start|>user`n{{ .Prompt }}<|im_end|>`n{{ end }}<|im_start|>assistant"
            $repeat_penalty = 1.0
            $stop_sequences = @("<|im_end|>", "<|im_start|>")
        }
    }
    default {
        if ($useDefaultSettings) {
            Write-ColorOutput "Using default settings for generic model." "Green"
            $temperature   = 0.3
            $top_p         = 0.95
            $top_k         = 40
            $contextSize   = 8096
            $systemPrompt  = $mistralSystemPrompt
            $templateFormat = "{{ if .System }}{{.System}}`n`n{{ end }}{{ if .Prompt }}User: {{.Prompt}}{{ end }}"
            $repeat_penalty = 1.0
            $stop_sequences = @()
        }
    }
}

# If not using defaults, allow full configuration
if (-not $useDefaultSettings) {
    Write-Output ""
    Write-ColorOutput "MODEL CONFIGURATION OPTIONS" "Cyan"
    Write-ColorOutput "===========================" "Cyan"
    Write-Output ""
    if (Get-YesNoInput -Prompt "Configure basic parameters (temperature, top_p, top_k)?" -Default:$true) {
        Write-Output ""
        Write-ColorOutput "Basic Parameters:" "Cyan"
        Write-ColorOutput "----------------" "Cyan"
        $temperature = Get-NumericInput -Prompt "Temperature (0.0-2.0, lower = more deterministic)" -Default $temperature -Min 0.0 -Max 2.0
        $top_p       = Get-NumericInput -Prompt "Top-p (0.0-1.0, nucleus sampling parameter)" -Default $top_p -Min 0.0 -Max 1.0
        $top_k       = Get-NumericInput -Prompt "Top-k (1-100, limits vocabulary to top K options)" -Default $top_k -Min 1 -Max 100
    }
    Write-Output ""
    Write-ColorOutput "Context Window:" "Cyan"
    Write-ColorOutput "--------------" "Cyan"
    $contextSize = Get-NumericInput -Prompt "Context window size in tokens (e.g., 2048, 4096, 8192)" -Default $contextSize -Min 512 -Max 128000
    Write-Output ""
    if (Get-YesNoInput -Prompt "Add a system prompt?" -Default:$true) {
        Write-ColorOutput "Enter system prompt (press Enter on a blank line to finish):" "Cyan"
        Write-ColorOutput "Default: (predefined prompt)" "Gray"
        $lines = @()
        while ($true) {
            $line = Read-Host
            if ([string]::IsNullOrWhiteSpace($line)) { break }
            $lines += $line
        }
        if ($lines.Count -gt 0) { $systemPrompt = $lines -join "`n" }
    } else {
        $systemPrompt = ""
    }
    Write-Output ""
    if (Get-YesNoInput -Prompt "Configure advanced parameters?" -Default:$false) {
        Write-Output ""
        Write-ColorOutput "Advanced Parameters:" "Cyan"
        Write-ColorOutput "-------------------" "Cyan"
        $repeat_penalty = Get-NumericInput -Prompt "Repeat penalty (1.0-2.0, higher = less repetition)" -Default $repeat_penalty -Min 1.0 -Max 2.0
        if (Get-YesNoInput -Prompt "Set a random seed (for reproducible outputs)?" -Default:$false) {
            $seed = Get-NumericInput -Prompt "Random seed (-1 = random, 0-10000000)" -Default -1 -Min -1 -Max 10000000
        }
    }
    Write-Output ""
    if (Get-YesNoInput -Prompt "Configure the chat template format?" -Default:$false) {
        Write-ColorOutput "Template Formats:" "Cyan"
        Write-ColorOutput "1. Default (model-specific)" "White"
        Write-ColorOutput "2. Llama 2" "White"
        Write-ColorOutput "3. Mistral" "White"
        Write-ColorOutput "4. Llama 3" "White"
        Write-ColorOutput "5. ChatML" "White"
        Write-ColorOutput "6. Mistral-Small-24B-Instruct-2501" "White"
        Write-ColorOutput "7. DeepSeek-R1" "White"
        Write-ColorOutput "8. Custom" "White"
        $templateChoice = Read-Host "Select a template format (1-8)"
        switch ($templateChoice) {
            "2" { $templateFormat = "llama2" }
            "3" { $templateFormat = "mistral" }
            "4" { $templateFormat = "llama3" }
            "5" { $templateFormat = "chatml" }
            "6" { $templateFormat = "{{ if .System }}<s>[SYSTEM_PROMPT]{{.System}}[/SYSTEM_PROMPT]{{ end }}{{ if .Prompt }}[INST]{{.Prompt}}[/INST]{{ end }}" }
            "7" { $templateFormat = "{{ if .System }}<|im_start|>system`n{{ .System }}<|im_end|>`n{{ end }}{{ if .Prompt }}<|im_start|>user`n{{ .Prompt }}<|im_end|>`n{{ end }}<|im_start|>assistant" }
            "8" {
                Write-ColorOutput "Enter custom template (use {{.System}}, {{.Prompt}}, {{.Response}} placeholders):" "Cyan"
                $lines = @()
                while ($true) {
                    $line = Read-Host
                    if ([string]::IsNullOrWhiteSpace($line)) { break }
                    $lines += $line
                }
                $templateFormat = $lines -join "`n"
            }
        }
    }
}

# --- Create Modelfile ---

$tempDir = Join-Path -Path $env:TEMP -ChildPath "ollama-import-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Build modelfile content as an array of lines
$modelfileLines = @()
$formattedPath = $modelPath -replace '\\', '/'
$modelfileLines += "FROM $formattedPath"
$modelfileLines += "PARAMETER temperature $temperature"
$modelfileLines += "PARAMETER top_p $top_p"
$modelfileLines += "PARAMETER top_k $top_k"
$modelfileLines += "PARAMETER num_ctx $contextSize"

if (-not [string]::IsNullOrWhiteSpace($systemPrompt)) {
    $escapedSystemPrompt = $systemPrompt -replace '"', '\"'
    $modelfileLines += "SYSTEM `"$escapedSystemPrompt`""
}

if (-not [string]::IsNullOrWhiteSpace($templateFormat)) {
    if ($templateFormat -in @("llama2", "mistral", "llama3", "chatml")) {
        $modelfileLines += "TEMPLATE `"$templateFormat`""
    } else {
        $modelfileLines += "TEMPLATE `"`n$templateFormat`n`""
    }
}

# Add advanced parameters if applicable
if ($repeat_penalty) {
    $modelfileLines += "PARAMETER repeat_penalty $repeat_penalty"
    if ($PSBoundParameters.ContainsKey("seed") -and $seed -ge 0) {
        $modelfileLines += "PARAMETER seed $seed"
    }
}

if ($stop_sequences -and $stop_sequences.Count -gt 0) {
    foreach ($seq in $stop_sequences) {
        $escapedSeq = $seq -replace '"', '\"'
        $modelfileLines += "PARAMETER stop `"$escapedSeq`""
    }
}

$modelfileContent = $modelfileLines -join "`n"
$modelfilePath = Join-Path -Path $tempDir -ChildPath "Modelfile"
$modelfileContent | Out-File -FilePath $modelfilePath -Encoding utf8

Write-Output ""
Write-Output "Modelfile created with the following content:"
Get-Content -Path $modelfilePath
Write-Output ""

# --- Import the Model ---

Write-ColorOutput "Importing model into Ollama (this may take a while)..." "Yellow"
Write-ColorOutput "The import process will copy the model to your Ollama models directory." "Yellow"
Write-Output ""

try {
    Push-Location -Path $tempDir
    & ollama create $modelName
    $importSuccess = $?
    Pop-Location

    if ($importSuccess) {
        Write-Output ""
        Write-ColorOutput "====================================================" "Green"
        Write-ColorOutput "Success! Your model has been imported." "Green"
        Write-Output ""
        Write-ColorOutput "You can now run your model with:" "Cyan"
        Write-ColorOutput "  ollama run $modelName" "White"
        Write-Output ""
        Write-ColorOutput "Or use the API with PowerShell:" "Cyan"
        Write-ColorOutput "  (Invoke-WebRequest -Method POST -Body '{""model"":""$modelName"", ""prompt"":""Hello"", ""stream"": false}' -Uri http://localhost:11434/api/generate ).Content | ConvertFrom-Json" "White"
        Write-ColorOutput "====================================================" "Green"

        # Save configuration for reference
        $configPath = Join-Path -Path (Get-Location) -ChildPath "$modelName-config.txt"
        $modelfileContent | Out-File -FilePath $configPath -Encoding utf8
        Write-ColorOutput "Model configuration saved to: $configPath" "Cyan"

        if (Get-YesNoInput -Prompt "Do you want to test the model with structured outputs?" -Default:$true) {
            Write-ColorOutput "Testing model with structured outputs..." "Cyan"
            Write-Output ""
            $scriptPath = Join-Path -Path (Get-Location) -ChildPath "simple_structured_output.py"
            if (-not (Test-Path -Path $scriptPath)) {
                Write-ColorOutput "Warning: simple_structured_output.py not found in the current directory." "Yellow"
                Write-ColorOutput "Please ensure it is available before testing." "Yellow"
            } else {
                Write-ColorOutput "Select a schema type for testing:" "Cyan"
                Write-ColorOutput "1. Friends list (simplest)" "White"
                Write-ColorOutput "2. Movies list" "White"
                Write-ColorOutput "3. Recipe (most complex)" "White"
                $schemaChoice = Read-Host "Enter your choice (1-3)"
                $schemaType = switch ($schemaChoice) {
                    "2" { "movies" }
                    "3" { "recipe" }
                    default { "friends" }
                }
                $testTemp = Get-NumericInput -Prompt "Temperature for generation (0.0-1.0, lower is more deterministic)" -Default 0.2 -Min 0.0 -Max 1.0
                try {
                    Write-ColorOutput "Running structured output test..." "Cyan"
                    & python3 simple_structured_output.py $modelName $schemaType --temperature $testTemp
                    if ($?) {
                        Write-ColorOutput "Test completed successfully!" "Green"
                    } else {
                        Write-ColorOutput "Test encountered issues. See output above for details." "Yellow"
                    }
                } catch {
                    Write-ColorOutput "Error running the test: $_" "Red"
                    Write-ColorOutput "Ensure Python and required packages are installed." "Yellow"
                }
            }
        }
    } else {
        Write-Output ""
        Write-ColorOutput "ERROR: Failed to import the model." "Red"
        Write-ColorOutput "Check the Ollama logs at %LOCALAPPDATA%\Ollama\server.log for more details." "Yellow"
    }
} catch {
    Write-ColorOutput "ERROR: An exception occurred while importing the model:" "Red"
    Write-ColorOutput $_.Exception.Message "Red"
    Write-ColorOutput "Check the Ollama logs at %LOCALAPPDATA%\Ollama\server.log for more details." "Yellow"
} finally {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
