Windows Registry Editor Version 5.00

; ADD Open Debian Here
; @="\"C:\\Users\\jholl\\OneDrive\\Documents\\06-Icons-and-Shortcuts\\Programs\\Debian.ico\" -d Debian --cd \"%W\""
; @="\"C:\\Users\\jholl\\OneDrive\\Documents\\06-Icons-and-Shortcuts\\Programs\\Debian.ico\" -d Debian --cd \"%W\""

; [ * ]

[HKEY_CLASSES_ROOT\*\Shell\WSL]
@="@wsl.exe,-2"
"MUIVerb"="Open Debian Here"
"Icon"="C:\\Users\\jholl\\OneDrive\\Documents\\06-Icons-and-Shortcuts\\Programs\\Debian.ico"
"NoWorkingDirectory"=""
"Position"="Middle"
"Extended"=-

[HKEY_CLASSES_ROOT\*\Shell\WSL\command]
@="powershell.exe -NoP -W Hidden -C \"Start-Process wt.exe -Args '-w new-tab wsl.exe -d Debian --cd \\\"%W\\\"' -Verb RunAs"

; [ DesktopBackground ]

[HKEY_CLASSES_ROOT\DesktopBackground\shell\WSL]
@="@wsl.exe,-2"
"MUIVerb"="Open Debian Here"
"Icon"="C:\\Users\\jholl\\OneDrive\\Documents\\06-Icons-and-Shortcuts\\Programs\\Debian.ico"
"NoWorkingDirectory"=""
"Position"="Middle"
"Extended"=-

[HKEY_CLASSES_ROOT\DesktopBackground\shell\WSL\command]
@="powershell.exe -NoP -W Hidden -C \"Start-Process wt.exe -Args '-w new-tab wsl.exe -d Debian --cd \\\"%V\\\"' -Verb RunAs"


; [ Directory\Background ]

[HKEY_CLASSES_ROOT\Directory\Background\shell\WSL]
@="@wsl.exe,-2"
"MUIVerb"="Open Debian Here"
"Icon"="C:\\Users\\jholl\\OneDrive\\Documents\\06-Icons-and-Shortcuts\\Programs\\Debian.ico"
"Position"="Middle"
"NoWorkingDirectory"=""
"Extended"=-

[HKEY_CLASSES_ROOT\Directory\Background\shell\WSL\command]
@="powershell.exe -NoP -W Hidden -C \"Start-Process wt.exe -Args '-w new-tab wsl.exe -d Debian --cd \\\"%V\\\"' -Verb RunAs"


; [ Directory ]

[HKEY_CLASSES_ROOT\Directory\shell\WSL]
@="@wsl.exe,-2"
"MUIVerb"="Open Debian Here"
"Icon"="C:\\Users\\jholl\\OneDrive\\Documents\\06-Icons-and-Shortcuts\\Programs\\Debian.ico"
"Position"="Middle"
"NoWorkingDirectory"=""
"Extended"=-

[HKEY_CLASSES_ROOT\Directory\shell\WSL\command]
@="powershell.exe -NoP -W Hidden -C \"Start-Process wt.exe -Args '-w new-tab wsl.exe -d Debian --cd \\\"%V\\\"' -Verb RunAs"


; [ Drive ]

[HKEY_CLASSES_ROOT\Drive\shell\WSL]
@="@wsl.exe,-2"
"MUIVerb"="Open Debian Here"
"Icon"="C:\\Users\\jholl\\OneDrive\\Documents\\06-Icons-and-Shortcuts\\Programs\\Debian.ico"
"Position"="Middle"
"NoWorkingDirectory"=""
"Extended"=-

[HKEY_CLASSES_ROOT\Drive\shell\WSL\command]
@="powershell.exe -NoP -W Hidden -C \"Start-Process wt.exe -Args '-w new-tab wsl.exe -d Debian --cd \\\"%V\\\"' -Verb RunAs"
