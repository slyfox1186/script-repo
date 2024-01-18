/*____________________________________________________________________________________
    OpenWSLHere.ahk

    GitHub:
    - https://github.com/slyfox1186

    Pastebin:
    - https://pastebin.com/u/slyfox1186
    
    Purpose:
    - This will open Windows' WSL terminal to the active file explorer folder or if no active explorer window is found, ~

    Instructions:
    - You need to replace the below variable 'osName' with the wsl distribution of your choosing.
    - To find the available distros run 'wsl.exe -l --all' using PowerShell to get a list of available options

    Updated:
    - 01.04.24

    Big Update:
    - Greatly improved the code. When explorer.exe has multiple tabs per window, it will
      open the correct tab the hotkey is trigged on instead of just activating the far left tab.

*/

!w Up::OpenWSLHere()

OpenWSLHere()
{
    osName := "Ubuntu"
    Static wt := "C:\Users\" . A_UserName . "\AppData\Local\Microsoft\WindowsApps\wt.exe"
    Static wsl := "C:\Windows\System32\wsl.exe"
    Static win := "ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe"
    if FileExist("C:\Program Files\PowerShell\7\pwsh.exe")
        pshell := "C:\Program Files\PowerShell\7\pwsh.exe"
    else
        pshell := "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

    if !WinActive("ahk_class CabinetWClass ahk_exe explorer.exe")
    {
        Run(pshell ' -NoP -W Hidden -C "Start-Process -WindowStyle Max ' . wt . ' -Args `'-w new-tab ' . wsl . ' -d ' . osName . ' --cd ~ `' -Verb RunAs"',, "Hide")
        if WinWait(win)
            WinActivate(win)
        return
    }
    hwnd := WinExist("A")
    winObj := ComObject("Shell.Application").Windows
    try activeTab := ControlGetHwnd("ShellTabWindowClass1", hwnd)

    for win in winObj
    {
        if win.hwnd != hwnd
            continue
        if IsSet(activeTab)
        {
            shellBrowser := ComObjQuery(win, "{000214E2-0000-0000-C000-000000000046}", "{000214E2-0000-0000-C000-000000000046}")
            ComCall(3, shellBrowser, 'uint*', &thisTab:=0)
            if thisTab != activeTab
                continue
        }
        pwd := '"' win.Document.Folder.Self.Path '"'
        pwd := StrReplace(pwd, "'", "''")
        pwd := StrReplace(pwd, "\\wsl.localhost", "")
        RegExMatch(pwd, "Arch|Debian|Ubuntu-22\.04|Ubuntu-20\.04|Ubuntu-18\.04|Ubuntu", &OSDir)
        try
        {
            osName := OSDir[]
            pwd := StrReplace(pwd, "\Arch", "")
            pwd := StrReplace(pwd, "\Debian", "")
            pwd := StrReplace(pwd, "\Ubuntu-22.04", "")
            pwd := StrReplace(pwd, "\Ubuntu-20.04", "")
            pwd := StrReplace(pwd, "\Ubuntu-18.04", "")
            pwd := StrReplace(pwd, "\Ubuntu", "")
            pwd := StrReplace(pwd, "\", "/")
        }
        catch
            pwd := StrReplace(pwd, "\", "/")
        break
    }

    Run(pshell ' -NoP -W Hidden -C "Start-Process -WindowStyle Max ' . wt . ' -Args `'-w new-tab ' . wsl . ' -d ' . osName . ' --cd \"' . pwd . '\" `' -Verb RunAs"',, "Hide")
    if WinWait(win)
        WinActivate(win)
    Return
}
