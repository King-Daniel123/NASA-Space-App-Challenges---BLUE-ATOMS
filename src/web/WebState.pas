unit WebState;

{ TradeSpace - the state of the game in the browser: which screen is showing,
  the design being worked on, the crew, and the mission being flown.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$mode objfpc}

interface

uses
  SysUtils, TsTypes, TsSim, TsScore;

type
  TScreen = (scTitle, scSetup, scBrief, scLab, scReview, scMission, scReport, scLog);

const
  TabCount = 7;
  TabName: array[0..TabCount - 1] of string = ('Orbit', 'Payload', 'Spacecraft',
    'Power', 'Comms and data', 'Launch', 'Plan');
  TabIcon: array[0..TabCount - 1] of string = ('orbit', 'flask', 'wrench', 'bolt',
    'dish', 'rocket', 'flag');
  TabRole: array[0..TabCount - 1] of TRole = (roScience, roScience, roSpacecraft,
    roSpacecraft, roOps, roPM, roPM);

var
  Screen: TScreen = scTitle;
  Scen: Integer = 0;
  Difficulty: TDifficulty = dfEngineer;
  Sandbox: Boolean = False;
  Players: Integer = 1;
  PlayerName: array[0..3] of string;
  D: TDesign;
  A, PrevA: TAnalysis;
  HasDesign: Boolean = False;
  HasPrev: Boolean = False;
  LabTab: Integer = 0;
  Votes: array[TRole] of Boolean;
  Sim: TSimState;
  HasSim: Boolean = False;
  Card: TScoreCard;
  HasCard: Boolean = False;
  SharedNote: string = '';

function RoleOwner(R: TRole): Integer;
function RoleOwnerName(R: TRole): string;
function RoleClass(R: TRole): string;
function PlayerRoles(P: Integer): string;
function CrewText: string;
function FindingTab(const Code: string): Integer;
procedure Recalc;
procedure ResetVotes;
function NewSeed: Integer;

implementation

uses
  JS, TsEngine;

function RoleOwner(R: TRole): Integer;
begin
  { Who looks after what, for crews of one to four. }
  Result := 0;
  case Players of
    2:
      if (R = roSpacecraft) or (R = roOps) then
        Result := 1;
    3:
      case R of
        roScience: Result := 0;
        roSpacecraft: Result := 1;
      else
        Result := 2;
      end;
    4:
      case R of
        roPM: Result := 0;
        roScience: Result := 1;
        roSpacecraft: Result := 2;
      else
        Result := 3;
      end;
  end;
end;

function RoleOwnerName(R: TRole): string;
begin
  if Players <= 1 then
    Result := ''
  else
    Result := PlayerName[RoleOwner(R)];
end;

function RoleClass(R: TRole): string;
begin
  case R of
    roPM: Result := 'pm';
    roScience: Result := 'sci';
    roSpacecraft: Result := 'eng';
  else
    Result := 'ops';
  end;
end;

function PlayerRoles(P: Integer): string;
var
  R: TRole;
begin
  Result := '';
  for R := Low(TRole) to High(TRole) do
    if RoleOwner(R) = P then
    begin
      if Result <> '' then
        Result := Result + ' and ';
      Result := Result + RoleName[R];
    end;
end;

function CrewText: string;
var
  I: Integer;
begin
  if Players <= 1 then
  begin
    Result := PlayerName[0];
    if Result = '' then
      Result := 'Solo';
    Exit;
  end;
  Result := '';
  for I := 0 to Players - 1 do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + PlayerName[I];
  end;
end;

function FindingTab(const Code: string): Integer;
begin
  if (Code = 'COVERAGE') or (Code = 'DRAG') then
    Result := 0
  else if (Code = 'NO_INSTR') or (Code = 'INSTR_COUNT') or (Code = 'PAYLOAD_MASS') or (Code = 'INSTR_BUS') or
    (Code = 'PRIMARY') or (Code = 'SCI_LOW') or (Code = 'POINT_INSTR') or (Code = 'COOLING') or (Code = 'RADIO_HGA') then
    Result := 1
  else if (Code = 'DRY_LIMIT') or (Code = 'ADCS_MTQ') or (Code = 'ADCS_DESAT') or (Code = 'THERMAL_COLD') or
    (Code = 'THERMAL_HOT') or (Code = 'RAD') or (Code = 'LIFE_LIMIT') or (Code = 'PROP_NEEDED') or
    (Code = 'PROP_RUNAWAY') or (Code = 'SEP_NA') or (Code = 'DEORBIT') then
    Result := 2
  else if (Code = 'ARRAY_LIMIT') or (Code = 'RTG_NA') or (Code = 'NO_POWER') or (Code = 'POWER_SHORT') or
    (Code = 'POWER_THIN') or (Code = 'POWER_BIG') or (Code = 'BATTERY') or (Code = 'BATTERY_THIN') or (Code = 'SEP_POWER') then
    Result := 3
  else if (Code = 'UHF_DEEP') or (Code = 'POINT_COMM') or (Code = 'POINT_DISH') or (Code = 'DATA') or (Code = 'STORAGE') then
    Result := 4
  else if (Code = 'LV_NONE') or (Code = 'LV_REACH') or (Code = 'LV_HEAVY') or (Code = 'LV_THIN') or
    (Code = 'LV_BIG') or (Code = 'RIDESHARE') then
    Result := 5
  else
    Result := 6;
end;

procedure Recalc;
begin
  if HasDesign then
  begin
    PrevA := A;
    HasPrev := True;
  end;
  A := Analyze(D);
  HasDesign := True;
end;

procedure ResetVotes;
var
  R: TRole;
begin
  for R := Low(TRole) to High(TRole) do
    Votes[R] := False;
end;

function NewSeed: Integer;
begin
  Result := 1 + Trunc(Random * 2000000000);
end;

initialization
  PlayerName[0] := 'Player 1';
  PlayerName[1] := 'Player 2';
  PlayerName[2] := 'Player 3';
  PlayerName[3] := 'Player 4';

end.
