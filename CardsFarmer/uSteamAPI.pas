{

  https://github.com/wanips7

}

unit uSteamAPI;

interface

uses
  Winapi.Windows, System.SysUtils;
 
const
  STEAM_API_DLL = 'steam_api.dll';
 
function Initialize(const LibPath: String): boolean;
procedure Shutdown;
  
var  
  SteamAPI_Init: procedure(); stdcall = nil;
  SteamAPI_Shutdown: procedure(); stdcall = nil;
  SteamAPI_IsSteamRunning: function(): Boolean; stdcall = nil;

implementation

var
  LibHandle: Cardinal = 0;

function GetSteamProcAddress(var Ptr: Pointer; const Name: AnsiString): Boolean;
begin
  Ptr := GetProcAddress(LibHandle, PAnsiChar(Name));
  Result := Assigned(Ptr);
  if not Result then
    raise Exception.Create('Error while loading Steam API function: ' + Name);
end;
  
function IsLibLoaded: Boolean;
begin
  Result := (LibHandle > 0)
end;
  
function LoadAPI(const LibPath: String): Boolean;
begin
  Result := False;
 
  if FileExists(LibPath) and (not IsLibLoaded) then
    LibHandle := LoadLibrary(PWideChar(LibPath));
 
  if LibHandle > 32 then
  begin
    Result := GetSteamProcAddress(@SteamAPI_Init, 'SteamAPI_Init') and
      GetSteamProcAddress(@SteamAPI_Shutdown, 'SteamAPI_Shutdown') and
      GetSteamProcAddress(@SteamAPI_IsSteamRunning, 'SteamAPI_IsSteamRunning');

  end
    else
  LibHandle := 0;
end;

function Initialize(const LibPath: String): Boolean;
begin
  Result := False;
  if LoadAPI(LibPath) then
    if Assigned(SteamAPI_Init) then
    begin
      SteamAPI_Init;
      Result := True;
    end;
	
end;
 
procedure Shutdown;
begin
  if not IsLibLoaded then
    Exit;
    
  if Assigned(SteamAPI_Shutdown) then
    SteamAPI_Shutdown;

  FreeLibrary(LibHandle);
  LibHandle := 0;

  SteamAPI_Init := nil;
  SteamAPI_Shutdown := nil;
  SteamAPI_IsSteamRunning := nil;
end;

end.
