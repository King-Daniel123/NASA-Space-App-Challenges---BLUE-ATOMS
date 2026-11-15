unit TsEngine;

{ Atomic Space - the mission analysis engine.

  Analyze() takes every decision the player has made and works out whether the
  design "closes": mass, power, propellant (Tsiolkovsky rocket equation),
  data link (inverse-square law), cost, schedule and risk. It also explains,
  in plain language, what is wrong and how each part affects the others.

  Plain Object Pascal: compiles with Delphi, Free Pascal and pas2js.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$IFDEF PAS2JS}{$mode delphi}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$ENDIF}

interface

uses
  TsTypes;

type
  TLaunchOption = record
    CapKg, CostM, Margin: Double;
    CanReach, Fits: Boolean;
    Why: string;
  end;

function DifficultyCapMult(Df: TDifficulty): Double;
function NewDesign(AScenario: Integer; ADifficulty: TDifficulty; ASandbox: Boolean): TDesign;
function InstrumentOffered(AScenario, AInstr: Integer): Boolean;
function SelectedCount(const D: TDesign): Integer;
function LauncherCapacity(ALauncher: Integer; const D: TDesign; var Why: string): Double;
function LauncherCost(ALauncher: Integer; const D: TDesign; WetKg: Double): Double;
function LaunchOption(ALauncher: Integer; const D: TDesign; WetKg: Double): TLaunchOption;
function LinkRateMbps(const D: TDesign; DistAU: Double; PointingTier: Integer): Double;
function LaunchEnergy(const D: TDesign): Double;
function LaunchTargetName(const D: TDesign): string;
{ How well each instrument works (0 = not flown or dead, 1 = perfect). }
procedure InstrumentQuality(const D: TDesign; const Alive: TBoolArray; PointTier: Integer;
  var Q: TDoubleArray);
{ What the payload can measure from the chosen orbit, 0..110 per measurement. }
function MeasureCapability(const D: TDesign; const Q: TDoubleArray): TMeasureValues;
{ Data the working instruments record per day, in gigabits. }
function DataGenGbitDay(const D: TDesign; const Alive: TBoolArray): Double;
function Analyze(const D: TDesign): TAnalysis;
function EncodeDesign(const D: TDesign): string;
function DecodeDesign(const Code: string; var D: TDesign): Boolean;

implementation

uses
  SysUtils, Math, TsCatalog, TsScenarios, TsFmt;

function DifficultyCapMult(Df: TDifficulty): Double;
begin
  case Df of
    dfCadet: Result := 1.2;
    dfChief: Result := 0.9;
  else
    Result := 1.0;
  end;
end;

function NewDesign(AScenario: Integer; ADifficulty: TDifficulty; ASandbox: Boolean): TDesign;
var
  K: TPartKind;
  I: Integer;
  Near, Far: Boolean;
begin
  Near := Scenarios[AScenario].NearEarth;
  Far := Scenarios[AScenario].SunAU > 3;
  Result.Scenario := AScenario;
  Result.Difficulty := ADifficulty;
  Result.Sandbox := ASandbox;
  Result.Orbit := 0;
  Result.Transfer := 0;
  for K := Low(TPartKind) to High(TPartKind) do
    Result.Part[K] := 0;
  { A plain, sensible starting point. The player improves on it. }
  Result.Part[pkBus] := 1;
  if Far then
    Result.Part[pkBus] := 2;
  if Near then
    Result.Part[pkPropulsion] := 0
  else if Far or (Scenarios[AScenario].Id = 'mars') then
    Result.Part[pkPropulsion] := 3
  else
    Result.Part[pkPropulsion] := 2;
  Result.Part[pkAdcs] := 1;
  Result.Part[pkThermal] := 0;
  if Near then
    Result.Part[pkComputer] := 0
  else
    Result.Part[pkComputer] := 1;
  Result.Part[pkShield] := 0;
  if Near then
  begin
    Result.Part[pkAntenna] := 0;
    Result.Part[pkBand] := 1;
  end
  else
  begin
    Result.Part[pkAntenna] := 1;
    Result.Part[pkBand] := 2;
  end;
  Result.Part[pkTx] := 0;
  Result.Part[pkGround] := 0;
  Result.Part[pkRisk] := 1;
  Result.Part[pkSchedule] := 0;
  Result.Launcher := -1;
  SetLength(Result.Instr, Length(Instruments));
  for I := 0 to High(Result.Instr) do
    Result.Instr[I] := False;
  if Far then
    Result.SolarM2 := 20
  else if Scenarios[AScenario].SunAU > 1.3 then
    Result.SolarM2 := 5
  else if Near then
    Result.SolarM2 := 1.0
  else
    Result.SolarM2 := 1.5;
  Result.RtgCount := 0;
  Result.BatteryWh := 300;
  Result.LifeYears := Scenarios[AScenario].DefaultLife;
  Result.ReservePct := 20;
  Result.Seed := 12345;
end;

function InstrumentOffered(AScenario, AInstr: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Scenarios[AScenario].Instruments) do
    if Scenarios[AScenario].Instruments[I] = Instruments[AInstr].Id then
    begin
      Result := True;
      Exit;
    end;
end;

function SelectedCount(const D: TDesign): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(D.Instr) do
    if D.Instr[I] and InstrumentOffered(D.Scenario, I) then
      Inc(Result);
end;

function LaunchEnergy(const D: TDesign): Double;
begin
  Result := Scenarios[D.Scenario].Transfers[D.Transfer].C3 +
    Scenarios[D.Scenario].Orbits[D.Orbit].C3;
end;

function LaunchTargetName(const D: TDesign): string;
begin
  case Scenarios[D.Scenario].Orbits[D.Orbit].LvMode of
    lvLEO: Result := 'low Earth orbit';
    lvSSO: Result := 'sun-synchronous orbit';
    lvGTO: Result := 'geostationary transfer orbit';
  else
    Result := 'this escape route (launch energy C3 = ' + FmtNum(LaunchEnergy(D), 0) + ' km2/s2)';
  end;
end;

function LauncherCapacity(ALauncher: Integer; const D: TDesign; var Why: string): Double;
var
  L: TLauncher;
  O: TOrbit;
  C3: Double;
  BusCls: TBusClass;
begin
  Result := 0;
  Why := '';
  if (ALauncher < 0) or (ALauncher > High(Launchers)) then
    Exit;
  L := Launchers[ALauncher];
  O := Scenarios[D.Scenario].Orbits[D.Orbit];
  BusCls := BusClassOf(Parts[pkBus][D.Part[pkBus]]);
  if Ord(BusCls) > Ord(L.MaxBus) then
  begin
    Why := 'A ' + BusClassName[BusCls] + ' does not fit this launcher.';
    Exit;
  end;
  case O.LvMode of
    lvLEO: Result := L.LeoKg;
    lvSSO: Result := L.SsoKg;
    lvGTO: Result := L.GtoKg;
  else
    begin
      C3 := LaunchEnergy(D);
      if L.C3ZeroKg > 0 then
        Result := L.C3ZeroKg * Exp(-C3 / L.C3K);
      if L.Rideshare and ((C3 > 15) or (D.Transfer <> 0)) then
      begin
        Result := 0;
        Why := 'No shared launch is going that way. A rideshare can only follow the main passenger''s route.';
        Exit;
      end;
    end;
  end;
  if (Result <= 0) and (Why = '') then
  begin
    if L.Rideshare then
      Why := 'Rideshare launches only go to sun-synchronous orbit or along a standard deep-space route.'
    else
      Why := 'This rocket cannot deliver anything to ' + LaunchTargetName(D) + '.';
  end;
end;

function LauncherCost(ALauncher: Integer; const D: TDesign; WetKg: Double): Double;
var
  L: TLauncher;
begin
  Result := 0;
  if (ALauncher < 0) or (ALauncher > High(Launchers)) then
    Exit;
  L := Launchers[ALauncher];
  if L.Rideshare then
  begin
    if Scenarios[D.Scenario].Orbits[D.Orbit].LvMode = lvC3 then
      Result := 9
    else
      Result := MaxD(1.2, 0.0065 * WetKg);
  end
  else
    Result := L.CostM;
end;

function LaunchOption(ALauncher: Integer; const D: TDesign; WetKg: Double): TLaunchOption;
var
  Why: string;
begin
  Result.CapKg := LauncherCapacity(ALauncher, D, Why);
  Result.Why := Why;
  Result.CostM := LauncherCost(ALauncher, D, WetKg);
  Result.CanReach := Result.CapKg > 0;
  Result.Fits := Result.CanReach and (WetKg <= Result.CapKg);
  if Result.CanReach then
    Result.Margin := (Result.CapKg - WetKg) / Result.CapKg
  else
    Result.Margin := -1;
end;

function LinkRateMbps(const D: TDesign; DistAU: Double; PointingTier: Integer): Double;
var
  Ant, Band, Tx, Gnd: TPart;
  D2: Double;
begin
  Ant := Parts[pkAntenna][D.Part[pkAntenna]];
  Band := Parts[pkBand][D.Part[pkBand]];
  Tx := Parts[pkTx][D.Part[pkTx]];
  Gnd := Parts[pkGround][D.Part[pkGround]];
  if DistAU < 1.0e-6 then
    DistAU := 1.0e-6;
  D2 := DistAU * DistAU;
  if Band.Tier = 4 then
    { Laser link: its own telescope and laser, so dish and transmitter do not matter. }
    Result := Band.A / D2
  else
    { Inverse-square law: power x dish area x band x ground dish / distance squared }
    Result := LinkK * Tx.A * Ant.A * Ant.A * Band.A * Gnd.C / D2;
  if Result > Band.B then
    Result := Band.B;
  { A narrow beam that cannot be held on Earth loses most of its signal. }
  if Round(Band.D) > PointingTier then
    Result := Result * 0.25
  else if (Ant.A >= 0.5) and (PointingTier < 1) and (Band.Tier < 4) then
    Result := Result * 0.3;
end;

procedure InstrumentQuality(const D: TDesign; const Alive: TBoolArray; PointTier: Integer;
  var Q: TDoubleArray);
var
  I: Integer;
  Therm, Ant, Band: TPart;
  V: Double;
begin
  Therm := Parts[pkThermal][D.Part[pkThermal]];
  Ant := Parts[pkAntenna][D.Part[pkAntenna]];
  Band := Parts[pkBand][D.Part[pkBand]];
  SetLength(Q, Length(Instruments));
  for I := 0 to High(Instruments) do
  begin
    Q[I] := 0;
    if (I > High(D.Instr)) or not D.Instr[I] then
      Continue;
    if (I <= High(Alive)) and not Alive[I] then
      Continue;
    if not InstrumentOffered(D.Scenario, I) then
      Continue;
    V := 1;
    if Instruments[I].NeedsFinePointing and (PointTier < 1) then
      V := V * 0.4;   // blurred pictures
    if Instruments[I].NeedsCooling and (Therm.Tier < 2) then
      V := V * 0.5;   // warm, noisy detector
    if Instruments[I].NeedsHGA and ((Ant.A < 0.5) or (Band.Tier < 2)) then
      V := V * 0.25;  // radio too weak for gravity science
    Q[I] := V;
  end;
end;

function MeasureCapability(const D: TDesign; const Q: TDoubleArray): TMeasureValues;
var
  M: TMeasure;
  I, J, N: Integer;
  Contrib: TDoubleArray;
  Sum, Share, Tmp: Double;
  O: TOrbit;
begin
  O := Scenarios[D.Scenario].Orbits[D.Orbit];
  for M := Low(TMeasure) to High(TMeasure) do
  begin
    SetLength(Contrib, 0);
    for I := 0 to High(Instruments) do
      if (I <= High(Q)) and (Q[I] > 0) and (Instruments[I].Value[M] > 0) then
      begin
        N := Length(Contrib);
        SetLength(Contrib, N + 1);
        Contrib[N] := Instruments[I].Value[M] * Q[I];
      end;
    { Sort high to low: a second instrument measuring the same thing adds half as much. }
    for I := 0 to High(Contrib) - 1 do
      for J := I + 1 to High(Contrib) do
        if Contrib[J] > Contrib[I] then
        begin
          Tmp := Contrib[I];
          Contrib[I] := Contrib[J];
          Contrib[J] := Tmp;
        end;
    Sum := 0;
    Share := 1;
    for I := 0 to High(Contrib) do
    begin
      Sum := Sum + Contrib[I] * Share;
      Share := Share * 0.5;
    end;
    Result[M] := MinD(110, Sum * O.Factor[M]);
  end;
end;

function DataGenGbitDay(const D: TDesign; const Alive: TBoolArray): Double;
var
  I: Integer;
  Mbps: Double;
begin
  Mbps := 0;
  for I := 0 to High(Instruments) do
    if (I <= High(D.Instr)) and D.Instr[I] and InstrumentOffered(D.Scenario, I) and
      ((I > High(Alive)) or Alive[I]) then
      Mbps := Mbps + Instruments[I].DataMbps * Instruments[I].Duty * Scenarios[D.Scenario].DataScale *
        Scenarios[D.Scenario].Orbits[D.Orbit].DataFactor;
  Result := Mbps * 86400 / 1000;
end;

function Analyze(const D: TDesign): TAnalysis;
var
  A: TAnalysis;
  NoDead: TBoolArray;
  GP: Double;
  Sc: TScenario;
  O: TOrbit;
  Tr: TTransfer;
  Bus, Prop, Adcs, Therm, Comp, Shield, Ant, Band, Tx, Gnd, Risk, Sched: TPart;
  L: TLauncher;
  G, G06, G07, G08: Double;
  I, J, N, Cnt, Prot, K: Integer;
  M: TMeasure;
  Ins: TInstrument;
  PayW, PayPeakW, PayCost, PayDev, GenMbps: Double;
  AdcsKg, AdcsW, AdcsCost, CompKg, CompCost, ShieldKg, ShieldCost: Double;
  ThermCost, HeaterW, ArrayKg, ArrayCost, BattKg, BattCost, RtgKgT, RtgCost: Double;
  PropDry, PropCost, TankKg, BaseKg, DryNoTank, X, Denom: Double;
  BaseW, CommW, TxDuty, Ecl, SepNeedW, SepHaveW, MidAU: Double;
  DistAvg, DistMax, Dev, OpsYear, SlipCost, CapSum, PowerFactor, DataFactor: Double;
  EffLife, LifeRad, FailRate, Q, Best, SunShare, CapMult: Double;
  Contrib: TDoubleArray;
  Names, BigName: string;
  Why: string;
  Late, HasPrimary, UsesSep: Boolean;
  Prim: TMeasure;
  SevCost: TSeverity;

  procedure AddF(ASev: TSeverity; const ACode, ATitle, AWhy, AFix: string; AOwner: TRole);
  var
    Idx: Integer;
  begin
    Idx := Length(A.Findings);
    SetLength(A.Findings, Idx + 1);
    A.Findings[Idx].Sev := ASev;
    A.Findings[Idx].Code := ACode;
    A.Findings[Idx].Title := ATitle;
    A.Findings[Idx].Why := AWhy;
    A.Findings[Idx].Fix := AFix;
    A.Findings[Idx].Owner := AOwner;
    if ASev = svBlock then
      Inc(A.Blockers)
    else if ASev = svWarn then
      Inc(A.Warnings);
  end;

begin
  Sc := Scenarios[D.Scenario];
  O := Sc.Orbits[D.Orbit];
  Tr := Sc.Transfers[D.Transfer];
  Bus := Parts[pkBus][D.Part[pkBus]];
  Prop := Parts[pkPropulsion][D.Part[pkPropulsion]];
  Adcs := Parts[pkAdcs][D.Part[pkAdcs]];
  Therm := Parts[pkThermal][D.Part[pkThermal]];
  Comp := Parts[pkComputer][D.Part[pkComputer]];
  Shield := Parts[pkShield][D.Part[pkShield]];
  Ant := Parts[pkAntenna][D.Part[pkAntenna]];
  Band := Parts[pkBand][D.Part[pkBand]];
  Tx := Parts[pkTx][D.Part[pkTx]];
  Gnd := Parts[pkGround][D.Part[pkGround]];
  Risk := Parts[pkRisk][D.Part[pkRisk]];
  Sched := Parts[pkSchedule][D.Part[pkSchedule]];

  SetLength(A.Findings, 0);
  SetLength(A.MassLines, 0);
  SetLength(A.PowerLines, 0);
  SetLength(A.CostLines, 0);
  A.Blockers := 0;
  A.Warnings := 0;
  A.LifeLimitWhy := '';
  UsesSep := Prop.Tier = 4;

  G := Bus.G;
  G06 := Power(G, 0.6);
  G07 := Power(G, 0.7);
  G08 := Power(G, 0.8);
  CapMult := DifficultyCapMult(D.Difficulty);

  { ---------------- payload ---------------- }
  A.PayloadKg := 0;
  PayW := 0;
  PayPeakW := 0;
  PayCost := 0;
  PayDev := 0;
  GenMbps := 0;
  Cnt := 0;
  SetLength(NoDead, 0);
  InstrumentQuality(D, NoDead, Adcs.Tier, A.InstrQuality);
  for I := 0 to High(Instruments) do
    if A.InstrQuality[I] > 0 then
    begin
      Ins := Instruments[I];
      Inc(Cnt);
      A.PayloadKg := A.PayloadKg + Ins.MassKg;
      PayW := PayW + Ins.PowerW * (0.2 + 0.8 * Ins.Duty);
      PayPeakW := PayPeakW + Ins.PowerW;
      PayCost := PayCost + Ins.CostM;
      { Instruments are built side by side, so the slowest one sets the pace. }
      if Ins.DevYears > PayDev then
        PayDev := Ins.DevYears;
      GenMbps := GenMbps + Ins.DataMbps * Ins.Duty * Sc.DataScale * O.DataFactor;
    end;
  if Cnt > 1 then
    PayDev := PayDev + 0.08 * (Cnt - 1);
  A.InstrumentCount := Cnt;
  A.PointingTier := Adcs.Tier;

  { ---------------- subsystem sizes ---------------- }
  AdcsKg := Adcs.MassKg * G * Risk.B;
  AdcsW := Adcs.PowerW * G08;
  AdcsCost := Adcs.CostM * G07 * Risk.A;
  CompKg := Comp.MassKg * Risk.B;
  CompCost := Comp.CostM * Risk.A;
  ShieldKg := Shield.MassKg * G;
  ShieldCost := Shield.CostM * G07;
  HeaterW := Sc.HeaterW * G07 * Therm.B;
  if D.RtgCount > 0 then
    HeaterW := HeaterW * 0.5;  // a nuclear battery's waste heat keeps the spacecraft warm
  ThermCost := Therm.CostM * G07 + Therm.E;
  ArrayKg := D.SolarM2 * ArrayKgPerM2;
  ArrayCost := 0;
  if D.SolarM2 > 0 then
    ArrayCost := D.SolarM2 * ArrayCostPerM2 + 0.4;
  BattKg := D.BatteryWh / BatteryWhPerKg;
  BattCost := 0;
  if D.BatteryWh > 0 then
    BattCost := D.BatteryWh * BatteryCostPerWh + 0.2;
  RtgKgT := D.RtgCount * RtgKg;
  RtgCost := D.RtgCount * RtgCostM;
  { Engines shrink well for small spacecraft, but not in proportion for big ones. }
  if G >= 1 then
    GP := G06
  else
    GP := Power(G, 1.1);
  PropDry := Prop.MassKg * GP;

  BaseKg := Bus.MassKg + A.PayloadKg + AdcsKg + CompKg + ShieldKg + Ant.MassKg +
    Band.MassKg + Tx.MassKg + Therm.MassKg + ArrayKg + BattKg + RtgKgT + PropDry;
  DryNoTank := BaseKg * (1 + Therm.A + HarnessFraction);

  { ---------------- delta-v and propellant (rocket equation) ---------------- }
  A.DvInsert := O.DvInsert * Tr.DvFactor;
  if UsesSep then
    A.DvInsert := A.DvInsert * Sc.SepDvFactor;
  A.DvKeep := O.DvPerYear * D.LifeYears;
  A.DvDisposal := 0;
  if O.NeedsDeorbit and (Prop.Tier > 0) then
    A.DvDisposal := 160;
  A.DvNeed := (A.DvInsert + A.DvKeep + A.DvDisposal) * (1 + DvMargin);
  A.PropFeasible := True;
  A.PropKg := 0;
  TankKg := 0;
  if (Prop.Tier > 0) and (A.DvNeed > 0) then
  begin
    X := Exp(A.DvNeed / (Prop.A * G0)) - 1;
    Denom := 1 - Prop.B * X;
    if Denom <= 0.05 then
    begin
      A.PropFeasible := False;
      A.PropKg := DryNoTank * 20;
    end
    else
      A.PropKg := DryNoTank * X / Denom;
    TankKg := Prop.B * A.PropKg;
  end;
  A.DryKg := DryNoTank + TankKg;
  A.WetKg := A.DryKg + A.PropKg;
  PropCost := 0;
  if Prop.Tier > 0 then
    PropCost := (Prop.CostM * GP + Prop.E * A.PropKg) * Risk.A;

  AddLine(A.MassLines, 'Structure', Bus.MassKg);
  AddLine(A.MassLines, 'Instruments', A.PayloadKg);
  AddLine(A.MassLines, 'Power system', ArrayKg + BattKg + RtgKgT);
  AddLine(A.MassLines, 'Communications', Ant.MassKg + Band.MassKg + Tx.MassKg);
  AddLine(A.MassLines, 'Avionics and pointing', AdcsKg + CompKg + ShieldKg);
  AddLine(A.MassLines, 'Thermal and cabling', Therm.MassKg + BaseKg * (Therm.A + HarnessFraction));
  AddLine(A.MassLines, 'Engines and tanks', PropDry + TankKg);
  AddLine(A.MassLines, 'Propellant', A.PropKg);

  { ---------------- launch vehicle ---------------- }
  A.LvCapKg := 0;
  A.MassMargin := -1;
  A.CostLaunch := 0;
  if D.Launcher >= 0 then
  begin
    A.LvCapKg := LauncherCapacity(D.Launcher, D, Why);
    A.CostLaunch := LauncherCost(D.Launcher, D, A.WetKg);
    if A.LvCapKg > 0 then
      A.MassMargin := (A.LvCapKg - A.WetKg) / A.LvCapKg;
  end;

  { ---------------- communications and data ---------------- }
  if Sc.NearEarth then
  begin
    DistAvg := O.RangeKm / AuKm;
    DistMax := DistAvg;
    A.ContactHr := Gnd.B * O.CommFactor;
  end
  else
  begin
    DistAvg := (Sc.EarthMinAU + Sc.EarthMaxAU) / 2;
    DistMax := Sc.EarthMaxAU;
    A.ContactHr := Gnd.A * O.CommFactor;
  end;
  if A.ContactHr > 24 then
    A.ContactHr := 24;
  A.ContactHr := A.ContactHr * Band.C;
  A.RateAvgMbps := LinkRateMbps(D, DistAvg, Adcs.Tier);
  A.RateMinMbps := LinkRateMbps(D, DistMax, Adcs.Tier);
  A.DownGbitDay := A.RateAvgMbps * A.ContactHr * 3600 / 1000;
  A.GenGbitDay := GenMbps * 86400 / 1000;
  if A.GenGbitDay > 0 then
    A.DataReturn := MinD(1, A.DownGbitDay / A.GenGbitDay)
  else
    A.DataReturn := 1;
  A.StorageGbit := Comp.A;
  if A.GenGbitDay > 0 then
    A.StorageDays := A.StorageGbit / A.GenGbitDay
  else
    A.StorageDays := 999;
  A.LightDelayMin := DistAvg * LightSecondsPerAu / 60;
  TxDuty := A.ContactHr / 24;

  { ---------------- power ---------------- }
  A.SolarW := D.SolarM2 * ArrayWattsPerM2 / (Sc.SunAU * Sc.SunAU);
  if Sc.SunAU > 3 then
    A.SolarW := A.SolarW * 0.85;  // cold, dim light makes cells less efficient
  A.RtgW := D.RtgCount * RtgWatts;
  A.GenW := A.SolarW + A.RtgW;
  Ecl := O.EclipseFrac;
  { Energy balance over one orbit: sunlight must run the spacecraft and refill the battery. }
  A.GenAvgW := A.RtgW + A.SolarW * (1 - Ecl) / (1 - Ecl + Ecl / 0.85);
  BaseW := Bus.PowerW + AdcsW + Comp.PowerW + MinD(Band.PowerW, 10) + Therm.PowerW + HeaterW;
  CommW := Tx.PowerW * TxDuty;
  if Band.Tier = 4 then
    CommW := (Band.PowerW - 10) * TxDuty;
  A.LoadAvgW := BaseW + PayW + CommW;
  A.LoadPeakW := BaseW + PayPeakW + Tx.PowerW;
  if A.LoadAvgW > 0 then
    A.PowerMargin := (A.GenAvgW - A.LoadAvgW) / A.LoadAvgW
  else
    A.PowerMargin := 0;
  A.BatteryNeedWh := 0;
  if (O.MaxEclipseHr > 0) and (A.LoadAvgW > A.RtgW) then
    A.BatteryNeedWh := (A.LoadAvgW - A.RtgW) * O.MaxEclipseHr / 0.6;
  AddLine(A.PowerLines, 'Spacecraft housekeeping', Bus.PowerW + Comp.PowerW + MinD(Band.PowerW, 10));
  AddLine(A.PowerLines, 'Pointing', AdcsW);
  AddLine(A.PowerLines, 'Heaters and coolers', Therm.PowerW + HeaterW);
  AddLine(A.PowerLines, 'Instruments', PayW);
  AddLine(A.PowerLines, 'Transmitter (averaged)', CommW);

  { ---------------- schedule ---------------- }
  A.DevYears := Bus.DevYears + PayDev + Prop.DevYears + Therm.DevYears + Comp.DevYears +
    Shield.DevYears + Band.DevYears + Adcs.DevYears + Ant.DevYears + Risk.D;
  if D.RtgCount > 0 then
    A.DevYears := A.DevYears + 1.0;
  A.DevYears := MaxD(0.75, A.DevYears * Sched.A);
  A.LaunchYear := A.DevYears;
  if Sc.WindowYears > 0 then
  begin
    A.LaunchYear := Sc.WindowYears;
    K := 0;
    while (A.LaunchYear < A.DevYears - 0.001) and (K < 20) do
    begin
      A.LaunchYear := A.LaunchYear + Sc.WindowPeriod;
      Inc(K);
    end;
  end;
  A.CruiseYears := Tr.CruiseYears + O.ExtraYears;
  if UsesSep then
    A.CruiseYears := A.CruiseYears + Sc.SepExtraYears;
  A.ArriveYear := A.LaunchYear + A.CruiseYears;
  if Sc.ArriveBy then
    Late := A.ArriveYear > Sc.DeadlineYears + 0.001
  else
    Late := A.LaunchYear > Sc.DeadlineYears + 0.001;
  A.MissedDeadline := Late;
  A.SlipYears := 0;
  if Late and not Sc.ArriveBy then
    A.SlipYears := A.LaunchYear - Sc.DeadlineYears;
  A.LifeYears := D.LifeYears;

  { ---------------- radiation and lifetime limits ---------------- }
  Prot := Comp.Tier + Shield.Tier;
  A.RadExposure := O.RadLevel - Prot;
  if A.RadExposure < 0 then
    A.RadExposure := 0;
  A.LifeLimitYears := 1000;
  if O.RadLifeYears > 0 then
  begin
    LifeRad := O.RadLifeYears;
    if Prot > O.RadLevel then
      LifeRad := LifeRad * (1 + 0.8 * (Prot - O.RadLevel));
    for J := 1 to A.RadExposure do
      LifeRad := LifeRad * 0.4;
    if LifeRad < A.LifeLimitYears then
    begin
      A.LifeLimitYears := LifeRad;
      A.LifeLimitWhy := 'radiation damage to the electronics';
    end;
  end;
  if (O.DragLifeYears > 0) and (Prop.Tier = 0) and (O.DragLifeYears < A.LifeLimitYears) then
  begin
    A.LifeLimitYears := O.DragLifeYears;
    A.LifeLimitWhy := 'air drag pulling the orbit down';
  end;
  EffLife := MinD(D.LifeYears, A.LifeLimitYears);

  { ---------------- science ---------------- }
  Prim := PrimaryMeasure(Sc);
  HasPrimary := False;
  for I := 0 to High(Instruments) do
    if (A.InstrQuality[I] > 0) and (Instruments[I].Value[Prim] >= 30) then
      HasPrimary := True;
  A.Capability := MeasureCapability(D, A.InstrQuality);
  CapSum := 0;
  for M := Low(TMeasure) to High(TMeasure) do
    CapSum := CapSum + Sc.Weight[M] * A.Capability[M] / 100;
  CapSum := CapSum * O.Coverage;
  A.ScienceMaxPct := 100 * CapSum / Sc.FullScience;
  PowerFactor := 1;
  if A.LoadAvgW > 0 then
    PowerFactor := Clamp(A.GenAvgW / A.LoadAvgW, 0, 1);
  DataFactor := Power(MaxD(0.0004, A.DataReturn), 0.7);
  A.TauYears := Sc.TauYears * O.TauFactor / MaxD(0.03, PowerFactor * DataFactor);
  A.SciencePct := A.ScienceMaxPct * (1 - Exp(-EffLife / A.TauYears));
  if Late and Sc.ArriveBy then
    A.SciencePct := A.SciencePct * Sc.LateFactor;

  { ---------------- risk ---------------- }
  { Expected faults per year: the bus's own record, scaled by how carefully it
    is built, plus whatever the environment adds. }
  FailRate := (1 - Bus.F) * Risk.C * Sched.C;
  if A.RadExposure = 1 then
    FailRate := FailRate + 0.5
  else if A.RadExposure = 2 then
    FailRate := FailRate + 2.0
  else if A.RadExposure >= 3 then
    FailRate := FailRate + 6.0;
  if (Adcs.Tier > 0) and (Prop.Tier = 0) and not Sc.NearEarth then
    FailRate := FailRate + 0.4;
  if Sc.ColdWorld and (Therm.Tier < 1) then
    FailRate := FailRate + 0.6;
  if Tr.HotFlyby and (Therm.Tier < 1) then
    FailRate := FailRate + 0.4;
  A.AnomalyRate := FailRate;
  { About one fault in five ends a mission. Full redundancy halves that. }
  A.FatalShare := 0.22;
  if Risk.Tier = 2 then
    A.FatalShare := 0.11;
  A.YearSurvival := Clamp(Exp(-FailRate * A.FatalShare), 0.02, 0.999);
  A.LaunchSuccess := 1;
  if D.Launcher >= 0 then
    A.LaunchSuccess := Launchers[D.Launcher].Reliability;
  if D.Difficulty = dfCadet then
    A.LaunchSuccess := 1;
  A.InsertSuccess := 1 - O.InsertRisk;
  if (A.DvInsert > 200) and (Prop.Tier > 0) then
    A.InsertSuccess := A.InsertSuccess * Prop.D;
  A.SuccessProb := A.LaunchSuccess * A.InsertSuccess *
    Power(A.YearSurvival, A.CruiseYears + EffLife);

  { ---------------- cost ---------------- }
  A.CostHardware := Bus.CostM * Risk.A + PayCost + AdcsCost + CompCost + ShieldCost +
    Ant.CostM + Band.CostM + Tx.CostM + ThermCost + ArrayCost + BattCost + RtgCost + PropCost;
  A.CostWraps := A.CostHardware * WrapFraction;
  Dev := (A.CostHardware + A.CostWraps) * Sched.B;
  OpsYear := Bus.E + Gnd.CostM + 0.6 * Cnt;
  A.CostOps := OpsYear * D.LifeYears + 0.5 * OpsYear * A.CruiseYears;
  SlipCost := A.SlipYears * 0.08 * Dev;
  A.CostReserve := Dev * D.ReservePct / 100;
  A.CostTotal := Dev + A.CostLaunch + A.CostOps + A.CostReserve + SlipCost;
  A.CapM := Sc.CostCapM * CapMult;
  A.CostMargin := (A.CapM - A.CostTotal) / A.CapM;
  A.DevCostM := Dev;
  A.OpsPerYearM := OpsYear;
  A.SlipCostM := SlipCost;
  AddLine(A.CostLines, 'Spacecraft bus', Bus.CostM * Risk.A * Sched.B);
  AddLine(A.CostLines, 'Instruments', PayCost * Sched.B);
  AddLine(A.CostLines, 'Power system', (ArrayCost + BattCost + RtgCost) * Sched.B);
  AddLine(A.CostLines, 'Propulsion', PropCost * Sched.B);
  AddLine(A.CostLines, 'Comms and avionics', (AdcsCost + CompCost + ShieldCost + Ant.CostM +
    Band.CostM + Tx.CostM + ThermCost) * Sched.B);
  AddLine(A.CostLines, 'Management, assembly and test', A.CostWraps * Sched.B);
  AddLine(A.CostLines, 'Launch', A.CostLaunch);
  AddLine(A.CostLines, 'Operations', A.CostOps);
  AddLine(A.CostLines, 'Reserves', A.CostReserve);
  if SlipCost > 0 then
    AddLine(A.CostLines, 'Cost of delay', SlipCost);

  { ======================= findings ======================= }
  SunShare := 1 / (Sc.SunAU * Sc.SunAU);

  if Cnt = 0 then
    AddF(svBlock, 'NO_INSTR', 'No science instruments',
      'The instruments are the reason the mission exists. Without them this is a very expensive paperweight.',
      'Open Payload and choose at least one instrument that serves the objective.', roScience);

  if Cnt > Round(Bus.C) then
    AddF(svBlock, 'INSTR_COUNT', 'Too many instruments for this bus',
      'A ' + Bus.Name + ' has mounting points, power feeds and data ports for ' + IntToStr(Round(Bus.C)) +
      ' instruments. You have chosen ' + IntToStr(Cnt) + '.',
      'Remove an instrument, or move up to a bigger spacecraft bus.', roSpacecraft);

  if A.PayloadKg > Bus.B then
    AddF(svBlock, 'PAYLOAD_MASS', 'Payload too heavy for this bus',
      'A ' + Bus.Name + ' can carry ' + FmtMass(Bus.B) + ' of instruments. Yours add up to ' + FmtMass(A.PayloadKg) + '.',
      'Drop the heaviest instrument, or choose a bigger bus.', roSpacecraft);

  Names := '';
  for I := 0 to High(Instruments) do
    if (A.InstrQuality[I] > 0) and (Ord(Instruments[I].MinBus) > Bus.Tier) then
    begin
      if Names <> '' then
        Names := Names + ', ';
      Names := Names + Instruments[I].Name;
    end;
  if Names <> '' then
    AddF(svBlock, 'INSTR_BUS', 'Instrument does not fit this bus',
      'Too large for a ' + Bus.Name + ': ' + Names + '.',
      'Choose a bigger bus or a smaller instrument.', roScience);

  if A.DryKg > Bus.A then
    AddF(svBlock, 'DRY_LIMIT', 'Too much equipment for the structure',
      'The frame of a ' + Bus.Name + ' is rated for ' + FmtMass(Bus.A) + ' of equipment. You have ' + FmtMass(A.DryKg) +
      ' before any propellant.',
      'Remove equipment or choose a bigger bus.', roSpacecraft);

  if D.SolarM2 > Bus.D + 0.001 then
    AddF(svBlock, 'ARRAY_LIMIT', 'Solar array too large for this bus',
      'A ' + Bus.Name + ' can deploy at most ' + FmtNum(Bus.D, 1) + ' m2 of panels. You have ' + FmtNum(D.SolarM2, 1) + ' m2.',
      'Shrink the array, cut power use, or choose a bigger bus.', roSpacecraft);

  if (D.RtgCount > 0) and not Sc.AllowRTG then
    AddF(svBlock, 'RTG_NA', 'Nuclear power is not approved for this mission',
      'Plutonium-238 is scarce and is reserved for places where sunlight is too weak. Here solar panels work.',
      'Remove the RTG and use solar panels.', roPM);

  if A.GenW <= 0 then
    AddF(svBlock, 'NO_POWER', 'No power source',
      'There are no solar panels and no nuclear battery. Nothing on board can switch on.',
      'Add solar array area in Bus and Power.', roSpacecraft)
  else if A.GenAvgW < A.LoadAvgW then
    AddF(svBlock, 'POWER_SHORT', 'Not enough power',
      'Averaged over an orbit the spacecraft makes ' + FmtPower(A.GenAvgW) + ' but needs ' + FmtPower(A.LoadAvgW) +
      '. Sunlight here is ' + FmtPct(SunShare) + ' of what Earth gets, and ' + FmtPct(Ecl) + ' of each orbit is in shadow.',
      'Add solar array area, remove a power-hungry instrument or choose a smaller transmitter.', roSpacecraft)
  else if A.PowerMargin < 0.2 then
    AddF(svWarn, 'POWER_THIN', 'Thin power margin (' + FmtPct(A.PowerMargin) + ')',
      'Solar panels fade a few percent every year and equipment usually draws more than planned. NASA teams aim for about 30 % spare at this stage.',
      'Add a little solar array area.', roSpacecraft)
  else if A.PowerMargin > 1.5 then
    AddF(svInfo, 'POWER_BIG', 'Power system is oversized',
      'You make ' + FmtPower(A.GenAvgW) + ' and need ' + FmtPower(A.LoadAvgW) + '. The spare panels cost mass and money that could buy science.',
      'Trim the array, or spend the power on another instrument or a stronger transmitter.', roSpacecraft);

  if (A.BatteryNeedWh > 0) and (D.BatteryWh < A.BatteryNeedWh) then
    AddF(svBlock, 'BATTERY', 'Battery too small for the dark',
      'The longest eclipse here lasts ' + FmtNum(O.MaxEclipseHr, 1) + ' hours. Staying alive through it takes about ' +
      FmtNum(A.BatteryNeedWh, 0) + ' Wh. You carry ' + FmtNum(D.BatteryWh, 0) + ' Wh.',
      'Add battery capacity, or cut power use.', roSpacecraft)
  else if (A.BatteryNeedWh > 0) and (D.BatteryWh < A.BatteryNeedWh * 1.25) then
    AddF(svWarn, 'BATTERY_THIN', 'Battery has almost no spare capacity',
      'Batteries lose capacity with every charge cycle. You carry ' + FmtNum(D.BatteryWh, 0) + ' Wh and need ' +
      FmtNum(A.BatteryNeedWh, 0) + ' Wh on day one.',
      'Carry at least a quarter more than you need.', roSpacecraft);

  if (Round(Adcs.A) = 1) and not ((Sc.NearEarth) and (O.AltKm < 2000)) then
    AddF(svBlock, 'ADCS_MTQ', 'Magnetorquers will not work here',
      'They turn the spacecraft by pushing against a planet''s magnetic field. Out here there is almost no field to push against.',
      'Choose reaction wheels.', roSpacecraft);

  if (Adcs.Tier > 0) and (Prop.Tier = 0) and not Sc.NearEarth then
    AddF(svWarn, 'ADCS_DESAT', 'Reaction wheels have no way to unload',
      'Wheels slowly spin faster as they fight sunlight pressure. Without thrusters to reset them they reach top speed and pointing is lost.',
      'Add any thrusters, even cold gas.', roSpacecraft);

  Names := '';
  for I := 0 to High(Instruments) do
    if (A.InstrQuality[I] > 0) and Instruments[I].NeedsFinePointing and (Adcs.Tier < 1) then
      Names := Names + Instruments[I].Name + ' ';
  if Names <> '' then
    AddF(svWarn, 'POINT_INSTR', 'Pictures will be blurred',
      Names + 'needs a very steady spacecraft. With coarse pointing it works at 40 %.',
      'Fit reaction wheels and a star tracker.', roSpacecraft);

  Names := '';
  for I := 0 to High(Instruments) do
    if (A.InstrQuality[I] > 0) and Instruments[I].NeedsCooling and (Therm.Tier < 2) then
      Names := Names + Instruments[I].Name + ' ';
  if Names <> '' then
    AddF(svWarn, 'COOLING', 'Infrared detector is too warm',
      Names + 'has a detector that must be far colder than the spacecraft. Without a cryocooler it works at half sensitivity.',
      'Choose thermal control with a cryocooler, or swap the instrument.', roSpacecraft);

  for I := 0 to High(Instruments) do
    if (A.InstrQuality[I] > 0) and Instruments[I].NeedsHGA and ((Ant.A < 0.5) or (Band.Tier < 2)) then
      AddF(svWarn, 'RADIO_HGA', 'Radio science needs a better radio',
        'Gravity is measured from tiny shifts in the radio signal. That needs a dish antenna and X-band or better. Working at 25 %.',
        'Fit a dish and X-band or Ka-band, or drop the radio science package.', roOps);

  if Sc.ColdWorld and (Therm.Tier < 1) then
    AddF(svWarn, 'THERMAL_COLD', 'Passive thermal control is not enough here',
      'The Sun delivers only ' + FmtPct(SunShare) + ' of the warmth it gives at Earth. Blankets alone cannot keep the propellant and electronics from freezing.',
      'Choose active thermal control.', roSpacecraft);
  if Tr.HotFlyby and (Therm.Tier < 1) then
    AddF(svWarn, 'THERMAL_HOT', 'This route passes Venus',
      'At Venus sunlight is twice as strong as at Earth. A spacecraft built for the cold of deep space needs a way to dump that heat.',
      'Choose active thermal control, or a route that does not go inward.', roSpacecraft);

  if A.RadExposure = 1 then
    AddF(svWarn, 'RAD', 'Electronics are exposed to radiation',
      'Beyond Earth''s magnetic shield, particles from the Sun and deep space flip bits and slowly damage chips. Expect an extra fault about every two years, and roughly a 10 % higher chance of losing the mission each year.',
      'Use a radiation-tolerant or hardened computer, or add shielding.', roSpacecraft)
  else if A.RadExposure >= 2 then
    AddF(svWarn, 'RAD', 'Radiation will destroy the electronics',
      'This is one of the harshest radiation environments in the solar system, and the electronics are far too lightly protected. They are unlikely to last a year.',
      'Fit a hardened computer and a radiation vault, or pick an orbit that stays out of the belts.', roSpacecraft);

  if (A.LifeLimitYears < D.LifeYears - 0.01) then
    AddF(svWarn, 'LIFE_LIMIT', 'Mission will end early, after about ' + FmtYears(A.LifeLimitYears),
      'You planned ' + FmtYears(D.LifeYears) + ', but ' + A.LifeLimitWhy + ' will stop the spacecraft first. You would still pay for the full plan.',
      'Fix the cause, or plan a shorter mission and save the operations cost.', roOps);

  if (Prop.Tier = 0) and (A.DvInsert > 0) then
    AddF(svBlock, 'PROP_NEEDED', 'This orbit needs an engine',
      'Reaching "' + O.Name + '" takes a speed change of ' + FmtDv(A.DvInsert) + ' after the rocket lets go. The spacecraft has no propulsion.',
      'Add a propulsion system.', roSpacecraft)
  else if not A.PropFeasible then
    AddF(svBlock, 'PROP_RUNAWAY', 'The rocket equation says no',
      'A speed change of ' + FmtDv(A.DvNeed) + ' with this engine needs more propellant than any tank could hold: ' +
      'every kilogram of fuel needs more fuel to carry it, and the demand grows exponentially.',
      'Use a more efficient engine, choose an orbit or route that needs less speed change, or shorten the mission.', roSpacecraft);

  if UsesSep and not Sc.AllowSEP then
    AddF(svBlock, 'SEP_NA', 'Electric propulsion cannot do this job',
      'Ion engines push too gently to brake into orbit here, and there is too little sunlight to run them.',
      'Use a bipropellant engine.', roSpacecraft)
  else if UsesSep then
  begin
    MidAU := (1 + Sc.SunAU) / 2;
    SepNeedW := Prop.C * G08;
    SepHaveW := D.SolarM2 * ArrayWattsPerM2 / (MidAU * MidAU) + A.RtgW;
    if SepHaveW < SepNeedW then
      AddF(svBlock, 'SEP_POWER', 'Not enough power for the ion engine',
        'The engine needs ' + FmtPower(SepNeedW) + ' while thrusting. On the way out the panels give about ' + FmtPower(SepHaveW) + '.',
        'Add solar array area, or use a chemical engine.', roSpacecraft);
  end;

  if (O.DragLifeYears > 0) and (Prop.Tier = 0) and (O.DragLifeYears >= D.LifeYears) and (O.DragLifeYears < 10) then
    AddF(svInfo, 'DRAG', 'Orbit decays in about ' + FmtYears(O.DragLifeYears),
      'With no engine, thin air at this height slowly pulls the satellite down. That is long enough for your plan, and it tidies the satellite away afterwards.',
      'Nothing to do unless you want a longer mission.', roOps);

  if O.NeedsDeorbit and (Prop.Tier = 0) then
    AddF(svWarn, 'DEORBIT', 'No plan to remove the satellite',
      'At ' + FmtNum(O.AltKm, 0) + ' km a dead satellite stays up for centuries as space junk. Operators are expected to remove it within 25 years.',
      'Add propulsion: the disposal burn is then budgeted automatically.', roPM);

  if D.Launcher < 0 then
    AddF(svBlock, 'LV_NONE', 'No launch vehicle chosen',
      'The spacecraft weighs ' + FmtMass(A.WetKg) + ' fuelled and has no ride.',
      'Open Launch and choose a rocket that can lift it.', roPM)
  else
  begin
    L := Launchers[D.Launcher];
    if A.LvCapKg <= 0 then
      AddF(svBlock, 'LV_REACH', L.Name + ' cannot fly this mission', Why,
        'Choose a different launch vehicle or a different orbit.', roPM)
    else if A.WetKg > A.LvCapKg then
      AddF(svBlock, 'LV_HEAVY', 'Too heavy for ' + L.Name,
        'Fuelled, the spacecraft weighs ' + FmtMass(A.WetKg) + '. ' + L.Name + ' can send ' + FmtMass(A.LvCapKg) + ' to ' + LaunchTargetName(D) + '.',
        'Choose a bigger rocket or a lower-energy route, or shed mass. Every kilogram of equipment you remove also removes the fuel needed to carry it.', roPM)
    else if A.MassMargin < 0.10 then
      AddF(svWarn, 'LV_THIN', 'Launch mass margin only ' + FmtPct(A.MassMargin),
        'Spacecraft almost always get heavier as they are built, often by 10 to 25 %. With this little spare, any growth means cutting something later.',
        'Shed some mass or choose a slightly bigger rocket.', roSpacecraft)
    else if (A.MassMargin > 0.75) and not L.Rideshare then
      AddF(svInfo, 'LV_BIG', 'Rocket is much bigger than needed',
        'You are using ' + FmtPct(1 - A.MassMargin) + ' of what ' + L.Name + ' can lift. A smaller rocket might save money.',
        'Compare the cheaper launchers.', roPM);
    if L.Rideshare then
      AddF(svInfo, 'RIDESHARE', 'Rideshare: you do not pick the date',
        'You fly when the main passenger is ready. If they slip, you wait and pay your team in the meantime.',
        'Accept the risk, or buy a dedicated rocket.', roPM);
  end;

  if (Band.Tier = 0) and not Sc.NearEarth then
    AddF(svBlock, 'UHF_DEEP', 'UHF cannot reach Earth from here',
      'UHF is a short-range band. From this distance the signal would be lost in the noise.',
      'Choose S-band, X-band or better.', roOps);

  if Round(Band.D) > Adcs.Tier then
    AddF(svWarn, 'POINT_COMM', 'Radio beam needs steadier pointing',
      Band.Name + ' squeezes the signal into a very narrow beam. This attitude control cannot hold it on Earth, so three quarters of the signal is lost.',
      'Upgrade attitude control, or use a wider-beam band.', roOps)
  else if (Ant.A >= 0.5) and (Adcs.Tier < 1) and (Band.Tier < 4) then
    AddF(svWarn, 'POINT_DISH', 'Dish antenna needs steadier pointing',
      'A dish only works when it points at Earth. With coarse pointing most of the signal misses.',
      'Fit reaction wheels, or use a patch antenna.', roOps);

  if (Cnt > 0) and (A.GenGbitDay > 0) and (A.DataReturn < 0.8) then
    AddF(svWarn, 'DATA', 'Data bottleneck: only ' + FmtPct(A.DataReturn) + ' gets home',
      'The instruments record ' + FmtData(A.GenGbitDay) + ' a day, but the link carries only ' + FmtData(A.DownGbitDay) +
      ' a day (' + FmtRate(A.RateAvgMbps) + ' for ' + FmtNum(A.ContactHr, 1) + ' hours). The rest is overwritten.',
      'Use a bigger dish, a stronger transmitter, a higher band or more ground time. Or carry fewer data-hungry instruments.', roOps);

  if (Cnt > 0) and (A.StorageDays < 0.5) then
    AddF(svWarn, 'STORAGE', 'Recorder fills in ' + FmtNum(A.StorageDays * 24, 1) + ' hours',
      'The spacecraft can only talk to Earth during contacts. Between them it must store everything it records.',
      'Choose a computer with more storage.', roOps);

  if A.CostTotal > A.CapM then
  begin
    BigName := '';
    Best := 0;
    for I := 0 to High(A.CostLines) do
      if A.CostLines[I].Value > Best then
      begin
        Best := A.CostLines[I].Value;
        BigName := A.CostLines[I].Name;
      end;
    SevCost := svBlock;
    if D.Sandbox then
      SevCost := svInfo;
    AddF(SevCost, 'COST_OVER', 'Over the cost cap by ' + FmtMoney(A.CostTotal - A.CapM),
      'The plan costs ' + FmtMoney(A.CostTotal) + ' against a cap of ' + FmtMoney(A.CapM) + '. The biggest item is ' + BigName +
      ' at ' + FmtMoney(Best) + '. A mission that cannot show it fits the cap is not approved.',
      'Look for the cheapest thing that still meets the objective: fewer instruments, a smaller bus, a cheaper rocket, a shorter mission or less ground time.', roPM);
  end;

  if (D.ReservePct < 15) and not D.Sandbox then
    AddF(svWarn, 'RESERVE_LOW', 'Reserves are only ' + FmtNum(D.ReservePct, 0) + ' %',
      'Something always goes wrong during development. NASA expects about 25 % held back when a mission is confirmed.',
      'Raise the reserves, even if it means flying a little less.', roPM);

  if Late and Sc.ArriveBy then
    AddF(svWarn, 'LATE', 'You will arrive after the flyby',
      'Building takes ' + FmtYears(A.DevYears) + ' and the trip ' + FmtYears(A.CruiseYears) + ', so you arrive in ' + FmtYears(A.ArriveYear) +
      '. The flyby is in ' + FmtYears(Sc.DeadlineYears) + '. You would miss the main event and score ' + FmtPct(Sc.LateFactor) + ' of the science.',
      'Build something simpler, speed up the schedule or take a faster route.', roPM)
  else if Late then
    AddF(svWarn, 'LATE', 'Too slow for the deadline',
      'The spacecraft will be ready to launch in ' + FmtYears(A.LaunchYear) + '. The announcement asks for launch within ' +
      FmtYears(Sc.DeadlineYears) + '. The delay costs about ' + FmtMoney(SlipCost) + ' in salaries while the team waits.',
      'Simplify the design, or pay for an accelerated schedule.', roPM)
  else if (Sc.WindowYears > 0) and (A.LaunchYear - A.DevYears > 0.5) then
    AddF(svInfo, 'WINDOW', 'Waiting ' + FmtYears(A.LaunchYear - A.DevYears) + ' for the launch window',
      'The spacecraft will be ready in ' + FmtYears(A.DevYears) + ', but the planets next line up in ' + FmtYears(A.LaunchYear) + '.',
      'You have time to spare: you could afford a standard schedule or more testing.', roPM);

  if D.LifeYears < Sc.MinLife - 0.001 then
    AddF(svWarn, 'LIFE_MIN', 'Planned mission is shorter than required',
      'The announcement asks for at least ' + FmtYears(Sc.MinLife) + ' of science operations.',
      'Extend the planned mission.', roOps);

  if (Cnt > 0) and (O.Coverage < 0.5) then
    AddF(svWarn, 'COVERAGE', 'This orbit reaches only ' + FmtPct(O.Coverage) + ' of the targets',
      O.Why,
      'Choose an orbit that passes over what you came to study.', roScience);

  if (Cnt > 0) and not HasPrimary then
    AddF(svWarn, 'PRIMARY', 'Nothing on board measures ' + MeasureName[Prim],
      'That is the main objective of this mission. ' + MeasureHint[Prim],
      'Add an instrument that is strong in ' + MeasureName[Prim] + '.', roScience);

  if (Cnt > 0) and (A.SciencePct < Sc.ThresholdPct) then
    AddF(svWarn, 'SCI_LOW', 'Predicted science is below the minimum',
      'This design should return about ' + FmtNum(A.SciencePct, 0) + ' % of the full science goal. Below ' +
      FmtNum(Sc.ThresholdPct, 0) + ' % the mission does not count as a success.',
      'Check the other warnings: science is lost through a poor orbit, missing instruments, too little power, a data bottleneck or a short life.', roScience);

  if (A.Blockers = 0) and (A.SuccessProb < 0.6) then
    AddF(svWarn, 'RISK', 'Only a ' + FmtPct(A.SuccessProb) + ' chance of finishing the mission',
      'Launch ' + FmtPct(A.LaunchSuccess) + ', arrival ' + FmtPct(A.InsertSuccess) + ', and ' + FmtPct(A.YearSurvival) +
      ' survival for each year in space, multiplied together.',
      'A more reliable rocket, more backups (risk class) or better radiation protection all raise the odds.', roPM);

  if (A.Blockers = 0) and (A.Warnings = 0) then
    AddF(svGood, 'CLOSED', 'The design closes',
      'Mass, power, data, money and time all balance with healthy margins. This is what engineers mean by a "closed" design.',
      'Fly it, or keep hunting for more science per dollar.', roPM);

  Result := A;
end;

{ ---- share codes ------------------------------------------------------- }

function EncodeDesign(const D: TDesign): string;
var
  K: TPartKind;
  I: Integer;
  S, Bits: string;
begin
  S := 'T1-' + Scenarios[D.Scenario].Id + '-' + IntToStr(Ord(D.Difficulty)) + '-';
  if D.Sandbox then
    S := S + '1-'
  else
    S := S + '0-';
  S := S + IntToStr(D.Orbit) + '-' + IntToStr(D.Transfer) + '-';
  for K := Low(TPartKind) to High(TPartKind) do
  begin
    if K <> Low(TPartKind) then
      S := S + '.';
    S := S + IntToStr(D.Part[K]);
  end;
  Bits := '';
  for I := 0 to High(Instruments) do
    if (I <= High(D.Instr)) and D.Instr[I] then
      Bits := Bits + '1'
    else
      Bits := Bits + '0';
  S := S + '-' + IntToStr(D.Launcher + 1) + '-' + Bits + '-' +
    IntToStr(Round(D.SolarM2 * 10)) + '-' + IntToStr(D.RtgCount) + '-' +
    IntToStr(Round(D.BatteryWh)) + '-' + IntToStr(Round(D.LifeYears * 100)) + '-' +
    IntToStr(Round(D.ReservePct)) + '-' + IntToStr(D.Seed);
  Result := S;
end;

function SplitStr(const S: string; Sep: Char): TStringArray;
var
  I, Start: Integer;
begin
  SetLength(Result, 0);
  Start := 1;
  for I := 1 to Length(S) do
    if S[I] = Sep then
    begin
      AddStr(Result, Copy(S, Start, I - Start));
      Start := I + 1;
    end;
  AddStr(Result, Copy(S, Start, Length(S) - Start + 1));
end;

function DecodeDesign(const Code: string; var D: TDesign): Boolean;
var
  P, Q: TStringArray;
  K: TPartKind;
  I, SI, V: Integer;
  Sc: TScenario;
begin
  Result := False;
  P := SplitStr(Trim(Code), '-');
  if (Length(P) <> 15) or (P[0] <> 'T1') then
    Exit;
  SI := FindScenario(P[1]);
  if SI < 0 then
    Exit;
  Sc := Scenarios[SI];
  V := StrToIntDef(P[2], 1);
  if (V < 0) or (V > 2) then
    V := 1;
  D := NewDesign(SI, TDifficulty(V), P[3] = '1');
  D.Orbit := StrToIntDef(P[4], 0);
  if (D.Orbit < 0) or (D.Orbit > High(Sc.Orbits)) then
    D.Orbit := 0;
  D.Transfer := StrToIntDef(P[5], 0);
  if (D.Transfer < 0) or (D.Transfer > High(Sc.Transfers)) then
    D.Transfer := 0;
  Q := SplitStr(P[6], '.');
  I := 0;
  for K := Low(TPartKind) to High(TPartKind) do
  begin
    if I <= High(Q) then
    begin
      V := StrToIntDef(Q[I], 0);
      if (V < 0) or (V > High(Parts[K])) then
        V := 0;
      D.Part[K] := V;
    end;
    Inc(I);
  end;
  D.Launcher := StrToIntDef(P[7], 0) - 1;
  if (D.Launcher < -1) or (D.Launcher > High(Launchers)) then
    D.Launcher := -1;
  for I := 0 to High(D.Instr) do
    D.Instr[I] := (I < Length(P[8])) and (P[8][I + 1] = '1');
  D.SolarM2 := Clamp(StrToIntDef(P[9], 20) / 10, 0, 200);
  D.RtgCount := StrToIntDef(P[10], 0);
  if (D.RtgCount < 0) or (D.RtgCount > 5) then
    D.RtgCount := 0;
  D.BatteryWh := Clamp(StrToIntDef(P[11], 300), 0, 20000);
  D.LifeYears := Clamp(StrToIntDef(P[12], 200) / 100, 0.25, 10);
  D.ReservePct := Clamp(StrToIntDef(P[13], 20), 0, 40);
  D.Seed := StrToIntDef(P[14], 12345);
  if D.Seed < 1 then
    D.Seed := 12345;
  Result := True;
end;

end.
