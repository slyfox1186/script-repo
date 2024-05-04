@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
COLOR 0A
TITLE Repair Windows Using an Offline Image

:------------------------------------------------------------------------------------------------------------------------

REM Created by: SlyFox1186
REM GitHub: https://github.com/slyfox1186/script-repo/blob/main/Batch/dism-fix-windows-errors-using-an-offline-image.bat

REM This script will help you repair Windows while limiting internet access by using an offline mounted image of Windows.

REM Before running this script, please make sure you have either "install.wim" or "install.esd" file in the same folder as this script.
REM These files can be found inside a Windows ISO file. It is highly recommended that you use the latest ISO file available.

:------------------------------------------------------------------------------------------------------------------------

PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:------------------------------------------------------------------------------------------------------------------------

REM Define variables
SET "ROOT=%SYSTEMDRIVE%\WinMount"
SET "MDIR=%ROOT%\Windows"
SET "ESD=install.esd"
SET "WIM=install.wim"

:------------------------------------------------------------------------------------------------------------------------

REM Kill any running instances of DISM or TiWorker to avoid errors
TASKLIST | FINDSTR "Dism.exe TiWorker.exe" >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
    TASKKILL /F /IM "Dism.exe" /IM "TiWorker.exe" /T >NUL 2>&1
)

:------------------------------------------------------------------------------------------------------------------------

REM Remove the leftover Windows temp directory
IF NOT EXIST "%MDIR%" IF EXIST "%ROOT%" RD /S /Q "%ROOT%"

:------------------------------------------------------------------------------------------------------------------------

REM Check if WIM or ESD file exists
IF NOT EXIST "%WIM%" (
    IF NOT EXIST "%ESD%" (
        CLS
        ECHO No Windows image file ^(install.wim or install.esd^) found in the current folder.
        ECHO Please download the latest Windows ISO file and extract the WIM or ESD file from it into this folder.
        ECHO Once you have the required file, run this script again.
        PAUSE
        EXIT /B
    )
)

:------------------------------------------------------------------------------------------------------------------------

REM Prompt user to select Windows version
CLS
ECHO Before proceeding, you need to select the version of Windows that matches your current installation.
ECHO This information can be found in the Windows image file.
ECHO=
ECHO Press any key to display the available Windows versions...
PAUSE >NUL

CLS
IF EXIST "%WIM%" (
    DISM /Get-WimInfo /WimFile:"%WIM%"
) ELSE (
    DISM /Get-WimInfo /WimFile:"%ESD%"
)
ECHO=
SET /P "USER_CHOICE=Please enter the index number that matches your Windows version: "

:------------------------------------------------------------------------------------------------------------------------

REM Repair Windows
:REPAIR_START
CLS
ECHO The Windows image file is now ready for the repair process.
ECHO You will be guided through the steps to mount the image, run the repairs, and then unmount the image.
ECHO=
ECHO [1] Mount the Windows image
ECHO [2] Run Windows repairs using the mounted image
ECHO [3] Unmount the Windows image (do this after finishing the repairs)
ECHO [4] Exit
ECHO=

CHOICE /C 1234 /N /M "Enter your choice: "

IF ERRORLEVEL 4 EXIT /B
IF ERRORLEVEL 3 (
    DISM /Unmount-Image /MountDir:"%ROOT%" /Discard
    RD /S /Q "%ROOT%" >NUL 2>&1
    GOTO REPAIR_START
)
IF ERRORLEVEL 2 CALL :RUN_REPAIRS
IF ERRORLEVEL 1 (
    IF NOT EXIST "%ROOT%" MD "%ROOT%"
    IF EXIST "%WIM%" (
        DISM /Mount-Image /ImageFile:"%WIM%" /Index:"%USER_CHOICE%" /MountDir:"%ROOT%" /CheckIntegrity
    ) ELSE (
        DISM /Mount-Image /ImageFile:"%ESD%" /Index:"%USER_CHOICE%" /MountDir:"%ROOT%" /CheckIntegrity
    )
)
GOTO REPAIR_START

:------------------------------------------------------------------------------------------------------------------------
:RUN_REPAIRS
:------------------------------------------------------------------------------------------------------------------------

CLS
IF EXIST "%MDIR%" (
    ECHO Running Windows repairs using the mounted offline image...
    ECHO This process may take some time. Please wait...
    ECHO=
    DISM /Online /Cleanup-Image /RestoreHealth /StartComponentCleanup
    ECHO=
    DISM /Online /Cleanup-Image /RestoreHealth /Source:"%MDIR%" /LimitAccess
    ECHO=
    SFC /SCANNOW
    ECHO=
    SFC /SCANNOW
    ECHO=
    ECHO Repairs completed!
    ECHO=
    PAUSE
) ELSE (
    ECHO The Windows image is not mounted.
    ECHO Please mount the image using Option 1 before running repairs.
    ECHO=
    PAUSE
)
GOTO :EOF

:------------------------------------------------------------------------------------------------------------------------

REM Pause before exiting
ECHO=
ECHO Press any key to exit...
PAUSE >NUL
