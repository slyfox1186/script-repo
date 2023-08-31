/*____________________________________________________________________________________
    OpenCMDHereNew.ahk

    Mechanism of action:
      - Opens a cmd.exe window to the active explorer window's current folder, otherwise
        it will open cmd.exe to the current user's download folder.

    Note on Windows 11:
      - If you have a single explorer window open and are using multiple tabs this script
        will open the far left tab path "only", it does not matter which tab is open
        when the hotkey is pressed in this scenario. Otherwsie, if you have multiple explorer
        windows open at once, then this script should open the correct folder path for each
        separate window when triggered.

    Extra Info:
      - Feel free to modify the command lines ' /E:ON /T:0A /K pushd ' to fit your needs.

*/

!c up::OpenCMDHereNew()

OpenCMDHereNew()
{
    win1 := 'ahk_class CabinetWClass ahk_exe explorer.exe'
    win2 := 'ahk_class ConsoleWindowClass ahk_exe cmd.exe'
    if !WinActive(win1)
    {
        Run(A_ComSpec ' /E:ON /T:0A /K pushd C:\Users\' . A_UserName . '\Downloads',, 'Max', &OutputVarPID)
        if WinWait('ahk_pid ' OutputVarPID)
        {
            Sleep 100
            WinActivate('ahk_pid ' OutputVarPID)
        }
    return
    }
    hwnd := WinExist('A')
    winObj := ComObject('Shell.Application').Windows
    for win in winObj
    {
        if win.hwnd != hwnd
            continue
        pwd := '"' win.Document.Folder.Self.Path '"'
        break
    }
    Run(A_ComSpec ' /E:ON /T:0A /K pushd ' . pwd,, 'Max', &OutputVarPID)
    if WinWait('ahk_pid ' OutputVarPID)
    {
        Sleep 100
        WinActivate('ahk_pid ' OutputVarPID)
    }
}
