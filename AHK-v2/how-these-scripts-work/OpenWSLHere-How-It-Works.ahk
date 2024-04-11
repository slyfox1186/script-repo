; Set the Hotkeys to call the function and pass the name of the desired Linux distro to the function
!w Up::OpenWSLHere("Debian") ; Opens Debian in Windows Terminal
^!w Up::OpenWSLHere("Ubuntu") ; Opens Ubuntu in Windows Terminal
^!+w Up::OpenWSLHere("Arch") ; Opens Arch Linux in Windows Terminal

OpenWSLHere(osName) {
    static wt := "C:\Users\" A_UserName "\AppData\Local\Microsoft\WindowsApps\wt.exe" ; Set the full path of Windows Terminal
    static wsl := A_WinDir . "\System32\wsl.exe" ; Set the full path of WSL
    static win := "ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe" ; Set the Window identifiers for Windows Terminal
    static pshell := FileExist(A_ProgramFiles . "\PowerShell\7\pwsh.exe") ? A_ProgramFiles . "\PowerShell\7\pwsh.exe" : A_WinDir . "\System32\WindowsPowerShell\v1.0\powershell.exe" ; Set the powershell version to use. If Powershell 7 is installed prioritize it first.

    ; This asks if the current active window is explorer.exe and if it's not then open Windows Terminal to the $HOME (~) path of the user.
    if !WinActive("ahk_class CabinetWClass ahk_exe explorer.exe") { ; Check if the active window is not Windows File Explorer
        Run(pshell ' -NoP -W H -C "Start-Process -WindowStyle Max ' . wt . ' -Args `'-w new-tab ' . wsl . ' -d ' . osName . ' --cd ~ `' -Verb RunAs"',, "Hide") ; Open a new Windows Terminal tab with the specified Linux distribution and navigate to the user's HOME directory
        if WinWait(win,, 2) ; Wait for the Windows Terminal window to appear
            WinActivate(win) ; Bring the Windows Terminal window to the foreground
        else
            WinActivate("A") ; Activate the currently active window if the Windows Terminal window doesn't appear
    return
    }

    hwnd := WinExist("A") ; Get the handle of the currently active window and store it in the hwnd variable
    winObj := ComObject("Shell.Application").Windows ; Create an object representing the open Windows Explorer windows
    try activeTab := ControlGetHwnd("ShellTabWindowClass1", hwnd) ; Attempt to get the handle of the active tab in the File Explorer window

    winObj := ComObject("Shell.Application").Windows ; Create another object representing the open Windows Explorer windows
    for win in winObj { ; Loop through the open Windows Explorer windows
        if (win.hwnd = hwnd) { ; Check if the window handle matches the currently active window handle
            if (activeTab) { ; Check if an active tab was previously detected
                shellBrowser := ComObjQuery(win, "{4C96BE40-915C-11CF-99D3-00AA004AE837}", "{000214E2-0000-0000-C000-000000000046}") ; Query the shell browser interface
                if (!shellBrowser) ; If the shell browser interface is not available
                    continue ; Move to the next iteration of the loop
                ComCall(3, shellBrowser, "uint*", &currentTab:=0) ; Get the handle of the current tab
                if (currentTab != activeTab) ; Check if the current tab handle is different from the active tab handle
                    continue ; Move to the next iteration of the loop
            }
            pwd := win.Document.Folder.Self.Path ; Get the current folder path from the active Explorer window
            pwd := StrReplace(pwd, "'", "''") ; Replace single quotes with double single quotes which if not done will cause the Explorer folder path to fail to open correctly
            pwd := StrReplace(pwd, "\\wsl.localhost", "") ; Remove the "\wsl.localhost" portion from the path
            pwd := RegExReplace(pwd, "\\(Arch|Debian|Ubuntu)", "/") ; Replace the Linux distribution path with a forward slash
            pwd := StrReplace(pwd, "\", "/") ; Replace all remaining backslashes with forward slashes
            break ; Exit the loop after finding the matching window and converting and obtaining the Windows path into a Linux path
        }
    }

    Run(pshell ' -NoP -W H -C "Start-Process -WindowStyle Max ' . wt . ' -Args `'-w new-tab ' . wsl . ' -d ' . osName . ' --cd \"' . pwd . '\" `' -Verb RunAs"',, "Hide") ; Open a new Windows Terminal tab with the specified Linux distribution and navigate to the retrieved folder path
    if WinWait(win,, 2) ; Wait for the Windows Terminal window to appear
        WinActivate(win) ; Bring the Windows Terminal window to the foreground
    else
        WinActivate("A") ; Activate the currently active window if the Windows Terminal window doesn't appear
}
