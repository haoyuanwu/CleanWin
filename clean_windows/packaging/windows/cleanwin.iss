; Build with Inno Setup 6.3+. The application bundle must be a Release build.
#ifndef BundleDir
  #define BundleDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{1E1CA448-9F8B-46BA-A92C-D78BA1BE092D}
AppName=CleanWin
AppVersion={#AppVersion}
AppPublisher=CleanWin
DefaultDirName={autopf}\CleanWin
DefaultGroupName=CleanWin
DisableProgramGroupPage=yes
PrivilegesRequired=admin
; No PrivilegesRequiredOverridesAllowed: per-user /CURRENTUSER downgrade is disabled.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
UninstallDisplayIcon={app}\clean_windows.exe
OutputDir={#OutputDir}
OutputBaseFilename=CleanWin-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=clean_windows.exe
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Excludes: "*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\CleanWin"; Filename: "{app}\clean_windows.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\CleanWin"; Filename: "{app}\clean_windows.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; Do not launch as the unelevated original user after an elevated installation.
Filename: "{app}\clean_windows.exe"; WorkingDir: "{app}"; Description: "Launch CleanWin"; Flags: nowait postinstall skipifsilent runascurrentuser
