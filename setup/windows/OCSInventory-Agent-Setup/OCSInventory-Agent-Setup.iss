#define AppName "OCS Inventory Agent"
#define AppVersion "3.0.0"
#define AppPublisher "OCS Inventory"
#define AppURL "https//www.ocsinventory.com/"
#define AppExeName "ocsinventory-agent.exe"
#define ServiceExeName "OCSInventory-Service.exe"
#define AppPath "../../.."
#define AppGuid "{652EB54C-0A14-46AF-9F06-3BA7C294AFC9}"

[Setup]
AppId={{#AppGuid}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
LicenseFile={#AppPath}\setup\windows\OCSInventory-Agent-Setup\assets\license.txt
OutputDir=OCSInventory-Agent-Setup
OutputBaseFilename=OCSInventory-Agent-Setup-{#AppVersion}
SetupIconFile={#AppPath}\setup\windows\OCSInventory-Agent-Setup\assets\OCSInventory.ico
SetupLogging=yes
SolidCompression=yes
UninstallDisplayIcon={#AppPath}\setup\windows\OCSInventory-Agent-Setup\assets\OCSInventory.ico
UninstallLogging=yes
WizardStyle=modern
DisableWelcomePage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Files]
Source: "{#AppPath}\setup\windows\OCSInventory-Agent-Setup\payload\OCSInventory-Service\Any CPU\Release\net9.0\win-x64\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#AppPath}\setup\windows\OCSInventory-Agent-Setup\payload\OCSInventory-Agent\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"

[Code]
var
  INSTALL_AS_A_SERVICE, RUN_NOW: Boolean;
  ConnectionInputPage: TInputQueryWizardPage;
  CheckPage, ConfigPage: TWizardPage;
  URL, USERNAME, PASSWORD, CERTIFICATE, STORE_DATA_PATH, CONFIG_PATH, LOG_PATH, INSTALL_PATH, BYPASS_CERT: String;
  INVENTORY_MODE, LOG_LEVEL: Integer;
  AgentModeCombo, LogLevelCombo: TNewComboBox;
  InstallAsAServiceCheckBox, RunNowCheckBox, ValidateCertCheckBox: TNewCheckBox;
  CredsLine, SecLine: TBevel;
  CredsCaption, SecCaption, AgentModeLabel, LogLevelLabel: TNewStaticText;
  hE, hL: Integer;
  InvCaption, VerbCaption, AgentModeHelp, RunNowHelp: TNewStaticText;
  InvLine, VerbLine: TBevel;
  ResultCode: Integer;
  DidPreUninstall: Boolean;
const
  AppGuid = '{#AppGuid}';

function BoolToStr(Value: Boolean): String;
begin
  if Value then
    Result := 'True'
  else
    Result := 'False';
end;

function CmMultiline(const Key: string): string;
var
  S: string;
begin
  S := ExpandConstant('{cm:' + Key + '}');
  StringChangeEx(S, '#13#10', #13#10, True);
  Result := S;
end;

function GetUninsExeFromReg(var ExePath: string): Boolean;
var
  S, KeyName: string;
  p, q: Integer;
begin
  Result := False;
  ExePath := '';
  KeyName := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + AppGuid + '_is1';

  if not RegQueryStringValue(HKLM64, KeyName, 'UninstallString', S) then
  if not RegQueryStringValue(HKLM,   KeyName, 'UninstallString', S) then
  if not RegQueryStringValue(HKCU,   KeyName, 'UninstallString', S) then
    exit;

  S := Trim(S);
  if S = '' then exit;

  if (Length(S) >= 2) and (S[1] = '"') then
  begin
    q := Pos('"', Copy(S, 2, MaxInt));
    if q > 0 then
      ExePath := Copy(S, 2, q-1);
  end
  else
  begin
    p := Pos(' ', S);
    if p > 0 then
      ExePath := Copy(S, 1, p-1)
    else
      ExePath := S;
  end;

  if (ExePath = '') or not FileExists(ExePath) then
  begin
    S := RemoveQuotes(S);
    ExePath := AddBackslash(ExtractFilePath(S)) + 'unins000.exe';
  end;

  Result := FileExists(ExePath);
end;

procedure SilentUninstallIfPresent;
var
  ExePath: string;
  RC: Integer;
begin
  if GetUninsExeFromReg(ExePath) then
  begin
    Log('Found previous installation. Running: ' + AddQuotes(ExePath) +
        ' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART');
    if Exec(ExePath, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART',
            '', SW_HIDE, ewWaitUntilTerminated, RC) then
      Log('Previous uninstall finished with code ' + IntToStr(RC) + '.')
    else
      Log('Previous uninstall failed to start.');
  end
  else
    Log('No previous installation found.');
end;

procedure UpdateRunNowState(Sender: TObject);
begin
  if InstallAsAServiceCheckBox.Checked then
  begin
    RunNowCheckBox.Checked := True;
    RunNowCheckBox.Enabled := False;
  end
  else
  begin
    RunNowCheckBox.Enabled := True;
    RunNowCheckBox.Checked := False;
  end;
end;

procedure InitializeWizard;
begin
  Log(ExpandConstant('{cm:StartingOCSInventoryAgentSetup}'));

  if WizardSilent then
  begin
    Log(ExpandConstant('{cm:RunningInSilentMode}'));
  end
  else
  begin
    Log(ExpandConstant('{cm:RunningInInteractiveMode}'));
    ConnectionInputPage := CreateInputQueryPage(wpLicense, ExpandConstant('{cm:AgentConfigurationPageTitle}'), ExpandConstant('{cm:AgentConfigurationPageDescription}'), '');

    ConnectionInputPage.Add(ExpandConstant('{cm:URL}'), False);
    ConnectionInputPage.Add(ExpandConstant('{cm:Username}'), False);
    ConnectionInputPage.Add(ExpandConstant('{cm:Password}'), True);
    ConnectionInputPage.Add(ExpandConstant('{cm:Certificate}'), False);

    // Default value for URL input
    ConnectionInputPage.Values[0] := 'https://ocsinventory-server-domain';
    ConnectionInputPage.Values[3] := 'cacert.pem';

    // Server credentials title
    CredsCaption := TNewStaticText.Create(ConnectionInputPage);
    CredsCaption.Parent := ConnectionInputPage.Surface;
    CredsCaption.Caption := ExpandConstant('{cm:ServerCredentialsGroupTitle}');
    CredsCaption.Font.Style := CredsCaption.Font.Style + [fsBold];
    CredsCaption.AutoSize := True;
    CredsCaption.Left := ScaleX(8);
    CredsCaption.Top := ConnectionInputPage.PromptLabels[0].Top - ScaleY(20);

    CredsLine := TBevel.Create(ConnectionInputPage);
    CredsLine.Parent := ConnectionInputPage.Surface;
    CredsLine.Shape := bsTopLine;
    CredsLine.Left := CredsCaption.Left;
    CredsLine.Top := CredsCaption.Top + CredsCaption.Height + ScaleY(2);
    CredsLine.Width := ConnectionInputPage.SurfaceWidth;
    
    // URL
    ConnectionInputPage.PromptLabels[0].Parent := ConnectionInputPage.Surface;
    ConnectionInputPage.Edits[0].Parent := ConnectionInputPage.Surface;
    ConnectionInputPage.Edits[0].Left := ScaleX(150);
    ConnectionInputPage.Edits[0].Top  := CredsLine.Top + ScaleY(24);
    ConnectionInputPage.Edits[0].Width :=
      ConnectionInputPage.SurfaceWidth - ConnectionInputPage.Edits[0].Left - ScaleX(16);
    hE := ConnectionInputPage.Edits[0].Height;
    hL := ConnectionInputPage.PromptLabels[0].Height;
    ConnectionInputPage.PromptLabels[0].Left := ScaleX(4);
    ConnectionInputPage.PromptLabels[0].Top :=
      ConnectionInputPage.Edits[0].Top + (hE - hL) div 2;
    ConnectionInputPage.Edits[0].BringToFront;
    
    // Username
    ConnectionInputPage.PromptLabels[1].Parent := ConnectionInputPage.Surface;
    ConnectionInputPage.Edits[1].Parent := ConnectionInputPage.Surface;
    ConnectionInputPage.Edits[1].Left := ScaleX(150);
    ConnectionInputPage.Edits[1].Top  := ConnectionInputPage.Edits[0].Top + ConnectionInputPage.Edits[0].Height + + ScaleY(24);
    ConnectionInputPage.Edits[1].Width :=
      ConnectionInputPage.SurfaceWidth - ConnectionInputPage.Edits[1].Left - ScaleX(16);
    hE := ConnectionInputPage.Edits[1].Height;
    hL := ConnectionInputPage.PromptLabels[1].Height;
    ConnectionInputPage.PromptLabels[1].Left := ScaleX(4);
    ConnectionInputPage.PromptLabels[1].Top :=
      ConnectionInputPage.Edits[1].Top + (hE - hL) div 2;
    ConnectionInputPage.Edits[1].BringToFront;
    
    // Password
    ConnectionInputPage.PromptLabels[2].Parent := ConnectionInputPage.Surface;
    ConnectionInputPage.Edits[2].Parent := ConnectionInputPage.Surface;
    ConnectionInputPage.Edits[2].Left := ScaleX(150);
    ConnectionInputPage.Edits[2].Top  := ConnectionInputPage.Edits[1].Top + ConnectionInputPage.Edits[1].Height + + ScaleY(24);
    ConnectionInputPage.Edits[2].Width :=
      ConnectionInputPage.SurfaceWidth - ConnectionInputPage.Edits[2].Left - ScaleX(16);
    hE := ConnectionInputPage.Edits[2].Height;
    hL := ConnectionInputPage.PromptLabels[2].Height;
    ConnectionInputPage.PromptLabels[2].Left := ScaleX(4);
    ConnectionInputPage.PromptLabels[2].Top :=
      ConnectionInputPage.Edits[2].Top + (hE - hL) div 2;
    ConnectionInputPage.Edits[2].BringToFront;

    // Security title
    SecCaption := TNewStaticText.Create(ConnectionInputPage);
    SecCaption.Parent := ConnectionInputPage.Surface;
    SecCaption.Caption := ExpandConstant('{cm:ServerSecurityGroupTitle}');
    SecCaption.Font.Style := SecCaption.Font.Style + [fsBold];
    SecCaption.AutoSize := True;
    SecCaption.Left := CredsCaption.Left;
    SecCaption.Top := ConnectionInputPage.Edits[2].Top + ConnectionInputPage.Edits[2].Height + ScaleY(16);

    SecLine := TBevel.Create(ConnectionInputPage);
    SecLine.Parent := ConnectionInputPage.Surface;
    SecLine.Shape := bsTopLine;
    SecLine.Left := SecCaption.Left;
    SecLine.Top := SecCaption.Top + SecCaption.Height + ScaleY(2);
    SecLine.Width := ConnectionInputPage.SurfaceWidth;

    // Certificat
    ConnectionInputPage.PromptLabels[3].Parent := ConnectionInputPage.Surface;
    ConnectionInputPage.Edits[3].Parent := ConnectionInputPage.Surface;
    ConnectionInputPage.Edits[3].Left := ScaleX(150);
    ConnectionInputPage.Edits[3].Top  := SecLine.Top + ScaleY(24);
    ConnectionInputPage.Edits[3].Width :=
      ConnectionInputPage.SurfaceWidth - ConnectionInputPage.Edits[3].Left - ScaleX(16);
    hE := ConnectionInputPage.Edits[3].Height;
    hL := ConnectionInputPage.PromptLabels[3].Height;
    ConnectionInputPage.PromptLabels[3].Left := ScaleX(4);
    ConnectionInputPage.PromptLabels[3].Top :=
      ConnectionInputPage.Edits[3].Top + (hE - hL) div 2;
    ConnectionInputPage.Edits[3].BringToFront;

    // By_pass
    ValidateCertCheckBox := TNewCheckBox.Create(ConnectionInputPage);
    ValidateCertCheckBox.Parent := ConnectionInputPage.Surface;
    ValidateCertCheckBox.Top := ConnectionInputPage.Edits[3].Top + ConnectionInputPage.Edits[3].Height + ScaleY(10);
    ValidateCertCheckBox.Left := ScaleX(8);
    ValidateCertCheckBox.Width := SecLine.Width - ScaleX(16);
    ValidateCertCheckBox.Caption := ExpandConstant('{cm:ValidateCertificate}');
    ValidateCertCheckBox.Checked := True;

    ConfigPage := CreateCustomPage(
      ConnectionInputPage.ID,
      ExpandConstant('{cm:AgentConfigurationPageTitle}'),
      ExpandConstant('{cm:AgentConfigurationPageDescription}')
    );

    // === Section "Inventory" ===
    InvCaption := TNewStaticText.Create(ConfigPage);
    InvCaption.Parent := ConfigPage.Surface;
    InvCaption.Caption := ExpandConstant('{cm:InventorySectionTitle}');
    InvCaption.Font.Style := InvCaption.Font.Style + [fsBold];
    InvCaption.AutoSize := True;
    InvCaption.Left := ScaleX(8);
    InvCaption.Top := 0;

    InvLine := TBevel.Create(ConfigPage);
    InvLine.Parent := ConfigPage.Surface;
    InvLine.Shape := bsTopLine;
    InvLine.Left := InvCaption.Left;
    InvLine.Top := InvCaption.Top + InvCaption.Height + ScaleY(2);
    InvLine.Width := ConfigPage.SurfaceWidth;

    // AgentMode (dropdown)
    AgentModeCombo := TNewComboBox.Create(ConfigPage);
    AgentModeCombo.Parent := ConfigPage.Surface;
    AgentModeCombo.Style := csDropDownList;
    AgentModeCombo.Left := ScaleX(150);
    AgentModeCombo.Top := InvLine.Top + ScaleY(16);
    AgentModeCombo.Width := ConfigPage.SurfaceWidth - AgentModeCombo.Left - ScaleX(16);
    AgentModeCombo.Items.Add(ExpandConstant('{cm:AgentMode1}'));
    AgentModeCombo.Items.Add(ExpandConstant('{cm:AgentMode2}'));
    AgentModeCombo.Items.Add(ExpandConstant('{cm:AgentMode3}'));
    AgentModeCombo.Items.Add(ExpandConstant('{cm:AgentMode4}'));
    AgentModeCombo.ItemIndex := 1;

    AgentModeLabel := TNewStaticText.Create(ConfigPage);
    AgentModeLabel.Parent := ConfigPage.Surface;
    AgentModeLabel.Caption := ExpandConstant('{cm:AgentMode}');
    AgentModeLabel.AutoSize := True;
    AgentModeLabel.Left := ScaleX(8);
    AgentModeLabel.Top := AgentModeCombo.Top + (AgentModeCombo.Height - AgentModeLabel.Height) div 2;

    // AgentMode help
    AgentModeHelp := TNewStaticText.Create(ConfigPage);
    AgentModeHelp.Parent := ConfigPage.Surface;
    AgentModeHelp.AutoSize := False;
    AgentModeHelp.WordWrap := True;
    AgentModeHelp.ShowAccelChar := False;
    AgentModeHelp.Left := AgentModeLabel.Left;
    AgentModeHelp.Top := AgentModeCombo.Top + AgentModeCombo.Height + ScaleY(6);
    AgentModeHelp.Width := InvLine.Width;
    AgentModeHelp.Height := ScaleY(110);
    AgentModeHelp.Caption := CmMultiline('AgentModeHelp');

    // === Section "Verbose" ===
    VerbCaption := TNewStaticText.Create(ConfigPage);
    VerbCaption.Parent := ConfigPage.Surface;
    VerbCaption.Caption := ExpandConstant('{cm:VerboseSectionTitle}');
    VerbCaption.Font.Style := VerbCaption.Font.Style + [fsBold];
    VerbCaption.AutoSize := True;
    VerbCaption.Left := InvCaption.Left;
    VerbCaption.Top := AgentModeHelp.Top + AgentModeHelp.Height + ScaleY(16);

    VerbLine := TBevel.Create(ConfigPage);
    VerbLine.Parent := ConfigPage.Surface;
    VerbLine.Shape := bsTopLine;
    VerbLine.Left := VerbCaption.Left;
    VerbLine.Top    := VerbCaption.Top + VerbCaption.Height + ScaleY(2);
    VerbLine.Width := ConfigPage.SurfaceWidth;

    // LogLevel (dropdown)
    LogLevelCombo := TNewComboBox.Create(ConfigPage);
    LogLevelCombo.Parent := ConfigPage.Surface;
    LogLevelCombo.Style := csDropDownList;
    LogLevelCombo.Left := AgentModeCombo.Left;
    LogLevelCombo.Top := VerbLine.Top + ScaleY(16);
    LogLevelCombo.Width := AgentModeCombo.Width;
    LogLevelCombo.Items.Add(ExpandConstant('{cm:LogLevel0}'));
    LogLevelCombo.Items.Add(ExpandConstant('{cm:LogLevel1}'));
    LogLevelCombo.Items.Add(ExpandConstant('{cm:LogLevel2}'));
    LogLevelCombo.Items.Add(ExpandConstant('{cm:LogLevel3}'));
    LogLevelCombo.Items.Add(ExpandConstant('{cm:LogLevel4}'));
    LogLevelCombo.ItemIndex := 3;

    LogLevelLabel := TNewStaticText.Create(ConfigPage);
    LogLevelLabel.Parent := ConfigPage.Surface;
    LogLevelLabel.Caption := ExpandConstant('{cm:LogLevel}');
    LogLevelLabel.AutoSize := True;
    LogLevelLabel.Left := AgentModeLabel.Left;
    LogLevelLabel.Top := LogLevelCombo.Top + (LogLevelCombo.Height - LogLevelLabel.Height) div 2;


    CheckPage := CreateCustomPage(
      ConfigPage.ID,
      ExpandConstant('{cm:AgentConfigurationPageTitle}'),
      ExpandConstant('{cm:AgentConfigurationPageDescription}')
    );

    // InstallAsAService
    InstallAsAServiceCheckBox := TNewCheckBox.Create(CheckPage);
    InstallAsAServiceCheckBox.Parent := CheckPage.Surface;
    InstallAsAServiceCheckBox.Top := 0;
    InstallAsAServiceCheckBox.Left := 0;
    InstallAsAServiceCheckBox.Width := CheckPage.SurfaceWidth;
    InstallAsAServiceCheckBox.Caption := ExpandConstant('{cm:InstallAsAService}');
    InstallAsAServiceCheckBox.Checked := True;
    InstallAsAServiceCheckBox.OnClick := @UpdateRunNowState;

        // RunNow
    RunNowCheckBox := TNewCheckBox.Create(CheckPage);
    RunNowCheckBox.Parent := CheckPage.Surface;
    RunNowCheckBox.Top := InstallAsAServiceCheckBox.Top + 50;
    RunNowCheckBox.Left := 0;
    RunNowCheckBox.Width := CheckPage.SurfaceWidth;
    RunNowCheckBox.Caption := ExpandConstant('{cm:RunNow}');
    RunNowCheckBox.Checked := True;

    // RunNow help
    RunNowHelp := TNewStaticText.Create(CheckPage);
    RunNowHelp.Parent := CheckPage.Surface;
    RunNowHelp.AutoSize := False;
    RunNowHelp.WordWrap := True;
    RunNowHelp.ShowAccelChar := False;
    RunNowHelp.Left := RunNowCheckBox.Left;
    RunNowHelp.Top := RunNowCheckBox.Top + RunNowCheckBox.Height + ScaleY(6);
    RunNowHelp.Width := CheckPage.SurfaceWidth;
    RunNowHelp.Height := ScaleY(110);
    RunNowHelp.Caption := ExpandConstant('{cm:RunNowHelp}');

    UpdateRunNowState(nil);

    Log(ExpandConstant('{cm:WaitingUserToEnterInputs}'));
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  if WizardSilent then
  begin
    Exit;
  end
  else
  begin
    if CurPageID = ConnectionInputPage.ID then
    begin
      if ConnectionInputPage.Values[0] = '' then
      begin
        MsgBox(Format(ExpandConstant('{cm:ErrorMandatoryField}'), [ExpandConstant('{cm:URL}')]), mbError, MB_OK);
        Result := False;
      end
      else if ConnectionInputPage.Values[1] = '' then
      begin
        MsgBox(Format(ExpandConstant('{cm:ErrorMandatoryField}'), [ExpandConstant('{cm:Username}')]), mbError, MB_OK);
        Result := False;
      end
      else if ConnectionInputPage.Values[2] = '' then
      begin
        MsgBox(Format(ExpandConstant('{cm:ErrorMandatoryField}'), [ExpandConstant('{cm:Password}')]), mbError, MB_OK);
        Result := False;
      end
      else
      begin
        Log(Format(ExpandConstant('{cm:ConnectionDetailsValidated}'), [ConnectionInputPage.Values[0], ConnectionInputPage.Values[1]]));
      end;
    end;
  end;
end;

procedure UpdateNativeProgress(const StatusText, DetailText: string);
begin
  WizardForm.StatusLabel.Caption := StatusText;
  WizardForm.FilenameLabel.Caption := DetailText;
  WizardForm.StatusLabel.Repaint;
  WizardForm.FilenameLabel.Repaint;
  WizardForm.Repaint;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  TotalSteps, Step, ResultCode: Integer;
  tmp: string;

begin
  if (CurStep = ssInstall) and (not DidPreUninstall) then
  begin
    UpdateNativeProgress(ExpandConstant('{cm:StepUninstallPrevious}'), '');
    SilentUninstallIfPresent;
    DidPreUninstall := True;
  end;

  if CurStep = ssPostInstall then
  begin
    if WizardSilent then
    begin
      URL := ExpandConstant('{param:URL}');
      USERNAME := ExpandConstant('{param:USERNAME}');
      PASSWORD := ExpandConstant('{param:PASSWORD}');
      CERTIFICATE := ExpandConstant('{param:CERTIFICATE}');
      INVENTORY_MODE := StrToIntDef(ExpandConstant('{param:MODE}'), 1);
      LOG_LEVEL := StrToIntDef(ExpandConstant('{param:LOG_LEVEL}'), 3);

      tmp := Lowercase(ExpandConstant('{param:BYPASS_CERT}'));
      if (tmp = 'true') or (tmp = '1') then BYPASS_CERT := 'true' else BYPASS_CERT := 'false';

      tmp := Lowercase(ExpandConstant('{param:NOW}'));
      RUN_NOW := (tmp = 'true') or (tmp = '1');

      tmp := Lowercase(ExpandConstant('{param:SERVICE}'));
      INSTALL_AS_A_SERVICE := (tmp = 'true') or (tmp = '1');

      Log(Format(ExpandConstant('{cm:Parameters}'), [URL, USERNAME, CERTIFICATE, INVENTORY_MODE, LOG_LEVEL,
           BoolToStr(RUN_NOW), BoolToStr(INSTALL_AS_A_SERVICE)]));
    end
    else
    begin
      URL := ConnectionInputPage.Values[0];
      USERNAME := ConnectionInputPage.Values[1];
      PASSWORD := ConnectionInputPage.Values[2];
      CERTIFICATE := ConnectionInputPage.Values[3];

      if ValidateCertCheckBox.Checked then BYPASS_CERT := 'false' else BYPASS_CERT := 'true';

      case AgentModeCombo.ItemIndex of
        0: INVENTORY_MODE := 1;
        1: INVENTORY_MODE := 2;
        2: INVENTORY_MODE := 3;
        3: INVENTORY_MODE := 4;
      else
        INVENTORY_MODE := 1;
      end;

      case LogLevelCombo.ItemIndex of
        0: LOG_LEVEL := 0;
        1: LOG_LEVEL := 1;
        2: LOG_LEVEL := 2;
        3: LOG_LEVEL := 3;
        4: LOG_LEVEL := 4;
      else
        LOG_LEVEL := 3;
      end;

      Log(Format(ExpandConstant('{cm:Parameters}'), [URL, USERNAME, CERTIFICATE, INVENTORY_MODE, LOG_LEVEL,
           BoolToStr(RunNowCheckBox.Checked), BoolToStr(InstallAsAServiceCheckBox.Checked)]));
    end;

    STORE_DATA_PATH := ExpandConstant('{commonappdata}\OCSInventory-Agent');
    CONFIG_PATH := STORE_DATA_PATH + '\config.json';
    LOG_PATH := STORE_DATA_PATH + '\ocsinventory-agent.log';
    INSTALL_PATH := ExpandConstant('{app}');
    StringChangeEx(STORE_DATA_PATH, '\', '/', True);
    StringChangeEx(CONFIG_PATH,   '\', '/', True);
    StringChangeEx(LOG_PATH,      '\', '/', True);
    StringChangeEx(INSTALL_PATH,  '\', '/', True);

    TotalSteps := 2; // data dir + config
    if WizardSilent then
    begin
      if INSTALL_AS_A_SERVICE then TotalSteps := TotalSteps + 3
      else if RUN_NOW then TotalSteps := TotalSteps + 1;
    end
    else
    begin
      if InstallAsAServiceCheckBox.Checked then TotalSteps := TotalSteps + 3
      else if RunNowCheckBox.Checked then TotalSteps := TotalSteps + 1;
    end;

    Step := 0;

    Step := Step + 1;
    UpdateNativeProgress(
      Format('%d/%d - %s', [Step, TotalSteps, ExpandConstant('{cm:StepCreateDataDir}')]),
      STORE_DATA_PATH);

    if DirExists(STORE_DATA_PATH) then
      Log(Format(ExpandConstant('{cm:DataDirectoryExist}'), [CONFIG_PATH]))
    else
    begin
      Log(Format(ExpandConstant('{cm:DataDirectoryDoesNotExist}'), [STORE_DATA_PATH]));
      if CreateDir(STORE_DATA_PATH) then
        Log(Format(ExpandConstant('{cm:DataDirectoryCreatedSuccessfully}'), [STORE_DATA_PATH]))
      else
        MsgBox(ExpandConstant('{cm:ErrorCreatingDataDirectory}'), mbError, MB_OK);
    end;

    Step := Step + 1;
    UpdateNativeProgress(
      Format('%d/%d - %s', [Step, TotalSteps, ExpandConstant('{cm:StepWriteConfig}')]),
      CONFIG_PATH);

    if SaveStringToFile(
         CONFIG_PATH,
         Format('{"url": "%s", "username": "%s", "password": "%s", "certificate": "%s", "bypass-certificate": %s, "log_file": true, "log_level": %d, "mode": %d, "data_directory": "%s", "log_file_path": "%s", "install_directory": "%s", "execution_timeout": 120}', [URL, USERNAME, PASSWORD, CERTIFICATE, BYPASS_CERT, LOG_LEVEL, INVENTORY_MODE, STORE_DATA_PATH, LOG_PATH, INSTALL_PATH]),
         False) then
      Log(Format(ExpandConstant('{cm:ConfigurationFileCreatedSuccessfully}'), [CONFIG_PATH]))
    else
      MsgBox(ExpandConstant('{cm:ErrorCreatingConfigurationFile}'), mbError, MB_OK);

    if WizardSilent then
    begin
      if INSTALL_AS_A_SERVICE then
      begin
        Step := Step + 1;
        UpdateNativeProgress(
          Format('%d/%d - %s', [Step, TotalSteps, ExpandConstant('{cm:StepCreateService}')]),
          ExpandConstant('{app}\{#ServiceExeName}'));

        if Exec('sc.exe',
                'create "OCSInventory Agent" binpath= "' + ExpandConstant('{app}\{#ServiceExeName}') + '" start= "auto"',
                '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
        begin
          Log(ExpandConstant('{cm:ServiceCreatedSuccessfully}'));
          Step := Step + 1;
          UpdateNativeProgress(
            Format('%d/%d - %s', [Step, TotalSteps, ExpandConstant('{cm:StepSetServiceDesc}')]),
            ExpandConstant('{cm:ServiceDescription}'));

          if Exec('sc.exe',
                  'description "OCSInventory Agent" "' + ExpandConstant('{cm:ServiceDescription}') + '"',
                  '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
            Log(ExpandConstant('{cm:ServiceDescriptionSetSuccessfully}'))
          else
            MsgBox(ExpandConstant('{cm:ServiceDescriptionFailed}'), mbError, MB_OK);

          Step := Step + 1;
          UpdateNativeProgress(
            Format('%d/%d - %s', [Step, TotalSteps, ExpandConstant('{cm:StepStartService}')]),
            'sc start "OCSInventory Agent"');

          if Exec('sc.exe', 'start "OCSInventory Agent"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
            Log(ExpandConstant('{cm:ServiceStartedSuccessfully}'))
          else
            MsgBox(ExpandConstant('{cm:ServiceStartFailed}'), mbError, MB_OK);
        end
        else
          MsgBox(ExpandConstant('{cm:ServiceCreateFailed}'), mbError, MB_OK);
      end
      else if RUN_NOW then
      begin
        Step := Step + 1;
        UpdateNativeProgress(
          Format('%d/%d - %s', [Step, TotalSteps, ExpandConstant('{cm:StepRunAgentNow}')]),
          ExpandConstant('{app}\{#AppExeName}'));

        if Exec(ExpandConstant('{app}\{#AppExeName}'), '', '', SW_HIDE, ewNoWait, ResultCode) then
          Log(ExpandConstant('{cm:OCSInventoryAgentStarted}'))
        else
          MsgBox(ExpandConstant('{cm:FailedToRunOCSInventoryAgent}'), mbError, MB_OK);
      end;
    end
    else
    begin
      if InstallAsAServiceCheckBox.Checked then
      begin
        Step := Step + 1;
        UpdateNativeProgress(
          Format('%d/%d - %s', [Step, TotalSteps, ExpandConstant('{cm:StepCreateService}')]),
          ExpandConstant('{app}\{#ServiceExeName}'));

        if Exec('sc.exe',
                'create "OCSInventory Agent" binpath= "' + ExpandConstant('{app}\{#ServiceExeName}') + '" start= "auto"',
                '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
        begin
          Log(ExpandConstant('{cm:ServiceCreatedSuccessfully}'));
          Step := Step + 1;
          UpdateNativeProgress(
            Format('%d/%d - %s', [Step, TotalSteps, ExpandConstant('{cm:StepSetServiceDesc}')]),
            ExpandConstant('{cm:ServiceDescription}'));

          if Exec('sc.exe',
                  'description "OCSInventory Agent" "' + ExpandConstant('{cm:ServiceDescription}') + '"',
                  '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
            Log(ExpandConstant('{cm:ServiceDescriptionSetSuccessfully}'))
          else
            MsgBox(ExpandConstant('{cm:ServiceDescriptionFailed}'), mbError, MB_OK);

          Step := Step + 1;
          UpdateNativeProgress(
            Format('%d/%d - %s', [Step, TotalSteps, ExpandConstant('{cm:StepStartService}')]),
            'sc start "OCSInventory Agent"');

          if Exec('sc.exe', 'start "OCSInventory Agent"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
            Log(ExpandConstant('{cm:ServiceStartedSuccessfully}'))
          else
            MsgBox(ExpandConstant('{cm:ServiceStartFailed}'), mbError, MB_OK);
        end
        else
          MsgBox(ExpandConstant('{cm:ServiceCreateFailed}'), mbError, MB_OK);
      end
      else if RunNowCheckBox.Checked then
      begin
        Step := Step + 1;
        UpdateNativeProgress(
          Format('%d/%d - %s', [Step, TotalSteps, ExpandConstant('{cm:StepRunAgentNow}')]),
          ExpandConstant('{app}\{#AppExeName}'));

        if Exec(ExpandConstant('{app}\{#AppExeName}'), '', '', SW_HIDE, ewNoWait, ResultCode) then
          Log(ExpandConstant('{cm:OCSInventoryAgentStarted}'))
        else
          MsgBox(ExpandConstant('{cm:FailedToRunOCSInventoryAgent}'), mbError, MB_OK);
      end;
    end;
    UpdateNativeProgress(ExpandConstant('{cm:StepDone}'), '');
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    if Exec('sc.exe', 'stop "OCSInventory Agent"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      if Exec('sc.exe', 'delete "OCSInventory Agent"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      begin
        Log(ExpandConstant('{cm:ServiceDeletedSuccessfully}'));
      end
      else
      begin
        MsgBox(ExpandConstant('{cm:ServiceDeleteFailed}'), mbError, MB_OK);
      end;
    end
    else
    begin
      MsgBox(ExpandConstant('{cm:ServiceStopFailed}'), mbError, MB_OK);
    end;

    if DirExists(STORE_DATA_PATH) then
    begin
      if RemoveDir(STORE_DATA_PATH) then
      begin
        Log(Format(ExpandConstant('{cm:DataDirectoryRemovedSuccessfully}'), [STORE_DATA_PATH]));
      end
      else
      begin
        MsgBox(Format(ExpandConstant('{cm:FailedToRemoveDataDirectory}'), [STORE_DATA_PATH]), mbError, MB_OK);
      end;
    end;
  end;
end;

[CustomMessages]
// Custom messages for the setup wizard
AgentConfigurationPageDescription=Please specify your own agent settings.
AgentConfigurationPageTitle=Agent configuration
AgentMode=Inventory mode
AgentMode1=Remote with template
AgentMode2=Remote without template
AgentMode3=Local with template
AgentMode4=Local without template
AgentModeHelp=#13#10Select the agent inventory mode:#13#10#13#10  • Remote with template: Sends the full inventory to the server.#13#10  • Remote without template: Sends the base inventory to the server.#13#10  • Local with template: Saves the full inventory locally.#13#10  • Local without template: Saves the base inventory locally.
Certificate=Certificate
ConfigurationFileCreatedSuccessfully=Configuration file created successfully: %s
ConnectionDetailsValidated=Connection details validated: URL: %s, Username: %s, Password: *****
DataDirectoryCreatedSuccessfully=Data directory created successfully: %s
DataDirectoryDoesNotExist=Data directory does not exist: %s
DataDirectoryExist=Data directory exists: %s
DataDirectoryRemovedSuccessfully=Data directory removed successfully: %s
ErrorCreatingConfigurationFile=Error creating configuration file.
ErrorCreatingDataDirectory=Error creating data directory.
ErrorMandatoryField=The field %s is mandatory.
FailedToRemoveDataDirectory=Failed to remove data directory: %s
FailedToRunOCSInventoryAgent=Failed to run OCS Inventory Agent.
InstallAsAService=Install agent as a service
InstallingOCSInventoryAgentAsAService=Installing OCS Inventory Agent as a service...
InstallProgressDesc=Please wait while the installer performs the required steps.
InstallProgressTitle=Installation details
InventorySectionTitle=Inventory
LogLevel=Log level
LogLevel0=Critical
LogLevel1=Error
LogLevel2=Warning
LogLevel3=Info
LogLevel4=Debug
OCSInventoryAgentStarted=OCS Inventory Agent started.
Parameters=Parameters: URL: %s, Username: %s, Password: *****, Certificate: %s, Inventory Mode: %d, Log Level: %d, Run Now: %s, Install as a Service: %s
Password=Password
RunningInInteractiveMode=Running in interactive mode.
RunningInSilentMode=Running in silent mode.
RunNow=Run the agent now
RunNowHelp=Run now option is managed automatically if the agent is installed as a service. Remove the service installation to manage this option.
ServerCredentialsGroupTitle=Server credentials (mandatory)
ServerSecurityGroupTitle=Server security
ServiceCreatedSuccessfully=Service created successfully.
ServiceCreateFailed=Failed to create service.
ServiceDeletedSuccessfully=Service deleted successfully.
ServiceDeleteFailed=Failed to delete service.
ServiceDescription=Service starting periodically OCSInventory Agent for Windows.
ServiceDescriptionFailed=Failed to set service description.
ServiceDescriptionSetSuccessfully=Service description set successfully.
ServiceStartedSuccessfully=Service started successfully.
ServiceStartFailed=Failed to start service.
ServiceStopFailed=Failed to stop service.
StartingOCSInventoryAgentSetup=Starting OCS Inventory Agent Setup...
StepCreateDataDir=Creating/validating data directory...
StepCreateService=Creating Windows service...
StepDone=All steps completed.
StepRunAgentNow=Running agent once...
StepSetServiceDesc=Setting service description...
StepStartService=Starting service...
StepUninstallPrevious=Uninstalling previous version...
StepWriteConfig=Writing configuration file...
URL=URL
Username=Username
ValidateCertificate=Validate certificate
VerboseSectionTitle=Verbose
WaitingUserToEnterInputs=Waiting for user to enter inputs...

french.AgentConfigurationPageDescription=Veuillez spécifier vos propres paramètres d'agent.
french.AgentConfigurationPageTitle=Configuration de l'agent
french.AgentMode=Mode d'inventaire
french.AgentMode1=Distant avec modèle
french.AgentMode2=Distant sans modèle
french.AgentMode3=Local avec modèle
french.AgentMode4=Local sans modèle
french.AgentModeHelp=#13#10Séléctionnez le mode d'inventaire de l'agent :#13#10#13#10  • Distant avec modèle : Envoi de l'inventaire complet au serveur.#13#10  • Distant sans modèle : Envoi de l'inventaire base au serveur.#13#10  • Local avec modèle : Sauvegarde de l'inventaire complet en local.#13#10  • Local sans modèle : Sauvegarde de l'inventaire base en local.
french.Certificate=Certificat
french.ConfigurationFileCreatedSuccessfully=Fichier de configuration créé avec succès : %s
french.ConnectionDetailsValidated=Détails de connexion validés : URL : %s, Nom d'utilisateur : %s, Mot de passe : *****
french.DataDirectoryCreatedSuccessfully=Répertoire de données créé avec succès : %s
french.DataDirectoryDoesNotExist=Le répertoire de données n'existe pas : %s
french.DataDirectoryExist=Le répertoire de données existe : %s
french.DataDirectoryRemovedSuccessfully=Répertoire de données supprimé avec succès : %s
french.ErrorCreatingConfigurationFile=Erreur lors de la création du fichier de configuration.
french.ErrorCreatingDataDirectory=Erreur lors de la création du répertoire de données.
french.ErrorMandatoryField=Le champ %s est obligatoire.
french.FailedToRemoveDataDirectory=Échec de la suppression du répertoire de données : %s
french.FailedToRunOCSInventoryAgent=Échec de l'exécution de l'agent OCS Inventory.
french.InstallAsAService=Installer l'agent en tant que service
french.InstallingOCSInventoryAgentAsAService=Installation de l'agent OCS Inventory en tant que service...
french.InstallProgressDesc=Veuillez patienter pendant l'exécution des opérations.
french.InstallProgressTitle=Détails de l'installation
french.InventorySectionTitle=Inventaire
french.LogLevel=Niveau de journalisation
french.LogLevel0=Critique
french.LogLevel1=Erreur
french.LogLevel2=Avertissement
french.LogLevel3=Info
french.LogLevel4=Débogage
french.OCSInventoryAgentStarted=Agent OCS Inventory démarré.
french.Parameters=Paramètres : URL : %s, Nom d'utilisateur : %s, Mot de passe : *****, Certificat : %s, Mode d'inventaire : %d, Niveau de journalisation : %d, Exécuter maintenant : %s, Installer en tant que service : %s
french.Password=Mot de passe
french.RunningInInteractiveMode=Exécution en mode interactif.
french.RunningInSilentMode=Exécution en mode silencieux.
french.RunNow=Exécuter l'agent maintenant
french.RunNowHelp=L'option Exécuter l'agent maintenant est gérée automatiquement si l'agent est installé en tant que service. Supprimez l'installation en tant que service pour gérer cette option.
french.ServerCredentialsGroupTitle=Identifiants serveur (requis)
french.ServerSecurityGroupTitle=Sécurité serveur
french.ServiceCreateFailed=Échec de la création du service.
french.ServiceCreatedSuccessfully=Service créé avec succès.
french.ServiceDeleteFailed=Échec de la suppression du service.
french.ServiceDeletedSuccessfully=Service supprimé avec succès.
french.ServiceDescription=Service démarrant périodiquement l'agent OCSInventory pour Windows.
french.ServiceDescriptionFailed=Échec de la définition de la description du service.
french.ServiceDescriptionSetSuccessfully=Description du service définie avec succès.
french.ServiceStartedSuccessfully=Service démarré avec succès.
french.ServiceStartFailed=Échec du démarrage du service.
french.ServiceStopFailed=Échec de l'arrêt du service.
french.StartingOCSInventoryAgentSetup=Début de l'installation de l'agent OCS Inventory...
french.StepCreateDataDir=Création/vérification du répertoire de données...
french.StepCreateService=Création du service Windows...
french.StepDone=Toutes les opérations sont terminées.
french.StepRunAgentNow=Exécution ponctuelle de l'agent...
french.StepSetServiceDesc=Définition de la description du service...
french.StepStartService=Démarrage du service...
french.StepUninstallPrevious=Désinstallation de la version précédente...
french.StepWriteConfig=Écriture du fichier de configuration...
french.URL=URL
french.Username=Nom d'utilisateur
french.ValidateCertificate=Valider le certificat
french.VerboseSectionTitle=Verbosité
french.WaitingUserToEnterInputs=En attente de l'utilisateur pour entrer les paramètres...
