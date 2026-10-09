REM CREATED BY SlyFox1186
REM https://pastebin.com/u/slyfox1186
REM https://stackoverflow.com/users/10572786/slyfox11867

REM THIS SCRIPT WILL LAUNCH AMD RYZEN MASTER MAXIMIZED >>
REM >> AND CREATE A RYZEN PROFILE+TEMPORARY AHK SCRIPT
REM [YOU MUST] HAVE AUTOHOTKEY.EXE INSTALLED
REM MAKE SURE AUTOHOTKEY.EXE IS SET TO RUNS AS AN ADMINISTRATOR
REM RIGHT CLICK AUTOHOTKEY.EXE, COMPATIBILITY TAB, CHECK "RUN AS AN ADMINISTRATOR"
REM MODIFY OR REMOVE SECTIONS IF/AS NECESSARY

REM BEGIN SCRIPT

@ECHO OFF
REM RUN THE SCRIPT AS AN ADMINISTRATOR IF NOT ALREADY DOING SO
IF NOT "%1"=="am_admin" (POWERSHELL -WindowStyle Hidden -Command START -verb RunAs '%0' am_admin & EXIT /B)
SETLOCAL ENABLEEXTENSIONS
COLOR 0A
TITLE OPEN RYZEN MASTER MAXIMIZED

:---------------------------------------------------------------------------------------------------------------

PUSHD "%~dp0"

:---------------------------------------------------------------------------------------------------------------

REM CREATE THE TEMPORARY AHK SCRIPT
REM IF YOU HAVE ISSUES WITH THE SCRIPT SUCCESSFULLY >>
REM >> CLOSING THE POP UP WINDOW WHEN RYZEN MASTER LAUNCHES >>
REM >> INCREASE THE SLEEP TIME VALUE BY EDITING THE [pauseAHK] VARIABLE BELOW
REM YOU SHOULD INCREASE THE SLEEP TIME IN INCREMENTS OF 100 UNTIL WORKING [1000 = 1 SECOND]

SET ahkSleep=1000
(
ECHO #SingleInstance, Force
ECHO #KeyHistory 0
ECHO ListLines Off
ECHO SetBatchLines, -1
ECHO SetControlDelay, -1
ECHO SetKeyDelay, -1, -1
ECHO SetWinDelay, -1
ECHO DetectHiddenWindows, On
ECHO DetectHiddenText, On
ECHO DllCall^("Sleep,",UInt,16.67^)
ECHO=
ECHO win :^= "AMD RYZEN MASTER ahk_class Qt5158QWindowOwnDCIcon ahk_exe AMD Ryzen Master.exe"
ECHO=
ECHO WinWaitActive, %% win,, 4
ECHO SendInput, {Enter}
ECHO Sleep, %ahkSleep%
ECHO WinWaitActive, %% win,, 3
ECHO WinMaximize, %% win
ECHO Return
)> "%TMP%\RyzenMax.ahk"

:---------------------------------------------------------------------------------------------------------------

REM START RYZEN MASTER
START "" "%ProgramFiles%\AMD\RyzenMaster\bin\AMD Ryzen Master.exe"

:---------------------------------------------------------------------------------------------------------------

REM START AND THEN DELETE THE TEMPORARY AHK SCRIPT
START "" /WAIT /HIGH "%TMP%\RyzenMax.ahk"
DEL /Q "%TMP%\RyzenMax.ahk"
