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

function Remove-OllamaModels {
    [CmdletBinding()]
    param()
    
    # Check if Ollama is installed
    if (-not (Test-Command -Command "ollama")) {
        Write-ColorOutput "ERROR: Ollama is not installed or not in your PATH." "Red"
        return
    }
    
    Write-ColorOutput "What would you like to do?" "Cyan"
    Write-ColorOutput "1. Delete installed models" "White"
    Write-ColorOutput "2. Clean orphaned manifest directories" "White"
    Write-ColorOutput "3. Return to main menu" "White"
    $cleanupOption = Read-Host "Choose option (1-3)"
    
    switch ($cleanupOption) {
        "1" {
            # Delete models - original functionality
            try {
                $ollamaOutput = & ollama list 2>$null
                if (-not $ollamaOutput -or $ollamaOutput.Count -eq 0) {
                    Write-ColorOutput "No models found in Ollama." "Yellow"
                    return
                }
                
                # Parse model names from output
                $models = @()
                $headerSkipped = $false
                
                foreach ($line in $ollamaOutput) {
                    if (-not $headerSkipped) {
                        $headerSkipped = $true
                        continue
                    }
                    
                    if (-not [string]::IsNullOrWhiteSpace($line)) {
                        $modelName = ($line -split '\s+')[0]
                        if (-not [string]::IsNullOrWhiteSpace($modelName)) {
                            $models += $modelName
                        }
                    }
                }
                
                if ($models.Count -eq 0) {
                    Write-ColorOutput "No models found in Ollama." "Yellow"
                    return
                }
                
                # Display models with numbers
                Write-ColorOutput "Installed models:" "Cyan"
                for ($i = 0; $i -lt $models.Count; $i++) {
                    Write-ColorOutput "$($i+1). $($models[$i])" "White"
                }
                
                # Get user input for models to delete
                Write-ColorOutput "Enter the numbers of models to delete (comma-separated, e.g., 1,3,5) or 'q' to cancel:" "Yellow"
                $userInput = Read-Host
                
                if ($userInput -eq 'q') {
                    Write-ColorOutput "Operation cancelled." "Yellow"
                    return
                }
                
                # Parse input and delete models
                $modelNumbers = $userInput -split ',' | ForEach-Object { $_.Trim() }
                $modelsToDelete = @()
                
                foreach ($num in $modelNumbers) {
                    try {
                        $index = [int]$num - 1
                        if ($index -ge 0 -and $index -lt $models.Count) {
                            $modelsToDelete += $models[$index]
                        } else {
                            Write-ColorOutput "Invalid model number: $num. Skipping." "Red"
                        }
                    } catch {
                        Write-ColorOutput "Invalid input: $num. Skipping." "Red"
                    }
                }
                
                if ($modelsToDelete.Count -eq 0) {
                    Write-ColorOutput "No valid models selected for deletion." "Yellow"
                    return
                }
                
                # Confirm deletion
                Write-ColorOutput "The following models will be deleted:" "Red"
                foreach ($model in $modelsToDelete) {
                    Write-ColorOutput "- $model" "White"
                }
                
                if (-not (Get-YesNoInput -Prompt "Are you sure you want to delete these models?" -Default:$false)) {
                    Write-ColorOutput "Operation cancelled." "Yellow"
                    return
                }
                
                # Delete models
                foreach ($model in $modelsToDelete) {
                    Write-ColorOutput "Deleting model: $model..." "Yellow"
                    & ollama rm $model
                    if ($LASTEXITCODE -eq 0) {
                        Write-ColorOutput "Successfully deleted model: $model" "Green"
                    } else {
                        Write-ColorOutput "Failed to delete model: $model" "Red"
                    }
                }
                
                # Ask if user wants to clean orphaned manifests
                if (Get-YesNoInput -Prompt "Would you like to clean orphaned manifest directories?" -Default:$true) {
                    Remove-OllamaOrphanedManifests
                }
                
            } catch {
                Write-ColorOutput "Error: $_" "Red"
            }
        }
        "2" {
            # Clean orphaned manifests
            Remove-OllamaOrphanedManifests
        }
        "3" {
            # Return to main menu
            return
        }
        default {
            Write-ColorOutput "Invalid option. Returning to main menu." "Yellow"
            return
        }
    }
}

function Remove-OllamaOrphanedManifests {
    [CmdletBinding()]
    param()
    
    # Check if Ollama is installed
    if (-not (Test-Command -Command "ollama")) {
        Write-ColorOutput "ERROR: Ollama is not installed or not in your PATH." "Red"
        return
    }
    
    # Get the model storage location
    $modelLocation = Get-OllamaModelLocation
    $manifestsDir = Join-Path -Path $modelLocation -ChildPath "manifests"
    
    if (-not (Test-Path -Path $manifestsDir)) {
        Write-ColorOutput "Manifests directory not found: $manifestsDir" "Red"
        return
    }
    
    # Get list of currently installed models from ollama list
    try {
        $ollamaOutput = & ollama list 2>$null
        if (-not $ollamaOutput -or $ollamaOutput.Count -eq 0) {
            Write-ColorOutput "No models found in Ollama." "Yellow"
            return
        }
        
        # Parse model names from output
        $installedModels = @()
        $headerSkipped = $false
        
        foreach ($line in $ollamaOutput) {
            if (-not $headerSkipped) {
                $headerSkipped = $true
                continue
            }
            
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $modelName = ($line -split '\s+')[0]
                if (-not [string]::IsNullOrWhiteSpace($modelName)) {
                    # Extract base model name (before the colon)
                    if ($modelName -match "^([^:]+)") {
                        $baseModelName = $matches[1]
                        $installedModels += $baseModelName.ToLower()
                    } else {
                        $installedModels += $modelName.ToLower()
                    }
                }
            }
        }
        
        # Get all model directories in the manifests folder
        $manifestFolders = Get-ChildItem -Path $manifestsDir -Directory -Recurse | Where-Object {
            # Only include leaf directories that might contain model files
            $_.GetDirectories().Count -eq 0 -or 
            $_.GetFiles().Count -gt 0 -or 
            $_.FullName -match "library\\[^\\]+$"
        }
        
        if ($manifestFolders.Count -eq 0) {
            Write-ColorOutput "No model directories found in the manifests directory." "Yellow"
            return
        }
        
        # Find directories that don't correspond to installed models
        $orphanedDirs = @()
        foreach ($dir in $manifestFolders) {
            $dirName = $dir.Name.ToLower()
            $isOrphaned = $true
            
            # Check if this directory corresponds to an installed model
            foreach ($model in $installedModels) {
                if ($dirName -eq $model -or $dir.FullName -match "\\$model$") {
                    $isOrphaned = $false
                    break
                }
            }
            
            # Special case for registry.ollama.ai/library directories
            if ($dir.FullName -match "registry\.ollama\.ai\\library$") {
                $isOrphaned = $false
            }
            
            # Skip the registry.ollama.ai directory itself
            if ($dir.FullName -match "registry\.ollama\.ai$") {
                $isOrphaned = $false
            }
            
            if ($isOrphaned) {
                $orphanedDirs += $dir
            }
        }
        
        if ($orphanedDirs.Count -eq 0) {
            Write-ColorOutput "No orphaned model directories found." "Green"
            return
        }
        
        # Display orphaned directories with numbers
        Write-ColorOutput "Found the following orphaned model directories:" "Cyan"
        for ($i = 0; $i -lt $orphanedDirs.Count; $i++) {
            Write-ColorOutput "$($i+1). $($orphanedDirs[$i].FullName)" "White"
        }
        
        # Get user input for directories to delete
        Write-ColorOutput "Enter the numbers of directories to delete (comma-separated, e.g., 1,3,5), 'all' to delete all, or 'q' to cancel:" "Yellow"
        $userInput = Read-Host
        
        if ($userInput -eq 'q') {
            Write-ColorOutput "Operation cancelled." "Yellow"
            return
        }
        
        $dirsToDelete = @()
        
        if ($userInput.ToLower() -eq 'all') {
            $dirsToDelete = $orphanedDirs
        } else {
            # Parse input and select directories
            $dirNumbers = $userInput -split ',' | ForEach-Object { $_.Trim() }
            
            foreach ($num in $dirNumbers) {
                try {
                    $index = [int]$num - 1
                    if ($index -ge 0 -and $index -lt $orphanedDirs.Count) {
                        $dirsToDelete += $orphanedDirs[$index]
                    } else {
                        Write-ColorOutput "Invalid directory number: $num. Skipping." "Red"
                    }
                } catch {
                    Write-ColorOutput "Invalid input: $num. Skipping." "Red"
                }
            }
        }
        
        if ($dirsToDelete.Count -eq 0) {
            Write-ColorOutput "No valid directories selected for deletion." "Yellow"
            return
        }
        
        # Confirm deletion
        Write-ColorOutput "The following directories will be deleted:" "Red"
        foreach ($dir in $dirsToDelete) {
            Write-ColorOutput "- $($dir.FullName)" "White"
        }
        
        if (-not (Get-YesNoInput -Prompt "Are you sure you want to delete these directories?" -Default:$false)) {
            Write-ColorOutput "Operation cancelled." "Yellow"
            return
        }
        
        # Delete directories
        foreach ($dir in $dirsToDelete) {
            Write-ColorOutput "Deleting directory: $($dir.FullName)..." "Yellow"
            try {
                Remove-Item -Path $dir.FullName -Recurse -Force
                Write-ColorOutput "Successfully deleted directory: $($dir.FullName)" "Green"
            } catch {
                Write-ColorOutput "Failed to delete directory: $($dir.FullName)" "Red"
                Write-ColorOutput "Error: $_" "Red"
            }
        }
        
    } catch {
        Write-ColorOutput "Error: $_" "Red"
    }
}

function Get-AvailableTemplateFormats {
    [CmdletBinding()]
    param()
    
    # Initialize with standard templates that are always available
    $templates = @(
        @{Name = "Default (model-specific)"; Value = "default"},
        @{Name = "Llama 2"; Value = "llama2"},
        @{Name = "Mistral"; Value = "mistral"},
        @{Name = "Llama 3"; Value = "llama3"},
        @{Name = "ChatML"; Value = "chatml"}
    )
    
    # Try to get installed models from Ollama
    try {
        # Check if Ollama is installed and running
        if (Test-Command -Command "ollama") {
            try {
                $ollamaOutput = & ollama list 2>$null
                $ollamaModels = $ollamaOutput -join "`n"
                
                # Create a hashtable to track which model families we've already added
                $addedModelFamilies = @{}
                
                # Check for specific model families in the installed models
                if ($ollamaModels -match "Mistral-Small-24B-Instruct" -and -not $addedModelFamilies.ContainsKey("mistral-small")) {
                    $templates += @{
                        Name = "Mistral-Small-24B-Instruct"; 
                        Value = "{{ if .System }}<s>[SYSTEM_PROMPT]{{.System}}[/SYSTEM_PROMPT]{{ end }}{{ if .Prompt }}[INST]{{.Prompt}}[/INST]{{ end }}"
                    }
                    $addedModelFamilies["mistral-small"] = $true
                }
                
                if (($ollamaModels -match "deepseek-r1" -or $ollamaModels -match "DeepSeek-R1") -and -not $addedModelFamilies.ContainsKey("deepseek")) {
                    $templates += @{
                        Name = "DeepSeek-R1"; 
                        Value = "{{ if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}{{ if .Prompt }}<|im_start|>user
{{ .Prompt }}<|im_end|>
{{ end }}<|im_start|>assistant"
                    }
                    $addedModelFamilies["deepseek"] = $true
                }
                
                # Add other model-specific templates based on installed models
                if ($ollamaModels -match "llama3\.2" -and -not $addedModelFamilies.ContainsKey("llama3.2")) {
                    $templates += @{Name = "Llama 3.2"; Value = "llama3.2"}
                    $addedModelFamilies["llama3.2"] = $true
                }
                
                if ($ollamaModels -match "mistral:7b-instruct" -and -not $addedModelFamilies.ContainsKey("mistral-instruct")) {
                    $templates += @{Name = "Mistral 7B Instruct"; Value = "mistral-instruct"}
                    $addedModelFamilies["mistral-instruct"] = $true
                }
                
                # Look for other potential model families
                if ($ollamaModels -match "phi" -and -not $addedModelFamilies.ContainsKey("phi")) {
                    $templates += @{Name = "Phi"; Value = "phi"}
                    $addedModelFamilies["phi"] = $true
                }
                
                if ($ollamaModels -match "qwen" -and -not $addedModelFamilies.ContainsKey("qwen")) {
                    $templates += @{Name = "Qwen"; Value = "qwen"}
                    $addedModelFamilies["qwen"] = $true
                }
                
                if ($ollamaModels -match "gemma" -and -not $addedModelFamilies.ContainsKey("gemma")) {
                    $templates += @{Name = "Gemma"; Value = "gemma"}
                    $addedModelFamilies["gemma"] = $true
                }
                
                if ($ollamaModels -match "claude" -and -not $addedModelFamilies.ContainsKey("claude")) {
                    $templates += @{Name = "Claude"; Value = "claude"}
                    $addedModelFamilies["claude"] = $true
                }
            } catch {
                Write-ColorOutput "Warning: Error retrieving installed models: $_" "Yellow"
            }
        } else {
            Write-ColorOutput "Warning: Ollama command not found. Using standard templates only." "Yellow"
        }
    } catch {
        Write-ColorOutput "Warning: Error checking for Ollama: $_" "Yellow"
    }
    
    # Always add custom option at the end
    $templates += @{Name = "Custom"; Value = "custom"}
    
    return $templates
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

function Get-ModelType {
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

# --- Main Menu ---
Write-ColorOutput "What would you like to do?" "Cyan"
Write-ColorOutput "1. Import a GGUF model" "White"
Write-ColorOutput "2. Use an existing model from the Ollama manifests directory" "White"
Write-ColorOutput "3. Delete existing models" "White"
$mainOption = Read-Host "Choose option (1-3)"

switch ($mainOption) {
    "3" {
        # Delete models
        Remove-OllamaModels
        exit 0
    }
    "2" {
        # Use existing model from manifests
        $pathOption = "2"
    }
    default {
        # Import a new GGUF model
        $pathOption = "1"
    }
}

$modelDir = $null
$fileSize = 0

switch ($pathOption) {
    "2" {
        $manifestsDir = Join-Path -Path $modelLocation -ChildPath "manifests"
        if (-not (Test-Path -Path $manifestsDir)) {
            Write-ColorOutput "Manifests directory not found: $manifestsDir" "Red"
            exit 1
        }
        
        # Get list of currently installed models from ollama list
        try {
            $ollamaOutput = & ollama list 2>$null
            $installedModels = @()
            
            if ($ollamaOutput -and $ollamaOutput.Count -gt 0) {
                $headerSkipped = $false
                foreach ($line in $ollamaOutput) {
                    if (-not $headerSkipped) {
                        $headerSkipped = $true
                        continue
                    }
                    if (-not [string]::IsNullOrWhiteSpace($line)) {
                        $modelInfo = $line -split '\s+'
                        if ($modelInfo.Count -ge 1) {
                            $modelName = $modelInfo[0]
                            $installedModels += @{
                                Name = $modelName
                                Directory = Join-Path -Path $manifestsDir -ChildPath "registry.ollama.ai\library\$($modelName.Split(':')[0])"
                            }
                        }
                    }
                }
            }
            
            if ($installedModels.Count -eq 0) {
                Write-ColorOutput "No models found in Ollama. Please install a model first or use option 1 to import a new model." "Yellow"
                exit 1
            }
            
            # Display models with numbers
            Write-ColorOutput "Available models:" "Cyan"
            for ($i = 0; $i -lt $installedModels.Count; $i++) {
                Write-ColorOutput "$($i+1). $($installedModels[$i].Name)" "White"
            }
            
            $manifestChoice = Read-Host "Select a model (number)"
            try {
                $index = [int]$manifestChoice - 1
                if ($index -lt 0 -or $index -ge $installedModels.Count) {
                    Write-ColorOutput "Invalid selection." "Red"
                    exit 1
                }
                $modelDir = $installedModels[$index].Directory
                $modelName = $installedModels[$index].Name.Split(':')[0]
                Write-ColorOutput "Selected model: $modelName" "Green"
                Write-ColorOutput "Model directory: $modelDir" "Green"
            } catch {
                Write-ColorOutput "Invalid input. Please enter a valid number." "Red"
                exit 1
            }
        } catch {
            Write-ColorOutput "Error retrieving models: $_" "Red"
            
            # Fallback to directory listing if model retrieval fails
            Write-ColorOutput "Falling back to directory listing..." "Yellow"
            $manifestFolders = Get-ChildItem -Path (Join-Path -Path $manifestsDir -ChildPath "registry.ollama.ai\library") -Directory -ErrorAction SilentlyContinue
            
            if (-not $manifestFolders -or $manifestFolders.Count -eq 0) {
                Write-ColorOutput "No models found in the manifests directory." "Yellow"
                exit 1
            }
            
            Write-ColorOutput "Available models in manifests directory:" "Cyan"
            for ($i = 0; $i -lt $manifestFolders.Count; $i++) {
                Write-ColorOutput "$($i+1). $($manifestFolders[$i].Name)" "White"
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
$modelType = Get-ModelType -ModelPath $modelPath -ModelDir $modelDir
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
        Write-ColorOutput "- Template: {{ if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}{{ if .Prompt }}<|im_start|>user
{{ .Prompt }}<|im_end|>
{{ end }}<|im_start|>assistant" "White"
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
            $contextSize   = 10000
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
            $contextSize   = 10000
            $systemPrompt  = $deepSeekSystemPrompt
            $templateFormat = "{{ if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}{{ if .Prompt }}<|im_start|>user
{{ .Prompt }}<|im_end|>
{{ end }}<|im_start|>assistant"
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
            $templateFormat = "{{ if .System }}{{.System}}

{{ end }}{{ if .Prompt }}User: {{.Prompt}}{{ end }}"
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
            $seed = Get-NumericInput -Prompt "Random seed (-1 = random, 0-1337)" -Default -1 -Min -1 -Max 1337
        }
    }
    Write-Output ""
    if (Get-YesNoInput -Prompt "Configure the chat template format?" -Default:$false) {
        $templateFormats = Get-AvailableTemplateFormats
        
        Write-ColorOutput "Template Formats:" "Cyan"
        for ($i = 0; $i -lt $templateFormats.Count; $i++) {
            Write-ColorOutput "$($i+1). $($templateFormats[$i].Name)" "White"
        }
        
        $maxChoice = $templateFormats.Count
        $templateChoice = Read-Host "Select a template format (1-$maxChoice)"
        
        try {
            $index = [int]$templateChoice - 1
            if ($index -lt 0 -or $index -ge $templateFormats.Count) {
                Write-ColorOutput "Invalid selection. Using default template." "Yellow"
                $templateFormat = "default"
            } else {
                $selectedTemplate = $templateFormats[$index]
                
                if ($selectedTemplate.Value -eq "custom") {
                    Write-ColorOutput "Enter custom template (use {{.System}}, {{.Prompt}}, {{.Response}} placeholders):" "Cyan"
                    $lines = @()
                    while ($true) {
                        $line = Read-Host
                        if ([string]::IsNullOrWhiteSpace($line)) { break }
                        $lines += $line
                    }
                    $templateFormat = $lines -join "`n"
                } else {
                    $templateFormat = $selectedTemplate.Value
                }
            }
        } catch {
            Write-ColorOutput "Invalid input. Using default template." "Yellow"
            $templateFormat = "default"
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
    # Handle the template format based on its value
    if ($templateFormat -eq "default") {
        # Don't add a TEMPLATE directive for default
    } elseif ($templateFormat -in @("llama2", "mistral", "llama3", "chatml", "llama3.2", "mistral-instruct")) {
        # Use the predefined template name
        $modelfileLines += "TEMPLATE `"$templateFormat`""
    } else {
        # Use the custom template format
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

        # Automatically run the model
        Write-ColorOutput "Starting the model. Press Ctrl+C to exit when done." "Yellow"
        Write-Output ""
        & Clear-Host; ollama run $modelName

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
