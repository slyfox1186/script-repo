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
    - 08.16.23

*/

!w up::_OpenWSLHere()

return

_OpenWSLHere()
{
    Static convert := " #$%&'()-.*:?@[]^_``{}|~/"
    Static osName := 'Debian'
    Static wt := 'C:\Users\jholl\AppData\Local\Microsoft\WindowsApps\wt.exe'
    Static wsl := 'C:\Windows\System32\wsl.exe'
    Static win := 'ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe'

    if FileExist('C:\Program Files\PowerShell\7\pwsh.exe')
        pshell := 'C:\Program Files\PowerShell\7\pwsh.exe'
    else
        pshell := 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'

    if WinActive('ahk_class CabinetWClass ahk_exe explorer.exe')
        winObj := ComObject('Shell.Application').Windows
    Else
    {
        Run pshell ' -NoP -W Hidden -C "Start-Process ' . wt . ' -Args `'-w new-tab ' . wsl . ' -d ' . osName . ' --cd ~ `' -Verb RunAs"'
        If WinWait(win,, 3)
        {
            WinActivate(win)
            return
        }
    }

    For win in winObj
    {
            pwd := SubStr(win.LocationURL, 9)
            Loop Parse, convert
                hex := Format("{:X}" , Ord(A_LoopField)),pwd := StrReplace(pwd, "%" . hex, A_LoopField)
                pwd := StrReplace(pwd, "%", "")
                pwd := StrReplace(pwd, "'", "''")
                pwd := StrReplace(pwd, pwd, '"' . pwd . '"')
                pwd := RegExReplace(pwd, 'sl.localhost/Debian', '')

        Run pshell ' -NoP -W Hidden -C "Start-Process ' . wt . ' -Args `'-w new-tab ' . wsl . ' -d ' . osName . ' --cd \"' . pwd . '\" `' -Verb RunAs"'
        If WinWait(win,, 3)
        {
            WinActivate(win)
            return
        }
    }
}
