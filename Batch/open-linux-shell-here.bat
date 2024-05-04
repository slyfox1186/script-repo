@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE OPEN WINDOWS WSL HERE

:------------------------------------------------------------------------------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:------------------------------------------------------------------------------------------------------------------------------------

REM PICK THE CORRECT POWERSHELL EXE TO USE
IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (SET EXE=pwsh.exe) ELSE (SET EXE=powershell.exe)

:------------------------------------------------------------------------------------------------------------------------------------

ECHO Available Distros to choose from below
ECHO Press enter to continue when done selecting
ECHO=
wsl.exe -l --all
ECHO=
SET /P DIST="Please input one of the listed distros to set as the default: "
CLS

:------------------------------------------------------------------------------------------------------------------------------------

(
ECHO Windows Registry Editor Version 5.00
ECHO=
ECHO ^; ADD OPEN LINUX HERE
ECHO=
ECHO ^; [ * ]
ECHO=
ECHO [HKEY_CLASSES_ROOT\*\shell\WSL]
ECHO @^="Open WSL Here"
ECHO "Icon"^="C:\\Windows\\System32\\wsl.exe"
ECHO "NoWorkingDirectory"^=""
ECHO "Extended"^=-
ECHO=
ECHO [HKEY_CLASSES_ROOT\*\shell\WSL\command]
ECHO @^="%EXE% -NoP -NoL -W Hidden -C \"Start-Process wt.exe -Args ^'-w new-tab -M -d \\\"%%W\\\" wsl.exe -d %DIST%^' -Verb RunAs\""
ECHO=
ECHO=
ECHO ^; [ DesktopBackground ]
ECHO=
ECHO [HKEY_CLASSES_ROOT\DesktopBackground\shell\WSL]
ECHO @^="Open WSL Here"
ECHO "Icon"^="C:\\Windows\\System32\\wsl.exe"
ECHO "NoWorkingDirectory"^=""
ECHO "Extended"^=-
ECHO=
ECHO [HKEY_CLASSES_ROOT\DesktopBackground\shell\WSL\command]
ECHO @^="%EXE% -NoP -NoL -W Hidden -C \"Start-Process wt.exe -Args ^'-w new-tab -M -d \\\"%%V\\\" wsl.exe -d %DIST%^' -Verb RunAs\""
ECHO=
ECHO=
ECHO ^; [ Directory\Background ]
ECHO=
ECHO [HKEY_CLASSES_ROOT\Directory\Background\shell\WSL]
ECHO @^="Open WSL Here"
ECHO "Icon"^="C:\\Windows\\System32\\wsl.exe"
ECHO "NoWorkingDirectory"^=""
ECHO "Extended"^=-
ECHO=
ECHO [HKEY_CLASSES_ROOT\Directory\Background\shell\WSL\command]
ECHO @^="%EXE% -NoP -NoL -W Hidden -C \"Start-Process wt.exe -Args ^'-w new-tab -M -d \\\"%%V\\\" wsl.exe -d %DIST%^' -Verb RunAs\""
ECHO=
ECHO=
ECHO ^; [ Directory ]
ECHO=
ECHO [HKEY_CLASSES_ROOT\Directory\shell\WSL]
ECHO @^="Open WSL Here"
ECHO "Icon"^="C:\\Windows\\System32\\wsl.exe"
ECHO "NoWorkingDirectory"^=""
ECHO "Extended"^=-
ECHO=
ECHO [HKEY_CLASSES_ROOT\Directory\shell\WSL\command]
ECHO @^="%EXE% -NoP -NoL -W Hidden -C \"Start-Process wt.exe -Args ^'-w new-tab -M -d \\\"%%V\\\" wsl.exe -d %DIST%^' -Verb RunAs\""
ECHO=
ECHO=
ECHO ^; [ Drive ]
ECHO=
ECHO [HKEY_CLASSES_ROOT\Drive\shell\WSL]
ECHO @^="Open WSL Here"
ECHO "Icon"^="C:\\Windows\\System32\\wsl.exe"
ECHO "NoWorkingDirectory"^=""
ECHO "Extended"^=-
ECHO=
ECHO [HKEY_CLASSES_ROOT\Drive\shell\WSL\command]
ECHO @^="%EXE% -NoP -NoL -W Hidden -C \"Start-Process wt.exe -Args ^'-w new-tab -M -d \\\"%%V\\\" wsl.exe -d %DIST%^' -Verb RunAs\""
)>"%TMP%\wsl.reg"

:------------------------------------------------------------------------------------------------------------------------------------

REM ADD THE CREATED REG FILE TO WINDOWS REGISTRY AND THEN DELETE IT
IF EXIST "%TMP%\wsl.reg" (
    "%SystemRoot%\regedit.exe" /s "%TMP%\wsl.reg"
    DEL /Q "%TMP%\wsl.reg"
)

:------------------------------------------------------------------------------------------------------------------------------------

REM ECHO TO THE USER THAT THE SCRIPT HAS COMPLETED
CLS
ECHO The script has finished!
ECHO=
ECHO Give the context-menu a try by right clicking on a folder, file, drive, or desktop/folder background.
ECHO=
ECHO The menu will say "Open WSL Here"
ECHO=
SET /P "DUMMY=Press enter to exit: "
