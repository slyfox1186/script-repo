@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
TITLE RESTART WINDOWS SUBSYSTEM FOR LINUX

:-----------------------------------------------

REM Shutdown all WSL instances
ECHO Restarting WSL...
ECHO=
wsl.exe --shutdown

:-----------------------------------------------

REM Restart the LxssManager service
ECHO Restarting the LxssManager service...
ECHO=
net stop LxssManager
net start LxssManager
