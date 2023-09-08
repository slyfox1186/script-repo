/*_______________________________________________________________________________________________________________
    OPEN UBUNTU DISTROS
*/

Numpad0 up::runDebian('Debian')

runDebian(appName)
{
    win := 'Terminal ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe'
    For app in ComObject('Shell.Application').NameSpace('shell:AppsFolder').Items
        (app.Name = appName) && RunWait('explorer.exe shell:appsFolder\' app.Path)
        if WinWait(win,, 2)
            WinActivate(win)
}

Numpad1 up::runXenial('Ubuntu 18.04.6 LTS')

runXenial(appName)
{
    win := 'Ubuntu 18.04.6 LTS ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe'
    For app in ComObject('Shell.Application').NameSpace('shell:AppsFolder').Items
        (app.Name = appName) && RunWait('explorer.exe shell:appsFolder\' app.Path)
        if WinWait(win,, 2)
            WinActivate(win)
}

Numpad2 up::runBionic('Ubuntu 20.04.6 LTS')

runBionic(appName)
{
    win := 'Terminal ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe'
    For app in ComObject('Shell.Application').NameSpace('shell:AppsFolder').Items
        (app.Name = appName) && RunWait('explorer.exe shell:appsFolder\' app.Path)
        if WinWait(win,, 2)
            WinActivate(win)
}

Numpad3 up::runJammy('Ubuntu 22.04.2 LTS')

runJammy(appName)
{
    win := 'Terminal ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe'
    For app in ComObject('Shell.Application').NameSpace('shell:AppsFolder').Items
        (app.Name = appName) && RunWait('explorer.exe shell:appsFolder\' app.Path)
        if WinWait(win,, 2)
            WinActivate(win)
}

Numpad4 up::runKali('Kali Linux')

runKali(appName)
{
    win := 'Terminal ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe'
    For app in ComObject('Shell.Application').NameSpace('shell:AppsFolder').Items
        (app.Name = appName) && RunWait('explorer.exe shell:appsFolder\' app.Path)
        if WinWait(win,, 2)
            WinActivate(win)
}
