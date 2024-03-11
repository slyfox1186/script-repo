function Set-FWBuddy {
<#
.SYNOPSIS
Creates or removes firewall rules for specified IP addresses or domains.

.DESCRIPTION
This function allows adding or removing inbound, outbound, or both types of firewall rules for specified IP addresses or domains.

.PARAMETER Target
The IP address(es) or domain name(s) to create or remove the firewall rule for.

.PARAMETER Action
The action to perform: 'Add' or 'Remove' the firewall rule.

.PARAMETER RuleType
The type of firewall rule to manage: 'Inbound', 'Outbound', or 'Both'.

.EXAMPLE
Set-FWBuddy -Target "192.168.1.1" -Action Add -RuleType Inbound

Adds an inbound firewall rule for the IP address 192.168.1.1.

.EXAMPLE
Set-FWBuddy -Target "example.com" -Action Remove -RuleType Both

Removes both inbound and outbound firewall rules for the domain example.com.

.NOTES
This function must be run with administrative privileges.
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Target,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Add', 'Remove')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Inbound', 'Outbound', 'Both')]
        [string]$RuleType
    )

    begin {
        # Check if running with administrative privileges
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw "This function must be run as an administrator."
        }

        # Map RuleType to directions
        $ruleDirections = switch ($RuleType) {
            'Inbound' { 'Inbound' }
            'Outbound' { 'Outbound' }
            'Both' { 'Inbound', 'Outbound' }
        }
    }

    process {
        foreach ($t in $Target) {
            # Resolve target to IP addresses for domains
            $ipAddresses, $targetType = if ($t -match "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$") {
                @($t), 'IP'
            } else {
                try {
                    @([System.Net.Dns]::GetHostAddresses($t) | Select-Object -ExpandProperty IPAddressToString), 'Domain'
                } catch {
                    Write-Error "Failed to resolve $t to an IP address. Error: $_"
                    continue
                }
            }

            if ($ipAddresses.Count -eq 0) {
                Write-Error "No IP addresses found for $t"
                continue
            }

            foreach ($ipAddress in $ipAddresses) {
                foreach ($direction in $ruleDirections) {
                    $ruleName = "Block $targetType $t ($direction)"
                    $ruleExists = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

                    switch ($Action) {
                        'Add' {
                            if ($ruleExists) {
                                Write-Output "Firewall rule '$ruleName' already exists."
                            } else {
                                New-NetFirewallRule -DisplayName $ruleName -Direction $direction -LocalPort Any -Protocol Any -Action Block -RemoteAddress $ipAddress
                                Write-Output "Firewall rule '$ruleName' created for IP address $ipAddress."
                            }
                        }
                        'Remove' {
                            if ($ruleExists) {
                                Remove-NetFirewallRule -DisplayName $ruleName
                                Write-Output "Firewall rule '$ruleName' removed."
                            } else {
                                Write-Output "Firewall rule '$ruleName' does not exist."
                            }
                        }
                    }
                }
            }
        }
    }
}
