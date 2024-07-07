@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
TITLE RESTART WINDOWS SUBSYSTEM FOR LINUX

ECHO Restarting WSL...
ECHO=

REM Shutdown all WSL instances
wsl.exe --shutdown

REM Restart the LxssManager service
ECHO Restarting the LxssManager service...
net stop LxssManager
net start LxssManager
