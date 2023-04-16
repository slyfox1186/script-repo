@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE SHUTDOWN WINDOWS 11

:----------------------------------------------------------------------------------

REM By: SlyFox1186
REM Web: https://pastebin.com/u/slyfox1186

REM THIS SCRIPT WILL PROMPT THE USER WITH ALL OF THE
REM MOST COMMON SHUTDOWN COMMAND OPTIONS

REM FOR THE WINDOWS 10 VERSION OF THIS SCRIPT: https://pastebin.com/CR9GGMQp

:---------------------------------------------------------------------------------------------

SET SD="%windir%\System32\shutdown.exe"
REM THE SEC VARIABLE BELOW MUST BE GREATER THAN OR EQUAL TO 5
SET SEC=5

:---------------------------------------------------------------------------------------------

ECHO [1] RESTART ^(DEFAULT^)
ECHO [2] RESTART AND RE-REGISTER APPS
ECHO [3] RESTART WITH ADVANCED BOOT OPTIONS
ECHO [4] RESTART INTO UEFI/BIOS MENU & ECHO=
ECHO [5] SHUTDOWN ^(DEFAULT^)
ECHO [6] SHUTDOWN AND RE-REGISTER APPS & ECHO=
ECHO [7] LOG OUT CURRENT USER & ECHO=
ECHO [8] EXIT & ECHO=

CHOICE /C 12345678 /N & CLS

:---------------------------------------------------------------------------------------------

IF "%ERRORLEVEL%" EQU "8" GOTO :EOF
IF "%ERRORLEVEL%" EQU "7" SET "ECHO=LOG OUT CURRENT USER" & SET "FLAGS=/L" & GOTO SHOW_CHOICE
IF "%ERRORLEVEL%" EQU "6" SET "ECHO=SHUTDOWN AND RE-REGISTER APPS" & SET "FLAGS=/SG /T" & GOTO SHOW_CHOICE
IF "%ERRORLEVEL%" EQU "5" SET "ECHO=SHUTDOWN ^(DEFAULT^)" & SET "FLAGS=/S /T" & GOTO SHOW_CHOICE
IF "%ERRORLEVEL%" EQU "4" SET "ECHO=RESTART INTO UEFI/BIOS MENU" & SET "FLAGS=/R /FW /T" & GOTO SHOW_CHOICE
IF "%ERRORLEVEL%" EQU "3" SET "ECHO=RESTART WITH ADVANCED BOOT OPTIONS" & SET "FLAGS=/R /O /T" & GOTO SHOW_CHOICE
IF "%ERRORLEVEL%" EQU "2" SET "ECHO=RESTART AND RE-REGISTER APPS" & SET "FLAGS=/G /T" & GOTO SHOW_CHOICE
IF "%ERRORLEVEL%" EQU "1" SET "ECHO=RESTART ^(DEFAULT^)" & SET "FLAGS=/R /T"

:---------------------------------------------------------------------------------------------

REM DISPLAY YOUR CHOICE
:SHOW_CHOICE
ECHO You chose: %ECHO% & ECHO=
ECHO IF YOU WANT TO ABORT SIMPLY CLOSE THE SCRIPT. & ECHO=
PAUSE

:---------------------------------------------------------------------------------------------

REM RUN SHUTDOWN COMMANDS
IF "%FLAGS%" EQU "/L" (%SD% %FLAGS%) ELSE (%SD% %FLAGS% %SEC%)

:---------------------------------------------------------------------------------------------

REM SEARCH FOR PICKERHOST.EXE AND WAIT 1 SECOND BEFORE CONTINUING IF NOT FOUND
TASKLIST | FIND "PickerHost.exe" >NUL || TIMEOUT 1 /NOBREAK >NUL
TASKKILL /F /IM "PickerHost.exe" /T >NUL 2>&1
