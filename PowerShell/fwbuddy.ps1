# Check if the script is running with administrative privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as an administrator. Please start PowerShell as an administrator and run the script again."
    exit 1
}

# Check if any IP addresses or domains are provided as arguments
if ($args.Count -eq 0) {
    Write-Error "Please provide one or more IP addresses or domains as arguments to the script."
    exit 1
}

# Prompt the user to add or remove a rule
$action = Read-Host "Do you want to add or remove a firewall rule?
1. Add
2. Remove
Enter your choice (1-2)"

# Map the user's choice to the corresponding action
$ruleAction = switch ($action) {
    '1' { 'Add' }
    '2' { 'Remove' }
}

# Prompt the user to select the type of firewall rule
Write-Host
$ruleType = Read-Host "Select the type of firewall rule:
1. Inbound
2. Outbound
3. Both
Enter your choice (1-3)"

# Map the user's choice to the corresponding firewall rule directions
$ruleDirections = switch ($ruleType) {
    '1' { 'Inbound' }
    '2' { 'Outbound' }
    '3' { 'Inbound', 'Outbound' }
}

# Iterate through each IP address or domain provided as an argument
foreach ($target in $args) {
    # Determine if the target is an IP address or a domain
    if ($target -match "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$") {
        $targetType = "IP"
        $ipAddresses = @($target)
    }
    else {
        try {
            $targetType = "Domain"
            $ipAddresses = [System.Net.Dns]::GetHostAddresses($target) | Select-Object -ExpandProperty IPAddressToString
            if ($ipAddresses.Count -eq 0) {
                throw "No IP addresses found for $target"
            }
        }
        catch {
            Write-Error "Failed to resolve $target to an IP address. Error: $_"
            continue
        }
    }

    foreach ($ipAddress in $ipAddresses) {
        foreach ($direction in $ruleDirections) {
            # Create or remove the Firewall rule based on the user's choice
            $ruleName = "Block $targetType $target ($direction)"

            if ($ruleAction -eq 'Add') {
                $ruleExists = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

                if ($ruleExists) {
                    Write-Warning "Firewall rule '$ruleName' already exists. Skipping..."
                }
                else {
                    New-NetFirewallRule -DisplayName $ruleName -Direction $direction -LocalPort Any -Protocol Any -Action Block -RemoteAddress $ipAddress
                    Write-Host "Firewall rule '$ruleName' created successfully for IP address $ipAddress."
                }
            }
            elseif ($ruleAction -eq 'Remove') {
                $ruleExists = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

                if ($ruleExists) {
                    Remove-NetFirewallRule -DisplayName $ruleName
                    Write-Host "Firewall rule '$ruleName' removed successfully."
                }
                else {
                    Write-Warning "Firewall rule '$ruleName' does not exist. Skipping..."
                }
            }
        }
    }
}
