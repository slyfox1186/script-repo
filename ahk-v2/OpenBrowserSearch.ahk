/*____________________________________________________________________________________

  Open your browser and search google or if it is a website visit the website
  Test the strings below!

  funny cat videos
  amazon.com
  mail.google.com
  https://github.com/slyfox1186/script-repo/new/main
  Test WebSite.com
  
  */
  
#Requires AutoHotkey v2.0

SendMode("Input")

^!c::
{
    SetControlDelay -1 ; make sure the script is run as fast as possible
    ClipSaved := ClipboardAll() ; save current A_Clipboard contents to its own variable
    A_Clipboard := "" ; Empty the clipboard
    Send "^c"
    If !ClipWait(2)
        A_Clipboard := ClipSaved ; If nothing is saved in the A_Clipboard from the clipwait command then use the current A_Clipboards contents

    A_Clipboard := Trim(A_Clipboard) ; Trim both ends of the string found in A_Clipboard

    ; A_Clipboard is the text only bit of the clipboard.
    ; trim whitepsace including "enter", becuse some apps are overzealous when selecting text. Trim does spaces and tabs by default."
    _text := Trim(A_Clipboard, " `t`r`n") 

    ; if the text ends in specific text matching a set of TLDs, assume it's a www address.
    ; otherwise query the text.
    ; if text does not end with listed postfix, add "? " so chrome treats it as query.
    _prefix := RegExMatch(_text, "i)^\S+\.(com|de|gov|io|jp|net|org|to|tv|uk)$")? "" : "? "

    ; Attach the prefix and wrap text in quotes.
    ; Characters between quotes are parsed as a single argument for most windows apps.
    ; NOTE: if you are using an editor with syntax highlighting it might color this part wrong.
    ;   AHK's quoting rules are ... interesting.
    ; '"' is a string containing a quote.
    _location :=  '"' . _prefix . _text . '"'

    ; Open chrome
    Run("C:\Program Files\Google\Chrome Beta\Application\chrome.exe --new-tab " . _location,,"Max")
    WinWait "ahk_exe chrome.exe",, 2
    WinActivate "ahk_exe chrome.exe"
    Return
} 
