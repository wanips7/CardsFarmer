{

  https://github.com/wanips7/CardsFarmer

}

unit uCardsFarmer;

// {$DEFINE OBJECT_EVENTS}

interface

uses
  Winapi.Windows, System.SysUtils, Messages, RegularExpressions, System.Net.HttpClient,
  System.Classes, System.Generics.Collections;

const
  WM_CLOSE_FARM_SERVICE = WM_USER + 1;

type
  TFarmMode = (fmSeparately, fmTogether);
  
type
  TGameInfo = record
    Name: string;
    Id: Integer;
    CardsLeft: Integer;
    CardsTotal: Integer;
    PlayTime: Single;
  end;

Type
  TLoginData = record
    SteamLoginSecure: string;
    SteamParental: string;
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
  TOnStart = procedure({$IFDEF OBJECT_EVENTS}Sender: TObject; {$ENDIF}
    const FarmMode: TFarmMode){$IFDEF OBJECT_EVENTS} of object{$ENDIF};
  TOnFinish = procedure{$IFDEF OBJECT_EVENTS}(Sender: TObject) of object{$ENDIF};
  TOnChangeGameList = procedure({$IFDEF OBJECT_EVENTS}Sender: TObject; {$ENDIF}
    const GameInfoList: TGameInfoList){$IFDEF OBJECT_EVENTS} of object{$ENDIF};
  TOnTimeLeft = procedure({$IFDEF OBJECT_EVENTS}Sender: TObject; {$ENDIF}
    const SecondsLeft: Integer){$IFDEF OBJECT_EVENTS} of object{$ENDIF};
  TOnUpdateFarmInfo = procedure({$IFDEF OBJECT_EVENTS}Sender: TObject; {$ENDIF}
    const FarmInfo: TFarmInfo){$IFDEF OBJECT_EVENTS} of object{$ENDIF};

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
  TCardsFarmer = class
  strict private
    FOnLoadBadgePage: TOnLoadBadgePage;
    FOnStart: TOnStart;
    FOnFinish: TOnFinish;
    FOnLogin: TOnLogin;
    FOnUpdateFarmInfo: TOnUpdateFarmInfo;
    FAppDir: string;
    FStop: Boolean;
    FFarmInfo: TFarmInfo;
    FFarmServices: TFarmServices;
    FHttpClient: THTTPClient;
    FLogin: string;
    FLoginData: TLoginData;
    FSteamID64: string;
    procedure DoLogin(const Login: string);
    procedure DoLoadBadgePage(const Loaded, Total: Integer);
    procedure DoStart(const FarmMode: TFarmMode);
    procedure DoFinish;
    procedure DoUpdateFarmInfo(const FarmInfo: TFarmInfo);
    function GetGameInfoList: TGameInfoList;
    function GetPlayedLessTwoHours(const GameInfoList: TGameInfoList): TGameInfoList;
    function GetGameIdList(const GameInfoList: TGameInfoList): TStringArray;
    function GetGamesWithDrop(const BadgesPage: string): TGameInfoList;
    function GetBadgePageCount(const BadgesPage: string): Integer;
    procedure StartFarm(FarmMode: TFarmMode);
    function TryLogin: Boolean;
    function GetLogin(const MainPage: string): string;
    procedure SetHttpClientHeaders;
    function IsLoggedIn: Boolean;
    function HasLoginData: Boolean;
  public
    property OnLogin: TOnLogin read FOnLogin write FOnLogin;
    property OnLoadBadgePage: TOnLoadBadgePage read FOnLoadBadgePage write FOnLoadBadgePage;
    property OnStart: TOnStart read FOnStart write FOnStart;
    property OnFinish: TOnFinish read FOnFinish write FOnFinish;
    property OnUpdateFarmInfo: TOnUpdateFarmInfo read FOnUpdateFarmInfo write FOnUpdateFarmInfo;
    property Login: string read FLogin;
    property FarmServices: TFarmServices read FFarmServices;
    property FarmInfo: TFarmInfo read FFarmInfo;
    constructor Create(const AppDir: string);
    destructor Destroy; override;
    procedure Start(const FarmMode: TFarmMode; const LoginData: TLoginData);
    procedure Stop;
  end;
  
implementation

const
  FARM_SERVICE_FILENAME = 'CardsFarmerService.exe';
  APP_RUN_LIMIT = 10;
  DEFAULT_WAIT_TIME = 300;
  TRY_REQUEST_COUNT = 3;
  USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.128 Safari/537.36';
  STEAM_MAIN_URL = 'https://steamcommunity.com';
  STEAM_BADGES_URL = 'https://steamcommunity.com/profiles/%s/badges?p=%d';
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
  if FAppInfoList.Count > 0 then
  begin
    for AppInfo in FAppInfoList do
    begin
      PostThreadMessage(AppInfo.ThreadId, WM_CLOSE_FARM_SERVICE, 0, 0);
      CloseHandle(AppInfo.ProcessHandle);
      CloseHandle(AppInfo.ThreadHandle);
    end;

    FAppInfoList.Clear;
  end;
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

constructor TCardsFarmer.Create(const AppDir: string);
begin
  FAppDir := AppDir;

  FOnStart := nil;
  FOnFinish := nil;
  FOnLoadBadgePage := nil;
  FOnLogin := nil;
  FOnUpdateFarmInfo := nil;

  FHttpClient := THTTPClient.Create;
  FHttpClient.UserAgent := USER_AGENT;

  FFarmServices := TFarmServices.Create(AppDir);

  FFarmInfo := Default(TFarmInfo);
  FLoginData := Default(TLoginData);
  FLogin := '';
  FSteamID64 := '';
  FStop := False;
end;

destructor TCardsFarmer.Destroy;
begin
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

  if not IsLoggedIn then
    Exit;

  repeat
    Inc(CurrentPage);

    Url := Format(STEAM_BADGES_URL, [FSteamID64, CurrentPage]);
    Response := FHttpClient.Get(Url);

    if Response.StatusCode = HTTP_OK then
    begin
      Body := Response.ContentAsString;

      if CurrentPage = 1 then
        PageCount := GetBadgePageCount(Body);

      DoLoadBadgePage(CurrentPage, PageCount);
      
      Result := Result + GetGamesWithDrop(Body);
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

function TCardsFarmer.GetGamesWithDrop(const BadgesPage: string): TGameInfoList;

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

function TCardsFarmer.GetLogin(const MainPage: string): string;
begin
  Result := ExtractBetween(MainPage, 'data-miniprofile="', '</div>');
  Result := ExtractBetween(Result, '">', '</a>');
end;

function TCardsFarmer.GetBadgePageCount(const BadgesPage: string): Integer;
var
  s: string;
  Offset: Integer;
begin
  Result := 1;
  s := ExtractBetween(BadgesPage, '<div class="pageLinks">', '</div>');
  Offset := s.LastIndexOf('pagelink');

  Result := ExtractBetween(s, '">', '<', Offset).ToInteger;
end;

function TCardsFarmer.HasLoginData: Boolean;
begin
  Result := not FLoginData.SteamLoginSecure.IsEmpty;
end;

function TCardsFarmer.IsLoggedIn: Boolean;
begin
  Result := not (FSteamID64.IsEmpty or FLogin.IsEmpty);
end;

function TCardsFarmer.TryLogin: Boolean;
var
  Response: IHttpResponse;
  Body: string;
begin
  Result := False;
  FLogin := '';

  SetHttpClientHeaders;

  Response := FHttpClient.Get(STEAM_MAIN_URL);

  if Response.StatusCode = HTTP_OK then
  begin
    Body := Response.ContentAsString;

    FSteamID64 := ExtractBetween(Body, 'g_steamID = "', '"');
    FLogin := GetLogin(Body);

    Result := IsLoggedIn;
  end;
                    
end;

procedure TCardsFarmer.SetHttpClientHeaders;

  procedure AddCookie(const Data: string);
  begin
    FHttpClient.CookieManager.AddServerCookie(Data, STEAM_MAIN_URL);
  end;

begin
  FHttpClient.CustHeaders
    .Clear
    .Add('Connection', 'keep-alive')
    .Add('Cache-Control', 'no-cache')
    .Add('Upgrade-Insecure-Requests', '1')
    .Add('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9')
    .Add('Accept-Encoding', 'gzip, deflate, br')
    .Add('Accept-Language', 'q=0.9,en-US;q=0.8,en;q=0.7');

  AddCookie('steamLoginSecure=' + FLoginData.SteamLoginSecure);

  if FLoginData.SteamParental <> '' then
    AddCookie('steamParental=' + FLoginData.SteamParental);
end;

procedure TCardsFarmer.Start(const FarmMode: TFarmMode; const LoginData: TLoginData);
begin
  DoStart(FarmMode);

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

  DoFinish;
  
end;

procedure TCardsFarmer.StartFarm(FarmMode: TFarmMode);
var
  GameInfoList: TGameInfoList;
  GameInfo: TGameInfo;
begin
  FStop := False;

  repeat
    GameInfoList := GetGameInfoList;

    DoUpdateFarmInfo(FarmInfo);

    if FarmMode = fmSeparately then
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
      FarmMode := fmSeparately;

    end;

  until (Length(GameInfoList) = 0) or FStop;

end;

procedure TCardsFarmer.Stop;
begin
  FStop := True;
  FFarmServices.Stop;
end;

end.
