; ════════════════════════════════════════════════════════════════════════════
; Inno Setup Script - POS Factory (Factory Flavor)
; Brand: DEVELOPED BY MO2 | Contact: 01025545211
; Compatible with Windows 10 & 11 (x64 only)
; ════════════════════════════════════════════════════════════════════════════

#define MyAppName "POS Factory - نسخه مجانيه"
#define MyAppVersion "2.2.0"
#define MyAppPublisher "DEVELOPED BY MO2"
#define MyAppContact "01025545211"
#define MyAppURL "https://mo2.dev"
#define MyAppExeName "pos_offline_desktop.exe"
#define MyAppCopyright "Copyright (C) 2026 DEVELOPED BY MO2"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
AppCopyright={#MyAppCopyright}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} - نسخه مجانيه مدى الحياة
VersionInfoCopyright={#MyAppCopyright}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=E:\Temp\installer_output
OutputBaseFilename=POS_Factory_Setup_{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2/ultra64
SolidCompression=yes
LZMANumBlockThreads=4
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
WizardSizePercent=110
SetupLogging=yes
CloseApplications=force
CloseApplicationsFilter=pos_offline_desktop.exe
RestartApplications=no
AllowCancelDuringInstall=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: checkedonce
Name: "startmenuicon"; Description: "Create a &Start Menu folder"; GroupDescription: "Additional icons:"; Flags: checkedonce
Name: "installvc"; Description: "Install Visual C++ Runtime (recommended)"; GroupDescription: "Prerequisites:"; Flags: checkedonce

[Files]
; Main application files
Source: "..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\sqlite3.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\sqlite3_flutter_libs_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\desktop_window_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\flutter_secure_storage_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\pdfium.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\permission_handler_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\platform_device_id_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\printing_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\screen_retriever_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\share_plus_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\url_launcher_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\window_manager_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion

; Data folder (Flutter assets)
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

; VC++ Redistributable (silent install)
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Tasks: installvc

[Icons]
; Desktop shortcut
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

; Start Menu folder
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: startmenuicon
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"

[Run]
; Install VC++ Redistributable silently
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Visual C++ Runtime..."; Flags: waituntilterminated; Tasks: installvc

; Launch app after installation  
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}"

[Code]
// ════════════════════════════════════════════════════════════════════════════
// Inno Setup Pascal Script
// ════════════════════════════════════════════════════════════════════════════

function InitializeSetup: Boolean;
begin
  Result := True;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  // Check if app is running and try to close it
  if CheckForMutexes('{#MyAppName}') then
  begin
    if MsgBox('The application is currently running. It will be closed to continue installation.', mbInformation, MB_OKCANCEL) = IDOK then
    begin
      Exec('taskkill', '/f /im {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Sleep(1000);
    end
    else
    begin
      Result := 'Installation cancelled by user.';
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // Post-install tasks if needed
  end;
end;

function InitializeUninstall: Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  // Close app before uninstall
  Exec('taskkill', '/f /im {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(500);
end;

// Custom page for brand information
procedure CreateAboutPage;
var
  AboutPage: TNewNotebookPage;
  TitleLabel: TNewStaticText;
  ContactLabel: TNewStaticText;
  BrandLabel: TNewStaticText;
begin
  // This would be called during wizard initialization if needed
end;
