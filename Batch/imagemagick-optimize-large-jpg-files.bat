@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE USE TEMP CACHE FILES TO OPTIMIZE LARGE JPG FILES

:----------------------------------------------------------------------------------

REM CREATED BY: SLYFOX1186
REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

:----------------------------------------------------------------------------------

REM THIS SCRIPT WILL USE TEMPORARY CACHE FILES TO APPLY EXTREME OPTIMIZATION TO LARGE JPG FILES
REM FOR USE WITH JPG FILES >= 3 MEGABYTES PER IMAGE.

REM YOU MUST DOWNLOAD AND INSTALL IMAGEMAGICK'S DLL VERSION FOR WINDOWS TO OBTAIN CONVERT.EXE.
REM DURING INSTALLATION YOU NEED TO CHECK THE BOX "INCLUDE LEGACY FILES" OR CONVERT.EXE WON'T BE INCLUDED.
REM DOWNLOAD: https://imagemagick.org/script/download.php

REM PLACE THIS SCRIPT INSIDE THE FOLDER WITH THE JPG FILES AND IT SCRIPT WILL CREATE A SUBFOLDER CALLED 'OUTPUT'
REM TO STORE THE OPTIMIZED FILES IN AND WILL LEAVE YOUR ORIGINAL FILES INTACT.

REM !ALWAYS! DO A TEST RUN BEFORE RUNNING THIS ON ANY FILES YOU CAN'T AFFORD TO LOSE.

:----------------------------------------------------------------------------------

PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:----------------------------------------------------------------------------------

REM POINT THIS VARIABLE TO THE FULL PATH OF IMAGEMAGICK'S CONVERT.EXE FILE
SET CONVERT=%ProgramFiles%\ImageMagick\convert.exe

:----------------------------------------------------------------------------------

REM CREATE TEMP AND OUTPUT FOLDERS
IF NOT EXIST "%TMP%\IMagick_Cache_Files" MD "%TMP%\IMagick_Cache_Files"
IF NOT EXIST "Output" MD "Output"

:----------------------------------------------------------------------------------

REM FIND ALL JPG FILES AND CONVERT THEM TO MPC FORMAT
SETLOCAL ENABLEEXTENSIONS
FOR %%G IN (*.jpg) DO (
	FOR /F "TOKENS=1-2" %%H IN ('identify +ping -format "%%w %%h" "%%G"') DO (
		ECHO Create: %%~nG.mpc ^+ %%~nG.cache
		ECHO=
		"%CONVERT%" "%%G" -monitor -filter Triangle -define filter:support=2 -thumbnail "%%Hx%%I" -strip ^
		-unsharp 0.25x0.08+8.3+0.045 -dither None -posterize 136 -quality 82 -define jpeg:fancy-upsampling=off ^
		-auto-level -enhance -interlace none -colorspace sRGB "%TMP%\IMagick_Cache_Files\%%~nG.mpc"
		CLS
		IF "%%G"=="" ENDLOCAL
	)
)

:----------------------------------------------------------------------------------

REM CONVERT CACHE FILES INTO JPG
SETLOCAL ENABLEEXTENSIONS
FOR %%G IN ("%TMP%\IMagick_Cache_Files\*.mpc") DO (
	ECHO Convert: %%~nG.cache ^>^> %%~nG.jpg
	ECHO=
	"%CONVERT%" "%%G" -monitor "Output\%%~nG.jpg"
	CLS
	IF "%%G"=="" ENDLOCAL
	)
)

:----------------------------------------------------------------------------------

REM CLEANUP TEMP FILES
RD /S /Q "%TMP%\IMagick_Cache_Files"
START "" /MAX "%CD%\Output\*.jpg"
