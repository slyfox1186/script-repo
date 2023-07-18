' RESET THE SYSTEM'S ICON CACHE ONE-LINER

Set Shell = CreateObject("Shell.Application")
	Shell.ShellExecute "cmd.exe", "/D /C TASKKILL /F /IM ""explorer.exe"" /T && DEL /F /Q ""%LocalAppData%\Microsoft\Windows\Explorer\iconcache*"" && ""C:\Windows\System32\ie4uinit.exe"" -show && START """" explorer.exe && START """" /MAX explorer.exe e,""shell:Downloads""", , "RunAs", 0
