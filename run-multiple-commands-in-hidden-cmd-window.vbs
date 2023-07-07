' RUN MULTIPLE COMMANDS IN A HIDDEN CMD WINDOW

If WScript.Arguments.length = 0 Then
Set oShell1 = CreateObject("Shell.Application")
	oShell1.ShellExecute "wscript.exe", Chr(34) & WScript.ScriptFullName & Chr(34) & " Run", , "RunAs", 0
Else
Set oShell2 = WScript.CreateObject("WScript.Shell")
	oShell2.Run "cmd.exe /D /C <COMMANDS>", 0, True
Set oShell3 = WScript.CreateObject("WScript.Shell")
	oShell3.Run "cmd.exe /D /C <COMMANDS>", 0, True
	WShell.Echo "Script Complete"
End If
Set oShell1 = Nothing
Set oShell2 = Nothing
Set oShell3 = Nothing
