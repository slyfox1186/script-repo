@ECHO OFF
SETLOCAL
COLOR 0A
TITLE ENABLE HPET IN WINDOWS

:-------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM THIS SCRIPT ONLY ENABLES WINDOWS TIMER (HPET)
REM TO [ ENABLE OR DISABLE ] HPET VISIT: https://pastebin.com/rqMrZmr2

:-------------------------------------------------------------

REM CREATE TEMP TXT FILE TO CHECK IF HPET IS ENABLED
BCDEDIT /enum > "%AppData%\temp.txt"
IF ERRORLEVEL 1 GOTO ERROR
	FINDSTR /C:"useplatformclock        Yes" "%AppData%\temp.txt" >NUL

:-------------------------------------------------------------
:CHECKS_TATUS
REM CHECK IF HPET ALREADY ENABLED
IF NOT ERRORLEVEL 1 GOTO ALREADY_ENABLED
	BCDEDIT /set useplatformclock true >NUL 2>&1

:-------------------------------------------------------------

REM CHECK IF HPET WAS ENABLED SUCCESFULLY
IF ERRORLEVEL 0 (
	DEL /F /Q "%AppData%\temp.txt" >NUL 2>&1
	CLS
	ECHO HPET ENABLED SUCCESSFULLY, SYSTEM RESTART IS REQUIRED
	TIMEOUT 4 >NUL
	GOTO RESTART
)

:-------------------------------------------------------------
:ALREADY_ENABLED
REM HPET ALREADY ENABLE
:-------------------------------------------------------------

DEL /F /Q "%AppData%\temp.txt" >NUL 2>&1
CLS
ECHO HPET IS ALREADY ENABLED & ECHO=
PAUSE
GOTO :EOF

:-------------------------------------------------------------
:RESTART
REM PROMPT USER CHOICE FOR PC RESTART
:-------------------------------------------------------------

CLS
ECHO RESTART PC NOW? & ECHO=
ECHO [1] YES
ECHO [2] NO & ECHO=

CHOICE /C 12 /N /M "Select a number: " & CLS

IF ERRORLEVEL 2 GOTO :EOF
IF ERRORLEVEL 1	(
	SHUTDOWN /R /T 1
	GOTO :EOF
)

:-------------------------------------------------------------
:ERROR
REM PLEASE RUN SCRIPT AS ADMIN
:-------------------------------------------------------------

CLS
ECHO ERROR SCRIPT LINE 12: & ECHO=
ECHO UNABLE TO CREATE TEMP FILE: "%AppData%\temp.txt" & ECHO=
ECHO MAKE SURE TO RUN THE SCRIPT AS AN ADMINISTRATOR & ECHO=
PAUSE
GOTO :EOF
