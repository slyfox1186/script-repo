@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
COLOR 0A
TITLE REPAIR WINDOWS USING AN OFFLINE IMAGE

:------------------------------------------------------------------------------------------------------------------------

REM Created by: SlyFox1186
REM Pastebin: https://pastebin.com/u/slyfox1186

REM THIS SCRIPT WILL HELP YOU REPAIR WINDOWS WHILE ALSO LIMITING
REM THE INTERNET'S ACCESS BY USING AN OFFLINE MOUNTED IMAGE OF WINDOWS.

REM BEFORE RUNNING THIS SCRIPT LOCATE AND PLACE EITHER
REM "install.wim" or "install.esd" IN THE SAME FOLDER AS THIS SCRIPT.
REM THE FILES CAN BE FOUND INSIDE A WINDOWS ".ISO" FILE.

REM IT IS HIGHLY RECOMMENDED THAT YOU USE THE LATEST ISO FILE AVAILABLE
REM WHEN SOURCING THE ESD OR WIM FILES MENTIONED ABOVE.

:------------------------------------------------------------------------------------------------------------------------

PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:------------------------------------------------------------------------------------------------------------------------

REM DEFINE VARIABLES
SET ROOT=%SYSTEMDRIVE%\WinMount
SET MDIR=!ROOT!\Windows
SET ESD=install.esd
SET WIM=install.wim

:------------------------------------------------------------------------------------------------------------------------

REM KILL ANY RUNNING INSTANCES OF DISM OR TIWORKER TO AVOID ERRORS
TASKLIST | FINDSTR "Dism.exe TiWorker.exe" >NUL && TASKKILL /F /IM "Dism.exe" /IM "TiWorker.exe" /T >NUL 2>&1

:------------------------------------------------------------------------------------------------------------------------

REM CREATE DIRECTORY IF NOT EXIST
IF NOT EXIST "%MDIR%" IF EXIST "!ROOT!" RD /S /Q "!ROOT!"

:------------------------------------------------------------------------------------------------------------------------

REM CHOOSE TO CONVERT IMAGE, OR SKIP STRAIGHT TO MOUNT/UNMOUNT/REPAIR
CLS
ECHO YOU MUST FIRST EXPORT THE WINDOWS INDEX THAT MATCHES THE VERSION OF WINDOWS WE ARE TRYING TO REPAIR ^(USUALLY THIS PC^). & ECHO=
ECHO IF YOU HAVE DONE THAT ALREADY YOU MAY SKIP AHEAD BY CHOOSING OPTION "2". & ECHO=
ECHO [1] EXPORT IMAGE INDEX
ECHO [2] SKIP AHEAD AND RUN THE "MOUNT/UNMOUNT/REPAIR" OPTIONS.
ECHO [3] EXIT & ECHO=

CHOICE /C 123 /N & CLS

IF ERRORLEVEL 3 EXIT
IF ERRORLEVEL 2 GOTO REPAIR_WINDOWS
IF ERRORLEVEL 1 GOTO GET_IMAGE_INDEX
EXIT

:------------------------------------------------------------------------------------------------------------------------
:GET_IMAGE_INDEX
:------------------------------------------------------------------------------------------------------------------------

REM YOU MUST INSPECT THE SOURCE FILES AND CHOOSE WHAT INDEX TO USE IN THE REPAIR PROCESS
CLS
ECHO YOU MUST INSPECT THE SOURCE FILES AND CHOOSE WHAT INDEX TO USE IN THE REPAIR PROCESS.
ECHO YOU NEED TO CHOOSE THE INDEX NUMBER THAT MATCHES THE VERSION OF WINDOWS THAT YOU ARE CURRENTLY USING. & ECHO=

REM DISCOVER WHAT SOURCE FILES ARE CURRENTLY AVAILABLE FOR USE
IF EXIST %WIM% (
    IF EXIST %ESD% (
        GOTO CHOICE_BOTH
    )
)
IF EXIST %WIM% (
    IF NOT EXIST %ESD% (
        GOTO CHOICE_WIM
    )
)
IF NOT EXIST %WIM% (
    IF EXIST %ESD% (
        GOTO CHOICE_ESD
    )
)

:------------------------------------------------------------------------------------------------------------------------
:CHOICE_BOTH
:------------------------------------------------------------------------------------------------------------------------

CLS
ECHO WIM AND ESD FILES WERE LOCATED. PLEASE CHOOSE THE ONE YOU WISH TO USE. & ECHO=
ECHO [1] WIM
ECHO [2] ESD
ECHO [3] EXIT & ECHO=

CHOICE /C 123 /N & CLS

IF ERRORLEVEL 3 EXIT
IF ERRORLEVEL 2 (
    SET INPUT=%ESD%
    SET OUTPUT=%WIM%
    GOTO SELECT_INDEX
)
IF ERRORLEVEL 1 (
    SET INPUT=%WIM%
    SET OUTPUT=%ESD%
    GOTO SELECT_INDEX
)

:------------------------------------------------------------------------------------------------------------------------
:CHOICE_WIM
:------------------------------------------------------------------------------------------------------------------------

CLS
ECHO ONLY THE WIM FILE WAS LOCATED. SO WE WILL USE THAT TO REPAIR WINDOWS. & ECHO=
SET INPUT=%WIM%
SET OUTPUT=%ESD%
GOTO SELECT_INDEX

:------------------------------------------------------------------------------------------------------------------------
:CHOICE_ESD
:------------------------------------------------------------------------------------------------------------------------

CLS
ECHO ONLY THE ESD FILE WAS LOCATED. SO WE WILL USE THAT TO REPAIR WINDOWS. & ECHO=
SET INPUT=%ESD%
SET OUTPUT=%WIM%
GOTO SELECT_INDEX

:------------------------------------------------------------------------------------------------------------------------
:SELECT_INDEX
:------------------------------------------------------------------------------------------------------------------------

CLS
DISM /Get-WimInfo /WimFile:"!INPUT!"
ECHO=
SET /P "USER_CHOICE=Please enter the index number that matches the exact version of Windows you are using: "
GOTO CONVERT_IMG

:------------------------------------------------------------------------------------------------------------------------
:CONVERT_IMG
:------------------------------------------------------------------------------------------------------------------------

CLS & ECHO Converting: !INPUT!:Index:!USER_CHOICE! ^>^> !OUTPUT!
DISM /Export-Image /SourceImageFile:"!INPUT!" /SourceIndex:"!USER_CHOICE!" /DestinationImageFile:"!OUTPUT!" /Compress:recovery /CheckIntegrity
GOTO REPAIR_WINDOWS

:------------------------------------------------------------------------------------------------------------------------
:REPAIR_WINDOWS
:------------------------------------------------------------------------------------------------------------------------

REM CHOOSE WHETHER TO MOUNT, UNMOUNT, OR SKIP TO REPAIRS
:REPAIR_START
CLS
ECHO The index image must be ready to run the repairs at this stage. If you have not done that restart the script and fix that.
ECHO It is recommended you go in order by, mounting, running the offline repairs, the unmounting the leftover files. & ECHO=
ECHO [1] Mount the offline image files
ECHO [2] Run Windows repairs using the offline mounted files
ECHO [3] Unmount the offline files ^(Do this after you are finished running the repairs^)
ECHO [4] Exit & ECHO=

CHOICE /C 1234 /N & CLS

IF ERRORLEVEL 4 EXIT
IF ERRORLEVEL 3 (
    DISM /Unmount-Image /MountDir:"!ROOT!" /Discard
    RD /S /Q "!ROOT!" >NUL
    GOTO REPAIR_START
)
IF ERRORLEVEL 2 (
    CALL :RUN_REPAIRS
    GOTO REPAIR_START
)
IF ERRORLEVEL 1 (
    IF NOT EXIST "!ROOT!" MD "!ROOT!"
    DISM /Mount-Image /ImageFile:"%WIM%" /Index:"1" /MountDir:"!ROOT!" /CheckIntegrity
    GOTO REPAIR_START
)

:------------------------------------------------------------------------------------------------------------------------
:RUN_REPAIRS
:------------------------------------------------------------------------------------------------------------------------

REM REPAIR WINDOWS USING THE MOUNTED OFFLINE IMAGE

IF EXIST "%MDIR%" (
    DISM /Online /Cleanup-Image /RestoreHealth /StartComponentCleanup
    ECHO=
    DISM /Online /Cleanup-Image /RestoreHealth /Source:"%MDIR%" /LimitAccess
    ECHO=
    SFC /SCANNOW
    ECHO=
    SFC /SCANNOW
    ECHO=
    ECHO REPAIRS COMPLETED!
    ECHO=
    PAUSE
    GOTO :EOF
  ) ELSE (
    ECHO YOU MUST MOUNT THE IMAGE BEFORE RUNNING REPAIRS... & ECHO=
    PAUSE
    GOTO REPAIR_START
)
