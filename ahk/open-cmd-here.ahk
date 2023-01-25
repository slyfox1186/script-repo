/*____________________________________________________________________________________

    Creator:       SlyFox1186
    Pastebin:      https://pastebin.com/u/slyfox1186

    Purpose:       Copy any highlighted text to the Clipboard or use the
                   current Clipboard contents and search google's engine.

    Instructions:  Replace the _Browser variable below with the full path of your browser's exe.


    Update 1:      2.0 (12.16.21)
                   Added ability to parse strings that start with http or https

    Update 2:      3.0 (10.20.22)
                   Added RegEx filtering to only identify primary domains with matching endings.
                   See below to customize the inputs as needed.

    Update 3:      v4.0 (11.23.22)
                   Fixed RegEx false negative issues among other problems.

    Update 4:      v4.1 (12.02.22)
                   Removed an unnecessary duplicate step.


    Update 5:      v4.2 (01.25.23)
                   Fixed a regex issue where URLs whith sub domains would not match correctly.

    Test:          google.com
                   battle.net
                   https://test.xyz   ; this should not work as it is not icluded in the list of acceptable names below.
                   www.yahoo.com
                   https://stackoverflow.com/users/10572786/slyfox1186
*/

^!c::
{
    _Browser := "C:\Program Files\Google\Chrome Beta\Application\chrome.exe"
    setcontroldelay, -1 ; make sure the script is running as fast as possible
    _ClipSaved := ClipboardAll ; save current Clipboard contents to its own variable
    Clipboard := "" ; empty the Clipboard
    sendinput, ^c ; make Clipboard ready to receive any possible input
    clipwait, 2.5 ; wait for that input to come through for no more than 2.5 second

    if (errorlevel)
        Clipboard := _ClipSaved ; if nothing is saved in the Clipboard from the clipwait command then use the current Clipboards contents

    Clipboard := trim(Clipboard) ; trim both ends of the string found in Clipboard

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
    for each, _Domain in _Domains
    {
        RegExMatch(Clipboard, "\.[a-z]{2,3}$|.*$", _isMatch)
        RegExMatch(Clipboard, "\.[a-z]+[$]*", _isMatchEnd)
        while (_isMatchEnd = _Domain)
        {
            run, "%_Browser%" --new-tab "%_isMatch%",, max, _wpid
            WinWait, ahk_pid %_wpid%,, 2
            WinSet, Top,, ahk_pid %_wpid%
            WinActivate, ahk_pid %_wpid%
            return
        }
    }

    /*
        task: modify the current string stored in the Clipboard.

        info: search engines use uri-type encoding which means
              you need must replace certain characters with others
              for the engine to understand your query correctly.
    */

    stringreplace, Clipboard, Clipboard, `r`n, `%20, All
    stringreplace, Clipboard, Clipboard, !, `%21, All
    stringreplace, Clipboard, Clipboard, #, `%23, All
    stringreplace, Clipboard, Clipboard, $, `%24, All
    stringreplace, Clipboard, Clipboard, `%`%, `%25, All
    stringreplace, Clipboard, Clipboard, &, `%26, All
    stringreplace, Clipboard, Clipboard, ', `%27, All
    stringreplace, Clipboard, Clipboard, (, `%28, All
    stringreplace, Clipboard, Clipboard, ), `%29, All
    stringreplace, Clipboard, Clipboard, -, `%2D, All
    stringreplace, Clipboard, Clipboard, ., `%2E, All
    stringreplace, Clipboard, Clipboard, *, `%30, All
    stringreplace, Clipboard, Clipboard, :, `%3A, All
    stringreplace, Clipboard, Clipboard, ?, `%3F, All
    stringreplace, Clipboard, Clipboard, @, `%40, All
    stringreplace, Clipboard, Clipboard, [, `%5B, All
    stringreplace, Clipboard, Clipboard, ], `%5D, All
    stringreplace, Clipboard, Clipboard, ^, `%5E, All
    stringreplace, Clipboard, Clipboard, _, `%5F, All
    stringreplace, Clipboard, Clipboard, ``, `%60, All
    stringreplace, Clipboard, Clipboard, {, `%7B, All
    stringreplace, Clipboard, Clipboard, |, `%7C, All
    stringreplace, Clipboard, Clipboard, }, `%7D, All
    stringreplace, Clipboard, Clipboard, ~, `%7E, All
    stringreplace, Clipboard, Clipboard, \, /, All

    Clipboard := trim(Clipboard) ; trim the ends of the string again

    msgbox, run, "%_Browser%" --new-tab "https://google.com/search?q=%Clipboard%",, max, _wpid
    WinWait, ahk_pid %_wpid%,, 2
    WinSet, Top,, ahk_pid %_wpid%
    WinActivate, ahk_pid %_wpid%
}
return
