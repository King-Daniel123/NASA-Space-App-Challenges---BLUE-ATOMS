unit WebStore;

{ Atomic Space - saving the mission log and settings in the browser.

  Everything stays on the player's own device (localStorage). Nothing is sent
  to a server and no account is needed.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$mode objfpc}

interface

uses
  JS, Web, SysUtils;

type
  TLogEntry = record
    Date, Scenario, ScenarioName, Grade, Outcome, Crew, Code: string;
    Score, Players: Integer;
    SciencePct, CostM, CapM: Double;
  end;
  TLogEntryArray = array of TLogEntry;

function LoadLog: TLogEntryArray;
procedure AddLogEntry(const E: TLogEntry);
procedure ClearLog;
function LoadSetting(const Key, Default: string): string;
procedure SaveSetting(const Key, Value: string);

implementation

const
  LogKey = 'tradespace.log.v1';
  SetPrefix = 'tradespace.set.';
  MaxEntries = 60;

function ReadKey(const Key: string): string;
var
  V: JSValue;
begin
  Result := '';
  try
    V := window.localStorage.getItem(Key);
    if isString(V) then
      Result := String(V);
  except
    Result := '';   // storage can be blocked, e.g. in private browsing
  end;
end;

procedure WriteKey(const Key, Value: string);
begin
  try
    window.localStorage.setItem(Key, Value);
  except
    // ignore: the game still works, it just will not remember
  end;
end;

function StrOf(O: TJSObject; const Name: string): string;
begin
  if isString(O[Name]) then
    Result := String(O[Name])
  else
    Result := '';
end;

function NumOf(O: TJSObject; const Name: string): Double;
begin
  if isNumber(O[Name]) then
    Result := Double(O[Name])
  else
    Result := 0;
end;

function LoadLog: TLogEntryArray;
var
  Raw: string;
  V: JSValue;
  Arr: TJSArray;
  O: TJSObject;
  I, N: Integer;
begin
  SetLength(Result, 0);
  Raw := ReadKey(LogKey);
  if Raw = '' then
    Exit;
  try
    V := TJSJSON.parse(Raw);
  except
    Exit;
  end;
  if not isArray(V) then
    Exit;
  Arr := TJSArray(V);
  for I := 0 to Arr.length - 1 do
  begin
    if not isObject(Arr[I]) then
      Continue;
    O := TJSObject(Arr[I]);
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N].Date := StrOf(O, 'date');
    Result[N].Scenario := StrOf(O, 'scen');
    Result[N].ScenarioName := StrOf(O, 'name');
    Result[N].Grade := StrOf(O, 'grade');
    Result[N].Outcome := StrOf(O, 'outcome');
    Result[N].Crew := StrOf(O, 'crew');
    Result[N].Code := StrOf(O, 'code');
    Result[N].Score := Round(NumOf(O, 'score'));
    Result[N].Players := Round(NumOf(O, 'players'));
    Result[N].SciencePct := NumOf(O, 'sci');
    Result[N].CostM := NumOf(O, 'cost');
    Result[N].CapM := NumOf(O, 'cap');
  end;
end;

procedure SaveLog(const L: TLogEntryArray);
var
  Arr: TJSArray;
  O: TJSObject;
  I: Integer;
begin
  Arr := TJSArray.new;
  for I := 0 to High(L) do
  begin
    O := TJSObject.new;
    O['date'] := L[I].Date;
    O['scen'] := L[I].Scenario;
    O['name'] := L[I].ScenarioName;
    O['grade'] := L[I].Grade;
    O['outcome'] := L[I].Outcome;
    O['crew'] := L[I].Crew;
    O['code'] := L[I].Code;
    O['score'] := L[I].Score;
    O['players'] := L[I].Players;
    O['sci'] := L[I].SciencePct;
    O['cost'] := L[I].CostM;
    O['cap'] := L[I].CapM;
    Arr.push(O);
  end;
  WriteKey(LogKey, TJSJSON.stringify(Arr));
end;

procedure AddLogEntry(const E: TLogEntry);
var
  L, Trimmed: TLogEntryArray;
  I, N: Integer;
begin
  L := LoadLog;
  N := Length(L);
  SetLength(L, N + 1);
  L[N] := E;
  { Keep the newest entries only. }
  if Length(L) > MaxEntries then
  begin
    SetLength(Trimmed, MaxEntries);
    for I := 0 to MaxEntries - 1 do
      Trimmed[I] := L[Length(L) - MaxEntries + I];
    L := Trimmed;
  end;
  SaveLog(L);
end;

procedure ClearLog;
begin
  try
    window.localStorage.removeItem(LogKey);
  except
  end;
end;

function LoadSetting(const Key, Default: string): string;
begin
  Result := ReadKey(SetPrefix + Key);
  if Result = '' then
    Result := Default;
end;

procedure SaveSetting(const Key, Value: string);
begin
  WriteKey(SetPrefix + Key, Value);
end;

end.
