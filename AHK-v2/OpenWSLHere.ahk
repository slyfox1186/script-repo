/*____________________________________________________________________________________
    OpenWSLHere.ahk

    GitHub:
    - https://github.com/slyfox1186/script-repo/blob/main/AHK-v2/OpenWSLHere.ahk

    Pastebin:
    - https://pastebin.com/u/slyfox1186

    Purpose:
    - This will open Windows' WSL terminal to the active file explorer folder or if no active explorer window is found, ~

    Instructions:
    - You need to replace the below variable 'osName' with the wsl distribution of your choosing.
    - To find the available distros run 'wsl.exe -l --all' using PowerShell to get a list of available options

    Updated:
    - 04.07.24

    Big Update:
        Combined all major versions of Windows WSL OS's into a single function greatly reducing
        the size of the overall code, and adding the ability to choose the OS you wish to use.

*/

!w Up::OpenWSLHere("Debian")
^!w Up::OpenWSLHere("Ubuntu")
^!+w Up::OpenWSLHere("Arch")

OpenWSLHere(osName) {
    static WT := "C:\Users\" A_UserName "\AppData\Local\Microsoft\WindowsApps\wt.exe"
    static WSL := "C:\Windows\System32\wsl.exe"
    static WIN := "ahk_class CASCADIA_HOSTING_WINDOW_CLASS ahk_exe WindowsTerminal.exe"
    static PSHELL := FileExist("C:\Program Files\PowerShell\7\pwsh.exe") ? "C:\Program Files\PowerShell\7\pwsh.exe" : "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

    if !WinActive("ahk_class CabinetWClass ahk_exe explorer.exe") {
        Run(pshell ' -NoP -W Hidden -C "Start-Process -WindowStyle Max ' . wt . ' -Args `'-w new-tab ' . wsl . ' -d ' . osName . ' --cd ~ `' -Verb RunAs"',, "Hide")
        if WinWait(WIN,, 2)
            WinActivate
        return
    }

    hwnd := WinExist("A")
    winObj := ComObject("Shell.Application").Windows
    try activeTab := ControlGetHwnd("ShellTabWindowClass1", hwnd)

    winObj := ComObject("Shell.Application").Windows
    for win in winObj {
        if (win.hwnd = hwnd) {
            if (activeTab) {
                shellBrowser := ComObjQuery(win, "{4C96BE40-915C-11CF-99D3-00AA004AE837}", "{000214E2-0000-0000-C000-000000000046}")
                if !shellBrowser
                    continue
                ComCall(3, shellBrowser, "uint*", &currentTab:=0)
                if (currentTab != activeTab)
                    continue
            }
            pwd := win.Document.Folder.Self.Path
            pwd := StrReplace(pwd, "'", "''")
            pwd := StrReplace(pwd, "\\wsl.localhost", "")
            pwd := RegExReplace(pwd, "\\(Arch|Debian|Ubuntu)", "/")
            pwd := StrReplace(pwd, "\", "/")
            break
        }
    }

    Run(pshell ' -NoP -W Hidden -C "Start-Process -WindowStyle Max ' . wt . ' -Args `'-w new-tab ' . wsl . ' -d ' . osName . ' --cd \"' . pwd . '\" `' -Verb RunAs"',, "Hide")
    if WinWait(WIN,, 2)
        WinActivate
}
