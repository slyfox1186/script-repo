@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE CONVERT WEBP FILE TO PNG AND CREATE ICON

REM THIS SCRIPT CONVERTS A WEBP FILE INTO A PNG THEN
REM CONVERTS THE PNG FILE INTO A MULTI-SIZED ICON

REM REQUIRED PACKAGES: IMAGEMAGICK'S CONVERT.EXE AND FFMPEG.EXE
REM FFMPEG: https://github.com/m-ab-s/media-autobuild_suite
REM IMAGEMAGICK: https://imagemagick.org/script/download.php

REM IN ORDER TO INSTALL CONVERT.EXE YOU NEED TO DOWNLOAD ONE OF THE
REM DLL VERSIONS OF IMAGEMAGICK FOR WINDOWS AND DURING INSTALL YOU
REM MUST CHECK "INSTALL LEGACY UTILITIES".

:----------------------------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM CHANGE WORKING DIRECTORY TO THE SCRIPT'S DIRECTORY AND OPEN WINDOW MAXIMIZED
PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:----------------------------------------------------------------------------------

REM SET VARS FOR FFMPEG.EXE, IMAGEMAGICK.EXE, AND ICON SIZES
SET FF=FULL\PATH\TO\ffmpeg.exe
SET IM=FULL\PATH\TO\convert.exe
SET ICO_SIZES=16,20,32,48,64,96,128,256

:----------------------------------------------------------------------------------

REM DEL LEFTOVER FILES FROM PREVIOUS RUNS AND CREATE THE OUTPUT DIRECTORY
IF EXIST "Output" RD /S /Q "Output"
MD "Output" >NUL

:----------------------------------------------------------------------------------

REM CONVERT WEBP FILE TO PNG
FOR %%G IN (*.webp) DO (
	"%FF%" ^
	-y ^
	-hide_banner ^
	-stats ^
	-i "%%G" ^
    "%%~nG.png"
)

:----------------------------------------------------------------------------------

REM CREATE ICON
FOR %%G IN (*.png) DO (
	"%IM%" ^
    "%%G" ^
    -colorspace sRGB ^
	-resize 256x256 ^
	-define icon:auto-resize="%ICO_SIZES%" ^
	"Output\%%~nG.ico"
)

:----------------------------------------------------------------------------------

REM UNCOMMENT THE NEXT LINE TO DELETE THE ORIGINAL WEBP AND PNG FILES
REM FOR %%G IN (*.png, *.webp) DO DEL /Q "%%~nxG"

:----------------------------------------------------------------------------------

REM OPEN THE CREATED ICON IN THE DEFAULT VIEWER
FOR /R %%G IN (*.ico) DO IF EXIST "%%G" START "" /MAX "%%G"
