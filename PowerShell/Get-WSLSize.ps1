# Function to prompt user for WSL distro name and get WSL size
function Get-WSLSize {
    param (
        [string]$DistroName = $(
            # Display available WSL distros
            $availableDistros = wsl.exe -l --all
            Write-Host "Available WSL distros:" -ForegroundColor Cyan
            $availableDistros | ForEach-Object { Write-Host $_ }

            # Prompt user to enter the distro name
            Read-Host -Prompt 'Please enter the WSL distro name'
        )
    )

    # Ensure the distro name is not empty
    if (-not $DistroName) {
        Write-Host "Distro name cannot be empty." -ForegroundColor Red
        return
    }

    # Run the WSL df command for the entered distro name
    try {
        wsl.exe --system -d $DistroName df -h /mnt/wslg/distro
    }
    catch {
        Write-Host "Error: Failed to execute WSL command for distro '$DistroName'." -ForegroundColor Red
    }
}
