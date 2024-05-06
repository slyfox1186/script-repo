@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
COLOR 0A
TITLE ENTER OR EXIT WINDOWS SAFE MODE

:------------------------------------------------------------------------------------------------

REM Created By: SlyFox1186
REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

:------------------------------------------------------------------------------------------------

REM THIS SCRIPT ELIMINATES THE NEED FOR MULTIPLE
REM SUPPORTING FILES TO ENTER OR EXIT WINDOWS SAFE MODE

REM CHOOSE FROM THE FOLLOWING BOOT OPTIONS:
REM	[SAFE MODE MINIMAL]
REM	[SAFE MODE WITH NETWORKING]
REM	[SAFE MODE WITH COMMAND PROMPT]
REM	[EXIT SAFE MODE]

REM INSTRUCTIONS:
REM SAVE THE SCRIPT WITH A ".bat" EXTENSION
REM DO NOT USE ".cmd" OR THE CHOICE COMMAND WILL FAIL
REM TO PROCESS THE USER'S INPUT IN THE CORRECT NUMERICAL ORDER

REM UPDATES:
REM :::::::::::::::::::::::::::::::::::::::::::::::::::::::::
REM ::                                                     ::
REM :: v4.0                                                ::
REM :: ADDED TIMEOUT VARIABLE                              ::
REM :: REMOVED SEVERAL UNNECESSARY VARIABLES               ::
REM :: ADDED SPACERS FOR EASIER VIEWING                    ::
REM :: CHANGED CHOICE COMMAND FORMATTING AT BOTTOM         ::
REM ::                                                     ::
REM :: v3.0                                                ::
REM :: OPTIMIZED SCRIPT FLOW                               ::
REM :: REMOVED UNNECESSARY PARTS                           ::
REM ::                                                     ::
REM :: v2.0                                                ::
REM :: REMOVED MOST OF THE SUBROUTINE SECTION              ::
REM :: ELIMINATED THE NEED FOR MULTIPLE SETLOCAL INSTANCES ::
REM ::                                                     ::
REM :::::::::::::::::::::::::::::::::::::::::::::::::::::::::

REM START SCRIPT

:-------------------------------------------------------------

REM MAXIMIZE CMD WINDOW
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:-----------------------------------------------------------------

REM CHANGE THE "SEC" VAR BELOW TO CHANGE HOW LONG WINDOWS WAITS BEFORE REBOOTING.
REM DO NOT SET A VALUE LOWER THAN "8" OR THE SCRIPT COULD FAIL TO PERFORM AS INTENDED!
SET SEC=8

:-----------------------------------------------------------------

REM ECHO RECOMMENDATIONS FOR USER
CLS & ECHO=
ECHO   :::::::::::::::::::::::::::::::::::::::::::::::::::
ECHO   ::                                               ::
ECHO   ::        Enter or Exit Windows Safe Mode        ::
ECHO   ::                                               ::
ECHO   ::           Please Save All Open Work           ::
ECHO   ::                                               ::
ECHO   ::           Press [Enter] To Continue           ::
ECHO   ::                                               ::
ECHO   :::::::::::::::::::::::::::::::::::::::::::::::::::
ECHO=
SET /P=Press [Enter] to Continue >NUL
GOTO FirstChoice

:-----------------------------------------------------------------

REM AFTER A SCRIPT RESTART, KILL ANY LEFTOVER PROCESSES
:StartOver
TASKLIST | FIND "wlrmdr.exe" >NUL
	IF ERRORLEVEL 1 GOTO HungProcess
		TASKKILL /F /IM "wlrmdr.exe" /T
		GOTO FirstChoice
:HungProcess
TASKLIST | FIND "wscript.exe" >NUL
	IF ERRORLEVEL 1 GOTO FirstChoice
		TASKKILL /F /IM "wscript.exe" /T

:-----------------------------------------------------------------

REM PROMPT USER CHOICES
:FirstChoice
CLS & ECHO=
ECHO   :::::::::::::::::::::::::::::::::::::::::::::::::::
ECHO   ::                                               ::
ECHO   ::  Choose A Boot Mode:                          ::
ECHO   ::                                               ::
ECHO   ::  [1] Safe Mode Minimal                        ::
ECHO   ::  [2] Safe Mode with Networking                ::
ECHO   ::  [3] Safe Mode with Command Prompt            ::
ECHO   ::  [4] Exit Safe Mode                           ::
ECHO   ::                                               ::
ECHO   :::::::::::::::::::::::::::::::::::::::::::::::::::
ECHO=
CHOICE /C 1234 /N & CLS & ECHO=

:-----------------------------------------------------------------

REM EXIT SAFE MODE
IF NOT ERRORLEVEL 4 GOTO TryCmd
(
ECHO If WScript.Arguments.length = 0 Then
ECHO Set oShell = CreateObject^("Shell.Application"^)
ECHO 	oShell.ShellExecute "wscript.exe", Chr^(34^) ^& WScript.ScriptFullName ^& Chr^(34^) ^& " Run", , "RunAs", 1 
ECHO Else
ECHO Set oShell2 = WScript.CreateObject^("WScript.Shell"^)
ECHO 	oShell2.Run "bcdedit /deletevalue {current} safeboot",0,True
ECHO 	oShell2.Run "bcdedit /deletevalue {current} safebootalternateshell",0,True
ECHO 	oShell2.Run "shutdown -r -t %SEC% -f", 0, True
ECHO End If
ECHO Set oShell = Nothing
ECHO Set oShell2 = Nothing
)>"%TMP%\safeExit.vbs"
	CALL :ConfirmChoice "Exit Safe Mode" "%TMP%\safeExit.vbs"
	GOTO :EOF

:-----------------------------------------------------------------

REM ENTER SAFE MODE WITH COMMAND PROMPT
:TryCmd
IF NOT ERRORLEVEL 3 GOTO TryNet
(
ECHO If WScript.Arguments.length = 0 Then
ECHO Set oShell = CreateObject^("Shell.Application"^)
ECHO 	oShell.ShellExecute "wscript.exe", Chr^(34^) ^& WScript.ScriptFullName ^& Chr^(34^) ^& " Run", , "RunAs", 1 
ECHO Else
ECHO Set oShell2 = WScript.CreateObject^("WScript.Shell"^)
ECHO 	oShell2.Run "bcdedit /set {current} safeboot minimal",0,True
ECHO 	oShell2.Run "bcdedit /set {current} safebootalternateshell yes",0,True
ECHO 	oShell2.Run "shutdown -r -t %SEC% -f", 0, True
ECHO End If
ECHO Set oShell = Nothing
ECHO Set oShell2 = Nothing
)>"%TMP%\safeCmd.vbs"
	CALL :ConfirmChoice "Safe Mode with Command Prompt" "%TMP%\safeCmd.vbs"
	GOTO :EOF

:-----------------------------------------------------------------

REM ENTER SAFE MODE WITH NETWORKING
:TryNet
IF NOT ERRORLEVEL 2 GOTO TrySafe
(
ECHO If WScript.Arguments.length = 0 Then
ECHO Set oShell = CreateObject^("Shell.Application"^)
ECHO 	oShell.ShellExecute "wscript.exe", Chr^(34^) ^& WScript.ScriptFullName ^& Chr^(34^) ^& " Run", , "RunAs", 1 
ECHO Else
ECHO Set oShell2 = WScript.CreateObject^("WScript.Shell"^)
ECHO 	oShell2.Run "bcdedit /set {current} safeboot network",0,True
ECHO 	oShell2.Run "shutdown -r -t %SEC% -f", 0, True
ECHO End If
ECHO Set oShell = Nothing
ECHO Set oShell2 = Nothing
)>"%TMP%\safeNet.vbs"
	CALL :ConfirmChoice "Safe Mode with Networking" "%TMP%\safeNet.vbs"
	GOTO :EOF

:-----------------------------------------------------------------

REM ENTER SAFE MODE MINIMAL
:TrySafe
IF NOT ERRORLEVEL 1 GOTO :EOF
(
ECHO If WScript.Arguments.length = 0 Then
ECHO Set oShell = CreateObject^("Shell.Application"^)
ECHO 	oShell.ShellExecute "wscript.exe", Chr^(34^) ^& WScript.ScriptFullName ^& Chr^(34^) ^& " Run", , "RunAs", 1 
ECHO Else
ECHO Set oShell2 = WScript.CreateObject^("WScript.Shell"^)
ECHO 	oShell2.Run "bcdedit /set {current} safeboot minimal",0,True
ECHO 	oShell2.Run "shutdown -r -t %SEC% -f", 0, True
ECHO End If
ECHO Set oShell = Nothing
ECHO Set oShell2 = Nothing
)>"%TMP%\safeMode.vbs"
	CALL :ConfirmChoice "Safe Mode Minimal" "%TMP%\safeMode.vbs"
	GOTO :EOF

:-----------------------------------------------------------------

REM BEGIN SUBROUTINE
:ConfirmChoice
CLS & ECHO=
ECHO   You Chose: [ %~1 ]
ECHO=
ECHO   :::::::::::::::::::::::::::::::::::::::::::::::::::
ECHO   ::                                               ::
ECHO   ::  Confirm Choice:                              ::
ECHO   ::                                               ::
ECHO   ::  [1] Restart PC                               ::
ECHO   ::  [2] Restart Script                           ::
ECHO   ::  [3] Exit Script                              ::
ECHO   ::                                               ::
ECHO   :::::::::::::::::::::::::::::::::::::::::::::::::::
ECHO=
CHOICE /C 123 /N & CLS & ECHO=

:-----------------------------------------------------------------

REM EXIT SCRIPT
IF ERRORLEVEL 3 (
	DEL /F /Q "%~2"
	GOTO :EOF
)

REM RESTART SCRIPT
IF ERRORLEVEL 2 (
	DEL /F /Q "%~2"
	ENDLOCAL
	GOTO StartOver
)

REM PROCEED WITH PC RESTART
IF ERRORLEVEL 1 (
	C:\Windows\System32\wscript.exe //NoLogo "%~2"
	:Rescan
	TIMEOUT 1 /NOBREAK >NUL
	TASKLIST | FIND "wlrmdr.exe" >NUL
		IF ERRORLEVEL 1 GOTO Rescan
			TASKKILL /F /IM "wlrmdr.exe" /T >NUL 2>&1
				CLS & ECHO=
				ECHO   :::::::::::::::::::::::::::::::::::::::::::::::::::
				ECHO   ::                                               ::
				ECHO   ::           Your PC Will Restart Soon           ::
				ECHO   ::                                               ::
				ECHO   ::                 Closing CMD..                 ::
				ECHO   ::                                               ::
				ECHO   :::::::::::::::::::::::::::::::::::::::::::::::::::
				ECHO=
				TIMEOUT 4
				DEL /F /Q "%~2"
				GOTO :EOF
)
