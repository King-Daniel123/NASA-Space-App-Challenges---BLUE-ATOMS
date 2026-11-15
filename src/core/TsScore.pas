unit TsScore;

{ Atomic Space - scoring and the post-mission analysis.

  Turns a finished simulation into a score card, explains in plain language
  why the mission did well or badly, finds the real mission it most resembles
  and checks each team role's personal objective.

  Plain Object Pascal: compiles with Delphi, Free Pascal and pas2js.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$IFDEF PAS2JS}{$mode delphi}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$ENDIF}

interface

uses
  TsTypes, TsSim;

type
  TInsight = record
    Tone: TSeverity;
    Title, Text, Tip: string;
  end;
  TInsightArray = array of TInsight;

  TScoreCard = record
    Science, Survival, Budget, Engineering, Efficiency: Double;  // each 0..100
    Total: Integer;                                              // 0..1000
    Stars: Integer;
    Grade, Title, Outcome, OutcomeText: string;
    FinalCostM, CapM, SciencePct, ReturnFrac, PowerAvg: Double;
    YearsFlown, YearsPlanned: Double;
    Insights: TInsightArray;
    Analog: Integer;
    AnalogText: string;
    RoleMet: array[TRole] of Boolean;
    RoleResult: array[TRole] of string;
    RolesMet: Integer;
  end;

const
  ScoreWeightScience = 0.45;
  ScoreWeightSurvival = 0.15;
  ScoreWeightBudget = 0.15;
  ScoreWeightEngineering = 0.15;
  ScoreWeightEfficiency = 0.10;

function ScoreMission(const S: TSimState): TScoreCard;
function GradeOf(Total: Integer): string;
function StarsOf(Total: Integer): Integer;
{ Each team role's personal objective, and whether the design is on course for it. }
function RoleGoalText(R: TRole): string;
function RoleForecast(R: TRole; const A: TAnalysis; const D: TDesign): Boolean;

implementation

uses
  SysUtils, Math, TsCatalog, TsScenarios, TsEngine, TsFmt;

function GradeOf(Total: Integer): string;
begin
  if Total >= 920 then Result := 'S'
  else if Total >= 850 then Result := 'A'
  else if Total >= 740 then Result := 'B'
  else if Total >= 620 then Result := 'C'
  else if Total >= 480 then Result := 'D'
  else Result := 'F';
end;

function StarsOf(Total: Integer): Integer;
begin
  if Total >= 920 then Result := 5
  else if Total >= 850 then Result := 4
  else if Total >= 740 then Result := 3
  else if Total >= 620 then Result := 2
  else if Total >= 480 then Result := 1
  else Result := 0;
end;

function RoleGoalText(R: TRole): string;
begin
  case R of
    roPM: Result := 'Finish within the cost cap and meet the deadline.';
    roScience: Result := 'Return at least 85 % of the science goal.';
    roSpacecraft: Result := 'Launch with at least 10 % mass margin and 20 % power margin, and keep the spacecraft alive.';
  else
    Result := 'Get at least 90 % of the recorded data home.';
  end;
end;

function RoleForecast(R: TRole; const A: TAnalysis; const D: TDesign): Boolean;
begin
  case R of
    roPM: Result := ((A.CostTotal <= A.CapM) or D.Sandbox) and not A.MissedDeadline;
    roScience: Result := A.SciencePct >= 85;
    roSpacecraft: Result := (A.MassMargin >= 0.10) and (A.PowerMargin >= 0.20);
  else
    Result := A.DataReturn >= 0.90;
  end;
end;

procedure AddInsight(var C: TScoreCard; ATone: TSeverity; const ATitle, AText, ATip: string);
var
  N: Integer;
begin
  N := Length(C.Insights);
  SetLength(C.Insights, N + 1);
  C.Insights[N].Tone := ATone;
  C.Insights[N].Title := ATitle;
  C.Insights[N].Text := AText;
  C.Insights[N].Tip := ATip;
end;

function ScoreMission(const S: TSimState): TScoreCard;
var
  C: TScoreCard;
  Sc: TScenario;
  O: TOrbit;
  A: TAnalysis;
  L: TLauncher;
  R: TRole;
  M, Prim: TMeasure;
  I, OrigPlan, BigI: Integer;
  Over, MassG, PowerG, DataG, RelG, Ratio, Best, Dist, BigData, V: Double;
  HasLv: Boolean;
  Nm: string;
begin
  Sc := Scenarios[S.D.Scenario];
  O := Sc.Orbits[S.D.Orbit];
  A := S.A;
  SetLength(C.Insights, 0);
  HasLv := S.D.Launcher >= 0;
  if HasLv then
    L := Launchers[S.D.Launcher];

  C.FinalCostM := SimFinalCost(S);
  C.CapM := A.CapM;
  C.SciencePct := S.SciencePct;
  if S.GenGbit > 0 then
    C.ReturnFrac := Clamp(S.DownGbit / S.GenGbit, 0, 1)
  else
    C.ReturnFrac := A.DataReturn;
  if S.SciWeek > 0 then
    C.PowerAvg := S.PowerSum / S.SciWeek
  else
    C.PowerAvg := 0;
  OrigPlan := Round(S.D.LifeYears * 52);
  if OrigPlan < 1 then
    OrigPlan := 1;
  C.YearsFlown := S.SciWeek / 52;
  C.YearsPlanned := S.D.LifeYears;

  { ---------------- the five scores ---------------- }
  C.Science := Clamp(S.SciencePct, 0, 100);
  if S.LostAtLaunch or S.LostAtArrival then
    C.Survival := 0
  else
    C.Survival := Clamp(S.SciWeek / OrigPlan, 0, 1) * 100;

  Over := (C.FinalCostM - C.CapM) / C.CapM;
  if S.D.Sandbox or (Over <= 0) then
    C.Budget := 100
  else
    C.Budget := Clamp(100 - Over * 400, 0, 100);

  if A.MassMargin >= 0.2 then MassG := 100
  else if A.MassMargin >= 0.1 then MassG := 80
  else if A.MassMargin >= 0 then MassG := 50
  else MassG := 0;
  if A.PowerMargin >= 0.3 then PowerG := 100
  else if A.PowerMargin >= 0.2 then PowerG := 85
  else if A.PowerMargin >= 0 then PowerG := 55
  else PowerG := 0;
  DataG := C.ReturnFrac * 100;
  RelG := Clamp(A.SuccessProb, 0, 1) * 100;
  C.Engineering := (MassG + PowerG + DataG + RelG) / 4;

  Ratio := (S.SciencePct / 100) / MaxD(0.05, C.FinalCostM / C.CapM);
  C.Efficiency := Clamp(70 * Ratio, 0, 100);

  C.Total := Round(10 * (ScoreWeightScience * C.Science + ScoreWeightSurvival * C.Survival +
    ScoreWeightBudget * C.Budget + ScoreWeightEngineering * C.Engineering +
    ScoreWeightEfficiency * C.Efficiency));
  { A mission that misses its minimum science cannot rate better than a D,
    however tidy the engineering was. }
  if (S.SciencePct < Sc.ThresholdPct) and (C.Total > 619) then
    C.Total := 619;
  C.Grade := GradeOf(C.Total);
  C.Stars := StarsOf(C.Total);
  case C.Stars of
    5: C.Title := 'Flagship-class triumph';
    4: C.Title := 'Outstanding mission';
    3: C.Title := 'Solid success';
    2: C.Title := 'Partial success';
    1: C.Title := 'Hard lessons';
  else
    C.Title := 'Back to the drawing board';
  end;

  if S.LostAtLaunch then
  begin
    C.Outcome := 'Lost at launch';
    C.OutcomeText := 'The rocket failed and the spacecraft never reached space.';
  end
  else if S.LostAtArrival then
  begin
    C.Outcome := 'Lost on arrival';
    C.OutcomeText := 'The spacecraft crossed the gap but could not enter its science orbit.';
  end
  else if S.SciencePct >= 100 then
  begin
    C.Outcome := 'Full mission success';
    C.OutcomeText := 'The baseline science goal was met in full: ' + FmtNum(S.SciencePct, 0) + ' %.';
  end
  else if S.SciencePct >= Sc.ThresholdPct then
  begin
    C.Outcome := 'Mission success';
    C.OutcomeText := 'The mission passed its minimum (threshold) science of ' + FmtNum(Sc.ThresholdPct, 0) +
      ' % and returned ' + FmtNum(S.SciencePct, 0) + ' % of the full goal.';
  end
  else if not S.Alive then
  begin
    C.Outcome := 'Mission cut short';
    C.OutcomeText := S.EndReason + ' after ' + FmtYears(C.YearsFlown) + ', with ' + FmtNum(S.SciencePct, 0) +
      ' % of the science goal. The minimum for success was ' + FmtNum(Sc.ThresholdPct, 0) + ' %.';
  end
  else
  begin
    C.Outcome := 'Below minimum science';
    C.OutcomeText := 'The spacecraft worked, but returned only ' + FmtNum(S.SciencePct, 0) +
      ' % of the science goal. The minimum for success was ' + FmtNum(Sc.ThresholdPct, 0) + ' %.';
  end;

  { ---------------- why it went the way it did ---------------- }
  if S.LostAtLaunch and HasLv then
    AddInsight(C, svBlock, 'The rocket failed',
      L.Name + ' succeeds about ' + FmtPct(L.Reliability) + ' of the time, so this was a ' + FmtPct(1 - L.Reliability) +
      ' roll of the dice. It was bad luck, but it was also a risk you chose.',
      'Compare the reliability of each launcher with its price. For an irreplaceable spacecraft, a proven rocket is cheap insurance.');

  if S.LostAtArrival then
    AddInsight(C, svBlock, 'The arrival burn was the mission',
      'Everything depends on one long engine burn at the far end. Yours had a ' + FmtPct(A.InsertSuccess) +
      ' chance of working with ' + FmtDv(A.DvInsert) + ' needed and ' + FmtDv(S.DvStart) + ' in the tanks at launch.',
      'Keep at least 10 % launch mass margin so the propellant is never drained, and consider a route or orbit that needs a smaller burn.');

  if (not S.LostAtLaunch) and (not S.LostAtArrival) then
  begin
    { data }
    if (S.GenGbit > 0) and (C.ReturnFrac < 0.85) then
    begin
      BigI := -1;
      BigData := 0;
      for I := 0 to High(Instruments) do
        if (I <= High(S.D.Instr)) and S.D.Instr[I] and InstrumentOffered(S.D.Scenario, I) then
        begin
          V := Instruments[I].DataMbps * Instruments[I].Duty;
          if V > BigData then
          begin
            BigData := V;
            BigI := I;
          end;
        end;
      Nm := 'Your instruments';
      if BigI >= 0 then
        Nm := 'The ' + Instruments[BigI].Name + ' alone';
      AddInsight(C, svWarn, 'Only ' + FmtPct(C.ReturnFrac) + ' of the data came home',
        'The instruments recorded ' + FmtData(S.GenGbit) + ' but the radio link could carry just ' + FmtData(S.DownGbit) +
        '. ' + FmtData(S.LostGbit) + ' was overwritten before it could be sent. ' + Nm +
        ' produced the most data. From ' + Sc.Body + ' the average rate was ' + FmtRate(A.RateAvgMbps) + '.',
        'Data rate grows with dish area, transmitter power, band and ground-station size, and falls with the square of distance. ' +
        'Upgrade the link, or fly fewer data-hungry instruments.');
    end
    else if S.GenGbit > 0 then
      AddInsight(C, svGood, 'Every bit came home',
        'The link kept up with the instruments: ' + FmtData(S.DownGbit) + ' returned, ' + FmtPct(C.ReturnFrac) + ' of what was recorded.', '');

    { power }
    if (S.SciWeek > 4) and (C.PowerAvg < 0.95) then
      AddInsight(C, svWarn, 'Short of power ' + FmtPct(1 - C.PowerAvg) + ' of the time',
        'You launched with a power margin of ' + FmtPct(A.PowerMargin) + '. Solar panels fade every year' +
        ' and by the end the spacecraft could not run everything at once, so instruments took turns.',
        'Start with about 30 % power margin. It looks like waste on day one and like wisdom in year three.')
    else if A.PowerMargin > 1.5 then
      AddInsight(C, svInfo, 'More power than you could use',
        'The power system made ' + FmtPower(A.GenAvgW) + ' against a need of ' + FmtPower(A.LoadAvgW) +
        '. That spare array cost mass and money.',
        'Trim the array to about 30 % margin and spend the saving on science.');

    { lifetime }
    if (not S.Alive) and (S.SciWeek < OrigPlan) then
      AddInsight(C, svWarn, 'Ended early: ' + S.EndReason,
        'The spacecraft flew ' + FmtYears(C.YearsFlown) + ' of a planned ' + FmtYears(C.YearsPlanned) + '.',
        'Look at what ended it. Radiation needs hardened parts and shielding, drag and station-keeping need propellant, and random failures need backups.');

    { orbit coverage and instruments }
    Prim := PrimaryMeasure(Sc);
    if O.Coverage < 0.5 then
      AddInsight(C, svWarn, 'The orbit missed most of the targets',
        '"' + O.Name + '" reaches only ' + FmtPct(O.Coverage) + ' of what this mission came to study. ' + O.Why,
        'Choose the orbit for the science first, then build the spacecraft to reach it.');
    if A.Capability[Prim] < 35 then
      AddInsight(C, svWarn, 'Weak on the main objective',
        'This mission is mostly about ' + MeasureName[Prim] + ', and your payload scored only ' +
        FmtNum(A.Capability[Prim], 0) + ' out of 100 for it from this orbit.',
        'Pick the instrument that is strongest in ' + MeasureName[Prim] + ' and an orbit where it works well.');
    if S.InstrLost > 0 then
      AddInsight(C, svInfo, Plural(S.InstrLost, 'instrument was', 'instruments were') + ' lost along the way',
        'Failures, storms or late mass cuts removed part of your payload. Science already gathered was kept.',
        'A higher risk class, radiation protection and healthy mass margin all make this less likely.');

    { science saturation }
    Best := 0;
    for M := Low(TMeasure) to High(TMeasure) do
      if S.Completion[M] > Best then
        Best := S.Completion[M];
    if (Best > 0.93) and (S.SciencePct < 90) then
      AddInsight(C, svInfo, 'The survey was finished, but the payload was thin',
        'You flew long enough to complete ' + FmtPct(Best) + ' of what your instruments could ever do. More time would not have helped: ' +
        'the limit was what was on board and where it could see.',
        'A richer payload or a better orbit would raise the ceiling. A shorter mission would have saved operations money.')
    else if (Best < 0.6) and S.Alive then
      AddInsight(C, svInfo, 'Still plenty left to discover',
        'By the end the instruments had completed only ' + FmtPct(Best) + ' of their survey.',
        'A longer mission, more power or a better data link would have let them finish.');
  end;

  { money }
  if (not S.D.Sandbox) and (C.FinalCostM > C.CapM) then
    AddInsight(C, svWarn, 'Over budget by ' + FmtMoney(C.FinalCostM - C.CapM),
      'The mission cost ' + FmtMoney(C.FinalCostM) + ' against a cap of ' + FmtMoney(C.CapM) + '. Surprises during the mission cost ' +
      FmtMoney(S.EventCostM) + ' and you had set aside ' + FmtMoney(A.CostReserve) + ' for them.',
      'Hold about 25 % in reserve and leave room under the cap for it.')
  else if S.EventCostM > A.CostReserve + 0.01 then
    AddInsight(C, svInfo, 'Reserves ran out',
      'Surprises cost ' + FmtMoney(S.EventCostM) + ' and only ' + FmtMoney(A.CostReserve) + ' had been set aside. Slack under the cap saved you.',
      'Next time plan the reserve in, do not rely on luck.')
  else if not S.LostAtLaunch then
    AddInsight(C, svGood, 'Finished ' + FmtMoney(C.CapM - C.FinalCostM) + ' under the cap',
      'Final cost ' + FmtMoney(C.FinalCostM) + '. Surprises cost ' + FmtMoney(S.EventCostM) + ' and your ' + FmtMoney(A.CostReserve) +
      ' reserve covered them.', '');

  if HasLv and (A.MassMargin > 0.75) and not L.Rideshare then
    AddInsight(C, svInfo, 'You bought more rocket than you needed',
      'The spacecraft used ' + FmtPct(1 - A.MassMargin) + ' of what ' + L.Name + ' can lift, for ' + FmtMoney(A.CostLaunch) + '.',
      'A smaller launcher or a shared ride could free up money for instruments.')
  else if HasLv and (A.MassMargin < 0.1) and (A.MassMargin >= 0) then
    AddInsight(C, svInfo, 'You launched with almost no mass margin',
      'Only ' + FmtPct(A.MassMargin) + ' spare, and the spacecraft then grew by ' + FmtMass(S.GrowthKg) + ' during development.',
      'Mass growth of 10 to 25 % is normal. Plan for it.');

  if S.StormsRidden > 0 then
    AddInsight(C, svGood, 'Rode out ' + Plural(S.StormsRidden, 'real solar storm', 'real solar storms'),
      'Particle storms recorded in NASA''s DONKI database swept over the spacecraft. Its radiation protection held every time, ' +
      'at the price of a little solar panel output.', '');
  if S.DragStorms > 0 then
    AddInsight(C, svInfo, Plural(S.DragStorms, 'real geomagnetic storm', 'real geomagnetic storms') + ' raised the drag',
      'Each storm in NASA''s DONKI record swelled Earth''s upper atmosphere and slowed your low-flying satellite a little, ' +
      'costing propellant or orbit lifetime.',
      'A higher orbit feels less drag. Propulsion lets you make up for it.');

  if S.ExtendedWeeks > 0 then
    AddInsight(C, svGood, 'The extended mission paid off',
      'Flying on for another ' + FmtYears(S.ExtendedWeeks / 52) + ' cost only the operations budget, because the spacecraft was already built and already there.', '');

  { ---------------- closest real mission ---------------- }
  C.Analog := -1;
  C.AnalogText := '';
  Best := 1.0e9;
  for I := 0 to High(Sc.Analogs) do
    if (Sc.Analogs[I].MassKg > 0) and (Sc.Analogs[I].CostM > 0) then
    begin
      Dist := Abs(Ln(MaxD(1, S.DryKg + S.PropKg) / Sc.Analogs[I].MassKg)) +
        Abs(Ln(MaxD(1, C.FinalCostM) / Sc.Analogs[I].CostM));
      if Dist < Best then
      begin
        Best := Dist;
        C.Analog := I;
      end;
    end;
  if C.Analog >= 0 then
    C.AnalogText := 'Your ' + FmtMass(S.DryKg + S.PropKg) + ', ' + FmtMoney(C.FinalCostM) + ' spacecraft with ' +
      Plural(A.InstrumentCount, 'instrument', 'instruments') + ' is closest in scale to ' + Sc.Analogs[C.Analog].Name +
      ' (' + Sc.Analogs[C.Analog].Agency + ', ' + Sc.Analogs[C.Analog].Year + '): ' + FmtMass(Sc.Analogs[C.Analog].MassKg) +
      ', about ' + FmtMoney(Sc.Analogs[C.Analog].CostM) + '.';

  { ---------------- team role objectives ---------------- }
  C.RoleMet[roPM] := ((C.FinalCostM <= C.CapM) or S.D.Sandbox) and not S.Late;
  if C.RoleMet[roPM] then
    C.RoleResult[roPM] := 'On budget (' + FmtMoney(C.FinalCostM) + ') and on time.'
  else if S.Late then
    C.RoleResult[roPM] := 'The deadline was missed.'
  else
    C.RoleResult[roPM] := 'Over the cap by ' + FmtMoney(C.FinalCostM - C.CapM) + '.';

  C.RoleMet[roScience] := S.SciencePct >= 85;
  C.RoleResult[roScience] := FmtNum(S.SciencePct, 0) + ' % of the science goal.';

  C.RoleMet[roSpacecraft] := (A.MassMargin >= 0.10) and (A.PowerMargin >= 0.20) and
    not (S.LostAtArrival or ((not S.Alive) and (not S.LostAtLaunch) and (S.SciWeek < OrigPlan)));
  C.RoleResult[roSpacecraft] := 'Mass margin ' + FmtPct(A.MassMargin) + ', power margin ' + FmtPct(A.PowerMargin);
  if S.LostAtArrival or ((not S.Alive) and (not S.LostAtLaunch) and (S.SciWeek < OrigPlan)) then
    C.RoleResult[roSpacecraft] := C.RoleResult[roSpacecraft] + ', but the spacecraft was lost early.'
  else
    C.RoleResult[roSpacecraft] := C.RoleResult[roSpacecraft] + '.';

  C.RoleMet[roOps] := (C.ReturnFrac >= 0.90) and not (S.LostAtLaunch or S.LostAtArrival);
  C.RoleResult[roOps] := FmtPct(C.ReturnFrac) + ' of the recorded data returned.';
  if S.LostAtLaunch or S.LostAtArrival then
    C.RoleResult[roOps] := 'No science operations took place.';

  C.RolesMet := 0;
  for R := Low(TRole) to High(TRole) do
    if C.RoleMet[R] then
      Inc(C.RolesMet);

  Result := C;
end;

end.
