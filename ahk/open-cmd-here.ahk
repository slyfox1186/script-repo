/*
	OpenCMDHere
	Required: AutoHotkey.exe

	Opens 'cmd.exe' using the active explorer.exe window's folder path
	as the working directory. If explorer is not the active window
	when triggered it will open 'cmd.exe' using "C:\Windows\System32"
	as the working directory.

    The '_pwd' VAR may require character changes in the file path
    that is retrieved because of the way ComObject stores characters.
    RegEx is used to change the special 'URL' encoding to 'ASCII'
    format so 'cmd.exe' can read it without throwing errors.
    https://www.w3schools.com/tags/ref_urlencode.ASP
*/

#SingleInstance, Force
DetectHiddenText, On
DetectHiddenWindows, On
SetTitleMatchMode, 2

!c::_OpenCMDHere()

_OpenCMDHere()
{
	If WinExist("ahk_class CabinetWClass ahk_exe explorer.exe")
		_winHWND := WinActive()
	For win in ComObjCreate("Shell.Application").Windows
		If (win.HWND = _winHWND)
		{
			_pwd := SubStr(win.LocationURL, 9)
			_pwd := RegExReplace(_pwd, "%20", " ")
			_pwd := RegExReplace(_pwd, "%21", "!")
			_pwd := RegExReplace(_pwd, "%24", "$")
			_pwd := RegExReplace(_pwd, "%25", "%")
			_pwd := RegExReplace(_pwd, "%26", "&")
			_pwd := RegExReplace(_pwd, "%27", "'")
			_pwd := RegExReplace(_pwd, "%28", "(")
			_pwd := RegExReplace(_pwd, "%29", ")")
			_pwd := RegExReplace(_pwd, "%2D", "-")
			_pwd := RegExReplace(_pwd, "%2E", ".")
			_pwd := RegExReplace(_pwd, "%30", "*")
			_pwd := RegExReplace(_pwd, "%3A", ":")
			_pwd := RegExReplace(_pwd, "%3F", "?")
			_pwd := RegExReplace(_pwd, "%40", "@")
			_pwd := RegExReplace(_pwd, "%5B", "[")
			_pwd := RegExReplace(_pwd, "%5D", "]")
			_pwd := RegExReplace(_pwd, "%5E", "^")
			_pwd := RegExReplace(_pwd, "%5F", "_")
			_pwd := RegExReplace(_pwd, "%60", "``")
			_pwd := RegExReplace(_pwd, "%7B", "{")
			_pwd := RegExReplace(_pwd, "%7C", "|")
			_pwd := RegExReplace(_pwd, "%7D", "}")
			_pwd := RegExReplace(_pwd, "%7E", "~")
			_pwd := RegExReplace(_pwd, "/", "\")
		}
	Run, "C:\Windows\System32\cmd.exe" /T:0A /K PROMPT $P$G$_$G, % _pwd ? _pwd : "C:\Windows\System32\",, _winPID
	WinWaitActive, ahk_pid %_winPID%
	WinGetPos,,, _Width, _Height, ahk_pid %_winPID%
	WinMove, ahk_pid %_winPID%,, (A_ScreenWidth/2)-(_Width/2), (A_ScreenHeight/2)-(_Height/2)
}
Return
