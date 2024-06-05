/*____________________________________________________________________________________
    OpenPSHere.ahk

    GitHub: https://github.com/slyfox1186/script-repo/blob/main/AHK-v2/OpenPSHere.ahk

    Mechanism of action:
      - Opens a PowerShell window to the active explorer folder path, otherwise
        it will open PowerShell to the current user's Downloads folder.
*/

!e::OpenPowerShellHere()

OpenPowerShellHere()
{
    static wt := "C:\Users\" A_UserName "\AppData\Local\Microsoft\WindowsApps\wt.exe"
    static wsl := A_WinDir . "\System32\wsl.exe"
    static win := "ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe"
    static pshell := FileExist(A_ProgramFiles "\PowerShell\7-preview\pwsh.exe") ? A_ProgramFiles "\PowerShell\7-preview\pwsh.exe" : A_ProgramFiles "\PowerShell\7\pwsh.exe"

    if !WinActive("ahk_class CabinetWClass ahk_exe explorer.exe")
    {
        downloadsFolder := FindPSDownloadsFolder()
        if (downloadsFolder)
        {
            Run(pshell ' -NoExit -C "Set-Location -Path "' downloadsFolder '"',, "Max", &pshellPID)
            If WinWait(win " ahk_pid " pshellPID,, 1)
                WinActivate(win)
            else
                WinActivate("A")
        }
        return
    }

    explorerWindow := GetActivePSTab()
    if explorerWindow && explorerWindow.Document
    {
        pwd := explorerWindow.Document.Folder.Self.Path
        if (pwd)
        {
            pwd := StrReplace(pwd, "'", "''")
            pwd := '"' pwd '"'
            Run(pshell ' -NoExit -C "Set-Location -Path ' pwd '"',, "Max", &pshellPID)
            if WinWait(win " ahk_pid " pshellPID,, 1)
                WinActivate(win)
            else
                WinActivate("A")
        }
    }
    else
        MsgBox "Could not determine the path of the active Explorer tab."
}

GetActivePSTab(hwnd := WinExist("A"))
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
            ; The window has tabs, so make sure this is right.
            static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"
            shellBrowser := ComObjQuery(win, IID_IShellBrowser, IID_IShellBrowser)
            ComCall(3, shellBrowser, "uint*", &thisTab:=0)
            if thisTab != activeTab
                continue
        }
        return win
    }
}

FindPSDownloadsFolder()
{
    downloadsFolder := ""
    if (FileExist(A_MyDocuments "\Downloads"))
        downloadsFolder := A_MyDocuments "\Downloads"
    else if (FileExist("C:\Users\" . A_UserName . "\Downloads"))
        downloadsFolder := "C:\Users\" . A_UserName . "\Downloads"
    else
        MsgBox "Downloads folder not found."
    return downloadsFolder
}
