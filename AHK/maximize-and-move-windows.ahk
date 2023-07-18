/*
	Maximize and Move Windows

	Created by: SlyFox1186
	Pastebin: https://pastebin.com/u/slyfox1186
	Requires AutoHotkey.exe

	Reworked (v2.0) uses a different (easier) method of
	adding/organizing window names: https://pastebin.com/t4BeVkzM
	Either version works.
	
	This script will move all windows that match the process
	names defined inside the brackets:  ["cmd" , "notepad"]
	Modify '0, 0, 1920, 1080' to match your monitor's dimensions

*/

#Persistent
#SingleInstance, Force

; Press Ctrl+Alt+c to activate
^!c::

For k, v in ["cmd" , "notepad"]

{
	WinGet, win, List, ahk_exe %v%.exe
	Loop, %win%
	{
		WinGet, _IsMax, MinMax, % wTitle := "ahk_id " win%A_Index%
		If (_IsMax = 1)
			Continue
			WinActivate, % wTitle
			WinMove, %wTitle%,, 0, 0, 1920, 1080
	}
}
Return
