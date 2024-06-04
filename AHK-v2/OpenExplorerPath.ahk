/*________________________________________________________________________________________________________________

    Purpose:
        Open explorer to the directory path of any highlighted text or the
        current clipboard contents when the hotkey is triggered

*/

!+e::
{
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

    ; Trim whitespace from the Clipboard text for accurate path detection
    A_Clipboard := Trim(A_Clipboard, " `t`r`n")
    A_Clipboard := StrReplace(A_Clipboard, "`"`"", "")

    ; Check if the Clipboard content is a valid folder path to a directory only
    if (FileExist(A_Clipboard) == "D")
        Run(A_WinDir . "\explorer.exe " . '"' . A_Clipboard . '"')

     ; Free the memory from the Clipboard in case it was of extensive size
    A_Clipboard := ""
}
