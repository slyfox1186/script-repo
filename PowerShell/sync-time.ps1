# Ensure the Windows Time service is set to automatic and start the service
Set-Service -Name W32Time -StartupType Automatic
Start-Service -Name W32Time

# Force synchronization of the time
w32tm /resync /force

# Add a scheduled task to run this command at system startup
$ScriptBlock = {
    Set-Service -Name W32Time -StartupType Automatic
    Start-Service -Name W32Time
    w32tm /resync /force
}
$EncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptBlock.ToString()))

$Action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-EncodedCommand $EncodedCommand"
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

# Register the task if it does not already exist
$TaskName = "SyncTimeOnStartup"
if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Description "Sync system time on startup"
}

# Output status
Write-Output "System time synchronization setup is completed."
