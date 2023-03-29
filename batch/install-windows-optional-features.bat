@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION ENABLEEXTENSIONS
COLOR 0A
TITLE INSTALL WINDOWS OPTIONAL FEATURES (INCLUDES WINDOWS SUBSYSTEM FOR LINUX)

:--------------------------------------------------------------------------------------------------

REM SET THE LIST OF FEATURES TO BE INSTALLED BY STOREING THEM IN THE FOLLOWING VARIABLES

SET PKG1=IIS-ASP,IIS-ASPNET,IIS-ASPNET45,Microsoft-Windows-Subsystem-Linux,VirtualMachinePlatform,WCF-HTTP-Activation,WCF-HTTP-Activation45
SET PKG2=WCF-MSMQ-Activation45,WCF-Pipe-Activation45,WCF-Services45,WCF-TCP-Activation45,WCF-TCP-PortSharing45,DirectoryServices-ADAM-Client
SET PKG3=WCF-Pipe-Activation45,SimpleTCP,SMB1Protocol,SMB1Protocol-Client,SMB1Protocol-Deprecation,SMB1Protocol-Server,SmbDirect,TelnetClient
SET PKG4=TFTP,TIFFIFilter,Printing-Foundation-Features,Printing-Foundation-InternetPrinting-Client,NFS-Administration,ServicesForNFS-ClientOnly
SET PKG5=WAS-WindowsActivationService,WorkFolders-Client,WCF-HTTP-Activation,WCF-HTTP-Activation45,WCF-MSMQ-Activation45,WCF-NonHTTP-Activation
SET PKG6=WCF-Services45,WCF-TCP-Activation45,WCF-TCP-PortSharing45,Client-DeviceLockdown,Client-EmbeddedBootExp,Client-EmbeddedLogon
SET PKG7=Client-EmbeddedShellLauncher,Deployment Image Servicing and Management tool,Windows-Identity-Foundation,NetFx4Extended-ASPNET45
SET PKG8=WCF-HTTP-Activation,WCF-NonHTTP-Activation,IIS-WebServerRole,IIS-WebServer,IIS-CommonHttpFeatures,IIS-HttpErrors,IIS-HttpRedirect
SET PKG9=IIS-ApplicationDevelopment,IIS-Security,IIS-RequestFiltering,IIS-NetFxExtensibility,IIS-NetFxExtensibility45,IIS-HealthAndDiagnostics
SET PKG10=IIS-HttpLogging,IIS-LoggingLibraries,IIS-RequestMonitor,IIS-HttpTracing,IIS-URLAuthorization,IIS-IPSecurity,IIS-Performance
SET PKG11=IIS-HttpCompressionDynamic,IIS-WebServerManagementTools,IIS-ManagementScriptingTools,IIS-IIS6ManagementCompatibility,IIS-Metabase

REM AFTER ALL THE FEATURES YOU WANT INCLUDED ARE ADDED ABOVE, CONCAT EACH VARIABLE TOGETHER
  - SEE THE NEXT LINE FOR AN EXAMPLE OF HOW TO COMBINE THE VARIABLES TOGETHER BEFORE RUNNING THEM IN THE FOR LOOP COMMAND BELOW

SET INSTALL_FEATURES=%PKG1%,%PKG2%,%PKG3%,%PKG4%,%PKG5%,%PKG6%,%PKG7%,%PKG8%,%PKG9%,%PKG10%,%PKG11%

:--------------------------------------------------------------------------------------------------

FOR %%G IN (%INSTALL_FEATURES:,= %) DO dism.exe /Online /Enable-Feature /FeatureName:%%G /All /NoRestart

:--------------------------------------------------------------------------------------------------

ECHO=
ECHO EXITING THE SCRIPT IN 3 SECONDS
TIMEOUT 3 >NUL
