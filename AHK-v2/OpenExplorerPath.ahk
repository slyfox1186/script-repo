/*________________________________________________________________________________________________________________

    Purpose:
        Open Explorer to the directory path of any highlighted text or the
        current clipboard contents when the hotkey is triggered.
    How to use:
        Highlight or copy to the clipboard a full existing folder path on
        a single or over multiple lines. The script will separate each path over
        a multiple-line trigger and open them one at a time until there are no
        more paths left to process.

*/

/*________________________________________________________________________________________________________________
    Open Explorer With Text

    Purpose:
        Open Explorer to the directory path of any highlighted text or the
        current clipboard contents when the hotkey is triggered.
    How to use:
        Highlight or copy to the clipboard a full existing folder path on
        a single or over multiple lines. The script will separate each path over
        a multiple-line trigger and open them one at a time until there are no
        more paths left to process.
*/

!+e::
{
    win := "ahk_class CabinetWClass ahk_exe explorer.exe"
    ; Save the current Clipboard contents
    ClipSaved := A_Clipboard
    ; Clear the Clipboard in anticipation of the ClipWait command below
    A_Clipboard := ""

    ; Execute the ClipWait command to see if any text that is highlighted gets copied to the Clipboard
    SendInput("^c")
    ClipWait(0.5)

    ; If the Clipboard is still empty then we restore the Clipboard with the contents of the ClipSaved variable
    if !(A_Clipboard)
        A_Clipboard := ClipSaved

    ; Parse the Clipboard content line by line
    Loop Parse, A_Clipboard, "`n", "`r"
    {
        ; Trim whitespace from the Clipboard text for accurate path detection
        currentPath := Trim(A_LoopField, " `t`r`n")
        currentPath := StrReplace(currentPath, "`"`"", "")

        ; Check if the path starts with a capital letter followed by ':' or starts with '\\' (UNC path)
        if RegExMatch(currentPath, "^[A-Z]:|^\\\\")
        {
            ; Check if the Clipboard content is a valid folder path to a directory only
            if (FileExist(currentPath) == "D")
            {
                ; Run explorer.exe and open the folder paths
                Run(A_WinDir . "\explorer.exe " . '"' . currentPath . '"')
                WinWait(win,, 1)
                WinWaitActive(win,, 2)
                WinMaximize(win)

                if !WinActive("A") ; Delay to ensure each window opens correctly and processing is smooth
                {
                    WinActivate(win)
                    Sleep 200
                }
                else
                    Sleep 400
            }
        }
    }

    ; Restore the original Clipboard contents
    A_Clipboard := ClipSaved
}
