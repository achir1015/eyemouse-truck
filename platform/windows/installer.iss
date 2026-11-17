; 眼動鼠之寶島卡車 Windows 安裝程式（Inno Setup 6）
; 用法：ISCC /DAppVersion=1.0.0 installer.iss
; 安裝到使用者資料夾，不需系統管理員權限；程式內更新會用 /SILENT 覆蓋安裝並自動重開。

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppName "眼動鼠之寶島卡車"
#define AppExe "EyeMouseTruck.exe"

[Setup]
AppId={{3E7A9C52-1B4D-4F86-9A2E-7C5D0B8F4A19}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=吳玉柱 先生 與 Claude AI Opus 5.5
AppPublisherURL=https://achir1015.github.io/eyemouse-truck/
AppSupportURL=https://github.com/achir1015/eyemouse-truck
AppUpdatesURL=https://github.com/achir1015/eyemouse-truck/releases
DefaultDirName={localappdata}\Programs\EyeMouseTruck
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\..\build\release
OutputBaseFilename=EyeMouseTruck-Setup
SetupIconFile=..\icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName={#AppName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "cht"; MessagesFile: "ChineseTraditional.isl"

[Tasks]
Name: "desktopicon"; Description: "建立桌面捷徑"; GroupDescription: "其他工作："

[Files]
Source: "..\..\..\build\windows\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\解除安裝 {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; 不加 skipifsilent：程式內更新（/SILENT）完成後也會自動重新開啟
Filename: "{app}\{#AppExe}"; Description: "立即開啟眼動鼠之寶島卡車"; Flags: nowait postinstall
