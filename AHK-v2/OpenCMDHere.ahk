/*____________________________________________________________________________________
    OpenCMDHereNew.ahk

    Mechanism of action:
      - Opens a cmd.exe window to the active explorer window's current folder, otherwise
        it will open cmd.exe to the current user's downloads folder.

    Extra Info:
      - Feel free to modify the command lines ' /E:ON /T:0A /K pushd ' to fit your needs.

    Authors:
      - SlyFox1186
      - https://www.reddit.com/user/plankoe/
*/

!c up::OpenCMDHereNew()

OpenCMDHereNew()
{
    win1 := 'ahk_class CabinetWClass ahk_exe explorer.exe'
    win2 := 'ahk_class ConsoleWindowClass ahk_exe cmd.exe'
    if !WinActive(win1)
    {
        Run(A_ComSpec ' /E:ON /T:0A /K pushd C:\Users\' . A_UserName . "\Downloads",, "Max", &OutputVarPID)
        if WinWait('ahk_pid ' OutputVarPID)
            WinActivate('ahk_pid ' OutputVarPID)
        return
    }
    hwnd := WinExist('A')
    winObj := ComObject('Shell.Application').Windows
    try activeTab := ControlGetHwnd('ShellTabWindowClass1', hwnd)
    for win in winObj
    {
        if win.hwnd != hwnd
            continue
        if IsSet(activeTab)
        {
            shellBrowser := ComObjQuery(win, '{000214E2-0000-0000-C000-000000000046}', '{000214E2-0000-0000-C000-000000000046}')
            ComCall(3, shellBrowser, 'uint*', &thisTab:=0)
            if thisTab != activeTab
                continue
        }
        pwd := '"' win.Document.Folder.Self.Path '"'
        break
    }
    Run(A_ComSpec ' /E:ON /T:0A /K pushd ' . pwd,, "Max", &OutputVarPID)
    if WinWait('ahk_pid ' OutputVarPID)
        WinActivate('ahk_pid ' OutputVarPID)
}
