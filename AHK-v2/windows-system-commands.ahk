; #############################
; #  WINDOWS SYSTEM COMMANDS  #
; #############################

/*____________________________________________________________________________________
    EMPTY RECYCLE BIN
*/

!+r up::
{
    if FileRecycleEmpty
    {
        FileRecycleEmpty
        ComObj := ComObject("SAPI.SpVoice").Speak("Files Deleted")
    }
    else
        ComObj := ComObject("SAPI.SpVoice").Speak("Failed to delete files")
}

/*____________________________________________________________________________________
    VIRTUAL DESKTOP LEFT
*/

!a up::
{
    Send "{LCtrl Down}{LWin Down}{Left Down}"
    Send "{LCtrl Up}{LWin Up}{Left Up}"
}

/*____________________________________________________________________________________
    VIRTUAL DESKTOP RIGHT
*/

!d up::
{
    Send "{LCtrl Down}{LWin Down}{Right Down}"
    Send "{LCtrl Up} {LWin Up}{Right Up}"
}
