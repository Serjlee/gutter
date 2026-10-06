; Gutter's Windows installer (Inno Setup 6). Installs for the current user
; only (%LOCALAPPDATA%\Programs\Gutter), so neither installing nor updating
; asks for admin rights: Gutter updates itself by running a new installer
; silently (/VERYSILENT) once it quits.
;
;   flutter build windows --release
;   iscc /DAppVersion=0.1.0 windows\installer\gutter.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputName
  #define OutputName "Gutter-windows-x64-" + AppVersion + "-setup"
#endif

[Setup]
; Never change: Windows knows the installed Gutter by it.
AppId={{A5943D5F-69F8-4EEF-AB9D-8ACED4AFD341}
AppName=Gutter
AppVersion={#AppVersion}
AppVerName=Gutter {#AppVersion}
AppPublisher=Gutter
AppPublisherURL=https://github.com/serjlee/gutter
AppSupportURL=https://github.com/serjlee/gutter/issues
AppUpdatesURL=https://github.com/serjlee/gutter/releases
PrivilegesRequired=lowest
DefaultDirName={autopf}\Gutter
DisableProgramGroupPage=yes
DisableDirPage=auto
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\gutter.exe
UninstallDisplayName=Gutter
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputDir=.
OutputBaseFilename={#OutputName}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

; Files of the previous version that this one doesn't have must not linger.
[InstallDelete]
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Gutter"; Filename: "{app}\gutter.exe"
Name: "{autodesktop}\Gutter"; Filename: "{app}\gutter.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\gutter.exe"; Description: "{cm:LaunchProgram,Gutter}"; Flags: nowait postinstall skipifsilent
