/*_______________________________________________________________________________________________________________
    OPEN WSL DISTROS DOWNLOADED FROM THE WINDOWS STORE

    CHANGE THE NAME AS NEEDED TO THE DISTRIBUTION YOU WISH TO OPEN

    EXAMPLE: Numpad0 up::runDebian('Debian') .... 'Debian' is the key to making it work
  
*/

Numpad0 up::runDebian('Debian')

runDebian(appName)
{
    win := 'ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe'
    For app in ComObject('Shell.Application').NameSpace('shell:AppsFolder').Items
        (app.Name = appName) && RunWait('explorer.exe shell:appsFolder\' app.Path)
        if !WinExist(win)
        try
        {
            WinWait(win,, 3)
            WinActivate(win)
        }
        catch
            return
}

Numpad1 up::runXenial('Ubuntu 18.04.6 LTS')

runXenial(appName)
{
    win := 'Ubuntu 18.04.6 LTS ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe'
    For app in ComObject('Shell.Application').NameSpace('shell:AppsFolder').Items
        (app.Name = appName) && RunWait('explorer.exe shell:appsFolder\' app.Path)
        if !WinExist(win)
        try
        {
            WinWait(win,, 3)
            WinActivate(win)
        }
        catch
            return
}

Numpad2 up::runBionic('Ubuntu 20.04.6 LTS')

runBionic(appName)
{
    win := 'Ubuntu 20.04.6 LTS ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe'
    For app in ComObject('Shell.Application').NameSpace('shell:AppsFolder').Items
        (app.Name = appName) && RunWait('explorer.exe shell:appsFolder\' app.Path)
        if !WinExist(win)
        try
        {
            WinWait(win,, 3)
            WinActivate(win)
        }
        catch
            return
}

Numpad3 up::runJammy('Ubuntu 22.04.2 LTS')

runJammy(appName)
{
    win := 'ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe'
    For app in ComObject('Shell.Application').NameSpace('shell:AppsFolder').Items
        (app.Name = appName) && RunWait('explorer.exe shell:appsFolder\' app.Path)
        if !WinExist(win)
        try
        {
            WinWait(win,, 3)
            WinActivate(win)
        }
        catch
            return
}

Numpad4 up::runKali('Kali Linux')

runKali(appName)
{
    win := 'ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe'
    For app in ComObject('Shell.Application').NameSpace('shell:AppsFolder').Items
        (app.Name = appName) && RunWait('explorer.exe shell:appsFolder\' app.Path)
        if !WinExist(win)
        try
        {
            WinWait(win,, 3)
            WinActivate(win)
        }
        catch
            return
}
