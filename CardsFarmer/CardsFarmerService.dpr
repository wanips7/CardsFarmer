program CardsFarmerService;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils,
  Winapi.Messages,
  uSteamAPI in 'uSteamAPI.pas';

const
  WM_CLOSE_FARM_SERVICE = WM_USER + 1;

var
  AppId: string;
  AppDir: string;
  Msg: TMsg;
  IsTest: Boolean = False;

procedure RaiseException(const Value: string);
begin
  raise Exception.Create(Value);
end;

procedure Print(const Value: string);
begin
  Writeln(Value);
end;

function GetAppId: string;
begin
  if ParamCount > 0 then
    Result := ParamStr(1)
  else
    Result := '';
end;

procedure ProcessMessages;
begin
  while GetMessage(Msg, 0, 0, 0) do
  begin
    if Msg.message = WM_CLOSE_FARM_SERVICE then
      Break;

    TranslateMessage(Msg);
    DispatchMessage(Msg);

    Sleep(100);
  end;

end;

procedure Deinit;
begin
  uSteamAPI.Shutdown;
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
  SetConsoleCtrlHandler(@ConsoleEventProc, True);

  AppDir := ExtractFilePath(ParamStr(0));
  AppId := GetAppId;

  if AppId = '' then
    RaiseException('No app id as a parameter');

  if ParamCount = 2 then
    IsTest := ParamStr(2).ToLower = 'test';

end;

function InitSteamApi: Boolean;
begin
  Result := False;

  Print('Try to init Steam api...');
  if uSteamAPI.Initialize(AppDir + STEAM_API_DLL) then
  begin
    Print('Ok.');

    if uSteamAPI.SteamAPI_IsSteamRunning then
    begin
      Result := True;

    end
      else
    Print('Error: Steam is not running');

  end
    else
  Print('Error: can''t init Steam api');
end;

begin
  try
    Init;

    SetEnvironmentVariable(PChar('SteamAppId'), PChar(AppId));

    if InitSteamApi then
    begin
      Print(Format('Idle... App id: %s', [AppId]));

      ProcessMessages;
    end;

  except
    on E: Exception do
      Writeln('Error: ', E.Message);
  end;

  if IsTest then
    Readln;
end.
