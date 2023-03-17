@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE Recursively extract zip archives

:--------------------------------------------------------------------------------

PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:--------------------------------------------------------------------------------

SET SZIP="%ProgramFiles%\7-Zip\7z.exe"

:--------------------------------------------------------------------------------

REM RECURSIVELY SEARCH FOR ALL ZIP FILES AND EXTRACT THEIR
REM CONTENTS TO A FOLDER WITH THE SAME NAME AS THE ARCHIVE.
REM UNCOMMENT DEL /Q "%%G" BELOW TO DELETE THE ARCHIVES AFTER EXTRACTION

FOR /F "USEBACKQ TOKENS=*" %%G IN (`DIR /S /B *.zip`) DO (
    %SZIP% x -y "%%G" -o"%%~dpnG"
    REM DEL /Q "%%G"
)
