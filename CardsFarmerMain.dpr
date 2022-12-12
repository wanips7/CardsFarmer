{

  A program for farm cards of Steam games.

  Version 0.4

  https://github.com/wanips7/CardsFarmer

  ==================================
  Parameters:
  -cf "filename"    Set config file
  -fs               Farm separately
  -ft               Farm together

}

program CardsFarmerMain;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils,
  System.IniFiles,
  uSteamAPI in 'uSteamAPI.pas',
  uCardsFarmer in 'uCardsFarmer.pas',
  uClp in '..\clp\uClp.pas'; { https://github.com/wanips7/clp }

const
  APP_VERSION = '0.4';
  APP_TITLE = 'Cards Farmer ' + APP_VERSION;

const
  PARAM_CONFIG_FILE: TArray<string> = ['cf', 'config'];
  PARAM_IDLE_SEPARATELY: TArray<string> = ['fs'];
  PARAM_IDLE_TOGETHER: TArray<string> = ['ft'];
  PARAM_HELP: TArray<string> = ['h', 'help'];

var
  AppPath: string;
  AppDir: string;
  ConfigFilePath: string;
  IdleMode: TFarmMode = fmTogether;
  LoginData: TLoginData;
  CardsFarmer: TCardsFarmer = nil;
  Clp: TCommandLineParser = nil;

procedure Print(const Value: string);
begin
  Writeln(FormatDateTime('[hh:nn:ss] ', Now) + Value);
end;

procedure PrintF(const Value: string; const Args: array of const);
begin
  Print(Format(Value, Args));
end;

procedure RaiseException(const Value: string);
begin
  raise Exception.Create(Value);
end;

procedure OnLogin(const Login: string);
begin
  PrintF('Logged as: %s', [Login]);
end;

procedure OnLoadBadgePage(const Loaded, Total: Integer);
begin
  PrintF('Badge pages loaded: %d/%d', [Loaded, Total]);
end;

procedure OnTimeLeft(const SecondsLeft: Integer);
var
  Time: string;
begin
  Time := FormatDateTime('nn:ss', SecondsLeft / SecsPerDay);

  Write(#13 + 'Time left: ' + Time);

  if SecondsLeft = 0 then
    Writeln;
end;

procedure OnUpdateFarmInfo(const FarmInfo: TFarmInfo);
begin
  PrintF('Game information has been updated. Cards left: %d/%d. Games left: %d. ',
    [FarmInfo.CardsLeft, FarmInfo.CardsTotal, FarmInfo.GamesLeft]);
end;

procedure OnChangeGameList(const GameInfoList: TGameInfoList);
var
  Text: string;
  GameInfo: TGameInfo;
begin
  Text := 'Farming... Game list:';

  for GameInfo in GameInfoList do
  begin
    Text := Text + CRLF + Format('%s. Cards left: %d/%d ',
      [GameInfo.Name, GameInfo.CardsLeft, GameInfo.CardsTotal]);
  end;

  Print(Text);
end;

procedure OnStart(const FarmMode: TFarmMode);
begin
  Print('Start farming.');
end;

procedure OnFinish;
begin
  Print('Done.');
end;

procedure ClearConsole;
var
  hStdOut: HWND;
  ScrBufInfo: TConsoleScreenBufferInfo;
  Coord: TCoord;
  z: Integer;
begin
  hStdOut := GetStdHandle(STD_OUTPUT_HANDLE);
  GetConsoleScreenBufferInfo(hStdOut, ScrBufInfo);

  for z := 1 to ScrBufInfo.dwSize.Y do
    WriteLn;

  Coord.X := 0;
  Coord.Y := 0;
  SetConsoleCursorPosition(hStdOut, Coord);
  CloseHandle(hStdOut);
end;

procedure Deinit;
begin
  if Assigned(CardsFarmer) then
  begin
    CardsFarmer.Stop;
    CardsFarmer.Free;
  end;

  uSteamAPI.Shutdown;
  Clp.Free;
end;

function ConsoleEventProc(CtrlType: DWORD): BOOL; stdcall;
begin
  if (CtrlType = CTRL_CLOSE_EVENT) then
  begin
    Deinit;
  end;

  Result := True;
end;

procedure Init;
begin
  AppPath := ParamStr(0);
  AppDir := ExtractFilePath(AppPath);

  SetConsoleCtrlHandler(@ConsoleEventProc, True);
  SetConsoleTitle(Pchar(APP_TITLE));

  Clp := TCommandLineParser.Create;

  CardsFarmer := TCardsFarmer.Create(AppDir);
  CardsFarmer.OnStart := OnStart;
  CardsFarmer.OnFinish := OnFinish;
  CardsFarmer.OnLogin := OnLogin;
  CardsFarmer.OnLoadBadgePage := OnLoadBadgePage;
  CardsFarmer.OnUpdateFarmInfo := OnUpdateFarmInfo;
  CardsFarmer.FarmServices.OnChangeGameList := OnChangeGameList;
  CardsFarmer.FarmServices.OnTimeLeft := OnTimeLeft;

end;

function LoadConfig(const FilePath: string; out LoginData: TLoginData): Boolean;
var
  Reader: TIniFile;
begin
  Result := False;
  LoginData := Default(TLoginData);

  if FileExists(FilePath) then
  begin
    Reader := TIniFile.Create(FilePath);

    LoginData.SteamLoginSecure := Reader.ReadString('Config', 'SteamLoginSecure', '');
    LoginData.SteamParental := Reader.ReadString('Config', 'SteamParental', '');

    Result := (LoginData.SteamLoginSecure <> '');

    Reader.Free;
  end;

end;

procedure RegisterSyntaxRules;
var
  Rule: TSyntaxRule;
begin
  Clp.SyntaxRules.Clear;

  Rule := TSyntaxRule.Create(PARAM_CONFIG_FILE, rcRequired);
  Rule.Values.New([], 1, vtAny);
  Rule.Description := 'Set config file.';
  Clp.SyntaxRules.Add(Rule);

  Rule := TSyntaxRule.Create(PARAM_IDLE_SEPARATELY, rcOptional);
  Rule.Description := 'Farm separately.';
  Clp.SyntaxRules.Add(Rule);

  Rule := TSyntaxRule.Create(PARAM_IDLE_TOGETHER, rcOptional);
  Rule.Description := 'Farm together.';
  Clp.SyntaxRules.Add(Rule);

  Rule := TSyntaxRule.Create(PARAM_HELP, rcOptional);
  Rule.Description := 'Show help.';
  Clp.SyntaxRules.Add(Rule);

end;

procedure ExecCommands;
var
  Param: TParam;
begin
  if Clp.Params.Contains(PARAM_HELP) then
  begin
    Writeln('Help screen:');
    Writeln(Clp.GetHelpText);
    Exit;
  end;

  if Clp.Params.Contains(PARAM_CONFIG_FILE, Param) then
  begin
    ConfigFilePath := Param.Values.First.Text;
  end
    else
  if Clp.Params.Contains(PARAM_IDLE_SEPARATELY) then
  begin
    IdleMode := fmSeparately;
  end
    else
  if Clp.Params.Contains(PARAM_IDLE_TOGETHER) then
  begin
    IdleMode := fmTogether;
  end;

  if LoadConfig(ConfigFilePath, LoginData) then
  begin
    CardsFarmer.Start(IdleMode, LoginData);

  end
    else
  RaiseException('Can''t load the config file.');

end;

procedure InitSteamApi;
begin
  Print('Try to init Steam api...');

  if uSteamAPI.Initialize(AppDir + STEAM_API_DLL) then
  begin
    Print('Ok.');

    if not uSteamAPI.SteamAPI_IsSteamRunning then
      RaiseException('Steam is not running.');

  end
    else
  RaiseException('Can''t init Steam api.');
end;

begin
  Init;
  RegisterSyntaxRules;

  try

    if Clp.Parse then
    begin
      InitSteamApi;
      ExecCommands;

    end
      else
    begin
      Print('Error: ' + Clp.ErrorMsg);
    end;

  except
    on E: Exception do
      Print('Error: ' + E.Message);
  end;

  Readln;

end.

