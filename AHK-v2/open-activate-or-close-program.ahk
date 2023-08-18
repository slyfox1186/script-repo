/*_____________________________________________________________________________________

  This will on activation on the following:

  1. Open a program if it doesn't exist already.
  2. Active a program if it exists but is not active.
  3. Closes the program if it is active.

*/

!f up::
{
    runThis := 'C:\Program Files\Notepad++\notepad++.exe'
    win := 'ahk_class Notepad++ ahk_exe notepad++.exe'

    if !WinExist(win)
    {
        Run(runThis,, 'Max', &winNew)
        if WinWait('ahk_pid ' . winNew,, 3)
            WinActivate('ahk_pid ' . winNew)
    }
    else if !WinActive(win)
        WinActivate(win)
    else
        WinClose(win)
}
