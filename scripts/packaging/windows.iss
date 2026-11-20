[Setup]
AppId=org.mingyuchoo.git-puller
AppName=Git Puller
AppVersion={#ReleaseVersion}
DefaultDirName={localappdata}\Programs\Git Puller
PrivilegesRequired=lowest
OutputBaseFilename=git-puller-{#ReleaseVersion}-windows-wsl-{#ReleaseArch}-setup
WizardStyle=modern
ArchitecturesAllowed={#WindowsArch}
InfoBeforeFile=requirements.txt
ChangesEnvironment=yes

[InstallDelete]
Type: files; Name: "{app}\bin\git-puller"
Type: files; Name: "{app}\git-puller.ps1"

[Files]
Source: "bundle\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Registry]
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}\bin"; Check: IsMissingFromUserPath

[Code]
function IsMissingFromUserPath: Boolean;
var
  UserPath: string;
begin
  Result := not RegQueryStringValue(HKCU, 'Environment', 'Path', UserPath)
    or (Pos(';' + Uppercase(ExpandConstant('{app}\bin')) + ';', ';' + Uppercase(UserPath) + ';') = 0);
end;
