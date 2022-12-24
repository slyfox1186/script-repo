/*____________________________________________________________________________________
    [ OpenTERMINALHere ]

    By: SlyFox1186
    Pastebin: https://pastebin.com/u/slyfox1186
    GitHub: https://github.com/slyfox1186/
    - Looking for a coder? You found him. Contact me on GitHub.

    Purpose:
    - This will open Windows' WSL terminal to the active file explorer folder.
    - If necessary modify the below variable "_osName" to the wsl dist you have installed.
*/

!x::_OpenWSLHere()

_OpenWSLHere()
{

_osName := "Ubuntu"

    ; OPEN CMD.EXE USING THE ACTIVE EXPLORER WINDOW'S FOLDER PATH
    If winexist("ahk_class CabinetWClass ahk_exe explorer.exe")
        _winHwnd := WinActive()
    For win in ComObjCreate("Shell.Application").Windows
        if (win.HWND = _winHwnd)
        {
            _pwd := SubStr(win.LocationURL, 9)
            _pwd := RegExReplace(_pwd, "%20", " ")
            _pwd := RegExReplace(_pwd, "%21", "!")
            _pwd := RegExReplace(_pwd, "%23", "#")
            _pwd := RegExReplace(_pwd, "%24", "$")
            _pwd := RegExReplace(_pwd, "%25", "%")
            _pwd := RegExReplace(_pwd, "%26", "&")
            _pwd := RegExReplace(_pwd, "%27", "'")
            _pwd := RegExReplace(_pwd, "%28", "(")
            _pwd := RegExReplace(_pwd, "%29", ")")
            _pwd := RegExReplace(_pwd, "%2D", "-")
            _pwd := RegExReplace(_pwd, "%2E", ".")
            _pwd := RegExReplace(_pwd, "%30", "*")
            _pwd := RegExReplace(_pwd, "%3A", ":")
            _pwd := RegExReplace(_pwd, "%3F", "?")
            _pwd := RegExReplace(_pwd, "%40", "@")
            _pwd := RegExReplace(_pwd, "%5B", "[")
            _pwd := RegExReplace(_pwd, "%5D", "]")
            _pwd := RegExReplace(_pwd, "%5E", "^")
            _pwd := RegExReplace(_pwd, "%5F", "_")
            _pwd := RegExReplace(_pwd, "%60", "``")
            _pwd := RegExReplace(_pwd, "%7B", "{")
            _pwd := RegExReplace(_pwd, "%7C", "|")
            _pwd := RegExReplace(_pwd, "%7D", "}")
            _pwd := RegExReplace(_pwd, "%7E", "~")
            _pwd := RegExReplace(_pwd, "/", "\")
        }
    Run, "%A_windir%\System32\wsl.exe" -d %_osName% --cd "%_pwd%",, Max, _wPID
    _winPID := "ahk_pid " . _wPID
    WinWait, %_winPID%,, 2
    WinActivate, %_winPID%
    Sleep, 500
    if !WinExist(_winPID)
        MsgBox, Script Error:`r`rYou may need to change the variable '_osName' to the name of the distribution you have installed.`r`rExamples: Debian, Ubuntu, or other.`r`rRemember the explorer.exe window must be the ACTIVE window when you activate the hotkey!
}
return
