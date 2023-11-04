{
  A unit for Steam authorization

  https://github.com/wanips7

}

unit uSteamAuth;

interface

{$SCOPEDENUMS ON}

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.NetEncoding,
  System.Net.HttpClient, System.JSON, REST.Json.Types, REST.Json, uRSA;

type
  TRSAResponseValue = class
  public
    [JSONName('publickey_exp')]
    Exponent: string;
    [JSONName('publickey_mod')]
    Modulus: string;
    [JSONName('timestamp')]
    Timestamp: string;
  end;

type
  TRSAResponse = class
  public
    [JSONName('response')]
    Value: TRSAResponseValue;
  end;

type
  TBeginAuthSessionResponseValue = class
  public
    [JSONName('client_id')]
    ClientId: string;
    [JSONName('request_id')]
    RequestId: string;
    [JSONName('interval')]
    Interval: Integer;

    [JSONName('steamid')]
    SteamId: string;
    [JSONName('weak_token')]
    WeakToken: string;
    [JSONName('extended_error_message')]
    ExtendedErrorMessage: string;
  end;

type
  TBeginAuthSessionResponse = class
  public
    [JSONName('response')]
    Value: TBeginAuthSessionResponseValue;
  end;

type
  TPollAuthSessionResponseValue = class
  public
    [JSONName('refresh_token')]
    RefreshToken: string;
    [JSONName('access_token')]
    AccessToken: string;
    [JSONName('had_remote_interaction')]
    HadRemoteInteraction: Boolean;
    [JSONName('account_name')]
    AccountName: string;
  end;

type
  TPollAuthSessionResponse = class
  public
    [JSONName('response')]
    Value: TPollAuthSessionResponseValue;
  end;

type
  TSteamAPI = class
  public
    const STEAMAPI_BASE = 'https://api.steampowered.com';
    const COMMUNITY_BASE = 'https://steamcommunity.com';
    const LOGIN_STEAMPOWERED_BASE = 'https://login.steampowered.com';
    const GET_PASSWORD_RSA_PUBLIC_KEY = STEAMAPI_BASE + '/IAuthenticationService/GetPasswordRSAPublicKey/v1/';
    const BEGIN_AUTH_SESSION_VIA_CRIDENTIALS = STEAMAPI_BASE + '/IAuthenticationService/BeginAuthSessionViaCredentials/v1/';
    const UPDATE_AUTH_SESSION_WITH_STEAM_GUARD_CODE = STEAMAPI_BASE + '/IAuthenticationService/UpdateAuthSessionWithSteamGuardCode/v1/';
    const POLL_AUTH_SESSION_STATUS = STEAMAPI_BASE + '/IAuthenticationService/PollAuthSessionStatus/v1/';
    const FINALIZE_LOGIN = LOGIN_STEAMPOWERED_BASE + '/jwt/finalizelogin';
    const SET_TOKEN = COMMUNITY_BASE + '/login/settoken';
  end;

type
  TSteamAuth = class
  public
  type
    TLoginResult = (GeneralFailure, LoginOkay, BadRSA, BadCredentials, NeedCaptcha, Need2FA,
      NeedEmail, TooManyFailedLogins);
    TConfirmationType = (Unknown = 0, None = 1, EmailCode = 2, TwoFactorCode = 3, DeviceConfirmation = 4,
      EmailConfirmation = 5, MachineToken = 6, LegacyMachineAuth = 7);

  type
    TSessionData = record
      SessionID: string;
      SteamLogin: string;
      SteamLoginSecure: string;
      SteamID: Int64;
      Cookie: string;
    end;

  type
    TOnConfirmationRequiredEvent = procedure(Sender: TObject; ConfirmationType: TConfirmationType) of object;

  private
    FOnConfirmationRequiredEvent: TOnConfirmationRequiredEvent;
    FCaptchaGID: string;
    FCaptchaText: string;
    FHttpClient: THTTPClient;
    FSessionData: TSessionData;
    FLoginResult: TLoginResult;
    FTwoFactorCode: string;
    procedure Clear;
    procedure SetHeaders;
    function GetCookieValue(const Url, Name: string): string;
    procedure DoConfirmationRequired(ConfirmationType: TConfirmationType);
  public
    const
      HTTP_OK = 200;
      HTTP_TOO_MANY_REQUESTS = 429;
      USER_AGENT =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36';
  public
    property OnConfirmationRequired: TOnConfirmationRequiredEvent read FOnConfirmationRequiredEvent write FOnConfirmationRequiredEvent;
    property SessionData: TSessionData read FSessionData;
    property TwoFactorCode: string read FTwoFactorCode write FTwoFactorCode;
    property CaptchaText: string read FCaptchaText write FCaptchaText;
    constructor Create;
    destructor Destroy; override;
    function Login(const Login, Password: string): TLoginResult;
    function LoggedIn: Boolean;
    function Requires2FA: Boolean;
    function RequiresEmailAuth: Boolean;
    function RequiresCaptcha: Boolean;
    function IsValidCookie(const Value: string): Boolean;
  end;

implementation

{ TSteamAuth }

procedure TSteamAuth.Clear;
begin
  FCaptchaGID := '';

  FSessionData := Default(TSessionData);
  FLoginResult := TLoginResult.GeneralFailure;
end;

constructor TSteamAuth.Create;
begin
  FOnConfirmationRequiredEvent := nil;
  FHttpClient := THTTPClient.Create;
  SetHeaders;

  FTwoFactorCode := '';
  FCaptchaText := '';

  Clear;

end;

destructor TSteamAuth.Destroy;
begin
  FHttpClient.Free;
  inherited;
end;

procedure TSteamAuth.DoConfirmationRequired(ConfirmationType: TConfirmationType);
begin
  if Assigned(FOnConfirmationRequiredEvent) then
    FOnConfirmationRequiredEvent(Self, ConfirmationType);
end;

function TSteamAuth.GetCookieValue(const Url, Name: string): string;
var
  Cookie: TCookie;
  Domain: string;
  Spl: TArray<string>;
begin
  Result := '';
  Spl := Url.Split(['//']);

  if Length(Spl) <> 2 then
    raise Exception.Create('Invalid url.');

  Domain := '.' + Spl[1];

  for Cookie in FHttpClient.CookieManager.Cookies do
  begin
    if (Cookie.Domain = Domain) and (Cookie.Name = Name) then
    begin
      Result := Cookie.Value;
      Break;
    end;
  end;
end;

function TSteamAuth.IsValidCookie(const Value: string): Boolean;
var
  Response: IHttpResponse;
  Body: string;
  s: string;
begin
  Result := False;

  if Value.IsEmpty then
    Exit;

  Clear;
  SetHeaders;
  FHttpClient.CookieManager.Clear;

  for s in Value.Split(['; ']) do
  begin
    FHttpClient.CookieManager.AddServerCookie(s, TSteamAPI.COMMUNITY_BASE);
  end;

  Response := FHttpClient.Get(TSteamAPI.COMMUNITY_BASE);
  Body := Response.ContentAsString;

  if Response.StatusCode = HTTP_OK then
  begin
    Result := Body.Contains('<div class="responsive_menu_user_area">');
  end;

end;

function TSteamAuth.LoggedIn: Boolean;
begin
  Result := FLoginResult = TLoginResult.LoginOkay;
end;

function TSteamAuth.Requires2FA: Boolean;
begin
  Result := FLoginResult = TLoginResult.Need2FA;
end;

function TSteamAuth.RequiresCaptcha: Boolean;
begin
  Result := FLoginResult = TLoginResult.NeedCaptcha;
end;

function TSteamAuth.RequiresEmailAuth: Boolean;
begin
  Result := FLoginResult = TLoginResult.NeedEmail;
end;

procedure TSteamAuth.SetHeaders;
begin
  FHttpClient.CustHeaders
    .Clear
    .Add('Accept', 'text/javascript, text/html, application/xml, text/xml, */*')
    .Add('Accept-Encoding', 'gzip, deflate, br')
    .Add('Accept-Language', 'q=0.9,en-US;q=0.8,en;q=0.7');

  FHttpClient.UserAgent := USER_AGENT;
  FHttpClient.CookieManager.Clear;
end;

function TSteamAuth.Login(const Login, Password: string): TLoginResult;
var
  Response: IHttpResponse;
  RSAResponse: TRSAResponse;
  BeginAuthSessionResponse: TBeginAuthSessionResponse;
  PollAuthSessionResponse: TPollAuthSessionResponse;
  EncryptedPasswordBytes: TBytes;
  EncryptedPassword: string;
  JsonValue: TJSONValue;
  C: TCookie;
  TokenNonce: string;
  TokenAuth: string;
  Body: string;
  List: TStringList;
  ConfirmationId: Integer;
  ConfirmationType: TConfirmationType;
begin
  RSAResponse := nil;
  BeginAuthSessionResponse := nil;
  PollAuthSessionResponse := nil;
  ConfirmationId := 0;

  List := TStringList.Create;

  Clear;
  SetHeaders;

  try
    Response := FHttpClient.Get(TSteamAPI.GET_PASSWORD_RSA_PUBLIC_KEY +
      '?account_name=' + Login);

    try
      RSAResponse := TJSON.JsonToObject<TRSAResponse>(Response.ContentAsString);
    except
      Exit(TLoginResult.GeneralFailure);
    end;

    EncryptedPasswordBytes := TRsa.Encrypt(Password, RSAResponse.Value.Modulus, RSAResponse.Value.Exponent);
    EncryptedPassword := TNetEncoding.Base64.EncodeBytesToString(EncryptedPasswordBytes);
    EncryptedPassword := EncryptedPassword.Replace(sLineBreak, '', [rfReplaceAll]);

    Sleep(300);

    { Send encrypted data }
    List.Clear;
    List.Add('persistence=1');
    List.Add('encrypted_password=' + EncryptedPassword);
    List.Add('account_name=' + Login);
    List.Add('encryption_timestamp=' + RSAResponse.Value.Timestamp);

    Response := FHttpClient.Post(TSteamAPI.BEGIN_AUTH_SESSION_VIA_CRIDENTIALS, List);
    Body := Response.ContentAsString;

    try
      BeginAuthSessionResponse := TJSON.JsonToObject<TBeginAuthSessionResponse>(Body);
    except
      Exit(TLoginResult.GeneralFailure);
    end;

    if BeginAuthSessionResponse.Value.SteamId.IsEmpty then
      Exit(TLoginResult.BadCredentials);

    JsonValue := TJSONObject.ParseJSONValue(Body);
    try
      try
        JSONValue.TryGetValue<Integer>('response.allowed_confirmations[0].confirmation_type', ConfirmationId);
      finally
        JsonValue.Free;
      end;

    except
      Exit(TLoginResult.GeneralFailure);
    end;

    if ConfirmationId > 0 then
    begin
      DoConfirmationRequired(TConfirmationType(ConfirmationId));
    end;

    { Update authentication session }
    List.Clear;
    List.Add('client_id=' + BeginAuthSessionResponse.Value.ClientId);
    List.Add('steamid=' + BeginAuthSessionResponse.Value.SteamId);
    List.Add('code=' + FTwoFactorCode);
    List.Add('code_type=' + ConfirmationId.ToString);

    Response := FHttpClient.Post(TSteamAPI.UPDATE_AUTH_SESSION_WITH_STEAM_GUARD_CODE, List);

    { Poll during authentication process }
    List.Clear;
    List.Add('client_id=' + BeginAuthSessionResponse.Value.ClientId);
    List.Add('request_id=' + BeginAuthSessionResponse.Value.RequestId);

    Response := FHttpClient.Post(TSteamAPI.POLL_AUTH_SESSION_STATUS, List);

    try
      PollAuthSessionResponse := TJSON.JsonToObject<TPollAuthSessionResponse>(Response.ContentAsString);
    except
      Exit(TLoginResult.GeneralFailure);
    end;

    { Finalize login }
    FSessionData.SessionID := GetCookieValue(TSteamAPI.COMMUNITY_BASE, 'sessionid');
    FSessionData.SteamLogin := PollAuthSessionResponse.Value.AccountName;

    List.Clear;
    List.Add('nonce=' + PollAuthSessionResponse.Value.RefreshToken);
    List.Add('sessionid=' + FSessionData.SessionID);

    Response := FHttpClient.Post(TSteamAPI.FINALIZE_LOGIN, List);

    JsonValue := TJSONObject.ParseJSONValue(Response.ContentAsString);
    try
      TokenNonce := JSONValue.GetValue<string>('transfer_info[1].params.nonce');
      TokenAuth := JSONValue.GetValue<string>('transfer_info[1].params.auth');
    finally
      JsonValue.Free;
    end;

    { Set token }
    List.Clear;
    List.Add('nonce=' + TokenNonce);
    List.Add('auth=' + TokenAuth);
    List.Add('steamID=' + BeginAuthSessionResponse.Value.SteamId);

    Response := FHttpClient.Post(TSteamAPI.SET_TOKEN, List);

    Result := TLoginResult.LoginOkay;

  finally
    FLoginResult := Result;

    if Result = TLoginResult.LoginOkay then
    begin
      FSessionData.SteamID := BeginAuthSessionResponse.Value.SteamId.ToInt64;
      FSessionData.SteamLoginSecure := GetCookieValue(TSteamAPI.COMMUNITY_BASE, 'steamLoginSecure');

      for C in FHttpClient.CookieManager.Cookies do
        FSessionData.Cookie := FSessionData.Cookie + C.ToString + '; ';
    end;

    if Assigned(RSAResponse) then
      if Assigned(RSAResponse.Value) then
        RSAResponse.Value.Free;
    RSAResponse.Free;

    if Assigned(BeginAuthSessionResponse) then
      if Assigned(BeginAuthSessionResponse.Value) then
        BeginAuthSessionResponse.Value.Free;
    BeginAuthSessionResponse.Free;

    if Assigned(PollAuthSessionResponse) then
      if Assigned(PollAuthSessionResponse.Value) then
        PollAuthSessionResponse.Value.Free;
    PollAuthSessionResponse.Free;

    List.Free;
  end;

end;

end.
