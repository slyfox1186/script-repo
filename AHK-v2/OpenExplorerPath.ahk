/*
    Purpose:
        Open Explorer to the directory path of any highlighted text or the
        current clipboard contents when the hotkey is triggered.

    How to use:
        Highlight or copy to the clipboard a full existing folder path on
        a single or multiple lines. The script will separate each path over
        a multiple-line trigger and open them one at a time until there are no
        more paths left to process.
*/

!+e Up::
{
    win := "ahk_class CabinetWClass ahk_exe explorer.exe"
    ClipSaved := A_Clipboard
    A_Clipboard := ""

    Send("^c")
    if !ClipWait(1)
        A_Clipboard := ClipSaved

    for each, line in StrSplit(A_Clipboard, "`n", "`r")
    {
        pwd := Trim(line, " `t`r`n")
        pwd := StrReplace(pwd, "`"`"", "")
        if RegExMatch(pwd, "^[A-Z]:|^\\\\")
        {
            if InStr(FileExist(pwd), "D")
            {
                Run(A_WinDir . "\explorer.exe" . ' "' . pwd . '"',, "Max", &ExplorerPID)
                WinWaitNotActive(WinExist("A"))
                Title := WinGetTitle("A")
                winFull := Title . " " . win
                Sleep(500)
            }
            else
                MsgBox("The folder does not exist!",, "T1")
        }
    }
}
