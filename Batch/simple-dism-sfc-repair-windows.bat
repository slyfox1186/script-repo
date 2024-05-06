@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE SIMPLE DISM AND SFC REPAIR

:----------------------------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM USE THIS TO FIX AND REPAIR CORRUPTED WINDOWS 10 AND 11 IMAGES

:----------------------------------------------------------------------------------

IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:----------------------------------------------------------------------------------

TASKLIST | FINDSTR "Dism.exe TiWorker.exe" >NUL && TASKKILL /F /IM "Dism.exe" /IM "TiWorker.exe" /T >NUL 2>&1

:----------------------------------------------------------------------------------

ECHO DISM ^& SFC & ECHO=
ECHO [1] NO RESTART
ECHO [2] RESTART PC
ECHO [3] EXIT & ECHO=

CHOICE /C 123 /N & CLS

:----------------------------------------------------------------------------------

IF ERRORLEVEL 3 GOTO :EOF
IF ERRORLEVEL 2 SET "FLAG=A" & GOTO RUNTHIS
IF ERRORLEVEL 1 CLS

:----------------------------------------------------------------------------------

:RUNTHIS
DISM /Online /Cleanup-Image /RestoreHealth /StartComponentCleanup
ECHO=
DISM /Online /Cleanup-Image /RestoreHealth
ECHO=
SFC /SCANNOW
ECHO=
SFC /SCANNOW

:----------------------------------------------------------------------------------

IF %FLAG%==A (
	SHUTDOWN /R /T 1
	GOTO :EOF
)

:----------------------------------------------------------------------------------

ECHO=
PAUSE
