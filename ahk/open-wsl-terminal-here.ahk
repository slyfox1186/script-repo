/*____________________________________________________________________________________
    [ OpenTERMINALHere ]

    By: SlyFox1186
    Pastebin: https://pastebin.com/u/slyfox1186
    GitHub: https://github.com/slyfox1186/

    Purpose:
    - This will open Windows' WSL terminal to the active file explorer folder or if no active window is found, %windir%\System32

    Instructions:
    - You need to replace the below variable "_osName" with the wsl distribution of your choosing.
      - To find the available distros run "wsl.exe -l --all" using powershell to get a list of available options
*/

; Defines script as a v1 script
#Requires AutoHotkey <2.0

!w::_OpenWSLHere()

_OpenWSLHere()
{
    ; Static vars so vars are not recreated each time
    Static _osName := "Ubuntu-22.04"
    Static convert := " !#$%&'()-.*:?@[]^_``{|}~/"

    _pshell1 := A_ProgramFiles . "\PowerShell\7\pwsh.exe"
    _pshell2 := A_windir . "\System32\WindowsPowerShell\v1.0\powershell.exe"

    If FileExist(_pshell1)
        _myexe := _pshell1
    Else
        _myexe := _pshell2

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
    If (_pwd = "")
        Run, % _myexe " -NoP -W Hidden -C ""Start-Process wt.exe -Args '-w new-tab -M -d \""" A_windir "\System32\"" wsl.exe -d " _osName "' -Verb RunAs",, Hide, _wPID
    Else
        Run, % _myexe " -NoP -W Hidden -C ""Start-Process wt.exe -Args '-w new-tab -M -d \""" _pwd "\"" wsl.exe -d " _osName "' -Verb RunAs",, Hide, _wPID
    
    _wPID := "ahk_pid " _wPID
    WinActivate, % _wPID, 2
}
