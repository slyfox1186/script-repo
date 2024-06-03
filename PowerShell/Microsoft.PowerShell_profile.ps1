# Function to initialize profile tasks
function Initialize-ProfileTasks {
    # Ensure TLS 1.2 is used
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Set execution policy to unrestricted
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine
    Set-PSRepository -Name 'PSGallery' -SourceLocation 'https://www.powershellgallery.com/api/v2' -InstallationPolicy Trusted

    # Register PowerShell Gallery as a package source if not already registered
    $psGallerySource = Get-PackageSource -Name "PSGallery" -ErrorAction SilentlyContinue
    if (-not $psGallerySource) {
        Write-Host "Registering PSGallery..." -ForegroundColor Cyan
        Register-PackageSource -Name "PSGallery" -ProviderName "PowerShellGet" -Location "https://www.powershellgallery.com/api/v2" -Trusted 2>$null
    } else {
        Set-PackageSource -Name "PSGallery" -Trusted 2>$null
    }

    # Update help for all modules if not updated in the last 7 days
    $helpUpdateLog = "$env:LOCALAPPDATA\PowerShellHelpUpdate.log"
    $updateIntervalDays = 7

    if (Test-Path $helpUpdateLog) {
        $lastUpdate = Get-Content $helpUpdateLog -Raw | Out-String
        $lastUpdateDate = [DateTime]::Parse($lastUpdate)
        $daysSinceLastUpdate = (New-TimeSpan -Start $lastUpdateDate -End (Get-Date)).Days
    } else {
        $daysSinceLastUpdate = $updateIntervalDays + 1
    }

    if ($daysSinceLastUpdate -gt $updateIntervalDays) {
        try {
            Update-Help -Force -UICulture en-US
            Set-Content -Path $helpUpdateLog -Value (Get-Date).ToString()
        } catch {
            Write-Warning "Failed to update Help for some modules: $($_.Exception.Message)"
        }
    }

    # Ensure PowerShellGet is loaded properly
    try {
        Import-Module PowerShellGet -ErrorAction Stop
    } catch {
        Write-Host "PowerShellGet module not found. Installing..." -ForegroundColor Yellow
        Install-Module -Name PowerShellGet -Scope CurrentUser -Force
        Import-Module PowerShellGet -ErrorAction Stop
    }

    # List of additional useful modules to import
    $additionalModules = @(
        'ActiveDirectory',                       # Active Directory module (part of RSAT)
        'CredentialManager',                     # Manage credentials securely
        'Microsoft.PowerShell.SecretManagement', # Secret management
        'Microsoft.PowerShell.SecretStore',      # Secret store
        'PSExcel',                               # For working with Excel files
        'PSReadLine',                            # Improved command line editing
        'PSWindowsUpdate'                        # For managing Windows updates
    )

    # Install and import additional useful modules
    foreach ($module in $additionalModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Host "Installing module $module..." -ForegroundColor Cyan
            try {
                Install-Module -Name $module -Scope CurrentUser -Force
            } catch {
                Write-Error "Failed to import module ${module}: $($_.Exception.Message)"
            }
        }
        try {
            Import-Module $module -Force -Verbose
        } catch {
            Write-Error "Failed to import module ${module}: $($_.Exception.Message)"
        }
    }
}

# Initialize profile tasks in background job
Start-Job -ScriptBlock {
    Initialize-ProfileTasks
}

# Optionally set window title for notification
$host.UI.RawUI.WindowTitle = "Profile Initialization Complete"
