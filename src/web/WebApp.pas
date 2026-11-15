unit WebApp;

{ Atomic Space - the controller: reacts to clicks and sliders, moves between
  screens, runs the animation loop and steps the mission simulation.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$mode objfpc}

interface

uses
  JS, Web, SysUtils, Math, TsTypes;

type
  TGame = class
  private
    FRunning: Boolean;
    FSpeed: Integer;
    FLaunching: Boolean;
    FLaunchT0: Double;
    FLaunchFail: Boolean;
    FLaunchSize: Integer;
    FShownLog: Integer;
    FAccum: Double;
    FLastMs: Double;
    FTick: Integer;
    FModalKind: string;
    FMissionDone: Boolean;
    FKeepSeed: Boolean;
    FShareUrl: string;
    function OnClick(Ev: TEventListenerEvent): Boolean;
    function OnInput(Ev: TEventListenerEvent): Boolean;
    function OnChange(Ev: TEventListenerEvent): Boolean;
    function OnKey(Ev: TEventListenerEvent): Boolean;
    function OnResize(Ev: TEventListenerEvent): Boolean;
    procedure Frame(aTime: TJSDOMHighResTimeStamp);
    procedure MissionFrame(Ms: Double);
    procedure Render;
    procedure RenderLab(WithMain: Boolean);
    procedure DrawStatics;
    procedure OpenModal(const Html, Kind: string);
    procedure CloseModal;
    procedure Go(S: Integer);
    procedure DoAction(const Act, Arg: string);
    procedure EnterLab;
    procedure StartMission;
    procedure StepSim;
    procedure RefreshMission;
    procedure SyncLog;
    procedure SetControls;
    procedure EndLaunch;
    procedure FinishMission;
    procedure DataChanged;
    procedure LoadFromHash;
    procedure UseDesign(const Code, Note: string);
    procedure ShareDesign;
  public
    procedure Start;
  end;

implementation

uses
  WebUtil, WebState, WebStore, WebNasa, WebDraw, WebViews, TsFmt, TsCatalog,
  TsScenarios, TsEngine, TsSim, TsScore, TsExamples;

{ ---- start-up ---------------------------------------------------------- }

procedure TGame.Start;
var
  I: Integer;
  S: string;
begin
  FSpeed := 1;
  FModalKind := '';
  LoadImages;
  DrawStars;
  for I := 0 to 3 do
  begin
    S := LoadSetting('player' + IntToStr(I), '');
    if S <> '' then
      PlayerName[I] := S;
  end;
  I := StrToIntDef(LoadSetting('difficulty', '1'), 1);
  if (I >= 0) and (I <= 2) then
    Difficulty := TDifficulty(I);
  document.addEventListener('click', @OnClick);
  document.addEventListener('input', @OnInput);
  document.addEventListener('change', @OnChange);
  document.addEventListener('keydown', @OnKey);
  window.addEventListener('resize', @OnResize);
  LoadNasaData(@DataChanged);
  LoadFromHash;
  Render;
  window.requestAnimationFrame(@Frame);
end;

procedure TGame.LoadFromHash;
var
  H: string;
  P: Integer;
begin
  H := window.location.hash;
  P := Pos('m=', H);
  if P > 0 then
    UseDesign(Copy(H, P + 2, Length(H)), 'A shared design was loaded. Fly it as it is to compare scores on equal terms, or try to improve it.');
end;

procedure TGame.UseDesign(const Code, Note: string);
var
  E: TDesign;
begin
  if not DecodeDesign(Code, E) then
  begin
    Toast('That design link could not be read.');
    Exit;
  end;
  D := E;
  Scen := D.Scenario;
  Difficulty := D.Difficulty;
  Sandbox := D.Sandbox;
  HasDesign := False;
  HasPrev := False;
  Recalc;
  HasPrev := False;
  SharedNote := Note;
  FKeepSeed := True;
  LabTab := 0;
  Screen := scLab;
end;

procedure TGame.DataChanged;
begin
  { New NASA data has arrived: the Earth scenario's priorities and orbit
    coverage may have changed. }
  if HasDesign then
  begin
    A := Analyze(D);
    HasPrev := False;
  end;
  { The setup screen is left alone so a name being typed is not interrupted. }
  if (Screen = scTitle) or (Screen = scBrief) then
    Render
  else if Screen = scLab then
    RenderLab(True);
end;

{ ---- rendering --------------------------------------------------------- }

procedure TGame.Render;
var
  Html: string;
begin
  case Screen of
    scTitle: Html := ViewTitle;
    scSetup: Html := ViewSetup;
    scBrief: Html := ViewBrief;
    scLab: Html := ViewLab;
    scReview: Html := ViewReview;
    scMission: Html := ViewMission;
    scReport: Html := ViewReport;
  else
    Html := ViewLog;
  end;
  SetHtml('app', Html);
  if Screen = scMission then
  begin
    FShownLog := 0;
    SetHtml('m-log', '');
    if not FLaunching then
      SyncLog;
    SetControls;
    RefreshMission;
  end;
  DrawStatics;
end;

procedure TGame.RenderLab(WithMain: Boolean);
begin
  SetHtml('lab-nav', ViewLabNav);
  if WithMain then
    SetHtml('lab-main', ViewLabMain);
  SetHtml('lab-dash', ViewLabDash);
  DrawStatics;
end;

procedure TGame.DrawStatics;
var
  Ctx: TCtx;
begin
  if Prep('cv-map', 640, 320, Ctx) then
    DrawEarthMap(Ctx, 640, 320, D, (Screen = scLab) and HasDesign);
  if (Screen = scLab) and Prep('cv-craft', 340, 230, Ctx) then
    DrawCraft(Ctx, 340, 230, D, A);
  if HasSim and Prep('cv-chart', 640, 170, Ctx) then
    DrawChart(Ctx, 640, 170, Sim);
end;

procedure TGame.Go(S: Integer);
begin
  Screen := TScreen(S);
  Render;
  ScrollTop;
end;

procedure TGame.OpenModal(const Html, Kind: string);
var
  M: TJSHTMLElement;
begin
  M := El('modal');
  if M = nil then
    Exit;
  M.innerHTML := Html;
  M.hidden := False;
  FModalKind := Kind;
end;

procedure TGame.CloseModal;
var
  M: TJSHTMLElement;
begin
  M := El('modal');
  if M <> nil then
  begin
    M.hidden := True;
    M.innerHTML := '';
  end;
  FModalKind := '';
end;

{ ---- events ------------------------------------------------------------ }

function TGame.OnClick(Ev: TEventListenerEvent): Boolean;
var
  T: TJSElement;
begin
  Result := True;
  if not (Ev.target is TJSElement) then
    Exit;
  T := TJSElement(Ev.target).closest('[data-act]');
  if T = nil then
  begin
    { A click on the dark area outside a dialog closes it, except decisions. }
    if (FModalKind = 'info') and (TJSElement(Ev.target).id = 'modal') then
      CloseModal;
    Exit;
  end;
  if T.hasAttribute('disabled') then
    Exit;
  { A missing attribute comes back as null, not as an empty string. }
  if T.hasAttribute('data-a') then
    DoAction(T.getAttribute('data-act'), T.getAttribute('data-a'))
  else
    DoAction(T.getAttribute('data-act'), '');
end;

function TGame.OnInput(Ev: TEventListenerEvent): Boolean;
var
  T: TJSHTMLInputElement;
  Name: string;
  V: Double;
  I: Integer;
begin
  Result := True;
  if not (Ev.target is TJSElement) then
    Exit;
  if not TJSElement(Ev.target).hasAttribute('data-in') then
    Exit;
  T := TJSHTMLInputElement(Ev.target);
  Name := T.getAttribute('data-in');
  if Name = 'pname' then
  begin
    I := StrToIntDef(T.getAttribute('data-a'), 0);
    if (I >= 0) and (I <= 3) then
    begin
      PlayerName[I] := Trim(T.value);
      if PlayerName[I] = '' then
        PlayerName[I] := 'Player ' + IntToStr(I + 1);
      SaveSetting('player' + IntToStr(I), PlayerName[I]);
    end;
    Exit;
  end;
  if (Name = 'sandbox') or not HasDesign then
    Exit;
  V := ParseFloat(T.value);
  if Name = 'solar' then
  begin
    D.SolarM2 := V;
    SetText('val-solar', FmtNum(V, 1) + ' m2');
  end
  else if Name = 'battery' then
  begin
    D.BatteryWh := V;
    SetText('val-battery', FmtNum(V, 0) + ' Wh');
  end
  else if Name = 'life' then
  begin
    D.LifeYears := V;
    SetText('val-life', FmtYears(V));
  end
  else if Name = 'reserve' then
  begin
    D.ReservePct := V;
    SetText('val-reserve', FmtNum(V, 0) + ' %');
  end
  else
    Exit;
  Recalc;
  { Leave the slider itself alone so it keeps hold of the pointer. }
  SetHtml('power-info', PowerInfo);
  SetHtml('plan-info', PlanInfo);
  RenderLab(False);
end;

function TGame.OnChange(Ev: TEventListenerEvent): Boolean;
var
  T: TJSHTMLInputElement;
  Name: string;
begin
  Result := True;
  if not (Ev.target is TJSElement) then
    Exit;
  if not TJSElement(Ev.target).hasAttribute('data-in') then
    Exit;
  T := TJSHTMLInputElement(Ev.target);
  Name := T.getAttribute('data-in');
  if Name = 'sandbox' then
  begin
    Sandbox := T.checked;
    Render;
  end
  else if (Name = 'solar') or (Name = 'battery') or (Name = 'life') or (Name = 'reserve') then
    RenderLab(True);  // slider released: refresh the findings in the tab too
end;

function TGame.OnKey(Ev: TEventListenerEvent): Boolean;
var
  K: string;
begin
  Result := True;
  K := TJSKeyboardEvent(Ev).key;
  if (K = 'Escape') and (FModalKind = 'info') then
    CloseModal;
end;

function TGame.OnResize(Ev: TEventListenerEvent): Boolean;
begin
  Result := True;
  DrawStars;
end;

procedure TGame.EnterLab;
begin
  if not (HasDesign and (D.Scenario = Scen) and (D.Difficulty = Difficulty) and (D.Sandbox = Sandbox)) then
  begin
    D := NewDesign(Scen, Difficulty, Sandbox);
    HasDesign := False;
    HasPrev := False;
    Recalc;
    HasPrev := False;
    SharedNote := '';
    LabTab := 0;
  end;
  Go(Ord(scLab));
end;

procedure TGame.ShareDesign;
var
  Base: string;
  P: Integer;
begin
  Base := window.location.href;
  P := Pos('#', Base);
  if P > 0 then
    Base := Copy(Base, 1, P - 1);
  FShareUrl := Base + '#m=' + EncodeDesign(D);
  OpenModal(ModalShare(FShareUrl), 'info');
end;

procedure TGame.DoAction(const Act, Arg: string);
var
  N, K, I, P: Integer;
  L: TLogEntryArray;
  Code: string;
begin
  N := StrToIntDef(Arg, 0);

  { ---- moving between screens ---- }
  if Act = 'home' then
  begin
    CloseModal;
    FRunning := False;
    FLaunching := False;
    Go(Ord(scTitle));
  end
  else if Act = 'start' then
  begin
    FRunning := False;
    FLaunching := False;
    Go(Ord(scSetup));
  end
  else if Act = 'scen' then
  begin
    if (N >= 0) and (N <= High(Scenarios)) then
      Scen := N;
    Render;
  end
  else if Act = 'diff' then
  begin
    if (N >= 0) and (N <= 2) then
      Difficulty := TDifficulty(N);
    SaveSetting('difficulty', IntToStr(N));
    Render;
  end
  else if Act = 'players' then
  begin
    if (N >= 1) and (N <= 4) then
      Players := N;
    Render;
  end
  else if Act = 'brief' then
    Go(Ord(scBrief))
  else if Act = 'lab' then
    EnterLab
  else if (Act = 'backlab') or (Act = 'improve') then
  begin
    FRunning := False;
    HasPrev := False;
    SharedNote := '';
    Go(Ord(scLab));
  end
  else if Act = 'review' then
  begin
    ResetVotes;
    Go(Ord(scReview));
  end
  else if Act = 'vote' then
  begin
    if (N >= 0) and (N <= Ord(High(TRole))) then
      Votes[TRole(N)] := not Votes[TRole(N)];
    Render;
  end
  else if (Act = 'fly') or (Act = 'refly') then
    StartMission
  else if Act = 'report' then
    Go(Ord(scReport))
  else if Act = 'log' then
  begin
    FRunning := False;
    Go(Ord(scLog));
  end
  else if Act = 'loadlog' then
  begin
    L := LoadLog;
    if (N >= 0) and (N <= High(L)) then
    begin
      UseDesign(L[N].Code, 'A design from your mission log was loaded.');
      Go(Ord(scLab));
    end;
  end
  else if Act = 'clearlog' then
  begin
    if window.confirm('Delete every mission in the log on this device?') then
    begin
      ClearLog;
      Render;
    end;
  end

  { ---- the design lab ---- }
  else if Act = 'tab' then
  begin
    if (N >= 0) and (N < TabCount) then
      LabTab := N;
    HasPrev := False;
    RenderLab(True);
    ScrollTop;
  end
  else if Act = 'orbit' then
  begin
    if (N >= 0) and (N <= High(Scenarios[Scen].Orbits)) then
      D.Orbit := N;
    Recalc;
    RenderLab(True);
  end
  else if Act = 'transfer' then
  begin
    if (N >= 0) and (N <= High(Scenarios[Scen].Transfers)) then
      D.Transfer := N;
    Recalc;
    RenderLab(True);
  end
  else if Act = 'instr' then
  begin
    if (N >= 0) and (N <= High(D.Instr)) then
      D.Instr[N] := not D.Instr[N];
    Recalc;
    RenderLab(True);
  end
  else if Act = 'part' then
  begin
    P := Pos(':', Arg);
    if P > 0 then
    begin
      K := StrToIntDef(Copy(Arg, 1, P - 1), -1);
      I := StrToIntDef(Copy(Arg, P + 1, 10), -1);
      if (K >= 0) and (K <= Ord(High(TPartKind))) and (I >= 0) and (I <= High(Parts[TPartKind(K)])) then
      begin
        D.Part[TPartKind(K)] := I;
        Recalc;
        RenderLab(True);
      end;
    end;
  end
  else if Act = 'launcher' then
  begin
    if (N >= 0) and (N <= High(Launchers)) then
    begin
      if D.Launcher = N then
        D.Launcher := -1
      else
        D.Launcher := N;
    end;
    Recalc;
    RenderLab(True);
  end
  else if Act = 'rtg' then
  begin
    D.RtgCount := D.RtgCount + N;
    if D.RtgCount < 0 then
      D.RtgCount := 0;
    if D.RtgCount > 5 then
      D.RtgCount := 5;
    Recalc;
    RenderLab(True);
  end
  else if Act = 'example' then
  begin
    D := ExampleDesign(Scen, Difficulty, Sandbox);
    HasDesign := False;
    HasPrev := False;
    Recalc;
    HasPrev := False;
    FKeepSeed := False;
    SharedNote := 'An example design was loaded. It passes the review board, but it is far from the best. Can you beat it?';
    Render;
  end
  else if Act = 'share' then
    ShareDesign
  else if Act = 'copyshare' then
  begin
    try
      window.navigator.clipboard.writeText(FShareUrl);
      Toast('Link copied.');
    except
      Toast('Select the link and copy it by hand.');
    end;
  end
  else if Act = 'gauge' then
    OpenModal(ModalBreakdown(Arg), 'info')

  { ---- dialogs ---- }
  else if Act = 'help' then
    OpenModal(ModalHelp, 'info')
  else if Act = 'glossary' then
    OpenModal(ModalGlossary, 'info')
  else if Act = 'about' then
    OpenModal(ModalAbout, 'info')
  else if Act = 'close' then
    CloseModal

  { ---- mission control ---- }
  else if Act = 'play' then
  begin
    FRunning := True;
    SetControls;
  end
  else if Act = 'pause' then
  begin
    FRunning := False;
    SetControls;
  end
  else if Act = 'speed' then
  begin
    if (N >= 1) and (N <= 3) then
      FSpeed := N;
    FRunning := True;
    SetControls;
  end
  else if Act = 'skiplaunch' then
    EndLaunch
  else if Act = 'choose' then
  begin
    if HasSim and Sim.HasPending then
    begin
      SimChoose(Sim, N);
      K := -1;
      for I := High(Sim.Log) downto 0 do
        if Sim.Log[I].IsDecision then
        begin
          K := I;
          Break;
        end;
      if K >= 0 then
        OpenModal(ModalOutcome(K), 'outcome')
      else
        CloseModal;
    end;
  end
  else if Act = 'resume' then
  begin
    CloseModal;
    RefreshMission;
    if Sim.Phase = spDone then
      FinishMission;
  end;
end;

{ ---- flying the mission ------------------------------------------------ }

procedure TGame.StartMission;
begin
  if A.Blockers > 0 then
    Exit;
  if not FKeepSeed then
    D.Seed := NewSeed;
  FKeepSeed := False;
  SimStart(Sim, D);
  HasSim := True;
  HasCard := False;
  FMissionDone := False;
  FLaunching := False;
  FRunning := True;
  FSpeed := 1;
  FAccum := 0;
  FShownLog := 0;
  CloseModal;
  Go(Ord(scMission));
end;

procedure TGame.SetControls;
begin
  SetHtml('m-ctl', ViewMissionControls(FRunning, FMissionDone, FLaunching, FSpeed));
end;

procedure TGame.SyncLog;
var
  E: TJSElement;
begin
  E := document.getElementById('m-log');
  if E = nil then
    Exit;
  while FShownLog < Length(Sim.Log) do
  begin
    E.insertAdjacentHTML('afterbegin', LogItemHtml(FShownLog));
    Inc(FShownLog);
  end;
end;

procedure TGame.RefreshMission;
var
  Bar, Box: TJSHTMLElement;
  Ctx: TCtx;
  S: string;
begin
  if Screen <> scMission then
    Exit;
  SetHtml('m-side', ViewMissionSide);
  if not FLaunching then
    SyncLog;
  Bar := El('m-prog');
  if Bar <> nil then
    Bar.style.setProperty('width', FmtNum(SimProgress(Sim) * 100, 1) + '%');
  case Sim.Phase of
    spDevelopment: S := 'Building the spacecraft';
    spLaunch: S := 'On the launch pad';
    spCruise: S := 'Cruise: ' + FmtYears(Sim.Week / 52) + ' since launch';
    spArrival: S := 'Arriving';
    spScience: S := 'Science week ' + IntToStr(Sim.SciWeek) + ' of ' + IntToStr(Sim.PlanWeeks);
  else
    S := 'Mission over';
  end;
  SetText('m-clock', S);
  if Length(Sim.HistScience) > 1 then
  begin
    Box := El('m-chartbox');
    if (Box <> nil) and Box.hidden then
      Box.hidden := False;
    if ((Length(Sim.HistScience) mod 3 = 0) or (Sim.Phase = spDone)) and Prep('cv-chart', 640, 170, Ctx) then
      DrawChart(Ctx, 640, 170, Sim);
  end;
end;

procedure TGame.StepSim;
var
  Was: TSimPhase;
begin
  Was := Sim.Phase;
  SimAdvance(Sim);
  if Sim.HasPending then
  begin
    RefreshMission;
    OpenModal(ModalDecision, 'decision');
    Exit;
  end;
  if Was = spLaunch then
  begin
    { The launch has been decided. Play it before revealing the result. }
    FLaunching := True;
    FLaunchT0 := NowMs;
    FLaunchFail := Sim.LostAtLaunch;
    FLaunchSize := 1;
    if D.Launcher >= 0 then
      FLaunchSize := Launchers[D.Launcher].Size;
    SetControls;
    SetText('m-clock', 'Launch');
    Exit;
  end;
  RefreshMission;
  if (Sim.Phase = spDone) and not FMissionDone then
    FinishMission;
end;

procedure TGame.EndLaunch;
begin
  if not FLaunching then
    Exit;
  FLaunching := False;
  SyncLog;
  RefreshMission;
  if Sim.Phase = spDone then
    FinishMission
  else
    SetControls;
end;

procedure TGame.FinishMission;
var
  E: TLogEntry;
begin
  if FMissionDone then
    Exit;
  FMissionDone := True;
  FRunning := False;
  Card := ScoreMission(Sim);
  HasCard := True;
  E.Date := TodayIso;
  E.Scenario := Scenarios[Scen].Id;
  E.ScenarioName := Scenarios[Scen].Name;
  E.Grade := Card.Grade;
  E.Outcome := Card.Outcome;
  E.Crew := CrewText;
  E.Code := EncodeDesign(D);
  E.Score := Card.Total;
  E.Players := Players;
  E.SciencePct := Card.SciencePct;
  E.CostM := Card.FinalCostM;
  E.CapM := Card.CapM;
  AddLogEntry(E);
  SyncLog;
  SetControls;
  RefreshMission;
end;

procedure TGame.MissionFrame(Ms: Double);
var
  Ctx: TCtx;
  Dt, Lt, EndT, Rate: Double;
  Guard: Integer;
begin
  Dt := (Ms - FLastMs) / 1000;
  FLastMs := Ms;
  if (Dt < 0) or (Dt > 0.25) then
    Dt := 0.25;

  if FLaunching then
  begin
    Lt := (NowMs - FLaunchT0) / 1000;
    if Prep('cv-main', 640, 360, Ctx) then
      DrawLaunch(Ctx, 640, 360, Lt, FLaunchSize, FLaunchFail);
    EndT := LaunchSeconds;
    if FLaunchFail then
      EndT := 10.5;
    if Lt >= EndT then
      EndLaunch;
    Exit;
  end;

  if Prep('cv-main', 640, 360, Ctx) then
  begin
    if Sim.LostAtLaunch then
      DrawLaunch(Ctx, 640, 360, 10.4, FLaunchSize, True)
    else if (Sim.Phase = spDevelopment) or (Sim.Phase = spLaunch) then
    begin
      DrawCraft(Ctx, 640, 360, D, Sim.A);
      Ctx.font := 'bold 15px ui-monospace, Consolas, monospace';
      Ctx.fillStyle := '#e8eef9';
      Ctx.textAlign := 'center';
      Ctx.fillText('IN THE CLEAN ROOM: BUILDING AND TESTING', 320, 344);
    end
    else if (Sim.Phase = spCruise) or ((Sim.Phase = spDone) and (Sim.SciWeek = 0) and not Sim.LostAtArrival and (Sim.CruiseWeeks > 0)) then
      DrawCruise(Ctx, 640, 360, Sim, Ms / 1000)
    else
      DrawOrbitView(Ctx, 640, 360, D, Ms / 1000);
  end;

  if FRunning and HasSim and (not Sim.HasPending) and (FModalKind = '') and (Sim.Phase <> spDone) then
  begin
    { How many simulation steps per second, for each phase and speed. }
    case Sim.Phase of
      spDevelopment, spLaunch, spArrival: Rate := 0.9 * FSpeed;
      spCruise:
        case FSpeed of
          1: Rate := 5;
          2: Rate := 14;
        else
          Rate := 40;
        end;
    else
      case FSpeed of
        1: Rate := 6;
        2: Rate := 20;
      else
        Rate := 70;
      end;
    end;
    FAccum := FAccum + Dt * Rate;
    Guard := 0;
    while (FAccum >= 1) and (Guard < 8) do
    begin
      FAccum := FAccum - 1;
      Inc(Guard);
      StepSim;
      if Sim.HasPending or FLaunching or (Sim.Phase = spDone) or (FModalKind <> '') then
      begin
        FAccum := 0;
        Break;
      end;
    end;
  end;
end;

procedure TGame.Frame(aTime: TJSDOMHighResTimeStamp);
var
  Ctx: TCtx;
begin
  Inc(FTick);
  if (Screen = scLab) and HasDesign and Prep('cv-orbit', 640, 310, Ctx) then
    DrawOrbitView(Ctx, 640, 310, D, aTime / 1000);
  if FTick mod 50 = 0 then
    DrawStatics;   // catches pictures that finished loading after the first draw
  if (Screen = scMission) and HasSim then
    MissionFrame(aTime);
  window.requestAnimationFrame(@Frame);
end;

end.
