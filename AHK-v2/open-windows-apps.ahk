; #######################
; #  OPEN WINDOWS APPS  #
; #######################

/*________________________________________________________________________________________________________________
    PROXY TOGGLE
*/

!+p up::Run A_WinDir . "\System32\wscript.exe " . _VBS . "\Toggle-Scripts\proxy-toggle.vbs"

/*____________________________________________________________________________________
    WINDOWS UPDATES
*/

#u up::Run A_WinDir . "\System32\wscript.exe " . _VBS . "\Windows-System\open-windows-update-hidden.vbs"

/*________________________________________________________________________________________________________________
    MUTE MICROPHONE TOGGLE
*/

^!+m up::Run _PF1 . "\NirLauncher\NirSoft\x64\nircmd.exe mutesysvolume 2 microphone"

/*________________________________________________________________________________________________________________
    NETWORK CONNECTIONS
*/

^!+n up::
{
    win := "Control Panel\All Control Panel Items\Network Connections ahk_class CabinetWClass ahk_exe explorer.exe"
    if !WinActive(win)
        Run A_WinDir . "\System32\RunDLL32.exe shell32.dll,Control_RunDLL NCPA.CPL,@0,3",, "Max"
    else if !WinActive(win)
        WinActivate
    else
        WinClose
}

/*________________________________________________________________________________________________________________
    OPEN SOUND CONTROL PANEL
*/

>!g up::
{
    win := "Sound ahk_class #32770 ahk_exe rundll32.exe"
    if !WinExist(win)
        Run A_WinDir . "\System32\mmsys.cpl"
    else if !WinActive(win)
        WinActivate
    else
        WinClose
}

/*________________________________________________________________________________________________________________
    REGEDIT
*/

^!r up::
{
    win := "Registry Editor ahk_class RegEdit_RegEdit ahk_exe regedit.exe"
    if !WinExist(win)
        Run A_WinDir . "\regedit.exe",, "Max"
    else if !WinActive(win)
        WinActivate
    else
        WinClose
}
