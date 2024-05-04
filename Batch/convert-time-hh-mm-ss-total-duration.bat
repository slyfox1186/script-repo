@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE CONVERT TOTAL TIME DURATION IN HH:MM:SS FORMAT

:----------------------------------------------------------------------------------

REM CREATED BY: SLYFOX1186
REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM CONVERT START TIME + STOP TIME = TOTAL TIME DURATION
REM TIME FORMAT: HH:MM:SS

REM THE SCRIPT WILL PROMPT THE USER TO ENTER THE
REM START AND STOP TIMES

:----------------------------------------------------------------------------------

REM SET WORKING DIRECTORY TO THE SCRIPT'S DIRECTORY
PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:----------------------------------------------------------------------------------

REM SET VARIABLES
ECHO=
SET /P "StartPosition=Start Position (HH:MM:SS): "
SET /P "EndPosition=End Position (HH:MM:SS):   "
SET /A "ss=(((1%EndPosition::=-100)*60+1%-100)-(((1%StartPosition::=-100)*60+1%-100)"
SET /A "hh=ss/3600+100,ss%%=3600,mm=ss/60+100,ss=ss%%60+100"

:----------------------------------------------------------------------------------

REM ECHO THE RESULTS TO THE CMD WINDOW
ECHO=
ECHO Duration = %hh:~1%:%mm:~1%:%ss:~1%
PAUSE >NUL

:----------------------------------------------------------------------------------

REM ADD OUTPUT TO WINDOWS CLIPBOARD
ECHO %hh:~1%:%mm:~1%:%ss:~1%|CLIP
REM OUTPUT DURATION TO TEXT FILE IN THE SCRIPT'S DIRECTORY
ECHO %hh:~1%:%mm:~1%:%ss:~1%>"duration.txt"
