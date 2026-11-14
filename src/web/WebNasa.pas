unit WebNasa;

{ TradeSpace - loading open NASA data into the game.

  Three NASA services drive the gameplay:
    EONET  - real natural events on Earth become the targets of the
             Disaster Watch scenario (and set its science priorities)
    DONKI  - real solar flares, particle storms and geomagnetic storms
             strike the spacecraft during every mission
    NeoWs  - the real Apophis flyby date sets the deadline of Race to Apophis

  A snapshot of all three ships with the game (public/data/nasa-snapshot.json,
  made by scripts/fetch-nasa-data.mjs) so it always works, even offline or
  behind a firewall. When the network allows, EONET is refreshed live.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$mode objfpc}

interface

uses
  JS, Web, SysUtils, TsTypes;

type
  TNasaStatus = record
    Loaded: Boolean;
    SnapshotDate: string;
    EonetCount, EonetTotal: Integer;
    EonetLive: Boolean;
    DonkiCount: Integer;
    DonkiFrom, DonkiTo: string;
    ApophisDays: Integer;
    ApophisDate: string;
  end;
  TNotifyProc = procedure of object;

var
  NasaStatus: TNasaStatus;

{ Load the bundled snapshot, then try a live refresh. OnChange is called
  each time new data has been applied, so the screen can redraw. }
procedure LoadNasaData(OnChange: TNotifyProc);
function DaysUntil(const IsoDate: string): Integer;

implementation

uses
  TsScenarios, TsFmt;

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
  else if isString(O[Name]) then
    Result := ParseFloat(String(O[Name]))
  else
    Result := 0;
end;

function DaysUntil(const IsoDate: string): Integer;
begin
  Result := DayNumber(IsoDate) - DayNumber(Copy(TJSDate.New.toISOString, 1, 10));
end;

procedure ApplyApophisFrom(O: TJSObject);
var
  D: string;
begin
  D := StrOf(O, 'approachDate');
  if D = '' then
    D := '2029-04-13';
  NasaStatus.ApophisDate := D;
  NasaStatus.ApophisDays := DaysUntil(D);
  { The countdown is real: the scenario gets harder every day. }
  ApplyApophis(NasaStatus.ApophisDays, NumOf(O, 'missKm'), NumOf(O, 'relVelKmS'), D);
end;

procedure ApplySnapshot(Snap: TJSObject);
var
  Sec: TJSObject;
  Arr: TJSArray;
  O: TJSObject;
  Ev: TEarthEventArray;
  Sw: TSpaceWeatherArray;
  I, N: Integer;
begin
  NasaStatus.SnapshotDate := Copy(StrOf(Snap, 'generated'), 1, 10);

  if isObject(Snap['eonet']) then
  begin
    Sec := TJSObject(Snap['eonet']);
    if isArray(Sec['events']) then
    begin
      Arr := TJSArray(Sec['events']);
      SetLength(Ev, 0);
      for I := 0 to Arr.length - 1 do
      begin
        O := TJSObject(Arr[I]);
        N := Length(Ev);
        SetLength(Ev, N + 1);
        Ev[N].Title := StrOf(O, 't');
        Ev[N].Category := StrOf(O, 'c');
        Ev[N].Date := StrOf(O, 'd');
        Ev[N].Lat := NumOf(O, 'lat');
        Ev[N].Lon := NumOf(O, 'lon');
      end;
      NasaStatus.EonetCount := Length(Ev);
      NasaStatus.EonetTotal := Round(NumOf(Sec, 'total'));
      NasaStatus.EonetLive := False;
      ApplyEarthEvents(Ev, 'NASA EONET, ' + NiceDate(NasaStatus.SnapshotDate));
    end;
  end;

  if isObject(Snap['donki']) then
  begin
    Sec := TJSObject(Snap['donki']);
    if isArray(Sec['events']) then
    begin
      Arr := TJSArray(Sec['events']);
      SetLength(Sw, 0);
      for I := 0 to Arr.length - 1 do
      begin
        O := TJSObject(Arr[I]);
        N := Length(Sw);
        SetLength(Sw, N + 1);
        Sw[N].Kind := StrOf(O, 'k');
        Sw[N].Date := StrOf(O, 'd');
        Sw[N].ClassType := StrOf(O, 'cls');
        Sw[N].Strength := WeatherStrength(Sw[N].Kind, Sw[N].ClassType);
      end;
      NasaStatus.DonkiCount := Length(Sw);
      NasaStatus.DonkiFrom := StrOf(Sec, 'from');
      NasaStatus.DonkiTo := StrOf(Sec, 'to');
      if Length(Sw) > 0 then
        ApplySpaceWeather(Sw, 'NASA DONKI, ' + NiceDate(NasaStatus.DonkiFrom) + ' to ' + NiceDate(NasaStatus.DonkiTo));
    end;
  end;

  if isObject(Snap['apophis']) then
    ApplyApophisFrom(TJSObject(Snap['apophis']));
  NasaStatus.Loaded := True;
end;

{ Turn a live EONET reply into the game's event list. }
function ParseEonetLive(Reply: TJSObject; out Total: Integer): TEarthEventArray;
var
  Arr, Geo, Cats, Co, Ring: TJSArray;
  O, G: TJSObject;
  I, J, N, Fires, Step: Integer;
  Lon, Lat: Double;
  Cat: string;
begin
  SetLength(Result, 0);
  Total := 0;
  if not isArray(Reply['events']) then
    Exit;
  Arr := TJSArray(Reply['events']);
  Total := Arr.length;
  Fires := 0;
  for I := 0 to Arr.length - 1 do
  begin
    O := TJSObject(Arr[I]);
    if isArray(O['categories']) and (TJSArray(O['categories']).length > 0) and
      (StrOf(TJSObject(TJSArray(O['categories'])[0]), 'id') = 'wildfires') then
      Inc(Fires);
  end;
  { There are thousands of wildfires. Keep an even sample of about 260. }
  Step := Fires div 260;
  if Step < 1 then
    Step := 1;
  Fires := 0;
  for I := 0 to Arr.length - 1 do
  begin
    O := TJSObject(Arr[I]);
    if not (isArray(O['categories']) and isArray(O['geometry'])) then
      Continue;
    Cats := TJSArray(O['categories']);
    Geo := TJSArray(O['geometry']);
    if (Cats.length = 0) or (Geo.length = 0) then
      Continue;
    Cat := StrOf(TJSObject(Cats[0]), 'id');
    if Cat = 'wildfires' then
    begin
      Inc(Fires);
      if Fires mod Step <> 0 then
        Continue;
    end;
    G := TJSObject(Geo[Geo.length - 1]);
    if not isArray(G['coordinates']) then
      Continue;
    Co := TJSArray(G['coordinates']);
    if StrOf(G, 'type') = 'Point' then
    begin
      if Co.length < 2 then
        Continue;
      Lon := Double(Co[0]);
      Lat := Double(Co[1]);
    end
    else
    begin
      { A polygon: use the centre of its outer ring. }
      if (Co.length = 0) or not isArray(Co[0]) then
        Continue;
      Ring := TJSArray(Co[0]);
      if Ring.length = 0 then
        Continue;
      Lon := 0;
      Lat := 0;
      for J := 0 to Ring.length - 1 do
      begin
        Lon := Lon + Double(TJSArray(Ring[J])[0]);
        Lat := Lat + Double(TJSArray(Ring[J])[1]);
      end;
      Lon := Lon / Ring.length;
      Lat := Lat / Ring.length;
    end;
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N].Title := StrOf(O, 'title');
    Result[N].Category := Cat;
    Result[N].Date := Copy(StrOf(G, 'date'), 1, 10);
    Result[N].Lat := Lat;
    Result[N].Lon := Lon;
  end;
end;

procedure DoLoad(OnChange: TNotifyProc); async;
var
  Resp: TJSResponse;
  Txt: string;
  Ev: TEarthEventArray;
  Total: Integer;
begin
  { 1. The bundled snapshot: always available. }
  try
    Resp := await(window.fetch('data/nasa-snapshot.json'));
    if Resp.ok then
    begin
      Txt := await(Resp.text());
      ApplySnapshot(TJSObject(TJSJSON.parse(Txt)));
      if Assigned(OnChange) then
        OnChange();
    end;
  except
    on E: Exception do
      console.warn('NASA snapshot not loaded: ' + E.Message);
  end;

  { 2. Live refresh of natural events from NASA EONET (no key needed). }
  try
    Resp := await(window.fetch('https://eonet.gsfc.nasa.gov/api/v3/events?days=30&status=all'));
    if Resp.ok then
    begin
      Txt := await(Resp.text());
      Ev := ParseEonetLive(TJSObject(TJSJSON.parse(Txt)), Total);
      if Length(Ev) >= 30 then
      begin
        NasaStatus.EonetCount := Length(Ev);
        NasaStatus.EonetTotal := Total;
        NasaStatus.EonetLive := True;
        NasaStatus.Loaded := True;
        ApplyEarthEvents(Ev, 'NASA EONET, live ' + NiceDate(Copy(TJSDate.New.toISOString, 1, 10)));
        if Assigned(OnChange) then
          OnChange();
      end;
    end;
  except
    on E: Exception do
      console.warn('Live EONET refresh skipped: ' + E.Message);
  end;
end;

procedure LoadNasaData(OnChange: TNotifyProc);
begin
  NasaStatus.Loaded := False;
  NasaStatus.EonetLive := False;
  NasaStatus.ApophisDate := '2029-04-13';
  NasaStatus.ApophisDays := DaysUntil('2029-04-13');
  { Even with no data at all, the Apophis clock runs on the real calendar. }
  ApplyApophis(NasaStatus.ApophisDays, 38011, 7.42, '2029-04-13');
  DoLoad(OnChange);
end;

end.
