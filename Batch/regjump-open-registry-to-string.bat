@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE REGJUMP TO EXPLORER SHELL FOLDERS

:-----------------------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM REGJUMP.EXE DOWNLOAD LINK: https://download.sysinternals.com/files/regjump.zip

:-----------------------------------------------------------------------------

PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:-----------------------------------------------------------------------------

SET "RJ=%windir%\System32\regjump.exe"
SET "RJC=%windir%\System32\regjump.exe -c"

:-----------------------------------------------------------------------------

REM CHOOSE A JUMP LOCATION
CLS & ECHO=
ECHO [1] USER
ECHO [2] MACHINE
ECHO [3] USE CLIPBOARD
ECHO [4] EXIT & ECHO=

CHOICE /C 1234 /N & CLS & ECHO=

:-----------------------------------------------------------------------------

IF ERRORLEVEL 4 GOTO :EOF
IF ERRORLEVEL 3 GOTO RegClipboard
IF ERRORLEVEL 2 GOTO RegMachine
IF ERRORLEVEL 1 GOTO RegUser

:-----------------------------------------------------------------------------

:RegMachine
ECHO HKEY_LOCAL_MACHINE & ECHO=
ECHO [1] *
ECHO [2] AllFilesystemObjects
ECHO [3] DesktopBackground
ECHO [4] Directory\Background
ECHO [5] Directory
ECHO [6] Drive
ECHO [7] Folder
ECHO [8] EXIT & ECHO=

CHOICE /C 12345678 /N & CLS & GOTO :EOF

IF ERRORLEVEL 8 GOTO :EOF
IF ERRORLEVEL 7 "%RJ%" "HKLM\Folder\shell" & GOTO :EOF
IF ERRORLEVEL 6 "%RJ%" "HKLM\Drive\shell" & GOTO :EOF
IF ERRORLEVEL 5 "%RJ%" "HKLM\Directory\shell" & GOTO :EOF
IF ERRORLEVEL 4 "%RJ%" "HKLM\Directory\Background\shell" & GOTO :EOF
IF ERRORLEVEL 3 "%RJ%" "HKLM\DesktopBackground\shell" & GOTO :EOF
IF ERRORLEVEL 2 "%RJ%" "HKLM\AllFilesystemObjects\shell" & GOTO :EOF
IF ERRORLEVEL 1 "%RJ%" "HKLM\*\shell" & GOTO :EOF

:-----------------------------------------------------------------------------

:RegUser
ECHO HKEY_CURRENT_USER & ECHO=
ECHO [1] *
ECHO [2] AllFilesystemObjects
ECHO [3] DesktopBackground
ECHO [4] Directory\Background
ECHO [5] Directory
ECHO [6] Drive
ECHO [7] Folder
ECHO [8] EXIT & ECHO=

CHOICE /C 12345678 /N & CLS & GOTO :EOF

IF ERRORLEVEL 8 GOTO :EOF
IF ERRORLEVEL 7 "%RJ%" "HKCR\Folder\shell" & GOTO :EOF
IF ERRORLEVEL 6 "%RJ%" "HKCR\Drive\shell" & GOTO :EOF
IF ERRORLEVEL 5 "%RJ%" "HKCR\Directory\shell" & GOTO :EOF
IF ERRORLEVEL 4 "%RJ%" "HKCR\Directory\Background\shell" & GOTO :EOF
IF ERRORLEVEL 3 "%RJ%" "HKCR\DesktopBackground\shell" & GOTO :EOF
IF ERRORLEVEL 2 "%RJ%" "HKCR\AllFilesystemObjects\shell" & GOTO :EOF
IF ERRORLEVEL 1 "%RJ%" "HKCR\*\shell" & GOTO :EOF

:-----------------------------------------------------------------------------

REM USE CURRENT CLIPBOARD
:RegClipboard
"%RJC%"
