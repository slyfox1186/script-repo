/*____________________________________________________________________________________
    OpenCMDHere

    By:
    - SlyFox1186

    Pastebin:
    - https://pastebin.com/u/slyfox1186

    GitHub:
    - https://github.com/slyfox1186/

    Purpose:
    - This will open cmd.exe to the active file explorer folder or if no active window is found, %windir%\System32
    
*/

; Defined as a v1 script
#Requires AutoHotkey <2.0

!c::_OpenCMDHere()

_OpenCMDHere()
{
    ; Static vars so vars are not recreated each time
    Static convert := " !#$%&'()-.*:?@[]^_``{|}~/"

    If WinExist("ahk_class CabinetWClass ahk_exe explorer.exe")
        _winHwnd := WinActive()

    For win in ComObjCreate("Shell.Application").Windows
        If (win.HWND = _winHwnd)
        {
            ; Get the string
            _pwd := SubStr(win.LocationURL, 9)
            ; Loop through the convert characters
            Loop, Parse, % convert
                ; Create a %_hex token using ord value of convert chars
                _hex := "%" Format("{1:X}", Ord(A_LoopField))
                ; Replace any hex tokens with their actual chars
                ,_pwd := StrReplace(_pwd, _hex, A_LoopField)
        }

    ; Converted both run commands to expression format
    Run, %ComSpec% /E:ON /T:0A /K PROMPT $P$G$_$G, % _pwd ? _pwd : "%A_windir%\System32\", Max
    _winPID := "ahk_pid " . _wPID
    WinActivate, % _winPID
    WinMove, %_winPID%,,,, %A_ScreenWidth%, %A_ScreenHeight%
}
