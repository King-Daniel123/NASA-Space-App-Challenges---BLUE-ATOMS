unit WebViews;

{ Atomic Space - the screens of the game, built as HTML text in Object Pascal.

  Each function returns the markup for one screen or one part of a screen.
  WebApp puts it on the page and reacts to clicks (every button carries a
  data-act attribute naming what it does).

  AI-assistance note: written with the help of Claude (Anthropic). }

{$mode objfpc}

interface

uses
  SysUtils, Math, TsTypes;

function ViewTitle: string;
function ViewSetup: string;
function ViewBrief: string;
function ViewLab: string;
function ViewLabNav: string;
function ViewLabMain: string;
function ViewLabDash: string;
function PowerInfo: string;
function PlanInfo: string;
function ViewReview: string;
function ViewMission: string;
function ViewMissionSide: string;
function ViewMissionControls(Running, Done, InLaunch: Boolean; Speed: Integer): string;
function LogItemHtml(Idx: Integer): string;
function ViewReport: string;
function ViewLog: string;
function ModalHelp: string;
function ModalGlossary: string;
function ModalAbout: string;
function ModalBreakdown(const Which: string): string;
function ModalDecision: string;
function ModalOutcome(Idx: Integer): string;
function ModalShare(const Url: string): string;

implementation

uses
  StrUtils, WebUtil, WebState, WebStore, WebNasa, WebDraw, TsFmt, TsCatalog, TsScenarios, TsEngine, TsSim, TsScore;

{ ---- small builders ---------------------------------------------------- }

function TopBar(Phase: Integer): string;
const
  Names: array[0..4] of string = ('Concept', 'Design', 'Review', 'Fly', 'Report');
var
  I: Integer;
  Cls: string;
begin
  Result := '<header class="topbar">' +
    '<button type="button" class="brand" data-act="home" title="Back to the start">ATOMIC<span>SPACE</span></button>';
  if Phase >= 0 then
  begin
    Result := Result + '<nav class="phase-track" aria-label="Mission phases">';
    for I := 0 to 4 do
    begin
      Cls := 'ph';
      if I < Phase then
        Cls := 'ph done'
      else if I = Phase then
        Cls := 'ph on';
      Result := Result + '<span class="' + Cls + '">' + IntToStr(I + 1) + ' ' + Names[I] + '</span>';
    end;
    Result := Result + '</nav>';
  end;
  Result := Result + '<div class="topbar-right">' +
    Btn('btn btn-ghost btn-small', 'glossary', '', Icon('book') + 'Glossary') +
    Btn('btn btn-ghost btn-small', 'help', '', Icon('info') + 'How to play') +
    '</div></header>';
end;

function Footer: string;
begin
  Result := '<footer class="foot">Atomic Space was made for the 2026 NASA Space Apps Challenge. ' +
    'It is not affiliated with or endorsed by NASA. Data: NASA EONET, DONKI, NeoWs and GIBS. ' +
    '<button type="button" class="btn btn-ghost btn-small" data-act="about">About, sources and AI disclosure</button></footer>';
end;

function Stat(const ALabel, AValue: string): string;
begin
  Result := '<span><i>' + ALabel + '</i> ' + AValue + '</span>';
end;

function KV(const ALabel, AValue: string): string;
begin
  Result := '<div class="kv"><span class="muted">' + ALabel + '</span><b>' + AValue + '</b></div>';
end;

function Fact(const AValue, ALabel: string): string;
begin
  Result := '<div class="fact"><b>' + AValue + '</b><span>' + ALabel + '</span></div>';
end;

function Num(const AValue, ALabel: string): string;
begin
  Result := '<div class="num"><b>' + AValue + '</b><span>' + ALabel + '</span></div>';
end;

function Dots(Level: Integer): string;
var
  I: Integer;
begin
  Result := '<span class="dots" title="Difficulty ' + IntToStr(Level) + ' of 3">';
  for I := 1 to 3 do
    if I <= Level then
      Result := Result + '<i class="on"></i>'
    else
      Result := Result + '<i></i>';
  Result := Result + '</span>';
end;

function SevClass(S: TSeverity): string;
begin
  case S of
    svBlock: Result := 'f-block';
    svWarn: Result := 'f-warn';
    svInfo: Result := 'f-info';
  else
    Result := 'f-good';
  end;
end;

function SevChip(S: TSeverity): string;
begin
  case S of
    svBlock: Result := Chip('chip-bad', Icon('block') + 'Must fix');
    svWarn: Result := Chip('chip-warn', Icon('warn') + 'Warning');
    svInfo: Result := Chip('chip-info', Icon('info') + 'Note');
  else
    Result := Chip('chip-good', Icon('check') + 'Good');
  end;
end;

function OwnerChip(R: TRole): string;
begin
  if Players <= 1 then
    Result := ''
  else
    Result := Chip('chip-' + RoleClass(R), RoleShort[R] + ' &middot; ' + Esc(RoleOwnerName(R)));
end;

function FindingHtml(const F: TFinding; WithOwner: Boolean): string;
begin
  Result := '<div class="finding ' + SevClass(F.Sev) + '"><div class="finding-title">' + SevChip(F.Sev) +
    '<span>' + F.Title + '</span>';
  if WithOwner then
    Result := Result + OwnerChip(F.Owner);
  Result := Result + '</div><p>' + F.Why + '</p><p class="fix"><b>Try:</b> ' + F.Fix + '</p></div>';
end;

function Gauge(const Key, IconName, AName, AValue: string; Fill: Double; const Tone: string;
  Mark: Double; const DeltaHtml: string): string;
begin
  Result := '<button type="button" class="gauge" data-act="gauge" data-a="' + Key + '" title="Show the breakdown">' +
    '<div class="gauge-head"><span class="gauge-name">' + Icon(IconName) + AName + '</span>' +
    '<span class="gauge-val">' + AValue + DeltaHtml + '</span></div>' +
    '<div class="gauge-bar"><div class="gauge-fill ' + Tone + '" style="width:' + FmtNum(Clamp(Fill, 0, 1) * 100, 1) + '%"></div>';
  if Mark >= 0 then
    Result := Result + '<div class="gauge-mark" style="left:' + FmtNum(Clamp(Mark, 0, 1) * 100, 1) + '%"></div>';
  Result := Result + '</div></button>';
end;

function Delta(Change: Double; const Txt: string; MoreIsWorse: Boolean): string;
var
  Cls: string;
begin
  Result := '';
  if not HasPrev then
    Exit;
  if Abs(Change) < 1.0e-9 then
    Exit;
  if (Change > 0) = MoreIsWorse then
    Cls := 'worse'
  else
    Cls := 'better';
  Result := '<span class="delta ' + Cls + '">' + Txt + '</span>';
end;

function Signed(X: Double; const S: string): string;
begin
  if X >= 0 then
    Result := '+' + S
  else
    Result := '-' + S;
end;

function DeadlineText(const Sc: TScenario): string;
begin
  if Sc.ArriveBy then
    Result := 'Arrive within ' + FmtYears(Sc.DeadlineYears)
  else if Sc.WindowYears > 0 then
    Result := 'Launch within ' + FmtYears(Sc.DeadlineYears)
  else
    Result := 'Launch within ' + FmtYears(Sc.DeadlineYears);
end;

function PriorityWord(W: Double): string;
begin
  if W >= 0.95 then Result := 'Top priority'
  else if W >= 0.7 then Result := 'High'
  else if W >= 0.4 then Result := 'Medium'
  else Result := 'Low';
end;

function PriorityBars(WithHave: Boolean): string;
var
  Sc: TScenario;
  M: TMeasure;
  Order: array of TMeasure;
  I, J, N: Integer;
  T: TMeasure;
begin
  Sc := Scenarios[Scen];
  SetLength(Order, 0);
  for M := Low(TMeasure) to High(TMeasure) do
    if Sc.Weight[M] >= 0.1 then
    begin
      N := Length(Order);
      SetLength(Order, N + 1);
      Order[N] := M;
    end;
  for I := 0 to High(Order) - 1 do
    for J := I + 1 to High(Order) do
      if Sc.Weight[Order[J]] > Sc.Weight[Order[I]] then
      begin
        T := Order[I];
        Order[I] := Order[J];
        Order[J] := T;
      end;
  Result := '';
  for I := 0 to High(Order) do
  begin
    M := Order[I];
    Result := Result + '<div class="wbar" title="' + MeasureHint[M] + '"><span>' + MeasureName[M] + '</span>' +
      '<div class="wbar-track"><div class="wbar-fill" style="width:' + FmtNum(Sc.Weight[M] * 100, 0) + '%;opacity:0.45"></div>';
    if WithHave and HasDesign then
      Result := Result + '<div class="wbar-have" style="width:' +
        FmtNum(Clamp(A.Capability[M] / 100, 0, 1) * Sc.Weight[M] * 100, 0) + '%"></div>';
    Result := Result + '</div><span class="muted tiny">';
    if WithHave and HasDesign then
      Result := Result + FmtNum(A.Capability[M], 0)
    else
      Result := Result + PriorityWord(Sc.Weight[M]);
    Result := Result + '</span></div>';
  end;
end;

function EventLegend: string;
var
  Cats: array of string;
  Cnt: array of Integer;
  I, J, N: Integer;
  Found: Boolean;
begin
  SetLength(Cats, 0);
  SetLength(Cnt, 0);
  for I := 0 to High(EarthEvents) do
  begin
    Found := False;
    for J := 0 to High(Cats) do
      if Cats[J] = EarthEvents[I].Category then
      begin
        Inc(Cnt[J]);
        Found := True;
        Break;
      end;
    if not Found then
    begin
      N := Length(Cats);
      SetLength(Cats, N + 1);
      SetLength(Cnt, N + 1);
      Cats[N] := EarthEvents[I].Category;
      Cnt[N] := 1;
    end;
  end;
  Result := '<div class="legend">';
  for I := 0 to High(Cats) do
    Result := Result + '<span><i style="background:' + CategoryColor(Cats[I]) + '"></i>' +
      CategoryLabel(Cats[I]) + ' (' + IntToStr(Cnt[I]) + ')</span>';
  Result := Result + '</div>';
end;

{ ---- title ------------------------------------------------------------- }

function ViewTitle: string;
var
  Live: string;
begin
  if NasaStatus.EonetLive then
    Live := 'live today'
  else if NasaStatus.SnapshotDate <> '' then
    Live := 'as of ' + NiceDate(NasaStatus.SnapshotDate)
  else
    Live := 'loading';
  Result := TopBar(-1) +
    '<main class="hero">' +
    '<h1 class="hero-mark">ATOMIC<span>SPACE</span></h1>' +
    '<p class="hero-tag">' + GameTagline + '</p>' +
    '<p class="hero-sub">Build a whole space mission, from the science question to the last day of operations. ' +
    'Every gram, watt and dollar you spend on one thing is taken from another. For one to four players.</p>' +
    '<div class="hero-actions">' +
    Btn('btn btn-primary btn-big', 'start', '', IconLg('rocket') + 'Start a mission') +
    Btn('btn btn-big', 'log', '', IconLg('trophy') + 'Mission log') +
    Btn('btn btn-big', 'help', '', IconLg('info') + 'How to play') +
    '</div>' +
    '<div class="loop-strip">' +
    '<div class="loop-step"><b>1. Take the mission</b><span>Five real destinations, from Earth orbit to Europa.</span></div>' +
    '<div class="loop-step"><b>2. Design the spacecraft</b><span>Orbit, instruments, power, radio, rocket, budget.</span></div>' +
    '<div class="loop-step"><b>3. Face the review board</b><span>It tells you what will fail, and why.</span></div>' +
    '<div class="loop-step"><b>4. Fly it</b><span>Launch, operate, decide, and read the report.</span></div>' +
    '</div>' +
    '<div class="data-strip">' +
    '<div class="ds-item"><div class="ds-num">' + IntToStr(NasaStatus.EonetCount) + '</div>' +
    '<p>real natural events on Earth (' + Live + ', NASA EONET). They are your targets in Disaster Watch.</p></div>' +
    '<div class="ds-item"><div class="ds-num">' + IntToStr(Length(SpaceWeather)) + '</div>' +
    '<p>real solar storms from NASA''s DONKI database. They strike your spacecraft in flight.</p></div>' +
    '<div class="ds-item"><div class="ds-num">' + IntToStr(NasaStatus.ApophisDays) + ' days</div>' +
    '<p>until asteroid Apophis skims past Earth (NASA JPL). That is your real deadline in Race to Apophis.</p></div>' +
    '</div></main>' + Footer;
end;

{ ---- setup ------------------------------------------------------------- }

function ViewSetup: string;
var
  I: Integer;
  Sc: TScenario;
  Cls, Txt: string;
  Df: TDifficulty;
begin
  Result := TopBar(0) + '<main class="wrap">';
  Result := Result + '<div class="section-head"><span class="step">1</span><h2>Choose a mission</h2></div><div class="scen-grid">';
  for I := 0 to High(Scenarios) do
  begin
    Sc := Scenarios[I];
    Cls := 'scen-card';
    if I = Scen then
      Cls := Cls + ' sel';
    Result := Result + '<button type="button" class="' + Cls + '" data-act="scen" data-a="' + IntToStr(I) + '">' +
      '<div class="scen-top"><div class="planet planet-' + LowerCase(Sc.Body) + '"></div><div><h3>' + Sc.Name +
      '</h3><span class="muted small">' + Sc.Body + '</span></div></div>' +
      '<p class="small">' + Sc.Tagline + '</p>' +
      '<div class="kv"><span class="muted">Level</span>' + Dots(Sc.Level) + '</div>' +
      KV('Cost cap', FmtMoney(Sc.CostCapM * DifficultyCapMult(Difficulty)));
    if Sc.UsesEonet or Sc.UsesApophis then
      Result := Result + '<div>' + Chip('chip-real', 'Driven by live NASA data') + '</div>';
    Result := Result + '</button>';
  end;
  Result := Result + '</div>';

  Result := Result + '<div class="section-head"><span class="step">2</span><h2>Choose the challenge</h2></div>' +
    '<div class="panel"><div class="row"><div class="seg" role="group" aria-label="Difficulty">';
  for Df := Low(TDifficulty) to High(TDifficulty) do
  begin
    Cls := 'seg-btn';
    if Df = Difficulty then
      Cls := Cls + ' on';
    Result := Result + Btn(Cls, 'diff', IntToStr(Ord(Df)), DifficultyName[Df]);
  end;
  Result := Result + '</div>';
  case Difficulty of
    dfCadet: Txt := 'A bigger budget, a rocket that cannot fail and fewer surprises. Best for a first flight.';
    dfChief: Txt := 'A tighter budget, more mass growth and more things going wrong. For crews who have flown before.';
  else
    Txt := 'Real budgets, real odds. Rockets can fail and hardware breaks at the rate your design earns.';
  end;
  Result := Result + '<span class="muted">' + Txt + '</span></div>' +
    '<p style="margin-top:12px"><label class="toggle"><input type="checkbox" data-in="sandbox"';
  if Sandbox then
    Result := Result + ' checked';
  Result := Result + '> <span><b>Sandbox</b> <span class="muted">: no cost cap, to experiment freely. Physics still applies.</span></span></label></p></div>';

  Result := Result + '<div class="section-head"><span class="step">3</span><h2>Choose your crew</h2>' +
    '<span class="muted">One screen, one to four players. Each player owns part of the design and has a goal of their own.</span></div>' +
    '<div class="panel"><div class="row" style="margin-bottom:12px"><div class="seg" role="group" aria-label="Number of players">';
  for I := 1 to 4 do
  begin
    Cls := 'seg-btn';
    if I = Players then
      Cls := Cls + ' on';
    if I = 1 then
      Result := Result + Btn(Cls, 'players', '1', '1 player')
    else
      Result := Result + Btn(Cls, 'players', IntToStr(I), IntToStr(I) + ' players');
  end;
  Result := Result + '</div></div><div class="crew-grid">';
  for I := 0 to Players - 1 do
    Result := Result + '<div class="crew-row"><input type="text" maxlength="18" aria-label="Name of player ' + IntToStr(I + 1) +
      '" data-in="pname" data-a="' + IntToStr(I) + '" value="' + Esc(PlayerName[I]) + '">' +
      '<span class="small">' + PlayerRoles(I) + '</span></div>';
  Result := Result + '</div></div>';

  Result := Result + '<div class="row" style="margin-top:22px">' +
    Btn('btn btn-primary btn-big', 'brief', '', 'Read the briefing ' + Icon('next')) + '</div></main>' + Footer;
end;

{ ---- briefing ---------------------------------------------------------- }

function ViewBrief: string;
var
  Sc: TScenario;
  I: Integer;
  R: TRole;
  Sun: Double;
begin
  Sc := Scenarios[Scen];
  Sun := 1 / (Sc.SunAU * Sc.SunAU);
  Result := TopBar(0) + '<main class="wrap">' +
    '<div class="row"><div class="planet planet-' + LowerCase(Sc.Body) + '"></div><div><h4>Announcement of opportunity</h4>' +
    '<h2>' + Sc.Name + ': ' + Sc.Tagline + '</h2></div></div>' +
    '<div class="brief-grid" style="margin-top:16px"><div>' +
    '<div class="panel"><p class="lead">' + Sc.Brief + '</p>' +
    '<div class="finding f-info" style="margin-top:14px"><div class="finding-title">' + Icon('target') + 'Your objective</div><p>' +
    Sc.Objective + '</p></div><div class="fact-row">' +
    Fact(FmtMoney(Sc.CostCapM * DifficultyCapMult(Difficulty)), 'cost cap for everything: spacecraft, rocket, operations') +
    Fact(DeadlineText(Sc), 'so a slow, complicated design may be too late') +
    Fact(FmtPct(Sun), 'of the sunlight Earth gets') +
    Fact(FmtYears(Sc.MinLife), 'of science operations, at least');
  if Sc.NearEarth then
    Result := Result + Fact('0.01 s', 'for a radio signal to reach the ground')
  else
    Result := Result + Fact(FmtNum((Sc.EarthMinAU + Sc.EarthMaxAU) / 2 * LightSecondsPerAu / 60, 1) + ' min',
      'for a radio signal to reach Earth, on average');
  if Sc.UsesApophis then
    Result := Result + Fact(IntToStr(Round(ApophisDays)) + ' days', 'until the real flyby on ' + NiceDate(ApophisDate)) +
      Fact(FmtNum(ApophisMissKm, 0) + ' km', 'closest distance from Earth''s centre (NASA NeoWs)');
  Result := Result + '</div></div>';

  if Sc.UsesEonet then
    Result := Result + '<div class="panel"><div class="panel-title">' + Icon('globe') + '<h3>Your targets: real events happening now</h3>' +
      Chip('chip-real', EarthEventsSource) + '</div><div class="map-box"><canvas id="cv-map" width="1280" height="640" ' +
      'role="img" aria-label="World map showing real natural events from NASA EONET"></canvas></div>' + EventLegend +
      '<p class="small muted" style="margin-top:8px">Each dot is a real wildfire, storm, flood or ice event listed by NASA''s Earth Observatory ' +
      'Natural Event Tracker. Where they are decides which orbit works, and what kind they are decides which instruments matter. ' +
      'Map: NASA Blue Marble.</p></div>';

  Result := Result + '</div><div><div class="panel"><div class="panel-title">' + Icon('flask') + '<h3>What the science team wants</h3></div>' +
    PriorityBars(False);
  if Sc.UsesEonet then
    Result := Result + '<p class="small muted" style="margin-top:8px">These priorities were worked out from today''s real events.</p>';
  Result := Result + '</div><div class="panel"><div class="panel-title">' + Icon('info') + '<h3>Worth knowing</h3></div>';
  for I := 0 to Min(3, High(Sc.Facts)) do
    Result := Result + '<p class="small" style="margin-top:6px">' + Sc.Facts[I] + '</p>';
  Result := Result + '</div></div></div>';

  if Players > 1 then
  begin
    Result := Result + '<div class="section-head"><h2>Your crew</h2><span class="muted">Everyone scores together, but each role also has a goal of its own. They pull in different directions. That is the point.</span></div><div class="role-cards">';
    for R := Low(TRole) to High(TRole) do
      Result := Result + '<div class="role-card role-' + RoleClass(R) + '"><h4>' + RoleName[R] + '</h4><h3>' +
        Esc(RoleOwnerName(R)) + '</h3><p class="small" style="margin-top:6px">' + RoleGoalText(R) + '</p></div>';
    Result := Result + '</div>';
  end;

  Result := Result + '<div class="section-head"><h2>Real missions like this one</h2><span class="muted">At the end, your design is compared with them.</span></div><div class="analog-grid">';
  for I := 0 to High(Sc.Analogs) do
    Result := Result + '<div class="analog"><h3>' + Sc.Analogs[I].Name + '</h3><span class="muted tiny">' + Sc.Analogs[I].Agency +
      ', ' + Sc.Analogs[I].Year + '</span><p style="margin:6px 0">' + Sc.Analogs[I].Blurb + '</p><div class="stats">' +
      Stat('mass', FmtMass(Sc.Analogs[I].MassKg)) + Stat('cost', '~' + FmtMoney(Sc.Analogs[I].CostM)) + '</div><p style="margin-top:6px">' +
      Link(Sc.Analogs[I].Url, 'Mission page') + '</p></div>';
  Result := Result + '</div><div class="row" style="margin-top:22px">' +
    Btn('btn', 'start', '', Icon('back') + 'Change mission') +
    Btn('btn btn-primary btn-big', 'lab', '', 'Open the design lab ' + Icon('next')) + '</div></main>' + Footer;
end;

{ ---- design lab -------------------------------------------------------- }

function TabDot(Tab: Integer): string;
var
  I: Integer;
  Worst: TSeverity;
begin
  Worst := svGood;
  for I := 0 to High(A.Findings) do
    if (FindingTab(A.Findings[I].Code) = Tab) and (A.Findings[I].Sev > Worst) and (A.Findings[I].Sev <> svInfo) then
      Worst := A.Findings[I].Sev;
  case Worst of
    svBlock: Result := '<span class="dot bad" title="Something here must be fixed"></span>';
    svWarn: Result := '<span class="dot warn" title="There is a warning here"></span>';
  else
    Result := '<span class="dot" title="No problems here"></span>';
  end;
end;

function ViewLabNav: string;
var
  I: Integer;
  Cls: string;
begin
  Result := '';
  for I := 0 to TabCount - 1 do
  begin
    Cls := 'tab';
    if I = LabTab then
      Cls := Cls + ' on';
    Result := Result + '<button type="button" class="' + Cls + '" data-act="tab" data-a="' + IntToStr(I) + '">' +
      '<span class="tab-n">' + IntToStr(I + 1) + '</span>' + Icon(TabIcon[I]) + '<span class="tab-label">' + TabName[I] + '</span>';
    if Players > 1 then
      Result := Result + Chip('chip-' + RoleClass(TabRole[I]), RoleShort[TabRole[I]]);
    Result := Result + TabDot(I) + '</button>';
  end;
  Result := Result + '<div style="height:6px"></div>';
  if A.Blockers > 0 then
    Result := Result + Btn('btn btn-primary', 'review', '', Icon('flag') + 'Review board (' + IntToStr(A.Blockers) + ' to fix)')
  else
    Result := Result + Btn('btn btn-primary', 'review', '', Icon('flag') + 'Go to the review board');
  Result := Result + Btn('btn btn-ghost btn-small', 'example', '', 'Load an example design') +
    Btn('btn btn-ghost btn-small', 'share', '', Icon('share') + 'Share this design');
end;

function TabFindings(Tab: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(A.Findings) do
    if (FindingTab(A.Findings[I].Code) = Tab) and (A.Findings[I].Sev <> svGood) then
      Result := Result + FindingHtml(A.Findings[I], False);
  if Result <> '' then
    Result := '<div style="margin-bottom:14px">' + Result + '</div>';
end;

function Opt(Sel, Off: Boolean; const Act, Arg, Title, Analog, Blurb, StatsHtml, Extra: string): string;
var
  Cls: string;
begin
  Cls := 'opt';
  if Sel then
    Cls := Cls + ' sel';
  if Off then
    Cls := Cls + ' off';
  Result := '<button type="button" class="' + Cls + '" data-act="' + Act + '" data-a="' + Arg + '" aria-pressed="';
  if Sel then
    Result := Result + 'true">'
  else
    Result := Result + 'false">';
  Result := Result + '<span class="tick"></span><span class="opt-title">' + Title + '</span>';
  if Analog <> '' then
    Result := Result + '<span class="opt-analog">' + Analog + '</span>';
  Result := Result + '<span class="opt-blurb">' + Blurb + '</span>' + Extra;
  if StatsHtml <> '' then
    Result := Result + '<span class="stats">' + StatsHtml + '</span>';
  Result := Result + '</button>';
end;

procedure PartFigures(K: TPartKind; Idx: Integer; out MassKg, PowerW, CostM: Double);
var
  P, Bus, Risk: TPart;
  G, GP: Double;
begin
  P := Parts[K][Idx];
  Bus := Parts[pkBus][D.Part[pkBus]];
  Risk := Parts[pkRisk][D.Part[pkRisk]];
  G := Bus.G;
  if G >= 1 then
    GP := Power(G, 0.6)
  else
    GP := Power(G, 1.1);
  MassKg := P.MassKg;
  PowerW := P.PowerW;
  CostM := P.CostM;
  case K of
    pkBus: CostM := P.CostM * Risk.A;
    pkAdcs:
      begin
        MassKg := P.MassKg * G * Risk.B;
        PowerW := P.PowerW * Power(G, 0.8);
        CostM := P.CostM * Power(G, 0.7) * Risk.A;
      end;
    pkPropulsion:
      begin
        MassKg := P.MassKg * GP;
        CostM := P.CostM * GP * Risk.A;
      end;
    pkShield:
      begin
        MassKg := P.MassKg * G;
        CostM := P.CostM * Power(G, 0.7);
      end;
    pkThermal: CostM := P.CostM * Power(G, 0.7) + P.E;
    pkComputer:
      begin
        MassKg := P.MassKg * Risk.B;
        CostM := P.CostM * Risk.A;
      end;
  end;
end;

function PartGroup(K: TPartKind; const Title, Intro: string): string;
var
  I: Integer;
  P: TPart;
  M, W, C: Double;
  S, Extra: string;
  Off: Boolean;
begin
  Result := '<div class="group-title"><h3>' + Title + '</h3>' + OwnerChip(PartKindOwner[K]) + '</div>';
  if Intro <> '' then
    Result := Result + '<p class="muted small" style="margin:-4px 0 10px;max-width:74ch">' + Intro + '</p>';
  Result := Result + '<div class="opt-grid">';
  for I := 0 to High(Parts[K]) do
  begin
    P := Parts[K][I];
    PartFigures(K, I, M, W, C);
    S := '';
    Extra := '';
    case K of
      pkBus: S := Stat('frame', FmtMass(M)) + Stat('carries', FmtMass(P.B) + ', ' + IntToStr(Round(P.C)) + ' instr') +
          Stat('cost', FmtMoney(C)) + Stat('build', FmtYears(P.DevYears));
      pkPropulsion:
        if P.Tier = 0 then
          S := Stat('mass', '0 kg') + Stat('cost', '$0')
        else
          S := Stat('efficiency', FmtNum(P.A, 0) + ' s') + Stat('mass', FmtMass(M)) + Stat('cost', FmtMoney(C));
      pkGround: S := Stat('cost', FmtMoney(C) + ' a year');
      pkRisk: S := Stat('cost', 'x' + FmtNum(P.A, 2)) + Stat('faults', 'x' + FmtNum(P.C, 2)) + Stat('time', Signed(P.D, FmtNum(Abs(P.D), 1)) + ' y');
      pkSchedule: S := Stat('time', 'x' + FmtNum(P.A, 2)) + Stat('cost', 'x' + FmtNum(P.B, 2));
      pkComputer: S := Stat('storage', FmtData(P.A)) + Stat('mass', FmtMass(M)) + Stat('power', FmtPower(W)) + Stat('cost', FmtMoney(C));
      pkBand:
        if P.Tier = 4 then
          S := Stat('rate', 'x50 or more') + Stat('mass', FmtMass(M)) + Stat('power', FmtPower(W)) + Stat('cost', FmtMoney(C))
        else
          S := Stat('rate', 'x' + FmtAuto(P.A)) + Stat('limit', FmtRate(P.B)) + Stat('mass', FmtMass(M)) + Stat('cost', FmtMoney(C));
      pkTx: S := Stat('signal', FmtNum(P.A, 0) + ' W') + Stat('draws', FmtPower(W)) + Stat('mass', FmtMass(M)) + Stat('cost', FmtMoney(C));
      pkAntenna: S := Stat('mass', FmtMass(M)) + Stat('cost', FmtMoney(C));
    else
      begin
        S := Stat('mass', FmtMass(M));
        if W > 0 then
          S := S + Stat('power', FmtPower(W));
        S := S + Stat('cost', FmtMoney(C));
      end;
    end;
    Off := (K <> pkBus) and (Ord(P.MinBus) > Parts[pkBus][D.Part[pkBus]].Tier);
    if Off then
      Extra := '<span class="needs">Needs a bigger spacecraft bus</span>';
    Result := Result + Opt(D.Part[K] = I, Off, 'part', IntToStr(Ord(K)) + ':' + IntToStr(I), P.Name, P.Analog, P.Blurb, S, Extra);
  end;
  Result := Result + '</div>';
end;

function RadWord(L: Integer): string;
begin
  case L of
    0: Result := 'gentle';
    1: Result := 'moderate';
    2: Result := 'harsh';
  else
    Result := 'extreme';
  end;
end;

function TabOrbit: string;
var
  Sc: TScenario;
  O: TOrbit;
  I: Integer;
  S: string;
begin
  Sc := Scenarios[Scen];
  Result := '<div class="tab-intro"><h2>Where will it work?</h2><p>The orbit decides what the instruments can see, how much fuel it takes to get there ' +
    'and stay there, how long the nights are and how far the radio has to shout.</p></div>' + TabFindings(0);
  if Sc.UsesEonet then
    Result := Result + '<div class="map-box" style="margin-bottom:10px"><canvas id="cv-map" width="1280" height="640" role="img" ' +
      'aria-label="World map of real events and what the chosen orbit can see"></canvas></div>' + EventLegend +
      '<p class="small muted" style="margin:6px 0 14px">Bright dots are real events this orbit can see. Dim ones are out of reach. ' +
      Chip('chip-real', EarthEventsSource) + '</p>';
  Result := Result + '<div class="cv-box" style="margin-bottom:14px"><canvas id="cv-orbit" width="1280" height="620" role="img" ' +
    'aria-label="Animated picture of the chosen orbit"></canvas><div class="cv-cap">Grey stretches of the orbit are in shadow: no solar power there. ' +
    'Altitudes are squeezed to fit the picture.</div></div>';
  Result := Result + '<div class="group-title"><h3>Orbit</h3>' + OwnerChip(roScience) + '</div><div class="opt-grid">';
  for I := 0 to High(Sc.Orbits) do
  begin
    O := Sc.Orbits[I];
    S := Stat('to get in', FmtDv(O.DvInsert * Sc.Transfers[D.Transfer].DvFactor)) + Stat('per year', FmtDv(O.DvPerYear)) +
      Stat('shadow', FmtPct(O.EclipseFrac));
    if O.EventsTotal > 0 then
      S := S + Stat('sees', IntToStr(O.EventsSeen) + '/' + IntToStr(O.EventsTotal) + ' events')
    else
      S := S + Stat('reach', FmtPct(O.Coverage));
    S := S + Stat('radiation', RadWord(O.RadLevel));
    Result := Result + Opt(D.Orbit = I, False, 'orbit', IntToStr(I), O.Name, O.Blurb, O.Why, S, '');
  end;
  Result := Result + '</div>';
  if Length(Sc.Transfers) > 1 then
  begin
    Result := Result + '<div class="group-title"><h3>Route</h3>' + OwnerChip(roScience) + '</div>' +
      '<p class="muted small" style="margin:-4px 0 10px;max-width:74ch">A faster route needs more launch energy, so each rocket can carry less. ' +
      'A slower route lets a smaller rocket do the job, if you can wait.</p><div class="opt-grid">';
    for I := 0 to High(Sc.Transfers) do
      Result := Result + Opt(D.Transfer = I, False, 'transfer', IntToStr(I), Sc.Transfers[I].Name, '', Sc.Transfers[I].Blurb,
        Stat('launch energy', FmtNum(Sc.Transfers[I].C3, 0)) + Stat('trip', FmtYears(Sc.Transfers[I].CruiseYears)) +
        Stat('braking', 'x' + FmtNum(Sc.Transfers[I].DvFactor, 2)), '');
    Result := Result + '</div>';
  end;
end;

function TabPayload: string;
var
  Sc: TScenario;
  I: Integer;
  M, Prim: TMeasure;
  Ins: TInstrument;
  S, Chips, Needs: string;
  Off: Boolean;
begin
  Sc := Scenarios[Scen];
  Prim := PrimaryMeasure(Sc);
  Result := '<div class="tab-intro"><h2>What will it measure?</h2><p>The instruments are the reason the mission exists. ' +
    'Each one adds science, and also mass, power draw, data to send home, cost and build time. Watch the gauges move as you choose.</p></div>' +
    TabFindings(1) + '<div class="panel" style="margin-bottom:14px"><div class="panel-title">' + Icon('flask') +
    '<h3>Science priorities and what your payload delivers</h3></div>' + PriorityBars(True) +
    '<p class="small muted" style="margin-top:8px">Pale bar: how much the science team wants it. Green: how well your payload measures it from the chosen orbit (out of 100). ' +
    'A second instrument for the same thing adds only half as much.</p></div><div class="opt-grid">';
  for I := 0 to High(Instruments) do
  begin
    if not InstrumentOffered(Scen, I) then
      Continue;
    Ins := Instruments[I];
    Chips := '<span class="mchips">';
    for M := Low(TMeasure) to High(TMeasure) do
      if (Ins.Value[M] > 0) and (Sc.Weight[M] > 0.04) then
      begin
        if M = Prim then
          Chips := Chips + '<span class="mchip key">'
        else
          Chips := Chips + '<span class="mchip">';
        Chips := Chips + MeasureName[M] + ' <b>' + FmtNum(Ins.Value[M], 0) + '</b></span>';
      end;
    Chips := Chips + '</span>';
    Needs := '';
    if Ins.NeedsFinePointing then
      Needs := Needs + 'Needs steady pointing. ';
    if Ins.NeedsCooling then
      Needs := Needs + 'Needs a cryocooler. ';
    if Ins.NeedsHGA then
      Needs := Needs + 'Needs a dish and X-band. ';
    Off := Ord(Ins.MinBus) > Parts[pkBus][D.Part[pkBus]].Tier;
    if Off then
      Needs := Needs + 'Too big for this bus. ';
    if Needs <> '' then
      Chips := Chips + '<span class="needs">' + Needs + '</span>';
    S := Stat('mass', FmtMass(Ins.MassKg)) + Stat('power', FmtPower(Ins.PowerW)) + Stat('cost', FmtMoney(Ins.CostM)) +
      Stat('data', FmtData(Ins.DataMbps * Ins.Duty * Sc.DataScale * Sc.Orbits[D.Orbit].DataFactor * 86.4) + '/day');
    Result := Result + Opt((I <= High(D.Instr)) and D.Instr[I], Off, 'instr', IntToStr(I), Ins.Name, Ins.Analog, Ins.Blurb, S, Chips);
  end;
  Result := Result + '</div>';
end;

function TabSpacecraft: string;
begin
  Result := '<div class="tab-intro"><h2>What will carry it?</h2><p>The bus is everything that is not an instrument: the frame, the engines, ' +
    'the pointing system and the protection. A bigger bus carries more, and needs more fuel and a bigger rocket to match.</p></div>' +
    TabFindings(2) +
    '<div class="ripple">Speed change needed: <b>' + FmtDv(A.DvNeed) + '</b> (' + FmtDv(A.DvInsert) + ' to get into orbit, ' +
    FmtDv(A.DvKeep) + ' to stay there for ' + FmtYears(D.LifeYears) + ', plus 10 % spare). With the engine chosen that takes <b>' +
    FmtMass(A.PropKg) + '</b> of propellant for a ' + FmtMass(A.DryKg) + ' spacecraft.</div>' +
    PartGroup(pkBus, 'Spacecraft bus', '') +
    PartGroup(pkPropulsion, 'Propulsion', 'The rocket equation rules here: every kilogram of fuel needs more fuel to carry it. An efficient engine (a high number of seconds) breaks the spiral.') +
    PartGroup(pkAdcs, 'Attitude control', 'How the spacecraft knows which way it faces and turns to point. Sharp cameras and narrow radio beams need a steady platform.') +
    PartGroup(pkThermal, 'Thermal control', 'Space is both very hot and very cold. Electronics, fuel and detectors each have a temperature they must be kept at.') +
    PartGroup(pkShield, 'Radiation shielding', 'Added to whatever protection the computer has. Radiation here is ' +
      RadWord(Scenarios[Scen].Orbits[D.Orbit].RadLevel) + '.');
end;

function PowerInfo: string;
var
  Sc: TScenario;
  O: TOrbit;
  I: Integer;
begin
  Sc := Scenarios[Scen];
  O := Sc.Orbits[D.Orbit];
  Result := '<div class="numgrid">' +
    Num(FmtPct(1 / (Sc.SunAU * Sc.SunAU)), 'of Earth''s sunlight') +
    Num(FmtPower(ArrayWattsPerM2 / (Sc.SunAU * Sc.SunAU)), 'from each square metre') +
    Num(FmtPct(O.EclipseFrac), 'of each orbit in shadow') +
    Num(FmtNum(O.MaxEclipseHr, 1) + ' h', 'longest night') +
    Num(FmtPower(A.GenAvgW), 'made, averaged over an orbit') +
    Num(FmtPower(A.LoadAvgW), 'needed, on average') +
    Num(FmtNum(A.BatteryNeedWh, 0) + ' Wh', 'battery needed for the night') +
    '</div><table class="tbl" style="margin-top:12px"><tr><th>Where the power goes</th><th class="n">Watts</th></tr>';
  for I := 0 to High(A.PowerLines) do
    Result := Result + '<tr><td>' + A.PowerLines[I].Name + '</td><td class="n">' + FmtNum(A.PowerLines[I].Value, 0) + '</td></tr>';
  Result := Result + '<tr><td><b>Total needed</b></td><td class="n"><b>' + FmtNum(A.LoadAvgW, 0) + '</b></td></tr></table>';
end;

function Slider(const Key, Title, Hint, ValText: string; Value, MinV, MaxV, Step: Double; R: TRole): string;
begin
  Result := '<div class="slider-row"><div class="slider-head"><div><h3>' + Title + ' ' + OwnerChip(R) + '</h3><span class="muted small">' + Hint +
    '</span></div><span class="slider-val" id="val-' + Key + '">' + ValText + '</span></div>' +
    '<input type="range" data-in="' + Key + '" aria-label="' + Title + '" min="' + FmtNum(MinV, 2) + '" max="' + FmtNum(MaxV, 2) +
    '" step="' + FmtNum(Step, 2) + '" value="' + FmtNum(Value, 2) + '"></div>';
end;

function PlainNum(X: Double): string;
begin
  { For form attributes: no thousands separators. }
  Result := StringReplace(FmtNum(X, 2), ',', '', [rfReplaceAll]);
end;

function TabPower: string;
var
  Sc: TScenario;
  Bus: TPart;
  Step, MaxB: Double;
begin
  Sc := Scenarios[Scen];
  Bus := Parts[pkBus][D.Part[pkBus]];
  Result := '<div class="tab-intro"><h2>What will power it?</h2><p>Sunlight fades with the square of distance, and solar panels make nothing in shadow. ' +
    'Size the array for the worst day, and the battery for the longest night.</p></div>' + TabFindings(3);
  case Bus.Tier of
    0: begin Step := 0.1; MaxB := 600; end;
    1: begin Step := 0.5; MaxB := 4000; end;
    2: begin Step := 1; MaxB := 10000; end;
  else
    begin Step := 2; MaxB := 20000; end;
  end;
  Result := Result + '<div class="slider-row"><div class="slider-head"><div><h3>Solar array ' + OwnerChip(roSpacecraft) +
    '</h3><span class="muted small">Up to ' + FmtNum(Bus.D, 1) + ' m2 on this bus. Each square metre weighs ' + FmtNum(ArrayKgPerM2, 1) +
    ' kg.</span></div><span class="slider-val" id="val-solar">' + FmtNum(D.SolarM2, 1) + ' m2</span></div>' +
    '<input type="range" data-in="solar" aria-label="Solar array area" min="0" max="' + PlainNum(Bus.D) + '" step="' + PlainNum(Step) +
    '" value="' + PlainNum(Min(D.SolarM2, Bus.D)) + '"></div>';
  Result := Result + '<div class="slider-row"><div class="slider-head"><div><h3>Battery ' + OwnerChip(roSpacecraft) +
    '</h3><span class="muted small">Carries the spacecraft through the dark. About 7.7 kg per kilowatt-hour.</span></div>' +
    '<span class="slider-val" id="val-battery">' + FmtNum(D.BatteryWh, 0) + ' Wh</span></div>' +
    '<input type="range" data-in="battery" aria-label="Battery capacity" min="0" max="' + PlainNum(MaxB) + '" step="' +
    PlainNum(MaxB / 200) + '" value="' + PlainNum(Min(D.BatteryWh, MaxB)) + '"></div>';
  if Sc.AllowRTG then
    Result := Result + '<div class="slider-row"><div class="slider-head"><div><h3>Nuclear batteries (RTG) ' + OwnerChip(roSpacecraft) +
      '</h3><span class="muted small">Each makes 110 W anywhere, day or night, for decades. Each weighs 45 kg, costs ' + FmtMoney(RtgCostM) +
      ' and the first one adds a year of safety approvals.</span></div><span class="stepper">' +
      Btn('btn', 'rtg', '-1', '&minus;') + '<span class="slider-val">' + IntToStr(D.RtgCount) + '</span>' + Btn('btn', 'rtg', '1', '+') +
      '</span></div></div>'
  else
    Result := Result + '<p class="muted small" style="margin:0 0 10px">Nuclear power is not offered for this mission: there is enough sunlight, and plutonium is scarce.</p>';
  Result := Result + '<div class="panel" id="power-info">' + PowerInfo + '</div>';
end;

function TabComms: string;
var
  Sc: TScenario;
  Dist: Double;
begin
  Sc := Scenarios[Scen];
  if Sc.NearEarth then
    Dist := Sc.Orbits[D.Orbit].RangeKm
  else
    Dist := (Sc.EarthMinAU + Sc.EarthMaxAU) / 2 * AuKm;
  Result := '<div class="tab-intro"><h2>How will the data get home?</h2><p>Data that never reaches Earth is science that never happened. ' +
    'The rate grows with dish size, transmitter power and frequency, and falls with the square of distance.</p></div>' + TabFindings(4) +
    '<div class="panel" style="margin-bottom:6px"><div class="numgrid">' +
    Num(FmtDist(Dist), 'to the ground station') +
    Num(FmtRate(A.RateAvgMbps), 'typical data rate') +
    Num(FmtRate(A.RateMinMbps), 'when furthest away') +
    Num(FmtNum(A.ContactHr, 1) + ' h', 'of contact a day') +
    Num(FmtData(A.GenGbitDay), 'recorded a day') +
    Num(FmtData(A.DownGbitDay), 'can be sent a day') +
    Num(FmtPct(A.DataReturn), 'of the data gets home') +
    '</div></div>' +
    PartGroup(pkAntenna, 'Antenna', 'Doubling the dish width gives four times the data rate.') +
    PartGroup(pkBand, 'Radio band', '') +
    PartGroup(pkTx, 'Transmitter', '') +
    PartGroup(pkGround, 'Ground network', 'Antennas on Earth are shared between missions. More listening time costs more every year.') +
    PartGroup(pkComputer, 'Flight computer and recorder', 'The recorder holds data between contacts. The computer also has to survive the radiation.');
end;

function TabLaunch: string;
var
  I, K, N: Integer;
  Opts: array of TLaunchOption;
  Order: array of Integer;
  L: TLauncher;
  S, Extra, Tone: string;
  T: Integer;
  Better: Boolean;
begin
  Result := '<div class="tab-intro"><h2>What will lift it?</h2><p>Fuelled, your spacecraft weighs <b>' + FmtMass(A.WetKg) +
    '</b> and has to reach ' + LaunchTargetName(D) + '. Every rocket can lift less the harder it has to throw.</p></div>' + TabFindings(5);
  N := Length(Launchers);
  SetLength(Opts, N);
  SetLength(Order, N);
  for I := 0 to N - 1 do
  begin
    Opts[I] := LaunchOption(I, D, A.WetKg);
    Order[I] := I;
  end;
  { Rockets that can do the job first, cheapest first. }
  for I := 0 to N - 2 do
    for K := I + 1 to N - 1 do
    begin
      Better := False;
      if Opts[Order[K]].Fits and not Opts[Order[I]].Fits then
        Better := True
      else if Opts[Order[K]].Fits = Opts[Order[I]].Fits then
      begin
        if Opts[Order[K]].CanReach and not Opts[Order[I]].CanReach then
          Better := True
        else if (Opts[Order[K]].CanReach = Opts[Order[I]].CanReach) and (Opts[Order[K]].CostM < Opts[Order[I]].CostM) then
          Better := True;
      end;
      if Better then
      begin
        T := Order[I];
        Order[I] := Order[K];
        Order[K] := T;
      end;
    end;
  Result := Result + '<div class="group-title"><h3>Launch vehicle</h3>' + OwnerChip(roPM) + '</div><div class="opt-grid">';
  for K := 0 to N - 1 do
  begin
    I := Order[K];
    L := Launchers[I];
    Extra := '';
    if not Opts[I].CanReach then
    begin
      S := Stat('cost', FmtMoney(Opts[I].CostM));
      Extra := '<span class="needs">' + Opts[I].Why + '</span>';
    end
    else
    begin
      S := Stat('can lift', FmtMass(Opts[I].CapKg)) + Stat('cost', FmtMoney(Opts[I].CostM)) + Stat('success', FmtPct(L.Reliability));
      if Opts[I].Fits then
      begin
        Tone := 'good';
        if Opts[I].Margin < 0.1 then
          Tone := 'warn';
        Extra := '<span class="gauge-bar" style="display:block"><span class="gauge-fill ' + Tone + '" style="display:block;width:' +
          FmtNum(Clamp(1 - Opts[I].Margin, 0, 1) * 100, 0) + '%"></span></span><span class="tiny muted">' + FmtPct(Opts[I].Margin) + ' to spare</span>';
      end
      else
        Extra := '<span class="needs">Too small: ' + FmtMass(A.WetKg - Opts[I].CapKg) + ' over its limit.</span>';
    end;
    Result := Result + Opt(D.Launcher = I, not Opts[I].Fits, 'launcher', IntToStr(I), L.Name, L.Agency, L.Blurb, S, Extra);
  end;
  Result := Result + '</div>';
end;

function PlanInfo: string;
var
  Sc: TScenario;
  I: Integer;
begin
  Sc := Scenarios[Scen];
  Result := '<div class="numgrid">' +
    Num(FmtYears(A.DevYears), 'to build and test') +
    Num(FmtYears(A.LaunchYear), 'until launch') +
    Num(FmtYears(A.CruiseYears), 'travelling') +
    Num(FmtYears(D.LifeYears), 'of science planned') +
    Num(FmtPct(A.SuccessProb), 'chance of finishing') +
    '</div>';
  if A.MissedDeadline then
    Result := Result + '<p class="small" style="margin-top:8px;color:var(--warn)">This plan misses the deadline (' + DeadlineText(Sc) + ').</p>'
  else
    Result := Result + '<p class="small muted" style="margin-top:8px">Deadline: ' + DeadlineText(Sc) + '. This plan meets it.</p>';
  Result := Result + '<table class="tbl" style="margin-top:12px"><tr><th>Where the money goes</th><th class="n">$ million</th></tr>';
  for I := 0 to High(A.CostLines) do
    Result := Result + '<tr><td>' + A.CostLines[I].Name + '</td><td class="n">' + FmtNum(A.CostLines[I].Value, 1) + '</td></tr>';
  Result := Result + '<tr><td><b>Total</b> against a cap of ' + FmtMoney(A.CapM) + '</td><td class="n"><b>' + FmtNum(A.CostTotal, 1) + '</b></td></tr></table>';
end;

function TabPlan: string;
var
  Sc: TScenario;
begin
  Sc := Scenarios[Scen];
  Result := '<div class="tab-intro"><h2>How will it be run?</h2><p>Time, money and risk are resources too. A longer mission returns more science, ' +
    'with diminishing returns, and costs more to operate. Reserves and backups look like waste until the day they are needed.</p></div>' + TabFindings(6) +
    '<div class="slider-row"><div class="slider-head"><div><h3>Planned science operations ' + OwnerChip(roOps) + '</h3><span class="muted small">At least ' +
    FmtYears(Sc.MinLife) + '. Each year costs ' + FmtMoney(A.OpsPerYearM) + ' to operate and uses station-keeping fuel.</span></div>' +
    '<span class="slider-val" id="val-life">' + FmtYears(D.LifeYears) + '</span></div>' +
    '<input type="range" data-in="life" aria-label="Planned science operations in years" min="0.25" max="' + PlainNum(Sc.MaxLife) +
    '" step="0.25" value="' + PlainNum(D.LifeYears) + '"></div>' +
    '<div class="slider-row"><div class="slider-head"><div><h3>Reserves ' + OwnerChip(roPM) + '</h3><span class="muted small">Money held back for surprises during development. ' +
    'Unspent reserves are not counted against you.</span></div><span class="slider-val" id="val-reserve">' + FmtNum(D.ReservePct, 0) + ' %</span></div>' +
    '<input type="range" data-in="reserve" aria-label="Reserves in percent" min="0" max="40" step="5" value="' + PlainNum(D.ReservePct) + '"></div>' +
    '<div class="panel" id="plan-info">' + PlanInfo + '</div>' +
    PartGroup(pkRisk, 'Risk posture', 'NASA grades missions from class A (must not fail) to class D (cheap, higher risk accepted). More backups and testing cost money, mass and time.') +
    PartGroup(pkSchedule, 'Schedule', '');
end;

function ViewLabMain: string;
begin
  case LabTab of
    0: Result := TabOrbit;
    1: Result := TabPayload;
    2: Result := TabSpacecraft;
    3: Result := TabPower;
    4: Result := TabComms;
    5: Result := TabLaunch;
  else
    Result := TabPlan;
  end;
end;

function RippleText: string;
var
  S: string;
begin
  Result := '';
  if not HasPrev then
    Exit;
  S := '';
  if Abs(A.DryKg - PrevA.DryKg) > 0.05 then
    S := S + Signed(A.DryKg - PrevA.DryKg, FmtMass(Abs(A.DryKg - PrevA.DryKg))) + ' equipment';
  if Abs(A.PropKg - PrevA.PropKg) > 0.05 then
  begin
    if S <> '' then
      S := S + ' &rarr; ';
    S := S + Signed(A.PropKg - PrevA.PropKg, FmtMass(Abs(A.PropKg - PrevA.PropKg))) + ' propellant';
  end;
  if (A.LvCapKg > 0) and (PrevA.LvCapKg > 0) and (Abs(A.MassMargin - PrevA.MassMargin) > 0.004) then
  begin
    if S <> '' then
      S := S + ' &rarr; ';
    S := S + 'launch margin ' + FmtPct(PrevA.MassMargin) + ' to ' + FmtPct(A.MassMargin);
  end;
  if Abs(A.LoadAvgW - PrevA.LoadAvgW) > 0.5 then
  begin
    if S <> '' then
      S := S + '; ';
    S := S + Signed(A.LoadAvgW - PrevA.LoadAvgW, FmtPower(Abs(A.LoadAvgW - PrevA.LoadAvgW))) + ' power needed';
  end;
  if Abs(A.DataReturn - PrevA.DataReturn) > 0.004 then
  begin
    if S <> '' then
      S := S + '; ';
    S := S + 'data home ' + FmtPct(PrevA.DataReturn) + ' to ' + FmtPct(A.DataReturn);
  end;
  if Abs(A.CostTotal - PrevA.CostTotal) > 0.05 then
  begin
    if S <> '' then
      S := S + '; ';
    S := S + Signed(A.CostTotal - PrevA.CostTotal, FmtMoney(Abs(A.CostTotal - PrevA.CostTotal)));
  end;
  if Abs(A.SciencePct - PrevA.SciencePct) > 0.5 then
  begin
    if S <> '' then
      S := S + '; ';
    S := S + 'science ' + FmtNum(PrevA.SciencePct, 0) + ' % to ' + FmtNum(A.SciencePct, 0) + ' %';
  end;
  if S <> '' then
    Result := '<div class="ripple"><b>Your last change rippled:</b> ' + S + '</div>';
end;

function ViewLabDash: string;
var
  Sc: TScenario;
  Tone, V, Dl: string;
  I, Shown: Integer;
  Sev: TSeverity;
  R: TRole;
begin
  Sc := Scenarios[Scen];
  Result := '<div class="panel"><div class="panel-title">' + Icon('target') + '<h3>Mission resources</h3></div>';

  { cost }
  Tone := 'good';
  if A.CostTotal > A.CapM then
  begin
    Tone := 'bad';
    if D.Sandbox then
      Tone := 'info';
  end
  else if A.CostMargin < 0.05 then
    Tone := 'warn';
  Dl := Delta(A.CostTotal - PrevA.CostTotal, Signed(A.CostTotal - PrevA.CostTotal, FmtMoney(Abs(A.CostTotal - PrevA.CostTotal))), True);
  Result := Result + Gauge('cost', 'coin', 'Cost', FmtMoney(A.CostTotal) + ' of ' + FmtMoney(A.CapM), A.CostTotal / A.CapM, Tone, -1, Dl);

  { launch mass }
  if D.Launcher < 0 then
    Result := Result + Gauge('mass', 'mass', 'Launch mass', FmtMass(A.WetKg) + ', no rocket', 0, 'bad', -1, '')
  else
  begin
    Tone := 'good';
    if (A.LvCapKg <= 0) or (A.WetKg > A.LvCapKg) then
      Tone := 'bad'
    else if A.MassMargin < 0.1 then
      Tone := 'warn';
    V := FmtMass(A.WetKg) + ' of ' + FmtMass(A.LvCapKg);
    Dl := Delta(A.WetKg - PrevA.WetKg, Signed(A.WetKg - PrevA.WetKg, FmtMass(Abs(A.WetKg - PrevA.WetKg))), True);
    if A.LvCapKg > 0 then
      Result := Result + Gauge('mass', 'mass', 'Launch mass', V, A.WetKg / A.LvCapKg, Tone, -1, Dl)
    else
      Result := Result + Gauge('mass', 'mass', 'Launch mass', FmtMass(A.WetKg) + ', cannot get there', 1, 'bad', -1, Dl);
  end;

  { power }
  Tone := 'good';
  if A.GenAvgW < A.LoadAvgW then
    Tone := 'bad'
  else if A.PowerMargin < 0.2 then
    Tone := 'warn';
  Dl := Delta(A.LoadAvgW - PrevA.LoadAvgW, Signed(A.LoadAvgW - PrevA.LoadAvgW, FmtPower(Abs(A.LoadAvgW - PrevA.LoadAvgW))), True);
  if A.GenAvgW > 0 then
    Result := Result + Gauge('power', 'bolt', 'Power', FmtPower(A.LoadAvgW) + ' of ' + FmtPower(A.GenAvgW), A.LoadAvgW / A.GenAvgW, Tone, -1, Dl)
  else
    Result := Result + Gauge('power', 'bolt', 'Power', FmtPower(A.LoadAvgW) + ' needed, none made', 1, 'bad', -1, Dl);

  { data }
  Tone := 'good';
  if A.DataReturn < 0.3 then
    Tone := 'bad'
  else if A.DataReturn < 0.8 then
    Tone := 'warn';
  Dl := Delta(A.DataReturn - PrevA.DataReturn, FmtSignedPct(A.DataReturn - PrevA.DataReturn), False);
  Result := Result + Gauge('data', 'data', 'Data sent home', FmtPct(A.DataReturn) + ' of ' + FmtData(A.GenGbitDay) + '/day', A.DataReturn, Tone, -1, Dl);

  { science }
  Tone := 'good';
  if A.SciencePct < Sc.ThresholdPct then
    Tone := 'bad'
  else if A.SciencePct < 85 then
    Tone := 'warn';
  Dl := Delta(A.SciencePct - PrevA.SciencePct, Signed(A.SciencePct - PrevA.SciencePct, FmtNum(Abs(A.SciencePct - PrevA.SciencePct), 0)), False);
  Result := Result + Gauge('science', 'flask', 'Predicted science', FmtNum(A.SciencePct, 0) + ' % of the goal', A.SciencePct / 120, Tone, Sc.ThresholdPct / 120, Dl);

  { schedule }
  Tone := 'good';
  if A.MissedDeadline then
    Tone := 'warn';
  Dl := Delta(A.DevYears - PrevA.DevYears, Signed(A.DevYears - PrevA.DevYears, FmtNum(Abs(A.DevYears - PrevA.DevYears), 1)) + ' y', True);
  if Sc.ArriveBy then
    Result := Result + Gauge('time', 'clock', 'Arrival', FmtYears(A.ArriveYear) + ', due in ' + FmtYears(Sc.DeadlineYears), A.ArriveYear / Sc.DeadlineYears, Tone, -1, Dl)
  else
    Result := Result + Gauge('time', 'clock', 'Ready to launch', FmtYears(A.LaunchYear) + ', due in ' + FmtYears(Sc.DeadlineYears), A.LaunchYear / Sc.DeadlineYears, Tone, -1, Dl);

  { odds }
  Tone := 'good';
  if A.SuccessProb < 0.6 then
    Tone := 'bad'
  else if A.SuccessProb < 0.8 then
    Tone := 'warn';
  Result := Result + Gauge('risk', 'shield', 'Chance of finishing', FmtPct(A.SuccessProb), A.SuccessProb, Tone, -1, '');
  Result := Result + '<p class="tiny muted" style="margin-top:8px">Click any gauge to see what is inside it.</p></div>';

  Result := Result + RippleText;

  Result := Result + '<div class="cv-box"><canvas id="cv-craft" width="680" height="460" role="img" aria-label="Blueprint of your spacecraft"></canvas>' +
    '<div class="cv-cap">Your spacecraft, drawn from the design. Purple boxes are instruments.</div></div>';

  if Players > 1 then
  begin
    Result := Result + '<div class="panel"><div class="panel-title">' + Icon('users') + '<h3>Crew goals</h3></div>';
    for R := Low(TRole) to High(TRole) do
    begin
      Result := Result + '<div class="row small" style="margin:5px 0;flex-wrap:nowrap;align-items:flex-start">';
      if RoleForecast(R, A, D) then
        Result := Result + Chip('chip-good', Icon('check'))
      else
        Result := Result + Chip('chip-bad', Icon('x'));
      Result := Result + '<span><b>' + Esc(RoleOwnerName(R)) + '</b> <span class="muted">(' + RoleShort[R] + ')</span>: ' + RoleGoalText(R) + '</span></div>';
    end;
    Result := Result + '</div>';
  end;

  Result := Result + '<div class="panel"><div class="panel-title">' + Icon('flag') + '<h3>What the review board will say</h3></div>';
  Shown := 0;
  for Sev := svBlock downto svWarn do
    for I := 0 to High(A.Findings) do
      if (A.Findings[I].Sev = Sev) and (Shown < 3) then
      begin
        Result := Result + '<div class="finding ' + SevClass(Sev) + '"><div class="finding-title"><span>' + A.Findings[I].Title +
          '</span></div><p class="fix">' + TabName[FindingTab(A.Findings[I].Code)] + ' tab</p></div>';
        Inc(Shown);
      end;
  if Shown = 0 then
    Result := Result + '<div class="finding f-good"><div class="finding-title">' + Icon('check') + '<span>The design closes</span></div>' +
      '<p>Mass, power, data, money and time all balance.</p></div>'
  else if A.Blockers + A.Warnings > Shown then
    Result := Result + '<p class="small muted" style="margin-top:8px">and ' + IntToStr(A.Blockers + A.Warnings - Shown) + ' more.</p>';
  Result := Result + '</div>';
end;

function ViewLab: string;
var
  Sc: TScenario;
begin
  Sc := Scenarios[Scen];
  Result := TopBar(1) + '<main class="wrap"><div class="row" style="margin-bottom:14px"><div class="planet planet-' + LowerCase(Sc.Body) +
    '" style="width:34px;height:34px"></div><div><h4>Design lab</h4><h2>' + Sc.Name + '</h2></div><span class="spacer"></span>' +
    Chip('', DifficultyName[Difficulty]);
  if Sandbox then
    Result := Result + Chip('chip-info', 'Sandbox');
  Result := Result + Btn('btn btn-ghost btn-small', 'brief', '', 'Briefing') + '</div>';
  if SharedNote <> '' then
    Result := Result + '<div class="finding f-info" style="margin-bottom:14px"><div class="finding-title">' + Icon('share') +
      '<span>' + Esc(SharedNote) + '</span></div></div>';
  Result := Result + '<div class="lab"><nav class="lab-nav" id="lab-nav" aria-label="Design steps">' + ViewLabNav + '</nav>' +
    '<section class="lab-main" id="lab-main">' + ViewLabMain + '</section>' +
    '<aside class="lab-dash" id="lab-dash" aria-label="Mission resources">' + ViewLabDash + '</aside></div></main>' + Footer;
end;

{ ---- review board ------------------------------------------------------ }

function ViewReview: string;
var
  Sc: TScenario;
  I: Integer;
  Sev: TSeverity;
  R: TRole;
  AllGo, CanLaunch: Boolean;
  List: string;
begin
  Sc := Scenarios[Scen];
  Result := TopBar(2) + '<main class="wrap"><h4>Mission review board</h4><h2>' + Sc.Name + '</h2>';
  if A.Blockers > 0 then
    Result := Result + '<div class="verdict nogo" style="margin-top:14px"><div class="verdict-word">NO-GO</div><div><h3>' +
      Plural(A.Blockers, 'thing', 'things') + ' must be fixed before this mission can be approved.</h3>' +
      '<p class="muted">Real missions go through reviews like this many times. Each finding below says what is wrong, why it matters and what to try.</p></div></div>'
  else
    Result := Result + '<div class="verdict go" style="margin-top:14px"><div class="verdict-word">GO</div><div><h3>The design is approved for flight' +
      IfThen(A.Warnings > 0, ', with ' + Plural(A.Warnings, 'warning', 'warnings') + '.', '.') + '</h3>' +
      '<p class="muted">You can launch now, or go back and squeeze out more science per dollar. You can fly the same mission as many times as you like.</p></div></div>';

  Result := Result + '<div class="two-col"><div>';
  List := '';
  for Sev := svBlock downto svGood do
    for I := 0 to High(A.Findings) do
      if A.Findings[I].Sev = Sev then
        List := List + FindingHtml(A.Findings[I], True);
  Result := Result + '<div class="panel"><div class="panel-title">' + Icon('list') + '<h3>Findings</h3></div>' + List + '</div></div><div>';

  Result := Result + '<div class="panel"><div class="panel-title">' + Icon('target') + '<h3>What to expect</h3></div><div class="numgrid">' +
    Num(FmtNum(A.SciencePct, 0) + ' %', 'of the science goal') +
    Num(FmtPct(A.SuccessProb), 'chance of finishing') +
    Num(FmtMoney(A.CostTotal), 'of a ' + FmtMoney(A.CapM) + ' cap') +
    Num(IfThen(A.LvCapKg > 0, FmtPct(A.MassMargin), 'none'), 'launch mass margin') +
    Num(FmtPct(A.PowerMargin), 'power margin') +
    Num(FmtPct(A.DataReturn), 'of data gets home') +
    '</div><p class="small muted" style="margin-top:10px">Minimum for success: ' + FmtNum(Sc.ThresholdPct, 0) +
    ' % of the science goal. Odds: launch ' + FmtPct(A.LaunchSuccess) + ', arrival ' + FmtPct(A.InsertSuccess) + ', each year in space ' +
    FmtPct(A.YearSurvival) + '.</p></div>';

  AllGo := True;
  if Players > 1 then
  begin
    Result := Result + '<div class="panel"><div class="panel-title">' + Icon('users') + '<h3>Go / no-go poll</h3></div>' +
      '<p class="small muted">Flight directors poll every position before a launch. Each of you must call GO. If your own goal is at risk, say so now and argue for a change.</p>';
    for R := Low(TRole) to High(TRole) do
    begin
      Result := Result + '<div class="poll-row"><div class="who">' + Chip('chip-' + RoleClass(R), RoleName[R]) + ' <b>' +
        Esc(RoleOwnerName(R)) + '</b><div class="small muted">' + RoleGoalText(R) + ' ';
      if RoleForecast(R, A, D) then
        Result := Result + '<span style="color:var(--good)">On course.</span>'
      else
        Result := Result + '<span style="color:var(--bad)">At risk.</span>';
      Result := Result + '</div></div>';
      if Votes[R] then
        Result := Result + Btn('btn btn-primary btn-small', 'vote', IntToStr(Ord(R)), Icon('check') + 'GO')
      else
      begin
        Result := Result + Btn('btn btn-small', 'vote', IntToStr(Ord(R)), 'Call GO');
        AllGo := False;
      end;
      Result := Result + '</div>';
    end;
    Result := Result + '</div>';
  end;
  CanLaunch := (A.Blockers = 0) and AllGo;
  Result := Result + '<div class="row" style="margin-top:14px">' + Btn('btn', 'backlab', '', Icon('back') + 'Back to the lab');
  if CanLaunch then
    Result := Result + Btn('btn btn-primary btn-big', 'fly', '', IconLg('rocket') + 'Build it and launch')
  else if A.Blockers > 0 then
    Result := Result + BtnOff('btn btn-primary btn-big', 'Fix the red findings first')
  else
    Result := Result + BtnOff('btn btn-primary btn-big', 'Waiting for every GO');
  Result := Result + '</div></div></div></main>' + Footer;
end;

{ ---- mission control --------------------------------------------------- }

function WhenText(const E: TSimEvent): string;
begin
  case E.Phase of
    spDevelopment: Result := 'Development';
    spLaunch: Result := 'Launch day';
    spCruise: Result := 'Cruise, week ' + IntToStr(E.Week);
    spArrival: Result := 'Arrival';
  else
    Result := 'Week ' + IntToStr(E.Week);
  end;
end;

function LogItemHtml(Idx: Integer): string;
var
  E: TSimEvent;
  Tn: string;
begin
  E := Sim.Log[Idx];
  case E.Tone of
    tnGood: Tn := 'tn-good';
    tnWarn: Tn := 'tn-warn';
    tnBad: Tn := 'tn-bad';
    tnReal: Tn := 'tn-real';
  else
    Tn := '';
  end;
  Result := '<div class="log-item ' + Tn + '"><div class="log-head"><span class="log-when">' + WhenText(E) + '</span>' +
    '<span class="log-title">' + E.Title + '</span>';
  if E.Tone = tnReal then
    Result := Result + Chip('chip-real', 'Real NASA data');
  if E.IsDecision then
    Result := Result + OwnerChip(E.Owner);
  Result := Result + '</div><p>' + E.Text + '</p>';
  if E.IsDecision then
    Result := Result + '<p class="decided"><b>Decision:</b> ' + E.Decision + '. ' + E.Outcome + '</p>';
  if E.Source <> '' then
    Result := Result + '<p class="src">' + E.Source + '</p>';
  if E.Lesson <> '' then
    Result := Result + '<p class="lesson">' + E.Lesson + '</p>';
  Result := Result + '</div>';
end;

function ViewMissionControls(Running, Done, InLaunch: Boolean; Speed: Integer): string;
var
  I: Integer;
  Cls: string;
begin
  if Done then
  begin
    Result := Btn('btn btn-primary btn-big', 'report', '', IconLg('trophy') + 'See the mission report');
    Exit;
  end;
  if InLaunch then
  begin
    Result := Btn('btn', 'skiplaunch', '', Icon('skip') + 'Skip the launch');
    Exit;
  end;
  if Running then
    Result := Btn('btn btn-primary', 'pause', '', Icon('pause') + 'Pause')
  else
    Result := Btn('btn btn-primary', 'play', '', Icon('play') + 'Run');
  Result := Result + '<div class="seg" role="group" aria-label="Speed">';
  for I := 1 to 3 do
  begin
    Cls := 'seg-btn';
    if I = Speed then
      Cls := Cls + ' on';
    case I of
      1: Result := Result + Btn(Cls, 'speed', '1', 'Slow');
      2: Result := Result + Btn(Cls, 'speed', '2', 'Fast');
    else
      Result := Result + Btn(Cls, 'speed', '3', 'Fastest');
    end;
  end;
  Result := Result + '</div><div class="progress" aria-hidden="true"><i id="m-prog"></i></div>';
end;

function ViewMissionSide: string;
var
  Sc: TScenario;
  I, N: Integer;
  Tone: string;
  V, Spent: Double;
begin
  Sc := Scenarios[Scen];
  Result := '<div class="panel"><div class="panel-title">' + Icon('target') + '<h3>' + PhaseName[Sim.Phase] + '</h3></div>';
  Tone := 'good';
  if Sim.SciencePct < Sc.ThresholdPct then
    Tone := 'warn';
  Result := Result + Gauge('science', 'flask', 'Science returned', FmtNum(Sim.SciencePct, 0) + ' % of the goal', Sim.SciencePct / 120, Tone, Sc.ThresholdPct / 120, '');
  N := Length(Sim.HistPower);
  if N > 0 then
  begin
    V := Sim.HistPower[N - 1] / 100;
    Tone := 'good';
    if V < 0.95 then
      Tone := 'warn';
    if V < 0.6 then
      Tone := 'bad';
    Result := Result + Gauge('power', 'bolt', 'Power available', FmtPct(V) + ' of what is needed', V, Tone, -1, '');
    V := 1;
    if Sim.GenGbit > 0 then
      V := Clamp(Sim.DownGbit / Sim.GenGbit, 0, 1);
    Tone := 'good';
    if V < 0.8 then
      Tone := 'warn';
    if V < 0.3 then
      Tone := 'bad';
    Result := Result + Gauge('data', 'data', 'Data sent home', FmtData(Sim.DownGbit) + ' (' + FmtPct(V) + ')', V, Tone, -1, '');
    V := Sim.HistStore[N - 1] / 100;
    Tone := 'good';
    if V > 0.9 then
      Tone := 'warn';
    Result := Result + Gauge('data', 'cpu', 'Recorder', FmtPct(V) + ' full', V, Tone, -1, '');
  end;
  if Sim.DvStart > 0 then
  begin
    V := Clamp(Sim.DvLeft / Sim.DvStart, 0, 1);
    Tone := 'good';
    if V < 0.1 then
      Tone := 'warn';
    Result := Result + Gauge('mass', 'rocket', 'Speed change left', FmtDv(Max(0, Sim.DvLeft)), V, Tone, -1, '');
  end;
  Spent := SimFinalCost(Sim);
  Tone := 'good';
  if Spent > Sim.A.CapM then
    Tone := 'bad';
  Result := Result + Gauge('cost', 'coin', 'Spent', FmtMoney(Spent) + ' of ' + FmtMoney(Sim.A.CapM), Spent / Sim.A.CapM, Tone, -1, '') + '</div>';

  Result := Result + '<div class="panel"><div class="panel-title">' + Icon('flask') + '<h3>Instruments</h3></div><div class="instr-list">';
  for I := 0 to High(Instruments) do
    if (I <= High(D.Instr)) and D.Instr[I] and InstrumentOffered(Scen, I) then
    begin
      if (I <= High(Sim.InstrAlive)) and Sim.InstrAlive[I] then
        Result := Result + '<div><span>' + Instruments[I].Name + '</span>' + Chip('chip-good', 'working') + '</div>'
      else
        Result := Result + '<div><span class="dead">' + Instruments[I].Name + '</span>' + Chip('chip-bad', 'lost') + '</div>';
    end;
  Result := Result + '</div>';
  if Sc.UsesEonet then
    Result := Result + '<p class="small" style="margin-top:10px"><b>' + IntToStr(Sim.EventsSeen) + '</b> real events observed so far.</p>';
  Result := Result + '</div>';
end;

function ViewMission: string;
var
  Sc: TScenario;
begin
  Sc := Scenarios[Scen];
  Result := TopBar(3) + '<main class="wrap"><div class="row" style="margin-bottom:12px"><div><h4>Mission control</h4><h2>' + Sc.Name +
    '</h2></div><span class="spacer"></span><span class="mono muted" id="m-clock"></span></div>' +
    '<div class="ops"><div><div class="stage"><canvas id="cv-main" width="1280" height="720" role="img" aria-label="Mission view"></canvas></div>' +
    '<div class="ops-controls" id="m-ctl"></div>' +
    '<div class="cv-box" id="m-chartbox" hidden><canvas id="cv-chart" width="1280" height="340" role="img" aria-label="Chart of science, power and data over time"></canvas></div>' +
    '<div class="section-head"><h3>Mission log</h3><span class="muted small">Newest first</span></div><div class="log" id="m-log"></div></div>' +
    '<aside id="m-side">' + ViewMissionSide + '</aside></div></main>' + Footer;
end;

{ ---- report ------------------------------------------------------------ }

function SBar(const AName: string; V, Weight: Double): string;
begin
  Result := '<div class="sbar"><span>' + AName + ' <span class="muted tiny">' + FmtPct(Weight) + '</span></span><div class="sbar-track"><div class="sbar-fill" style="width:' +
    FmtNum(Clamp(V, 0, 100), 0) + '%"></div></div><span class="mono">' + FmtNum(V, 0) + '</span></div>';
end;

function ViewReport: string;
var
  Sc: TScenario;
  I: Integer;
  R: TRole;
  Stars: string;
begin
  Sc := Scenarios[Scen];
  Stars := '';
  for I := 1 to 5 do
    if I <= Card.Stars then
      Stars := Stars + '&#9733;'
    else
      Stars := Stars + '<i>&#9733;</i>';
  Result := TopBar(4) + '<main class="wrap"><div class="panel"><div class="report-head">' +
    '<div class="grade"><b>' + Card.Grade + '</b><span>grade</span></div><div><h4>' + Sc.Name + ' &middot; mission report</h4>' +
    '<h2>' + Card.Outcome + '</h2><p class="lead" style="margin-top:4px">' + Card.OutcomeText + '</p>' +
    '<p style="margin-top:8px"><span class="stars">' + Stars + '</span> <b class="mono" style="font-size:20px;margin-left:8px">' +
    IntToStr(Card.Total) + '</b> <span class="muted">of 1,000 &middot; ' + Card.Title + '</span></p></div></div></div>';

  Result := Result + '<div class="two-col"><div>' +
    '<div class="panel"><div class="panel-title">' + Icon('list') + '<h3>What happened, and why</h3></div>';
  for I := 0 to High(Card.Insights) do
  begin
    Result := Result + '<div class="insight ' + SevClass(Card.Insights[I].Tone) + '"><b>' + Card.Insights[I].Title + '</b><p>' +
      Card.Insights[I].Text + '</p>';
    if Card.Insights[I].Tip <> '' then
      Result := Result + '<p class="tip"><b>Next time:</b> ' + Card.Insights[I].Tip + '</p>';
    Result := Result + '</div>';
  end;
  Result := Result + '</div>';
  if Length(Sim.HistScience) > 2 then
    Result := Result + '<div class="panel"><div class="panel-title">' + Icon('target') + '<h3>The mission, week by week</h3></div>' +
      '<div class="cv-box"><canvas id="cv-chart" width="1280" height="340" role="img" aria-label="Chart of science, power and data over time"></canvas></div></div>';
  if Card.Analog >= 0 then
    Result := Result + '<div class="panel"><div class="panel-title">' + Icon('rocket') + '<h3>The real mission most like yours</h3></div><p>' +
      Card.AnalogText + '</p><p class="muted" style="margin-top:6px">' + Sc.Analogs[Card.Analog].Blurb + ' ' +
      Link(Sc.Analogs[Card.Analog].Url, 'Read about it') + '</p></div>';
  Result := Result + '</div><div>';

  Result := Result + '<div class="panel"><div class="panel-title">' + Icon('trophy') + '<h3>Score</h3></div>' +
    SBar('Science', Card.Science, ScoreWeightScience) + SBar('Survival', Card.Survival, ScoreWeightSurvival) +
    SBar('Budget', Card.Budget, ScoreWeightBudget) + SBar('Engineering', Card.Engineering, ScoreWeightEngineering) +
    SBar('Value for money', Card.Efficiency, ScoreWeightEfficiency) +
    '<div class="numgrid" style="margin-top:12px">' +
    Num(FmtNum(Card.SciencePct, 0) + ' %', 'of the science goal') +
    Num(FmtMoney(Card.FinalCostM), 'spent, cap ' + FmtMoney(Card.CapM)) +
    Num(FmtYears(Card.YearsFlown), 'of science flown') +
    Num(FmtPct(Card.ReturnFrac), 'of data sent home');
  if Sc.UsesEonet then
    Result := Result + Num(IntToStr(Sim.EventsSeen), 'real events observed');
  Result := Result + '</div></div>';

  if Players > 1 then
  begin
    Result := Result + '<div class="panel"><div class="panel-title">' + Icon('users') + '<h3>Crew goals: ' + IntToStr(Card.RolesMet) +
      ' of 4 met</h3></div>';
    for R := Low(TRole) to High(TRole) do
    begin
      Result := Result + '<div class="poll-row"><div class="who">' + Chip('chip-' + RoleClass(R), RoleName[R]) + ' <b>' +
        Esc(RoleOwnerName(R)) + '</b><div class="small muted">' + RoleGoalText(R) + '</div><div class="small">' + Card.RoleResult[R] + '</div></div>';
      if Card.RoleMet[R] then
        Result := Result + Chip('chip-good', Icon('check') + 'Met')
      else
        Result := Result + Chip('chip-bad', Icon('x') + 'Missed');
      Result := Result + '</div>';
    end;
    Result := Result + '</div>';
  end;

  Result := Result + '<div class="panel"><div class="panel-title">' + Icon('redo') + '<h3>What next?</h3></div><div class="stack">' +
    Btn('btn btn-primary', 'improve', '', Icon('wrench') + 'Improve this design and fly again') +
    Btn('btn', 'refly', '', Icon('redo') + 'Fly the same design again (new luck)') +
    Btn('btn', 'share', '', Icon('share') + 'Challenge someone with this design') +
    Btn('btn', 'log', '', Icon('trophy') + 'Mission log and rankings') +
    Btn('btn', 'start', '', Icon('rocket') + 'Start a different mission') + '</div></div>';
  Result := Result + '</div></div>';

  Result := Result + '<div class="section-head"><h3>Full mission log</h3></div><div class="log">';
  for I := High(Sim.Log) downto 0 do
    Result := Result + LogItemHtml(I);
  Result := Result + '</div></main>' + Footer;
end;

{ ---- mission log ------------------------------------------------------- }

function ViewLog: string;
var
  L: TLogEntryArray;
  I, J, T: Integer;
  Order: array of Integer;
begin
  L := LoadLog;
  Result := TopBar(-1) + '<main class="wrap"><div class="row"><div><h4>Mission log</h4><h2>Every mission flown on this device</h2></div>' +
    '<span class="spacer"></span>' + Btn('btn', 'start', '', Icon('rocket') + 'Start a mission') + '</div>';
  if Length(L) = 0 then
  begin
    Result := Result + '<div class="panel" style="margin-top:16px"><p>No missions flown yet. Your results will be ranked here, best first, ' +
      'so you can compare designs and crews.</p></div></main>' + Footer;
    Exit;
  end;
  SetLength(Order, Length(L));
  for I := 0 to High(L) do
    Order[I] := I;
  for I := 0 to High(Order) - 1 do
    for J := I + 1 to High(Order) do
      if L[Order[J]].Score > L[Order[I]].Score then
      begin
        T := Order[I];
        Order[I] := Order[J];
        Order[J] := T;
      end;
  Result := Result + '<div class="panel" style="margin-top:16px"><div class="tbl-scroll"><table class="tbl"><tr><th>Rank</th><th>Mission</th><th>Crew</th>' +
    '<th class="n">Score</th><th>Grade</th><th class="n">Science</th><th class="n">Cost</th><th>Result</th><th>Date</th><th></th></tr>';
  for I := 0 to High(Order) do
  begin
    J := Order[I];
    Result := Result + '<tr><td class="n">' + IntToStr(I + 1) + '</td><td>' + Esc(L[J].ScenarioName) + '</td><td>' + Esc(L[J].Crew) +
      '</td><td class="n"><b>' + IntToStr(L[J].Score) + '</b></td><td>' + Esc(L[J].Grade) + '</td><td class="n">' + FmtNum(L[J].SciencePct, 0) +
      ' %</td><td class="n">' + FmtMoney(L[J].CostM) + '</td><td>' + Esc(L[J].Outcome) + '</td><td>' + Esc(L[J].Date) + '</td><td>' +
      Btn('btn btn-small', 'loadlog', IntToStr(J), 'Open design') + '</td></tr>';
  end;
  Result := Result + '</table></div><div class="row" style="margin-top:14px">' +
    '<span class="muted small">Saved in this browser only. Send someone a design with Share, then compare scores on the same mission.</span><span class="spacer"></span>' +
    Btn('btn btn-danger btn-small', 'clearlog', '', 'Clear the log') + '</div></div></main>' + Footer;
end;

{ ---- modals ------------------------------------------------------------ }

function ModalShell(const Title, Body: string; Wide: Boolean): string;
begin
  Result := '<div class="modal';
  if Wide then
    Result := Result + ' wide';
  Result := Result + '" role="dialog" aria-modal="true" aria-label="' + Title + '"><div class="modal-head"><h2>' + Title + '</h2>' +
    Btn('btn btn-ghost btn-small', 'close', '', Icon('x') + 'Close') + '</div>' + Body + '</div>';
end;

function ModalHelp: string;
begin
  Result := ModalShell('How to play',
    '<p>You are a mission design team. A space agency has asked for a mission and set a cost cap and a deadline. ' +
    'Your job is to return as much science as you can without breaking either.</p>' +
    '<dl class="gloss">' +
    '<dt>1. Read the briefing</dt><dd>It says what the science team wants measured and what makes this destination hard.</dd>' +
    '<dt>2. Design in the lab</dt><dd>Work through the seven tabs: orbit, payload, spacecraft, power, comms, launch and plan. ' +
    'The gauges on the right show cost, mass, power, data, science and schedule. Change one thing and watch the others move. That ripple is the whole game.</dd>' +
    '<dt>3. Go to the review board</dt><dd>It lists what would stop the mission (red) and what might hurt it (amber), and explains each one. Fix the red ones. Decide which amber ones you can live with.</dd>' +
    '<dt>4. Fly</dt><dd>Things go wrong during development and in flight, some of them real solar storms from NASA records. You will be asked to decide.</dd>' +
    '<dt>5. Read the report</dt><dd>It tells you why the mission scored what it did and which real mission yours resembles. Then improve the design and fly again.</dd>' +
    '<dt>Playing as a crew</dt><dd>Two to four players share one screen. Each owns some of the tabs and has a personal goal. ' +
    'The science lead wants more instruments, the engineer wants margin, the operations lead wants every bit sent home and the project manager wants it on budget. You have to negotiate.</dd>' +
    '<dt>There is no single right answer</dt><dd>A small, cheap spacecraft and a big, capable one can both score well. Try both.</dd></dl>' +
    '<div class="row" style="margin-top:16px">' + Btn('btn btn-primary', 'close', '', 'Got it') + '</div>', True);
end;

function ModalGlossary: string;
var
  I: Integer;
  S: string;
begin
  S := '<p class="muted">Plain-language meanings of the terms used in the game.</p><dl class="gloss">';
  for I := 0 to High(Glossary) do
    S := S + '<dt>' + Glossary[I].Term + '</dt><dd>' + Glossary[I].Plain + '</dd><dd class="why">' + Glossary[I].Why + '</dd>';
  S := S + '</dl>';
  Result := ModalShell('Glossary', S, True);
end;

function ModalAbout: string;
begin
  Result := ModalShell('About Atomic Space',
    '<p>Atomic Space was built for the 2026 NASA Space Apps Challenge, &ldquo;Space Mission Design Game&rdquo;. It is not affiliated with or endorsed by NASA.</p>' +
    '<p>The whole game is written in Object Pascal (the Delphi language) and compiled for the browser with the open-source pas2js compiler.</p>' +
    '<dl class="gloss"><dt>NASA data used while you play</dt>' +
    '<dd>' + Link('https://eonet.gsfc.nasa.gov/', 'EONET') + ': real natural events are the targets and set the science priorities of Disaster Watch.</dd>' +
    '<dd>' + Link('https://ccmc.gsfc.nasa.gov/tools/DONKI/', 'DONKI') + ': real solar flares, particle storms and geomagnetic storms strike your spacecraft.</dd>' +
    '<dd>' + Link('https://api.nasa.gov/', 'NeoWs') + ' and JPL: the real 2029 Apophis flyby sets the deadline of Race to Apophis.</dd>' +
    '<dd>' + Link('https://www.earthdata.nasa.gov/engage/open-data-services-software/earthdata-developer-portal/gibs-api', 'GIBS') + ': the Blue Marble world map.</dd>' +
    '<dd>NASA image KSC-08pd1628 (sunset over the Kennedy Space Center turn basin): the launch sky and clouds.</dd>' +
    '<dt>NASA resources that shaped the design</dt>' +
    '<dd>' + Link('https://www.nasa.gov/wp-content/uploads/2025/04/250323-design-and-develop-science-mission.pdf', 'Design and Develop Science Missions') +
    ', JPL ' + Link('https://dataverse.jpl.nasa.gov/dataset.xhtml?persistentId=hdl:2014/44299', 'Concept Maturity Levels') + ', the ' +
    Link('https://etd.gsfc.nasa.gov/capabilities/integrated-design-center/mission-design-lab/', 'Goddard Mission Design Lab') + ', ' +
    Link('https://software.nasa.gov/software/GSC-19468-1', 'GMAT') + ', ' + Link('https://nasa.github.io/mission-viz/', 'Mission Viz') + ', ' +
    Link('https://www3.nasa.gov/sites/default/files/atoms/files/nasa_csli_cubesat_101_508.pdf', 'CubeSat 101') + ' and the Webb ' +
    Link('https://science.nasa.gov/mission/webb/game-build-it-yourself/', 'Build It Yourself') + ' game.</dd>' +
    '<dt>Space agency partners</dt><dd>Rockets, missions and instruments from ISRO, ESA, JAXA, CSA, ASI, KASA and the UAE appear throughout, with links to their mission pages.</dd>' +
    '<dt>Numbers</dt><dd>Masses, costs, data rates and rocket capacities are simplified from public figures and rounded for teaching. They are not engineering data.</dd>' +
    '<dt>Use of AI</dt><dd>The program code, the in-game text and the code that draws the graphics were written with the help of Claude, an AI model made by Anthropic. ' +
    'No AI-generated images, audio or video are used: every picture is drawn by the game from the numbers in your design, or is a NASA photograph.</dd></dl>', True);
end;

function LinesTable(const L: TLineArray; const Head, UnitName: string; Dec: Integer): string;
var
  I: Integer;
  Sum: Double;
begin
  Sum := 0;
  Result := '<table class="tbl"><tr><th>' + Head + '</th><th class="n">' + UnitName + '</th></tr>';
  for I := 0 to High(L) do
  begin
    Result := Result + '<tr><td>' + L[I].Name + '</td><td class="n">' + FmtNum(L[I].Value, Dec) + '</td></tr>';
    Sum := Sum + L[I].Value;
  end;
  Result := Result + '<tr><td><b>Total</b></td><td class="n"><b>' + FmtNum(Sum, Dec) + '</b></td></tr></table>';
end;

function ModalBreakdown(const Which: string): string;
var
  Sc: TScenario;
  O: TOrbit;
  M: TMeasure;
  S: string;
begin
  Sc := Scenarios[Scen];
  O := Sc.Orbits[D.Orbit];
  if Which = 'cost' then
    Result := ModalShell('Where the money goes',
      LinesTable(A.CostLines, 'Item', '$ million', 1) + '<p class="lesson">The cap is ' + FmtMoney(A.CapM) +
      '. Management, assembly and test add about 23 % to the hardware. Operations are paid every year the mission flies. ' +
      'Reserves are only spent if something goes wrong.</p>', False)
  else if Which = 'mass' then
    Result := ModalShell('Where the mass goes',
      LinesTable(A.MassLines, 'Item', 'kg', 1) + '<p class="lesson">Propellant comes from the rocket equation: to change speed by ' + FmtDv(A.DvNeed) +
      ' the spacecraft must burn a fixed share of its own mass. Add 1 kg of equipment and the propellant grows too. ' +
      IfThen(A.LvCapKg > 0, 'Your rocket can send ' + FmtMass(A.LvCapKg) + ' to ' + LaunchTargetName(D) + '.', 'No rocket has been chosen yet.') + '</p>', False)
  else if Which = 'power' then
    Result := ModalShell('Where the power goes',
      LinesTable(A.PowerLines, 'Load', 'watts', 0) + '<p class="lesson">The array makes ' + FmtPower(A.SolarW) + ' in full sun here' +
      IfThen(A.RtgW > 0, ', plus ' + FmtPower(A.RtgW) + ' from nuclear batteries', '') + '. With ' + FmtPct(O.EclipseFrac) +
      ' of each orbit in shadow and the battery to refill, that averages ' + FmtPower(A.GenAvgW) + '. Margin: ' + FmtPct(A.PowerMargin) + '.</p>', False)
  else if Which = 'data' then
    Result := ModalShell('The data link',
      '<div class="numgrid">' + Num(FmtData(A.GenGbitDay), 'recorded a day') + Num(FmtRate(A.RateAvgMbps), 'typical rate') +
      Num(FmtRate(A.RateMinMbps), 'slowest rate') + Num(FmtNum(A.ContactHr, 1) + ' h', 'contact a day') + Num(FmtData(A.DownGbitDay), 'sent a day') +
      Num(FmtData(A.StorageGbit), 'recorder size') + Num(FmtNum(A.LightDelayMin, 1) + ' min', 'signal travel time') + '</div>' +
      '<p class="lesson">Rate = transmitter power &times; dish area &times; band &times; ground antenna, divided by distance squared. ' +
      'Twice as far means a quarter of the data. The recorder bridges the gaps between contacts.</p>', False)
  else if Which = 'science' then
  begin
    S := '<table class="tbl"><tr><th>Measurement</th><th class="n">Wanted</th><th class="n">Your payload</th></tr>';
    for M := Low(TMeasure) to High(TMeasure) do
      if Sc.Weight[M] >= 0.1 then
        S := S + '<tr><td>' + MeasureName[M] + '</td><td class="n">' + PriorityWord(Sc.Weight[M]) + '</td><td class="n">' +
          FmtNum(A.Capability[M], 0) + '</td></tr>';
    S := S + '</table><p class="lesson">Your payload could reach ' + FmtNum(A.ScienceMaxPct, 0) + ' % of the goal given unlimited time. In ' +
      FmtYears(Min(D.LifeYears, A.LifeLimitYears)) + ' it should reach ' + FmtNum(A.SciencePct, 0) +
      ' %. Too little power or a data bottleneck slows it down. The minimum for success is ' + FmtNum(Sc.ThresholdPct, 0) + ' %.</p>';
    Result := ModalShell('Predicted science', S, False);
  end
  else if Which = 'time' then
    Result := ModalShell('The schedule',
      '<div class="numgrid">' + Num(FmtYears(A.DevYears), 'to build and test') + Num(FmtYears(A.LaunchYear), 'until launch') +
      Num(FmtYears(A.CruiseYears), 'travelling') + Num(FmtYears(A.ArriveYear), 'until arrival') + Num(FmtYears(D.LifeYears), 'of science planned') + '</div>' +
      '<p class="lesson">' + DeadlineText(Sc) + '. Bigger buses and complicated instruments take longer to build. ' +
      IfThen(Sc.WindowYears > 0, 'Launch windows to ' + Sc.Body + ' open every ' + FmtYears(Sc.WindowPeriod) + '. ', '') +
      'An accelerated schedule buys time with money and risk.</p>', False)
  else
    Result := ModalShell('The odds',
      '<div class="numgrid">' + Num(FmtPct(A.LaunchSuccess), 'launch') + Num(FmtPct(A.InsertSuccess), 'arrival') +
      Num(FmtPct(A.YearSurvival), 'each year in space') + Num(FmtNum(A.AnomalyRate, 2), 'faults expected a year') +
      Num(FmtPct(A.SuccessProb), 'finishing the whole plan') + '</div>' +
      '<p class="lesson">The chances multiply. A more proven rocket, a higher risk class with more backups, and proper radiation protection all raise them. ' +
      'About one fault in five ends a mission. The rest cost you an instrument, your pointing or a few weeks in safe mode.</p>', False);
end;

function ModalDecision: string;
var
  E: TSimEvent;
  I: Integer;
  S: string;
begin
  E := Sim.Pending;
  S := '';
  if Players > 1 then
    S := '<p>' + Chip('chip-' + RoleClass(E.Owner), RoleName[E.Owner]) + ' <b>' + Esc(RoleOwnerName(E.Owner)) + ', this one is yours.</b> Talk it over, then decide.</p>';
  S := S + '<p>' + E.Text + '</p>';
  if E.Source <> '' then
    S := S + '<p>' + Chip('chip-real', 'Real NASA data') + ' <span class="small muted">' + E.Source + '</span></p>';
  S := S + '<div class="choices">';
  for I := 0 to High(E.Choices) do
    S := S + '<button type="button" class="choice" data-act="choose" data-a="' + IntToStr(I) + '"><b>' + E.Choices[I].Text + '</b><span>' +
      E.Choices[I].Hint + '</span></button>';
  S := S + '</div>';
  if E.Lesson <> '' then
    S := S + '<p class="lesson">' + E.Lesson + '</p>';
  Result := '<div class="modal" role="dialog" aria-modal="true" aria-label="' + E.Title + '"><div class="modal-head"><h2>' + E.Title +
    '</h2>' + Chip('chip-warn', 'Decision') + '</div>' + S + '</div>';
end;

function ModalOutcome(Idx: Integer): string;
var
  E: TSimEvent;
  Cls: string;
begin
  E := Sim.Log[Idx];
  case E.Tone of
    tnGood: Cls := 'f-good';
    tnBad: Cls := 'f-block';
  else
    Cls := 'f-info';
  end;
  Result := '<div class="modal" role="dialog" aria-modal="true" aria-label="Outcome"><div class="modal-head"><h2>' + E.Title + '</h2></div>' +
    '<p class="muted">You chose: ' + E.Decision + '</p><div class="finding ' + Cls + '" style="margin-top:10px"><p style="margin:0">' + E.Outcome +
    '</p></div><div class="row" style="margin-top:16px">' + Btn('btn btn-primary', 'resume', '', 'Carry on ' + Icon('next')) + '</div></div>';
end;

function ModalShare(const Url: string): string;
begin
  Result := ModalShell('Share this design',
    '<p>Anyone who opens this link gets your exact design and the same run of luck, so you can compare scores on equal terms.</p>' +
    '<p><input type="text" readonly id="share-url" value="' + Esc(Url) + '" style="width:100%;background:var(--bg);color:var(--text);' +
    'border:1px solid var(--line2);border-radius:8px;padding:10px;font:13px var(--mono)" aria-label="Link to this design"></p>' +
    '<div class="row" style="margin-top:12px">' + Btn('btn btn-primary', 'copyshare', '', Icon('share') + 'Copy the link') + '</div>', False);
end;

end.
