/*____________________________________________________________________________________

    Creator:       SlyFox1186
    Pastebin:      https://pastebin.com/u/slyfox1186

    Purpose:       Copy any highlighted text to the clipboard or use the
                   current clipboard contents and search google's engine.

    Instructions:  Replace the _browser variable below with the full path of your browser's exe.


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
    _browser := "C:\Program Files\Google\Chrome Beta\Application\chrome.exe"
    setcontroldelay, -1 ; make sure the script is running as fast as possible
    _clipsaved := clipboardAll ; save current clipboard contents to its own variable
    clipboard := "" ; empty the clipboard
    sendinput, ^c ; make clipboard ready to receive any possible input
    clipwait, 2.5 ; wait for that input to come through for no more than 2.5 second

    if (errorlevel)
        clipboard := _clipsaved ; if nothing is saved in the clipboard from the clipwait command then use the current clipboards contents

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

    ; test each of the primary domain above with regex expressions for any matches.
    for each, _domain in _domains
    {
        RegExMatch(clipboard, "\.[a-z]{2,3}$|.*$", _isMatch)
        RegExMatch(clipboard, "\.[a-z]{2,3}?$", _isMatchEnd)
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

    MsgBox, run, "%_browser%" --new-tab "https://google.com/search?q=%clipboard%",, max, _wpid
    WinWait, ahk_pid %_wpid%,, 2
    WinSet, Top,, ahk_pid %_wpid%
    WinActivate, ahk_pid %_wpid%
}
return

; ARIA2 CHROME EXTENSION paste + .mp4

^!+7::
{
    _win := "ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe"
    WinGet, _wPID, PID, % _win
    WinGet, _wID, ID, % _win
    win := _win . " ahk_pid " . _wPID . " ahk_id " . _wID
    If WinExist(win) && WinActive(win) || !WinActive(win)
    {
        _paste := Clipboard . ".mp4"
        SendInput, % _paste
        Sleep, 75
        Send, {Enter}
        Sleep, 100
        SendInput, ^{w}
    }
}

; ARIA2 CHROME EXTENSION Pics.7z

^!+8::
{
    SetControlDelay, 50
    SetKeyDelay, 50
    _wAria2 := "AriaNg ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe"
    _win := "ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe"
    WinGet, _wPID, PID, % _win
    WinGet, _wID, ID, % _win
    win := _win . " ahk_pid " . _wPID . " ahk_id " . _wID
    If WinExist(win) && WinActive(win) || !WinActive(win)
    {
        Click
        WinWaitActive, %_wAria2%,, 2
        Sleep, 2000
        Send, {Tab 4}
        Sleep, 50
        Send, {Down}
        Sleep, 50
        SendInput, {Enter}
        Sleep, 50
        Send, {Tab}
        Sleep, 50
        BlockInput, On
        SendRaw, Pics.zip
        BlockInput, Off
        Sleep, 50
        SendInput, {Enter}
        Sleep, 50
        SendInput, ^{w}
        Sleep, 50
        SendInput, ^{w}
    }
}

/*____________________________________________________________________________________
    MAKE THE REFRESH KEYBOARD SHORTCUT INTO REFRESH WITHOUT CACHE

*/

~^r::
{
    _win := "ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe"
    WinGetTitle, _wTitle, % _win
    WinGet, _wPID, PID, % _win
    win := _wTitle . " " . _win .  " ahk_pid " . _wPID
    if WinExist(win) && WinActive(win)
    {
        send, {RCtrl Down}{F5 Down}
        sleep, 5
        send, {F5 Up}{RCtrl Up}
    }
    else
    {
        send, {RCtrl Down}
        sleep, 5
        send, {RCtrl Up}
    }
}
return
