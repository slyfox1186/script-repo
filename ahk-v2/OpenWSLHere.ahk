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
        winObj := ComObject("Shell.Application").Windows
    For win in winObj
    {
            ; Get the string
            pwd := SubStr(win.LocationURL, 9)
            ; Loop through the convert characters
            Loop Parse, _convert
                ; Create a %hex token using ord value of convert chars
                hex := Format("{:X}" , Ord(A_LoopField))
                ; Replace any hex tokens with their actual chars
                ,pwd := StrReplace(pwd, hex, A_LoopField)
                ; Single quotes must be doubled for the command line below to work properly
                pwd := StrReplace(pwd, "%", "")
                pwd := StrReplace(pwd, "'", "''")
                pwd := StrReplace(pwd, pwd, '"' . pwd . '"')
     }

    ; Converted both run commands to expression format
    len := StrLen(pwd)
    If (len < 0)
        Run A_ComSpec ' /D /C START "" "' _myexe '" -NoP -W Hidden -C "Start-Process wt.exe -Args `'-w new-tab -M -d \"~\" wsl.exe -d \"' _osName '\"`' -Verb RunAs'
    Else
        Run A_ComSpec ' /D /C START "" "' _myexe '" -NoP -W Hidden -C "Start-Process wt.exe -Args `'-w new-tab -M -d \"' pwd '\" wsl.exe -d \"' _osName '\"`' -Verb RunAs'
}
