{

  A program for farm Steam cards.

  Version 0.7

  https://github.com/wanips7/CardsFarmer

  ========================================
  Parameters:
  -l -login         Set login
  -p -pass          Set password
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
  System.IOUtils,
  uSteamAuth in '..\SteamAuth\uSteamAuth.pas',
  uRSA in '..\SteamAuth\uRSA.pas',
  uSteamAPI in 'uSteamAPI.pas',
  uCardsFarmer in 'uCardsFarmer.pas',
  uClp in '..\clp\uClp.pas'; { https://github.com/wanips7/clp }

const
  APP_VERSION = '0.7';
  APP_TITLE = 'Cards Farmer ' + APP_VERSION;
  COOKIES_FOLDER = 'Cookies\';

const
  PARAM_LOGIN: TArray<string> = ['l', 'login'];
  PARAM_PASSWORD: TArray<string> = ['p', 'pass', 'password'];
  PARAM_FARM_SEPARATELY: TArray<string> = ['fs'];
  PARAM_FARM_TOGETHER: TArray<string> = ['ft'];
  PARAM_HELP: TArray<string> = ['h', 'help'];

var
  AppPath: string = '';
  AppDir: string = '';
  CookieFileName: string = '';
  FarmMode: TFarmMode = TFarmMode.Together;
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

procedure LoginEventHandler(const Nickname: string);
begin
  PrintF('Logged as: %s', [Nickname]);
end;

procedure LoadBadgePageEventHandler(const Loaded, Total: Integer);
begin
  PrintF('Badge pages loaded: %d/%d', [Loaded, Total]);
end;

procedure TimeLeftEventHandler(const SecondsLeft: Integer);
var
  Time: string;
begin
  Time := FormatDateTime('nn:ss', SecondsLeft / SecsPerDay);

  Write(#13 + 'Time left: ' + Time);

  if SecondsLeft = 0 then
    Writeln;
end;

procedure UpdateFarmInfoEventHandler(const FarmInfo: TFarmInfo);
begin
  PrintF('Game information has been updated. Cards left: %d/%d. Games left: %d. ',
    [FarmInfo.CardsLeft, FarmInfo.CardsTotal, FarmInfo.GamesLeft]);
end;

procedure ChangeGameListEventHandler(const GameInfoList: TGameInfoList);
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

procedure StartEventHandler(const FarmMode: TFarmMode);
begin
  Print('Start farming.');
end;

procedure FinishEventHandler;
begin
  Print('Done.');
end;

procedure Required2FAEventHandler(var Code: string);
begin
  Print('Enter 2FA code:');

  Readln(Code);
end;

procedure LoadCookie;
begin
  if not DirectoryExists(AppDir + COOKIES_FOLDER) then
    CreateDir(AppDir + COOKIES_FOLDER);

  CookieFileName := AppDir + COOKIES_FOLDER + LoginData.Login + '.dat';

  if not LoginData.Login.IsEmpty then
    if FileExists(CookieFileName) then
    begin
      LoginData.Cookie := TFile.ReadAllText(CookieFileName);
    end;
end;

procedure SaveCookie;
begin
  if not LoginData.Cookie.IsEmpty then
  begin
    TFile.WriteAllText(CookieFileName, LoginData.Cookie);
  end;
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

  SaveCookie;

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

  LoginData := Default(TLoginData);

  Clp := TCommandLineParser.Create;

  CardsFarmer := TCardsFarmer.Create(AppDir);
  CardsFarmer.OnStart := StartEventHandler;
  CardsFarmer.OnFinish := FinishEventHandler;
  CardsFarmer.OnLogin := LoginEventHandler;
  CardsFarmer.OnLoadBadgePage := LoadBadgePageEventHandler;
  CardsFarmer.OnUpdateFarmInfo := UpdateFarmInfoEventHandler;
  CardsFarmer.OnRequired2FA := Required2FAEventHandler;
  CardsFarmer.FarmServices.OnChangeGameList := ChangeGameListEventHandler;
  CardsFarmer.FarmServices.OnTimeLeft := TimeLeftEventHandler;

end;

procedure AddCommandLineRules;
var
  Rule: TSyntaxRule;
begin
  Clp.SyntaxRules.Clear;

  Rule := TSyntaxRule.Create(PARAM_LOGIN, rcRequired);
  Rule.Values.New([], 1, vtAny);
  Rule.Description := 'Set Steam account login.';
  Clp.SyntaxRules.Add(Rule);

  Rule := TSyntaxRule.Create(PARAM_PASSWORD, rcRequired);
  Rule.Values.New([], 1, vtAny);
  Rule.Description := 'Set Steam account password.';
  Clp.SyntaxRules.Add(Rule);

  Rule := TSyntaxRule.Create(PARAM_FARM_SEPARATELY, rcOptional);
  Rule.Description := 'Farm separately.';
  Clp.SyntaxRules.Add(Rule);

  Rule := TSyntaxRule.Create(PARAM_FARM_TOGETHER, rcOptional);
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

  if Clp.Params.Contains(PARAM_LOGIN, Param) then
  begin
    LoginData.Login := Param.Values.First.Text;
  end;

  if Clp.Params.Contains(PARAM_PASSWORD, Param) then
  begin
    LoginData.Password := Param.Values.First.Text;
  end;

  if Clp.Params.Contains(PARAM_FARM_SEPARATELY) then
  begin
    FarmMode := TFarmMode.Separately;
  end
    else
  if Clp.Params.Contains(PARAM_FARM_TOGETHER) then
  begin
    FarmMode := TFarmMode.Together;
  end;

  LoadCookie;

  CardsFarmer.Start(FarmMode, @LoginData);


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
  AddCommandLineRules;

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

