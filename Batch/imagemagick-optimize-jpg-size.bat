@ECHO OFF
SETLOCAL
COLOR 0A
TITLE IMAGEMAGICK - OPTIMIZE JPG FILES

:------------------------------------------------------------------------------------------------

REM Created By: SlyFox1186
REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM I RECOMMEND USING THE NEW VERSION OF THIS SCRIPT: https://pastebin.com/gLtreVxs

REM THIS IS ONE OF THE BEST IMAGEMAGICK SCRIPTS TO SHRINK ANY SIZED JPG FILES WITH NEAR LOSSLESS QUALITY
REM CREATE A BATCH SCRIPT AND PLACE IT IN A TEST FOLDER FULL OF JPG FILES TO PROCESS

REM INSTRUCTIONS:
REM MOGRIFY.EXE IS REQUIRED TO USE THIS SCRIPT SO MAKE SURE YOU INSTALL IMAGEMAGICK
REM YOU MUST CHOOSE A DLL VERSION AND ENABLE LEGACY DOWNLOADS WHEN INSTALLING TO GET MOGRIFY.EXE
REM LINK: https://imagemagick.org/script/download.php

REM YOU ALSO NEED TO PLACE THE ROOT INSTALL DIRECTORY ( C:\Program Files\ImageMagick-blah-blah ) IN YOUR WINDOWS ENVIRONMENT PATH
REM OR POINT THE FULL PATH OF [ C:\Program Files\ImageMagick-blah-blah\mogrify.exe ] IN PLACE OF THE MOGRIFY COMMAND IN THE SCRIPT BELOW.

:------------------------------------------------------------------------------------------------

REM START SCRIPT

PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:------------------------------------------------------------------------------------------------

IF NOT EXIST "Output" MKDIR "Output"

:------------------------------------------------------------------------------------------------

SETLOCAL ENABLEDELAYEDEXPANSION
FOR %%G IN (*.jpg) DO (
    FOR /F "TOKENS=3" %%I IN ('MAGICK identify "%%G"') DO (
    	SET /A CNT+=1
	    SET "file!CNT!=%%~nxG"
	    ECHO=
    	CALL ECHO [!CNT!] Converting Image: %%file!CNT!%%
    	ECHO=
    	MOGRIFY -monitor -path Output/ -filter Triangle -define filter:support=2 -thumbnail "%%I" -unsharp 0.25x0.08+8.3+0.045 -dither None -posterize 136 -quality 82 -define jpeg:fancy-upsampling=off -define png:compression-filter=5 -define png:compression-level=9 -define png:compression-strategy=1 -define png:exclude-chunk=all -interlace none -colorspace sRGB -format jpg "%%G"
    	ECHO=
    	REM FINISH THE SCRIPT IF ALL FILES HAVE BEEN PROCESSED
       	IF "%%G"=="" ENDLOCAL
	)
)

:------------------------------------------------------------------------------------------------

REM OPEN EXPLORER TO THE OUTPUT FOLDER
START "" /MAX explorer.exe "%CD%\Output"
