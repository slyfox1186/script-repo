/*____________________________________________________________________________________

    Creator:       SlyFox1186
    Pastebin:      https://pastebin.com/u/slyfox1186

    Purpose:       Copy any highlighted text to the clipboard or use the
                   current clipboard contents and search google's engine.

    Instructions:  Replace the _browser variable below with the full path of your browser's exe.


    Update:        2.0 (12.16.21)
                   Added ability to parse strings that start with http or https

    Update:        3.0 (10.20.22)
                   Added RegEx filtering to only identify primary domains with matching endings.
                   See below to customize the inputs as needed.

    Update:        v4.0 (11.23.22)
                   Fixed RegEx false negative issues among other problems.

    Update:        v4.1 (12.02.22)
                   Removed an unnecessary duplicate step.

    Test:          google.com
                   battle.net
                   https://test.xyz   ; this should not work as it is not included in the list of acceptable names below.
                   www.yahoo.com
                   https://stackoverflow.com/users/10572786/slyfox1186
*/

^!c::
{
    _browser := "C:\Program Files\Google\Chrome Beta\Application\chrome.exe"
    setcontroldelay, -1 ; make sure the script is running as fast as possible
    _clipsaved := clipboardAll ; save current clipboard contents to its own variable
    clipboard := "" ; empty the clipboard
    sendinput, ^c ; make the clipboard ready to receive any possible input
    clipwait, 2.5 ; wait for that input to come through for no more than 2.5 second

    if (errorlevel)
        clipboard := _clipsaved ; if nothing is saved in the clipboard from the clipwait command then use the current clipboard's contents

    clipboard := trim(clipboard) ; trim both ends of the string found in clipboard

    ; task: list the types of primary domains you want regex to attempt to match.
    ; info: change the below domains as needed.
    _domains := [   .com
                ,   .de
                ,   .gov
                ,   .io
                ,   .jp
                ,   .net
                ,   .org
                ,   .to
                ,   .tv
                ,   .uk   ]

    ; test each of the primary domains above with regex expressions for any matches.
    for each, _domain in _domains
    {
        RegExMatch(clipboard, "\.[a-z]{2,3}$|.*$", _isMatch)
        RegExMatch(clipboard, "\.[a-z]{2,3}", _isMatchEnd)
        while (_ismatchend = _domain)
        {
            run, "%_browser%" --new-tab "%_isMatch%",, max, _wpid
            WinWait, ahk_pid %_wpid%,, 2
            WinSet, Top,, ahk_pid %_wpid%
            WinActivate, ahk_pid %_wpid%
            return
        }
    }

    /*
        task: modify the current string stored in the clipboard.

        info: search engines use uri-type encoding which means
              you need must replace certain characters with others
              for the engine to understand your query correctly.
    */

    stringreplace, clipboard, clipboard, `r`n, `%20, All
    stringreplace, clipboard, clipboard, !, `%21, All
    stringreplace, clipboard, clipboard, #, `%23, All
    stringreplace, clipboard, clipboard, $, `%24, All
    stringreplace, clipboard, clipboard, `%`%, `%25, All
    stringreplace, clipboard, clipboard, &, `%26, All
    stringreplace, clipboard, clipboard, ', `%27, All
    stringreplace, clipboard, clipboard, (, `%28, All
    stringreplace, clipboard, clipboard, ), `%29, All
    stringreplace, clipboard, clipboard, -, `%2D, All
    stringreplace, clipboard, clipboard, ., `%2E, All
    stringreplace, clipboard, clipboard, *, `%30, All
    stringreplace, clipboard, clipboard, :, `%3A, All
    stringreplace, clipboard, clipboard, ?, `%3F, All
    stringreplace, clipboard, clipboard, @, `%40, All
    stringreplace, clipboard, clipboard, [, `%5B, All
    stringreplace, clipboard, clipboard, ], `%5D, All
    stringreplace, clipboard, clipboard, ^, `%5E, All
    stringreplace, clipboard, clipboard, _, `%5F, All
    stringreplace, clipboard, clipboard, ``, `%60, All
    stringreplace, clipboard, clipboard, {, `%7B, All
    stringreplace, clipboard, clipboard, |, `%7C, All
    stringreplace, clipboard, clipboard, }, `%7D, All
    stringreplace, clipboard, clipboard, ~, `%7E, All
    stringreplace, clipboard, clipboard, \, /, All

    clipboard := trim(clipboard) ; trim the ends of the string again

    run, "%_browser%" --new-tab "https://google.com/search?q=%clipboard%",, max, _wpid
    WinWait, ahk_pid %_wpid%,, 2
    WinSet, Top,, ahk_pid %_wpid%
    WinActivate, ahk_pid %_wpid%
}
return
