/*____________________________________________________________________________________
    Open your browser and search the current Clipboard or the currently highlighted text using
    a Google search query for regular text strings or if the text is an actual url/website/link
    then the script will send it directly to the Browser without using Google so the website loads
    directly.

    Instructions:
    1. Use the script WindowSpy.ahk to replace the variable 'win' with the correct text
       that identifies your default browser.
    2. Activate the Hotkey by highlighting a single line of text that consists of a
       single url/website/link or a line of regular text and the script will use the
       appropriate search method.
    3. Activate the Hotkey over multiple lines of highlighted text which can consist of either
       string type. Each url/website/link must be a single entry per line. Multiple entries
       per line have not been tested yet.
    Single-line tests:
    1. Test the strings below by highlighting any line and activating the Hotkey.
    2. Test a string by copying it to the clipboard, make sure the line is not currently
       highlighted, and then activate the Hotkey to test the script's ability to read what is
       in the current Clipboard.
    Multi-line tests:
    1. Highlight all of the lines at once starting with the string 'funny' to the
       end of the website string ending with 'script-repo/' and then activate the Hotkey.
       The script will sort the strings appropriately by detecting the type of string
       that each line is composed of.
    Test Strings:
    funny cat videos
    how to bake a pie
    amazon.com
    mail.google.com
    https://github.com/slyfox1186/script-repo/
*/

^!c::
{
    Browser := GetDefaultBrowser()
    win := "ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe"
    ClipSaved := A_Clipboard ; Save the current Clipboard contents
    A_Clipboard := ""

    SendInput("^c")
    ClipWait(0.5)
    ; Ensure the clipboard is not empty and wait a bit more if it is
    if !(A_Clipboard)
        A_Clipboard := ClipSaved

    ; Parse clipboard text by new lines
    Loop Parse, A_Clipboard, "`n", "`r"
    {
        searchText := Trim(A_LoopField, " `t`r`n")
        if !(searchText)
            continue
        ; searchText values that are a url/website/link will be passed directly to the browser as a non-Google search query
        if RegExMatch(searchText, "i)^(https?:\/\/)?([a-z0-9\-]+\.)+[a-z]{2,6}(\/.*)?$")
        {
            searchThis := searchText
        }
        else
        {
            ; searchText values that are not a url/website/link will be passed as a Google search query
            searchThis := "https://google.com/search?q=" . '"' . searchText . '"'
        }
        ; Open the browser with the URL or search query
        Run(Browser . " --new-tab " . searchThis,, "Max")
        ; Attempt to bring the browser window to the foreground
        If !WinExist(win)
        {
            WinWait(win,, 2)
            WinActivate(win)
            WinMaximize(win)
        }
        Sleep 650 ; There is a Small delay to ensure the command is processed
    }
    ; Free the memory in case the clipboard was extensive
    ClipSaved := ""
    ; Clear the clipboard
    A_Clipboard := ""
}
GetDefaultBrowser()
{
    ; Retrieve the ProgId for the default browser
    browserQuery := RegRead("HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice", "ProgId")
    ; If a value was found for the registry entry ProgId then use it to get the default browser path.
    if (browserQuery)
    {
        ; Retrieve the application associated with the ProgId
        browserPath := RegRead("HKCR\" . browserQuery . "\shell\open\command",, "Default")
        ; Format the path to remove any command-line parameters
        if (browserPath)
        {
            browserPath := RegExReplace(browserPath, '"\s*--.*$', '"')
            ; Remove quotation marks for clarity
            browserPath := StrReplace(browserPath, '"', "")
        }
    }
    else
    {
        MsgBox "Unable to determine the default Browser Path from querying the registry."
        return
    }
    return browserPath
}
