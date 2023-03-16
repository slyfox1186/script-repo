^!c::
{

    _Browser := "C:\Program Files\Google\Chrome Beta\Application\chrome.exe"
    setcontroldelay, -1 ; make sure the script is running as fast as possible
    _ClipSaved := ClipboardAll ; save current Clipboard contents to its own variable
    Clipboard := "" ; empty the Clipboard
    SendInput, ^c ; make Clipboard ready to receive any possible input
    ClipWait, 2 ; wait for that input to come through for no more than 2.5 second

    If (ErrorLevel)
        Clipboard := _ClipSaved ; If nothing is saved in the Clipboard from the clipwait command then use the current Clipboards contents

    Clipboard := Trim(Clipboard) ; Trim both ends of the string found in Clipboard

    ; task: list the types of primary domains you want regex to attempt to match.
    ; info: change the below domains as needed.
        _Domains := [   .com
                    ,   .de
                    ,   .gov
                    ,   .io
                    ,   .jp
                    ,   .net
                    ,   .org
                    ,   .to
                    ,   .tv
                    ,   .uk   ]

    ; test each of the primary domain above with regex expressions for any matches.
    For Each, _Domain in _Domains
    {
        RegExMatch(Clipboard, "\.[a-z]{2,3}$|.*$", _isMatch)
        RegExMatch(Clipboard, "(\.(com|de|gov|io|jp|net|org|to|tv|uk)[$]*)", _isMatchEnd)
        While (_isMatchEnd = _Domain)
        {
            Run, "C:\Program Files\Google\Chrome Beta\Application\chrome.exe" --new-tab %_isMatch%,, Max
            WinWait, ahk_exe chrome.exe
            WinActivate, ahk_exe chrome.exe
            Return
        }
    }

    If (_isMatchEnd = _Domain)
        Clipboard := ""

    /*
        task: modify the current string stored in the Clipboard.

        info: search engines use uri-type encoding which means
              you need must replace certain characters with others
              for the engine to understand your query correctly.
    */

    StringReplace, Clipboard, Clipboard, -, `%2D, All
    StringReplace, Clipboard, Clipboard, ., `%2E, All
    StringReplace, Clipboard, Clipboard, _, `%5F, All
    StringReplace, Clipboard, Clipboard, ~, `%7E, All

    Clipboard := Trim(Clipboard) ; Trim the ends of the string again

    Run, "C:\Program Files\Google\Chrome Beta\Application\chrome.exe" --new-tab https://google.com/search?q=%Clipboard%,, Max
    WinWait, ahk_exe chrome.exe
    WinActivate, ahk_exe chrome.exe
}
Return
