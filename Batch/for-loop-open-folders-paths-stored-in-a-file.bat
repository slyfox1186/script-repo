@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE LOOP OPEN FOLDERS IN EXPLORER

:-------------------------------------------------------------------

PUSHD "%~dp0"

:-------------------------------------------------------------------

FILENAME=<file.txt here>

:-------------------------------------------------------------------

FOR /F "TOKENS=*" %%G IN (%FILENAME%) DO (
    START "" /MAX explorer.exe %%G
    TIMEOUT 1 >NUL
)
