/*____________________________________________________________________________________
    OpenPSHere.ahk

    Mechanism of action:
      - Opens a PowerShell window

    Authors:
      - SlyFox1186
*/

!e Up::OpenPowerShell()

OpenPowerShell() {
    static wt := "C:\Users\" A_UserName "\AppData\Local\Microsoft\WindowsApps\wt.exe"
    static wsl := A_WinDir . "\System32\wsl.exe"
    static win := "ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe"
    static PShell := FileExist(A_ProgramFiles . "\PowerShell\7\pwsh.exe") ? A_ProgramFiles . "\PowerShell\7\pwsh.exe" : A_WinDir . "\System32\WindowsPowerShell\v1.0\powershell.exe"

    if !WinActive("ahk_class CabinetWClass ahk_exe explorer.exe") {
        downloadsFolder := GetDownloadsFolder()
        Run(pshell ' -NoP -NoExit -C "Set-Location -Path ' '" ' . downloadsFolder . ' "',, "Max", &pshellPID)
        If WinWait(win . " ahk_pid " pshellPID,, 1)
            WinActivate(win)
        else
            WinActivate("A")
        return
    }

    hwnd := WinExist("A")
    winObj := ComObject("Shell.Application").Windows
    try activeTab := ControlGetHwnd("ShellTabWindowClass1", hwnd)

    winObj := ComObject("Shell.Application").Windows
    for win in winObj {
        if (win.hwnd = hwnd) {
            if (activeTab) {
                shellBrowser := ComObjQuery(win, "{4C96BE40-915C-11CF-99D3-00AA004AE837}", "{000214E2-0000-0000-C000-000000000046}")
                if (!shellBrowser)
                    continue
                ComCall(3, shellBrowser, "uint*", &currentTab:=0)
                if (currentTab != activeTab)
                    continue
            }
            pwd := win.Document.Folder.Self.Path
            pwd := StrReplace(pwd, "'", "''")
            pwd := '"' . pwd . '"'
            break
        }
    }

    Run(pshell ' -NoP -NoExit -C "Set-Location -Path ' '"' . pwd . '"',, "Max", &pshellPID)
    if WinWait(win . " ahk_pid " pshellPID,, 1)
        WinActivate(win)
    else
        WinActivate("A")
}

GetDownloadsFolder() {
    downloadsFolder := ""
    if (FileExist(A_MyDocuments "\\Downloads"))
        downloadsFolder := A_MyDocuments "\\Downloads"
    else if (FileExist("C:\\Users\\" . A_UserName . "\\Downloads"))
        downloadsFolder := "C:\\Users\\" . A_UserName . "\\Downloads"
    else
        MsgBox "Downloads folder not found."
    return downloadsFolder
}
