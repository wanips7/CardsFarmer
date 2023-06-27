{

  https://github.com/wanips7

}

unit uRSA;

interface

uses
  Winapi.Windows, System.SysUtils, System.NetEncoding;

type
  PPublicKeyBLOB = ^TPublicKeyBLOB;
  TPublicKeyBLOB = packed record
    Magic: ULONG;
    BitLength: ULONG;
    cbPublicExp: ULONG;
    cbModulus: ULONG;
    cbPrime1: ULONG;
    cbPrime2: ULONG;
    Exponent: array[0..2] of Byte;
    Modulus: array[0..255] of Byte;
  end;

type
  TRSAException = class(Exception);

TBCryptOpenAlgorithmProvider = function (phAlgorithm: pHandle; pszAlgId: LPCWSTR;
  pszImplementation: LPCWSTR; dwFlags: DWORD): ULONG; stdcall;

TBCryptImportKeyPair = function (hAlgorithm: THandle; hImportKey: THandle; pszBlobType: LPCWSTR;
  phKey: pHandle; pbInput: pPublicKeyBLOB; cbInput: ULONG; dwFlags: ULONG): ULONG; stdcall;

TBCryptEncrypt = function (hKey: THandle; pbInput: PUCHAR; cbInput: ULONG; pPaddingInfo: Pointer;
  pbIV: PUCHAR; cbIV: ULONG; pbOutput: PUCHAR; cbOutput: ULONG; pcbResult: PULONG; dwFlags: ULONG): ULONG; stdcall;

TBCryptCloseAlgorithmProvider = function (hAlgorithm: THandle; dwFlags: ULONG): ULONG; stdcall;


type
  TRSA = class
  private const
    BCRYPT_LIB = 'bcrypt.dll';
    BCRYPT_RSAPUBLIC_MAGIC = $31415352;
    BCRYPT_PAD_PKCS1 = $00000002;
    BCRYPT_RSA_ALGORITHM = 'RSA';
    BCRYPT_RSAPUBLIC_BLOB = 'RSAPUBLICBLOB';
  private
    class var FLibHandle: THandle;
    class procedure RaiseError(const Text: string; Status: Cardinal); overload; static;
    class procedure RaiseError(const Text: string); overload; static;
  public
    class function IsLibLoaded: Boolean; static;
    class function Initialize: Boolean; static;
    class procedure Shutdown; static;
    class function Encrypt(const Data: string; modulusStr, exponentStr: string): TBytes; static;
  end;

implementation

var
  BCryptOpenAlgorithmProvider: TBCryptOpenAlgorithmProvider = nil;
  BCryptImportKeyPair: TBCryptImportKeyPair = nil;
  BCryptEncrypt: TBCryptEncrypt = nil;
  BCryptCloseAlgorithmProvider: TBCryptCloseAlgorithmProvider = nil;

function HexToByte(const Str: string): Byte; inline;
begin
  Result := Byte(StrToInt('$' + Str));
end;

class procedure TRSA.RaiseError(const Text: string; Status: Cardinal);
begin
  raise TRSAException.CreateFmt(Text + ' Status: %d. %s', [Status, SysErrorMessage(GetLastError)]);
end;

class procedure TRSA.RaiseError(const Text: string);
begin
  raise TRSAException.Create(Text);
end;

class function TRsa.Encrypt(const Data: string; modulusStr, exponentStr: string): TBytes;
var
  PublicKeyBLOB: TPublicKeyBlob;
  i: Integer;
  Status: ULONG;
  hAlg: THandle;
  hKey: THandle;
  InputData: TBytes;
  EncryptedData: TBytes;
  EncryptedSize: ULONG;

  procedure CheckErrors;
  begin
    if Status <> 0 then
      raise TRSAException.CreateFmt('%s error. Status: %d. %s', [BCRYPT_LIB, Status, SysErrorMessage(GetLastError)]);
  end;

  function GetErrorMessage: string;
  begin
    Result := BCRYPT_LIB + ' error, status: ' + IntToStr(status) + '. ' + SysErrorMessage(GetLastError());
  end;

begin
  Result := [];

  if not IsLibLoaded then
    RaiseError('Error: ' + BCRYPT_LIB + ' is not loaded.');

  InputData := TEncoding.ASCII.GetBytes(Data);

  { Create a key }
  with PublicKeyBLOB do
  begin
    Magic := BCRYPT_RSAPUBLIC_MAGIC;
    BitLength := SizeOf(Modulus) * 8;
    cbPublicExp := SizeOf(Exponent);
    cbModulus := SizeOf(Modulus);

    if (Length(exponentstr) mod 2) <> 0 then
      exponentstr := '0' + exponentstr;
    if (Length(modulusstr) mod 2) <> 0 then
      modulusstr := '0' + modulusstr;
    for i := Low(exponent) to High(exponent) do
      exponent[i] := HexToByte(copy(exponentstr, i * 2 + 1, 2));
    for i := Low(modulus) to High(modulus) do
      modulus[i] := HexToByte(copy(modulusstr, i * 2 + 1, 2));
  end;

  { Open provider, encrypt, close provider }
  Status := BCryptOpenAlgorithmProvider(@halg, BCRYPT_RSA_ALGORITHM, nil, 0);
  if Status <> 0 then
  begin
    RaiseError(GetErrorMessage);
  end;

  Status := BCryptImportKeyPair(hAlg, 0, BCRYPT_RSAPUBLIC_BLOB, @hKey, @PublicKeyBLOB, SizeOf(PublicKeyBLOB), 0);
  if Status <> 0 then
  begin
    RaiseError(GetErrorMessage);
  end;

  Status := BCryptEncrypt(hKey, @InputData[0], Length(InputData), nil, nil, 0, nil, 0, @EncryptedSize, BCRYPT_PAD_PKCS1);
  if Status <> 0 then
  begin
    RaiseError(GetErrorMessage);
  end;

  SetLength(EncryptedData,EncryptedSize);
  Status := BCryptEncrypt(hKey, @InputData[0], Length(InputData), nil, nil, 0, @EncryptedData[0], Length(EncryptedData), @EncryptedSize, BCRYPT_PAD_PKCS1);
  if Status <> 0 then
  begin
    RaiseError(GetErrorMessage);
  end;

  Status := BCryptCloseAlgorithmProvider(hAlg, 0);
  if Status <> 0 then
  begin
    RaiseError(GetErrorMessage);
  end;

  Result := EncryptedData;
end;

class function TRSA.Initialize: Boolean;
begin
  FLibHandle := LoadLibrary(BCRYPT_LIB);
  if FLibHandle < 32 then
  begin
    RaiseError('Error while loading ' + BCRYPT_LIB + '!');
  end;

  @BCryptOpenAlgorithmProvider := GetProcAddress(FLibHandle, 'BCryptOpenAlgorithmProvider');
  @BCryptImportKeyPair := GetProcAddress(FLibHandle, 'BCryptImportKeyPair');
  @BCryptEncrypt := GetProcAddress(FLibHandle, 'BCryptEncrypt');
  @BCryptCloseAlgorithmProvider := GetProcAddress(FLibHandle, 'BCryptCloseAlgorithmProvider');

  Result := IsLibLoaded;
end;

class function TRSA.IsLibLoaded: Boolean;
begin
  Result :=
    Assigned(BCryptOpenAlgorithmProvider) and Assigned(BCryptImportKeyPair) and
    Assigned(BCryptEncrypt) and Assigned(BCryptCloseAlgorithmProvider);
end;

class procedure TRSA.Shutdown;
begin
  if not IsLibLoaded then
    Exit;

  FreeLibrary(FLibHandle);
  FLibHandle := 0;

  BCryptOpenAlgorithmProvider := nil;
  BCryptImportKeyPair := nil;
  BCryptEncrypt := nil;
  BCryptCloseAlgorithmProvider := nil;
end;

initialization
  TRSA.Initialize;

finalization
  TRSA.Shutdown;

end.
