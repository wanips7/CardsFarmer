{

  https://github.com/wanips7/CardsFarmer

}

unit uCardsFarmer;

// {$DEFINE OBJECT_EVENTS}

interface

{$SCOPEDENUMS ON}

uses
  Winapi.Windows, System.SysUtils, Messages, RegularExpressions, System.Net.HttpClient,
  System.Classes, System.Generics.Collections, uSteamAuth;

const
  WM_CLOSE_FARM_SERVICE = WM_USER + 1;

type
  TFarmMode = (Separately, Together);
  
type
  TGameInfo = record
    Name: string;
    Id: Integer;
    CardsLeft: Integer;
    CardsTotal: Integer;
    PlayTime: Single;
  end;

type
  PLoginData = ^TLoginData;
  TLoginData = record
    Login: string;
    Password: string;
    Cookie: string;
  end;

Type
  TFarmInfo = record
    CardsLeft: Cardinal;
    CardsTotal: Cardinal;
    GamesLeft: Cardinal;
  end;

Type
  TFarmServiceAppInfo = record
    ProcessHandle: DWORD;
    ThreadHandle: DWORD;
    ThreadId: DWORD;
  end;

type
  TStringArray = TArray<string>;

type
  TGameInfoList = TArray<TGameInfo>;

type
  ECardsFarmerException = class (Exception);

type
  TOnLoadBadgePage = procedure({$IFDEF OBJECT_EVENTS}Sender: TObject; {$ENDIF}
    const Loaded, Total: Integer){$IFDEF OBJECT_EVENTS} of object{$ENDIF};
  TOnLogin = procedure({$IFDEF OBJECT_EVENTS}Sender: TObject; {$ENDIF}
    const Login: string){$IFDEF OBJECT_EVENTS} of object{$ENDIF};
  TOnLogged = procedure({$IFDEF OBJECT_EVENTS}Sender: TObject; {$ENDIF}
    const Nickname: string){$IFDEF OBJECT_EVENTS} of object{$ENDIF};
  TOnStart = procedure({$IFDEF OBJECT_EVENTS}Sender: TObject; {$ENDIF}
    const FarmMode: TFarmMode){$IFDEF OBJECT_EVENTS} of object{$ENDIF};
  TOnFinish = procedure{$IFDEF OBJECT_EVENTS}(Sender: TObject) of object{$ENDIF};
  TOnChangeGameList = procedure({$IFDEF OBJECT_EVENTS}Sender: TObject; {$ENDIF}
    const GameInfoList: TGameInfoList){$IFDEF OBJECT_EVENTS} of object{$ENDIF};
  TOnTimeLeft = procedure({$IFDEF OBJECT_EVENTS}Sender: TObject; {$ENDIF}
    const SecondsLeft: Integer){$IFDEF OBJECT_EVENTS} of object{$ENDIF};
  TOnUpdateFarmInfo = procedure({$IFDEF OBJECT_EVENTS}Sender: TObject; {$ENDIF}
    const FarmInfo: TFarmInfo){$IFDEF OBJECT_EVENTS} of object{$ENDIF};

  TOnRequired2FA = procedure({$IFDEF OBJECT_EVENTS}Sender: TObject; {$ENDIF}
    var Code: string){$IFDEF OBJECT_EVENTS} of object{$ENDIF};

type
  TFarmServices = class
  strict private
    FOnChangeGameList: TOnChangeGameList;
    FOnTimeLeft: TOnTimeLeft;
    FAppDir: string;
    FAppInfoList: TList<TFarmServiceAppInfo>;
    FStop: Boolean;
    procedure DoChangeGameList(const GameInfoList: TGameInfoList);
    procedure DoTimeLeft(const SecondsLeft: Integer);
    procedure Wait(const Seconds: Integer);
    procedure StartFarmService(const AppId: Cardinal);
  public
    property OnChangeGameList: TOnChangeGameList read FOnChangeGameList write FOnChangeGameList;
    property OnTimeLeft: TOnTimeLeft read FOnTimeLeft write FOnTimeLeft;
    constructor Create(const AppDir: string);
    destructor Destroy; override;
    procedure Start(GameInfoList: TGameInfoList; const Limit: Integer = 0); overload;
    procedure Start(const GameInfo: TGameInfo); overload;
    procedure Stop;
  end;

type
  EParseException = class(Exception);

type
  TSteamDataParser = record
    function ParseGamesWithDrop(const BadgesPage: string): TGameInfoList;
    function ParseBadgePageCount(const BadgesPage: string): Integer;
    function ParseNickname(const MainPage: string): string;
    function ParseProfileUrl(const MainPage: string): string;
  end;

type
  TCardsFarmer = class
  strict private
    FOnLoadBadgePage: TOnLoadBadgePage;
    FOnStart: TOnStart;
    FOnFinish: TOnFinish;
    FOnLogin: TOnLogin;
    FOnLogged: TOnLogged;
    FOnUpdateFarmInfo: TOnUpdateFarmInfo;
    FOnRequired2FA: TOnRequired2FA;
    FStop: Boolean;
    FSteamAuth: TSteamAuth;
    FFarmInfo: TFarmInfo;
    FFarmServices: TFarmServices;
    FHttpClient: THTTPClient;
    FLoginData: PLoginData;
    FIsLoggedIn: Boolean;
    FProfileUrl: string;
    FParser: TSteamDataParser;
    procedure DoLogin(const Login: string);
    procedure DoLogged(const Nickname: string);
    procedure DoLoadBadgePage(const Loaded, Total: Integer);
    procedure DoStart(const FarmMode: TFarmMode);
    procedure DoFinish;
    procedure DoUpdateFarmInfo(const FarmInfo: TFarmInfo);
    procedure DoRequired2FA(var Code: string);
    procedure ConfirmationRequiredEventHandler(Sender: TObject; ConfirmationType: TSteamAuth.TConfirmationType);
    function GetGameInfoList: TGameInfoList;
    function GetPlayedLessTwoHours(const GameInfoList: TGameInfoList): TGameInfoList;
    function GetGameIdList(const GameInfoList: TGameInfoList): TStringArray;
    procedure StartFarm(Mode: TFarmMode);
    function TryLogin: Boolean;
    procedure SetHttpClientHeaders;
    function HasLoginData: Boolean;
  public
    property OnLogin: TOnLogin read FOnLogin write FOnLogin;
    property OnLogged: TOnLogged read FOnLogged write FOnLogged;
    property OnLoadBadgePage: TOnLoadBadgePage read FOnLoadBadgePage write FOnLoadBadgePage;
    property OnStart: TOnStart read FOnStart write FOnStart;
    property OnFinish: TOnFinish read FOnFinish write FOnFinish;
    property OnUpdateFarmInfo: TOnUpdateFarmInfo read FOnUpdateFarmInfo write FOnUpdateFarmInfo;
    property OnRequired2FA: TOnRequired2FA read FOnRequired2FA write FOnRequired2FA;
    property FarmServices: TFarmServices read FFarmServices;
    property FarmInfo: TFarmInfo read FFarmInfo;
    constructor Create(const AppDir: string);
    destructor Destroy; override;
    procedure Start(const FarmMode: TFarmMode; LoginData: PLoginData);
    procedure Stop;
  end;
  
implementation

uses
  System.IOUtils;

const
  FARM_SERVICE_FILENAME = 'CardsFarmerService.exe';
  APP_RUN_LIMIT = 10;
  DEFAULT_WAIT_TIME = 300;
  TRY_REQUEST_COUNT = 3;
  USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.128 Safari/537.36';
  HTTP_OK = 200;

function ExecApp(const FileName, Params: string; const CreationFlags: DWORD; var StartupInfo: TStartupInfo; var ProcessInfo: TProcessInformation): Boolean; overload;
var
  Line: PWideChar;
begin
  if Params = '' then
    Line := PChar(FileName)
  else
    Line := PChar(FileName + ' ' + Params);

  Result := CreateProcess(nil, Line, nil, nil, False, CreationFlags, nil, nil, StartupInfo, ProcessInfo);
end;

function ExecApp(const FileName, Params: string; var StartupInfo: TStartupInfo; var ProcessInfo: TProcessInformation): Boolean; overload;
begin
  ExecApp(FileName, Params, 0, StartupInfo, ProcessInfo);
end;

function ExecApp(const FileName, Params: string): Boolean; overload;
var
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
begin
  StartupInfo := Default(TStartupInfo);
  ProcessInfo := Default(TProcessInformation);
  Result := ExecApp(FileName, Params, StartupInfo, ProcessInfo);
end;

function ExtractBetween(const Text, TagFirst, TagLast: string; Offset: Integer = 1): string;
var
  TFPos, TLPos: Integer;
begin
  Result := '';
  TFPos := Pos(TagFirst, Text, Offset);
  TLPos := Pos(TagLast, Text, TFPos + Length(TagFirst));

  if (TLPos <> 0) and (TFPos <> 0) then    
    Result := Copy(Text, TFPos + Length(TagFirst), TLPos - TFPos - Length(TagFirst));
end;

procedure RaiseException(const Text: string);
begin
  raise ECardsFarmerException.Create(Text);
end;

procedure RaiseParseException(const Text: string);
begin
  raise EParseException.Create('Parse error. ' + Text);
end;

{ TFarmerServices }

constructor TFarmServices.Create(const AppDir: string);
begin
  FStop := False;
  FAppDir := AppDir;
  FOnTimeLeft := nil;
  FOnChangeGameList := nil;
  FAppInfoList := TList<TFarmServiceAppInfo>.Create;
end;

destructor TFarmServices.Destroy;
begin
  Stop;
  FAppInfoList.Free;
  inherited;
end;

procedure TFarmServices.DoChangeGameList(const GameInfoList: TGameInfoList);
begin
  if Assigned(FOnChangeGameList) then
    FOnChangeGameList({$IFDEF OBJECT_EVENTS}Self, {$ENDIF}GameInfoList);
end;

procedure TFarmServices.DoTimeLeft(const SecondsLeft: Integer);
begin
  if Assigned(FOnTimeLeft) then
    FOnTimeLeft({$IFDEF OBJECT_EVENTS}Self, {$ENDIF}SecondsLeft);
end;

procedure TFarmServices.Start(GameInfoList: TGameInfoList; const Limit: Integer);
var
  GameInfo: TGameInfo;
  Seconds: Integer;
begin
  FStop := False;

  Stop;

  if (Limit > 0) and (Length(GameInfoList) <= Limit) then
    SetLength(GameInfoList, Limit);

  for GameInfo in GameInfoList do
  begin
    StartFarmService(GameInfo.Id);
  end;

  DoChangeGameList(GameInfoList);

  Wait(DEFAULT_WAIT_TIME);

  Stop;
end;

procedure TFarmServices.Start(const GameInfo: TGameInfo);
begin
  Start([GameInfo]);
end;

procedure TFarmServices.StartFarmService(const AppId: Cardinal);
var
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  CreationFlags: DWORD;
  FarmServiceAppInfo: TFarmServiceAppInfo;
begin
  if not FileExists(FAppDir + FARM_SERVICE_FILENAME) then
    RaiseException('Farm service is not exist.');

  CreationFlags := CREATE_NO_WINDOW or NORMAL_PRIORITY_CLASS;
  StartupInfo := Default(TStartupInfo);
  ProcessInfo := Default(TProcessInformation);

  if ExecApp(FAppDir + FARM_SERVICE_FILENAME, AppId.ToString, CreationFlags, StartupInfo, ProcessInfo) then
  begin
    FarmServiceAppInfo.ProcessHandle := ProcessInfo.hProcess;
    FarmServiceAppInfo.ThreadHandle := ProcessInfo.hThread;
    FarmServiceAppInfo.ThreadId := ProcessInfo.dwThreadId;

    FAppInfoList.Add(FarmServiceAppInfo);

  end
    else
  RaiseException('Farm service start error.');

end;

procedure TFarmServices.Stop;
var
  AppInfo: TFarmServiceAppInfo;
begin
  for AppInfo in FAppInfoList do
  begin
    PostThreadMessage(AppInfo.ThreadId, WM_CLOSE_FARM_SERVICE, 0, 0);
    CloseHandle(AppInfo.ProcessHandle);
    CloseHandle(AppInfo.ThreadHandle);
  end;

  FAppInfoList.Clear;
end;

procedure TFarmServices.Wait(const Seconds: Integer);
var
  i: Integer;
begin
  for i := Seconds downto 0 do
  begin
    if FStop then
      Break;

    Sleep(MSecsPerSec);

    DoTimeLeft(i);
  end;

end;

{ TCardsFarmer }

procedure TCardsFarmer.ConfirmationRequiredEventHandler(Sender: TObject; ConfirmationType: TSteamAuth.TConfirmationType);
var
  Code2FA: string;
begin
  DoRequired2FA(Code2FA);

  FSteamAuth.TwoFactorCode := Code2FA;
end;

constructor TCardsFarmer.Create(const AppDir: string);
begin
  FOnStart := nil;
  FOnFinish := nil;
  FOnLoadBadgePage := nil;
  FOnLogin := nil;
  FOnLogged := nil;
  FOnUpdateFarmInfo := nil;
  FOnRequired2FA := nil;
  FProfileUrl := '';

  FFarmInfo := Default(TFarmInfo);
  FStop := False;
  FIsLoggedIn := False;

  FSteamAuth := TSteamAuth.Create;
  FSteamAuth.OnConfirmationRequired := ConfirmationRequiredEventHandler;

  FHttpClient := THTTPClient.Create;
  FHttpClient.UserAgent := USER_AGENT;

  FFarmServices := TFarmServices.Create(AppDir);

  SetHttpClientHeaders;
end;

destructor TCardsFarmer.Destroy;
begin
  FSteamAuth.Free;
  FHttpClient.Free;
  FFarmServices.Free;
  inherited;
end;

procedure TCardsFarmer.DoFinish;
begin
  if Assigned(FOnFinish) then
    FOnFinish({$IFDEF OBJECT_EVENTS}Self{$ENDIF});
end;

procedure TCardsFarmer.DoLoadBadgePage(const Loaded, Total: Integer);
begin
  if Assigned(FOnLoadBadgePage) then
    FOnLoadBadgePage({$IFDEF OBJECT_EVENTS}Self, {$ENDIF}Loaded, Total);
end;

procedure TCardsFarmer.DoLogin(const Login: string);
begin
  if Assigned(FOnLogin) then
    FOnLogin({$IFDEF OBJECT_EVENTS}Self, {$ENDIF}Login);
end;

procedure TCardsFarmer.DoLogged(const Nickname: string);
begin
  if Assigned(FOnLogged) then
    FOnLogged({$IFDEF OBJECT_EVENTS}Self, {$ENDIF}Nickname);
end;

procedure TCardsFarmer.DoRequired2FA(var Code: string);
begin
  if Assigned(FOnRequired2FA) then
    FOnRequired2FA({$IFDEF OBJECT_EVENTS}Self, {$ENDIF}Code);
end;

procedure TCardsFarmer.DoStart(const FarmMode: TFarmMode);
begin
  if Assigned(FOnStart) then
    FOnStart({$IFDEF OBJECT_EVENTS}Self, {$ENDIF}FarmMode);
end;

procedure TCardsFarmer.DoUpdateFarmInfo(const FarmInfo: TFarmInfo);
begin
  if Assigned(FOnUpdateFarmInfo) then
    FOnUpdateFarmInfo({$IFDEF OBJECT_EVENTS}Self, {$ENDIF}FarmInfo);
end;

function TCardsFarmer.GetGameIdList(const GameInfoList: TGameInfoList): TStringArray;
var
  GameInfo: TGameInfo;
begin
  Result := [];

  for GameInfo in GameInfoList do
    Result := Result + [GameInfo.Id.ToString];
end;

function TCardsFarmer.GetGameInfoList: TGameInfoList;
var
  Response: IHttpResponse;
  PageCount: Integer;
  CurrentPage: Integer;
  GameInfo: TGameInfo;
  Body: string;
  Url: string;
begin
  Result := [];
  PageCount := 0;
  CurrentPage := 0;
  FFarmInfo := Default(TFarmInfo);

  if not FIsLoggedIn then
    Exit;

  repeat
    Inc(CurrentPage);

    Url := Format(FProfileUrl + 'badges/?p=%d', [CurrentPage]);
    Response := FHttpClient.Get(Url);

    if Response.StatusCode = HTTP_OK then
    begin
      Body := Response.ContentAsString;

      if CurrentPage = 1 then
        PageCount := FParser.ParseBadgePageCount(Body);

      DoLoadBadgePage(CurrentPage, PageCount);
      
      Result := Result + FParser.ParseGamesWithDrop(Body);
    end;
    
  until (CurrentPage >= PageCount);

  for GameInfo in Result do
  begin
    Inc(FFarmInfo.CardsLeft, GameInfo.CardsLeft);
    Inc(FFarmInfo.CardsTotal, GameInfo.CardsTotal);
  end;

  FFarmInfo.GamesLeft := Length(Result);
end;

function TCardsFarmer.GetPlayedLessTwoHours(const GameInfoList: TGameInfoList): TGameInfoList;
var
  GameInfo: TGameInfo;
begin
  Result := [];

  for GameInfo in GameInfoList do
  begin
    if GameInfo.PlayTime <= 2 then
      Result := Result + [GameInfo];
  end;
end;



function TCardsFarmer.HasLoginData: Boolean;
begin
  Result := not FLoginData.Login.IsEmpty and not FLoginData.Password.IsEmpty;
end;

function TCardsFarmer.TryLogin: Boolean;
var
  Response: IHttpResponse;
  Body: string;
  LoginResult: TSteamAuth.TLoginResult;
  Code2FA: string;
  Nickname: string;
  s: string;
begin
  Result := FSteamAuth.IsValidCookie(FLoginData.Cookie);
  Code2FA := '';

  if not Result then
  begin
    DoLogin(FLoginData.Login);

    LoginResult := FSteamAuth.Login(FLoginData.Login, FLoginData.Password);

    Result := FSteamAuth.LoggedIn;

    if Result then
      FLoginData.Cookie := FSteamAuth.SessionData.Cookie;
  end;

  FIsLoggedIn := Result;

  if Result then
  begin
    for s in FLoginData.Cookie.Split(['; ']) do
    begin
      FHttpClient.CookieManager.AddServerCookie(s, TSteamAPI.COMMUNITY_BASE);
    end;

    Response := FHttpClient.Get(TSteamAPI.COMMUNITY_BASE);
    Body := Response.ContentAsString;

    if Response.StatusCode = HTTP_OK then
    begin
      Nickname := FParser.ParseNickname(Body);
      FProfileUrl := FParser.ParseProfileUrl(Body);
    end;

    DoLogged(Nickname);
  end;

end;

procedure TCardsFarmer.SetHttpClientHeaders;
begin
  FHttpClient.CustHeaders
    .Clear
    .Add('Connection', 'keep-alive')
    .Add('Cache-Control', 'no-cache')
    .Add('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9')
    .Add('Accept-Encoding', 'gzip, deflate, br')
    .Add('Accept-Language', 'q=0.9,en-US;q=0.8,en;q=0.7');

end;

procedure TCardsFarmer.Start(const FarmMode: TFarmMode; LoginData: PLoginData);
begin
  FLoginData := LoginData;

  if HasLoginData then
  begin
    if TryLogin then
    begin
      StartFarm(FarmMode);
    end
      else
    RaiseException('Can''t login.');

  end
    else
  RaiseException('No login data.');

end;

procedure TCardsFarmer.StartFarm(Mode: TFarmMode);
var
  GameInfoList: TGameInfoList;
  GameInfo: TGameInfo;
begin
  FStop := False;

  DoStart(Mode);

  repeat
    GameInfoList := GetGameInfoList;

    DoUpdateFarmInfo(FarmInfo);

    if Mode = TFarmMode.Separately then
    begin
      for GameInfo in GameInfoList do
      begin
        FFarmServices.Start(GameInfo);
      end;

    end
      else
    begin
      GameInfoList := GetPlayedLessTwoHours(GameInfoList);

      if Length(GameInfoList) > 0 then
      begin
        FFarmServices.Start(GameInfoList, APP_RUN_LIMIT);
      end
        else
      Mode := TFarmMode.Separately;

    end;

  until (Length(GameInfoList) = 0) or FStop;

  DoFinish;
end;

procedure TCardsFarmer.Stop;
begin
  FStop := True;
  FFarmServices.Stop;
end;

{ TSteamDataParser }

function TSteamDataParser.ParseGamesWithDrop(const BadgesPage: string): TGameInfoList;

  function GetMatch(const Text, Pattern: string): string;
  var
    RegEx: TRegEx;
    Match: TMatch;
  begin
    RegEx := TRegEx.Create(Pattern, [roSingleLine]);
    Match := RegEx.Match(Text);

    if Match.Success then
      Result := Match.Value
    else
      Result := '';
  end;

const
  START_TAG = '<div id="image_group_scroll_badge_images_gamebadge_';
  END_TAG = '<div style="clear: both;"></div>';

var
  Info: TGameInfo;
  Text: string;
  s: string;
  Offset: Integer;
  i: Integer;
begin
  Result := [];
  Offset := 1;

  repeat
    Info := Default(TGameInfo);

    Text := ExtractBetween(BadgesPage, START_TAG, END_TAG, Offset);
    if Text = '' then
      Break;

    Offset := Pos(END_TAG, BadgesPage, Offset) + END_TAG.Length;

    Info.Name := ExtractBetween(Text, '<div class="badge_title">', '&nbsp').Trim;

    Info.Id := ExtractBetween(Text, '/gamecards/', '/').ToInteger;

    s := ExtractBetween(Text, '<div class="card_drop_info_header">', '</div>');
    if s <> '' then
      Info.CardsTotal := GetMatch(s, '\d\d?').ToInteger
    else
      Continue;

    s := ExtractBetween(Text, '<span class="progress_info_bold">', '</span>');
    s := GetMatch(s, '\d\d?');
    if s <> '' then
      Info.CardsLeft := s.ToInteger
    else
      Info.CardsLeft := 0;

    s := ExtractBetween(Text, '<div class="badge_title_stats_playtime">', '</div>');
    s := GetMatch(s, '[0-9]+\.[0-9]+').Replace('.', ',');
    if s <> '' then
      Info.PlayTime := s.ToSingle
    else
      Info.PlayTime := 0;

    if Info.CardsLeft > 0 then
      Result := Result + [Info];

  until Text = '';

end;

function TSteamDataParser.ParseNickname(const MainPage: string): string;
begin
  Result := ExtractBetween(MainPage, 'data-miniprofile="', '</div>');
  Result := ExtractBetween(Result, '">', '</a>');

  if Result.IsEmpty then
    RaiseParseException('Can''t parse nickname.');
end;

function TSteamDataParser.ParseProfileUrl(const MainPage: string): string;
begin
  Result := ExtractBetween(MainPage, '<div class="responsive_menu_user_area">', '</div>');
  Result := ExtractBetween(Result, '<a href="', '">');

  if Result.IsEmpty then
    RaiseParseException('Can''t parse profile url.');
end;

function TSteamDataParser.ParseBadgePageCount(const BadgesPage: string): Integer;
var
  s: string;
  Offset: Integer;
begin
  Result := 1;

  s := ExtractBetween(BadgesPage, '<div class="pageLinks">', '</div>');

  if not s.IsEmpty then
  begin
    Offset := s.LastIndexOf('pagelink');

    s := ExtractBetween(s, '">', '<', Offset);

    if not TryStrToInt(s, Result) then
      RaiseParseException('Can''t parse badge page count.');
  end;

end;



end.
