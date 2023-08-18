; #################
; #  OpenCMDHere  #
; #################

!c up::_OpenCMDHere()

_OpenCMDHere()
{
    ; Static vars so vars are not recreated each time
    Static convert := " !#$%&'()-.*:?@[]^_``{|}~/"

    if WinActive('ahk_class CabinetWClass ahk_exe explorer.exe')
        winObj := ComObject('Shell.Application').Windows
    else
    {
        Run(A_ComSpec ' /E:ON /T:0A /K pushd 'C:\Users\' . A_UserName . '\Downloads',, 'Max')
        return
    }

    for win in winObj
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
}
