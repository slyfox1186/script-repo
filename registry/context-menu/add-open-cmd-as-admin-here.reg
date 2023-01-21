Windows Registry Editor Version 5.00

; ADD OPEN CMD AS ADMINISTRATOR TO EXPLORER'S CONTEXT MENU
; USES EXPLORER'S ACTIVE PATH AS CMD'S CURRENT WORKING DIRECTORY

; SAVE THIS SCRIPT WITH A '.reg' EXTENSION AND RUN THE FILE AS AN ADMIN TO ADD TO THE REGISTRY
; GO TO THE END OF SCRIPT TO SEE HOW YOU CAN REMOVE THE MENU SHOULD YOU WANT TO

[HKEY_CLASSES_ROOT\*\shell\CMDAsAdmin]
@="CMD Here"
"Icon"="imageres.dll,-5324"
"HasLUAShield"=""
"Position"="Middle"
[HKEY_CLASSES_ROOT\*\shell\CMDAsAdmin\command]
@="CMD /D /C ECHO|SET/P=\"%W\"|POWERSHELL -NoP -W 1 -NonI -NoL \"SaPs 'CMD' -Args '/D /C \"\"\"PUSHD',$([char]34+$Input+[char]34),'^&^& START /MAX CMD /E:ON /T:0A /D /K\"\"\"PROMPT $P$G$_$G' -Verb RunAs\""


[HKEY_CLASSES_ROOT\DesktopBackground\Shell\CMDAsAdmin]
@="CMD Here"
"Icon"="imageres.dll,-5324"
"HasLUAShield"=""
"Position"="Middle"
[HKEY_CLASSES_ROOT\DesktopBackground\Shell\CMDAsAdmin\command]
@="CMD /D /C ECHO|SET/P=\"%V\"|POWERSHELL -NoP -W 1 -NonI -NoL \"SaPs 'CMD' -Args '/D /C \"\"\"PUSHD',$([char]34+$Input+[char]34),'^&^& START /MAX CMD /E:ON /T:0A /D /K\"\"\"PROMPT $P$G$_$G' -Verb RunAs\""


[HKEY_CLASSES_ROOT\Directory\shell\CMDAsAdmin]
@="CMD Here"
"Icon"="imageres.dll,-5324"
"HasLUAShield"=""
"Position"="Middle"
[HKEY_CLASSES_ROOT\Directory\shell\CMDAsAdmin\command]
@="CMD /D /C ECHO|SET/P=\"%L\"|POWERSHELL -NoP -W 1 -NonI -NoL \"SaPs 'CMD' -Args '/D /C \"\"\"PUSHD',$([char]34+$Input+[char]34),'^&^& START /MAX CMD /E:ON /T:0A /D /K\"\"\"PROMPT $P$G$_$G' -Verb RunAs\""


[HKEY_CLASSES_ROOT\Directory\Background\shell\CMDAsAdmin]
@="CMD Here"
"Icon"="imageres.dll,-5324"
"HasLUAShield"=""
"Position"="Middle"
[HKEY_CLASSES_ROOT\Directory\Background\shell\CMDAsAdmin\command]
@="CMD /D /C ECHO|SET/P=\"%V\"|POWERSHELL -NoP -W 1 -NonI -NoL \"SaPs 'CMD' -Args '/D /C \"\"\"PUSHD',$([char]34+$Input+[char]34),'^&^& START /MAX CMD /E:ON /T:0A /D /K\"\"\"PROMPT $P$G$_$G' -Verb RunAs\""


[HKEY_CLASSES_ROOT\Drive\shell\CMDAsAdmin]
@="CMD Here"
"Icon"="imageres.dll,-5324"
"HasLUAShield"=""
"Position"="Middle"
[HKEY_CLASSES_ROOT\Drive\shell\CMDAsAdmin\command]
@="CMD /D /C ECHO|SET/P=\"%L\"|POWERSHELL -NoP -W 1 -NonI -NoL \"SaPs 'CMD' -Args '/D /C \"\"\"PUSHD',$([char]34+$Input+[char]34),'^&^& START /MAX CMD /E:ON /T:0A /D /K\"\"\"PROMPT $P$G$_$G' -Verb RunAs\""


[HKEY_CLASSES_ROOT\LibraryFolder\background\shell\CMDAsAdmin]
@="CMD Here"
"Icon"="imageres.dll,-5324"
"HasLUAShield"=""
"Position"="Middle"
[HKEY_CLASSES_ROOT\LibraryFolder\background\shell\CMDAsAdmin\command]
@="CMD /D /C ECHO|SET/P=\"%V\"|POWERSHELL -NoP -W 1 -NonI -NoL \"SaPs 'CMD' -Args '/D /C \"\"\"PUSHD',$([char]34+$Input+[char]34),'^&^& START /MAX CMD /E:ON /T:0A /D /K\"\"\"PROMPT $P$G$_$G' -Verb RunAs\""


; To allow mapped drives to be available in command prompt
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System]
"EnableLinkedConnections"=dword:00000001


; TO REMOVE THE CONTEXT MENU ABOVE UNCOMMENT THE BELOW SECTION AND SAVE IT IN A NEW, SEPARATE FILE FROM THIS ONE ALSO USING A '.reg' EXTENSION... RUN THE FILE AS AN ADMIN
; MAKE SURE TO REMOVE THE '; ' INFRONT OF EACH LINE BELOW

; [-HKEY_CLASSES_ROOT\*\shell\CMDAsAdmin]
; [-HKEY_CLASSES_ROOT\DesktopBackground\Shell\CMDAsAdmin]
; [-HKEY_CLASSES_ROOT\Directory\shell\CMDAsAdmin]
; [-HKEY_CLASSES_ROOT\Directory\Background\shell\CMDAsAdmin]
; [-HKEY_CLASSES_ROOT\Drive\shell\CMDAsAdmin]
; [-HKEY_CLASSES_ROOT\LibraryFolder\background\shell\CMDAsAdmin]
; [HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System]
; "EnableLinkedConnections"=-
