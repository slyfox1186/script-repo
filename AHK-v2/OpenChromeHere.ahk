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

^!c Up::
{
    Browser := GetDefaultBrowser()
    win := "ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe"
    ClipSaved := A_Clipboard
    A_Clipboard := ""
    Send("^c")
    if !ClipWait(0.75)
        A_Clipboard := ClipSaved

    Loop Parse, A_Clipboard, "`n", "`r"
    {
        searchText := Trim(A_LoopField)
        if !searchText
            continue
        searchThis := RegExMatch(searchText, "i)^(https?:\/\/|www\.)|(\.[a-z]{2,}\/?$)") ? searchText : "https://google.com/search?q=" . UrlEncode(searchText)
        Run(Browser . " --new-tab " . searchThis,, "Max")
        WinWaitActive(win,, 1)
        sleepThis := Random(500, 1350)  ; Random delay between 0.5 and 1.35 minutes (in milliseconds)
        Sleep(sleepThis)
        Sleep(25)
    }
    A_Clipboard := ""
}

GetDefaultBrowser() {
    browserQuery := RegRead("HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice", "ProgId")
    if (browserQuery) {
        browserPath := RegRead("HKCR\" . browserQuery . "\shell\open\command")
        if (browserPath) {
            return RegExReplace(StrReplace(browserPath, '"'), '\s*--.*$')
        }
    }
    MsgBox("Unable to determine the default Browser Path.")
    reload
}

UrlEncode(str) {
    return RegExReplace(str, "[!#$&'()*+,/:;=?@[\]%\s]", "%$0")
}
