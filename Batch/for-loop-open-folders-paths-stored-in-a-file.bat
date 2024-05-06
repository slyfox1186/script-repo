@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE LOOP OPEN FOLDERS IN EXPLORER

:-------------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

PUSHD "%~dp0"
SET FILENAME=<file.txt here>

:-------------------------------------------------------------------

FOR /F "TOKENS=*" %%G IN (%FILENAME%) DO (
    START "" /MAX explorer.exe %%G
    TIMEOUT 1 >NUL
)
