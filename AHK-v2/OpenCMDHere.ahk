; #################
; #  OpenCMDHere  #
; #################

!c up::_OpenCMDHere()

_OpenCMDHere()
{
    win := 'ahk_class ConsoleWindowClass ahk_exe cmd.exe'
    Static convert := " !#$%&'()-.*:?@[]^_``{|}~/"

    If WinActive('ahk_class CabinetWClass ahk_exe explorer.exe')
        winObj := ComObject('Shell.Application').Windows
    Else
    {
        Run(A_ComSpec ' /E:ON /T:0A /K pushd C:\Users\' . A_UserName . '\Downloads',, 'Max', &winCMD)
        if WinWait('ahk_pid ' winCMD,, 2)
            WinActivate('ahk_pid ' winCMD)
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
     Run(A_ComSpec ' /E:ON /T:0A /K pushd ' . pwd,, 'Max', &winCMD)
     if WinWait('ahk_pid ' . winCMD,, 2)
        WinActivate('ahk_pid ' . winCMD)
     return
}
