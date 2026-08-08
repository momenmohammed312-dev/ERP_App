; POS System v2.2.0 - Inno Setup Installer Script
; Professional installer for Windows

#define MyAppName "Professional POS System"
#define MyAppVersion "2.2.0"
#define MyAppPublisher "MO2 Systems"
#define MyAppURL "https://mo2-systems.com"
#define MyAppExeName "pos_offline_desktop.exe"

[Setup]
AppId={{8B5A3E2B-4F1C-4A2B-9E3D-7F8A9B2C3D4E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
LicenseFile=license.txt
InfoBeforeFile=readme.txt
OutputDir=installer_output
OutputBaseFilename=POS_System_v2.2.0_Setup
SetupIconFile=assets\logo\app_logo.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/quiet /norestart"; Flags: waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"

[Code]
// Verifies that all required plugin DLLs exist next to the installed exe.
// Mirrors the list used by the startup self-check in windows/runner/main.cpp.
function VerifyInstalledFiles(): Boolean;
var
  RequiredDlls: array of String;
  I: Integer;
  AppDir: String;
begin
  Result := True;
  AppDir := ExpandConstant('{app}');

  RequiredDlls := [
    'flutter_windows.dll',
    'app_links_plugin.dll',
    'connectivity_plus_plugin.dll',
    'desktop_window_plugin.dll',
    'flutter_secure_storage_windows_plugin.dll',
    'permission_handler_windows_plugin.dll',
    'platform_device_id_windows_plugin.dll',
    'printing_plugin.dll',
    'screen_retriever_windows_plugin.dll',
    'share_plus_plugin.dll',
    'sqlite3_flutter_libs_plugin.dll',
    'url_launcher_windows_plugin.dll',
    'window_manager_plugin.dll'
  ];

  for I := 0 to GetArrayLength(RequiredDlls) - 1 do
  begin
    if not FileExists(AppDir + '\' + RequiredDlls[I]) then
    begin
      Result := False;
      Log('Missing required file after install: ' + RequiredDlls[I]);
    end;
  end;

  if not FileExists(AppDir + '\{#MyAppExeName}') then
    Result := False;
end;

function InitializeSetup(): Boolean;
begin
  if not IsWin64 then
  begin
    MsgBox('This application requires a 64-bit version of Windows.', mbError, MB_OK);
    Result := False;
    exit;
  end;
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    RegWriteStringValue(HKLM, 'SOFTWARE\{#MyAppName}', 'InstallPath', ExpandConstant('{app}'));
    RegWriteStringValue(HKLM, 'SOFTWARE\{#MyAppName}', 'Version', '{#MyAppVersion}');
    RegWriteStringValue(HKLM, 'SOFTWARE\{#MyAppName}', 'Publisher', '{#MyAppPublisher}');

    // Verify all required plugin DLLs were actually installed.
    // A missing DLL (e.g. connectivity_plus_plugin.dll) makes the app fail
    // at the customer side, so detect it during install instead.
    if not VerifyInstalledFiles then
      MsgBox('تحذير: بعض ملفات البرنامج لم يتم تثبيتها بنجاح.' + #13#10 +
             'Warning: some required program files were NOT installed correctly.' + #13#10 + #13#10 +
             'يرجى إعادة تشغيل المثبّت، وإذا استمرت المشكلة قم بفحص إعدادات مضاد الفيروسات.' + #13#10 +
             'Please run the installer again. If the problem persists, check your antivirus settings.',
             mbError, MB_OK);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RegDeleteKeyIncludingSubkeys(HKLM, 'SOFTWARE\{#MyAppName}');
  end;
end;

[CustomMessages]
arabic.LaunchProgram=تشغيل البرنامج
english.LaunchProgram=Launch Program
arabic.CreateDesktopIcon=إنشاء أيقونة على سطح المكتب
english.CreateDesktopIcon=Create a desktop icon
arabic.AdditionalIcons=أيقونات إضافية
english.AdditionalIcons=Additional Icons
arabic.UninstallProgram=إزالة البرنامج
english.UninstallProgram=Uninstall Program
