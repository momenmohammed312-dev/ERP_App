; POS System v2.0 - Inno Setup Installer Script
; Professional installer for Windows

#define MyAppName "Professional POS System"
#define MyAppVersion "2.1.0"
#define MyAppPublisher "MO2 Systems"
#define MyAppURL "https://mo2-systems.com"
#define MyAppExeName "pos_system.exe"

[Setup]
; NOTE: The value of AppId uniquely identifies this application.
; Do not use the same AppId value in installers for other applications.
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
OutputBaseFilename=POS_System_v2.1_Setup
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
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; OnlyBelowVersion: 6.1

[Files]
; Main application files
Source: "build\windows\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

; Required runtime files
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: quicklaunchicon

[Run]
; Install Visual C++ Redistributable
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/quiet"; StatusMsg: "Installing Visual C++ Runtime..."

; Launch application after installation
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\assets"

[Code]
// Custom code for additional functionality

function InitializeSetup(): Boolean;
begin
  // Check if .NET Framework is installed
  if not DotNetIsInstalled(4, 6) then
  begin
    MsgBox('This application requires .NET Framework 4.6 or higher. Please install it first.', mbError, MB_OK);
    Result := False;
    exit;
  end;
  
  // Check Windows version
  if not IsWin64 then
  begin
    MsgBox('This application requires a 64-bit version of Windows.', mbError, MB_OK);
    Result := False;
    exit;
  end;
  
  Result := True;
end;

// Check if .NET Framework is installed
function DotNetIsInstalled(version: cardinal; service: cardinal): boolean;
var
  key: string;
  install, serviceCount: cardinal;
begin
  key := 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v' + IntToStr(version) + '.0';
  if not RegQueryDWordValue(HKLM, key, 'Install', install) then
  begin
    Result := False;
    exit;
  end;
  
  if install <> 1 then
  begin
    Result := False;
    exit;
  end;
  
  if service > 0 then
  begin
    if not RegQueryDWordValue(HKLM, key, 'Servicing', serviceCount) then
    begin
      Result := False;
      exit;
    end;
    
    Result := (serviceCount >= service);
  end else
    Result := True;
end;

// Custom page for license key input
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  // Skip license key page for upgrade
  if PageID = wpSelectDir then
  begin
    if RegKeyExists(HKLM, 'SOFTWARE\{#MyAppName}') then
    begin
      // This is an upgrade
      Result := False;
    end else
    begin
      // This is a fresh install
      Result := False;
    end;
  end;
  
  Result := False;
end;

// Create registry entries for auto-update
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // Create registry entries for application
    RegWriteStringValue(HKLM, 'SOFTWARE\{#MyAppName}', 'InstallPath', ExpandConstant('{app}'));
    RegWriteStringValue(HKLM, 'SOFTWARE\{#MyAppName}', 'Version', '{#MyAppVersion}');
    RegWriteStringValue(HKLM, 'SOFTWARE\{#MyAppName}', 'Publisher', '{#MyAppPublisher}');
    
    // Add to Windows Firewall exception
    ShellExec('netsh', 'advfirewall firewall add rule name="{#MyAppName}" dir=in action=allow program="' + ExpandConstant('{app}\{#MyAppExeName}') + '" enable=yes', '', SW_HIDE, ewWaitUntilTerminated, n);
  end;
end;

// Clean up on uninstall
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    // Remove firewall exception
    ShellExec('netsh', 'advfirewall firewall delete rule name="{#MyAppName}"', '', SW_HIDE, ewWaitUntilTerminated, n);
    
    // Remove registry entries
    RegDeleteKeyIncludingSubkeys(HKLM, 'SOFTWARE\{#MyAppName}');
  end;
end;

// Custom messages
[CustomMessages]
arabic.LaunchProgram=تشغيل البرنامج
english.LaunchProgram=Launch Program

arabic.CreateDesktopIcon=إنشاء أيقونة على سطح المكتب
english.CreateDesktopIcon=Create a desktop icon

arabic.CreateQuickLaunchIcon=إنشاء أيقونة تشغيل سريع
english.CreateQuickLaunchIcon=Create a Quick Launch icon

arabic.AdditionalIcons=أيقونات إضافية
english.AdditionalIcons=Additional Icons

arabic.UninstallProgram=إزالة البرنامج
english.UninstallProgram=Uninstall Program
