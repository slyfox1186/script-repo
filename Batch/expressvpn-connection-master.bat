@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE ExpressVPN Client Command Line Script

:----------------------------------------------------------------------------------

REM Created by: SlyFox1186
REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM Command line to connect to an ExpressVPN server by
REM using the 3rd party app "expresso.exe".
REM Download: https://github.com/sttz/expresso

REM Place this script in the same directory as "expresso.exe".

REM This script will start or restart the ExpressVPN
REM service before connecting to the VPN server to
REM ensure the client runs correctly.

REM For a list of commands run: expresso.exe -h

REM Make sure to change the variable SERVER to your preference.

:----------------------------------------------------------------------------------

PUSHD "%~dp0"
REM Uncomment the next line to start the cmd.exe window minimized.
:: IF NOT "%1"=="MIN" START /MIN CMD /D /C %0 MIN & GOTO :EOF

:----------------------------------------------------------------------------------
:RESTART
:----------------------------------------------------------------------------------

REM Edit the SERVER number variable below to your desired server.
REM To get the list of servers run: expresso.exe alfred --locations
SET SERVER=19

:----------------------------------------------------------------------------------

ECHO What would you like to do? & ECHO=
ECHO [1] Connect/Disconnect
ECHO [2] List Servers
ECHO [3] Exit & ECHO=

CHOICE /C 123 /N & CLS

IF ERRORLEVEL 3 GOTO :EOF
IF ERRORLEVEL 2 GOTO LIST
IF ERRORLEVEL 1 GOTO AUTO_CONNECT

:----------------------------------------------------------------------------------
:LIST
:----------------------------------------------------------------------------------

REM LIST ALL VPN SERVERS
expresso.exe alfred --locations
ECHO=
PAUSE
CLS & ENDLOCAL & GOTO RESTART

:----------------------------------------------------------------------------------
:AUTO_CONNECT
:----------------------------------------------------------------------------------

REM USE FINDSTR TO VERIFY IF EXPRESSPN IS CURRENTLY CONNECTED
FOR /F "TOKENS=*" %%G IN ('expresso.exe disconnect ^| FINDSTR "VPN is not connected"') DO (
	IF /I NOT "%%G" NEQ "VPN is not connected" (
		ECHO Connecting ExpressVPN, please wait..
		net stop "ExpressVPNService" >NUL
		net start "ExpressVPNService" >NUL
		CLS
		expresso.exe connect --change %SERVER%
	  ) ELSE (
		expresso.exe disconnect
	)
)

TIMEOUT 3 >NUL
