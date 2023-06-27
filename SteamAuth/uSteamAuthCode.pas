{

  https://github.com/wanips7

}

unit uSteamAuthCode;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Hash, System.TimeSpan, System.NetEncoding, System.JSON, System.IOUtils, DateUtils;

type
  TMAFileData = record
    Login: string;
    SharedSecret: string;
  end;

type
  TSteamAuthCode = record
  private
    class function GetTimeOffset: Int64; static;
    class function GetServerTimeInSeconds: Int64; static;
  public
    const UPDATE_PERIOD = 30;
  public
    class function LoadMaFile(const FileName: string; out MAFileData: TMAFileData): Boolean; static;
    class function GetSecondsUntilNewCode: Integer; static;
    class function GetAuthCode(const Secret: string): string; overload; static;
    class function GetAuthCode(const Secret: string; TimeOffset: Integer): string; overload; static;
  end;

implementation

function BytesToInt(const Value: TBytes): Integer;
begin
  if Length(Value) = SizeOf(Integer) then
    Move(Value[0], Result, SizeOf(Integer))
  else
    raise EConvertError.Create('Convert error');
end;

class function TSteamAuthCode.GetAuthCode(const Secret: string): string;
begin
  Result := GetAuthCode(Secret, GetTimeOffset);
end;

class function TSteamAuthCode.GetAuthCode(const Secret: string; TimeOffset: Integer): string;
const
  CodeTranslations: TBytes =
    [50, 51, 52, 53, 54, 55, 56, 57, 66, 67, 68, 70, 71, 72, 74, 75, 77, 78, 80, 81, 82, 84, 86, 87, 88, 89];
  CODE_LEN = 5;
var
  i: Integer;
  Time: Int64;
  TimeArray: TBytes;
  HashSHA1: THashSHA1;
  HashedData: TBytes;
  codeArray: TBytes;
  b: Byte;
  codePoint: Integer;
  codePointArray: TBytes;
begin
  Time := GetServerTimeInSeconds - TimeOffset;
  Time := Time div UPDATE_PERIOD;

  SetLength(TimeArray, 8);

  for i := 7 downto 0 do
  begin
    TimeArray[i] := Byte(Time);
    Time := Time shr 8;
  end;

  HashSHA1 := THashSHA1.Create;
  HashedData := HashSHA1.GetHMACAsBytes(TimeArray, TNetEncoding.Base64.DecodeStringToBytes(secret));

  b := Byte(HashedData[19] and $F);

  SetLength(codePointArray, 4);
  codePointArray[0] := HashedData[b + 3] and $FF;
  codePointArray[1] := HashedData[b + 2] and $FF;
  codePointArray[2] := HashedData[b + 1] and $FF;
  codePointArray[3] := HashedData[b] and $7F;

  codePoint := BytesToInt(codePointArray);

  SetLength(codeArray, CODE_LEN);

  for i := 0 to CODE_LEN - 1 do
  begin
    codeArray[i] := CodeTranslations[codePoint mod Length(CodeTranslations)];
    codePoint := codePoint div Length(CodeTranslations);
  end;

  Result := TEncoding.UTF8.GetString(codeArray);
end;

class function TSteamAuthCode.GetSecondsUntilNewCode: Integer;
begin
  Result := SecondOf(Now);

  if Result >= UPDATE_PERIOD then
    Result := Result - UPDATE_PERIOD;

  Result := UPDATE_PERIOD - Result;
end;

class function TSteamAuthCode.GetServerTimeInSeconds: Int64;
begin
  Result := DateUtils.SecondsBetween(Now, StrToDate('01.01.1970'));
end;

class function TSteamAuthCode.GetTimeOffset: Int64;
begin
  Result := Round(TTimeZone.Local.GetUtcOffset(Now, False).TotalSeconds);
end;

class function TSteamAuthCode.LoadMaFile(const FileName: string; out MAFileData: TMAFileData): Boolean;
var
  JsonValue: TJSONValue;
  Text: string;
begin
  Result := False;

  if FileExists(FileName) then
  begin
    Text := TFile.ReadAllText(FileName);

    JsonValue := TJSONObject.ParseJSONValue(Text);

    try
      MAFileData.Login := JSONValue.GetValue<string>('account_name');
      MAFileData.SharedSecret := JSONValue.GetValue<string>('shared_secret');

    finally
      JsonValue.Free;
    end;

    Result := not MAFileData.Login.IsEmpty and not MAFileData.SharedSecret.IsEmpty;
  end;
end;

end.
