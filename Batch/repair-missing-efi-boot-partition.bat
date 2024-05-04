@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE CREATE AN EFI PARTITION

:----------------------------------------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM THIS SCRIPT WILL WALK YOU THROUGH CREATING A NEW EFI
REM PARTITION BY SHRINKING THE DISK SIZE (RECOMMENDED IS 300)
REM AND CREATING A NEW EFI BOOT PARTITION. AFTER CREATING
REM THE SCRIPT WILL RUN BCDBOOT.EXE TO TRANSFER THE WINDOWS
REM FILES NEEDED TO THE NEW EFI PARTITION.

REM IMPORTANT!
USE THIS AT YOUR OWN RISK AS I ASSUME NO LIABILITY BEYOND MY OWN EXPERIENCES.

:----------------------------------------------------------------------------------------------

REM OPEN CMD WINDOW MAXIMIZED
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:---------------------------------------------------------------------------------------------------------

REM DELETE ANY LEFTOVER FILES FROM PREVIOUS RUNS
IF EXIST "%TMP%\diskpart.txt" DEL /Q "%TMP%\diskpart.txt"

:---------------------------------------------------------------------------------------------------------

:START_OVER1
REM CREATE FILE WITH DISK NUMBERED IN A LIST
ECHO >"%TMP%\diskpart.txt" lis dis
CLS
REM ECHO THE NEWLY CREATED FILES CONTENTS INTO TERMINAL
"%WINDIR%\System32\diskpart.exe" /S "%TMP%\diskpart.txt"
ECHO=
SET /P DISK="Enter the disk number: "
CLS
IF "%DISK%" NEQ "%DISK%" GOTO START_OVER1

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

ECHO Please review your choices: & ECHO=
ECHO Partition    = %PTYPE%
ECHO Drive Label  = %LABEL%
ECHO Drive Letter = %LETTER% & ECHO=

:---------------------------------------------------------------------------------------------------------

:START_OVER2
REM ADD PARTITION INFO TO DISKPART SCRIPT
CLS
(
ECHO SELECT DISK %DISK%
ECHO LIST PARTITION
)>>"%TMP%\diskpart.txt"

REM RUN DISKPART AGAIN TO READ THE NEW FILE CONTENTS
"%WINDIR%\System32\diskpart.exe" /S "%TMP%\diskpart.txt"
ECHO=
SET /P "PART=Enter the partition number: "
IF "%PART%" NEQ "%PART%" GOTO START_OVER2
ECHO=
REM ENTER THE EFI PARTITION SIZE
SET /P "FSIZE=Enter the EFI partition size: "
IF "%FSIZE%" NEQ "%FSIZE%" GOTO START_OVER2
CLS

REM ADD THE FINAL INFO TO THE DISKPART SCRIPT TO SHRINK AND FORMAT THE NEW EFI PARTITION
(
ECHO SELECT PARTITION "%PART%"
ECHO SHRINK DESIRED="%FSIZE%"
ECHO CREATE PARTITION EFI SIZE="%FSIZE%"
ECHO FORMAT FS="FAT32" LABEL="%LABEL%" QUICK
ECHO ASSIGN LETTER="%LETTER%"
ECHO EXIT
)>>"%TMP%\diskpart.txt"

:---------------------------------------------------------------------------------------------------------

REM EXECUTE DISKPART SCRIPT TO MAKE THE CHANGES
"%WINDIR%\System32\diskpart.exe" /S "%TMP%\diskpart.txt"

:---------------------------------------------------------------------------------------------------------

REM RUN BCDBOOT TO ASSIGN THE WINDOWS FILES TO THE NEWLY CREATED EFI PARTITION
"C:\Windows\System32\bcdboot.exe" C:\Windows /s %LETTER%:

:---------------------------------------------------------------------------------------------------------

REM OPEN WITH NOTEPAD
REM START "" /MAX "%WINDIR%\notepad.exe" "%TMP%\diskpart.txt"
