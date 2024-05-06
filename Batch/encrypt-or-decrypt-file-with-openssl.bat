@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
COLOR 0A
TITLE Encrypt or Decrypt a File using OpenSSL

:----------------------------------------------------------------------------------------------
:ABOUT
:----------------------------------------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM SELECT ENCRYPT OR DECRYPT AND ENTER THE INPUT FILE NAME

:----------------------------------------------------------------------------------------------
:INSTRUCTIONS
:----------------------------------------------------------------------------------------------

REM YOU MUST HAVE OPENSSL.EXE INSTALLED AND
REM ADD THE FOLDER PATH TO WINDOWS' %PATH% ENVIRONMENT
REM OR YOU CAN UNCOMMENT AND EDIT THE VARIABLE "OSSL"
REM BELOW AND POINT IT TO THE FULL PATH OF OPENSSL.EXE
REM YOU WILL THEN HAVE TO REPLACE EACH OF THE TWO "openssl.exe"
REM COMMANDS BELOW WITH %OSSL%

:----------------------------------------------------------------------------------------------
:MAXIMIZE_WINDOW
:----------------------------------------------------------------------------------------------

PUSHD "%~dp0"
IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:----------------------------------------------------------------------------------------------
:SET_VARIABLES
:----------------------------------------------------------------------------------------------

REM SET OSLL="C:\REPLACE\WITH\PATH\TO\openssl.exe"

:----------------------------------------------------------------------------------------------
:USER_CHOICE
:----------------------------------------------------------------------------------------------

ECHO=
ECHO Select a number: & ECHO=
ECHO   [1] Encrypt
ECHO   [2] Decrypt
ECHO   [3] Exit

CHOICE /C 123 /N & CLS

IF ERRORLEVEL 3 GOTO :EOF
IF ERRORLEVEL 2 GOTO DC
IF ERRORLEVEL 1 GOTO EC

:----------------------------------------------------------------------------------------------
:SUBROUTINES
:----------------------------------------------------------------------------------------------

:DC
SET /P "DEC=[i] Input File Name: "
set _DEC=!DEC:~0,-4!
openssl.exe aes-256-cbc -d -a -pbkdf2 -in %DEC% -out !_DEC!
GOTO :EOF

:EC
SET /P "ENC=[i] Input File Name: "
openssl.exe aes-256-cbc -a -salt -pbkdf2 -in %ENC% -out %ENC%.enc
