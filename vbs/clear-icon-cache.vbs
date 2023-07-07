' RESET THE SYSTEM'S ICON CACHE

Option Explicit
Dim WShell, objFSO, strICPath1, strICPath2, strmsg, rtnStatus, Process, iDirtyFlags, iDirtyFlags2

Const DeleteReadOnly = True
Set WShell = WScript.CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")
strICPath1 = WShell.ExpandEnvironmentStrings("%LOCALAPPDATA%")
strICPath2 = strICPath1 & "\Microsoft\Windows\Explorer"

ExitExplorerShell
WScript.Sleep(3000)
ClearIconCache
WScript.Sleep(2000)
StartExplorerShell

' SUBROUTINE 1
' ===========================================================================================
Sub ExitExplorerShell()
	strmsg = "File Explorer must be stopped. "
	strmsg = strmsg & vbCrLf & vbCrLf & "Would you like to continue?"
	rtnStatus = MsgBox (strmsg, vbYesNo, "Clear the Icon Cache")
	If rtnStatus = vbYes Then
		For Each Process In GetObject("winmgmts:"). _
			ExecQuery ("select * from Win32_Process where name='explorer.exe'")
			Process.terminate(1)
		Next
	ElseIf rtnStatus = vbNo Then
		WScript.Quit
	End If
End Sub

' SUBROUTINE 2
' ===========================================================================================
Sub StartExplorerShell
	WShell.Run "explorer.exe"
	WScript.Echo "Success!" & vbCrLf & vbCrLf & "Press [ ENTER ] to continue..."
	WShell.Run "explorer.exe ""shell:Downloads"""
	If WShell.AppActivate("Downloads") Then
	Else
		WScript.Sleep(500)
		WShell.AppActivate("Downloads")
	End If
End Sub

' SUBROUTINE 3
' ===========================================================================================
Sub ClearIconCache()
	If (objFSO.FileExists(strICPath2 & "\thumbcache_*.db")) Then
		On Error Resume Next
		objFSO.DeleteFile strICPath2 & "\thumbcache_*.db", DeleteReadOnly
		On Error GoTo 0
		If Err.Number <> 0 And Err.Number <> 53 Then
			iDirtyFlags = 1
		End If
	End If

	If objFSO.FolderExists(strICPath2) Then
		On Error Resume Next
		objFSO.DeleteFile(strICPath2 & "\iconcache_*.db"), DeleteReadOnly
		On Error GoTo 0
		If Err.Number <> 0 And Err.Number <> 53 Then
			iDirtyFlags2 = 1
		End If
	End If
	WShell.Run "C:\Windows\System32\ie4uinit.exe -show"
End Sub

' MSGBOXES
' ===========================================================================================
If iDirtyFlags = 1 Then
	rtnStatus = MsgBox ("Some programs are still using the IconCache.db in LOCALAPPDATA. Close all programs and try again", vbOKOnly, "Clear the Icon Cache")
End If
If iDirtyFlags2 = 1 Then
	If iDirtyFlags <> 1  Then
		rtnStatus = MsgBox ("Some programs are still using the cache in Location 2. Close all programs and try again", vbOKOnly, "Clear the Icon Cache")
	End If
End If
Set WShell = Nothing
Set objFSO = Nothing
