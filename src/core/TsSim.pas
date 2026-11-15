unit TsSim;

{ Atomic Space - the mission simulation.

  Takes a reviewed design and flies it: development surprises, launch, cruise,
  arrival, then science operations one week at a time. Power fades, the data
  link changes with distance, hardware fails at the rate the design earned,
  and real space-weather events from NASA DONKI arrive on their real dates.
  Now and then the simulation stops and asks the team to decide something.

  The simulation is deterministic for a given seed, so two teams flying the
  same shared design face the same surprises.

  Plain Object Pascal: compiles with Delphi, Free Pascal and pas2js.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$IFDEF PAS2JS}{$mode delphi}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$ENDIF}

interface

uses
  TsTypes;

const
  dkOverweight = 1;
  dkSupplier = 2;
  dkTestFail = 3;
  dkBudgetCut = 4;
  dkPartner = 5;
  dkStorm = 6;
  dkWheel = 7;
  dkStation = 8;
  dkDiscovery = 9;
  dkExtend = 10;
  dkEclipse = 11;
  dkMax = 11;

type
  TSimPhase = (spDevelopment, spLaunch, spCruise, spArrival, spScience, spDone);
  TEventTone = (tnInfo, tnGood, tnWarn, tnBad, tnReal);

  TSimChoice = record
    Text, Hint: string;
  end;

  TSimEvent = record
    Week: Integer;
    Phase: TSimPhase;
    Tone: TEventTone;
    Title, Text, Source, Lesson: string;
    Decision, Outcome: string;   // filled in once a decision has been taken
    Owner: TRole;
    IsDecision: Boolean;
    Kind, Chosen: Integer;
    Choices: array of TSimChoice;
  end;
  TSimEventArray = array of TSimEvent;

  TSimState = record
    D: TDesign;
    A: TAnalysis;                // the design as reviewed
    Phase: TSimPhase;
    Week: Integer;               // weeks since launch
    SciWeek: Integer;            // weeks of science operations flown
    PlanWeeks: Integer;          // science weeks planned (grows if extended)
    CruiseWeeks: Integer;
    Rng: Double;
    Alive: Boolean;
    LostAtLaunch, LostAtArrival: Boolean;
    EndReason: string;
    { money and time }
    EventCostM, OpsCostM: Double;
    DelayYears, LaunchYear: Double;
    Late: Boolean;
    { the spacecraft as it really turned out }
    GrowthKg, DryKg, PropKg: Double;
    DvLeft, DvStart: Double;
    SciQuality, RateFactor, SolarLoss, FailMult: Double;
    PointTier: Integer;
    InstrAlive: TBoolArray;
    Cap: TMeasureValues;
    { temporary conditions, in weeks }
    SafeWeeks, HalfLinkWeeks, BlackoutWeeks, SlowWeeks, DustWeeks: Integer;
    { wear }
    Dose, DoseLimit, DragLimitYears: Double;
    BatteryAged: Boolean;
    StorageGbit: Double;
    PhaseDays: Double;
    { science }
    Completion, Realized: TMeasureValues;
    BonusPct, SciencePct: Double;
    { totals for the report }
    GenGbit, DownGbit, LostGbit: Double;
    PowerSum: Double;
    SafeTotal, Anomalies, EventsSeen, ExtendedWeeks: Integer;
    InstrLost: Integer;
    StormsRidden: Integer;       // real particle storms the protected electronics shrugged off
    DragStorms, FlareHits: Integer; // real geomagnetic storms and flares that touched the mission
    { one sample per science week, for the charts }
    HistScience, HistPower, HistData, HistStore, HistDv: TDoubleArray;
    Log: TSimEventArray;
    HasPending: Boolean;
    Pending: TSimEvent;
    Used: array[0..dkMax] of Boolean;
    DecWeek: array[0..dkMax] of Integer;
    DevLeft: Integer;
    DevDone: Boolean;
    EarthIdx: Integer;
    ConjCycle: Integer;          // week of the last solar conjunction
    DustDone, FlybyDone, HalfDone: Boolean;
  end;

const
  PhaseName: array[TSimPhase] of string = ('Development', 'Launch', 'Cruise',
    'Arrival', 'Science operations', 'Mission complete');

procedure SimStart(var S: TSimState; const D: TDesign);
{ Advance one step. Does nothing while a decision is waiting. }
procedure SimAdvance(var S: TSimState);
procedure SimChoose(var S: TSimState; Choice: Integer);
function SimDone(const S: TSimState): Boolean;
function SimProgress(const S: TSimState): Double;
{ Run to the end, answering every decision with the same option (for tests). }
procedure SimRunAll(var S: TSimState; Policy: Integer);
function SimFinalCost(const S: TSimState): Double;
function SimMissionYear(const S: TSimState): Double;

implementation

uses
  SysUtils, Math, TsCatalog, TsScenarios, TsEngine, TsFmt;

{ ---- small helpers ----------------------------------------------------- }

function Rnd(var S: TSimState): Double;
var
  Q: TBigInt;
begin
  { Park-Miller generator, done in floating point so it is identical in
    Delphi and in the browser. }
  S.Rng := S.Rng * 16807.0;
  Q := Trunc(S.Rng / 2147483647.0);
  S.Rng := S.Rng - 2147483647.0 * Q;
  if S.Rng < 1 then
    S.Rng := 1;
  Result := S.Rng / 2147483647.0;
end;

procedure LogEvent(var S: TSimState; ATone: TEventTone; const ATitle, AText, ASource,
  ALesson: string; AOwner: TRole);
var
  N: Integer;
begin
  N := Length(S.Log);
  SetLength(S.Log, N + 1);
  S.Log[N].Week := S.Week;
  S.Log[N].Phase := S.Phase;
  S.Log[N].Tone := ATone;
  S.Log[N].Title := ATitle;
  S.Log[N].Text := AText;
  S.Log[N].Source := ASource;
  S.Log[N].Lesson := ALesson;
  S.Log[N].Decision := '';
  S.Log[N].Outcome := '';
  S.Log[N].Owner := AOwner;
  S.Log[N].IsDecision := False;
  S.Log[N].Kind := 0;
  S.Log[N].Chosen := -1;
  SetLength(S.Log[N].Choices, 0);
end;

procedure Ask(var S: TSimState; AKind: Integer; const ATitle, AText, ASource,
  ALesson: string; AOwner: TRole);
begin
  S.Pending.Week := S.Week;
  S.Pending.Phase := S.Phase;
  S.Pending.Tone := tnWarn;
  S.Pending.Title := ATitle;
  S.Pending.Text := AText;
  S.Pending.Source := ASource;
  S.Pending.Lesson := ALesson;
  S.Pending.Decision := '';
  S.Pending.Outcome := '';
  S.Pending.Owner := AOwner;
  S.Pending.IsDecision := True;
  S.Pending.Kind := AKind;
  S.Pending.Chosen := -1;
  SetLength(S.Pending.Choices, 0);
  S.HasPending := True;
  S.Used[AKind] := True;
end;

procedure Opt(var S: TSimState; const AText, AHint: string);
var
  N: Integer;
begin
  N := Length(S.Pending.Choices);
  SetLength(S.Pending.Choices, N + 1);
  S.Pending.Choices[N].Text := AText;
  S.Pending.Choices[N].Hint := AHint;
end;

function AliveCount(const S: TSimState): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(S.InstrAlive) do
    if S.InstrAlive[I] then
      Inc(Result);
end;

function HeaviestAlive(const S: TSimState): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(S.InstrAlive) do
    if S.InstrAlive[I] and ((Result < 0) or (Instruments[I].MassKg > Instruments[Result].MassKg)) then
      Result := I;
end;

function RandomAlive(var S: TSimState): Integer;
var
  I, N, Pick: Integer;
begin
  Result := -1;
  N := AliveCount(S);
  if N = 0 then
    Exit;
  Pick := Trunc(Rnd(S) * N);
  if Pick >= N then
    Pick := N - 1;
  for I := 0 to High(S.InstrAlive) do
    if S.InstrAlive[I] then
    begin
      if Pick = 0 then
      begin
        Result := I;
        Exit;
      end;
      Dec(Pick);
    end;
end;

procedure RecomputeCap(var S: TSimState);
var
  Q: TDoubleArray;
begin
  InstrumentQuality(S.D, S.InstrAlive, S.PointTier, Q);
  S.Cap := MeasureCapability(S.D, Q);
end;

function ScienceNow(const S: TSimState): Double;
var
  Sc: TScenario;
  O: TOrbit;
  M: TMeasure;
  Sum: Double;
begin
  Sc := Scenarios[S.D.Scenario];
  O := Sc.Orbits[S.D.Orbit];
  Sum := 0;
  for M := Low(TMeasure) to High(TMeasure) do
    Sum := Sum + Sc.Weight[M] * S.Realized[M];
  Result := 100 * Sum * O.Coverage / Sc.FullScience;
  if S.Late and Sc.ArriveBy then
    Result := Result * Sc.LateFactor;
  Result := Result + S.BonusPct;
end;

procedure Spend(var S: TSimState; Amount: Double);
begin
  S.EventCostM := S.EventCostM + Amount;
end;

procedure EndMission(var S: TSimState; const AReason: string);
begin
  S.EndReason := AReason;
  S.Phase := spDone;
end;

function SimDone(const S: TSimState): Boolean;
begin
  Result := S.Phase = spDone;
end;

function SimMissionYear(const S: TSimState): Double;
begin
  Result := S.LaunchYear + S.Week / 52;
end;

function SimProgress(const S: TSimState): Double;
var
  Total: Double;
begin
  Total := S.CruiseWeeks + S.PlanWeeks;
  if S.Phase = spDone then
    Result := 1
  else if (S.Phase = spDevelopment) or (S.Phase = spLaunch) or (Total <= 0) then
    Result := 0
  else
    Result := Clamp(S.Week / Total, 0, 1);
end;

function SimFinalCost(const S: TSimState): Double;
begin
  { What was actually spent: building it, launching it, flying it for as long
    as it lasted, plus every surprise. Unspent reserves are handed back. }
  Result := S.A.DevCostM + S.A.CostLaunch + S.A.SlipCostM + S.OpsCostM + S.EventCostM;
end;

{ ---- start ------------------------------------------------------------- }

procedure SimStart(var S: TSimState; const D: TDesign);
var
  Sc: TScenario;
  O: TOrbit;
  I, K: Integer;
  M: TMeasure;
begin
  Sc := Scenarios[D.Scenario];
  O := Sc.Orbits[D.Orbit];
  S.D := D;
  S.A := Analyze(D);
  S.Phase := spDevelopment;
  S.Week := 0;
  S.SciWeek := 0;
  S.PlanWeeks := Round(D.LifeYears * 52);
  if S.PlanWeeks < 4 then
    S.PlanWeeks := 4;
  S.CruiseWeeks := Round(S.A.CruiseYears * 52);
  S.Rng := D.Seed;
  if S.Rng < 1 then
    S.Rng := 12345;
  S.Alive := True;
  S.LostAtLaunch := False;
  S.LostAtArrival := False;
  S.EndReason := '';
  S.EventCostM := 0;
  S.OpsCostM := 0;
  S.DelayYears := 0;
  S.LaunchYear := S.A.LaunchYear;
  S.Late := S.A.MissedDeadline;
  S.GrowthKg := 0;
  S.DryKg := S.A.DryKg;
  S.PropKg := S.A.PropKg;
  S.DvLeft := 0;
  S.DvStart := 0;
  S.SciQuality := 1;
  S.RateFactor := 1;
  S.SolarLoss := 0;
  S.FailMult := 1;
  S.PointTier := S.A.PointingTier;
  SetLength(S.InstrAlive, Length(Instruments));
  for I := 0 to High(Instruments) do
    S.InstrAlive[I] := (I <= High(D.Instr)) and D.Instr[I] and InstrumentOffered(D.Scenario, I);
  RecomputeCap(S);
  S.SafeWeeks := 0;
  S.HalfLinkWeeks := 0;
  S.BlackoutWeeks := 0;
  S.SlowWeeks := 0;
  S.DustWeeks := 0;
  S.Dose := 0;
  S.BatteryAged := False;
  S.StorageGbit := 0;
  for M := Low(TMeasure) to High(TMeasure) do
  begin
    S.Completion[M] := 0;
    S.Realized[M] := 0;
  end;
  S.BonusPct := 0;
  S.SciencePct := 0;
  S.GenGbit := 0;
  S.DownGbit := 0;
  S.LostGbit := 0;
  S.PowerSum := 0;
  S.SafeTotal := 0;
  S.Anomalies := 0;
  S.EventsSeen := 0;
  S.ExtendedWeeks := 0;
  S.InstrLost := 0;
  S.StormsRidden := 0;
  S.DragStorms := 0;
  S.FlareHits := 0;
  SetLength(S.HistScience, 0);
  SetLength(S.HistPower, 0);
  SetLength(S.HistData, 0);
  SetLength(S.HistStore, 0);
  SetLength(S.HistDv, 0);
  SetLength(S.Log, 0);
  S.HasPending := False;
  for K := 0 to dkMax do
  begin
    S.Used[K] := False;
    S.DecWeek[K] := -1;
  end;
  case D.Difficulty of
    dfCadet: S.DevLeft := 1;
    dfChief: S.DevLeft := 3;
  else
    S.DevLeft := 2;
  end;
  S.DevDone := False;
  S.EarthIdx := 0;
  S.ConjCycle := -1000;
  S.DustDone := False;
  S.FlybyDone := False;
  S.HalfDone := False;

  { A little luck in when things wear out. }
  S.DoseLimit := 0.85 + 0.3 * Rnd(S);
  S.DragLimitYears := 0;
  if (O.DragLifeYears > 0) and (Parts[pkPropulsion][D.Part[pkPropulsion]].Tier = 0) then
    S.DragLimitYears := O.DragLifeYears * (0.9 + 0.2 * Rnd(S));
  S.PhaseDays := Rnd(S) * 400;

  { When the operations decisions will come up, as shares of the plan. }
  S.DecWeek[dkStorm] := Round(S.PlanWeeks * (0.12 + 0.10 * Rnd(S)));
  S.DecWeek[dkWheel] := Round(S.PlanWeeks * (0.32 + 0.10 * Rnd(S)));
  S.DecWeek[dkStation] := Round(S.PlanWeeks * (0.50 + 0.08 * Rnd(S)));
  S.DecWeek[dkDiscovery] := Round(S.PlanWeeks * (0.64 + 0.10 * Rnd(S)));
  S.DecWeek[dkEclipse] := Round(S.PlanWeeks * (0.40 + 0.05 * Rnd(S)));
  if D.Difficulty = dfCadet then
  begin
    S.DecWeek[dkWheel] := -1;
    S.DecWeek[dkStation] := -1;
  end;

  LogEvent(S, tnInfo, 'Mission confirmed',
    'The review board has approved the design. Planned cost ' + FmtMoney(S.A.CostTotal) + ' including ' +
    FmtMoney(S.A.CostReserve) + ' of reserves. Development should take ' + FmtYears(S.A.DevYears) + '.',
    '', '', roPM);
end;

{ ---- development ------------------------------------------------------- }

procedure AskDev(var S: TSimState);
var
  Kind, Tries, H, Kg: Integer;
  Dev: Double;
  Part: string;
begin
  Dev := S.A.DevCostM;
  Kind := 0;
  Tries := 0;
  repeat
    Kind := 1 + Trunc(Rnd(S) * 5);
    if Kind > 5 then
      Kind := 5;
    Inc(Tries);
  until (not S.Used[Kind]) or (Tries > 30);
  if S.Used[Kind] then
    Exit;

  case Kind of
    dkOverweight:
      begin
        H := HeaviestAlive(S);
        if H < 0 then
        begin
          S.Used[Kind] := True;
          Exit;
        end;
        Kg := Round(MaxD(1, Instruments[H].MassKg * 0.12));
        Ask(S, Kind, 'An instrument came in overweight',
          'The ' + Instruments[H].Name + ' team has delivered their flight unit. It is ' + IntToStr(Kg) +
          ' kg heavier than promised.',
          '', 'Mass growth is so common that NASA teams hold back 25 to 30 % at the start. ' +
          'Margin is not waste. It is what you spend when reality arrives.', roSpacecraft);
        Opt(S, 'Pay for a lighter redesign', 'Costs ' + FmtMoney(MaxD(0.5, 0.03 * Dev)) + '. No extra mass.');
        Opt(S, 'Accept the extra mass', '+' + IntToStr(2 * Kg) + ' kg with stronger brackets. Eats launch margin and fuel reserve.');
        Opt(S, 'Strip features from the instrument', 'No cost and no mass, but about 7 % less science.');
      end;
    dkSupplier:
      begin
        case Trunc(Rnd(S) * 3) of
          0: Part := 'reaction wheels';
          1: Part := 'flight computer';
        else
          Part := 'star tracker';
        end;
        Ask(S, Kind, 'A key part is late',
          'The supplier of your ' + Part + ' has a production problem. Delivery will be five months late.',
          '', 'Space hardware comes from a handful of specialist suppliers. One late part can hold up a whole spacecraft.', roPM);
        Opt(S, 'Wait for it', 'Five months of delay. If that misses a launch window, you wait for the next one.');
        Opt(S, 'Pay a second supplier to rush one', 'Costs ' + FmtMoney(MaxD(0.5, 0.035 * Dev)) + '. No delay.');
        Opt(S, 'Skip some testing to catch up', 'No cost and no delay, but faults in flight become 30 % more likely.');
      end;
    dkTestFail:
      begin
        Ask(S, Kind, 'Shake test failure',
          'On the vibration table that mimics a rocket launch, a solar panel hinge cracked.',
          '', 'Finding a weakness on the ground is a success. Hubble''s flawed mirror slipped through because ' +
          'one complete end-to-end test was skipped, and fixing it took a Shuttle mission.', roSpacecraft);
        Opt(S, 'Redesign the hinge and test again', 'Costs ' + FmtMoney(MaxD(0.3, 0.025 * Dev)) + ' and two months.');
        Opt(S, 'Reinforce it and move on', 'Costs ' + FmtMoney(MaxD(0.1, 0.006 * Dev)) + '. Faults in flight become 20 % more likely.');
      end;
    dkBudgetCut:
      begin
        Ask(S, Kind, 'This year''s funding is cut',
          'The agency''s budget came in lower than planned. Your project must find ' + FmtMoney(MaxD(0.5, 0.04 * Dev)) + ' this year.',
          '', 'Missions are funded one year at a time. Stretching a project to save money now nearly always costs more in total.', roPM);
        Opt(S, 'Cover it from reserves', 'Costs ' + FmtMoney(MaxD(0.5, 0.04 * Dev)) + '. Nothing else changes.');
        Opt(S, 'Promise a shorter mission', 'Planned science operations shrink by a quarter.');
        Opt(S, 'Slow down and stretch the schedule', 'Six months of delay, and salaries to pay while you wait.');
      end;
  else
    begin
      Ask(S, dkPartner, 'A partner agency offers help',
        'Another space agency offers time on its ground stations in exchange for a share of the data.',
        '', 'Almost every modern mission is international. NISAR is half Indian, Chandrayaan-1 carried NASA ' +
        'instruments and Canada built the laser altimeter on OSIRIS-REx.', roPM);
      Opt(S, 'Accept and share the data', 'A quarter more data-link capacity for the whole mission.');
      Opt(S, 'Decline and keep it simple', 'Nothing changes.');
    end;
  end;
end;

procedure FinishDevelopment(var S: TSimState);
var
  Sc: TScenario;
  Prop: TPart;
  G, Wet, Over, Ready, Launch, Wait: Double;
  H, K: Integer;
  WasLate: Boolean;
begin
  Sc := Scenarios[S.D.Scenario];
  Prop := Parts[pkPropulsion][S.D.Part[pkPropulsion]];

  { 1. Mass growth: it almost always happens. }
  case S.D.Difficulty of
    dfCadet: G := 0.02 + 0.03 * Rnd(S);
    dfChief: G := 0.07 + 0.11 * Rnd(S);
  else
    G := 0.04 + 0.09 * Rnd(S);
  end;
  S.GrowthKg := S.GrowthKg + S.A.DryKg * G;
  S.DryKg := S.A.DryKg + S.GrowthKg;
  { A heavier spacecraft needs more propellant for the same manoeuvres. The
    tanks are topped up, as long as the rocket can still lift the total.
    This is what launch mass margin is for. }
  S.PropKg := S.A.PropKg;
  if S.A.DryKg > 0 then
    S.PropKg := S.A.PropKg * S.DryKg / S.A.DryKg;
  Wet := S.DryKg + S.PropKg;
  if (S.A.LvCapKg > 0) and (Wet > S.A.LvCapKg) then
  begin
    Over := Wet - S.A.LvCapKg;
    if Over > S.PropKg * 0.6 then
    begin
      { Too much to fix by draining fuel: something has to come off. }
      H := HeaviestAlive(S);
      if (H >= 0) and (AliveCount(S) > 1) then
      begin
        S.InstrAlive[H] := False;
        Inc(S.InstrLost);
        S.DryKg := S.DryKg - Instruments[H].MassKg;
        RecomputeCap(S);
        LogEvent(S, tnBad, 'Instrument removed to save mass',
          'The spacecraft grew ' + FmtMass(S.GrowthKg) + ' heavier during development and no longer fits the rocket. ' +
          'The ' + Instruments[H].Name + ' was taken off before launch.',
          '', 'With too little mass margin, growth has to be paid for in science.', roSpacecraft);
      end;
      Wet := S.DryKg + S.PropKg;
      Over := Wet - S.A.LvCapKg;
    end;
    if Over > 0 then
    begin
      if Over > S.PropKg then
        Over := S.PropKg;
      S.PropKg := S.PropKg - Over;
      LogEvent(S, tnWarn, 'Overweight at the launch site',
        'The spacecraft grew ' + FmtMass(S.GrowthKg) + ' heavier during development and went over the rocket''s limit. ' +
        'Engineers drained ' + FmtMass(Over) + ' of propellant to make it fit.',
        '', 'That propellant was your safety margin and part of your mission life.', roSpacecraft);
    end;
  end
  else if S.A.LvCapKg > 0 then
    LogEvent(S, tnInfo, 'Mass grew by ' + FmtMass(S.GrowthKg),
      'As nearly always happens, the spacecraft gained weight while it was built (' + FmtPct(G) +
      '), and needed ' + FmtMass(S.PropKg - S.A.PropKg) + ' more propellant to match. Your launch margin of ' +
      FmtPct(S.A.MassMargin) + ' absorbed both.',
      '', '', roSpacecraft);

  { 2. How much speed change is really in the tanks. }
  S.DvLeft := 0;
  if (Prop.Tier > 0) and (S.PropKg > 0) and (S.DryKg > 0) then
    S.DvLeft := Prop.A * G0 * Ln((S.DryKg + S.PropKg) / S.DryKg);
  S.DvStart := S.DvLeft;

  { 3. Delays, launch windows and deadlines. }
  WasLate := S.Late;
  Ready := S.A.DevYears + S.DelayYears;
  Launch := Ready;
  if Sc.WindowYears > 0 then
  begin
    Launch := Sc.WindowYears;
    K := 0;
    while (Launch < Ready - 0.001) and (K < 20) do
    begin
      Launch := Launch + Sc.WindowPeriod;
      Inc(K);
    end;
  end;
  if Launch < S.A.LaunchYear then
    Launch := S.A.LaunchYear;
  Wait := Launch - S.A.LaunchYear;
  S.LaunchYear := Launch;
  if Wait > 0.01 then
  begin
    Spend(S, Wait * 0.08 * S.A.DevCostM);
    if (Sc.WindowYears > 0) and (Wait > 1) then
      LogEvent(S, tnBad, 'Launch window missed',
        'The delays pushed the spacecraft past its launch window. The planets will not line up again for ' +
        FmtYears(Sc.WindowPeriod) + '. The team is paid to wait: ' + FmtMoney(Wait * 0.08 * S.A.DevCostM) + '.',
        '', 'A small slip can turn into a two-year wait when the destination is another planet.', roPM)
    else
      LogEvent(S, tnWarn, 'Launch delayed by ' + FmtYears(Wait),
        'Keeping the team together while waiting cost ' + FmtMoney(Wait * 0.08 * S.A.DevCostM) + '.', '', '', roPM);
  end;
  if Sc.ArriveBy then
    S.Late := Launch + S.A.CruiseYears > Sc.DeadlineYears + 0.001
  else
    S.Late := Launch > Sc.DeadlineYears + 0.001;
  if S.Late and not WasLate then
    LogEvent(S, tnWarn, 'The deadline has been missed',
      'After the delays, the mission can no longer meet its deadline.', '', '', roPM);

  S.DevDone := True;
  S.Phase := spLaunch;
end;

procedure DevTick(var S: TSimState);
begin
  if S.DevLeft > 0 then
  begin
    Dec(S.DevLeft);
    AskDev(S);
    if S.HasPending then
      Exit;
  end;
  if S.DevLeft <= 0 then
    FinishDevelopment(S);
end;

{ ---- launch, cruise, arrival ------------------------------------------- }

procedure LaunchTick(var S: TSimState);
var
  Sc: TScenario;
  L: TLauncher;
  Name: string;
begin
  Sc := Scenarios[S.D.Scenario];
  Name := 'The rocket';
  if S.D.Launcher >= 0 then
  begin
    L := Launchers[S.D.Launcher];
    Name := L.Name;
    if L.Rideshare and (Rnd(S) < 0.3) then
    begin
      S.LaunchYear := S.LaunchYear + 0.5;
      Spend(S, 0.5 * 0.08 * S.A.DevCostM);
      LogEvent(S, tnWarn, 'Your ride slipped six months',
        'The main passenger on your shared rocket was not ready, so you waited too. Cost: ' +
        FmtMoney(0.5 * 0.08 * S.A.DevCostM) + '.',
        '', 'NASA''s Janus asteroid mission was built and ready, then lost its trajectory when the mission it was sharing a rocket with slipped a year.', roPM);
      if Sc.ArriveBy and (S.LaunchYear + S.A.CruiseYears > Sc.DeadlineYears + 0.001) then
        S.Late := True;
    end;
  end;
  if Rnd(S) < S.A.LaunchSuccess then
  begin
    LogEvent(S, tnGood, 'Liftoff',
      Name + ' delivered the spacecraft to ' + LaunchTargetName(S.D) + '. Launch mass ' +
      FmtMass(S.DryKg + S.PropKg) + '.', '', '', roPM);
    if S.CruiseWeeks > 0 then
      S.Phase := spCruise
    else
      S.Phase := spArrival;
  end
  else
  begin
    S.LostAtLaunch := True;
    S.Alive := False;
    LogEvent(S, tnBad, 'Launch failure',
      Name + ' failed during ascent and the spacecraft was lost. This rocket succeeds about ' +
      FmtPct(S.A.LaunchSuccess) + ' of the time.',
      '', 'Every rocket has a track record. NASA will only fly its most valuable spacecraft on rockets with a long one.', roPM);
    EndMission(S, 'Lost in a launch failure');
  end;
end;

procedure SpaceWeatherTick(var S: TSimState; WeekSpan: Integer; InScience: Boolean);
var
  Sc: TScenario;
  O: TOrbit;
  I, D0, Wk, Cur: Integer;
  W: TSpaceWeather;
  Logged: Boolean;
begin
  if Length(SpaceWeather) = 0 then
    Exit;
  Sc := Scenarios[S.D.Scenario];
  O := Sc.Orbits[S.D.Orbit];
  D0 := DayNumber(SpaceWeather[0].Date);
  Logged := False;
  Cur := S.Week mod 52;
  for I := 0 to High(SpaceWeather) do
  begin
    W := SpaceWeather[I];
    { Replay the real record once per mission year. }
    Wk := (((DayNumber(W.Date) - D0) div 7) mod 52 + 52) mod 52;
    if (Wk < Cur) or (Wk >= Cur + WeekSpan) then
      Continue;
    if W.Kind = 'SEP' then
    begin
      if Sc.NearEarth and (O.RadLevel = 0) then
        Continue;  // tucked under Earth's magnetic shield
      if S.A.RadExposure >= 1 then
      begin
        S.SolarLoss := S.SolarLoss + 0.01;
        if Rnd(S) < 0.45 then
        begin
          if InScience then
            S.SafeWeeks := S.SafeWeeks + 1;
          if not Logged then
            LogEvent(S, tnReal, 'Particle storm upset the computer',
              'A burst of high-energy particles from the Sun scrambled the unprotected flight computer. ' +
              'The spacecraft dropped into safe mode and lost a week.',
              'Real event: ' + WeatherLabel(W) + ' (' + SpaceWeatherSource + ')',
              'Radiation-hardened electronics and shielding exist for exactly this.', roSpacecraft);
          Logged := True;
        end;
      end
      else
      begin
        S.SolarLoss := S.SolarLoss + 0.004;
        Inc(S.StormsRidden);
        { Tell the story once. After that the storms are simply counted. }
        if (not Logged) and (S.StormsRidden = 1) then
        begin
          LogEvent(S, tnReal, 'Rode out a particle storm',
            'A burst of high-energy particles from the Sun swept over the spacecraft. The protected electronics carried on, ' +
            'though the solar panels lost a little output for good.',
            'Real event: ' + WeatherLabel(W) + ' (' + SpaceWeatherSource + ')', '', roSpacecraft);
          Logged := True;
        end;
      end;
    end
    else if (W.Kind = 'GST') and Sc.NearEarth and (O.AltKm < 1000) and (W.Strength >= 0.6) then
    begin
      if S.DvLeft > 2 then
        S.DvLeft := S.DvLeft - 2 * W.Strength
      else if S.DragLimitYears > 0 then
        S.DragLimitYears := S.DragLimitYears - 0.04;
      Inc(S.DragStorms);
      { Tell the story the first time. After that the storms are counted. }
      if (not Logged) and (S.DragStorms = 1) then
      begin
        LogEvent(S, tnReal, 'Geomagnetic storm raised the drag',
          'A storm in Earth''s magnetic field heated the upper atmosphere, which swelled upward. ' +
          'Drag on your low-flying satellite jumped for several days.',
          'Real event: ' + WeatherLabel(W) + ' (' + SpaceWeatherSource + ')',
          'In February 2022 a storm like this brought down 38 newly launched Starlink satellites.', roOps);
        Logged := True;
      end;
    end
    else if (W.Kind = 'FLR') and (W.Strength >= 0.5) and InScience then
    begin
      Inc(S.FlareHits);
      if (not Logged) and (S.FlareHits = 1) then
      begin
        LogEvent(S, tnReal, 'Solar flare disturbed the radio link',
          'An X-class flare bathed Earth''s daylit side in X-rays and garbled a ground-station pass.',
          'Real event: ' + WeatherLabel(W) + ' (' + SpaceWeatherSource + ')', '', roOps);
        Logged := True;
      end;
    end;
  end;
end;

procedure CruiseTick(var S: TSimState);
var
  Step: Integer;
  PFatal: Double;
begin
  Step := 4;
  if S.Week + Step > S.CruiseWeeks then
    Step := S.CruiseWeeks - S.Week;
  if Step < 1 then
    Step := 1;
  SpaceWeatherTick(S, Step, False);
  S.Week := S.Week + Step;
  S.OpsCostM := S.OpsCostM + 0.5 * S.A.OpsPerYearM * Step / 52;

  { With instruments asleep, the cruise is gentler than operations. }
  PFatal := 1 - Exp(-S.A.AnomalyRate * S.FailMult * S.A.FatalShare * 0.5 * Step / 52);
  if (S.D.Difficulty <> dfCadet) and (Rnd(S) < PFatal) then
  begin
    S.Alive := False;
    Inc(S.Anomalies);
    LogEvent(S, tnBad, 'Contact lost during cruise',
      'The spacecraft stopped answering ' + FmtYears(S.Week / 52) + ' after launch and never recovered.',
      '', 'Mars Observer fell silent three days before reaching Mars in 1993. Backups and testing are what you pay for to make this less likely.', roSpacecraft);
    EndMission(S, 'Lost during the cruise');
    Exit;
  end;
  if (not S.HalfDone) and (S.CruiseWeeks >= 16) and (S.Week >= S.CruiseWeeks div 2) then
  begin
    S.HalfDone := True;
    LogEvent(S, tnInfo, 'Halfway there',
      'All systems normal. A radio signal now takes ' + FmtNum(S.A.LightDelayMin * 0.6, 1) +
      ' minutes to reach the spacecraft, so it has to look after itself.', '', '', roOps);
  end;
  if S.Week >= S.CruiseWeeks then
    S.Phase := spArrival;
end;

procedure ArrivalTick(var S: TSimState);
var
  Sc: TScenario;
  O: TOrbit;
begin
  Sc := Scenarios[S.D.Scenario];
  O := Sc.Orbits[S.D.Orbit];
  S.HalfDone := False;
  if S.A.DvInsert > 0 then
  begin
    if S.DvLeft < S.A.DvInsert * 0.98 then
    begin
      S.LostAtArrival := True;
      S.Alive := False;
      LogEvent(S, tnBad, 'Not enough propellant to stop',
        'Braking into "' + O.Name + '" needs ' + FmtDv(S.A.DvInsert) + ', but only ' + FmtDv(S.DvLeft) +
        ' was left in the tanks after the overweight spacecraft was drained to fit its rocket. It sailed past.',
        '', 'This is why mass margin matters: it protects the propellant, and the propellant is the mission.', roSpacecraft);
      EndMission(S, 'Could not enter orbit');
      Exit;
    end;
    if Rnd(S) >= S.A.InsertSuccess then
    begin
      S.LostAtArrival := True;
      S.Alive := False;
      LogEvent(S, tnBad, 'Arrival failed',
        'Something went wrong during the make-or-break arrival manoeuvre and the spacecraft was lost.',
        '', 'Japan''s Akatsuki missed Venus in 2010 when its main engine failed mid-burn. Its team waited five years and got it into orbit on the second try with small thrusters.', roSpacecraft);
      EndMission(S, 'Lost on arrival');
      Exit;
    end;
    S.DvLeft := S.DvLeft - S.A.DvInsert;
    if O.ExtraYears > 0 then
      LogEvent(S, tnGood, 'Captured, then aerobraked into orbit',
        'The engine burn worked, and months of skimming the upper atmosphere shrank the orbit to "' + O.Name + '". ' +
        FmtDv(S.DvLeft) + ' of speed change remains.', '', '', roSpacecraft)
    else
      LogEvent(S, tnGood, 'Arrived: ' + O.Name,
        'The arrival burn worked. ' + FmtDv(S.DvLeft) + ' of speed change remains for staying in orbit.', '', '', roSpacecraft);
  end
  else
    LogEvent(S, tnGood, 'On station: ' + O.Name, 'The spacecraft is checked out and ready for science.', '', '', roOps);
  if Sc.ArriveBy then
  begin
    if S.Late then
      LogEvent(S, tnWarn, 'Arrived after the flyby',
        'Apophis has already passed Earth. The chance to watch Earth''s gravity reshape it has gone, but there is still an asteroid to study.',
        '', '', roPM)
    else
      LogEvent(S, tnGood, 'Arrived before the flyby',
        'The spacecraft is alongside Apophis with time to map it before Earth''s gravity takes hold.', '', '', roPM);
  end;
  S.Phase := spScience;
  S.SciWeek := 0;
end;

{ ---- science operations ------------------------------------------------ }

function EarthDistance(const S: TSimState): Double;
var
  Sc: TScenario;
  O: TOrbit;
  Mid, Amp, Days, FlybyYear: Double;
begin
  Sc := Scenarios[S.D.Scenario];
  O := Sc.Orbits[S.D.Orbit];
  if Sc.NearEarth then
    Result := O.RangeKm / AuKm
  else if Sc.SynodicDays <= 0 then
    Result := Sc.EarthMaxAU
  else
  begin
    Mid := (Sc.EarthMinAU + Sc.EarthMaxAU) / 2;
    Amp := (Sc.EarthMaxAU - Sc.EarthMinAU) / 2;
    Days := S.Week * 7;
    if Sc.ArriveBy then
    begin
      { Apophis is closest to Earth on flyby day. }
      FlybyYear := Sc.DeadlineYears + 0.08 - S.LaunchYear;
      Result := Mid - Amp * Cos(2 * Pi * (Days - FlybyYear * 365.25) / Sc.SynodicDays);
    end
    else
      Result := Mid - Amp * Cos(2 * Pi * (Days + S.PhaseDays) / Sc.SynodicDays);
  end;
end;

procedure Anomaly(var S: TSimState);
var
  R: Double;
  I: Integer;
  Adcs, Comp: TPart;
begin
  Adcs := Parts[pkAdcs][S.D.Part[pkAdcs]];
  Comp := Parts[pkComputer][S.D.Part[pkComputer]];
  Inc(S.Anomalies);
  R := Rnd(S);
  if R < S.A.FatalShare then
  begin
    S.Alive := False;
    LogEvent(S, tnBad, 'Fatal failure',
      'A fault in the power system cut off the spacecraft for good, ' + FmtYears(S.SciWeek / 52) + ' into science operations.',
      '', 'Roughly one fault in five ends a mission. Redundancy, a higher risk class, halves that share.', roSpacecraft);
    EndMission(S, 'Lost to a hardware failure');
  end
  else if R < S.A.FatalShare + 0.36 then
  begin
    I := RandomAlive(S);
    if (I >= 0) and (AliveCount(S) > 1) then
    begin
      S.InstrAlive[I] := False;
      Inc(S.InstrLost);
      RecomputeCap(S);
      LogEvent(S, tnBad, 'Instrument failed: ' + Instruments[I].Name,
        'It stopped responding and could not be revived. Science it had already gathered is safe.',
        '', '', roScience);
    end
    else
    begin
      S.SciQuality := S.SciQuality * 0.7;
      LogEvent(S, tnBad, 'Instrument degraded',
        'A detector fault leaves your instrument working at reduced sensitivity.', '', '', roScience);
    end;
  end
  else if (R < S.A.FatalShare + 0.58) and (S.PointTier >= 1) then
  begin
    if Round(Adcs.B) = 1 then
      LogEvent(S, tnGood, 'Reaction wheel failed, spare took over',
        'One wheel seized. The fourth wheel you paid for took its place and pointing is unaffected.',
        '', 'This is what redundancy buys.', roSpacecraft)
    else
    begin
      S.PointTier := 0;
      S.RateFactor := S.RateFactor * 0.7;
      RecomputeCap(S);
      LogEvent(S, tnBad, 'Reaction wheel failed',
        'With only two wheels left the spacecraft can no longer hold steady. Sharp instruments are blurred and the antenna wanders.',
        '', 'Kepler lost its second wheel in 2013 and could no longer do its original job.', roSpacecraft);
    end;
  end
  else
  begin
    if Comp.Tier >= 2 then
      S.SafeWeeks := S.SafeWeeks + 1
    else
      S.SafeWeeks := S.SafeWeeks + 3;
    LogEvent(S, tnWarn, 'Computer fault: safe mode',
      'The flight computer hit an error and put the spacecraft into safe mode. Controllers are working to bring it back.',
      '', 'Safe mode saves the spacecraft, but every day in it is a day without science.', roOps);
  end;
end;

procedure AskOps(var S: TSimState; Kind: Integer);
var
  Sc: TScenario;
  Src, T, X: string;
  I, N, Ext: Integer;
  W: TSpaceWeather;
begin
  Sc := Scenarios[S.D.Scenario];
  case Kind of
    dkStorm:
      begin
        Src := '';
        T := 'Forecasters report a solar eruption heading your way.';
        N := Length(SpaceWeather);
        if N > 0 then
        begin
          I := Trunc(Rnd(S) * N);
          if I >= N then
            I := N - 1;
          W := SpaceWeather[I];
          T := T + ' It is modelled on a real one: a ' + WeatherLabel(W) + '.';
          Src := 'NASA DONKI space weather database (' + SpaceWeatherSource + ')';
        end;
        Ask(S, Kind, 'Solar storm warning', T, Src,
          'Operators often put spacecraft into safe mode to ride out a storm. During the 2003 Halloween storms a radiation instrument on Mars Odyssey was destroyed.', roOps);
        Opt(S, 'Go to safe mode for a week', 'Lose one week of science. No risk.');
        Opt(S, 'Keep observing', 'A chance of damage, and a chance of rare data.');
      end;
    dkWheel:
      begin
        Ask(S, Kind, 'A reaction wheel is running hot',
          'Telemetry shows rising friction in one of the wheels that point the spacecraft.', '',
          'Kepler lost two of its four wheels. Engineers reinvented the mission as K2, balancing the telescope against the pressure of sunlight.', roSpacecraft);
        Opt(S, 'Rest it: fewer turns for two months', 'About 20 % less science for eight weeks.');
        Opt(S, 'Carry on as normal', 'A 40 % chance that the wheel fails.');
      end;
    dkStation:
      begin
        Ask(S, Kind, 'Ground antenna out of service',
          'The dish you rely on is going offline for six weeks of repairs.', '',
          'In 2020 the only antenna able to command Voyager 2 was switched off for 11 months of upgrades. The ground is part of the mission too.', roOps);
        Opt(S, 'Buy time on another network', 'Costs ' + FmtMoney(MaxD(0.6, 0.012 * S.A.DevCostM)) + '. No data lost.');
        Opt(S, 'Wait it out', 'Half the downlink for six weeks. The recorder must hold the backlog.');
      end;
    dkDiscovery:
      begin
        if Sc.Id = 'earth' then
        begin
          T := 'A volcano has just erupted';
          X := 'A new eruption has started inside your coverage. Catching it early would be valuable to people on the ground.';
        end
        else if Sc.Id = 'moon' then
        begin
          T := 'A surprise in the data';
          X := 'One shadowed crater shows a far stronger hydrogen signal than predicted. It is not on the observing plan.';
        end
        else if Sc.Id = 'mars' then
        begin
          T := 'A fresh impact crater';
          X := 'A new crater has punched through the dust and exposed bright ice. It will fade within months.';
        end
        else if Sc.Id = 'apophis' then
        begin
          T := 'Boulders are moving';
          X := 'Images show boulders shifting on the surface. Nobody has ever watched this happen.';
        end
        else
        begin
          T := 'A possible plume';
          X := 'A faint glow above the edge of Europa could be water vapour venting from the ocean below.';
        end;
        Ask(S, Kind, T, X, '',
          'The best discoveries are rarely in the plan. Good missions keep some fuel, time and data volume in hand for surprises.', roScience);
        Opt(S, 'Re-plan and investigate', 'Two slower weeks and some propellant, for a chance of a major result.');
        Opt(S, 'Stay on the plan', 'Nothing changes.');
      end;
    dkExtend:
      begin
        Ext := S.PlanWeeks div 2;
        if Ext < 13 then
          Ext := 13;
        Ask(S, Kind, 'Extended mission?',
          'The planned mission is complete and the spacecraft is healthy. The science team asks to keep going. ' +
          'So far you have ' + FmtNum(S.SciencePct, 0) + ' % of the science goal and have spent ' + FmtMoney(SimFinalCost(S)) +
          ' of a ' + FmtMoney(S.A.CapM) + ' cap.', '',
          'Extended missions are the best bargain in space science: the spacecraft is already built and already there. Mars Odyssey has worked for over 20 years on a 3-year plan.', roPM);
        Opt(S, 'Extend by ' + FmtYears(Ext / 52), 'Operations cost about ' + FmtMoney(S.A.OpsPerYearM * Ext / 52) + '. More science, with diminishing returns.');
        Opt(S, 'End on schedule', 'Bank the result.');
      end;
  else
    begin
      Ask(S, dkEclipse, 'Lunar eclipse ahead',
        'Next week Earth''s shadow will sweep across the Moon. The spacecraft will be in darkness for about five hours, ' +
        'far longer than a normal orbit night, and your battery cannot carry it that long.', '',
        'Lunar Reconnaissance Orbiter switches off its instruments and warms itself up before every lunar eclipse.', roSpacecraft);
      Opt(S, 'Power down and wait', 'Lose a week of science.');
      Opt(S, 'Stay on and hope', 'An even chance of damaging the battery for good.');
    end;
  end;
end;

procedure ScienceTick(var S: TSimState);
var
  Sc: TScenario;
  O: TOrbit;
  Prop: TPart;
  M: TMeasure;
  Years, Deg, SolarNow, RtgNow, Ecl, GenAvg, PF, Ops: Double;
  GenWeek, Dist, Rate, LinkWeek, Down, Lost, FW, Tau, DC, CapNow, PAnom, Need: Double;
  Ev: TEarthEvent;
  Seen: Boolean;
  K: Integer;
begin
  Sc := Scenarios[S.D.Scenario];
  O := Sc.Orbits[S.D.Orbit];
  Prop := Parts[pkPropulsion][S.D.Part[pkPropulsion]];

  { ---- decisions that are due ---- }
  for K := dkStorm to dkDiscovery do
    if (not S.Used[K]) and (S.DecWeek[K] >= 0) and (S.SciWeek >= S.DecWeek[K]) then
    begin
      if (K = dkWheel) and (S.PointTier < 1) then
      begin
        S.Used[K] := True;
        Continue;
      end;
      AskOps(S, K);
      Exit;
    end;
  if (Sc.Id = 'moon') and (not S.Used[dkEclipse]) and (S.SciWeek >= S.DecWeek[dkEclipse]) and (S.SciWeek >= 20) then
  begin
    Need := MaxD(0, S.A.LoadAvgW - S.A.RtgW) * 5 / 0.8;
    if S.D.BatteryWh >= Need then
    begin
      S.Used[dkEclipse] := True;
      LogEvent(S, tnGood, 'Sailed through a lunar eclipse',
        'Earth''s shadow covered the Moon for five hours. Your ' + FmtNum(S.D.BatteryWh, 0) + ' Wh battery carried the spacecraft through.',
        '', 'Sizing the battery for the worst night, not the usual one, paid off.', roSpacecraft);
    end
    else
    begin
      AskOps(S, dkEclipse);
      Exit;
    end;
  end;

  Years := S.SciWeek / 52;

  { ---- power: panels fade, nuclear batteries decay ---- }
  Deg := 0.025;
  if O.RadLevel >= 2 then
    Deg := 0.06;
  SolarNow := S.A.SolarW * MaxD(0.3, 1 - Deg * (Years + 0.5 * S.A.CruiseYears)) * MaxD(0.2, 1 - S.SolarLoss);
  RtgNow := S.A.RtgW * Power(1 - RtgDecayPerYear, Years + S.A.CruiseYears);
  Ecl := O.EclipseFrac;
  GenAvg := RtgNow + SolarNow * (1 - Ecl) / (1 - Ecl + Ecl / 0.85);
  PF := 1;
  if S.A.LoadAvgW > 0 then
    PF := Clamp(GenAvg / S.A.LoadAvgW, 0, 1);
  if (not S.BatteryAged) and (S.A.BatteryNeedWh > 0) and
    (S.D.BatteryWh * (1 - 0.04 * Years) < S.A.BatteryNeedWh) then
  begin
    S.BatteryAged := True;
    LogEvent(S, tnWarn, 'Battery has aged',
      'After ' + FmtYears(Years) + ' of charging and draining, the battery can no longer run everything through the longest eclipses. ' +
      'Instruments now switch off in the dark.', '', 'Batteries lose capacity with every cycle. Spare capacity on day one is what keeps a mission whole in year three.', roSpacecraft);
  end;
  if S.BatteryAged then
    PF := PF * 0.85;

  { ---- what is switched on this week ---- }
  Ops := 1;
  if S.SafeWeeks > 0 then
  begin
    Ops := 0;
    Dec(S.SafeWeeks);
    Inc(S.SafeTotal);
  end;
  if S.SlowWeeks > 0 then
  begin
    Ops := Ops * 0.8;
    Dec(S.SlowWeeks);
  end;

  { ---- data: record, store, send home ---- }
  GenWeek := DataGenGbitDay(S.D, S.InstrAlive) * 7 * PF * Ops;
  Dist := EarthDistance(S);
  Rate := LinkRateMbps(S.D, Dist, S.PointTier) * S.RateFactor;
  LinkWeek := Rate * S.A.ContactHr * 3600 * 7 / 1000;
  if S.BlackoutWeeks > 0 then
  begin
    LinkWeek := 0;
    Dec(S.BlackoutWeeks);
  end
  else if S.HalfLinkWeeks > 0 then
  begin
    LinkWeek := LinkWeek * 0.5;
    Dec(S.HalfLinkWeeks);
  end;
  S.StorageGbit := S.StorageGbit + GenWeek;
  Down := MinD(S.StorageGbit, LinkWeek);
  S.StorageGbit := S.StorageGbit - Down;
  Lost := 0;
  if S.StorageGbit > S.A.StorageGbit then
  begin
    Lost := S.StorageGbit - S.A.StorageGbit;
    S.StorageGbit := S.A.StorageGbit;
  end;
  S.GenGbit := S.GenGbit + GenWeek;
  S.DownGbit := S.DownGbit + Down;
  S.LostGbit := S.LostGbit + Lost;
  FW := 1;
  if GenWeek > 0 then
    FW := Power(Clamp(Down / GenWeek, 0, 3), 0.7);

  { ---- science gathered this week ---- }
  if Ops > 0 then
    for M := Low(TMeasure) to High(TMeasure) do
    begin
      Tau := Sc.TauYears * O.TauFactor / MaxD(0.03, PF * FW * Ops);
      DC := (1 - S.Completion[M]) * (1 - Exp(-(1 / 52) / Tau));
      S.Completion[M] := S.Completion[M] + DC;
      CapNow := S.Cap[M] * S.SciQuality;
      if (S.DustWeeks > 0) and ((M = mImaging) or (M = mSpectral) or (M = mThermal)) then
        CapNow := CapNow * 0.3;
      S.Realized[M] := S.Realized[M] + CapNow / 100 * DC;
    end;
  if S.DustWeeks > 0 then
    Dec(S.DustWeeks);
  S.SciencePct := ScienceNow(S);
  S.PowerSum := S.PowerSum + PF;

  { ---- propellant for staying in orbit ---- }
  if Prop.Tier > 0 then
    S.DvLeft := S.DvLeft - O.DvPerYear / 52;

  { ---- money ---- }
  S.OpsCostM := S.OpsCostM + S.A.OpsPerYearM / 52;

  { ---- samples for the charts ---- }
  K := Length(S.HistScience);
  SetLength(S.HistScience, K + 1);
  SetLength(S.HistPower, K + 1);
  SetLength(S.HistData, K + 1);
  SetLength(S.HistStore, K + 1);
  SetLength(S.HistDv, K + 1);
  S.HistScience[K] := S.SciencePct;
  S.HistPower[K] := PF * 100;
  if GenWeek > 0 then
    S.HistData[K] := Clamp(Down / GenWeek, 0, 1) * 100
  else
    S.HistData[K] := 100;
  if S.A.StorageGbit > 0 then
    S.HistStore[K] := S.StorageGbit / S.A.StorageGbit * 100
  else
    S.HistStore[K] := 0;
  if S.DvStart > 0 then
    S.HistDv[K] := Clamp(S.DvLeft / S.DvStart, 0, 1) * 100
  else
    S.HistDv[K] := 0;

  Inc(S.SciWeek);
  Inc(S.Week);

  { ---- scenario colour ---- }
  if Sc.UsesEonet and (Length(EarthEvents) > 0) then
  begin
    Ev := EarthEvents[S.EarthIdx mod Length(EarthEvents)];
    Inc(S.EarthIdx);
    Seen := EventVisible(O, Ev.Lat, Ev.Lon) and (Ops > 0);
    if Seen then
    begin
      Seen := False;
      for M := Low(TMeasure) to High(TMeasure) do
        if (CategorySuit(Ev.Category, M) >= 0.5) and (S.Cap[M] > 20) then
          Seen := True;
    end;
    if Seen then
    begin
      Inc(S.EventsSeen);
      if S.EventsSeen mod 7 = 1 then
        LogEvent(S, tnReal, 'Observed: ' + Ev.Title,
          CategoryLabel(Ev.Category) + ' at ' + FmtNum(Abs(Ev.Lat), 1) + ' deg ' + Copy('NS', 1 + Ord(Ev.Lat < 0), 1) +
          ', reported ' + NiceDate(Ev.Date) + '. Your instruments caught it and the data went to responders.',
          'Real event: ' + EarthEventsSource, '', roScience);
    end;
  end;
  if (Sc.Id = 'mars') and (S.Week - S.ConjCycle > 40) and (Dist > Sc.EarthMaxAU * 0.985) then
  begin
    S.ConjCycle := S.Week;
    S.BlackoutWeeks := 2;
    LogEvent(S, tnWarn, 'Solar conjunction',
      'Mars has moved behind the Sun as seen from Earth. For two weeks no reliable signal can get through. ' +
      'Everything recorded has to wait in the ' + FmtData(S.A.StorageGbit) + ' recorder.',
      '', 'This happens every 26 months. Storage is what bridges the gap.', roOps);
  end;
  if (Sc.Id = 'mars') and (not S.DustDone) and (S.SciWeek > 20) and (S.D.Difficulty <> dfCadet) and (Rnd(S) < 0.012) then
  begin
    S.DustDone := True;
    S.DustWeeks := 8;
    if S.Cap[mAtmos] > 20 then
    begin
      S.BonusPct := S.BonusPct + 2;
      LogEvent(S, tnWarn, 'Global dust storm',
        'Dust has wrapped the whole planet. Cameras see almost nothing for two months, but your atmospheric instruments are having the time of their lives.',
        '', 'Mariner 9 arrived in the middle of a storm like this in 1971 and simply waited for it to clear.', roScience);
    end
    else
      LogEvent(S, tnWarn, 'Global dust storm',
        'Dust has wrapped the whole planet. Cameras and spectrometers see almost nothing for two months.',
        '', 'Mariner 9 arrived in the middle of a storm like this in 1971 and simply waited for it to clear.', roScience);
  end;
  if Sc.UsesApophis and (not S.FlybyDone) and (not S.Late) and
    (SimMissionYear(S) >= Sc.DeadlineYears + 0.08) then
  begin
    S.FlybyDone := True;
    LogEvent(S, tnReal, 'Flyby day',
      'Apophis is sweeping past Earth at ' + FmtNum(ApophisVelKmS, 2) + ' km/s, ' + FmtNum(ApophisMissKm, 0) +
      ' km from the centre of the planet. Your spacecraft is alongside, recording Earth''s gravity at work.',
      'Real figures: NASA NeoWs / JPL close-approach data for ' + NiceDate(ApophisDate), '', roScience);
  end;
  if (not S.HalfDone) and (S.SciWeek >= S.PlanWeeks div 2) and (S.PlanWeeks >= 20) then
  begin
    S.HalfDone := True;
    LogEvent(S, tnInfo, 'Halfway through the plan',
      FmtNum(S.SciencePct, 0) + ' % of the science goal so far. ' + FmtData(S.DownGbit) + ' sent home, ' +
      FmtPct(S.PowerSum / S.SciWeek) + ' of the power needed.', '', '', roScience);
  end;

  SpaceWeatherTick(S, 1, True);

  { ---- things that end a mission ---- }
  if S.A.LifeLimitYears < 900 then
    if S.A.LifeLimitWhy = 'radiation damage to the electronics' then
    begin
      S.Dose := S.Dose + (1 / 52) / S.A.LifeLimitYears;
      if S.Dose >= S.DoseLimit then
      begin
        S.Alive := False;
        LogEvent(S, tnBad, 'Radiation finally won',
          'After ' + FmtYears(S.SciWeek / 52) + ' in the radiation belts the electronics have taken all they can. The spacecraft has gone silent.',
          '', 'Every mission to Jupiter is a race between the science and the radiation dose.', roSpacecraft);
        EndMission(S, 'Electronics destroyed by radiation');
        Exit;
      end;
    end;
  if (S.DragLimitYears > 0) and (S.SciWeek / 52 >= S.DragLimitYears) then
  begin
    S.Alive := False;
    LogEvent(S, tnWarn, 'Re-entry',
      'With no engine to fight it, air drag has pulled the satellite down. It burned up after ' + FmtYears(S.SciWeek / 52) + '.',
      '', 'Low orbits clean themselves up, but only propulsion lets you choose when.', roOps);
    EndMission(S, 'Orbit decayed');
    Exit;
  end;
  if (Prop.Tier > 0) and (O.DvPerYear > 0) and (S.DvLeft <= 0) then
  begin
    S.Alive := False;
    LogEvent(S, tnWarn, 'Out of propellant',
      'The tanks are empty after ' + FmtYears(S.SciWeek / 52) + '. Without fuel the orbit can no longer be held and the mission ends.',
      '', 'Propellant is a mission''s lifetime. Every unplanned manoeuvre shortens it.', roSpacecraft);
    EndMission(S, 'Ran out of propellant');
    Exit;
  end;

  { ---- random hardware faults ---- }
  PAnom := 1 - Exp(-S.A.AnomalyRate * S.FailMult / 52);
  if S.D.Difficulty = dfCadet then
    PAnom := PAnom * 0.5;
  if Rnd(S) < PAnom then
  begin
    Anomaly(S);
    if S.Phase = spDone then
      Exit;
  end;

  { ---- end of the plan ---- }
  if S.SciWeek >= S.PlanWeeks then
  begin
    if not S.Used[dkExtend] then
      AskOps(S, dkExtend)
    else
    begin
      LogEvent(S, tnGood, 'Mission complete',
        'Operations ended as planned after ' + FmtYears(S.SciWeek / 52) + ' of science.', '', '', roPM);
      EndMission(S, 'Completed');
    end;
  end;
end;

{ ---- decisions --------------------------------------------------------- }

procedure SimChoose(var S: TSimState; Choice: Integer);
var
  E: TSimEvent;
  Dev, Cost, P: Double;
  N, I, H, Kg, Ext: Integer;
  Adcs: TPart;
begin
  if not S.HasPending then
    Exit;
  E := S.Pending;
  if (Choice < 0) or (Choice > High(E.Choices)) then
    Choice := 0;
  E.Chosen := Choice;
  E.Decision := E.Choices[Choice].Text;
  E.Tone := tnInfo;
  Dev := S.A.DevCostM;
  Adcs := Parts[pkAdcs][S.D.Part[pkAdcs]];

  case E.Kind of
    dkOverweight:
      begin
        H := HeaviestAlive(S);
        Kg := 1;
        if H >= 0 then
          Kg := Round(MaxD(1, Instruments[H].MassKg * 0.12));
        if Choice = 0 then
        begin
          Cost := MaxD(0.5, 0.03 * Dev);
          Spend(S, Cost);
          E.Outcome := 'The redesign cost ' + FmtMoney(Cost) + ' and the mass is back on target.';
        end
        else if Choice = 1 then
        begin
          S.GrowthKg := S.GrowthKg + 2 * Kg;
          E.Outcome := 'The spacecraft is ' + IntToStr(2 * Kg) + ' kg heavier. Your margin will have to absorb it.';
        end
        else
        begin
          S.SciQuality := S.SciQuality * 0.93;
          E.Outcome := 'The instrument flies with fewer modes. Science quality is down about 7 %.';
        end;
      end;
    dkSupplier:
      if Choice = 0 then
      begin
        S.DelayYears := S.DelayYears + 0.4;
        E.Outcome := 'Development is five months longer.';
      end
      else if Choice = 1 then
      begin
        Cost := MaxD(0.5, 0.035 * Dev);
        Spend(S, Cost);
        E.Outcome := 'The rushed part arrived on time for ' + FmtMoney(Cost) + '.';
      end
      else
      begin
        S.FailMult := S.FailMult * 1.3;
        E.Outcome := 'The schedule held, but the spacecraft will fly with less testing behind it.';
      end;
    dkTestFail:
      if Choice = 0 then
      begin
        Cost := MaxD(0.3, 0.025 * Dev);
        Spend(S, Cost);
        S.DelayYears := S.DelayYears + 0.15;
        E.Outcome := 'The new hinge passed the test. Cost ' + FmtMoney(Cost) + ' and two months.';
      end
      else
      begin
        Cost := MaxD(0.1, 0.006 * Dev);
        Spend(S, Cost);
        S.FailMult := S.FailMult * 1.2;
        E.Outcome := 'The patch held on the table. Whether it holds in flight is another matter.';
      end;
    dkBudgetCut:
      if Choice = 0 then
      begin
        Cost := MaxD(0.5, 0.04 * Dev);
        Spend(S, Cost);
        E.Outcome := 'Reserves covered the ' + FmtMoney(Cost) + ' gap.';
      end
      else if Choice = 1 then
      begin
        S.PlanWeeks := Round(S.PlanWeeks * 0.75);
        if S.PlanWeeks < 4 then
          S.PlanWeeks := 4;
        E.Outcome := 'The planned mission is now ' + FmtYears(S.PlanWeeks / 52) + '.';
      end
      else
      begin
        S.DelayYears := S.DelayYears + 0.5;
        E.Outcome := 'Work slows down. Launch readiness slips six months.';
      end;
    dkPartner:
      if Choice = 0 then
      begin
        S.RateFactor := S.RateFactor * 1.25;
        E.Tone := tnGood;
        E.Outcome := 'The partner''s stations will add a quarter more downlink.';
      end
      else
        E.Outcome := 'You keep full control of the data and the ground plan stays as it was.';
    dkStorm:
      if Choice = 0 then
      begin
        S.SafeWeeks := S.SafeWeeks + 1;
        E.Outcome := 'The spacecraft waited out the storm with its instruments off and came back unharmed.';
      end
      else
      begin
        P := 0.12 + 0.2 * S.A.RadExposure;
        if S.D.Difficulty = dfCadet then
          P := P - 0.05
        else if S.D.Difficulty = dfChief then
          P := P + 0.08;
        if Rnd(S) < P then
        begin
          E.Tone := tnBad;
          I := RandomAlive(S);
          if (I >= 0) and (AliveCount(S) > 1) then
          begin
            S.InstrAlive[I] := False;
            Inc(S.InstrLost);
            RecomputeCap(S);
            E.Outcome := 'The storm hit hard. The ' + Instruments[I].Name + ' was damaged beyond recovery.';
          end
          else
          begin
            S.SolarLoss := S.SolarLoss + 0.08;
            E.Outcome := 'The storm hit hard. The solar panels lost 8 % of their output for good.';
          end;
        end
        else
        begin
          E.Tone := tnGood;
          if S.Cap[mFields] > 20 then
          begin
            S.BonusPct := S.BonusPct + 3;
            E.Outcome := 'The spacecraft came through, and your fields and particles instruments recorded the whole storm. A rare data set.';
          end
          else
          begin
            S.BonusPct := S.BonusPct + 1;
            E.Outcome := 'The spacecraft came through unharmed and lost no observing time.';
          end;
        end;
      end;
    dkWheel:
      if Choice = 0 then
      begin
        S.SlowWeeks := S.SlowWeeks + 8;
        E.Outcome := 'The wheel cooled down and recovered. Operations run gently for two months.';
      end
      else if Rnd(S) < 0.4 then
      begin
        if Round(Adcs.B) = 1 then
        begin
          E.Tone := tnGood;
          E.Outcome := 'The wheel seized, but the spare you paid for took over. Pointing is unaffected.';
        end
        else
        begin
          E.Tone := tnBad;
          S.PointTier := 0;
          S.RateFactor := S.RateFactor * 0.7;
          RecomputeCap(S);
          E.Outcome := 'The wheel seized. With two wheels left the spacecraft can no longer hold steady.';
        end;
      end
      else
      begin
        E.Tone := tnGood;
        E.Outcome := 'The friction settled by itself. No science was lost.';
      end;
    dkStation:
      if Choice = 0 then
      begin
        Cost := MaxD(0.6, 0.012 * Dev);
        Spend(S, Cost);
        E.Outcome := 'Another network filled in for ' + FmtMoney(Cost) + '.';
      end
      else
      begin
        S.HalfLinkWeeks := S.HalfLinkWeeks + 6;
        E.Outcome := 'Six weeks at half the downlink. The recorder has to hold the backlog.';
      end;
    dkDiscovery:
      if Choice = 0 then
      begin
        S.SlowWeeks := S.SlowWeeks + 2;
        if S.DvLeft > 0 then
          S.DvLeft := S.DvLeft * 0.97;
        if Rnd(S) < 0.75 then
        begin
          P := 4 + 4 * Rnd(S);
          S.BonusPct := S.BonusPct + P;
          E.Tone := tnGood;
          E.Outcome := 'It was real. The follow-up observations are a highlight of the mission (+' + FmtNum(P, 0) + ' science points).';
        end
        else
          E.Outcome := 'The follow-up found nothing unusual. Two weeks and a little propellant spent on a false alarm.';
      end
      else
        E.Outcome := 'The plan carries on unchanged. Someone else may follow it up one day.';
    dkExtend:
      if Choice = 0 then
      begin
        Ext := S.PlanWeeks div 2;
        if Ext < 13 then
          Ext := 13;
        S.PlanWeeks := S.PlanWeeks + Ext;
        S.ExtendedWeeks := Ext;
        E.Tone := tnGood;
        E.Outcome := 'The mission is extended by ' + FmtYears(Ext / 52) + '.';
      end
      else
        E.Outcome := 'The mission ends on schedule.';
    dkEclipse:
      if Choice = 0 then
      begin
        S.SafeWeeks := S.SafeWeeks + 1;
        E.Outcome := 'Everything non-essential was switched off. The spacecraft woke up cold but healthy.';
      end
      else if Rnd(S) < 0.5 then
      begin
        E.Tone := tnBad;
        S.SolarLoss := S.SolarLoss + 0.15;
        E.Outcome := 'The battery ran flat and was damaged. The power system has lost about 15 % for good.';
      end
      else
      begin
        E.Tone := tnGood;
        E.Outcome := 'The battery just held. No science was lost.';
      end;
  end;

  N := Length(S.Log);
  SetLength(S.Log, N + 1);
  S.Log[N] := E;
  S.HasPending := False;

  if (E.Kind = dkExtend) and (Choice <> 0) then
  begin
    LogEvent(S, tnGood, 'Mission complete',
      'Operations ended as planned after ' + FmtYears(S.SciWeek / 52) + ' of science.', '', '', roPM);
    EndMission(S, 'Completed');
  end;
end;

{ ---- driver ------------------------------------------------------------ }

procedure SimAdvance(var S: TSimState);
begin
  if S.HasPending or (S.Phase = spDone) then
    Exit;
  case S.Phase of
    spDevelopment: DevTick(S);
    spLaunch: LaunchTick(S);
    spCruise: CruiseTick(S);
    spArrival: ArrivalTick(S);
    spScience: ScienceTick(S);
  end;
end;

procedure SimRunAll(var S: TSimState; Policy: Integer);
var
  Guard, C: Integer;
begin
  Guard := 0;
  while (S.Phase <> spDone) and (Guard < 5000) do
  begin
    Inc(Guard);
    if S.HasPending then
    begin
      C := Policy;
      if C > High(S.Pending.Choices) then
        C := High(S.Pending.Choices);
      SimChoose(S, C);
    end
    else
      SimAdvance(S);
  end;
end;

end.
