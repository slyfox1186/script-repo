@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE ImageMagick - Optimize jpg files

:------------------------------------------------------------------------------------------------
 
REM Created By: SlyFox1186
REM https://pastebin.com/u/slyfox1186
 
REM ImageMagick
REM Optimize Image: Ultra Settings

REM This is my favorite settings for optimizing (shrinking) an image's
REM file size with very little quality loss.

REM The script will prompt the user to select the
REM input file type, choose either jpg or png.

REM Save this with a .bat extension and place it in
REM the folder with your images.

REM You must do a test run and confirm the results are
REM to your satisfaction before running on your favorite
REM photos. We only do smart around here, right!

REM IMPORTANT! This Requires Imagemagick's mogrify.exe

REM You can install mogrify.exe by downloading the DLL
REM version of ImageMagick (not the static version due
REM to mogrify.exe not being included with it).

REM During the installation make sure to check
REM "Install legacy programs" for mogrify.exe to be installed.
REM Link: https://imagemagick.org/script/download.php
REM Screenshot: https://i.imgur.com/fnMWY9Q.jpg

:------------------------------------------------------------------------------------------------

PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:------------------------------------------------------------------------------------------------

REM Please change these two variable value's as needed
REM Set the 'EDITOR_NAME' variable to whatever you want
SET EDITOR_NAME=NOTEPAD
REM SET the 'EDITOR_PATH' variable to the exe file path of your editor.
SET EDITOR_PATH="%windir%\notepad.exe"

:------------------------------------------------------------------------------------------------

REM If detected prompt the user to delete all files from a prior run
IF EXIST "Output" (
	ECHO=
	ECHO Output files detected: Delete them? & ECHO=
	ECHO [1] Yes
	ECHO [2] No & ECHO=
	CHOICE /C 12 /N & CLS & ECHO=
	IF ERRORLEVEL 2 GOTO NO_DELETE
	IF ERRORLEVEL 1 RD /S /Q "Output"
)

REM Create the output folder if missing
IF NOT EXIST "Output" MKDIR "Output"

:------------------------------------------------------------------------------------------------

:NO_DELETE
REM Prompt the user to choose the input file type
CLS & ECHO=
ECHO CHOOSE INPUT FILE TYPE & ECHO=
ECHO [1] JPG
ECHO [2] PNG
ECHO [3] EXIT & ECHO=

CHOICE /C 123 /N & CLS & ECHO=

IF ERRORLEVEL 3 GOTO :EOF
IF ERRORLEVEL 2 GOTO RUN_PNG
IF ERRORLEVEL 1 GOTO RUN_JPG

:------------------------------------------------------------------------------------------------
:RUN_PNG
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
:------------------------------------------------------------------------------------------------

REM Run mogrify on all png files in script's working directory
SET CNT=0
FOR %%G IN (*.png) DO (
	FOR /F "TOKENS=*" %%H IN ('MAGICK identify -format "%%[fx:w]x%%[fx:h]" "*.png"') DO (
		SET /A CNT+=1
		SET "file!CNT!=%%~nxG"
		ECHO=
		CALL ECHO [!CNT!] %%file!CNT!%%
		ECHO=
		START "" /B /WAIT /ABOVENORMAL MOGRIFY -monitor -path Output/ -filter Triangle -define filter:support=2 -thumbnail "%%H" -unsharp 0.25x0.08+8.3+0.045 -dither None -posterize 136 -quality 82 -define jpeg:fancy-upsampling=off -define png:compression-filter=5 -define png:compression-level=9 -define png:compression-strategy=1 -define png:exclude-chunk=all -interlace none -colorspace sRGB -format png "*.png"
		IF "%%G"=="" ENDLOCAL
	)
)

REM If the script was successful open the file using the default program otherwise continue to error
DIR /A-D "Output\*.png" >NUL 2>&1
IF NOT ERRORLEVEL 1 (
	COLOR 03
	ECHO= & ECHO=
	ECHO [93mMogrify Completed[0m
	ECHO=
	TIMEOUT 5 >NUL
	PUSHD "Output"
	FOR %%I IN (*.png) DO (
		START "" "%%~fI" & GOTO :EOF
	)
)

REM Jump to the error section to alert the user of a problem
GOTO ERROR

:------------------------------------------------------------------------------------------------
:RUN_JPG
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
:------------------------------------------------------------------------------------------------

REM Run mogrify on all jpg files in script's working directory
SET CNT=0
FOR %%G IN (*.jpg) DO (
	FOR /F "TOKENS=*" %%H IN ('MAGICK identify -format "%%[fx:w]x%%[fx:h]" "*.jpg"') DO (
		SET /A CNT+=1
		SET "file!CNT!=%%~nxG"
		ECHO=
		CALL ECHO [!CNT!] %%file!CNT!%%
		ECHO=
		START "" /B /WAIT /ABOVENORMAL MOGRIFY -monitor -path Output/ -filter Triangle -define filter:support=2 -thumbnail "%%H" -unsharp 0.25x0.08+8.3+0.045 -dither None -posterize 136 -quality 82 -define jpeg:fancy-upsampling=off -define png:compression-filter=5 -define png:compression-level=9 -define png:compression-strategy=1 -define png:exclude-chunk=all -interlace none -colorspace sRGB -format jpg "*.jpg"
		IF "%%G"=="" ENDLOCAL
	)
)

REM If the script was successful open the file using the default program otherwise continue
DIR /A-D "Output\*.jpg" >NUL 2>&1
IF NOT ERRORLEVEL 1 (
	COLOR 03
	ECHO= & ECHO=
	ECHO [93mMogrify Completed[0m
	ECHO=
	TIMEOUT 5 >NUL
	PUSHD "Output"
	FOR %%I IN (*.jpg) DO (
		START "" "%%~fI" & GOTO :EOF
	)
)

:------------------------------------------------------------------------------------------------
:ERROR
:------------------------------------------------------------------------------------------------

REM Echo an error message and open the script by using the 'EDITOR_PATH' variable
CLS & ECHO=
ECHO Error: Mogrify failed to convert the file^(s^). & ECHO=
SET /P "dummy=Press [Enter] to open the script in: %EDITOR_NAME% "
START "" /MAX %EDITOR_PATH% "%0"
