@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A

CLS

ECHO Select an option: & ECHO=
ECHO [1] Add "Copy Linux Path" to the context menu
ECHO [2] Remove "Copy Linux Path" from the context menu & ECHO=

CHOICE /C 12 /N /M "Your choices are (1 or 2): " & CLS

IF "%ERRORLEVEL%" EQU "1" GOTO addReg
IF "%ERRORLEVEL%" EQU "2" GOTO removeReg

ECHO Invalid option selected. & ECHO=
PAUSE
GOTO :EOF

:addReg
REG ADD "HKCR\Directory\shell\CopyLinuxPath" /ve /d "Copy Linux Path" /f
REG ADD "HKCR\Directory\shell\CopyLinuxPath" /v "Extended" /d "" /f
REG ADD "HKCR\Directory\shell\CopyLinuxPath" /v "Icon" /d "C:\Program Files\WSL\wsl.exe" /f
REG ADD "HKCR\Directory\shell\CopyLinuxPath\command" /d "%windir%\System32\cmd.exe /d /c \"wsl.exe wslpath -u '%%V' ^| %windir%\System32\clip.exe\"" /f
REG ADD "HKCR\*\shell\CopyLinuxPath" /ve /d "Copy Linux Path" /f
REG ADD "HKCR\*\shell\CopyLinuxPath" /v "Extended" /d "" /f
REG ADD "HKCR\*\shell\CopyLinuxPath" /v "Icon" /d "C:\Program Files\WSL\wsl.exe" /f
REG ADD "HKCR\*\shell\CopyLinuxPath\command" /d "%windir%\System32\cmd.exe /d /c \"wsl.exe wslpath -u '%%1' ^| %windir%\System32\clip.exe\"" /f
GOTO :EOF

:removeReg
REG DELETE "HKCR\*\shell\CopyLinuxPath" /f
REG DELETE "HKCR\Directory\shell\CopyLinuxPath" /f
