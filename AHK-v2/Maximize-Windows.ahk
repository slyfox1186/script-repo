/*________________________________________________________________________________________________________________
    Maximize-Windows.ahk

    Purpose: Find all windows that match the names listed in the variable "_processNames"
             and maximize them all at once.
*/

^+c Up::
{

    _processNames := "
    ( LTrim
    chrome
    cmd
    WindowsTerminal
    mintty
    PowerShell
    pwsh
    Termius
    )"

    _processNames := RegExReplace(_processNames, "([a-zA-Z\d]+)", "$1.exe")

    Loop Parse, _processNames, "`n", "`r"
    {
        Try
        {
        wTitle := WinGetTitle("ahk_exe " . A_LoopField)
        wClass := WinGetClass(wTitle . " ahk_exe " . A_LoopField)
        wPID := WinGetPID(wTitle . " ahk_class " . wClass . " ahk_exe " . A_LoopField)
        wFull := wTitle . " ahk_class " . wClass . " ahk_exe " . A_LoopField . " ahk_pid " . wPID
        WinMaximize(wFull)
        }
        Catch
            Continue
    }
}
