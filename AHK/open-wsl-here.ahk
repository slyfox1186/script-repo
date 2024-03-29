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
    - 08.18.23

*/

!w up::OpenWSLHere()

OpenWSLHere()
{
    Static osName := "Debian"
    Static wt := "C:\Users\" . A_UserName . "\AppData\Local\Microsoft\WindowsApps\wt.exe"
    Static wsl := "C:\Windows\System32\wsl.exe"
    Static win := "ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe"
    if FileExist("C:\Program Files\PowerShell\7\pwsh.exe")
        pshell := "C:\Program Files\PowerShell\7\pwsh.exe"
    else
        pshell := "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !WinActive("ahk_class CabinetWClass ahk_exe explorer.exe")
    {
        Run(pshell ' -NoP -W Hidden -C "Start-Process -WindowStyle Hidden ' . wt . ' -Args `'-w new-tab ' . wsl . ' -d ' . osName . ' --cd ~ `' -Verb RunAs"')
        if WinWait(win)
            WinActivate(win)
        return
    }
    hwnd := WinExist("A")
    winObj := ComObject("Shell.Application").Windows
    try activeTab := ControlGetHwnd("ShellTabWindowClass1", hwnd)
    for win in winObj
    {
        if(win.hwnd != hwnd)
            continue
        if IsSet(activeTab)
        {
            shellBrowser := ComObjQuery(win, "{000214E2-0000-0000-C000-000000000046}", "{000214E2-0000-0000-C000-000000000046}")
            ComCall(3, shellBrowser, "uint*", &thisTab:=0)
            if(thisTab != activeTab)
                continue
        }
        pwd := '"' win.Document.Folder.Self.Path '"'
        break
    }
    Run(pshell ' -NoP -W Hidden -C "Start-Process -WindowStyle Hidden ' . wt . ' -Args `'-w new-tab ' . wsl . ' -d ' . osName . ' --cd \"' . pwd . '\" `' -Verb RunAs"')
    if WinWait(win)
        WinActivate(win)
}
