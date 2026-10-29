#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#ifndef AssetSuffix
  #define AssetSuffix "local"
#endif

#ifndef ReleaseDir
  #error ReleaseDir must point to the Flutter Windows Release directory.
#endif

#define AppExeName "mfuns_flutter.exe"

[Setup]
AppId={{7E832652-EB41-4774-BA5E-0B858418C366}
AppName=Mfuns Flutter
AppVersion={#AppVersion}
AppPublisher=Mfuns Flutter
DefaultDirName={localappdata}\Programs\Mfuns Flutter
DefaultGroupName=Mfuns Flutter
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\..\build\windows\installer
OutputBaseFilename=mfuns-flutter-setup-{#AssetSuffix}
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Mfuns Flutter"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\Mfuns Flutter"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "启动 Mfuns Flutter"; Flags: nowait postinstall skipifsilent
