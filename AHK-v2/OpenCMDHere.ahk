/*____________________________________________________________________________________
    OpenCMDHere.ahk

    GitHub: https://github.com/slyfox1186/script-repo/blob/main/AHK-v2/OpenCMDHere.ahk

    Mechanism of action:
      - Opens a cmd.exe window to the active explorer window's current folder, otherwise
        it will open cmd.exe to the current user's downloads folder.

*/

!c::OpenCMDHere()

OpenCMDHere()
{
    win := "ahk_class ConsoleWindowClass ahk_exe cmd.exe"

    if !WinActive("ahk_class CabinetWClass ahk_exe explorer.exe")
    {
        downloadsFolder := FindDownloadsFolder()
        if (downloadsFolder)
        {
            Run(A_ComSpec ' /E:ON /T:0A /K pushd "' downloadsFolder '"',, "Max", &winPID)
            If WinWait(win " ahk_pid " winPID,, 1)
                WinActivate(win)
        }
        return
    }

    explorerWindow := GetActiveExplorerTab()
    if explorerWindow && explorerWindow.Document
    {
        pwd := explorerWindow.Document.Folder.Self.Path
        if (pwd)
        {
            Run(A_ComSpec ' /E:ON /T:0A /K pushd "' pwd '"',, "Max", &winPID)
            if WinWait(win " ahk_pid " winPID,, 1)
                WinActivate(win)
        }
    }
    else
        MsgBox "Could not determine the path of the active Explorer tab."
}

GetActiveExplorerTab(hwnd := WinExist("A"))
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

FindDownloadsFolder()
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
