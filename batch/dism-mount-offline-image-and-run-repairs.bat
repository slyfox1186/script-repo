@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE REPAIR WINDOWS USING AN OFFLINE IMAGE

:------------------------------------------------------------------------------------------------------------------------

REM Created by: SlyFox1186
REM Pastebin: https://pastebin.com/u/slyfox1186

REM THIS SCRIPT WILL HELP YOU REPAIR WINDOWS WHILE
REM ALSO LIMITING THE INTERNET'S ACCESS BY USING AN
REM OFFLINE MOUNTED IMAGE OF WINDOWS.

REM BEFORE RUNNING THIS SCRIPT LOCATE AND PLACE EITHER
REM "install.wim” or “install.esd" IN THE SAME FOLDER AS THIS SCRIPT.
REM THE FILES CAN BE FOUND INSIDE A WINDOWS ".ISO" FILE.

REM IT IS HIGHLY RECOMMENDED THAT YOU USE THE LATEST ISO FILE AVAILABLE
REM WHEN SOURCING THE ESD OR WIM FILES MENTIONED ABOVE.

REM WIN 10 ISO DOWNLOAD: https://www.microsoft.com/en-us/software-download/windows10
REM WIN 11 ISO DOWNLOAD: https://www.microsoft.com/software-download/windows11

:------------------------------------------------------------------------------------------------------------------------

PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:------------------------------------------------------------------------------------------------------------------------

REM DEFINE VARIABLES
SET ROOT=%SYSTEMDRIVE%\WinMount
SET MDIR=%ROOT%\Windows
SET ESD=%CD%\install.esd
SET WIM=%CD%\install.wim

:----------------------------------------------------------------------------------

REM CREATE DIRECTORY IF NOT EXIST
IF NOT EXIST "%MDIR%" IF EXIST "%ROOT%" RD /S /Q "%ROOT%"

:----------------------------------------------------------------------------------

REM KILL ANY RUNNING INSTANCES OF DISM OR TIWORKER TO AVOID ERRORS
TASKLIST | FINDSTR "Dism.exe TiWorker.exe" >NUL && TASKKILL /F /IM "Dism.exe" /IM "TiWorker.exe" /T >NUL 2>&1

:------------------------------------------------------------------------------------------------

REM CHECK IF WIM EXISTS
IF EXIST "%ESD%" (SET "FTYPE=%ESD%" & CALL :WIM_NOT_EXIST & GOTO :EOF) ELSE (CALL :CHOOSE_TYPE & GOTO :EOF)

:WIM_NOT_EXIST
ECHO EITHER CONVERT THE WIM TO ESD OR SKIP TO MOUNT/UNMOUNT/REPAIR: & ECHO=
ECHO [1] Convert: install.esd ^>^> install.wim
ECHO [2] Skip to mount/unmount/repair
ECHO [3] Exit & ECHO=

CHOICE /C 123 /N & CLS

IF ERRORLEVEL 3 EXIT
IF ERRORLEVEL 2 GOTO CHOOSE_TYPE
IF ERRORLEVEL 1 (SET "FTYPE=%ESD%" & SET "FLAG_01=%WIM%" & CALL :CONVERT_FORMAT & GOTO :EOF)
EXIT

:------------------------------------------------------------------------------------------------
:CONVERT_FORMAT
:------------------------------------------------------------------------------------------------

REM CONVERT ESD TO WIM FILE
:RETRY1
CLS
SET INDEX=
DISM /Get-ImageInfo /ImageFile:"%ESD%"
ECHO=
SET /P "INDEX=Please select an index number from the list above that matches your Windows version: "
IF "%INDEX%" LSS "1" (
	ECHO Please enter an acceptable value that matches your Windows version...
	ECHO=
	PAUSE
	GOTO RETRY1
)
CLS
ECHO Creating: "%FLAG_01%"
DISM /Export-Image /SourceImageFile:"%ESD%" /SourceIndex:%INDEX% /DestinationImageFile:"%FLAG_01%" /Compress:Max /CheckIntegrity
ECHO Created: "%FLAG_01%"

:------------------------------------------------------------------------------------------------
:CHOOSE_TYPE
:------------------------------------------------------------------------------------------------

REM CHOOSE WHICH FILE TYPE TO USE WHEN MOUNTING THE OFFLINE IMAGE
ECHO CHOOSE WHICH FILE TYPE TO USE WHEN MOUNTING THE OFFLINE IMAGE: & ECHO=
ECHO [1] ESD
ECHO [2] WIM
ECHO [3] EXIT & ECHO=

CHOICE /C 123 /N & CLS

IF ERRORLEVEL 3 EXIT
IF ERRORLEVEL 2 IF EXIST "%WIM%" (
        SET "INDEX=1"
        SET "FTYPE=%WIM%"
        CALL :MOUNT_OFFLINE_IMAGE %INDEX% %FTYPE%
        GOTO :EOF
      ) ELSE (
        ECHO Essential File: install.wim is missing!
        ECHO=
        ECHO Press [Enter] to fix the issue or close the window to exit.
        ECHO=
        PAUSE
        SET "FTYPE=%ESD%"
        SET "FLAG_01=%WIM%"
        CALL :CONVERT_FORMAT
        GOTO :EOF
)
IF ERRORLEVEL 1 (
    SET "INDEX=6"
    SET "FTYPE=%ESD%"
    CALL :MOUNT_OFFLINE_IMAGE %INDEX% %FTYPE%
    GOTO :EOF
)

:------------------------------------------------------------------------------------------------
:MOUNT_OFFLINE_IMAGE
:------------------------------------------------------------------------------------------------

REM CHOOSE WHETHER TO MOUNT, UNMOUNT, OR SKIP TO REPAIRS
:RETRY3
CLS
ECHO Choose next step: & ECHO=
ECHO [1] Mount Image
ECHO [2] Unmount Image
ECHO [3] Run offline repairs using the mounted image
ECHO [4] Exit & ECHO=

CHOICE /C 1234 /N & CLS

IF ERRORLEVEL 4 EXIT
IF ERRORLEVEL 3 GOTO RUN_REPAIRS
IF ERRORLEVEL 2 (
	DISM /Unmount-Image /MountDir:"%ROOT%" /Discard
	RD /S /Q "%ROOT%" >NUL
	GOTO :EOF
    )
)
IF ERRORLEVEL 1 (
    IF NOT EXIST "%ROOT%" MD "%ROOT%"
	DISM /Mount-Image /ImageFile:"%FTYPE%" /Index:"%INDEX%" /MountDir:"%ROOT%
    ECHO=
    TIMEOUT 2 >NUL
	GOTO :EOF
)

:------------------------------------------------------------------------------------------------
:RUN_REPAIRS
:------------------------------------------------------------------------------------------------

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
    ECHO REPAIRS ARE COMPLETE! & ECHO=
    PAUSE
	GOTO :EOF
  ) ELSE (
	ECHO YOU MUST MOUNT THE IMAGE BEFORE RUNNING REPAIRS... & ECHO=
	PAUSE
	GOTO RETRY3
)
