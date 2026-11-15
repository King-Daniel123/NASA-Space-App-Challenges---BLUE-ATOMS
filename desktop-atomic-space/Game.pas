unit Game;

{ Atomic Space - the mission planner.
  Choose a mission, build the rocket (ship, thrusters, number of boosters),
  read the review board, launch, fly to the Moon and read the report.
  Hot-seat team mode: up to four players, each with a role and a sign-off.
  Mission rules live in MissionPlan_u.pas.
  Updated with the help of Claude (Anthropic), an AI coding assistant. }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.OleCtrls,
  Vcl.StdCtrls, Vcl.ToolWin, Vcl.ActnMan, Vcl.ActnCtrls, Vcl.ActnMenus,
  Vcl.Imaging.pngimage, Vcl.ExtCtrls, Vcl.Imaging.jpeg, Vcl.CheckLst,
  System.Diagnostics, System.Math, MissionPlan_u;

type
  TfrmGame = class(TForm)
    AtomicSpace: TPageControl;
    TPlanner: TTabSheet;
    Image3: TImage;
    Image4: TImage;
    imgPresident: TImage;
    btnBase: TButton;
    btnNext: TButton;
    btnPrevious: TButton;
    btnThrust: TButton;
    meminfo: TMemo;
    RichEdit1: TRichEdit;
    btnClose: TButton;
    btnMoonMission: TButton;
    imgThrust_1: TImage;
    imgThrust_2: TImage;
    ImgRocket: TImage;
    btnLaunch: TButton;
    TLaunch: TTabSheet;
    imgGround: TImage;
    imgBackground: TImage;
    imgRocketLaunch: TImage;
    imgThrust_1Launch: TImage;
    imgThrust_2Launch: TImage;
    tmrMovement: TTimer;
    lblheight: TLabel;
    Label1: TLabel;
    lblCountdown: TLabel;
    tmrCountdown: TTimer;
    tmrZoom: TTimer;
    ImgSky: TImage;
    ImgSky2: TImage;
    ImgSky4: TImage;
    ImgSky3: TImage;
    ImgSky6: TImage;
    ImgSky5: TImage;
    ImgSpace: TImage;
    TMoon: TTabSheet;
    imgMoon: TImage;
    ImgThrust_1Land: TImage;
    ImgThrust_2Land: TImage;
    ImgRocketLand: TImage;
    imgBackground2: TImage;
    tmrReverse: TTimer;
    AnimationTimer: TTimer;
    procedure btnCloseClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnBaseClick(Sender: TObject);
    procedure btnNextClick(Sender: TObject);
    procedure btnPreviousClick(Sender: TObject);
    procedure btnThrustClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure time(Sender: TObject);
    procedure btnLaunchClick(Sender: TObject);
    procedure tmrMovementTimer(Sender: TObject);
    procedure tmrZoomTimer(Sender: TObject);
    procedure tmrCountdownTimer(Sender: TObject);
    procedure tmrReverseTimer(Sender: TObject);
    procedure btnMoonMissionClick(Sender: TObject);
  private
    FSidePanel: TPanel;
    FMissionCombo: TComboBox;
    FBoosterCombo: TComboBox;
    FCrewCombo: TComboBox;
    FReviewMemo: TMemo;
    FSignOffBox: TCheckListBox;
    FPlan: TPlanResult;
    FShip: TPartSpec;
    FThrusterSpec: TPartSpec;
    procedure BuildMissionPanel;
    procedure LoadPartImages;
    procedure ShowPartInfo;
    procedure RefreshReview;
    procedure UpdateBrief;
    procedure MissionChanged(Sender: TObject);
    procedure CrewChanged(Sender: TObject);
    procedure LaunchContinue(Sender: TObject);
    procedure LaunchBack(Sender: TObject);
    procedure GameFormClose(Sender: TObject; var Action: TCloseAction);
    procedure ShowReport(Flown, Landed: Boolean; FuelLeft: Double);
    function BoosterCount: Integer;
    function AllSignedOff: Boolean;
  public
    procedure createcloud;
    procedure Thrust;
  end;

var
  frmGame: TfrmGame;
   ImageDirection: Integer;
  OriginalY: Integer;

  Rocket : Integer = 1;
  Thruster: Integer = 1;
  RInfo : Integer=1;
  TInfo : Integer = 1;

  SelectedPart: Integer = 1;
  arrRocket : array[1..3] of string = ('Rocket_1_1.png','Rocket_2_2.png','Rocket_3_3.png');
  arrThrusters : array[1..3] of string = ('Thrust_1_1.png','Thrust_2_2.png','Thrust_3_3.png');

  arrThrustInfo : array[1..3] of string = ('Thrust_1_1.txt','Thrust_2_2.txt','Thrust_3_3.txt');
  arrRocketInfo : array[1..3] of string = ('Rocket_1_1.txt','Rocket_2_2.txt','Rocket_3_3.txt');

  arrCloud: array [1 .. 100] of TImage;

  sRocket, sThruster : string;

  rSpeed: Integer;
  rA: Real;
  dt1, dt2: Real;
  rMass: Real;
  rForce: Real;
  iheight: Integer;
  NewTime1, newTime2, oldTime1, oldTime2: TTime;
  stopwatch1, stopwatch2: TStopwatch;
  tmrClouds: TTimer;
  iCountCloud: Integer;
  iNoClouds: Integer;

  Countdown: Integer;
  ZoomSize: Integer;
  ZoomDirection: Integer;
  FlashCount: Integer;

  const
  Distance: Integer = 1000;
  rG: Real = 9.8;

implementation
uses Launch_u, Unit1;

{$R *.dfm}

const
  SidePanelWidth = 400;
  RoleNames: array[0..3] of string = (
    'Mission Lead - budget and schedule',
    'Spacecraft Engineer - mass and thrust',
    'Science Lead - payload and objective',
    'Flight & Comms Lead - fuel and landing');

procedure TfrmGame.time(Sender: TObject);
var
  I: Integer;
begin
  for I := 1 to iNoClouds do
  begin
    arrCloud[I].Top := arrCloud[I].Top + Round(rA * dt1);
  end;
end;

procedure TfrmGame.createcloud;
var
  I: Integer;
begin
  tmrClouds := TTimer.Create(Self);
  tmrClouds.Interval := 1000;
  tmrClouds.Enabled := False;
  iNoClouds := RandomRange(1, 11);
  for I := 1 to iNoClouds do
  begin
    arrCloud[I] := TImage.Create(frmGame);
    arrCloud[I].Parent := TLaunch;
    arrCloud[I].Picture.LoadFromFile(AssetFile('Assets\Cloud.jpeg'));
    arrCloud[I].Stretch := True;
    arrCloud[I].Height := RandomRange(60, 101);
    arrCloud[I].Width := Round(arrCloud[I].Height * 1.8);
    arrCloud[I].Top := RandomRange(-arrCloud[I].Height, 0);
    arrCloud[I].Left := RandomRange(0, Max(1, ClientWidth - arrCloud[I].Width + 1));
    arrCloud[I].BringToFront;
  end;
  tmrClouds.OnTimer := time;
  tmrClouds.Enabled := True;
end;

procedure TfrmGame.thrust;
begin
  rMass := rMass - 10000;
  rA := (rForce / rMass);
  imgThrust_1Launch.Top := imgThrust_1Launch.Top + Round(rA * dt1);
  imgThrust_2Launch.Top := imgThrust_2Launch.Top + Round(rA * dt1);
end;


{ ---------- mission panel ---------- }

procedure TfrmGame.BuildMissionPanel;
var
  I, Y, W: Integer;
  Lbl: TLabel;

  { Positions are written for 96 DPI and scaled to the screen. }
  function Sc(Value: Integer): Integer;
  begin
    Result := MulDiv(Value, CurrentPPI, 96);
  end;

  function AddLabel(const Text: string; Top: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := FSidePanel;
    Result.Left := Sc(12);
    Result.Top := Top;
    Result.Caption := Text;
    Result.Font.Size := 9;
    Result.Font.Style := [fsBold];
    Result.Font.Color := RGB(190, 132, 252);
  end;

  function AddCombo(Left, Top, Width: Integer): TComboBox;
  begin
    Result := TComboBox.Create(Self);
    Result.Parent := FSidePanel;
    Result.Style := csDropDownList;
    Result.SetBounds(Left, Top, Width, Sc(23));
  end;

begin
  ClientWidth := AtomicSpace.Left + AtomicSpace.Width + Sc(SidePanelWidth);
  ClientHeight := Max(ClientHeight, Sc(600));
  AtomicSpace.Height := ClientHeight;
  Caption := 'Atomic Space | Mission Design';

  FSidePanel := TPanel.Create(Self);
  FSidePanel.Parent := Self;
  FSidePanel.Align := alRight;
  FSidePanel.Width := Sc(SidePanelWidth);
  FSidePanel.BevelOuter := bvNone;
  FSidePanel.ParentBackground := False;
  FSidePanel.Color := RGB(20, 10, 38);
  W := FSidePanel.Width - Sc(24);

  Y := Sc(8);
  AddLabel('1. MISSION', Y);
  FMissionCombo := AddCombo(Sc(12), Y + Sc(20), W);
  for I := 0 to MissionCount - 1 do
    FMissionCombo.Items.Add(Format('%s  (%.0f t, cap $%.0f M)',
      [GetMission(I).Name, GetMission(I).PayloadT, GetMission(I).BudgetM]));
  FMissionCombo.ItemIndex := 0;
  FMissionCombo.OnChange := MissionChanged;

  Y := Y + Sc(54);
  AddLabel('2. BOOSTERS', Y);
  Lbl := AddLabel('CREW', Y);
  Lbl.Left := Sc(12) + W div 2 + Sc(6);
  FBoosterCombo := AddCombo(Sc(12), Y + Sc(20), W div 2 - Sc(6));
  FBoosterCombo.Items.Add('2 boosters');
  FBoosterCombo.Items.Add('4 boosters');
  FBoosterCombo.ItemIndex := 0;
  FBoosterCombo.OnChange := MissionChanged;
  FCrewCombo := AddCombo(Sc(12) + W div 2 + Sc(6), Y + Sc(20),
    W div 2 - Sc(6));
  FCrewCombo.Items.Add('1 player (solo)');
  FCrewCombo.Items.Add('2 players');
  FCrewCombo.Items.Add('3 players');
  FCrewCombo.Items.Add('4 players');
  FCrewCombo.ItemIndex := 0;
  FCrewCombo.OnChange := CrewChanged;
  Lbl := AddLabel('Ship and thrusters: Base / Thrusters and < > on the left.',
    Y + Sc(48));
  Lbl.Font.Style := [];
  Lbl.Font.Color := RGB(200, 190, 220);

  Y := Y + Sc(74);
  AddLabel('3. REVIEW BOARD  (live)', Y);
  FReviewMemo := TMemo.Create(Self);
  FReviewMemo.Parent := FSidePanel;
  FReviewMemo.SetBounds(Sc(12), Y + Sc(20), W,
    ClientHeight - (Y + Sc(20)) - Sc(126));
  FReviewMemo.Anchors := [akLeft, akTop, akRight, akBottom];
  FReviewMemo.ReadOnly := True;
  FReviewMemo.ScrollBars := ssVertical;
  FReviewMemo.WordWrap := True;
  FReviewMemo.Font.Name := 'Consolas';
  FReviewMemo.Font.Size := 9;
  FReviewMemo.Color := RGB(32, 20, 56);
  FReviewMemo.Font.Color := RGB(235, 228, 245);

  Lbl := AddLabel('4. TEAM GO / NO-GO  (each role signs off)',
    ClientHeight - Sc(118));
  Lbl.Anchors := [akLeft, akBottom];
  FSignOffBox := TCheckListBox.Create(Self);
  FSignOffBox.Parent := FSidePanel;
  FSignOffBox.SetBounds(Sc(12), ClientHeight - Sc(96), W, Sc(88));
  FSignOffBox.Anchors := [akLeft, akRight, akBottom];
  CrewChanged(nil);
end;

procedure TfrmGame.CrewChanged(Sender: TObject);
var
  Players, I: Integer;
begin
  Players := FCrewCombo.ItemIndex + 1;
  FSignOffBox.Items.Clear;
  { Each player owns one or more of the four roles. }
  for I := 0 to High(RoleNames) do
    FSignOffBox.Items.Add(Format('Player %d: %s', [(I mod Players) + 1,
      RoleNames[I]]));
  FSignOffBox.Enabled := Players > 1;
  if Players = 1 then
    for I := 0 to FSignOffBox.Items.Count - 1 do
      FSignOffBox.Checked[I] := True;
end;

function TfrmGame.AllSignedOff: Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to FSignOffBox.Items.Count - 1 do
    if not FSignOffBox.Checked[I] then
      Exit(False);
end;

function TfrmGame.BoosterCount: Integer;
begin
  if (FBoosterCombo <> nil) and (FBoosterCombo.ItemIndex = 1) then
    Result := 4
  else
    Result := 2;
end;

procedure TfrmGame.MissionChanged(Sender: TObject);
var
  I: Integer;
begin
  { A changed design needs a fresh team sign-off. }
  if (FSignOffBox <> nil) and FSignOffBox.Enabled then
    for I := 0 to FSignOffBox.Items.Count - 1 do
      FSignOffBox.Checked[I] := False;
  UpdateBrief;
  RefreshReview;
end;

procedure TfrmGame.UpdateBrief;
var
  M: TMissionSpec;
begin
  if FMissionCombo = nil then
    Exit;
  M := GetMission(FMissionCombo.ItemIndex);
  RichEdit1.Clear;
  RichEdit1.Lines.Add('MISSION DIRECTOR: ' + M.Name + ' - ' + M.Destination);
  RichEdit1.Lines.Add(M.Brief);
  RichEdit1.Lines.Add(Format('Budget cap $%.0f million. Payload %.0f t. ' +
    'Fuel needed for the trip: %s US gallons.', [M.BudgetM, M.PayloadT,
    FormatFloat('#,##0', M.FuelNeededGal)]));
  RichEdit1.Lines.Add('Every choice is a trade: watch the review board on the right.');
end;

procedure TfrmGame.RefreshReview;
var
  M: TMissionSpec;
begin
  if (FReviewMemo = nil) or (FMissionCombo = nil) then
    Exit;
  M := GetMission(FMissionCombo.ItemIndex);
  if not LoadPartSpec(arrRocketInfo[Rocket], FShip) or
    not LoadPartSpec(arrThrustInfo[Thruster], FThrusterSpec) then
  begin
    FReviewMemo.Lines.Text := 'Part data files were not found in ' +
      'Assets\TextFile. Keep the Assets folder next to the program.';
    FPlan := Default(TPlanResult);
    Exit;
  end;
  FPlan := EvaluatePlan(M, FShip, FThrusterSpec, BoosterCount);
  ReviewLines(M, FShip, FThrusterSpec, BoosterCount, FPlan, FReviewMemo.Lines);
  if FPlan.Ready then
    btnLaunch.Caption := 'LAUNCH'
  else
    btnLaunch.Caption := 'NO-GO';
end;

{ ---------- parts ---------- }

procedure TfrmGame.LoadPartImages;
var
  RocketFile, ThrusterFile: string;
begin
  RocketFile := AssetFile('Assets\Base_Models\' + arrRocket[Rocket]);
  ThrusterFile := AssetFile('Assets\Thrusters\' + arrThrusters[Thruster]);
  if FileExists(RocketFile) then
  begin
    imgRocket.Picture.LoadFromFile(RocketFile);
    imgRocketLaunch.Picture.LoadFromFile(RocketFile);
    imgRocketLand.Picture.LoadFromFile(RocketFile);
  end;
  if FileExists(ThrusterFile) then
  begin
    imgThrust_1.Picture.LoadFromFile(ThrusterFile);
    imgThrust_2.Picture.LoadFromFile(ThrusterFile);
    imgThrust_1Launch.Picture.LoadFromFile(ThrusterFile);
    imgThrust_2Launch.Picture.LoadFromFile(ThrusterFile);
    imgThrust_1Land.Picture.LoadFromFile(ThrusterFile);
    imgThrust_2Land.Picture.LoadFromFile(ThrusterFile);
  end;
end;

procedure TfrmGame.ShowPartInfo;
var
  InfoFile: string;
begin
  if SelectedPart = 2 then
    InfoFile := AssetFile('Assets\TextFile\' + arrThrustInfo[Thruster])
  else
    InfoFile := AssetFile('Assets\TextFile\' + arrRocketInfo[Rocket]);
  if FileExists(InfoFile) then
    meminfo.Lines.LoadFromFile(InfoFile)
  else
    meminfo.Lines.Text := 'Missing file: ' + InfoFile;
end;

procedure TfrmGame.btnBaseClick(Sender: TObject);
begin
  SelectedPart := 1;
  btnBase.Visible := False;
  btnThrust.Visible := True;
  btnPrevious.Visible := True;
  btnNext.Visible := True;
  ShowPartInfo;
end;

procedure TfrmGame.btnThrustClick(Sender: TObject);
begin
  SelectedPart := 2;
  btnBase.Visible := True;
  btnThrust.Visible := False;
  btnPrevious.Visible := True;
  btnNext.Visible := True;
  ShowPartInfo;
end;

procedure TfrmGame.btnNextClick(Sender: TObject);
begin
  if SelectedPart = 1 then
  begin
    if Rocket < 3 then
      Inc(Rocket);
  end
  else if Thruster < 3 then
    Inc(Thruster);
  LoadPartImages;
  ShowPartInfo;
  MissionChanged(Sender);
end;

procedure TfrmGame.btnPreviousClick(Sender: TObject);
begin
  if SelectedPart = 1 then
  begin
    if Rocket > 1 then
      Dec(Rocket);
  end
  else if Thruster > 1 then
    Dec(Thruster);
  LoadPartImages;
  ShowPartInfo;
  MissionChanged(Sender);
end;

procedure TfrmGame.btnCloseClick(Sender: TObject);
begin
  btnClose.Visible := False;
  RichEdit1.Visible := False;
  imgPresident.Visible := False;
end;

{ ---------- flight ---------- }

procedure TfrmGame.btnMoonMissionClick(Sender: TObject);
begin
  { Practice the lunar phase with a full tank; it is not scored. }
  ShowAtomicMission(arrRocket[Rocket]);
end;

procedure TfrmGame.btnLaunchClick(Sender: TObject);
begin
  RefreshReview;
  if not FPlan.Ready then
  begin
    MessageDlg('The review board says NO-GO.' + sLineBreak + sLineBreak +
      'Fix the [RED] findings in the review panel first.' + sLineBreak +
      'Hint: every mission has more than one design that works.',
      mtWarning, [mbOK], 0);
    Exit;
  end;
  if not AllSignedOff then
  begin
    MessageDlg('Not every role has signed off.' + sLineBreak +
      'Each player ticks their role in the TEAM GO / NO-GO list when they ' +
      'agree with the design.', mtInformation, [mbOK], 0);
    Exit;
  end;

  frmLaunch.OnContinue := LaunchContinue;
  frmLaunch.OnBackToDesign := LaunchBack;
  frmLaunch.PrepareLaunch(FPlan.LaunchMassKg, FPlan.ThrustN, FShip.FuelGal,
    BoosterCount * FThrusterSpec.BurnGalPerS, arrRocket[Rocket],
    arrThrusters[Thruster]);
  frmLaunch.Show;
  Hide;
end;

procedure TfrmGame.LaunchBack(Sender: TObject);
begin
  Show;
end;

procedure TfrmGame.LaunchContinue(Sender: TObject);
var
  Outcome: TMoonOutcome;
begin
  Outcome := ShowAtomicMission(arrRocket[Rocket], MoonFuelPercent(FPlan));
  Show;
  ShowReport(Outcome.Flown, Outcome.Landed, Outcome.FuelLeft);
end;

procedure TfrmGame.ShowReport(Flown, Landed: Boolean; FuelLeft: Double);
var
  ReportForm: TForm;
  Memo: TMemo;
begin
  ReportForm := TForm.CreateNew(Self);
  try
    ReportForm.Caption := 'Atomic Space | Mission Report';
    ReportForm.Position := poOwnerFormCenter;
    ReportForm.ClientWidth := 640;
    ReportForm.ClientHeight := 460;
    Memo := TMemo.Create(ReportForm);
    Memo.Parent := ReportForm;
    Memo.Align := alClient;
    Memo.ReadOnly := True;
    Memo.ScrollBars := ssVertical;
    Memo.Font.Name := 'Consolas';
    Memo.Font.Size := 10;
    ReportLines(GetMission(FMissionCombo.ItemIndex), FPlan, Flown, Landed,
      FuelLeft, Memo.Lines);
    ReportForm.ShowModal;
  finally
    ReportForm.Free;
  end;
  MissionChanged(nil);
end;

procedure TfrmGame.GameFormClose(Sender: TObject; var Action: TCloseAction);
begin
  { The start screen is the hidden main form; closing the planner ends the game. }
  Application.Terminate;
end;

procedure TfrmGame.FormCreate(Sender: TObject);
begin
  imgSky.Visible := False;
  imgSky2.Visible := False;
  imgSky3.Visible := False;
  imgSky4.Visible := False;
  imgSky5.Visible := False;
  imgSky6.Visible := False;
  imgSpace.Visible := False;

  Randomize;
  iCountCloud := 0;
  MemInfo.Clear;
  RichEdit1.Clear;
  ImageDirection := 1;
  OriginalY := imgPresident.Top;
  { The old director character is hidden: it resembles a real person, which
    the Space Apps rules on likeness make risky. Set True to show it again. }
  imgPresident.Visible := False;

  btnPrevious.Visible := True;
  btnNext.Visible := True;
  btnBase.Visible := False;
  btnThrust.Visible := True;

  tmrCountdown.Enabled := False;
  tmrZoom.Enabled := False;
  tmrReverse.Enabled := False;

  OnClose := GameFormClose;
  BuildMissionPanel;

  { The mission brief sits under the part buttons, in the space the taller
    window adds, so it never covers Base / Thrusters. }
  RichEdit1.Top := Max(btnBase.Top + btnBase.Height,
    btnMoonMission.Top + btnMoonMission.Height) + MulDiv(10, CurrentPPI, 96);
  RichEdit1.Height := Max(MulDiv(60, CurrentPPI, 96),
    TPlanner.ClientHeight - RichEdit1.Top - MulDiv(8, CurrentPPI, 96));
  RichEdit1.Color := RGB(20, 10, 38);
  RichEdit1.Font.Color := RGB(235, 228, 245);
  RichEdit1.Font.Size := 10;
  RichEdit1.Anchors := [akLeft, akTop, akRight, akBottom];
  btnBase.BringToFront;
  btnThrust.BringToFront;
  btnMoonMission.BringToFront;
  btnClose.BringToFront;
end;

procedure TfrmGame.FormShow(Sender: TObject);
begin
  AtomicSpace.ActivePage := TPlanner;
  TLaunch.TabVisible := False;
  TMoon.TabVisible := False;
  LoadPartImages;
  ShowPartInfo;
  UpdateBrief;
  RefreshReview;
end;

procedure TfrmGame.tmrCountdownTimer(Sender: TObject);
begin
if Countdown > 0 then
  begin
    Dec(Countdown);

    lblCountdown.Caption := IntToStr(Countdown);

    if Countdown >= 7 then
    begin
      lblCountdown.Font.Color := clWhite;
    end
    else if Countdown >= 4 then
    begin
      lblCountdown.Font.Color := RGB(255, 140, 0);
    end
    else
    begin
      lblCountdown.Font.Color := clRed;
    end;

    ZoomSize := 48;
    ZoomDirection := 1;
    lblCountdown.Font.Size := ZoomSize;

    Exit;
  end;

  if FlashCount = 0 then
  begin
    tmrCountdown.Interval := 250;
    lblCountdown.Caption := 'LIFTOFF!';
    lblCountdown.Font.Color := clRed;
    lblCountdown.Font.Size := 48;
    tmrZoom.Enabled := False;
    lblCountdown.Visible := false;
  end;

  Inc(FlashCount);

  lblCountdown.Visible := not lblCountdown.Visible;

  if FlashCount >= 8 then
  begin
    tmrCountdown.Enabled := False;

    lblCountdown.Visible := True;

    stopwatch1 := TStopwatch.StartNew;
    tmrMovement.Enabled := True;
  end;
end;

procedure TfrmGame.tmrMovementTimer(Sender: TObject);
begin
  lblCountdown.visible := false;
  dt1 := stopwatch1.Elapsed.TotalSeconds;
  stopwatch1 := TStopwatch.StartNew;
  rA := (rForce / rMass);
  rSpeed := rSpeed + Round(rA * dt1);
  iheight := rSpeed;
  lblheight.Caption := IntToStr(iheight) + ' m';
  imgGround.Top := imgGround.Top + rSpeed;
  if (iheight >= 200) and (iCountCloud = 0) then
  begin
    createcloud;
    Inc(iCountCloud);
  end;
  if (iheight >= 600) and (iCountCloud > 0) then
  begin
    dec(iCountCloud, 3);
  end;
  if (iheight >= 800) then
  begin
    imgSky.Visible := true;
    imgBackground.Top := imgBackground.Top + rSpeed;
  end;

  if (iheight >= 1300) then
  begin
    imgBackground.Visible := false;
    imgSky2.Visible := true;
    imgSky.Top := imgSky.Top + rSpeed;
  end;

  if (iheight >= 1800) then
  begin
    imgSky3.Visible := True;
    ImgSky.Visible := False;
    imgSky2.Top := imgSky2.Top + rSpeed;
  end;

   if (iheight >= 2100) then
  begin
    imgSky4.Visible := True;
    imgSky2.Visible := false;
    imgSky3.Top := imgSky3.Top + rSpeed;
  end;

   if (iheight >= 2500) then
  begin
    imgSky5.Visible := True;
    ImgSky3.Visible := False;
    imgSky4.Top := imgSky4.Top + rSpeed;
  end;

   if (iheight >= 2700) then
  begin
    imgSky6.Visible := True;
    ImgSky4.Visible := False;
    imgSky5.Top := imgSky5.Top + rSpeed;
  end;

   if (iheight >= 3000) then
  begin
    imgSpace.Visible := True;
    ImgSky5.Visible := False;
    imgSky6.Top := imgSky6.Top + rSpeed;
  end;

  if (iheight >= 5000) then
  begin
       AtomicSpace.ActivePage := TMoon;
       tmrMovement.Enabled := False;
       tmrReverse.Enabled := true;
  end;

end;

procedure TfrmGame.tmrReverseTimer(Sender: TObject);
begin
  dt1 := stopwatch1.Elapsed.TotalSeconds;
  stopwatch1 := TStopwatch.StartNew;
  rA := (rForce / rMass);
  rSpeed := rSpeed + Round(rA * dt1);
  iheight := rSpeed;
  imgMoon.Top := imgMoon.Top - rSpeed;
end;

procedure TfrmGame.tmrZoomTimer(Sender: TObject);
begin
  ZoomSize := ZoomSize + (ZoomDirection * 2);

  if ZoomSize >= 80 then
  begin
    ZoomSize := 80;
    ZoomDirection := -1;
  end;

  if ZoomSize <= 48 then
  begin
    ZoomSize := 48;
    ZoomDirection := 1;
  end;

  lblCountdown.Font.Size := ZoomSize;
end;

end.
