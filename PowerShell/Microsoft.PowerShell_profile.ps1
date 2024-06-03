# Ensure TLS 1.2 is used
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Set execution policy to unrestricted
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Register PowerShell Gallery as a package source if not already registered
$psGallerySource = Get-PackageSource -Name "PSGallery" -ErrorAction SilentlyContinue
if (-not $psGallerySource) {
    Write-Output "Registering PSGallery..."
    Register-PackageSource -Name "PSGallery" -ProviderName "PowerShellGet" -Location "https://www.powershellgallery.com/api/v2" -Trusted 2>$null
} else {
    Set-PackageSource -Name "PSGallery" -Trusted 2>$null
}

# Register NuGet as a package source if not already registered
$nuGetSource = Get-PackageSource -Name "NuGet" -ErrorAction SilentlyContinue
if (-not $nuGetSource) {
    Write-Output "Registering NuGet..."
    Register-PackageSource -Name "NuGet" -ProviderName "NuGet" -Location "https://www.nuget.org/api/v2" -Trusted 2>$null
} else {
    Set-PackageSource -Name "NuGet" -Trusted 2>$null
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

# Check if PowerShellGet is already imported
if (-not (Get-Module -ListAvailable -Name "PowerShellGet")) {
    # Install and import PowerShellGet module if not already present
    Write-Output "Installing PowerShellGet module..."
    Install-Module -Name PowerShellGet -Force -Scope CurrentUser
    Update-Module -Name PowerShellGet
}

# Import PowerShellGet module
Import-Module PowerShellGet -ErrorAction SilentlyContinue

# Check and import necessary modules
$modules = @('PackageManagement', 'PowerShellGet')
foreach ($module in $modules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Output "Installing module $module..."
        Install-Module -Name $module -Scope CurrentUser -Force
    }
    try {
        Import-Module $module -ErrorAction Stop
    } catch {
        Write-Error "Failed to import module ${module}: $($_.Exception.Message)"
    }
}

# Additional configurations (if any)
