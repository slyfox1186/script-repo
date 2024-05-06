@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION ENABLEEXTENSIONS
COLOR 0A
TITLE INSTALL WINDOWS OPTIONAL FEATURES

:--------------------------------------------------------------------------------------------------

REM GitHub: https://github.com/slyfox1186/script-repo/tree/main/Batch

SET DISM="C:\Windows\System32\Dism.exe"
SET SD="C:\Windows\System32\shutdown.exe"

:--------------------------------------------------------------------------------------------------

REM FIRST, SET THE LIST OF FEATURES TO BE INSTALLED BY STOREING THEM IN THE FOLLOWING VARIABLES

SET PKG1=IIS-ASP,IIS-ASPNET,IIS-ASPNET45,Microsoft-Windows-Subsystem-Linux,VirtualMachinePlatform,WCF-HTTP-Activation,WCF-HTTP-Activation45
SET PKG2=WCF-MSMQ-Activation45,WCF-Pipe-Activation45,WCF-Services45,WCF-TCP-Activation45,WCF-TCP-PortSharing45,DirectoryServices-ADAM-Client
SET PKG3=WCF-Pipe-Activation45,SimpleTCP,SMB1Protocol,SMB1Protocol-Client,SMB1Protocol-Deprecation,SMB1Protocol-Server,SmbDirect,TelnetClient
SET PKG4=TFTP,TIFFIFilter,Printing-Foundation-Features,Printing-Foundation-InternetPrinting-Client,NFS-Administration,ServicesForNFS-ClientOnly
SET PKG5=WAS-WindowsActivationService,WorkFolders-Client,WCF-HTTP-Activation,WCF-HTTP-Activation45,WCF-MSMQ-Activation45,WCF-NonHTTP-Activation
SET PKG6=WCF-Services45,WCF-TCP-Activation45,WCF-TCP-PortSharing45,Client-DeviceLockdown,Client-EmbeddedBootExp,Client-EmbeddedLogon
SET PKG7=Client-EmbeddedShellLauncher,Windows-Identity-Foundation,NetFx4Extended-ASPNET45,WCF-HTTP-Activation,WCF-NonHTTP-Activation
SET PKG8=IIS-WebServerRole,IIS-WebServer,IIS-CommonHttpFeatures,IIS-HttpErrors,IIS-HttpRedirect,IIS-ApplicationDevelopment,IIS-Security
SET PKG9=IIS-RequestFiltering,IIS-NetFxExtensibility,IIS-NetFxExtensibility45,IIS-HealthAndDiagnostics,IIS-HttpLogging,IIS-LoggingLibraries
SET PKG10=IIS-RequestMonitor,IIS-HttpTracing,IIS-URLAuthorization,IIS-IPSecurity,IIS-Performance,IIS-HttpCompressionDynamic
SET PKG11=IIS-WebServerManagementTools,IIS-ManagementScriptingTools,IIS-IIS6ManagementCompatibility,IIS-Metabase,IIS-WindowsAuthentication

:--------------------------------------------------------------------------------------------------

REM CONCAT THE ABOVE VARIABLES TOGETHER BY CREATING A NEW VARAIBLE BELOW
SET INSTALL_FEATURES=%PKG1%,%PKG2%,%PKG3%,%PKG4%,%PKG5%,%PKG6%,%PKG7%,%PKG8%,%PKG9%,%PKG10%,%PKG11%

:--------------------------------------------------------------------------------------------------

FOR %%G IN (%INSTALL_FEATURES:,= %) DO %DISM% /Online /Enable-Feature /FeatureName:%%G /All /NoRestart

:--------------------------------------------------------------------------------------------------

IF ERRORLEVEL 0 (
    ECHO=
    ECHO THE WINDOWS FEATURES HAVE BEEN ENABLED SUCCESSFULLY & ECHO=
    ECHO DO YOU WANT TO RESTART YOUR PC TO ACTIVATE THEM? & ECHO=
    ECHO [1] Yes
    ECHO [2] No & ECHO=

    CHOICE /C 12 /N & CLS

    IF ERRORLEVEL 2 GOTO :EOF
    IF ERRORLEVEL 1 (
        %SD% /r /t 1
        GOTO :EOF
    )
) ELSE (
    CLS
    ECHO THE SCRIPT FAILED TO ENABLE WINDOW'S OPTIONAL FEATURES...
    ECHO=
    ECHO PLEASE CHECK THE SCRIPT FOR ERRORS OR RESTART YOUR PC AND TRY AGAIN
    ECHO=
    PAUSE
)
