{
  A unit for Steam authorization

  https://github.com/wanips7

}

unit uSteamAuth;

interface

{$SCOPEDENUMS ON}

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils,
  System.Net.HttpClient, System.JSON, System.NetEncoding, REST.Json.Types, REST.Json,
  uRSA;

type
  TLoginResult =
    (GeneralFailure, LoginOkay, BadRSA, BadCredentials, NeedCaptcha, Need2FA, NeedEmail, TooManyFailedLogins);

type
  TRSAResponse = class
    [JSONName('success')]
    Success: Boolean;
    [JSONName('publickey_exp')]
    Exponent: string;
    [JSONName('publickey_mod')]
    Modulus: string;
    [JSONName('timestamp')]
    Timestamp: string;
    [JSONName('steamid')]
    SteamID: Int64;
  end;

type
  TSessionData = record
    SessionID: string;
    SteamLogin: string;
    SteamLoginSecure: string;
    WebCookie: string;
    SteamID: Int64;
  end;

type
  TTransferParameters = class
    [JSONName('steamid')]
    SteamID: UInt64;
    [JSONName('token_secure')]
    TokenSecure: string;
    [JSONName('auth')]
    Auth: string;
    [JSONName('webcookie')]
    WebCookie: string;
  end;

type
  TLoginResponse = class
    [JSONName('success')]
    Success: Boolean;
    [JSONName('login_complete')]
    LoginComplete: Boolean;
    [JSONName('transfer_parameters')]
    TransferParameters: TTransferParameters;
    [JSONName('captcha_needed')]
    CaptchaNeeded: Boolean;
    [JSONName('captcha_gid')]
    CaptchaGID: string;
    [JSONName('emailsteamid')]
    EmailSteamID: string;
    [JSONName('emailauth_needed')]
    EmailAuthNeeded: Boolean;
    [JSONName('requires_twofactor')]
    TwoFactorNeeded: Boolean;
    [JSONName('message')]
    Message: string;
  end;

type
  TSteamAuth = class
  private
    FCookie: string;
    FTwoFactorCode: string;
    FCaptchaGID: string;
    FSteamID: string;
    FEmailCode: string;
    FCaptchaText: string;
    FHttpClient: THTTPClient;
    FList: TStringList;
    FSessionData: TSessionData;
    FLoginResult: TLoginResult;
    procedure Clear;
    procedure SetHeaders;
  public
    const
      HTTP_OK = 200;
      HTTP_TOO_MANY_REQUESTS = 429;
      STEAMAPI_BASE = 'https://api.steampowered.com';
      COMMUNITY_BASE = 'https://steamcommunity.com';
      USER_AGENT =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36';
  public
    property Cookie: string read FCookie;
    property SessionData: TSessionData read FSessionData;
    property TwoFactorCode: string read FTwoFactorCode write FTwoFactorCode;
    property EmailCode: string read FEmailCode write FEmailCode;
    property CaptchaText: string read FCaptchaText write FCaptchaText;
    constructor Create;
    destructor Destroy; override;
    function TryLogin(const Login, Password: string): TLoginResult;
    function LoggedIn: Boolean;
    function Requires2FA: Boolean;
    function RequiresEmailAuth: Boolean;
    function RequiresCaptcha: Boolean;
    function IsValidCookie(const Value: string): Boolean;
  end;

implementation

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

{ TSteamAuth }

procedure TSteamAuth.Clear;
begin
  FCaptchaGID := '';
  FSteamID := '';
  FCookie := '';

  FSessionData := Default(TSessionData);
  FLoginResult := TLoginResult.GeneralFailure;
  FList.Clear;
end;

constructor TSteamAuth.Create;
begin
  FHttpClient := THTTPClient.Create;
  SetHeaders;
  FList := TStringList.Create;

  FTwoFactorCode := '';
  FEmailCode := '';
  FCaptchaText := '';

  Clear;

end;

destructor TSteamAuth.Destroy;
begin
  FList.Free;
  FHttpClient.Free;
  inherited;
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
    FHttpClient.CookieManager.AddServerCookie(s, COMMUNITY_BASE);
  end;

  Response := FHttpClient.Get(COMMUNITY_BASE);
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

function TSteamAuth.TryLogin(const Login, Password: string): TLoginResult;
var
  Response: IHttpResponse;
  Body: string;
  RSAResponse: TRSAResponse;
  LoginResponse: TLoginResponse;
  EncryptedPasswordBytes: TBytes;
  EncryptedPassword: string;
  C: TCookie;
begin
  RSAResponse := nil;
  LoginResponse := nil;

  Clear;
  SetHeaders;

  FList.Add('username=' + Login);

  Response := FHttpClient.Post(COMMUNITY_BASE + '/login/getrsakey', FList);
  Body := Response.ContentAsString;

  try
    if Response.StatusCode <> HTTP_OK then
      Exit(TLoginResult.GeneralFailure);

    if Body.Contains('<BODY>\nAn error occurred while processing your request.') then
      Exit(TLoginResult.GeneralFailure);

    try
      RSAResponse := TJSON.JsonToObject<TRSAResponse>(Body);
    except
      Exit(TLoginResult.GeneralFailure);
    end;

    if not Assigned(RSAResponse) then
      Exit(TLoginResult.GeneralFailure);

    if not RSAResponse.Success then
    begin
      Exit(TLoginResult.BadRSA);
    end
      else
    begin
      EncryptedPasswordBytes := TRsa.Encrypt(Password, RSAResponse.Modulus, RSAResponse.Exponent);
      EncryptedPassword := TNetEncoding.Base64.EncodeBytesToString(EncryptedPasswordBytes);
      EncryptedPassword := EncryptedPassword.Replace(sLineBreak, '', [rfReplaceAll]);

      Sleep(300);

      { Send encrypted data }
      FList.Clear;
      FList.Add('password=' + EncryptedPassword);
      FList.Add('username=' + Login);
      FList.Add('twofactorcode=' + FTwoFactorCode);

      FList.Add('emailauth=' + FEmailCode);
      FList.Add('captchagid=' + FCaptchaGID);
      FList.Add('captcha_text=' + FCaptchaText);
      FList.Add('emailsteamid=' + FSteamID);

      FList.Add('rsatimestamp=' + RSAResponse.Timestamp);
      FList.Add('remember_login=true');

      Response := FHttpClient.Post(COMMUNITY_BASE + '/login/dologin', FList);
      Body := Response.ContentAsString;

      if (Response.StatusCode <> HTTP_OK) or Body.IsEmpty then
        Exit(TLoginResult.GeneralFailure);

      try
        LoginResponse := TJSON.JsonToObject<TLoginResponse>(Body);
      except
        Exit(TLoginResult.GeneralFailure);
      end;

      if not Assigned(LoginResponse) then
        Exit(TLoginResult.GeneralFailure);

      if not LoginResponse.Message.IsEmpty then
      begin
        if LoginResponse.Message.Contains('There have been too many login failures') then
          Exit(TLoginResult.TooManyFailedLogins);

        if LoginResponse.Message.Contains('Incorrect login') then
          Exit(TLoginResult.BadCredentials);
      end;

      if LoginResponse.CaptchaNeeded then
      begin
        FCaptchaGID := LoginResponse.CaptchaGID;
        Exit(TLoginResult.NeedCaptcha);
      end;

      if LoginResponse.EmailAuthNeeded then
      begin
        FSteamID := LoginResponse.EmailSteamID;
        Exit(TLoginResult.NeedEmail);
      end;

      if LoginResponse.TwoFactorNeeded and not LoginResponse.Success then
      begin
        Exit(TLoginResult.Need2FA);
      end;

      if not LoginResponse.LoginComplete then
      begin
        Exit(TLoginResult.BadCredentials);
      end;

      FSessionData.SteamID := LoginResponse.TransferParameters.SteamID;
      FSessionData.SteamLoginSecure := LoginResponse.TransferParameters.SteamID.ToString + '%7C%7C' +
        LoginResponse.TransferParameters.TokenSecure;
      FSessionData.SteamLogin := Login;
      FSessionData.WebCookie := LoginResponse.TransferParameters.WebCookie;
      FSessionData.SessionID := '';

      Result := TLoginResult.LoginOkay;
    end;

  finally
    FLoginResult := Result;
    RSAResponse.Free;

    if Assigned(LoginResponse) then
      if Assigned(LoginResponse.TransferParameters) then
        FreeAndNil(LoginResponse.TransferParameters);
    LoginResponse.Free;
  end;

  if Result = TLoginResult.LoginOkay then
  begin
    for C in FHttpClient.CookieManager.Cookies do
      FCookie := FCookie + C.ToString + '; ';
  end;

end;



end.
