@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A

CLS

ECHO Select an option:
ECHO [1] Add "Copy Linux Path" to context menu
ECHO [2] Remove "Copy Linux Path" from context menu
ECHO=
SET /P option=Enter your choice (1 or 2) and press Enter: 

IF "%option%"=="1" GOTO addReg
IF "%option%"=="2" GOTO removeReg
ECHO Invalid option selected.
GOTO end

:addReg
(
ECHO Windows Registry Editor Version 5.00
ECHO=
ECHO ; Adds context menu entry for directories
ECHO=
ECHO [HKEY_CLASSES_ROOT\Directory\shell\CopyLinuxPath]
ECHO @="Copy Linux Path"
ECHO "Extended"=""
ECHO "Icon"="C:\\Program Files\\WSL\\wsl.exe"
ECHO=
ECHO [HKEY_CLASSES_ROOT\Directory\shell\CopyLinuxPath\command]
ECHO @="C:\\Windows\\System32\\cmd.exe /d /c \"wsl.exe wslpath -u '%%V' ^| C:\\Windows\\System32\\clip.exe\""
ECHO=
ECHO ; Adds context menu entry for files
ECHO [HKEY_CLASSES_ROOT\^*\shell\CopyLinuxPath]
ECHO @="Copy Linux Path"
ECHO "Extended"=""
ECHO "Icon"="C:\\Program Files\\WSL\\wsl.exe"
ECHO=
ECHO [HKEY_CLASSES_ROOT\^*\shell\CopyLinuxPath\command]
ECHO @="C:\\Windows\\System32\\cmd.exe /d /c \"wsl.exe wslpath -u '%%1' ^| C:\\Windows\\System32\\clip.exe\""
)> AddCopyLinuxPath.reg
ECHO Applying Add script...
regedit.exe /s "AddCopyLinuxPath.reg"
GOTO :EOF

:removeReg
(ECHO Windows Registry Editor Version 5.00
ECHO=
ECHO [-HKEY_CLASSES_ROOT\^*\shell\CopyLinuxPath]
ECHO [-HKEY_CLASSES_ROOT\Directory\shell\CopyLinuxPath]
)> RemoveCopyLinuxPath.reg
ECHO Applying Remove script...
regedit.exe /s "RemoveCopyLinuxPath.reg"
