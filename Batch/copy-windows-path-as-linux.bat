@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A

REM GitHub: https://github.com/slyfox1186/script-repo/blob/main/Batch/copy-windows-path-as-linux.bat
REM Updated: 05.07.24
REM Changes:
REM   - Removed a new line character at the end of the copied string that was most noticable when pasting.
REM   - Added separators above and below the context menu entries to help locate them faster.

REM Imporant Information
REM Once installed you must hold the "shift" key and right click on a file or folder to access the context menu item.
REM The reason for this is because the context menu is in "hidden mode" which is why the "shift" key is required.

CLS
ECHO Select an option: & ECHO=
ECHO [1] Add "Copy Linux Path" to the context menu
ECHO [2] Remove "Copy Linux Path" from the context menu & ECHO=

CHOICE /C 12 /N /M "Your choices are (1 or 2): " & CLS

IF "%ERRORLEVEL%" EQU "1" GOTO ADD_REG
IF "%ERRORLEVEL%" EQU "2" GOTO REMOVE_REG

ECHO Invalid option selected. & ECHO=
PAUSE
GOTO :EOF

:ADD_REG
REM [ * ] >> FILES ONLY
REG ADD "HKCR\*\shell\CopyLinuxPath" /ve /d "Copy Linux Path" /f
REG ADD "HKCR\*\shell\CopyLinuxPath" /v "Icon" /d "C:\Program Files\WSL\wsl.exe" /f
REG ADD "HKCR\*\shell\CopyLinuxPath" /v "Position" /d "Middle"  /f
REG ADD "HKCR\*\shell\CopyLinuxPath\command" /d "C:\Windows\System32\wsl.exe -- wslpath -u \"%%1\" | tr -d '\n' | clip.exe" /f
REG ADD "HKCR\*\shell\CopyLinuxPath" /v "SeparatorBefore" /t REG_SZ /d "" /f
REG ADD "HKCR\*\shell\CopyLinuxPath" /v "SeparatorAfter" /t REG_SZ /d "" /f
REM [ Directory ] >> DIRECTORIES/FOLDERS ONLY
REG ADD "HKCR\Directory\shell\CopyLinuxPath" /ve /d "Copy Linux Path" /f
REG ADD "HKCR\Directory\shell\CopyLinuxPath" /v "Icon" /d "C:\Program Files\WSL\wsl.exe" /f
REG ADD "HKCR\Directory\shell\CopyLinuxPath" /v "Position" /d "Middle" /f
REG ADD "HKCR\Directory\shell\CopyLinuxPath\command" /d "C:\Windows\System32\wsl.exe -- wslpath -u \"%%V\" | tr -d '\n' | clip.exe" /f
REG ADD "HKCR\Directory\shell\CopyLinuxPath" /v "SeparatorBefore" /t REG_SZ /d "" /f
REG ADD "HKCR\Directory\shell\CopyLinuxPath" /v "SeparatorAfter" /t REG_SZ /d "" /f
GOTO :EOF

:REMOVE_REG
REG DELETE "HKCR\*\shell\CopyLinuxPath" /f
REG DELETE "HKCR\Directory\shell\CopyLinuxPath" /f
REG DELETE "HKCR\Drive\shell\CopyLinuxPath" /f
