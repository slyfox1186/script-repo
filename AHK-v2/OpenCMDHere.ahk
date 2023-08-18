; #################
; #  OpenCMDHere  #
; #################

!c up::_OpenCMDHere()

_OpenCMDHere()
{
    Static convert := " !#$%&'()-.*:?@[]^_``{|}~/"
    win := 'ahk_class ConsoleWindowClass ahk_exe cmd.exe'
    If WinActive('ahk_class CabinetWClass ahk_exe explorer.exe')
        winObj := ComObject('Shell.Application').Windows
    Else
    {
        Run(A_ComSpec ' /E:ON /T:0A /K pushd C:\Users\' . A_UserName . '\Downloads',, 'Max')
        if WinWait(win,, 2)
            WinActivate(win)
        return
    }

    For win in winObj
    {
        pwd := SubStr(win.LocationURL, 9)
        Loop Parse, convert
            hex := Format('{:X}' , Ord(A_LoopField))
            ,pwd := StrReplace(pwd, hex, A_LoopField)
            pwd := StrReplace(pwd, "%", "")
            pwd := StrReplace(pwd, "'", "''")
            pwd := StrReplace(pwd, "/", "\")
            pwd := StrReplace(pwd, pwd, '"' . pwd . '"')
    }
     Run(A_ComSpec ' /E:ON /T:0A /K pushd ' . pwd,, 'Max')
     if WinWait(win,, 2)
        WinActivate(win)
     return
}
