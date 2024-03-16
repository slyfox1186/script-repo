<#
.SYNOPSIS
Gets one or all environment variables for the specified scope.

.DESCRIPTION
The Get-EnvironmentVariable function retrieves the value of an environment variable for the current user or the local machine. If no name is provided, it returns all environment variables for the specified scope.

.PARAMETER Name
The name of the environment variable to retrieve. If not specified, all environment variables for the scope are returned.

.PARAMETER Scope
Specifies the scope of the environment variable. Valid values are "User" and "Machine". The default is "Machine".

.EXAMPLE
Get-EnvironmentVariable -Name PATH -Scope User

Gets the value of the PATH environment variable for the current user.

.EXAMPLE
Get-EnvironmentVariable -Scope Machine

Gets all environment variables for the local machine.
#>
function Get-EnvironmentVariable {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Name,

        [Parameter(Mandatory=$false)]
        [ValidateSet("User", "Machine")]
        [string]$Scope = "Machine"
    )

    If ($Name) {
        [System.Environment]::GetEnvironmentVariable($Name, $Scope)
    }
    else {
        [System.Environment]::GetEnvironmentVariables($Scope)
    }
}

<#
.SYNOPSIS
Sets an environment variable for the specified scope.

.DESCRIPTION
The Set-EnvironmentVariable function creates or modifies an environment variable for the current user or the local machine.

.PARAMETER Name
The name of the environment variable to set.

.PARAMETER Value
The value to assign to the environment variable.

.PARAMETER Scope
Specifies the scope of the environment variable. Valid values are "User" and "Machine". The default is "Machine".

.EXAMPLE
Set-EnvironmentVariable -Name MY_VARIABLE -Value "MyValue" -Scope User

Sets the MY_VARIABLE environment variable to "MyValue" for the current user.
#>
function Set-EnvironmentVariable {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Name,

        [Parameter(Mandatory=$true)]
        [string]$Value,

        [Parameter(Mandatory=$false)]
        [ValidateSet("User", "Machine")]
        [string]$Scope = "Machine"
    )

    [System.Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
    Write-Output "Environment variable `'$Name`' set to `'$Value`' for `'$Scope`' scope."
}

<#
.SYNOPSIS
Removes an environment variable from the specified scope.

.DESCRIPTION
The Remove-EnvironmentVariable function deletes an environment variable for the current user or the local machine.

.PARAMETER Name
The name of the environment variable to remove.

.PARAMETER Scope
Specifies the scope of the environment variable. Valid values are "User" and "Machine". The default is "Machine".

.EXAMPLE
Remove-EnvironmentVariable -Name MY_VARIABLE -Scope User

Removes the MY_VARIABLE environment variable for the current user.
#>
function Remove-EnvironmentVariable {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Name,

        [Parameter(Mandatory=$false)]
        [ValidateSet("User", "Machine")]
        [string]$Scope = "Machine"
    )

    [System.Environment]::SetEnvironmentVariable($Name, $null, $Scope)
    Write-Output "Environment variable `'$Name`' removed from `'$Scope`' scope."
}
