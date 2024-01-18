/*____________________________________________________________________________________
    OpenPSHere.ahk

    Mechanism of action:
      - Opens a powershell window

    Authors:
      - SlyFox1186
*/

!e Up::
{
    if FileExist("C:\Program Files\PowerShell\7\pwsh.exe")
    {
        pshell := "C:\Program Files\PowerShell\7\pwsh.exe"
        win := "ahk_class ConsoleWindowClass ahk_exe pwsh.exe"
    }
    else
    {
        pshell := "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        win := "ahk_class ConsoleWindowClass ahk_exe powershell.exe"
    }
    if !WinExist(win)
    {
        Run("C:\Program Files\PowerShell\7\pwsh.exe",, "Max", &pwshVar)
        if WinWait("ahk_pid " pwshVar)
            WinActivate("ahk_pid " pwshVar)
    }
    else if WinExist(win) && !WinActive(win)
        WinActivate(win)
    else
        ProcessClose "pwsh.exe"
}
