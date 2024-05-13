/*____________________________________________________________________________________

    Open your browser and search the clipboard or the currently highlighted text using
    Google or if it is a website then directly load it.

    Instructions:
                  1. Change the variable 'Browser' to the full path of the exe you wish to use.
                  2. If needed, use WindowSpy.ahk to replace the variable 'win' with the correct text.

    Test the strings below!

    funny cat videos
    how to bake a pie
    amazon.com
    mail.google.com
    https://github.com/slyfox1186/script-repo/
*/

^!c::
{
    Browser := A_ProgramFiles . "\Google\Chrome Beta\Application\chrome.exe" ; Update this path as necessary
    win := "ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe"

    ClipSaved := ClipboardAll()  ; Save the current Clipboard contents
    A_Clipboard := ""

    Send("^c")
    if !ClipWait(1)
        A_Clipboard := ClipSaved
    
    ; Trim whitespace from the clipboard text for accurate URL detection
    searchText := Trim(A_Clipboard, " `t`r`n")

    ; Determine if the searchText looks like a URL. If not, prepare a Google search.
    isUrl := RegExMatch(searchText, "i)^(https?:\/\/)?[\w.-]+(\.[a-zA-Z]{2,})+(\/\S*)?$")
    searchOrUrl := isUrl ? searchText : "https://www.google.com/search?q=" . searchText

    ; Open the browser with the URL or search query
    ff_cmd := '"' . Browser . '"' . " --new-tab " . '"' . searchOrUrl . '"'
    Run(ff_cmd,, "Max")

    ; Attempt to bring the browser window to the foreground
    If !WinExist(win)
    {
        WinWait(win,, 2)
        WinActivate(win)
        WinMaximize(win)
    }

    ; Restore the original clipboard content
    A_Clipboard := ClipSaved
}
