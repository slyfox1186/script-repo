@ECHO OFF
SETLOCAL
COLOR 0A
TITLE RESET NETWORK CONNECTION

:------------------------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

REM SAVE FILE AS "RESET_NETWORK.BAT" TO YOUR DESKTOP
REM RIGHT CLICK FILE AND SELECT RUN AS ADMINISTRATOR

:------------------------------------------------------------------------------

IPCONFIG /RELEASE
IPCONFIG /RELEASE6
NET STOP "DHCP CLIENT"
NET STOP "DNS CLIENT"
NET STOP "NETWORK CONNECTIONS"
NET START "DHCP CLIENT"
NET START "DNS CLIENT"
NET START "NETWORK CONNECTIONS"
IPCONFIG /FLUSHDNS
IPCONFIG /RENEW
IPCONFIG /RENEW6
IPCONFIG /ALL

:------------------------------------------------------------------------------

ECHO.
TITLE [ Done ] RESET NETWORK CONNECTION
PAUSE
