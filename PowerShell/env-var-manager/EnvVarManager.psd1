@{
    ModuleVersion     = '1.0.0'
    GUID              = 'b8255ae8-b2c5-4fa9-9b07-ed63dd16e71c'
    Author            = 'Jeff Hollis'
    CompanyName       = 'Unknown'
    Copyright         = Copyright = '(c) 2024 Jeff Hollis. All rights reserved.'
    Description       = 'PowerShell module for managing system and user environment variables.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Get-EnvironmentVariable', 'Set-EnvironmentVariable', 'Remove-EnvironmentVariable')
    AliasesToExport   = @()
    CmdletsToExport   = @()
    VariablesToExport = @()
    ModuleList        = @()
    FileList          = @('EnvVarManager.psm1')
    PrivateData       = @{
        PSData = @{
            Tags         = @('EnvironmentVariables', 'System', 'Configuration')
            ProjectUri   = ''
            LicenseUri   = ''
            ReleaseNotes = 'Initial release'
        }
    }
}
