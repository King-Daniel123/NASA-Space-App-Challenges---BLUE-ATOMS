unit TsScenarios;

{ Atomic Space - the mission scenarios (announcements of opportunity).

  Each scenario describes a destination, a science goal, a cost cap, the
  orbits and routes on offer and the real missions it is modelled on.
  Distances, sunlight and timings come from NASA Planetary Fact Sheets and
  mission press kits, rounded for teaching.

  Two scenarios are driven by live NASA data:
    Earth   - targets are real natural events from NASA EONET
    Apophis - the deadline is the real 2029 flyby date from NASA NeoWs / JPL

  AI-assistance note: written with the help of Claude (Anthropic). }

{$IFDEF PAS2JS}{$mode delphi}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$ENDIF}

interface

uses
  TsTypes;

var
  Scenarios: array of TScenario;
  EarthEvents: TEarthEventArray;       // real events currently loaded
  EarthEventsSource: string;           // e.g. 'NASA EONET, 14 Nov 2026'
  SpaceWeather: TSpaceWeatherArray;    // real space-weather events loaded
  SpaceWeatherSource: string;
  ApophisMissKm, ApophisVelKmS, ApophisDays: Double;
  ApophisDate: string;

function FindScenario(const AId: string): Integer;
function PrimaryMeasure(const S: TScenario): TMeasure;
function EventVisible(const O: TOrbit; Lat, Lon: Double): Boolean;
function CategorySuit(const Cat: string; M: TMeasure): Double;
function CategoryImportance(const Cat: string): Double;
function CategoryLabel(const Cat: string): string;

{ Feed real NASA EONET events into the Earth scenario: the science priorities
  and what each orbit can see are recalculated from where the events are. }
procedure ApplyEarthEvents(const Ev: TEarthEventArray; const ASource: string);
{ Feed real NASA DONKI space-weather events into the simulation deck. }
procedure ApplySpaceWeather(const Sw: TSpaceWeatherArray; const ASource: string);
{ Turn a DONKI class such as 'X2.8' or 'Kp 7' into a 0..1 game strength. }
function WeatherStrength(const Kind, ClassType: string): Double;
function WeatherLabel(const W: TSpaceWeather): string;
{ Set the Apophis deadline from the real number of days left until the flyby. }
procedure ApplyApophis(DaysToFlyby, MissKm, VelKmS: Double; const ADate: string);

implementation

uses
  Math, TsCatalog, TsFmt;

function FindScenario(const AId: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Scenarios) do
    if Scenarios[I].Id = AId then
    begin
      Result := I;
      Exit;
    end;
end;

function PrimaryMeasure(const S: TScenario): TMeasure;
var
  M: TMeasure;
begin
  Result := mImaging;
  for M := Low(TMeasure) to High(TMeasure) do
    if S.Weight[M] > S.Weight[Result] then
      Result := M;
end;

function EventVisible(const O: TOrbit; Lat, Lon: Double): Boolean;
var
  Ang, DLon: Double;
begin
  if O.IsGeo then
  begin
    { A geostationary satellite sees a disc of the globe below it. }
    DLon := (Lon - O.GeoLon) * Pi / 180;
    Ang := ArcCos(Clamp(Cos(Lat * Pi / 180) * Cos(DLon), -1, 1)) * 180 / Pi;
    Result := Ang <= 62;
  end
  else if O.IncDeg >= 90 then
    Result := Abs(Lat) <= 86
  else
    { An inclined orbit never flies over latitudes above its inclination. }
    Result := Abs(Lat) <= O.IncDeg + 4;
end;

function CategoryLabel(const Cat: string): string;
begin
  if Cat = 'wildfires' then Result := 'Wildfires'
  else if Cat = 'severeStorms' then Result := 'Severe storms'
  else if Cat = 'volcanoes' then Result := 'Volcanoes'
  else if Cat = 'floods' then Result := 'Floods'
  else if Cat = 'seaLakeIce' then Result := 'Sea and lake ice'
  else if Cat = 'dustHaze' then Result := 'Dust and haze'
  else if Cat = 'drought' then Result := 'Drought'
  else if Cat = 'landslides' then Result := 'Landslides'
  else if Cat = 'snow' then Result := 'Snow'
  else if Cat = 'tempExtremes' then Result := 'Temperature extremes'
  else if Cat = 'earthquakes' then Result := 'Earthquakes'
  else if Cat = 'waterColor' then Result := 'Water colour'
  else if Cat = 'manmade' then Result := 'Human-made events'
  else Result := Cat;
end;

function CategoryImportance(const Cat: string): Double;
begin
  { A single hurricane matters more than a single small fire. }
  if Cat = 'severeStorms' then Result := 8
  else if Cat = 'volcanoes' then Result := 6
  else if Cat = 'floods' then Result := 3
  else if Cat = 'drought' then Result := 3
  else if Cat = 'landslides' then Result := 3
  else if Cat = 'earthquakes' then Result := 3
  else if Cat = 'seaLakeIce' then Result := 2
  else if Cat = 'dustHaze' then Result := 2
  else Result := 1;
end;

function CategorySuit(const Cat: string; M: TMeasure): Double;
begin
  { How useful each kind of measurement is for each kind of event. }
  Result := 0;
  if Cat = 'wildfires' then
    case M of
      mThermal: Result := 1.0;
      mImaging: Result := 0.5;
      mSpectral: Result := 0.5;
      mRadar: Result := 0.3;
      mAtmos: Result := 0.2;
    end
  else if Cat = 'severeStorms' then
    case M of
      mAtmos: Result := 1.0;
      mImaging: Result := 0.6;
      mThermal: Result := 0.4;
      mRadar: Result := 0.4;
    end
  else if Cat = 'volcanoes' then
    case M of
      mThermal: Result := 1.0;
      mSpectral: Result := 0.6;
      mRadar: Result := 0.6;
      mImaging: Result := 0.5;
      mAtmos: Result := 0.4;
    end
  else if Cat = 'floods' then
    case M of
      mRadar: Result := 1.0;
      mImaging: Result := 0.6;
      mSpectral: Result := 0.4;
      mThermal: Result := 0.2;
    end
  else if Cat = 'seaLakeIce' then
    case M of
      mRadar: Result := 1.0;
      mImaging: Result := 0.6;
      mThermal: Result := 0.5;
      mAtmos: Result := 0.2;
    end
  else if Cat = 'dustHaze' then
    case M of
      mImaging: Result := 0.8;
      mAtmos: Result := 0.8;
      mSpectral: Result := 0.5;
    end
  else if Cat = 'drought' then
    case M of
      mSpectral: Result := 0.9;
      mThermal: Result := 0.8;
      mImaging: Result := 0.4;
    end
  else if (Cat = 'landslides') or (Cat = 'earthquakes') then
    case M of
      mRadar: Result := 0.9;
      mImaging: Result := 0.8;
    end
  else
    case M of
      mImaging: Result := 0.5;
      mSpectral: Result := 0.3;
    end;
end;

procedure ApplyEarthEvents(const Ev: TEarthEventArray; const ASource: string);
var
  SI, OI, I: Integer;
  M: TMeasure;
  Tot, Seen: TMeasureValues;
  W, MaxW, SumW, Imp: Double;
  Vis: Boolean;
begin
  SI := FindScenario('earth');
  if (SI < 0) or (Length(Ev) < 10) then
    Exit;
  EarthEvents := Ev;
  EarthEventsSource := ASource;

  { 1. The planet sets the science priorities. }
  for M := Low(TMeasure) to High(TMeasure) do
    Tot[M] := 0;
  for I := 0 to High(Ev) do
  begin
    Imp := CategoryImportance(Ev[I].Category);
    for M := Low(TMeasure) to High(TMeasure) do
      Tot[M] := Tot[M] + Imp * CategorySuit(Ev[I].Category, M);
  end;
  MaxW := 0;
  for M := Low(TMeasure) to High(TMeasure) do
    if Tot[M] > MaxW then
      MaxW := Tot[M];
  if MaxW <= 0 then
    Exit;
  SumW := 0;
  for M := Low(TMeasure) to High(TMeasure) do
  begin
    W := Round(100 * Tot[M] / MaxW) / 100;
    Scenarios[SI].Weight[M] := W;
    SumW := SumW + W;
  end;
  Scenarios[SI].FullScience := 0.45 * SumW;

  { 2. Where the events are decides what each orbit can see. }
  for OI := 0 to High(Scenarios[SI].Orbits) do
  begin
    for M := Low(TMeasure) to High(TMeasure) do
      Seen[M] := 0;
    Scenarios[SI].Orbits[OI].EventsSeen := 0;
    Scenarios[SI].Orbits[OI].EventsTotal := Length(Ev);
    for I := 0 to High(Ev) do
    begin
      Vis := EventVisible(Scenarios[SI].Orbits[OI], Ev[I].Lat, Ev[I].Lon);
      if Vis then
      begin
        Inc(Scenarios[SI].Orbits[OI].EventsSeen);
        Imp := CategoryImportance(Ev[I].Category);
        for M := Low(TMeasure) to High(TMeasure) do
          Seen[M] := Seen[M] + Imp * CategorySuit(Ev[I].Category, M);
      end;
    end;
    for M := Low(TMeasure) to High(TMeasure) do
      if Tot[M] > 0 then
        Scenarios[SI].Orbits[OI].Factor[M] :=
          Scenarios[SI].Orbits[OI].Base[M] * Seen[M] / Tot[M]
      else
        Scenarios[SI].Orbits[OI].Factor[M] := Scenarios[SI].Orbits[OI].Base[M];
    Scenarios[SI].Orbits[OI].Coverage := 1.0;
  end;
end;

procedure ApplySpaceWeather(const Sw: TSpaceWeatherArray; const ASource: string);
begin
  if Length(Sw) = 0 then
    Exit;
  SpaceWeather := Sw;
  SpaceWeatherSource := ASource;
end;

function WeatherStrength(const Kind, ClassType: string): Double;
var
  N: Double;
begin
  Result := 0.3;
  if Kind = 'FLR' then
  begin
    N := ParseFloat(Copy(ClassType, 2, 8));
    if (Length(ClassType) > 0) and (ClassType[1] = 'X') then
      Result := 0.5 + MinD(0.5, N / 20)
    else
      Result := 0.2 + MinD(0.2, N * 0.02);
  end
  else if Kind = 'GST' then
    Result := Clamp(ParseFloat(ClassType) / 9, 0.1, 1)   // 'Kp 7' -> 0.78
  else if Kind = 'SEP' then
    Result := 0.7;
end;

function WeatherLabel(const W: TSpaceWeather): string;
begin
  if W.Kind = 'FLR' then
    Result := 'class ' + W.ClassType + ' solar flare'
  else if W.Kind = 'GST' then
    Result := 'geomagnetic storm (' + W.ClassType + ')'
  else
    Result := 'solar energetic particle storm';
  Result := Result + ' on ' + NiceDate(W.Date);
end;

procedure AddWeather(const AKind, ADate, AClass: string);
var
  N: Integer;
begin
  N := Length(SpaceWeather);
  SetLength(SpaceWeather, N + 1);
  SpaceWeather[N].Kind := AKind;
  SpaceWeather[N].Date := ADate;
  SpaceWeather[N].ClassType := AClass;
  SpaceWeather[N].Strength := WeatherStrength(AKind, AClass);
end;

procedure BuildFallbackWeather;
begin
  { Famous real events, used only if the live NASA DONKI feed and the bundled
    snapshot are both unavailable. }
  AddWeather('GST', '2022-02-04', 'Kp 5');     // brought down 38 new Starlink satellites
  AddWeather('SEP', '2017-09-10', 'SEP');      // seen at Mars by MAVEN and Curiosity
  AddWeather('FLR', '2017-09-10', 'X8.2');
  AddWeather('FLR', '2003-10-28', 'X17');      // the Halloween storms
  AddWeather('SEP', '2003-10-28', 'SEP');
  AddWeather('GST', '2024-05-10', 'Kp 9');     // strongest geomagnetic storm in 20 years
  AddWeather('FLR', '2024-05-14', 'X8.7');
  AddWeather('FLR', '2024-10-03', 'X9.0');
  SpaceWeatherSource := 'historic events (NASA)';
end;

procedure ApplyApophis(DaysToFlyby, MissKm, VelKmS: Double; const ADate: string);
var
  SI: Integer;
begin
  SI := FindScenario('apophis');
  if SI < 0 then
    Exit;
  ApophisDays := DaysToFlyby;
  ApophisMissKm := MissKm;
  ApophisVelKmS := VelKmS;
  ApophisDate := ADate;
  { Be on station about a month before closest approach. The floor keeps
    the scenario playable when the real date gets very close. }
  Scenarios[SI].DeadlineYears := MaxD(2.0, DaysToFlyby / 365.25 - 0.08);
end;

{ ---- builders ---------------------------------------------------------- }

function NewOrbit(const AId, AName, ABlurb, AWhy: string): TOrbit;
var
  M: TMeasure;
begin
  Result.Id := AId;
  Result.Name := AName;
  Result.Blurb := ABlurb;
  Result.Why := AWhy;
  Result.AltKm := 0;
  Result.ApoKm := 0;
  Result.IncDeg := 0;
  Result.PeriodHr := 2;
  Result.EclipseFrac := 0;
  Result.MaxEclipseHr := 0;
  Result.Coverage := 1;
  for M := Low(TMeasure) to High(TMeasure) do
  begin
    Result.Factor[M] := 1;
    Result.Base[M] := 1;
  end;
  Result.EventsSeen := 0;
  Result.EventsTotal := 0;
  Result.TauFactor := 1;
  Result.DataFactor := 1;
  Result.CommFactor := 1;
  Result.RangeKm := 0;
  Result.DvInsert := 0;
  Result.DvPerYear := 0;
  Result.LvMode := lvC3;
  Result.C3 := 0;
  Result.ExtraYears := 0;
  Result.InsertRisk := 0;
  Result.RadLevel := 1;
  Result.RadLifeYears := 0;
  Result.DragLifeYears := 0;
  Result.NeedsDeorbit := False;
  Result.IsGeo := False;
  Result.GeoLon := 0;
end;

procedure SetFactors(var O: TOrbit; const V: TMeasureValues);
var
  M: TMeasure;
begin
  for M := Low(TMeasure) to High(TMeasure) do
  begin
    O.Factor[M] := V[M];
    O.Base[M] := V[M];
  end;
end;

procedure AddOrbit(var S: TScenario; const O: TOrbit);
var
  N: Integer;
begin
  N := Length(S.Orbits);
  SetLength(S.Orbits, N + 1);
  S.Orbits[N] := O;
  if S.Orbits[N].ApoKm = 0 then
    S.Orbits[N].ApoKm := S.Orbits[N].AltKm;
end;

procedure AddTransfer(var S: TScenario; const AId, AName, ABlurb: string;
  AC3, ACruise, ADvFactor: Double; AHot: Boolean);
var
  N: Integer;
begin
  N := Length(S.Transfers);
  SetLength(S.Transfers, N + 1);
  S.Transfers[N].Id := AId;
  S.Transfers[N].Name := AName;
  S.Transfers[N].Blurb := ABlurb;
  S.Transfers[N].C3 := AC3;
  S.Transfers[N].CruiseYears := ACruise;
  S.Transfers[N].DvFactor := ADvFactor;
  S.Transfers[N].HotFlyby := AHot;
end;

procedure AddAnalog(var S: TScenario; const AName, AAgency, AYear, ABlurb, AUrl: string;
  AMass, ACost: Double; AInstr: Integer);
var
  N: Integer;
begin
  N := Length(S.Analogs);
  SetLength(S.Analogs, N + 1);
  S.Analogs[N].Name := AName;
  S.Analogs[N].Agency := AAgency;
  S.Analogs[N].Year := AYear;
  S.Analogs[N].Blurb := ABlurb;
  S.Analogs[N].Url := AUrl;
  S.Analogs[N].MassKg := AMass;
  S.Analogs[N].CostM := ACost;
  S.Analogs[N].Instruments := AInstr;
end;

function NewScenario(const AId, AName, ATagline, ABody: string; ALevel: Integer): TScenario;
var
  M: TMeasure;
begin
  Result.Id := AId;
  Result.Name := AName;
  Result.Tagline := ATagline;
  Result.Body := ABody;
  Result.Brief := '';
  Result.Objective := '';
  Result.Level := ALevel;
  Result.CostCapM := 100;
  Result.DeadlineYears := 4;
  Result.WindowYears := 0;
  Result.WindowPeriod := 0;
  Result.ArriveBy := False;
  Result.LateFactor := 1;
  Result.MinLife := 1;
  Result.MaxLife := 5;
  Result.DefaultLife := 2;
  Result.SunAU := 1;
  Result.EarthMinAU := 0;
  Result.EarthMaxAU := 0;
  Result.SynodicDays := 0;
  Result.NearEarth := False;
  Result.DataScale := 1;
  Result.HeaterW := 0;
  Result.ColdWorld := False;
  Result.AllowRTG := False;
  Result.AllowSEP := False;
  Result.SepDvFactor := 1;
  Result.SepExtraYears := 0;
  for M := Low(TMeasure) to High(TMeasure) do
    Result.Weight[M] := 0;
  Result.FullScience := 2;
  Result.ThresholdPct := 40;
  Result.TauYears := 1;
  SetLength(Result.Orbits, 0);
  SetLength(Result.Transfers, 0);
  SetLength(Result.Instruments, 0);
  SetLength(Result.Analogs, 0);
  SetLength(Result.Facts, 0);
  Result.UsesEonet := False;
  Result.UsesApophis := False;
end;

procedure AddScenario(const S: TScenario);
var
  N: Integer;
begin
  N := Length(Scenarios);
  SetLength(Scenarios, N + 1);
  Scenarios[N] := S;
end;

procedure Offer(var S: TScenario; const Ids: array of string);
var
  I: Integer;
begin
  for I := 0 to High(Ids) do
    AddStr(S.Instruments, Ids[I]);
end;

{ ---- Earth ------------------------------------------------------------- }

procedure BuildEarth;
var
  S: TScenario;
  O: TOrbit;
begin
  S := NewScenario('earth', 'Disaster Watch', 'Keep watch over a restless planet', 'Earth', 1);
  S.Brief := 'Right now, satellites are tracking hundreds of wildfires, floods, storms and ice ' +
    'events around the world. NASA''s Earth Observatory Natural Event Tracker (EONET) lists ' +
    'them as they happen, and emergency teams need eyes on every one.';
  S.Objective := 'Build a small Earth-observation satellite that can see as many of today''s real ' +
    'natural events as possible, with the right instruments, and get the data home.';
  S.CostCapM := 120;
  S.DeadlineYears := 3.5;
  S.MinLife := 1;
  S.MaxLife := 7;
  S.DefaultLife := 3;
  S.SunAU := 1;
  S.NearEarth := True;
  S.Weight := MV(0.7, 0.5, 1.0, 0.85, 0.2, 0, 0.9, 0.1, 0);
  S.FullScience := 1.9;
  S.ThresholdPct := 40;
  S.TauYears := 1.5;
  S.UsesEonet := True;

  O := NewOrbit('iss', 'Mid-inclination low orbit', '420 km high, tilted 51.6 degrees, like the Space Station.',
    'Flies over everywhere between 52 N and 52 S, where most people live. It never sees the far north or south, ' +
    'and thin air this low slowly drags the satellite down.');
  O.AltKm := 420; O.IncDeg := 51.6; O.PeriodHr := 1.55;
  O.EclipseFrac := 0.38; O.MaxEclipseHr := 0.6;
  O.Coverage := 0.8; O.CommFactor := 0.9; O.RangeKm := 2000;
  O.LvMode := lvLEO; O.DvPerYear := 30; O.RadLevel := 0; O.DragLifeYears := 1.5;
  AddOrbit(S, O);

  O := NewOrbit('tropic', 'Tropical low orbit', '550 km high, tilted only 30 degrees.',
    'Stays over the tropics and comes back to the same storm again and again. Blind to everything beyond 34 degrees latitude.');
  O.AltKm := 550; O.IncDeg := 30; O.PeriodHr := 1.6;
  O.EclipseFrac := 0.36; O.MaxEclipseHr := 0.6;
  O.Coverage := 0.5; O.CommFactor := 0.7; O.RangeKm := 2200;
  SetFactors(O, MV(1, 1, 1, 1, 1, 1, 1.15, 1, 1));
  O.LvMode := lvLEO; O.DvPerYear := 8; O.RadLevel := 0; O.DragLifeYears := 6;
  AddOrbit(S, O);

  O := NewOrbit('sso', 'Sun-synchronous polar orbit', '700 km high, passing near both poles.',
    'Sees the whole planet, always in the same lighting, and polar ground stations hear it on every lap. ' +
    'So high that it would stay up for centuries, so it must carry fuel to bring itself down.');
  O.AltKm := 700; O.IncDeg := 98; O.PeriodHr := 1.65;
  O.EclipseFrac := 0.30; O.MaxEclipseHr := 0.6;
  O.Coverage := 1.0; O.CommFactor := 1.25; O.RangeKm := 2500;
  SetFactors(O, MV(0.95, 1, 0.95, 0.95, 0.95, 1, 0.95, 1, 1));
  O.LvMode := lvSSO; O.DvPerYear := 3; O.RadLevel := 0; O.NeedsDeorbit := True;
  AddOrbit(S, O);

  O := NewOrbit('geo_am', 'Geostationary: Americas', '35,786 km up, parked over 75 W.',
    'Stares at the Americas without ever blinking, perfect for following a storm minute by minute. ' +
    'But it is 85 times farther away than a low orbit, so detail is poor, radar is impossible and getting there takes a big engine burn.');
  O.AltKm := 35786; O.IncDeg := 0; O.PeriodHr := 24;
  O.EclipseFrac := 0.02; O.MaxEclipseHr := 1.2;
  O.Coverage := 0.38; O.CommFactor := 20; O.RangeKm := 38000;
  SetFactors(O, MV(0.4, 0.35, 0.85, 0.03, 0.1, 1, 1.35, 1, 1));
  O.LvMode := lvGTO; O.DvInsert := 1500; O.DvPerYear := 50; O.RadLevel := 1;
  O.IsGeo := True; O.GeoLon := -75;
  AddOrbit(S, O);

  O.Id := 'geo_af'; O.Name := 'Geostationary: Africa and Europe';
  O.Blurb := '35,786 km up, parked over 20 E.';
  O.Why := 'The same unblinking stare, centred on Africa and Europe. Great for fires and storms there, blind to the rest of the world.';
  O.GeoLon := 20;
  AddOrbit(S, O);

  O.Id := 'geo_as'; O.Name := 'Geostationary: Asia and Pacific';
  O.Blurb := '35,786 km up, parked over 140 E.';
  O.Why := 'Centred on East Asia, Australia and the western Pacific, where typhoons are born.';
  O.GeoLon := 140;
  AddOrbit(S, O);

  AddTransfer(S, 'direct', 'Direct launch', 'The rocket drops the satellite straight into its orbit.', 0, 0, 1, False);
  Offer(S, ['cam_ctx', 'cam_hires', 'spec_vnir', 'tir', 'sar', 'radiometer', 'uvs']);

  AddAnalog(S, 'Landsat 9', 'NASA / USGS', '2021', 'Sun-synchronous orbit at 705 km. Two instruments: a multispectral imager and a thermal imager.',
    'https://science.nasa.gov/mission/landsat-9/', 2711, 750, 2);
  AddAnalog(S, 'TROPICS', 'NASA', '2023', 'Four 5 kg CubeSats in a 30 degree orbit, each with one microwave radiometer, revisiting storms about hourly.',
    'https://science.nasa.gov/mission/tropics/', 21, 30, 1);
  AddAnalog(S, 'NISAR', 'NASA / ISRO', '2025', 'A joint US-India radar satellite that maps almost all land and ice every 12 days, day or night, through cloud.',
    'https://science.nasa.gov/mission/nisar/', 2400, 1500, 2);
  AddAnalog(S, 'CYGNSS', 'NASA', '2016', 'Eight microsatellites in a 35 degree orbit measuring winds inside hurricanes.',
    'https://science.nasa.gov/mission/cygnss/', 232, 157, 1);
  AddAnalog(S, 'Terra', 'NASA with Japan and Canada', '1999', 'A bus-sized observatory with five instruments, including ASTER from Japan and MOPITT from Canada.',
    'https://terra.nasa.gov/', 5190, 1300, 5);

  AddStr(S.Facts, 'The TROPICS CubeSats weigh about 5 kg each, yet together they revisit a hurricane roughly every hour.');
  AddStr(S.Facts, 'The first two TROPICS satellites were lost when their rocket failed in 2022. The mission survived because it had built spares.');
  AddStr(S.Facts, 'NISAR, built by NASA and ISRO, can measure the ground moving by less than a centimetre from 747 km up.');
  AddStr(S.Facts, 'A geostationary satellite sits 35,786 km up, almost a tenth of the way to the Moon.');
  AddStr(S.Facts, 'A sun-synchronous satellite crosses the equator at the same local time on every orbit, so shadows always fall the same way.');
  AddScenario(S);
end;

{ ---- Moon -------------------------------------------------------------- }

procedure BuildMoon;
var
  S: TScenario;
  O: TOrbit;
begin
  S := NewScenario('moon', 'Ice Prospector', 'Find the water at the Moon''s south pole', 'Moon', 1);
  S.Brief := 'Craters near the Moon''s south pole have not seen sunlight for two billion years. ' +
    'Earlier missions found signs of hydrogen there, probably water ice. Future astronauts could drink it, ' +
    'breathe it and turn it into rocket fuel, if we know exactly where it is.';
  S.Objective := 'Map water ice and other volatiles at the lunar poles from orbit for at least one year.';
  S.CostCapM := 150;
  S.DeadlineYears := 4;
  S.MinLife := 1;
  S.MaxLife := 5;
  S.DefaultLife := 2;
  S.SunAU := 1;
  S.EarthMinAU := 0.00257;
  S.EarthMaxAU := 0.00257;
  S.DataScale := 0.5;
  S.HeaterW := 10;
  S.AllowSEP := True;
  S.SepDvFactor := 2.2;
  S.SepExtraYears := 1.0;
  S.Weight := MV(0.45, 0.8, 0.6, 0.6, 0.5, 1.0, 0.05, 0.1, 0);
  S.FullScience := 1.9;
  S.ThresholdPct := 40;
  S.TauYears := 0.7;

  O := NewOrbit('polar100', 'Low polar orbit', 'A 100 km circle passing over both poles every two hours.',
    'The classic mapping orbit, used by Lunar Reconnaissance Orbiter. Every instrument works well here, ' +
    'but lumps in the Moon''s gravity keep pulling the orbit out of shape, so it costs fuel every year.');
  O.AltKm := 100; O.IncDeg := 90; O.PeriodHr := 1.96;
  O.EclipseFrac := 0.38; O.MaxEclipseHr := 0.8;
  O.CommFactor := 0.6; O.DvInsert := 850; O.DvPerYear := 60;
  AddOrbit(S, O);

  O := NewOrbit('frozen', 'Elliptical frozen orbit', '30 km over the south pole, 220 km over the north.',
    'A special shape that the Moon''s lumpy gravity leaves almost alone, so it needs hardly any fuel. ' +
    'It skims the south pole for superb detail there, at the price of a poorer view of the north.');
  O.AltKm := 30; O.ApoKm := 220; O.IncDeg := 90; O.PeriodHr := 2.0;
  O.EclipseFrac := 0.33; O.MaxEclipseHr := 0.8;
  O.Coverage := 0.85; O.CommFactor := 0.65; O.DvInsert := 880; O.DvPerYear := 8;
  SetFactors(O, MV(1.25, 1.1, 1.1, 1.2, 1.2, 1.3, 1, 1, 1));
  AddOrbit(S, O);

  O := NewOrbit('nrho', 'Near-rectilinear halo orbit', 'A week-long loop from 3,000 km to 70,000 km above the Moon.',
    'The orbit of the planned Gateway station, pioneered by the CAPSTONE CubeSat. Almost free to reach and to keep, ' +
    'always in sunlight and always in view of Earth. But it is far too high for instruments that need to be close.');
  O.AltKm := 3000; O.ApoKm := 70000; O.IncDeg := 90; O.PeriodHr := 156;
  O.EclipseFrac := 0.0; O.MaxEclipseHr := 1.5;
  O.Coverage := 0.9; O.CommFactor := 1.5; O.DvInsert := 450; O.DvPerYear := 10;
  SetFactors(O, MV(0.12, 0.2, 0.2, 0.05, 0.05, 0.02, 1, 1, 1));
  AddOrbit(S, O);

  O := NewOrbit('equator', 'Low equatorial orbit', 'A 100 km circle around the Moon''s equator.',
    'Easy to reach, but an orbit can only fly over latitudes up to its tilt. This one never goes near the poles, where the ice is.');
  O.AltKm := 100; O.IncDeg := 0; O.PeriodHr := 1.96;
  O.EclipseFrac := 0.40; O.MaxEclipseHr := 0.8;
  O.Coverage := 0.08; O.CommFactor := 0.6; O.DvInsert := 820; O.DvPerYear := 60;
  AddOrbit(S, O);

  AddTransfer(S, 'direct', 'Direct transfer (5 days)', 'Straight there, then a hard braking burn to be captured.', -2, 0.014, 1, False);
  AddTransfer(S, 'blt', 'Ballistic lunar transfer (4 months)',
    'A long loop 1.5 million km out, where the Sun''s gravity does a quarter of the braking for free. Used by CAPSTONE and Danuri.',
    -0.6, 0.33, 0.75, False);
  Offer(S, ['neutron', 'spec_vnir', 'tir', 'sar', 'lidar', 'cam_ctx', 'cam_hires', 'uvs', 'mag', 'dust', 'radio']);

  AddAnalog(S, 'Lunar Reconnaissance Orbiter', 'NASA', '2009', 'Seven instruments in a low polar orbit. Still working after more than 15 years.',
    'https://science.nasa.gov/mission/lro/', 1916, 504, 7);
  AddAnalog(S, 'Lunar Prospector', 'NASA', '1998', 'A simple spinning probe whose neutron spectrometer found the first signs of polar hydrogen.',
    'https://science.nasa.gov/mission/lunar-prospector/', 296, 63, 5);
  AddAnalog(S, 'Lunar Trailblazer', 'NASA', '2025', 'A 200 kg SmallSat with a spectrometer and a thermal mapper. It rode along with another launch and fell silent a day later.',
    'https://science.nasa.gov/mission/lunar-trailblazer/', 200, 94, 2);
  AddAnalog(S, 'CAPSTONE', 'NASA', '2022', 'A 25 kg CubeSat launched on an Electron. First spacecraft in a near-rectilinear halo orbit.',
    'https://www.nasa.gov/mission/capstone/', 25, 33, 1);
  AddAnalog(S, 'Chandrayaan-1', 'ISRO with NASA instruments', '2008', 'India''s first Moon mission. NASA''s M3 spectrometer on board found water molecules on the surface.',
    'https://science.nasa.gov/mission/chandrayaan-1/', 1380, 80, 11);
  AddAnalog(S, 'Danuri', 'KARI (Korea) with NASA ShadowCam', '2022', 'South Korea''s first lunar orbiter, sent on a fuel-saving ballistic transfer.',
    'https://science.nasa.gov/mission/danuri/', 678, 180, 6);

  AddStr(S.Facts, 'Lunar Prospector found signs of polar hydrogen in 1998 with a neutron spectrometer weighing about 4 kg.');
  AddStr(S.Facts, 'CAPSTONE took a four-month looping route to the Moon to save fuel, travelling 1.5 million km from Earth on the way.');
  AddStr(S.Facts, 'India''s Chandrayaan-1 carried NASA''s M3 spectrometer, which found water molecules across the lunar surface.');
  AddStr(S.Facts, 'Lunar Trailblazer, a low-cost SmallSat, fell silent a day after its 2025 launch. Lean missions accept more risk.');
  AddStr(S.Facts, 'ESA''s SMART-1 reached the Moon using an ion engine. The trip took 13 months instead of 5 days.');
  AddStr(S.Facts, 'A radio signal takes about 1.3 seconds to travel between Earth and the Moon.');
  AddScenario(S);
end;

{ ---- Mars -------------------------------------------------------------- }

procedure BuildMars;
var
  S: TScenario;
  O: TOrbit;
begin
  S := NewScenario('mars', 'Follow the Water', 'Track the weather and water of the Red Planet', 'Mars', 2);
  S.Brief := 'Mars once had rivers and lakes. Today its water is locked in ice, hidden underground or lost to space. ' +
    'Before people go, we need to know where the water went and what weather they will face. ' +
    'The planets only line up for the trip once every 26 months.';
  S.Objective := 'Study the Martian atmosphere, water and climate from orbit for a full Mars year (about two Earth years), ' +
    'and relay data for missions on the surface if you can.';
  S.CostCapM := 650;
  S.DeadlineYears := 4.4;
  S.WindowYears := 2.1;
  S.WindowPeriod := 2.14;
  S.MinLife := 2;
  S.MaxLife := 8;
  S.DefaultLife := 2;
  S.SunAU := 1.6;
  S.EarthMinAU := 0.52;
  S.EarthMaxAU := 2.52;
  S.SynodicDays := 780;
  S.DataScale := 0.05;
  S.HeaterW := 20;
  S.AllowSEP := True;
  S.SepDvFactor := 1.6;
  S.SepExtraYears := 0.8;
  S.Weight := MV(0.7, 0.7, 0.5, 0.6, 0.3, 0.3, 1.0, 0.45, 0.5);
  S.FullScience := 2.3;
  S.ThresholdPct := 40;
  S.TauYears := 1.0;

  O := NewOrbit('low_aero', 'Low orbit by aerobraking', 'A 300 km sun-synchronous orbit, reached by skimming the atmosphere for six months.',
    'Brake into a long looping orbit, then dip into the top of the atmosphere on every pass and let drag do the rest. ' +
    'It saves over a kilometre per second of fuel, but costs half a year and a little risk.');
  O.AltKm := 300; O.IncDeg := 93; O.PeriodHr := 1.87;
  O.EclipseFrac := 0.35; O.MaxEclipseHr := 0.7;
  O.CommFactor := 0.7; O.DvInsert := 1150; O.DvPerYear := 15;
  O.ExtraYears := 0.5; O.InsertRisk := 0.015;
  AddOrbit(S, O);

  O := NewOrbit('low_prop', 'Low orbit by engine alone', 'The same 300 km orbit, reached entirely with rocket burns.',
    'No waiting and no skimming the atmosphere: science starts at once. But the fuel bill more than doubles.');
  O.AltKm := 300; O.IncDeg := 93; O.PeriodHr := 1.87;
  O.EclipseFrac := 0.35; O.MaxEclipseHr := 0.7;
  O.CommFactor := 0.7; O.DvInsert := 2450; O.DvPerYear := 15;
  AddOrbit(S, O);

  O := NewOrbit('ellip', 'Elliptical dipping orbit', 'From 150 km out to 6,200 km, like MAVEN.',
    'Dives through the upper atmosphere, then swings far out to watch the whole planet. Ideal for studying how Mars loses its air. ' +
    'Cameras and radar suffer, because the spacecraft is seldom low for long.');
  O.AltKm := 150; O.ApoKm := 6200; O.IncDeg := 75; O.PeriodHr := 4.5;
  O.EclipseFrac := 0.15; O.MaxEclipseHr := 1.0;
  O.Coverage := 0.9; O.CommFactor := 0.85; O.DvInsert := 1250; O.DvPerYear := 10;
  SetFactors(O, MV(0.5, 0.6, 0.6, 0.5, 0.3, 1.4, 1.15, 1.4, 0.9));
  AddOrbit(S, O);

  O := NewOrbit('areo', 'Areostationary orbit', '17,032 km up, hovering over one spot on the equator.',
    'The Martian version of a geostationary orbit. It watches one side of the planet''s weather all day and is a perfect relay station, ' +
    'but from this height the surface is a blur.');
  O.AltKm := 17032; O.IncDeg := 0; O.PeriodHr := 24.6;
  O.EclipseFrac := 0.02; O.MaxEclipseHr := 1.3;
  O.Coverage := 0.45; O.CommFactor := 0.95; O.DvInsert := 1900; O.DvPerYear := 5;
  SetFactors(O, MV(0.15, 0.2, 0.4, 0.02, 0.05, 0.1, 1.2, 0.6, 1.6));
  AddOrbit(S, O);

  AddTransfer(S, 'hohmann', 'Seven-month transfer', 'The standard fuel-saving path used by nearly every Mars mission.', 12, 0.58, 1, False);
  Offer(S, ['radiometer', 'cam_ctx', 'cam_hires', 'spec_vnir', 'tir', 'sar', 'massspec', 'mag', 'plasma', 'uvs', 'lidar', 'relay', 'radio']);

  AddAnalog(S, 'Mars Reconnaissance Orbiter', 'NASA', '2005', 'Six instruments and a 3 m dish. It aerobraked for six months and has returned more data than all other planetary missions combined.',
    'https://science.nasa.gov/mission/mars-reconnaissance-orbiter/', 2180, 720, 6);
  AddAnalog(S, 'MAVEN', 'NASA', '2013', 'Eight instruments in an elliptical orbit that dips into the upper atmosphere to study how Mars loses its air.',
    'https://science.nasa.gov/mission/maven/', 2454, 671, 8);
  AddAnalog(S, 'Mars Odyssey', 'NASA', '2001', 'Found vast amounts of buried ice and has relayed data for every NASA rover since.',
    'https://science.nasa.gov/mission/odyssey/', 725, 297, 3);
  AddAnalog(S, 'Hope', 'UAE Space Agency / MBRSC', '2020', 'Orbits very high so it can see a whole hemisphere of weather at once.',
    'https://www.emiratesmarsmission.ae/', 1350, 200, 3);
  AddAnalog(S, 'Mangalyaan', 'ISRO', '2013', 'India reached Mars orbit at the first attempt for about 74 million dollars.',
    'https://www.isro.gov.in/MarsOrbiterMissionSpacecraft.html', 1337, 74, 5);
  AddAnalog(S, 'ESCAPADE', 'NASA', '2025', 'Two SmallSats studying how the solar wind strips the Martian atmosphere.',
    'https://science.nasa.gov/mission/escapade/', 1070, 80, 3);
  AddAnalog(S, 'MarCO', 'NASA', '2018', 'Two briefcase-sized CubeSats that relayed the InSight landing live from Mars.',
    'https://science.nasa.gov/mission/marco/', 27, 18.5, 0);

  AddStr(S.Facts, 'MRO spent six months skimming the top of Mars''s atmosphere to shrink its orbit, saving hundreds of kilograms of fuel.');
  AddStr(S.Facts, 'Mars Climate Orbiter was lost in 1999 because one team worked in pounds and another in newtons.');
  AddStr(S.Facts, 'Radio signals take between 3 and 22 minutes to cross from Mars to Earth, so nobody can fly a Mars orbiter by joystick.');
  AddStr(S.Facts, 'Every 26 months Mars slips behind the Sun and its spacecraft go quiet for about two weeks.');
  AddStr(S.Facts, 'Sunlight at Mars is less than half as strong as at Earth, so solar panels must be more than twice the size.');
  AddStr(S.Facts, 'MRO''s 3 m dish and 100 W transmitter send about 0.5 to 6 megabits per second, depending on how far away Mars is.');
  AddScenario(S);
end;

{ ---- Apophis ----------------------------------------------------------- }

procedure BuildApophis;
var
  S: TScenario;
  O: TOrbit;
begin
  S := NewScenario('apophis', 'Race to Apophis', 'Meet an asteroid before it meets Earth', 'Apophis', 2);
  S.Brief := 'On 13 April 2029 the asteroid 99942 Apophis, a rock about 340 m wide, will skim past Earth closer than ' +
    'our TV satellites. It will not hit us, but Earth''s gravity will tug it, twist it and may even shake its surface. ' +
    'Nothing this large comes this close more than once in thousands of years, and the date cannot move.';
  S.Objective := 'Get a spacecraft to Apophis in time to watch what Earth''s gravity does to it. ' +
    'The real question is what you can build before the clock runs out.';
  S.CostCapM := 250;
  S.DeadlineYears := 2.33;
  S.ArriveBy := True;
  S.LateFactor := 0.6;
  S.MinLife := 0.5;
  S.MaxLife := 3;
  S.DefaultLife := 1;
  S.SunAU := 1.05;
  S.EarthMinAU := 0.02;
  S.EarthMaxAU := 0.55;
  S.SynodicDays := 560;
  S.DataScale := 0.05;
  S.HeaterW := 5;
  S.AllowSEP := True;
  S.SepDvFactor := 1.1;
  S.SepExtraYears := 0.2;
  S.Weight := MV(0.9, 0.9, 0.7, 0.7, 0.8, 0.4, 0, 0.25, 0);
  S.FullScience := 1.4;
  S.ThresholdPct := 30;
  S.TauYears := 0.35;
  S.UsesApophis := True;

  O := NewOrbit('rdv', 'Rendezvous and stay', 'Match speed with the asteroid and fly alongside it for months.',
    'You watch the whole flyby from close up and map every boulder before and after. It takes a real engine to slow down and stay.');
  O.AltKm := 2; O.IncDeg := 90; O.PeriodHr := 30;
  O.EclipseFrac := 0.05; O.MaxEclipseHr := 1.0;
  O.DvInsert := 950; O.DvPerYear := 30;
  AddOrbit(S, O);

  O := NewOrbit('flyby', 'Fast flyby', 'Race past once at several kilometres per second.',
    'Almost no fuel and a smaller rocket, but all the science happens in a few frantic hours and you see only one side.');
  O.AltKm := 500; O.IncDeg := 0; O.PeriodHr := 2;
  O.EclipseFrac := 0; O.MaxEclipseHr := 0;
  O.Coverage := 0.45; O.TauFactor := 0.05; O.DataFactor := 0.05; O.DvInsert := 80; O.DvPerYear := 0; O.C3 := -3;
  SetFactors(O, MV(0.9, 0.8, 0.8, 0.3, 0.3, 0.6, 1, 0.6, 1));
  AddOrbit(S, O);

  AddTransfer(S, 'fast', 'Fast transfer (4 months)', 'Leave late and fly hard. Needs more launch energy, so a bigger rocket per kilogram.', 25, 0.35, 1, False);
  AddTransfer(S, 'slow', 'Low-energy transfer (19 months)', 'A gentle path that a small rocket can manage, with a quarter less braking. You must leave much earlier.', 3, 1.6, 0.75, False);
  Offer(S, ['cam_ctx', 'cam_hires', 'spec_vnir', 'tir', 'lidar', 'sar', 'dust', 'mag', 'radio']);

  AddAnalog(S, 'OSIRIS-APEX', 'NASA', '2029 arrival', 'The OSIRIS-REx spacecraft, sent on to Apophis after delivering its Bennu sample. It arrives just after the flyby.',
    'https://science.nasa.gov/mission/osiris-apex/', 2110, 200, 5);
  AddAnalog(S, 'Ramses', 'ESA with JAXA', 'planned 2028', 'A European mission planned to launch in 2028 and reach Apophis before the flyby.',
    'https://www.esa.int/Space_Safety/Planetary_Defence/Introducing_Ramses_ESA_s_mission_to_asteroid_Apophis', 1200, 400, 4);
  AddAnalog(S, 'DART', 'NASA with ASI''s LICIACube', '2021', 'Crashed into the asteroid moon Dimorphos and changed its orbit, the first planetary-defence test.',
    'https://science.nasa.gov/mission/dart/', 610, 325, 1);
  AddAnalog(S, 'NEAR Shoemaker', 'NASA', '1996', 'The first spacecraft to orbit and then land on an asteroid, Eros.',
    'https://science.nasa.gov/mission/near-shoemaker/', 805, 224, 6);
  AddAnalog(S, 'Hayabusa2', 'JAXA', '2014', 'Used ion engines to reach asteroid Ryugu and bring samples back to Earth.',
    'https://www.hayabusa2.jaxa.jp/en/', 609, 150, 5);
  AddAnalog(S, 'OSIRIS-REx', 'NASA with a Canadian laser altimeter', '2016', 'Mapped asteroid Bennu in detail and returned a sample in 2023.',
    'https://science.nasa.gov/mission/osiris-rex/', 2110, 1000, 5);

  AddStr(S.Facts, 'Apophis will pass about 32,000 km above Earth''s surface, inside the ring of geostationary satellites.');
  AddStr(S.Facts, 'On the night of the flyby Apophis will be visible to the naked eye from Africa, Europe and western Asia.');
  AddStr(S.Facts, 'After delivering its Bennu sample, NASA''s OSIRIS-REx was renamed OSIRIS-APEX and sent on to Apophis.');
  AddStr(S.Facts, 'DART proved in 2022 that a spacecraft can change an asteroid''s path by crashing into it.');
  AddStr(S.Facts, 'Japan''s Hayabusa2 used ion engines to visit asteroid Ryugu and bring samples home.');
  AddScenario(S);
end;

{ ---- Europa ------------------------------------------------------------ }

procedure BuildEuropa;
var
  S: TScenario;
  O: TOrbit;
begin
  S := NewScenario('europa', 'Ocean World', 'Is there an ocean we could live in?', 'Europa', 3);
  S.Brief := 'Under the cracked ice of Jupiter''s moon Europa lies a salt-water ocean holding more water than all of ' +
    'Earth''s seas. It is one of the best places to look for life. But Jupiter is five times farther from the Sun than we are, ' +
    'so sunlight is 27 times weaker, and its radiation belts can kill electronics in weeks.';
  S.Objective := 'Measure the thickness of Europa''s ice shell and the nature of its ocean, and survive long enough to send the answer home.';
  S.CostCapM := 2000;
  S.DeadlineYears := 9;
  S.MinLife := 0.25;
  S.MaxLife := 6;
  S.DefaultLife := 3.5;
  S.SunAU := 5.2;
  S.EarthMinAU := 4.2;
  S.EarthMaxAU := 6.2;
  S.SynodicDays := 399;
  S.DataScale := 0.01;
  S.HeaterW := 60;
  S.ColdWorld := True;
  S.AllowRTG := True;
  S.Weight := MV(0.8, 0.8, 0.6, 1.0, 0.6, 0.7, 0.15, 0.9, 0);
  S.FullScience := 3.0;
  S.ThresholdPct := 40;
  S.TauYears := 1.3;

  O := NewOrbit('tour', 'Europa flyby tour', 'Orbit Jupiter and swoop past Europa about 45 times.',
    'The Europa Clipper plan. Each pass maps a new strip, then the spacecraft retreats from the radiation to send its data home. ' +
    'Slower than orbiting Europa, but the electronics live for years.');
  O.AltKm := 50; O.ApoKm := 2500000; O.IncDeg := 10; O.PeriodHr := 500;
  O.EclipseFrac := 0.03; O.MaxEclipseHr := 3;
  O.Coverage := 0.85; O.CommFactor := 0.9; O.DvInsert := 1500; O.DvPerYear := 40;
  O.RadLevel := 2; O.RadLifeYears := 4.5;
  AddOrbit(S, O);

  O := NewOrbit('orbiter', 'Europa orbiter', 'Circle Europa itself at 100 km.',
    'The dream orbit: complete maps in weeks and the best gravity and radar data possible. ' +
    'But it sits deep in the radiation belt all the time, and braking into it takes almost twice the fuel.');
  O.AltKm := 100; O.IncDeg := 90; O.PeriodHr := 2.1;
  O.EclipseFrac := 0.30; O.MaxEclipseHr := 0.8;
  O.Coverage := 1.0; O.TauFactor := 0.15; O.CommFactor := 0.6; O.DvInsert := 2900; O.DvPerYear := 100;
  SetFactors(O, MV(1.2, 1.2, 1.2, 1.35, 1.5, 1.3, 1, 1.3, 1));
  O.RadLevel := 3; O.RadLifeYears := 0.3;
  AddOrbit(S, O);

  O := NewOrbit('jpolar', 'Jupiter polar orbit', 'Long loops over Jupiter''s poles, like Juno.',
    'Ducks under the worst of the radiation, so the spacecraft lasts. Superb for Jupiter itself, ' +
    'but Europa is only glimpsed from a distance a few times.');
  O.AltKm := 5000; O.ApoKm := 8000000; O.IncDeg := 90; O.PeriodHr := 1270;
  O.EclipseFrac := 0.0; O.MaxEclipseHr := 0;
  O.Coverage := 0.2; O.CommFactor := 0.95; O.DvInsert := 1250; O.DvPerYear := 20;
  SetFactors(O, MV(0.5, 0.5, 0.5, 0.3, 0.6, 0.4, 1.5, 1.2, 1));
  O.RadLevel := 2; O.RadLifeYears := 7;
  AddOrbit(S, O);

  AddTransfer(S, 'direct', 'Direct (2.7 years)', 'Straight to Jupiter. Needs an enormous amount of launch energy.', 82, 2.7, 1, False);
  AddTransfer(S, 'mega', 'Mars and Earth gravity assists (5.5 years)', 'Swing past Mars and then Earth to pick up speed. Halves the launch energy. Europa Clipper''s route.', 41, 5.5, 1, False);
  AddTransfer(S, 'veega', 'Venus and Earth gravity assists (6.5 years)', 'Three planetary flybys, starting inward at Venus where it is twice as hot as at Earth. The smallest rocket of all, the longest wait. Galileo''s route.', 16, 6.5, 1, True);
  Offer(S, ['sar', 'mag', 'plasma', 'spec_vnir', 'cam_hires', 'cam_ctx', 'tir', 'massspec', 'dust', 'uvs', 'radio']);

  AddAnalog(S, 'Europa Clipper', 'NASA', '2024', 'Nine instruments, solar wings over 30 m across and a 3 m dish. It will make about 49 flybys from 2030.',
    'https://science.nasa.gov/mission/europa-clipper/', 6065, 5200, 9);
  AddAnalog(S, 'Juno', 'NASA', '2011', 'The first solar-powered spacecraft at Jupiter. Its electronics live in a 200 kg titanium vault.',
    'https://science.nasa.gov/mission/juno/', 3625, 1130, 9);
  AddAnalog(S, 'Galileo', 'NASA', '1989', 'Nuclear-powered. Its main antenna jammed, cutting the data rate ten-thousand-fold, yet it still discovered Europa''s ocean.',
    'https://science.nasa.gov/mission/galileo/', 2562, 1600, 10);
  AddAnalog(S, 'JUICE', 'ESA', '2023', 'Europe''s mission to Jupiter''s icy moons, with 85 m2 of solar panels. It arrives in 2031.',
    'https://www.esa.int/Science_Exploration/Space_Science/Juice', 6070, 1700, 10);
  AddAnalog(S, 'New Horizons', 'NASA', '2006', 'A small, nuclear-powered probe launched so fast that it passed the Moon in nine hours.',
    'https://science.nasa.gov/mission/new-horizons/', 478, 780, 7);

  AddStr(S.Facts, 'Juno''s solar panels cover 60 m2, yet at Jupiter they make only about 500 W: less than a microwave oven uses.');
  AddStr(S.Facts, 'Europa Clipper''s solar wings span more than 30 m, longer than a basketball court.');
  AddStr(S.Facts, 'Galileo''s main antenna never opened. Engineers rescued the mission by teaching the spacecraft to compress its data.');
  AddStr(S.Facts, 'Juno keeps its electronics inside a titanium vault with walls about a centimetre thick.');
  AddStr(S.Facts, 'Europa Clipper flies past Europa again and again instead of orbiting it, to limit the radiation it soaks up.');
  AddStr(S.Facts, 'Voyager''s nuclear batteries are still working nearly 50 years after launch.');
  AddStr(S.Facts, 'A radio signal from Jupiter takes around 45 minutes to reach Earth.');
  AddScenario(S);
end;

initialization
  BuildEarth;
  BuildMoon;
  BuildMars;
  BuildApophis;
  BuildEuropa;
  ApophisDays := 881;
  ApophisMissKm := 38011;
  ApophisVelKmS := 7.42;
  ApophisDate := '2029-04-13';
  EarthEventsSource := '';
  BuildFallbackWeather;

end.
