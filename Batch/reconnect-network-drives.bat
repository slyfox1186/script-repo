@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION
COLOR 0A
TITLE RECONNECT NETWORK DRIVES

:----------------------------------------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM OPEN THE CMD WINDOW IN THE SCRIPT'S DIRECTORY MAXIMIZED
PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:----------------------------------------------------------------------------------------------

REM LOOP THIS SCRIPT TWICE TO RECONNECT DRIVES
SET LOOP=0
:LOOP

:----------------------------------------------------------------------------------------------

REM WAIT FOR THE NETWORK TO GET READY
CLS & ECHO=
ECHO WAITING FOR NETWORK CONNECTION

:----------------------------------------------------------------------------------------------

SET LC=0 && GOTO :WAITFORNET2
:WAITFORNET1
TIMEOUT 1 /NOBREAK >NUL
:WAITFORNET2
ROUTE PRINT -4  | FINDSTR /C:" 0.0.0.0 " >NUL 2>NUL

IF NOT ERRORLEVEL 1 GOTO :NETREADY
SET /A LC=%LC%+1
IF %LC% LSS 30 GOTO :WAITFORNET1
GOTO :EOF

:----------------------------------------------------------------------------------------------

:NETREADY
REM ONCE THE NETWORK IS READY WE NEED TO WAIT A BIT BEFORE THE NEXT STEP OR IT MIGHT FAIL ON SOME PCS
CLS & ECHO=
ECHO NETWORK IS BACK ONLINE
TIMEOUT 2 /NOBREAK >NUL
ECHO=
ECHO WAITING 3 MORE SECONDS TO AVOID SCRIPT ERRORS
TIMEOUT 3 /NOBREAK >NUL

:----------------------------------------------------------------------------------------------

REM NOW WE CREATE A LIST OF ALL NETWORK DRIVES THAT ARE NOT 'OK'
CLS & ECHO=
ECHO SEARCHING FOR OFFLINE NETWORK DRIVES:
TIMEOUT 2 >NUL

:----------------------------------------------------------------------------------------------

SET "DRIVES_CNT=0"

:----------------------------------------------------------------------------------------------

NET USE | FINDSTR /B /V OK |FINDSTR "A:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=A:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "B:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=B:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "C:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=C:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "D:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=D:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "E:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=E:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "F:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=F:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "G:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=G:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "H:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=H:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "I:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=I:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "J:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=J:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "K:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=K:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "L:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=L:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "M:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=M:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "N:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=N:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "O:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=O:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "P:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=P:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "Q:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=Q:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "R:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=R:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "S:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=S:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "T:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=T:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "U:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=U:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "V:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=V:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "W:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=W:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "X:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=X:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "Y:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=Y:"
)
NET USE | FINDSTR /B /V OK |FINDSTR "Z:"
IF NOT ERRORLEVEL 1 (
    SET /A DRIVES_CNT+=1
    SET "OFFLINE_DRIVES[!DRIVES_CNT!]=Z:"
)

:----------------------------------------------------------------------------------------------

CLS & ECHO=
ECHO !DRIVES_CNT! OFFLINE NETWORK DRIVES FOUND
TIMEOUT 2 /NOBREAK >NUL

:----------------------------------------------------------------------------------------------

REM USES WINDOWS EXPLORER TO ACCESS EACH OFFLINE NETWORK SHARE
CLS & ECHO=
ECHO RECONNECTING ALL NETWORK SHARES:
FOR /L %%G in (1 1 !DRIVES_CNT!) DO ( 
ECHO !OFFLINE_DRIVES[%%G]!
START /MIN explorer "!OFFLINE_DRIVES[%%G]!"
)

:----------------------------------------------------------------------------------------------

CLS & ECHO=
ECHO EXPLORER NEEDS A 5 SECOND TIMEOUT && TIMEOUT 3 /NOBREAK >NUL

:----------------------------------------------------------------------------------------------

REM CLOSE THE EXPLORER WINDOWS WHICH WERE JUST OPENED
CLS & ECHO=
ECHO CLEANUP: CLOSING EXPLORER WINDOWS

:----------------------------------------------------------------------------------------------

FOR /L %%G in (1 1 !DRIVES_CNT!) DO (
    FOR /F "TOKENS=2 DELIMS=," %%I IN ('TASKLIST /FI "IMAGENAME EQ explorer.exe" /V /FO:CSV /NH ^| FINDSTR /R "!OFFLINE_DRIVES[%%G]!"') DO (
    ECHO !OFFLINE_DRIVES[%%G]! & TASKKILL /PID %%I
    )
)

:----------------------------------------------------------------------------------------------

CLS & ECHO=
ECHO EXPLORER WINDOWS HAVE BEEN CLOSED...
TIMEOUT 3 /NOBREAK >NUL

:----------------------------------------------------------------------------------------------

SET /A LOOP=%LOOP%+1
IF NOT "%LOOP%"=="2" GOTO LOOP

:----------------------------------------------------------------------------------------------

TASKKILL /F /IM explorer.exe
TIMEOUT 2 /NOBREAK >NUL
START explorer.exe
EXIT
