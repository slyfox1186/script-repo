@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE CHANGING NETWORK SETTINGS

:----------------------------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM FOR USE AS A QUICK SWITCH BETWEEN LAN AND WAN DNS SERVERS, OR DHCP.
REM USE EITHER THE ROUTER'S DNS OR OPENDNS SERVERS.
REM CHANGE THE VARIABLES AS NEEDED.

:----------------------------------------------------------------------------------

IF NOT "%1"=="MAX" START /MAX CMD /D /C %0 MAX & GOTO :EOF

:----------------------------------------------------------------------------------

SET NETWORK=Wi-Fi
SET IPV4=192.168.1.100
SET SUBNET=255.255.255.0
SET GATEWAY=192.168.1.1
REM WAN USES OPENDNS
SET DNS1=208.67.220.220
SET DNS2=208.67.222.222
SET LOCAL_DNS=192.168.1.1

:----------------------------------------------------------------------------------

ECHO CHANGING NETWORK SETTINGS: & ECHO=
ECHO VALUES SET IN SCRIPT: & ECHO=
ECHO ===============================================
ECHO:      IP       ^|     SUBNET    ^|   GATEWAY   =
ECHO: %IPV4% ^| %SUBNET% ^| %GATEWAY% =
ECHO =============================================== & ECHO=
ECHO [1] SET WAN OPENDNS [ %DNS1% ^| %DNS2% ]
ECHO [2] SET LAN DNS [ %LOCAL_DNS% ]
ECHO [3] SET DHCP
ECHO [4] EXIT

:----------------------------------------------------------------------------------

CHOICE /C 1234 /N & CLS

:----------------------------------------------------------------------------------

IF ERRORLEVEL 4 GOTO :EOF

IF ERRORLEVEL 3 (
	ECHO CHANGING NETWORK SETTINGS: & ECHO=
	ECHO DHCP
	netsh interface ip set address "%NETWORK%" dhcp
	netsh interface ip set dnsservers name="%NETWORK%" source=dhcp
)

IF ERRORLEVEL 2 (
	ECHO CHANGING NETWORK SETTINGS: & ECHO=
	ECHO IP: %NETWORK%
	ECHO SUBNET: %SUBNET% 
	ECHO GATEWAY: %GATEWAY%
	ECHO DNS 1: %DNS1%
	ECHO DNS 2: %DNS2%
	netsh interface ip set address name="%NETWORK%" static %IPV4% %SUBNET% %GATEWAY% 1
	netsh interface ip set dns name="%NETWORK%" static %DNS1% >NUL
	netsh interface ip add dns name="%NETWORK%" %DNS2% index=2 >NUL
)

IF ERRORLEVEL 1 (
	ECHO CHANGING NETWORK SETTINGS: & ECHO=
	ECHO IP: %NETWORK%
	ECHO SUBNET: %SUBNET% 
	ECHO GATEWAY: %GATEWAY%
	ECHO DNS: %LOCAL_DNS%
	netsh interface ip set address name="%NETWORK%" static %IPV4% %SUBNET% %GATEWAY% 1
	netsh interface ip set dns name="%NETWORK%" static %LOCAL_DNS% >NUL
)

:----------------------------------------------------------------------------------

PAUSE
