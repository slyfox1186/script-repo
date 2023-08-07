/*____________________________________________________________________________________
    OpenWSLHere.ahk

    By:
    - SlyFox1186

    GitHub:
    - https://github.com/slyfox1186

    Pastebin:
    - https://pastebin.com/u/slyfox1186
    
    Purpose:
    - This will open Windows' WSL terminal to the active file explorer folder or if no active window is found, %A_WinDir%\System32

    Instructions:
    - You need to replace the below variable "_osName" with the wsl distribution of your choosing.
      - To find the available distros run "wsl.exe -l --all" using PowerShell to get a list of available options

    Updated:
    - 08.07.23

*/

!w up::_OpenWSLHere()

_OpenWSLHere()
{
    Static convert := " !#$%&'()-.*:?@[]^_``{|}~/"
    Static osName := "Debian"
    Static wt := "C:\Users\jholl\AppData\Local\Microsoft\WindowsApps\wt.exe"

    if FileExist("C:\Program Files\PowerShell\7\pwsh.exe")
        myexe := "C:\Program Files\PowerShell\7\pwsh.exe"
    else
        myexe := "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

    if WinActive("ahk_class CabinetWClass ahk_exe explorer.exe")
        winObj := ComObject("Shell.Application").Windows
    Else
    {
        Run A_ComSpec ' /D /C START "" /MIN "' myexe '" -NoP -W Hidden -C "Start-Process ' wt ' -Args `'-w new-tab C:\Windows\System32\wsl.exe -d \"' osName '\" --cd \"~\"`' -Verb RunAs'
        Return
    }

    For win in winObj
    {
            pwd := SubStr(win.LocationURL, 9)
            Loop Parse, convert
                hex := Format("{:X}" , Ord(A_LoopField))
                ,pwd := StrReplace(pwd, hex, A_LoopField)
                pwd := StrReplace(pwd, "%", "")
                pwd := StrReplace(pwd, "'", "''")
                pwd := StrReplace(pwd, pwd, '"' . pwd . '"')
     }

        Run A_ComSpec ' /D /C START "" /MIN "' myexe '" -NoP -W Hidden -C "Start-Process ' wt ' -Args `'-w new-tab C:\Windows\System32\wsl.exe -d \"' osName '\" --cd \"' pwd '\"`' -Verb RunAs'
}
