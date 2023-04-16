# SUSPEND ROCKETLEAGUE TO FREE UP RESOURCES WHILE TWO INSTANCES ARE RUNNING AT THE SAME TIME.
# THIS SCRIPT ACTS AS A TOGGLE SO JUST RUN IT AND UNCOMMENT ONLY ONE OF THE TWO VARIABLES
# BELOW TO SELECT THE PROCESS YOU WANT THE SCRIPT TO ACT UPON.
# UNCOMMENT ONLY ONE OF THE TWO VARIABLES BELOW THIS LINE.

# $exeFile = 'C:\Program Files (x86)\Steam\steamapps\common\rocketleague\Binaries\Win64\RocketLeague.exe'
# $exeFile = 'I:\Epic\rocketleague\Binaries\Win64\RocketLeague.exe'

Get-Process -Name 'RocketLeague' | 
Where-Object{ $_.Path -eq $exeFile }|
ForEach-Object {    
    If($_.Responding) {        
        Start-Process cmd.exe -WindowStyle H -ArgumentList "/D /C pssuspend.exe -nobanner $($_.Id)"
        } 
    ElseIf(!$_.Responding) {
        Start-Process cmd.exe -WindowStyle H -ArgumentList "/D /C pssuspend.exe -nobanner -r $($_.Id)"
    }
}
