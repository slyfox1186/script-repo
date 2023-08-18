/*____________________________________________________________________________________
    OpenWSLHere.ahk

    GitHub:
    - https://github.com/slyfox1186

    Pastebin:
    - https://pastebin.com/u/slyfox1186
    
    Purpose:
    - This will open Windows' WSL terminal to the active file explorer folder or if no active explorer window is found, ~

    Instructions:
    - You need to replace the below variable '_osName' with the wsl distribution of your choosing.
      - To find the available distros run 'wsl.exe -l --all' using PowerShell to get a list of available options

    Updated:
    - 08.18.23

*/

!w up::_OpenWSLHere()
return

_OpenWSLHere()
{
    Static convert := " #$%&'()-.*:?@[]^_``{}|~/"
    Static osName := 'Debian'
    Static wt := 'C:\Users\' . A_UserName . '\AppData\Local\Microsoft\WindowsApps\wt.exe'
    Static wsl := 'C:\Windows\System32\wsl.exe'
    Static win := 'ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe'

    if FileExist('C:\Program Files\PowerShell\7\pwsh.exe')
        pshell := 'C:\Program Files\PowerShell\7\pwsh.exe'
    else
        pshell := 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'

    if WinActive('ahk_class CabinetWClass ahk_exe explorer.exe')
        winObj := ComObject('Shell.Application').Windows
    else
    {
        Run pshell ' -NoP -W Hidden -C "Start-Process ' . wt . ' -Args `'-w new-tab ' . wsl . ' -d ' . osName . ' --cd ~ `' -Verb RunAs"'
        if WinWait(win,, 2)
            WinActivate(win)
    }

    for win in winObj
    {
            pwd := SubStr(win.LocationURL, 9)
            Loop Parse, convert
                hex := Format("{:X}" , Ord(A_LoopField)),pwd := StrReplace(pwd, "%" . hex, A_LoopField)
                pwd := StrReplace(pwd, "%", "")
                pwd := StrReplace(pwd, "'", "''")
                pwd := StrReplace(pwd, pwd, '"' . pwd . '"')
                pwd := RegExReplace(pwd, 'sl.localhost/' . osName, '')

        Run pshell ' -NoP -W Hidden -C "Start-Process ' . wt . ' -Args `'-w new-tab ' . wsl . ' -d ' . osName . ' --cd \"' . pwd . '\" `' -Verb RunAs"'
        if WinWait(win,, 2)
            WinActivate(win)
    }
}
