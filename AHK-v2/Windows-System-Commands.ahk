; #############################
; #  WINDOWS SYSTEM COMMANDS  #
; #############################

/*____________________________________________________________________________________
    EMPTY RECYCLE BIN
*/

!+r Up::
{
    try
        FileRecycleEmpty
    catch
    {
        ComObj := ComObject("SAPI.SpVoice").Speak("Failed to delete files")
        MsgBox("Failed to delete files.",, "T2")
        Reload
    }
}

/*____________________________________________________________________________________
    MOVE VIRTUAL DESKTOP LEFT
*/

!a Up::
{
    SendInput "{LCtrl Down}{LWin Down}{Left Down}"
    Sleep 25
    SendInput "{LCtrl Up}{LWin Up}{Left Up}"
}

/*____________________________________________________________________________________
    MOVE VIRTUAL DESKTOP RIGHT
*/

!d Up::
{
    SendInput "{LCtrl Down}{LWin Down}{Right Down}"
    Sleep 25
    SendInput "{LCtrl Up}{LWin Up}{Right Up}"
}
