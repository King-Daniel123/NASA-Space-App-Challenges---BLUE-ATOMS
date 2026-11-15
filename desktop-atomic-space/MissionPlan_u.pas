unit MissionPlan_u;

{ Atomic Space - mission design rules.

  Pure logic, no forms: the mission catalogue, the part specifications read
  from Assets\TextFile, the engineering review (mass, thrust-to-weight,
  budget, fuel, payload) and the score.

  All numbers are simplified teaching values, not engineering data.
  Written with the help of Claude (Anthropic), an AI coding assistant. }

interface

uses
  System.SysUtils, System.Classes, System.Math;

type
  TMissionSpec = record
    Name: string;
    Destination: string;
    PayloadT: Double;       { payload carried, tonnes }
    PayloadCostM: Double;   { payload price, $ million }
    BudgetM: Double;        { cost cap, $ million }
    FuelNeededGal: Double;  { propellant the trip to the Moon needs, US gal }
    Brief: string;
    RealMission: string;
  end;

  TPartSpec = record
    Name: string;
    MassKg: Double;
    MaxPayloadT: Double;    { ships only }
    FuelGal: Double;        { ships only }
    ThrustN: Double;        { thrusters only }
    BurnGalPerS: Double;    { thrusters only }
    CostM: Double;
  end;

  TPlanResult = record
    LaunchMassKg: Double;
    ThrustN: Double;
    WeightN: Double;
    TWR: Double;
    CostM: Double;
    BudgetLeftM: Double;
    PayloadMarginT: Double;
    FuelMarginPct: Double;
    BurnTimeS: Double;
    Ready: Boolean;
    DesignScore: Integer;   { 0..60 }
    Problems: TArray<string>;
    Warnings: TArray<string>;
    Strengths: TArray<string>;
  end;

const
  Gravity = 9.81;
  MinTWR = 1.15;
  MissionCount = 3;

function GetMission(Index: Integer): TMissionSpec;
function AssetFile(const RelPath: string): string;
function LoadPartSpec(const TextFileName: string; out Spec: TPartSpec): Boolean;
function EvaluatePlan(const Mission: TMissionSpec; const Ship,
  Thruster: TPartSpec; BoosterCount: Integer): TPlanResult;
function MoonFuelPercent(const R: TPlanResult): Double;
procedure ReviewLines(const Mission: TMissionSpec; const Ship,
  Thruster: TPartSpec; BoosterCount: Integer; const R: TPlanResult;
  Lines: TStrings);
function FinalScore(const R: TPlanResult; Flown, Landed: Boolean;
  FuelLeftPct: Double; out Grade: string): Integer;
procedure ReportLines(const Mission: TMissionSpec; const R: TPlanResult;
  Flown, Landed: Boolean; FuelLeftPct: Double; Lines: TStrings);

implementation

function Money(ValueM: Double): string;
begin
  Result := '$' + FormatFloat('#,##0.0', ValueM) + ' M';
end;

function GetMission(Index: Integer): TMissionSpec;
begin
  case Index of
    1:
      begin
        Result.Name := 'Lunar Science Orbiter';
        Result.Destination := 'Low lunar orbit';
        Result.PayloadT := 35;
        Result.PayloadCostM := 22;
        Result.BudgetM := 220;
        Result.FuelNeededGal := 480000;
        Result.Brief := 'Map the Moon''s surface and search for water ice ' +
          'from a low polar orbit. The orbiter is heavy, and the long trip ' +
          'needs a big fuel tank.';
        Result.RealMission := 'NASA Lunar Reconnaissance Orbiter (LRO), ' +
          'launched 2009, still mapping the Moon.';
      end;
    2:
      begin
        Result.Name := 'Cargo Lander';
        Result.Destination := 'Lunar south pole';
        Result.PayloadT := 80;
        Result.PayloadCostM := 40;
        Result.BudgetM := 300;
        Result.FuelNeededGal := 600000;
        Result.Brief := 'Deliver supplies for a future Moon base near the ' +
          'south pole. Only a large ship can carry the cargo, and it needs ' +
          'a lot of thrust to leave the pad.';
        Result.RealMission := 'NASA Commercial Lunar Payload Services ' +
          '(CLPS) and Artemis cargo landers.';
      end;
  else
    begin
      Result.Name := 'CubeSat Pathfinder';
      Result.Destination := 'Lunar orbit (test flight)';
      Result.PayloadT := 8;
      Result.PayloadCostM := 6;
      Result.BudgetM := 150;
      Result.FuelNeededGal := 300000;
      Result.Brief := 'Fly a small, cheap test satellite to prove the orbit ' +
        'that future crews will use. Small payload, tight budget.';
      Result.RealMission := 'NASA CAPSTONE CubeSat, launched 2022 to test ' +
        'the Gateway near-rectilinear halo orbit.';
    end;
  end;
end;

function AssetFile(const RelPath: string): string;
var
  ExeDir: string;
  Candidates: array[0..3] of string;
  I: Integer;
begin
  ExeDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  Candidates[0] := ExeDir + RelPath;
  Candidates[1] := ExeDir + 'Win32\Debug\' + RelPath;
  Candidates[2] := ExpandFileName(ExeDir + '..\..\' + RelPath);
  Candidates[3] := IncludeTrailingPathDelimiter(GetCurrentDir) + RelPath;
  for I := Low(Candidates) to High(Candidates) do
    if FileExists(Candidates[I]) then
      Exit(Candidates[I]);
  Result := Candidates[0];
end;

{ Splits "2 800 kN" into 2800 and "kn", "$73 000 000" into 73000000 and "". }
function SplitValue(const Text: string; out Value: Double;
  out UnitName: string): Boolean;
var
  Compact, NumberText: string;
  I: Integer;
  FS: TFormatSettings;
begin
  Compact := StringReplace(Text, ' ', '', [rfReplaceAll]);
  Compact := StringReplace(Compact, #9, '', [rfReplaceAll]);
  Compact := StringReplace(Compact, '$', '', [rfReplaceAll]);
  Compact := StringReplace(Compact, ',', '', [rfReplaceAll]);
  I := 1;
  while (I <= Length(Compact)) and CharInSet(Compact[I], ['0'..'9', '.']) do
    Inc(I);
  NumberText := Copy(Compact, 1, I - 1);
  UnitName := LowerCase(Copy(Compact, I, MaxInt));
  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';
  Result := (NumberText <> '') and TryStrToFloat(NumberText, Value, FS);
  if not Result then
    Value := 0;
end;

function LoadPartSpec(const TextFileName: string; out Spec: TPartSpec): Boolean;
var
  Lines: TStringList;
  I, P: Integer;
  Key, RawValue, UnitName: string;
  Value: Double;
begin
  Spec := Default(TPartSpec);
  Result := False;
  Lines := TStringList.Create;
  try
    if not FileExists(AssetFile('Assets\TextFile\' + TextFileName)) then
      Exit;
    Lines.LoadFromFile(AssetFile('Assets\TextFile\' + TextFileName));
    for I := 0 to Lines.Count - 1 do
    begin
      P := Pos(':', Lines[I]);
      if P = 0 then
        Continue;
      Key := LowerCase(Trim(Copy(Lines[I], 1, P - 1)));
      RawValue := Trim(Copy(Lines[I], P + 1, MaxInt));
      if (Key = 'space-ship') or (Key = 'thruster') or (Key = 'name') then
      begin
        Spec.Name := RawValue;
        Continue;
      end;
      if not SplitValue(RawValue, Value, UnitName) then
        Continue;
      if (Key = 'structural mass') or (Key = 'mass') then
      begin
        if UnitName = 't' then
          Spec.MassKg := Value * 1000
        else
          Spec.MassKg := Value;
      end
      else if Key = 'maximum payload mass' then
      begin
        if UnitName = 'kg' then
          Spec.MaxPayloadT := Value / 1000
        else
          Spec.MaxPayloadT := Value;
      end
      else if Key = 'fuel tank' then
        Spec.FuelGal := Value
      else if Key = 'thrust force' then
      begin
        if UnitName = 'kn' then
          Spec.ThrustN := Value * 1000
        else
          Spec.ThrustN := Value;
      end
      else if Key = 'fuel consumption rate' then
        Spec.BurnGalPerS := Value
      else if Key = 'cost' then
        Spec.CostM := Value / 1000000;
    end;
    Result := (Spec.MassKg > 0) and (Spec.CostM > 0);
  finally
    Lines.Free;
  end;
end;

procedure Add(var List: TArray<string>; const Text: string);
begin
  SetLength(List, Length(List) + 1);
  List[High(List)] := Text;
end;

function EvaluatePlan(const Mission: TMissionSpec; const Ship,
  Thruster: TPartSpec; BoosterCount: Integer): TPlanResult;
var
  Pts: Double;
begin
  Result := Default(TPlanResult);
  BoosterCount := Max(1, BoosterCount);
  Result.LaunchMassKg := Ship.MassKg + BoosterCount * Thruster.MassKg +
    Mission.PayloadT * 1000;
  Result.ThrustN := BoosterCount * Thruster.ThrustN;
  Result.WeightN := Result.LaunchMassKg * Gravity;
  if Result.WeightN > 0 then
    Result.TWR := Result.ThrustN / Result.WeightN;
  Result.CostM := Ship.CostM + BoosterCount * Thruster.CostM +
    Mission.PayloadCostM;
  Result.BudgetLeftM := Mission.BudgetM - Result.CostM;
  Result.PayloadMarginT := Ship.MaxPayloadT - Mission.PayloadT;
  if Mission.FuelNeededGal > 0 then
    Result.FuelMarginPct := (Ship.FuelGal - Mission.FuelNeededGal) /
      Mission.FuelNeededGal * 100;
  if Thruster.BurnGalPerS > 0 then
    Result.BurnTimeS := Ship.FuelGal / (BoosterCount * Thruster.BurnGalPerS);

  { Red findings: the mission cannot fly. }
  if Result.PayloadMarginT < 0 then
    Add(Result.Problems, Format('Payload too heavy: %s carries at most %.0f t, ' +
      'the mission needs %.0f t. Choose a bigger ship.',
      [Ship.Name, Ship.MaxPayloadT, Mission.PayloadT]));
  if Result.TWR < 1 then
    Add(Result.Problems, Format('Thrust-to-weight %.2f: the rocket weighs more ' +
      'than its engines can lift, so it will not leave the pad. Add boosters ' +
      'or choose stronger thrusters.', [Result.TWR]))
  else if Result.TWR < MinTWR then
    Add(Result.Problems, Format('Thrust-to-weight %.2f is below %.2f: the rocket ' +
      'climbs so slowly that gravity eats the fuel ("gravity losses").',
      [Result.TWR, MinTWR]));
  if Result.BudgetLeftM < 0 then
    Add(Result.Problems, Format('Over budget by %s. Cheaper parts or fewer ' +
      'boosters are needed.', [Money(-Result.BudgetLeftM)]));
  if Result.FuelMarginPct < 0 then
    Add(Result.Problems, Format('Not enough fuel to reach the Moon: tank %s gal, ' +
      'trip needs %s gal. Choose a ship with a bigger tank.',
      [FormatFloat('#,##0', Ship.FuelGal),
       FormatFloat('#,##0', Mission.FuelNeededGal)]));

  { Amber findings: it can fly, but it is a gamble. }
  if Result.TWR > 2.5 then
    Add(Result.Warnings, Format('Thrust-to-weight %.2f is very high: strong ' +
      'g-forces shake the payload, and you paid for thrust you do not need.',
      [Result.TWR]));
  if (Result.BudgetLeftM >= 0) and
    (Result.BudgetLeftM < 0.05 * Mission.BudgetM) then
    Add(Result.Warnings, 'Less than 5% of the budget is left as a reserve. ' +
      'Real projects keep 10-30% for surprises.');
  if (Result.FuelMarginPct >= 0) and (Result.FuelMarginPct < 10) then
    Add(Result.Warnings, Format('Fuel margin only %.0f%%: the Moon landing ' +
      'will start with a low tank.', [Result.FuelMarginPct]));
  if (Result.PayloadMarginT >= 0) and
    (Result.PayloadMarginT < 0.1 * Ship.MaxPayloadT) then
    Add(Result.Warnings, 'The ship is almost full: no room for extra ' +
      'instruments if the science team asks.');

  { Green findings. }
  if (Result.TWR >= 1.3) and (Result.TWR <= 2.0) then
    Add(Result.Strengths, 'Thrust-to-weight in the 1.3-2.0 sweet spot used ' +
      'by real launch vehicles.');
  if Result.BudgetLeftM >= 0.2 * Mission.BudgetM then
    Add(Result.Strengths, 'Healthy budget reserve (20% or more).');
  if Result.FuelMarginPct >= 20 then
    Add(Result.Strengths, 'Comfortable fuel margin for the landing.');

  Result.Ready := Length(Result.Problems) = 0;

  { Design score out of 60: budget 20, thrust-to-weight 20, fuel 20. }
  Pts := 0;
  if Result.BudgetLeftM >= 0 then
    Pts := Pts + 20 * Min(1.0, Result.BudgetLeftM / (0.25 * Mission.BudgetM));
  if (Result.TWR >= 1.3) and (Result.TWR <= 2.0) then
    Pts := Pts + 20
  else if (Result.TWR >= MinTWR) and (Result.TWR <= 2.5) then
    Pts := Pts + 14
  else if Result.TWR > 2.5 then
    Pts := Pts + 8;
  if Result.FuelMarginPct >= 0 then
    Pts := Pts + 20 * Min(1.0, Result.FuelMarginPct / 20);
  if not Result.Ready then
    Pts := Pts * 0.5;
  Result.DesignScore := Round(Pts);
end;

function MoonFuelPercent(const R: TPlanResult): Double;
begin
  { A thin fuel margin means the lunar phase starts with less in the tank. }
  Result := EnsureRange(60 + 2 * R.FuelMarginPct, 35, 100);
end;

procedure ReviewLines(const Mission: TMissionSpec; const Ship,
  Thruster: TPartSpec; BoosterCount: Integer; const R: TPlanResult;
  Lines: TStrings);
var
  S: string;
begin
  Lines.BeginUpdate;
  try
    Lines.Clear;
    Lines.Add('MISSION: ' + Mission.Name);
    Lines.Add('Target: ' + Mission.Destination);
    Lines.Add(Mission.Brief);
    Lines.Add('Real-world match: ' + Mission.RealMission);
    Lines.Add('');
    Lines.Add(Format('DESIGN: %s + %d x %s', [Ship.Name, BoosterCount,
      Thruster.Name]));
    Lines.Add('');
    Lines.Add('RESOURCES');
    Lines.Add(Format('  Budget    %s of %s  (left %s)', [Money(R.CostM),
      Money(Mission.BudgetM), Money(R.BudgetLeftM)]));
    Lines.Add(Format('  Mass      %s t at lift-off (payload %.0f t)',
      [FormatFloat('#,##0.0', R.LaunchMassKg / 1000), Mission.PayloadT]));
    Lines.Add(Format('  Thrust    %s kN vs weight %s kN',
      [FormatFloat('#,##0', R.ThrustN / 1000),
       FormatFloat('#,##0', R.WeightN / 1000)]));
    Lines.Add(Format('  T/W ratio %.2f  (needs %.2f or more)', [R.TWR, MinTWR]));
    Lines.Add(Format('  Fuel      %s gal, margin %.0f%%',
      [FormatFloat('#,##0', Ship.FuelGal), R.FuelMarginPct]));
    Lines.Add(Format('  Burn time %s s with all engines',
      [FormatFloat('#,##0', R.BurnTimeS)]));
    Lines.Add('');
    Lines.Add('REVIEW BOARD');
    if Length(R.Problems) = 0 then
      Lines.Add('  GO - no blocking findings.')
    else
      for S in R.Problems do
        Lines.Add('  [RED] ' + S);
    for S in R.Warnings do
      Lines.Add('  [AMBER] ' + S);
    for S in R.Strengths do
      Lines.Add('  [GREEN] ' + S);
    Lines.Add('');
    Lines.Add(Format('Design score: %d / 60', [R.DesignScore]));
    if R.Ready then
      Lines.Add('Press LAUNCH when the whole team agrees.')
    else
      Lines.Add('Fix the RED findings before launch.');
  finally
    Lines.EndUpdate;
  end;
end;

function FinalScore(const R: TPlanResult; Flown, Landed: Boolean;
  FuelLeftPct: Double; out Grade: string): Integer;
begin
  Result := R.DesignScore;
  if Flown and Landed then
    Result := Result + 30 + Round(10 * EnsureRange(FuelLeftPct, 0, 100) / 100);
  Result := EnsureRange(Result, 0, 100);
  if Result >= 85 then
    Grade := 'A - Mission of the decade'
  else if Result >= 70 then
    Grade := 'B - Solid success'
  else if Result >= 55 then
    Grade := 'C - Success with lessons'
  else
    Grade := 'D - Back to the drawing board';
end;

procedure ReportLines(const Mission: TMissionSpec; const R: TPlanResult;
  Flown, Landed: Boolean; FuelLeftPct: Double; Lines: TStrings);
var
  Score: Integer;
  Grade: string;
begin
  Score := FinalScore(R, Flown, Landed, FuelLeftPct, Grade);
  Lines.Clear;
  Lines.Add('MISSION REPORT - ' + Mission.Name);
  Lines.Add('');
  Lines.Add(Format('Final score: %d / 100   Grade: %s', [Score, Grade]));
  Lines.Add('');
  Lines.Add(Format('Design (budget, thrust, fuel): %d / 60', [R.DesignScore]));
  if not Flown then
    Lines.Add('Flight: the lunar phase was not completed (0 / 40).')
  else if Landed then
    Lines.Add(Format('Flight: landed safely with %.0f%% fuel left (%d / 40).',
      [FuelLeftPct, Score - R.DesignScore]))
  else
    Lines.Add('Flight: the landing failed (0 / 40).');
  Lines.Add('');
  Lines.Add('WHY');
  if R.BudgetLeftM >= 0.2 * Mission.BudgetM then
    Lines.Add('+ You kept a real reserve. Agencies cancel missions that overrun.')
  else
    Lines.Add('- Little budget reserve. A cheaper ship or fewer boosters would ' +
      'have scored more.');
  if (R.TWR >= 1.3) and (R.TWR <= 2.0) then
    Lines.Add('+ Your thrust-to-weight was in the efficient range.')
  else if R.TWR > 2.0 then
    Lines.Add('- Too much thrust: extra boosters cost money and add mass.')
  else
    Lines.Add('- A sluggish climb wastes fuel fighting gravity.');
  if R.FuelMarginPct >= 20 then
    Lines.Add('+ The big fuel margin made the landing forgiving.')
  else
    Lines.Add('- A thin fuel margin left little room for landing corrections.');
  if Flown and not Landed then
    Lines.Add('- Landing: approach slower than 7 m/s and stay over the pad. ' +
      'Try AUTO mode (M) to watch how the autopilot brakes.');
  Lines.Add('');
  Lines.Add('Real mission like yours: ' + Mission.RealMission);
  Lines.Add('');
  Lines.Add('Try again: there is more than one good design for every mission.');
end;

end.
