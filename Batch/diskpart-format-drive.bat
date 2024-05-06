@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE DISKPART FORMAT DRIVE

:----------------------------------------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM OPEN CMD WINDOW MAXIMIZED
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:---------------------------------------------------------------------------------------------------------

SET DP="%windir%\System32\diskpart.exe"

:---------------------------------------------------------------------------------------------------------

:START_OVER
REM CREATE FILE WITH DISK NUMBERED IN A LIST
ECHO >"%TMP%\diskpart.txt" lis dis
CLS
REM ECHO THE NEWLY CREATED FILES CONTENTS INTO TERMINAL
%DP% /S "%TMP%\diskpart.txt"
REM PROMPT THE USER TO INPUT THE CORRECT DISC NUMBER
ECHO=
SET /P DISK="Enter the disk number: "
CLS
IF "%DISK%" NEQ "%DISK%" GOTO START_OVER

:---------------------------------------------------------------------------------------------------------

REM CREATES A TEMPORARY FILE THAT DISKPART CAN READ
SET /P "PTYPE=Please enter either GPT or MBR: "
ECHO=
SET /P "FSTYPE=Enter FS type (example: FAT32, NTFS, EXFAT): "
ECHO=
SET /P "LABEL=Enter label: "
ECHO=
SET /P "LETTER=Enter Letter: "
CLS

:---------------------------------------------------------------------------------------------------------

ECHO Please review your choices before continuing: & ECHO=
ECHO Partition    = %PTYPE%
ECHO File System  = %FSTYPE%
ECHO Drive Label  = %LABEL%
ECHO Drive Letter = %LETTER% & ECHO=
SET /P "DUMMY=Press enter to make changes to the drive as listed above: "
CLS

:---------------------------------------------------------------------------------------------------------

(
ECHO SELECT DISK %DISK%
ECHO CLEAN
ECHO CONVERT %PTYPE%
ECHO CREATE PARTITION PRIMARY
ECHO FORMAT FS="%FSTYPE%" LABEL="%LABEL%" QUICK
ECHO ASSIGN LETTER=%LETTER%
ECHO EXIT
)>"%TMP%\diskpart.txt"

:---------------------------------------------------------------------------------------------------------

REM EXECUTE DISKPART TO MAKE THE CHANGES TO THE DISK
%DP% /S "%TMP%\diskpart.txt"

:---------------------------------------------------------------------------------------------------------

REM OPEN WITH NOTEPAD (UNCOMMENT THE BELOW COMMAND TO OPEN THE DISKPART FILE)
REM START "" /MAX "%windir%\notepad.exe" "%TMP%\diskpart.txt"
