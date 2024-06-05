/*
    OpenWSLHere.ahk

    GitHub:
    - https://github.com/slyfox1186/script-repo/blob/main/AHK-v2/OpenWSLHere.ahk

    Purpose:
    - This will open WindowsTerminal.exe to the active file explorer path or if no active explorer window is found,
      it will open to the user's "$HOME".

    Updated:
    - 06.05.24
*/

^!+w::OpenWSLHere("Arch")
^!+d::OpenWSLHere("Debian")
^!w::OpenWSLHere("Ubuntu")
!w::OpenWSLHere("Ubuntu-24.04")

OpenWSLHere(osName)
{
    static wt := "C:\Users\" A_UserName "\AppData\Local\Microsoft\WindowsApps\wt.exe"
    static wsl := A_WinDir "\System32\wsl.exe"
    static win := "ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe"
    static pshell := FileExist(A_ProgramFiles "\PowerShell\7-preview\pwsh.exe") ? A_ProgramFiles "\PowerShell\7-preview\pwsh.exe" 
                     : FileExist(A_ProgramFiles "\PowerShell\7\pwsh.exe") ? A_ProgramFiles "\PowerShell\7\pwsh.exe" 
                     : A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"

    if !WinActive("ahk_class CabinetWClass ahk_exe explorer.exe")
    {
        Run(pshell ' -NoP -W H -C "Start-Process -WindowStyle Max ' wt ' -Args `'-w new-tab ' wsl ' -d ' osName ' --cd ~ `' -Verb RunAs"',, "Hide")
        if WinWait(win,, 2)
            WinActivate(win)
        else
            WinActivate("A")
        return
    }

    explorerWindow := GetWSLExplorerTab()
    if explorerWindow && explorerWindow.Document
    {
        pwd := explorerWindow.Document.Folder.Self.Path
        if (pwd)
        {
            pwd := StrReplace(pwd, "'", "''")
            pwd := StrReplace(pwd, "\\wsl.localhost", "")
            pwd := RegExReplace(pwd, "\\(Arch|Debian|Ubuntu-24.04|Ubuntu-20.04|Ubuntu-18.04|Ubuntu)", "/")
            pwd := StrReplace(pwd, "\", "/")
            Run(pshell ' -NoP -W H -C "Start-Process -WindowStyle Max ' wt ' -Args `'-w new-tab ' wsl ' -d ' osName ' --cd \"' pwd '\" `' -Verb RunAs"',, "Hide")
            if WinWait(win,, 2)
                WinActivate(win)
            else
                WinActivate("A")
        }
    }
    else
        MsgBox "Could not determine the path of the active Explorer tab."
}

GetWSLExplorerTab(hwnd := WinExist("A"))
{
    activeTab := 0
    try activeTab := ControlGetHwnd("ShellTabWindowClass1", hwnd) ; File Explorer (Windows 11)
    catch
    try activeTab := ControlGetHwnd("TabWindowClass1", hwnd) ; IE
    for win in ComObject("Shell.Application").Windows
    {
        if win.hwnd != hwnd
            continue
        if activeTab
        { 
            ; The window has tabs, so make sure this is the right one.
            static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"
            shellBrowser := ComObjQuery(win, IID_IShellBrowser, IID_IShellBrowser)
            ComCall(3, shellBrowser, "uint*", &thisTab:=0)
            if thisTab != activeTab
                continue
        }
        return win
    }
}
