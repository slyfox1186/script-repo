/*____________________________________________________________________________________
    OpenWSLHere.ahk

    By:
    - SlyFox1186

    GitHub:
    - https://github.com/slyfox1186

    Pastebin:
    - https://pastebin.com/u/slyfox1186
    
    Purpose:
    - This will open Windows' WSL terminal to the active file explorer folder or if no active window is found, %windir%\System32

    Instructions:
    - You need to replace the below variable "_osName" with the wsl distribution of your choosing.
      - To find the available distros run "wsl.exe -l --all" using PowerShell to get a list of available options
*/

!w::_OpenWSLHere()

_OpenWSLHere()
{
    ; Static vars so vars are not recreated each time
    Static _convert := " !#$%&'()-.*:?@[]^_``{|}~/"
    Static _osName := "Ubuntu-22.04"
    Static _wt := "C:\Users\jholl\AppData\Local\Microsoft\WindowsApps\wt.exe"
    Static _wsl := "C:\Windows\System32\wsl.exe"

    If FileExist(A_ProgramFiles . "\PowerShell\7\pwsh.exe")
        _myexe := A_ProgramFiles . "\PowerShell\7\pwsh.exe"
    Else
        _myexe := A_windir . "\System32\WindowsPowerShell\v1.0\powershell.exe"

    If WinExist("ahk_class CabinetWClass ahk_exe explorer.exe")
        _winHwnd := WinActive()

    For win in ComObjCreate("Shell.Application").Windows
        If (win.HWND = _winHwnd)
        {
            ; Get the string
            _pwd := SubStr(win.LocationURL, 9)
            ; Loop through the convert characters
            Loop Parse, % _convert
                ; Create a %hex token using ord value of convert chars
                _hex := "%" Format("{1:X}", Ord(A_LoopField))
                ; Replace any hex tokens with their actual chars
                ,_pwd := StrReplace(_pwd, _hex, A_LoopField)
                ; Single quotes must be doubled for the command line below to work properly
                _pwd := StrReplace(_pwd, "'", "''")
        }

    ; Converted both run commands to expression format
    If (_pwd = "")
        Run ComSpec '""/D /C START """" "_myexe" -NoP -W Hidden -C """Start-Process " . _wt . "-Args '-w new-tab -M -d \"~\" _wsl -d \"%_osName%\"' -Verb RunAs"""',, Hide, _wPID
    Else
        Run, %ComSpec% /D /C START "" "%_myexe%" -NoP -W Hidden -C "Start-Process %_wt% -Args '-w new-tab -M -d \"%_pwd%\" %_wsl% -d \"%_osName%\"' -Verb RunAs",, Hide, _wPID
    WinActivate, ahk_exe WindowsTerminal.exe
}
