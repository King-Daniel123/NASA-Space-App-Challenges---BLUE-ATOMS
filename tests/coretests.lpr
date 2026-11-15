program coretests;

{ Atomic Space - command-line checks for the mission engine.

  Compiled with pas2js for Node.js (see scripts/test.ps1). The same core units
  also run in the browser game, so a pass here means the game logic is sound.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$mode delphi}

uses
  SysUtils, TsTypes, TsFmt, TsCatalog, TsScenarios, TsEngine, TsSim, TsScore, TsExamples;

var
  Failures: Integer = 0;
  Checks: Integer = 0;

procedure Check(Cond: Boolean; const Msg: string);
begin
  Inc(Checks);
  if not Cond then
  begin
    Inc(Failures);
    Writeln('  FAIL: ', Msg);
  end;
end;

procedure Pick(var D: TDesign; const InstrId: string);
var
  I: Integer;
begin
  I := FindInstrument(InstrId);
  if I < 0 then
    raise Exception.Create('unknown instrument ' + InstrId);
  D.Instr[I] := True;
end;

procedure SetPart(var D: TDesign; K: TPartKind; const Id: string);
var
  I: Integer;
begin
  I := FindPart(K, Id);
  if I < 0 then
    raise Exception.Create('unknown part ' + Id);
  D.Part[K] := I;
end;

{ Fly a design many times with different luck and print the spread of results. }
procedure Fly(const D: TDesign);
var
  S: TSimState;
  C: TScoreCard;
  E: TDesign;
  Run, Lost, MinT, MaxT, SumT, Pol: Integer;
  SumSci, SumCost: Double;
  Line: string;
begin
  Lost := 0;
  MinT := 100000;
  MaxT := -1;
  SumT := 0;
  SumSci := 0;
  SumCost := 0;
  for Run := 1 to 40 do
  begin
    E := D;
    E.Seed := 1000 + Run * 7919;
    Pol := Run mod 2;
    SimStart(S, E);
    SimRunAll(S, Pol);
    Check(SimDone(S), 'simulation finishes');
    C := ScoreMission(S);
    Check((C.Total >= 0) and (C.Total <= 1000), 'score within 0..1000');
    if S.LostAtLaunch or S.LostAtArrival or not S.Alive then
      Inc(Lost);
    if C.Total < MinT then MinT := C.Total;
    if C.Total > MaxT then MaxT := C.Total;
    SumT := SumT + C.Total;
    SumSci := SumSci + S.SciencePct;
    SumCost := SumCost + C.FinalCostM;
  end;
  Line := '  FLOWN x40: score ' + IntToStr(MinT) + '..' + IntToStr(MaxT) + ' (avg ' + IntToStr(SumT div 40) + ', grade ' +
    GradeOf(SumT div 40) + ')  science avg ' + FmtNum(SumSci / 40, 0) + '%  cost avg ' + FmtMoney(SumCost / 40) +
    '  ended early or lost ' + IntToStr(Lost) + '/40';
  Writeln(Line);
end;

procedure Report(const Title: string; const D: TDesign);
var
  A: TAnalysis;
  I: Integer;
  Tag: string;
begin
  A := Analyze(D);
  Writeln('');
  Writeln('== ', Title, ' ==');
  Writeln('  mass   dry ', FmtMass(A.DryKg), '  prop ', FmtMass(A.PropKg), '  wet ', FmtMass(A.WetKg),
    '  rocket cap ', FmtMass(A.LvCapKg), '  margin ', FmtPct(A.MassMargin));
  Writeln('  power  gen ', FmtPower(A.GenAvgW), '  load ', FmtPower(A.LoadAvgW), '  margin ', FmtPct(A.PowerMargin),
    '  battery need ', FmtNum(A.BatteryNeedWh, 0), ' Wh');
  Writeln('  dv     need ', FmtDv(A.DvNeed), '  (insert ', FmtDv(A.DvInsert), ', keep ', FmtDv(A.DvKeep), ')');
  Writeln('  data   gen ', FmtData(A.GenGbitDay), '/day  rate ', FmtRate(A.RateAvgMbps), ' (worst ', FmtRate(A.RateMinMbps),
    ')  contact ', FmtNum(A.ContactHr, 1), ' h  down ', FmtData(A.DownGbitDay), '/day  return ', FmtPct(A.DataReturn));
  Writeln('  cost   ', FmtMoney(A.CostTotal), ' of ', FmtMoney(A.CapM), '  (hw ', FmtMoney(A.CostHardware), ', launch ',
    FmtMoney(A.CostLaunch), ', ops ', FmtMoney(A.CostOps), ', reserve ', FmtMoney(A.CostReserve), ')');
  Writeln('  time   dev ', FmtYears(A.DevYears), '  launch at ', FmtYears(A.LaunchYear), '  cruise ', FmtYears(A.CruiseYears),
    '  late=', A.MissedDeadline);
  Writeln('  sci    ', FmtNum(A.SciencePct, 0), '% (max ', FmtNum(A.ScienceMaxPct, 0), '%, tau ', FmtNum(A.TauYears, 2),
    ' y)  success ', FmtPct(A.SuccessProb), '  blockers ', A.Blockers, '  warnings ', A.Warnings);
  for I := 0 to High(A.Findings) do
  begin
    case A.Findings[I].Sev of
      svBlock: Tag := 'BLOCK';
      svWarn: Tag := 'warn ';
      svInfo: Tag := 'info ';
    else
      Tag := 'good ';
    end;
    Writeln('    [', Tag, '] ', A.Findings[I].Title);
  end;
  if A.Blockers = 0 then
    Fly(D);
end;

{ One full mission with its event log, to read like a player would. }
procedure Story(const D: TDesign);
var
  S: TSimState;
  C: TScoreCard;
  I: Integer;
  R: TRole;
begin
  SimStart(S, D);
  SimRunAll(S, 0);
  C := ScoreMission(S);
  Writeln('');
  Writeln('== One mission in full (seed ', D.Seed, ') ==');
  for I := 0 to High(S.Log) do
  begin
    Write('  [', PhaseName[S.Log[I].Phase], ' wk ', S.Log[I].Week, '] ', S.Log[I].Title);
    if S.Log[I].IsDecision then
      Write('  -> ', S.Log[I].Decision, '  => ', S.Log[I].Outcome);
    if S.Log[I].Source <> '' then
      Write('  {', S.Log[I].Source, '}');
    Writeln('');
  end;
  Writeln('  OUTCOME: ', C.Outcome, ' - ', C.OutcomeText);
  Writeln('  SCORE ', C.Total, ' grade ', C.Grade, ' (', C.Title, ')  science ', FmtNum(C.Science, 0), ' survival ',
    FmtNum(C.Survival, 0), ' budget ', FmtNum(C.Budget, 0), ' engineering ', FmtNum(C.Engineering, 0), ' efficiency ',
    FmtNum(C.Efficiency, 0));
  Writeln('  cost ', FmtMoney(C.FinalCostM), ' of ', FmtMoney(C.CapM), '  data return ', FmtPct(C.ReturnFrac), '  events observed ', S.EventsSeen);
  for I := 0 to High(C.Insights) do
    Writeln('  * ', C.Insights[I].Title);
  Writeln('  ', C.AnalogText);
  for R := Low(TRole) to High(TRole) do
    Writeln('  role ', RoleShort[R], ': met=', C.RoleMet[R], '  ', C.RoleResult[R]);
  Check(Length(S.Log) >= 4, 'a mission produces an event log');
  Check(Length(C.Insights) >= 1, 'a mission produces insights');
end;

procedure TestCatalog;
var
  I, J: Integer;
  K: TPartKind;
begin
  Writeln('Catalogue: ', Length(Instruments), ' instruments, ', Length(Launchers), ' launchers, ',
    Length(Scenarios), ' scenarios, ', Length(Glossary), ' glossary terms');
  Check(Length(Scenarios) = 5, 'five scenarios');
  Check(Length(Instruments) >= 14, 'instrument count');
  for K := Low(TPartKind) to High(TPartKind) do
    Check(Length(Parts[K]) >= 2, 'at least two options for ' + PartKindName[K]);
  for I := 0 to High(Scenarios) do
  begin
    Check(Length(Scenarios[I].Orbits) >= 2, Scenarios[I].Id + ' has orbits');
    Check(Length(Scenarios[I].Transfers) >= 1, Scenarios[I].Id + ' has a transfer');
    Check(Length(Scenarios[I].Analogs) >= 3, Scenarios[I].Id + ' has real-mission analogues');
    for J := 0 to High(Scenarios[I].Instruments) do
      Check(FindInstrument(Scenarios[I].Instruments[J]) >= 0,
        Scenarios[I].Id + ' offers a known instrument: ' + Scenarios[I].Instruments[J]);
  end;
end;

procedure TestPhysics;
var
  D: TDesign;
  A, B: TAnalysis;
begin
  { Rocket equation: more delta-v must cost more than proportionally more propellant. }
  D := NewDesign(FindScenario('mars'), dfEngineer, False);
  Pick(D, 'radiometer');
  SetPart(D, pkBus, 'medium');
  SetPart(D, pkPropulsion, 'biprop');
  D.Orbit := 0;  // aerobraking: 1,150 m/s
  A := Analyze(D);
  D.Orbit := 1;  // all-propulsive: 2,450 m/s
  B := Analyze(D);
  Check(B.PropKg > A.PropKg * 2.13, 'rocket equation is super-linear (' + FmtMass(A.PropKg) + ' -> ' + FmtMass(B.PropKg) + ')');

  { Inverse-square law: sunlight at Jupiter is about 1/27 of Earth's. }
  D := NewDesign(FindScenario('europa'), dfEngineer, False);
  D.SolarM2 := 60;
  A := Analyze(D);
  Check((A.SolarW > 400) and (A.SolarW < 600), 'Juno-size 60 m2 array gives about 500 W at Jupiter, got ' + FmtPower(A.SolarW));

  { Link budget: an MRO-like radio at Mars should give roughly MRO-like rates. }
  D := NewDesign(FindScenario('mars'), dfEngineer, False);
  SetPart(D, pkBus, 'medium');
  SetPart(D, pkAntenna, 'dish30');
  SetPart(D, pkBand, 'x');
  SetPart(D, pkTx, 'tx100');
  A := Analyze(D);
  Check((A.RateAvgMbps > 0.2) and (A.RateAvgMbps < 6), 'MRO-like link is 0.5 to 6 Mbps class, got ' + FmtRate(A.RateAvgMbps));
  Check(A.RateMinMbps < A.RateAvgMbps, 'rate drops when Mars is far away');

  { Adding an instrument must ripple through mass, power, data and cost. }
  D := NewDesign(FindScenario('moon'), dfEngineer, False);
  Pick(D, 'neutron');
  A := Analyze(D);
  Pick(D, 'sar');
  B := Analyze(D);
  Check(B.WetKg > A.WetKg + 30, 'radar adds more than its own mass (propellant grows too)');
  Check(B.LoadAvgW > A.LoadAvgW, 'radar adds power demand');
  Check(B.GenGbitDay > A.GenGbitDay, 'radar adds data');
  Check(B.CostTotal > A.CostTotal, 'radar adds cost');
end;

procedure TestShareCode;
var
  D, E: TDesign;
  Code: string;
begin
  D := NewDesign(FindScenario('moon'), dfChief, False);
  Pick(D, 'neutron');
  Pick(D, 'tir');
  D.Orbit := 1;
  D.Transfer := 1;
  D.Launcher := FindLauncher('pslv');
  D.SolarM2 := 3.5;
  D.LifeYears := 2.5;
  D.Seed := 4242;
  Code := EncodeDesign(D);
  Check(DecodeDesign(Code, E), 'share code decodes: ' + Code);
  Check(EncodeDesign(E) = Code, 'share code round-trips');
  Check(not DecodeDesign('garbage', E), 'bad code is rejected');
end;

procedure SampleDesigns;
var
  D: TDesign;
begin
  { Earth: small satellite, three instruments, polar orbit }
  D := NewDesign(FindScenario('earth'), dfEngineer, False);
  Pick(D, 'tir'); Pick(D, 'radiometer'); Pick(D, 'cam_ctx');
  D.Orbit := 2;
  SetPart(D, pkPropulsion, 'mono');
  SetPart(D, pkBand, 'x');
  SetPart(D, pkGround, 'standard');
  SetPart(D, pkComputer, 'radtol');
  D.SolarM2 := 2;
  D.Launcher := FindLauncher('rideshare');
  Report('Earth: SmallSat, TIR + radiometer + camera, SSO, rideshare', D);

  { Earth: CubeSat }
  D := NewDesign(FindScenario('earth'), dfEngineer, False);
  Pick(D, 'radiometer');
  D.Orbit := 1;
  SetPart(D, pkBus, 'cube');
  SetPart(D, pkAdcs, 'mtq');
  D.SolarM2 := 0.4; D.BatteryWh := 80;
  D.Launcher := FindLauncher('electron');
  Report('Earth: TROPICS-like CubeSat', D);

  { Moon: SmallSat prospector }
  D := NewDesign(FindScenario('moon'), dfEngineer, False);
  Pick(D, 'neutron'); Pick(D, 'spec_vnir'); Pick(D, 'tir');
  D.Orbit := 1; D.Transfer := 1;
  SetPart(D, pkThermal, 'cryo');
  SetPart(D, pkGround, 'basic');
  D.SolarM2 := 2.5; D.BatteryWh := 500;
  D.Launcher := FindLauncher('rideshare');
  Report('Moon: Trailblazer-like SmallSat, frozen orbit, BLT', D);
  D.Transfer := 0;
  Report('Moon: same, direct transfer on rideshare', D);

  { Moon: CubeSat }
  D := NewDesign(FindScenario('moon'), dfEngineer, False);
  Pick(D, 'neutron');
  D.Orbit := 1; D.Transfer := 1;
  SetPart(D, pkBus, 'cube');
  D.SolarM2 := 0.5; D.BatteryWh := 120;
  D.Launcher := FindLauncher('electron');
  Report('Moon: LunaH-Map-like CubeSat on Electron', D);

  { Mars: MRO-like }
  D := NewDesign(FindScenario('mars'), dfEngineer, False);
  Pick(D, 'radiometer'); Pick(D, 'cam_ctx'); Pick(D, 'cam_hires'); Pick(D, 'spec_vnir'); Pick(D, 'sar'); Pick(D, 'relay');
  SetPart(D, pkBus, 'medium');
  SetPart(D, pkPropulsion, 'biprop');
  SetPart(D, pkAntenna, 'dish30'); SetPart(D, pkBand, 'ka'); SetPart(D, pkTx, 'tx100');
  SetPart(D, pkGround, 'standard'); SetPart(D, pkComputer, 'radhard'); SetPart(D, pkThermal, 'cryo');
  D.SolarM2 := 20; D.BatteryWh := 1500;
  D.Launcher := FindLauncher('falcon9');
  Report('Mars: MRO-like orbiter (real MRO: 2,180 kg, $720M)', D);

  { Mars: ESCAPADE-like }
  D := NewDesign(FindScenario('mars'), dfEngineer, False);
  Pick(D, 'mag'); Pick(D, 'plasma');
  D.Orbit := 2;
  SetPart(D, pkPropulsion, 'biprop');
  D.SolarM2 := 5; D.BatteryWh := 400;
  SetPart(D, pkTx, 'tx20'); SetPart(D, pkGround, 'standard');
  D.Launcher := FindLauncher('lvm3');
  Report('Mars: ESCAPADE-like SmallSat, fields and particles', D);

  { Apophis: CubeSat }
  D := NewDesign(FindScenario('apophis'), dfEngineer, False);
  Pick(D, 'cam_ctx'); Pick(D, 'tir');
  SetPart(D, pkBus, 'cube');
  SetPart(D, pkPropulsion, 'mono');
  SetPart(D, pkTx, 'tx20'); SetPart(D, pkGround, 'standard');
  D.SolarM2 := 0.8; D.BatteryWh := 100;
  D.Launcher := FindLauncher('electron');
  Report('Apophis: CubeSat rendezvous, fast transfer', D);

  D := NewDesign(FindScenario('apophis'), dfEngineer, False);
  Pick(D, 'cam_ctx'); Pick(D, 'spec_vnir'); Pick(D, 'tir'); Pick(D, 'lidar');
  SetPart(D, pkRisk, 'classd'); SetPart(D, pkSchedule, 'fast'); SetPart(D, pkThermal, 'cryo');
  SetPart(D, pkTx, 'tx20'); SetPart(D, pkGround, 'standard'); SetPart(D, pkAntenna, 'dish12');
  D.SolarM2 := 3; D.BatteryWh := 300;
  D.Launcher := FindLauncher('falcon9');
  Report('Apophis: SmallSat rendezvous, accelerated class D', D);

  { Europa: Clipper-like }
  D := NewDesign(FindScenario('europa'), dfEngineer, False);
  Pick(D, 'sar'); Pick(D, 'mag'); Pick(D, 'plasma'); Pick(D, 'spec_vnir'); Pick(D, 'cam_hires');
  Pick(D, 'cam_ctx'); Pick(D, 'tir'); Pick(D, 'massspec'); Pick(D, 'dust');
  SetPart(D, pkBus, 'large');
  D.Orbit := 0; D.Transfer := 1;
  SetPart(D, pkPropulsion, 'biprop');
  SetPart(D, pkAdcs, 'rw4'); SetPart(D, pkThermal, 'cryo'); SetPart(D, pkComputer, 'radhard'); SetPart(D, pkShield, 'vault');
  SetPart(D, pkAntenna, 'dish30'); SetPart(D, pkBand, 'ka'); SetPart(D, pkTx, 'tx100'); SetPart(D, pkGround, 'premium');
  SetPart(D, pkRisk, 'classb');
  D.SolarM2 := 100; D.BatteryWh := 4000; D.LifeYears := 3.5;
  D.Launcher := FindLauncher('falconheavy');
  Report('Europa: Clipper-like flagship (real Clipper: 6,065 kg, $5.2B)', D);

  { Europa: lean Discovery-class }
  D := NewDesign(FindScenario('europa'), dfEngineer, False);
  Pick(D, 'sar'); Pick(D, 'mag'); Pick(D, 'cam_ctx'); Pick(D, 'tir');
  SetPart(D, pkBus, 'medium');
  D.Orbit := 0; D.Transfer := 2;
  SetPart(D, pkPropulsion, 'biprop');
  SetPart(D, pkThermal, 'active'); SetPart(D, pkComputer, 'radhard'); SetPart(D, pkShield, 'spot');
  SetPart(D, pkAntenna, 'dish30'); SetPart(D, pkBand, 'x'); SetPart(D, pkTx, 'tx100'); SetPart(D, pkGround, 'premium');
  D.SolarM2 := 0; D.RtgCount := 3; D.BatteryWh := 1000; D.LifeYears := 3.5;
  D.Launcher := FindLauncher('falcon9');
  Report('Europa: lean RTG probe, VEEGA route', D);
end;

procedure TestEarthEvents;
var
  Ev: TEarthEventArray;
  I, SI: Integer;
  PolarSeen, TropicSeen: Integer;
begin
  { Thirty fires in the far north and ten storms in the tropics: a polar orbit
    must see them all, a tropical orbit only the storms. }
  SetLength(Ev, 40);
  for I := 0 to 39 do
  begin
    Ev[I].Title := 'Test event ' + IntToStr(I);
    Ev[I].Date := '2026-11-01';
    if I < 30 then
    begin
      Ev[I].Category := 'wildfires';
      Ev[I].Lat := 60 + (I mod 5);
      Ev[I].Lon := -120 + I * 3;
    end
    else
    begin
      Ev[I].Category := 'severeStorms';
      Ev[I].Lat := 10 + (I mod 5);
      Ev[I].Lon := 130 + I;
    end;
  end;
  ApplyEarthEvents(Ev, 'test data');
  SI := FindScenario('earth');
  PolarSeen := Scenarios[SI].Orbits[2].EventsSeen;
  TropicSeen := Scenarios[SI].Orbits[1].EventsSeen;
  Check(PolarSeen = 40, 'polar orbit sees all 40 events, got ' + IntToStr(PolarSeen));
  Check(TropicSeen = 10, 'tropical orbit sees only the 10 tropical storms, got ' + IntToStr(TropicSeen));
  Check(Scenarios[SI].Orbits[1].Factor[mThermal] < Scenarios[SI].Orbits[2].Factor[mThermal] * 0.7,
    'tropical orbit is much poorer than polar for fires that are all in the far north');
  Check(Scenarios[SI].Orbits[1].Factor[mAtmos] > 0.9, 'tropical orbit is good for tropical storms');
  Check(Scenarios[SI].Weight[mThermal] > 0, 'event mix sets the science priorities');
end;

procedure TestExamples;
var
  I: Integer;
  D: TDesign;
  A: TAnalysis;
  Df: TDifficulty;
begin
  { Every built-in example must pass the review board. }
  for I := 0 to High(Scenarios) do
  begin
    D := ExampleDesign(I, dfEngineer, False);
    A := Analyze(D);
    Report('EXAMPLE for ' + Scenarios[I].Name, D);
    Check(A.Blockers = 0, 'example design for ' + Scenarios[I].Id + ' closes');
    Check(A.SciencePct >= Scenarios[I].ThresholdPct, 'example design for ' + Scenarios[I].Id + ' meets minimum science');
    { It must also pass on the easiest and the hardest level, where the cost cap differs. }
    for Df := Low(TDifficulty) to High(TDifficulty) do
    begin
      A := Analyze(ExampleDesign(I, Df, False));
      Check(A.Blockers = 0, 'example design for ' + Scenarios[I].Id + ' closes at level ' + DifficultyName[Df] +
        ' (cost ' + FmtMoney(A.CostTotal) + ' of ' + FmtMoney(A.CapM) + ')');
    end;
  end;
end;

procedure Stories;
var
  D: TDesign;
begin
  D := NewDesign(FindScenario('moon'), dfEngineer, False);
  Pick(D, 'neutron'); Pick(D, 'spec_vnir'); Pick(D, 'tir');
  D.Orbit := 1; D.Transfer := 0;
  SetPart(D, pkThermal, 'cryo');
  D.SolarM2 := 2; D.BatteryWh := 500;
  D.Launcher := FindLauncher('rideshare');
  D.Seed := 2026;
  Story(D);

  D := NewDesign(FindScenario('mars'), dfEngineer, False);
  Pick(D, 'radiometer'); Pick(D, 'cam_ctx'); Pick(D, 'spec_vnir'); Pick(D, 'relay');
  SetPart(D, pkBus, 'medium');
  SetPart(D, pkPropulsion, 'biprop');
  SetPart(D, pkAntenna, 'dish30'); SetPart(D, pkBand, 'ka'); SetPart(D, pkTx, 'tx100');
  SetPart(D, pkGround, 'standard'); SetPart(D, pkComputer, 'radhard'); SetPart(D, pkThermal, 'cryo');
  D.SolarM2 := 12; D.BatteryWh := 900;
  D.Launcher := FindLauncher('h3');
  D.Seed := 777;
  Story(D);
end;

begin
  Writeln('Atomic Space core tests');
  TestCatalog;
  TestPhysics;
  TestShareCode;
  SampleDesigns;
  TestExamples;
  Stories;
  TestEarthEvents;
  Writeln('');
  Writeln(Checks, ' checks, ', Failures, ' failed');
  if Failures > 0 then
    raise Exception.Create(IntToStr(Failures) + ' test(s) failed');
end.
