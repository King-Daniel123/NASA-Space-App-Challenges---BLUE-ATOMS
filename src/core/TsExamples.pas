unit TsExamples;

{ TradeSpace - one worked example design for each mission.

  Each example "closes" (the review board approves it) but is deliberately
  modest, so players can load it, see a working design and then beat it.
  They are built by name, not by position, so they keep working when the
  catalogue changes. The core tests check that every example still closes.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$IFDEF PAS2JS}{$mode delphi}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$ENDIF}

interface

uses
  TsTypes;

function ExampleDesign(AScenario: Integer; ADifficulty: TDifficulty; ASandbox: Boolean): TDesign;

implementation

uses
  TsCatalog, TsScenarios, TsEngine;

procedure Pick(var D: TDesign; const Id: string);
var
  I: Integer;
begin
  I := FindInstrument(Id);
  if (I >= 0) and (I <= High(D.Instr)) then
    D.Instr[I] := True;
end;

procedure Use(var D: TDesign; K: TPartKind; const Id: string);
var
  I: Integer;
begin
  I := FindPart(K, Id);
  if I >= 0 then
    D.Part[K] := I;
end;

procedure Orbit(var D: TDesign; const Id: string);
var
  I: Integer;
begin
  for I := 0 to High(Scenarios[D.Scenario].Orbits) do
    if Scenarios[D.Scenario].Orbits[I].Id = Id then
      D.Orbit := I;
end;

procedure Route(var D: TDesign; const Id: string);
var
  I: Integer;
begin
  for I := 0 to High(Scenarios[D.Scenario].Transfers) do
    if Scenarios[D.Scenario].Transfers[I].Id = Id then
      D.Transfer := I;
end;

function ExampleDesign(AScenario: Integer; ADifficulty: TDifficulty; ASandbox: Boolean): TDesign;
var
  D: TDesign;
  Id: string;
begin
  D := NewDesign(AScenario, ADifficulty, ASandbox);
  Id := Scenarios[AScenario].Id;

  if Id = 'earth' then
  begin
    { A small fire-and-storm watcher in a polar orbit, sharing a rocket. }
    Pick(D, 'tir');
    Pick(D, 'radiometer');
    Orbit(D, 'sso');
    Use(D, pkBus, 'small');
    Use(D, pkPropulsion, 'mono');
    Use(D, pkAdcs, 'rw3');
    Use(D, pkComputer, 'radtol');
    Use(D, pkAntenna, 'patch');
    Use(D, pkBand, 'x');
    Use(D, pkTx, 'tx5');
    Use(D, pkGround, 'standard');
    D.SolarM2 := 1.0;
    D.BatteryWh := 250;
    D.LifeYears := 3;
    D.ReservePct := 20;
    D.Launcher := FindLauncher('rideshare');
  end
  else if Id = 'moon' then
  begin
    { A lean ice hunter: two simple instruments, skimming the south pole. }
    Pick(D, 'neutron');
    Pick(D, 'tir');
    Orbit(D, 'frozen');
    Route(D, 'direct');
    Use(D, pkBus, 'small');
    Use(D, pkPropulsion, 'mono');
    Use(D, pkAdcs, 'rw3');
    Use(D, pkComputer, 'radtol');
    Use(D, pkAntenna, 'dish06');
    Use(D, pkBand, 'x');
    Use(D, pkTx, 'tx5');
    Use(D, pkGround, 'basic');
    D.SolarM2 := 1.5;
    D.BatteryWh := 350;
    D.LifeYears := 2;
    D.ReservePct := 20;
    D.Launcher := FindLauncher('rideshare');
  end
  else if Id = 'mars' then
  begin
    { A weather orbiter with a relay radio, aerobraking to save fuel. }
    Pick(D, 'radiometer');
    Pick(D, 'cam_ctx');
    Pick(D, 'tir');
    Pick(D, 'relay');
    Orbit(D, 'low_aero');
    Use(D, pkBus, 'medium');
    Use(D, pkPropulsion, 'biprop');
    Use(D, pkAdcs, 'rw3');
    Use(D, pkThermal, 'passive');
    Use(D, pkComputer, 'radhard');
    Use(D, pkAntenna, 'dish20');
    Use(D, pkBand, 'x');
    Use(D, pkTx, 'tx100');
    Use(D, pkGround, 'standard');
    D.SolarM2 := 10;
    D.BatteryWh := 800;
    D.LifeYears := 2;
    D.ReservePct := 20;
    D.Launcher := FindLauncher('lvm3');
  end
  else if Id = 'apophis' then
  begin
    { A CubeSat with an ion engine: small enough to build in time, efficient
      enough to stop at the asteroid. One instrument only. }
    Pick(D, 'tir');
    Orbit(D, 'rdv');
    Route(D, 'fast');
    Use(D, pkBus, 'cube');
    Use(D, pkPropulsion, 'sep');
    Use(D, pkAdcs, 'rw3');
    Use(D, pkComputer, 'radtol');
    Use(D, pkAntenna, 'dish06');
    Use(D, pkBand, 'x');
    Use(D, pkTx, 'tx20');
    Use(D, pkGround, 'standard');
    Use(D, pkSchedule, 'fast');
    D.SolarM2 := 1.0;
    D.BatteryWh := 140;
    D.LifeYears := 1;
    D.ReservePct := 20;
    D.Launcher := FindLauncher('pslv');
  end
  else
  begin
    { A nuclear-powered probe on the slow road to Jupiter, flying past Europa. }
    Pick(D, 'sar');
    Pick(D, 'mag');
    Pick(D, 'cam_ctx');
    Pick(D, 'tir');
    Orbit(D, 'tour');
    Route(D, 'veega');
    Use(D, pkBus, 'medium');
    Use(D, pkPropulsion, 'biprop');
    Use(D, pkAdcs, 'rw3');
    Use(D, pkThermal, 'active');
    Use(D, pkComputer, 'radhard');
    Use(D, pkShield, 'spot');
    Use(D, pkAntenna, 'dish30');
    Use(D, pkBand, 'x');
    Use(D, pkTx, 'tx100');
    Use(D, pkGround, 'premium');
    D.SolarM2 := 0;
    D.RtgCount := 5;
    D.BatteryWh := 1500;
    D.LifeYears := 3.5;
    D.ReservePct := 20;
    D.Launcher := FindLauncher('falcon9');
  end;
  Result := D;
end;

end.
