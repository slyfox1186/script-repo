/*_____________________________________________________________________________________

  This will on activation on the following:
  
  1. Open a program if it doesn't exist already.
  2. Active a program if it exists but is not active.
  3. Closes the program if it is active.

*/

!m::
{
   win := "ahk_exe mintty.exe"
    if !WinExist(win)
    {
        try
        {
            Run "C:\path\to\mintty.exe",, "Max"
            WinWait win,, 2
            WinMaximize
            WinActivate
        }
        catch
            MsgBox "The exe was not found."
    }
    else if !WinActive(win)
        WinActivate
    else
        WinClose
}
