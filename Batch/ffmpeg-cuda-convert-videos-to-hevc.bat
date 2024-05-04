@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
COLOR 0A

:-----------------------------------------------------------------------------

REM BY: SlyFox1186
REM PASTEBIN: https://pastebin.com/u/slyfox1186
REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM NEED A PROGRAMMER? YOU FOUND A GOOD ONE! CONTACT ME ON GITHUB!

:-----------------------------------------------------------------------------

REM PURPOSE

REM THIS SCRIPT WILL RECURSIVELY SEARCH FOR MKV OR MP4 VIDEOS IN THE CURRENT SCRIPTS DIRECTORY
REM AND CREATE A CONVERTED ROUGHLY HALF-SIZE VERSION OF THE ORIGINAL IN X265 10-BIT (HEVC).

REM ADDITIONAL NOTES

REM THE ORIGINAL VIDEO SHOULD NOT BE OVERWRITTEN. SO FAR, THIS IS AS CLOSE TO INDISTINGUISHABLE
REM QUALITY AS I HAVE BEEN ABLE TO GET USING AN AUTOMATED LOOP SCRIPT SO ENJOY MY EFFORTS!

REM CONVERT METHOD

REM THE SCRIPT UTILIZES GEFORCE VIDEO CARDS THAT ARE VERSION TURING AND HIGHER
REM BY USING HARDWARE ACCELERATION (CUDA) TO SPEED UP THE ENCODING PROCESS.

REM INSTRUCTIONS

REM YOU MUST POINT THE FF AND FP VARIABLES BELOW TO THE FULL PATH OF YOUR OWN EXE FILES
REM IF THEY ARE NOT ALREADY INSIDE YOUR WINDOWS ENVIRONMENT AND IF SO THEN
REM REPLACE %FF% BELOW WITH ffmpeg.exe AND %FP% WITH ffprobe.exe

REM IMPORTANT

REM I HIGHLY RECOMMEND YOU USE THIS GITHUB REPO TO COMPILE ALL OF THE EXE FILES NEEDED
REM FOR THIS SCRIPT TO RUN. https://github.com/m-ab-s/media-autobuild_suite

REM I ASSUME NO RISK AND PROVIDE THIS AS-IS WHICH MEANS YOU
REM SHOULD RUN TESTS BEFORE YOU USE THIS ON ANY DATA YOU VALUE.

REM FINAL COMMENT

REM GOOD LUCK AND GIVE ME A THUMBS UP IF YOU LIKE THIS! IT KEEPS
REM ME MOTIVATED TO POST MY FAVORITE PERSONAL SCRIPTS ON HERE!

:-----------------------------------------------------------------------------

REM CHANGE THE WORKING DIRECTORY TO THE SCRIPTS, REOPEN CMD MAXIMIZED, AND SET THE WINDOW TITLE
PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF
FOR /F "TOKENS=*" %%A IN ("%CD%") DO SET "WIN_TITLE=%%A"
TITLE %WIN_TITLE%

:-----------------------------------------------------------------------------

REM SET MANUAL VARIABLES HERE
SET FF=G:\MAB\local64\bin-video\ffmpeg.exe
SET FP=G:\MAB\local64\bin-video\ffprobe.exe

:-----------------------------------------------------------------------------

REM DELETE ANY LEFTOVER FILES FROM PREVIOUS RUNS
FOR /R %%G IN (*.mkv, *.mp4) DO (
    SET FNAME=%%~dpnG
    SET FNAME_END=!FNAME:~-7!
    IF "!FNAME_END!%%~xG"==" (x265)%%~xG" (
        ECHO MAKE A CHOICE: & ECHO=
        ECHO [1] Delete
        ECHO [2] Keep
        ECHO [3] Exit & ECHO=
        CHOICE /C 123 /N & CLS
            IF ERRORLEVEL 3 GOTO :EOF
            IF ERRORLEVEL 2 GOTO NEXT
            IF ERRORLEVEL 1 (
                DEL /Q "!FNAME!%%~xG"
                ECHO File Deleted: "!FNAME!%%~xG"
            )
      ) ELSE (
        :NEXT
        REM STORES THE CURRENT VIDEO WIDTH, ASPECT RATIO, PROFILE, BIT RATE, AND TOTAL DURATION IN VARIABLES FOR USE LATER IN THE FFMPEG COMMAND LINE.
        FOR /F "TOKENS=*" %%A IN ('%FP% -hide_banner -v error -select_streams v:0 -show_entries stream^=width -of csv^=s^=x:p^=0 -pretty "%%G"') DO SET VW=%%A
        FOR /F "TOKENS=*" %%A IN ('%FP% -hide_banner -v error -select_streams v:0 -show_entries stream^=display_aspect_ratio -of default^=nk^=1:nw^=1 -pretty "%%G"') DO SET AR=%%A
        FOR /F "TOKENS=1" %%A IN ('%FP% -hide_banner -v error -select_streams v:0 -show_entries stream^=profile -of default^=nk^=1:nw^=1 -pretty "%%G"') DO SET PROFILE=%%A
        FOR /F "TOKENS=1" %%A IN ('%FP% -hide_banner -v error -show_entries format^=bit_rate -of default^=nk^=1:nw^=1 -pretty "%%G"') DO SET MR=%%A
        FOR /F "TOKENS=1" %%A IN ('%FP% -v error -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "%%G"') DO SET LENGTH=%%A

        REM REMOVES ALL TRAILING DECIMALS FROM THE LENGTH VARIABLE TO GET THE TOTAL MINUTES
        REM I HAD TO MAKE TWO VARS IN CASE THE VIDEO IS OVER A CERTAIN LENGTH LONG SO ONLY ONE
        REM OF THESE WILL BE ACCURATE AND YOU SHOULD BE ABLE TO TELL THE DIFFERENCE WHEN EXECUTING
        REM THE SCRIPT... UNFORTUNATE LIMIT OF BATCH CODE
        SET "LN1=!LENGTH:~0,4!"
        SET "LN2=!LENGTH:~0,5!"
        SET /A "LN3=LN1/60"
        SET /A "LN4=LN2/60"

        REM GETS THE INPUT VIDEO'S MAX DATARATE AND APPLIES LOGIC TO DETERMINE BITRATE, BUFSIZE, AND MAXRATE VARIABLES
        SET "MR1=!MR:~0,4!"
        SET /A "BR1=MR/2"
        SET /A "BR2=BR1*1000"
        SET /A "BR=BR2+1000"
        SET /A "MR=MR1*1000"
        SET /A "BF=BR*2"

        REM TEST IF THE DECIMAL IS 0.51 OR HIGHER THEN ADD NUMBERS TO THE VARAIABLE MAXRATE BASED ON LOGIC.
        REM IF THE MAXRATE DECIMAL PLACE IS 0.51 OR HIGHER ADD 3 TO MAXRATE ELSE ADD 2. AGAIN A LIMIT OF
        REM BATCH CODE OTHERWISE I WOULD WRITE THIS DIFFERENTLY... HOWEVER, IT SEEMS TO WORK WELL.
        SET _MR=!MR:~2,4!
        IF "!_MR!" GEQ "51" (SET /A "MR=MR+2") ELSE (SET /A "MR=MR+1")

        REM ECHO THE STORED VARIABLES THAT CONTAIN THE VIDEO'S STATS
        ECHO= & ECHO=
        ECHO ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
        ECHO=
        ECHO FILE NAME:    %%G
        ECHO=
        ECHO LENGTH:       !LN3! MINUTES ^(SHORT VIDEOS^)
        ECHO LENGTH:       !LN4! MINUTES ^(LONG VIDEOS^)
        ECHO=
        ECHO VIDEO WIDTH:  !VW!
        ECHO=
        ECHO ASPECT RATIO: !AR!
        ECHO=
        ECHO BITRATE:      !BR!k
        ECHO BUFSIZE:      !BF!k
        ECHO MAXRATE:      !MR!k
        ECHO=
        ECHO PROFILE:      !PROFILE!
        ECHO=
        ECHO ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

        REM RUN FFMPEG
        %FF% ^
        -y ^
        -threads 0 ^
        -fflags "+igndts +nofillin" ^
        -hide_banner ^
        -hwaccel_output_format cuda ^
        -i "%%G" ^
        -fps_mode vfr ^
        -movflags +faststart ^
        -c:v hevc_nvenc ^
        -preset:v p7 ^
        -tune:v hq ^
        -pix_fmt:v p010le ^
        -rc:v vbr ^
        -b:v !BR!k ^
        -bufsize:v !BF!k ^
        -maxrate:v !MR!k ^
        -bf:v 3 ^
        -b_ref_mode:v middle ^
        -qmin:v 0 ^
        -qmax:v 99 ^
        -temporal-aq:v 1 ^
        -rc-lookahead:v 20 ^
        -i_qfactor:v 0.75 ^
        -b_qfactor:v 1.1 ^
        -c:a libfdk_aac ^
        -qmin:a 1 ^
        -qmax:a 4 ^
        "%%~dpnG (x265)%%~xG"
        )
    )
)
