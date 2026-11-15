unit Launch_u;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Types, System.Classes,
  System.Math, System.Diagnostics, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Dialogs, System.UITypes, Vcl.Imaging.pngimage;

type
  TLaunchSceneControl = class(TCustomControl)
  private
    FOnPaint: TNotifyEvent;
  protected
    procedure Paint; override;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Align;
    property OnPaint: TNotifyEvent read FOnPaint write FOnPaint;
  end;

  TCloud = record
    X: Integer;
    Y: Double;
    Scale: Double;
  end;

  TStar = record
    X: Integer;
    Y: Double;
    Size: Integer;
  end;

  TGradientPixel = packed record
    Blue: Byte;
    Green: Byte;
    Red: Byte;
  end;
  PGradientPixel = ^TGradientPixel;

  TfrmLaunch = class(TForm)
    AnimationTimer: TTimer;
    ControlPanel: TPanel;
    TitleLabel: TLabel;
    HelpLabel: TLabel;
    AltitudeLabel: TLabel;
    VelocityLabel: TLabel;
    AccelerationLabel: TLabel;
    FlightStatusLabel: TLabel;
    StartButton: TButton;
    ResetButton: TButton;
    ScenePaintBox: TPaintBox;
    FuelLabel: TLabel;
    TankBar: TProgressBar;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ScenePaintBoxPaint(Sender: TObject);
    procedure AnimationTimerTimer(Sender: TObject);
    procedure StartButtonClick(Sender: TObject);
    procedure ResetButtonClick(Sender: TObject);
  public
    OnContinue: TNotifyEvent;
    OnBackToDesign: TNotifyEvent;
    procedure PrepareLaunch(Mass, Thrust: Double;
      FuelCapacityGallons, FuelConsumptionGallonsPerSecond: Double;
      const RocketFile, ThrusterFile: string);
  private
    FClouds: array[0..9] of TCloud;
    FStars: array[0..39] of TStar;
    FAnimationStopwatch: TStopwatch;
    FMass: Double;
    FThrust: Double;
    FAltitude: Double;
    FVelocity: Double;
    FAcceleration: Double;
    FThrusterDriftX: Double;
    FThrusterDriftY: Double;
    FThrusterDriftVelocityY: Double;
    FFuelCapacityGallons: Double;
    FFuelConsumptionGallonsPerSecond: Double;
    FFuelConsumptionRemainder: Double;
    FHasParameters: Boolean;
    FFlightRunning: Boolean;
    FThrustersDetached: Boolean;
    FBodyImage: TPngImage;
    FLeftThrusterImage: TPngImage;
    FRightThrusterImage: TPngImage;
    FGradientBitmap: TBitmap;
    FSceneBitmap: TBitmap;
    FCountdownTimer: TTimer;
    FCountdown: Integer;
    FFlashCount: Integer;
    FCountdownText: string;
    FCountdownColor: TColor;
    FCountdownVisible: Boolean;
    FContinueButton: TButton;
    FBackButton: TButton;
    FOrbitReached: Boolean;
    FFlightOver: Boolean;
    procedure ContinueClick(Sender: TObject);
    procedure BackClick(Sender: TObject);
    procedure LaunchFormClose(Sender: TObject; var Action: TCloseAction);
    procedure CountdownTimerTimer(Sender: TObject);
    procedure DrawBackground(Canvas: TCanvas; Width, Height: Integer; SpaceBlend: Double);
    procedure DrawCloud(Canvas: TCanvas; const Cloud: TCloud; Visibility: Double);
    procedure DrawGround(Canvas: TCanvas; Width, Height: Integer; Scale: Double);
    procedure DrawRocket(Canvas: TCanvas; CenterX, CenterY: Integer; Scale: Double);
    procedure LoadRocketImages(const RocketFile, ThrusterFile: string);
    procedure BeginCountdown;
    procedure StartFlight;
    procedure UpdateFuelDisplay;
    procedure UpdateTelemetry;
    procedure ResetFlight;
  end;

var
  frmLaunch: TfrmLaunch;

implementation

{$R *.dfm}

const
  MetersToFeet = 3.28084;
  ScenePixelsPerMeter = 0.15;
  CloudBaseAltitude = 1500.0;
  CloudFadeStartAltitude = 8000.0;
  CloudTopAltitude = 12000.0;
  ThrusterJettisonAltitudeFeet = 100000.0;
  CoreStageAcceleration = 6.0;
  ThrusterSeparationSpeed = 45.0;
  ThrusterSeparationGravity = 90.0;
  ThrusterSpriteWidth = 72;
  ThrusterSpriteHeight = 185;
  LeftThrusterOffset = -56;
  RightThrusterOffset = -16;

constructor TLaunchSceneControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  ParentDoubleBuffered := False;
  DoubleBuffered := True;
end;

procedure TLaunchSceneControl.Paint;
begin
  if Assigned(FOnPaint) then
    FOnPaint(Self);
end;

procedure TLaunchSceneControl.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

procedure TfrmLaunch.FormCreate(Sender: TObject);
var
  I: Integer;
begin
  DoubleBuffered := True;
  Randomize;
  Caption := 'Atomic Space | Launch';
  TitleLabel.Caption := 'ATOMIC SPACE | LAUNCH';
  OnClose := LaunchFormClose;

  FBackButton := TButton.Create(Self);
  FBackButton.Parent := ControlPanel;
  FBackButton.SetBounds(688, 70, 188, 30);
  FBackButton.Caption := '< Back to design';
  FBackButton.OnClick := BackClick;

  FContinueButton := TButton.Create(Self);
  FContinueButton.Parent := Self;
  FContinueButton.SetBounds(20, 572, 300, 48);
  FContinueButton.Caption := 'Orbit reached: continue to the Moon >';
  FContinueButton.Font.Size := 11;
  FContinueButton.Font.Style := [fsBold];
  FContinueButton.Visible := False;
  FContinueButton.OnClick := ContinueClick;
  FGradientBitmap := TBitmap.Create;
  FGradientBitmap.PixelFormat := pf24bit;
  FGradientBitmap.Width := 1;
  FSceneBitmap := TBitmap.Create;
  FSceneBitmap.PixelFormat := pf24bit;

  FCountdownText := '';
  FCountdownColor := clWhite;
  FCountdownVisible := False;
  FFuelCapacityGallons := 0;
  FFuelConsumptionGallonsPerSecond := 0;
  FFuelConsumptionRemainder := 0;
  TankBar.Min := 0;
  TankBar.Max := 1;
  TankBar.Position := 0;
  UpdateFuelDisplay;

  FCountdownTimer := TTimer.Create(Self);
  FCountdownTimer.Enabled := False;
  FCountdownTimer.Interval := 1000;
  FCountdownTimer.OnTimer := CountdownTimerTimer;

  for I := Low(FClouds) to High(FClouds) do
  begin
    FClouds[I].X := Random(Max(1, ScenePaintBox.Width));
    FClouds[I].Y := Random(Max(1, ScenePaintBox.Height));
    FClouds[I].Scale := 0.65 + Random * 0.9;
  end;

  for I := Low(FStars) to High(FStars) do
  begin
    FStars[I].X := Random(Max(1, ScenePaintBox.Width));
    FStars[I].Y := Random(Max(1, ScenePaintBox.Height));
    FStars[I].Size := 1 + Random(3);
  end;

  ResetFlight;
end;

procedure TfrmLaunch.ContinueClick(Sender: TObject);
begin
  AnimationTimer.Enabled := False;
  FCountdownTimer.Enabled := False;
  Hide;
  if Assigned(OnContinue) then
    OnContinue(Self);
end;

procedure TfrmLaunch.BackClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmLaunch.LaunchFormClose(Sender: TObject; var Action: TCloseAction);
begin
  AnimationTimer.Enabled := False;
  FCountdownTimer.Enabled := False;
  Action := caHide;
  if Assigned(OnBackToDesign) then
    OnBackToDesign(Self);
end;

procedure TfrmLaunch.PrepareLaunch(Mass, Thrust: Double;
  FuelCapacityGallons, FuelConsumptionGallonsPerSecond: Double;
  const RocketFile, ThrusterFile: string);
begin
  LoadRocketImages(RocketFile, ThrusterFile);
  FFuelCapacityGallons := FuelCapacityGallons;
  FFuelConsumptionGallonsPerSecond := FuelConsumptionGallonsPerSecond;
  TankBar.Min := 0;
  TankBar.Max := Ceil(FFuelCapacityGallons);
  ResetFlight;

  FMass := Mass;
  FThrust := Thrust;
  FAcceleration := FThrust / FMass - 9.81;
  FHasParameters := True;
  UpdateTelemetry;

  BeginCountdown;
  ScenePaintBox.Invalidate;
end;

procedure TfrmLaunch.BeginCountdown;
begin
  FCountdown := 10;
  FFlashCount := 0;
  FCountdownText := IntToStr(FCountdown);
  FCountdownColor := clWhite;
  FCountdownVisible := True;
  FCountdownTimer.Interval := 1000;
  FCountdownTimer.Enabled := True;
  ScenePaintBox.Invalidate;
end;

procedure TfrmLaunch.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FBodyImage);
  FreeAndNil(FLeftThrusterImage);
  FreeAndNil(FRightThrusterImage);
  FreeAndNil(FGradientBitmap);
  FreeAndNil(FSceneBitmap);
end;

procedure TfrmLaunch.CountdownTimerTimer(Sender: TObject);
begin
  if FCountdown > 0 then
  begin
    Dec(FCountdown);
    FCountdownText := IntToStr(FCountdown);
    if FCountdown >= 7 then
      FCountdownColor := clWhite
    else if FCountdown >= 4 then
      FCountdownColor := RGB(255, 140, 0)
    else
      FCountdownColor := clRed;
    ScenePaintBox.Invalidate;
    Exit;
  end;

  if FFlashCount = 0 then
  begin
    FCountdownTimer.Interval := 250;
    FCountdownText := 'LIFTOFF!';
    FCountdownColor := clRed;
    FCountdownVisible := False;
  end;
  Inc(FFlashCount);
  FCountdownVisible := not FCountdownVisible;
  if FFlashCount >= 8 then
  begin
    FCountdownTimer.Enabled := False;
    FCountdownVisible := False;
    StartFlight;
  end;
  ScenePaintBox.Invalidate;
end;

function BlendColor(DayColor, SpaceColor: TColor; SpaceBlend: Double): TColor;
begin
  Result := RGB(
    Round(GetRValue(DayColor) + (GetRValue(SpaceColor) - GetRValue(DayColor)) * SpaceBlend),
    Round(GetGValue(DayColor) + (GetGValue(SpaceColor) - GetGValue(DayColor)) * SpaceBlend),
    Round(GetBValue(DayColor) + (GetBValue(SpaceColor) - GetBValue(DayColor)) * SpaceBlend)
  );
end;

procedure TfrmLaunch.DrawBackground(Canvas: TCanvas; Width, Height: Integer;
  SpaceBlend: Double);
var
  Y: Integer;
  T: Double;
  TopColor, MiddleColor, BottomColor, Color: TColor;
  Pixel: PGradientPixel;
begin
  TopColor := BlendColor(RGB(48, 137, 219), RGB(2, 7, 22), SpaceBlend);
  MiddleColor := BlendColor(RGB(83, 171, 231), RGB(7, 20, 51), SpaceBlend);
  BottomColor := BlendColor(RGB(142, 211, 242), RGB(18, 43, 82), SpaceBlend);

  if FGradientBitmap.Height <> Height then
    FGradientBitmap.Height := Height;

  for Y := 0 to Height - 1 do
  begin
    T := (Height - 1 - Y) / Max(1, Height);
    if T < 0.58 then
    begin
      T := T / 0.58;
      Color := BlendColor(TopColor, MiddleColor, T);
    end
    else
    begin
      T := (T - 0.58) / 0.42;
      Color := BlendColor(MiddleColor, BottomColor, T);
    end;

    Pixel := FGradientBitmap.ScanLine[Y];
    Pixel^.Blue := GetBValue(Color);
    Pixel^.Green := GetGValue(Color);
    Pixel^.Red := GetRValue(Color);
  end;

  Canvas.StretchDraw(Rect(0, 0, Width, Height), FGradientBitmap);
end;

procedure TfrmLaunch.DrawCloud(Canvas: TCanvas; const Cloud: TCloud; Visibility: Double);
var
  X, Y, W, H: Integer;
  CloudShade, CloudHighlight: TColor;
begin
  X := Cloud.X;
  Y := Round(Cloud.Y);
  W := Round(Cloud.Scale * 118);
  H := Round(Cloud.Scale * 38);
  CloudShade := BlendColor(RGB(20, 40, 70), RGB(191, 220, 238), Visibility);
  CloudHighlight := BlendColor(RGB(25, 48, 80), RGB(239, 248, 255), Visibility);

  Canvas.Pen.Style := psClear;
  Canvas.Brush.Color := CloudShade;
  Canvas.Ellipse(X, Y + H div 3, X + W, Y + H);
  Canvas.Brush.Color := CloudHighlight;
  Canvas.Ellipse(X + W div 10, Y + H div 4, X + W div 2, Y + H);
  Canvas.Ellipse(X + W div 3, Y, X + W * 3 div 4, Y + H);
  Canvas.Ellipse(X + W * 3 div 5, Y + H div 4, X + W * 9 div 10, Y + H);
  Canvas.Pen.Style := psSolid;
end;

procedure TfrmLaunch.DrawGround(Canvas: TCanvas; Width, Height: Integer; Scale: Double);
var
  GroundY, CenterX, PadHalfWidth, TowerX, TowerTop: Integer;
begin
  GroundY := Height - Round(26 * Scale) +
    Round(Min(FAltitude * ScenePixelsPerMeter, Height * 4.0));
  if GroundY < Height then
  begin
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Color := RGB(43, 82, 77);
    Canvas.Rectangle(0, GroundY, Width, Height);
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Width := Max(1, Round(2 * Scale));
    Canvas.Pen.Color := RGB(148, 203, 161);
    Canvas.MoveTo(0, GroundY);
    Canvas.LineTo(Width, GroundY);
  end;

  CenterX := Width div 2;
  PadHalfWidth := Round(82 * Scale);
  if (GroundY > 0) and (GroundY - Round(9 * Scale) < Height) then
  begin
    Canvas.Pen.Color := RGB(82, 100, 116);
    Canvas.Brush.Color := RGB(160, 174, 185);
    Canvas.Rectangle(CenterX - PadHalfWidth, GroundY - Round(9 * Scale),
      CenterX + PadHalfWidth, GroundY);
  end;

  TowerX := CenterX + Round(112 * Scale);
  TowerTop := GroundY - Round(112 * Scale);
  if (TowerTop < Height) and (GroundY > 0) then
  begin
    Canvas.Pen.Color := RGB(220, 226, 231);
    Canvas.Pen.Width := Max(2, Round(4 * Scale));
    Canvas.MoveTo(TowerX, TowerTop);
    Canvas.LineTo(TowerX, GroundY - Round(8 * Scale));
    Canvas.MoveTo(TowerX - Round(18 * Scale), TowerTop + Round(22 * Scale));
    Canvas.LineTo(TowerX + Round(18 * Scale), TowerTop + Round(22 * Scale));
    Canvas.MoveTo(TowerX - Round(15 * Scale), TowerTop + Round(48 * Scale));
    Canvas.LineTo(TowerX + Round(15 * Scale), TowerTop + Round(48 * Scale));
    Canvas.MoveTo(TowerX - Round(12 * Scale), TowerTop + Round(74 * Scale));
    Canvas.LineTo(TowerX + Round(12 * Scale), TowerTop + Round(74 * Scale));
  end;
end;

procedure TfrmLaunch.DrawRocket(Canvas: TCanvas; CenterX, CenterY: Integer; Scale: Double);
var
  BodyW, BodyH, SideW, SideH, RightSideW, RightSideH: Integer;
  BodyLeft, BodyTop, BodyBottom: Integer;
  LeftX, RightX, ThrusterBottom, FlameH, ThrusterFlameH: Integer;
  ThrusterFlameHalfWidth: Integer;
  Flame: array[0..2] of TPoint;
begin
  if (FBodyImage = nil) or (FLeftThrusterImage = nil) or
    (FRightThrusterImage = nil) then
    Exit;

  BodyH := Round(250 * Scale);
  BodyW := Max(1, Round(FBodyImage.Width * BodyH / FBodyImage.Height));
  SideW := ThrusterSpriteWidth;
  SideH := ThrusterSpriteHeight;
  RightSideW := ThrusterSpriteWidth;
  RightSideH := ThrusterSpriteHeight;
  BodyLeft := CenterX - BodyW div 2;
  BodyTop := CenterY - BodyH div 2;
  BodyBottom := BodyTop + BodyH;
  LeftX := CenterX + LeftThrusterOffset;
  RightX := CenterX + RightThrusterOffset;
  ThrusterBottom := BodyBottom;
  if FThrustersDetached then
  begin
    LeftX := LeftX - Round(FThrusterDriftX);
    RightX := RightX + Round(FThrusterDriftX);
    ThrusterBottom := ThrusterBottom + Round(FThrusterDriftY);
  end;

  if FFlightRunning and not FThrustersDetached then
  begin
    FlameH := Round(32 * Scale);
    ThrusterFlameH := Max(1, FlameH div 3);
    ThrusterFlameHalfWidth := Max(1, Round(5 * Scale / 3));
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Color := RGB(255, 112, 38);
    Flame[0] := Point(CenterX - Round(7 * Scale), BodyBottom - Round(2 * Scale));
    Flame[1] := Point(CenterX, BodyBottom + FlameH);
    Flame[2] := Point(CenterX + Round(7 * Scale), BodyBottom - Round(2 * Scale));
    Canvas.Polygon(Flame);

    Canvas.Brush.Color := RGB(255, 224, 112);
    Flame[0] := Point(CenterX - Round(3 * Scale), BodyBottom);
    Flame[1] := Point(CenterX, BodyBottom + FlameH div 2);
    Flame[2] := Point(CenterX + Round(3 * Scale), BodyBottom);
    Canvas.Polygon(Flame);

    Canvas.Brush.Color := RGB(255, 112, 38);
    Flame[0] := Point(LeftX + SideW div 2 - ThrusterFlameHalfWidth,
      BodyBottom - Round(2 * Scale / 3));
    Flame[1] := Point(LeftX + SideW div 2, BodyBottom + ThrusterFlameH);
    Flame[2] := Point(LeftX + SideW div 2 + ThrusterFlameHalfWidth,
      BodyBottom - Round(2 * Scale / 3));
    Canvas.Polygon(Flame);
    Flame[0] := Point(RightX + RightSideW div 2 - ThrusterFlameHalfWidth,
      BodyBottom - Round(2 * Scale / 3));
    Flame[1] := Point(RightX + RightSideW div 2,
      BodyBottom + ThrusterFlameH);
    Flame[2] := Point(RightX + RightSideW div 2 + ThrusterFlameHalfWidth,
      BodyBottom - Round(2 * Scale / 3));
    Canvas.Polygon(Flame);
    Canvas.Pen.Style := psSolid;
  end;

  Canvas.StretchDraw(Rect(BodyLeft, BodyTop, BodyLeft + BodyW, BodyBottom), FBodyImage);
  Canvas.StretchDraw(Rect(LeftX, ThrusterBottom - SideH, LeftX + SideW, ThrusterBottom),
    FLeftThrusterImage);
  Canvas.StretchDraw(Rect(RightX, ThrusterBottom - RightSideH,
    RightX + RightSideW, ThrusterBottom),
    FRightThrusterImage);
end;

procedure TfrmLaunch.LoadRocketImages(const RocketFile, ThrusterFile: string);
var
  BasePath: string;
  BodyImage, LeftThrusterImage, RightThrusterImage: TPngImage;

  function AssetPath(const FileName: string): string;
  begin
    Result := IncludeTrailingPathDelimiter(BasePath) + FileName;
    if not FileExists(Result) then
      Result := IncludeTrailingPathDelimiter(BasePath) + 'Win32\Debug\' + FileName;
    if not FileExists(Result) then
      raise EFOpenError.CreateFmt('Rocket image file not found: %s', [FileName]);
  end;

begin
  BasePath := ExtractFilePath(ParamStr(0));
  BodyImage := TPngImage.Create;
  LeftThrusterImage := TPngImage.Create;
  RightThrusterImage := TPngImage.Create;
  try
    BodyImage.LoadFromFile(AssetPath('Assets\Base_Models\' + RocketFile));
    LeftThrusterImage.LoadFromFile(AssetPath('Assets\Thrusters\' + ThrusterFile));
    RightThrusterImage.LoadFromFile(AssetPath('Assets\Thrusters\' + ThrusterFile));

    FreeAndNil(FBodyImage);
    FreeAndNil(FLeftThrusterImage);
    FreeAndNil(FRightThrusterImage);
    FBodyImage := BodyImage;
    FLeftThrusterImage := LeftThrusterImage;
    FRightThrusterImage := RightThrusterImage;
    BodyImage := nil;
    LeftThrusterImage := nil;
    RightThrusterImage := nil;
  finally
    BodyImage.Free;
    LeftThrusterImage.Free;
    RightThrusterImage.Free;
  end;
end;

procedure TfrmLaunch.ScenePaintBoxPaint(Sender: TObject);
var
  I, W, H, RocketY, LaunchSurfaceY, RocketBaseOffset, StarCount: Integer;
  Scale, VisualLift, SpaceBlend, CloudVisibility: Double;
  StarColor: TColor;
  CountdownRect, CountdownShadowRect: TRect;
begin
  W := ScenePaintBox.Width;
  H := ScenePaintBox.Height;
  if (W <= 0) or (H <= 0) then
    Exit;

  if (FSceneBitmap.Width <> W) or (FSceneBitmap.Height <> H) then
  begin
    FSceneBitmap.Width := W;
    FSceneBitmap.Height := H;
  end;

  SpaceBlend := 1 - Exp(-FAltitude / 25000);
  DrawBackground(FSceneBitmap.Canvas, W, H, SpaceBlend);

  StarCount := Round(Length(FStars) * SpaceBlend);
  for I := Low(FStars) to Low(FStars) + StarCount - 1 do
  begin
    if I mod 4 = 0 then
      StarColor := RGB(108, 199, 255)
    else
      StarColor := RGB(232, 244, 255);
    FSceneBitmap.Canvas.Pen.Style := psClear;
    FSceneBitmap.Canvas.Brush.Color := StarColor;
    FSceneBitmap.Canvas.Ellipse(FStars[I].X, Round(FStars[I].Y),
      FStars[I].X + FStars[I].Size, Round(FStars[I].Y) + FStars[I].Size);
  end;

  if (FAltitude >= CloudBaseAltitude) and (FAltitude < CloudTopAltitude) then
  begin
    CloudVisibility := EnsureRange(
      (CloudTopAltitude - FAltitude) /
      (CloudTopAltitude - CloudFadeStartAltitude), 0.0, 1.0);
    if CloudVisibility > 0 then
      for I := Low(FClouds) to High(FClouds) do
        DrawCloud(FSceneBitmap.Canvas, FClouds[I], CloudVisibility);
  end;

  FSceneBitmap.Canvas.Pen.Style := psSolid;
  Scale := Min(W, H) / 500;
  if Scale < 0.55 then
    Scale := 0.55;
  DrawGround(FSceneBitmap.Canvas, W, H, Scale);
  LaunchSurfaceY := H - Round(26 * Scale);
  RocketBaseOffset := Round(250 * Scale) div 2;
  VisualLift := Min(FAltitude * ScenePixelsPerMeter, H * 0.42);
  RocketY := LaunchSurfaceY - RocketBaseOffset - Round(5 * Scale) -
    Round(VisualLift);
  DrawRocket(FSceneBitmap.Canvas, W div 2, RocketY, Scale);
  if FCountdownVisible then
  begin
    FSceneBitmap.Canvas.Font.Name := 'Segoe UI';
    FSceneBitmap.Canvas.Font.Size := 48;
    FSceneBitmap.Canvas.Font.Style := [fsBold];
    SetBkMode(FSceneBitmap.Canvas.Handle, TRANSPARENT);
    CountdownRect := Rect(0, 0, W, H);
    CountdownShadowRect := Rect(2, 2, W + 2, H + 2);
    FSceneBitmap.Canvas.Font.Color := clBlack;
    Winapi.Windows.DrawText(FSceneBitmap.Canvas.Handle, PChar(FCountdownText),
      Length(FCountdownText), CountdownShadowRect,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    FSceneBitmap.Canvas.Font.Color := FCountdownColor;
    Winapi.Windows.DrawText(FSceneBitmap.Canvas.Handle, PChar(FCountdownText),
      Length(FCountdownText), CountdownRect,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  end;
  BitBlt(ScenePaintBox.Canvas.Handle, 0, 0, W, H,
    FSceneBitmap.Canvas.Handle, 0, 0, SRCCOPY);
end;

procedure TfrmLaunch.AnimationTimerTimer(Sender: TObject);
var
  I: Integer;
  H: Integer;
  FuelUnitsConsumed: Integer;
  DeltaTime, PreviousAltitude, AltitudeDelta, SceneDelta: Double;
begin
  H := ScenePaintBox.Height;
  DeltaTime := FAnimationStopwatch.Elapsed.TotalSeconds;
  FAnimationStopwatch := TStopwatch.StartNew;
  if DeltaTime <= 0 then
    DeltaTime := AnimationTimer.Interval / 1000.0
  else if DeltaTime > 0.05 then
    DeltaTime := 0.05;

  if FFlightRunning and not FThrustersDetached and (TankBar.Position > 0) and
    (FFuelConsumptionGallonsPerSecond > 0) then
  begin
    FFuelConsumptionRemainder := FFuelConsumptionRemainder +
      FFuelConsumptionGallonsPerSecond * DeltaTime;
    FuelUnitsConsumed := Trunc(FFuelConsumptionRemainder);
    if FuelUnitsConsumed > 0 then
    begin
      TankBar.Position := Max(TankBar.Min, TankBar.Position - FuelUnitsConsumed);
      FFuelConsumptionRemainder := FFuelConsumptionRemainder - FuelUnitsConsumed;
      UpdateFuelDisplay;
    end;
    if TankBar.Position = TankBar.Min then
      FFuelConsumptionRemainder := 0;
  end;

  if FThrust > FMass * 9.81 then
  begin
    PreviousAltitude := FAltitude;
    FAltitude := FAltitude + FVelocity * DeltaTime +
      0.5 * FAcceleration * DeltaTime * DeltaTime;
    FVelocity := FVelocity + FAcceleration * DeltaTime;
    AltitudeDelta := FAltitude - PreviousAltitude;
    SceneDelta := AltitudeDelta * ScenePixelsPerMeter;

    if (FAltitude >= CloudBaseAltitude) and (FAltitude < CloudTopAltitude) then
    begin
      for I := Low(FClouds) to High(FClouds) do
      begin
        FClouds[I].Y := FClouds[I].Y + SceneDelta;
        if FClouds[I].Y > H + 60 then
        begin
          FClouds[I].Y := -80 - Random(180);
          FClouds[I].X := Random(Max(1, ScenePaintBox.Width));
        end;
      end;
    end;

    for I := Low(FStars) to High(FStars) do
    begin
      FStars[I].Y := FStars[I].Y + SceneDelta * 0.35;
      if FStars[I].Y > H then
        FStars[I].Y := FStars[I].Y - H
      else if FStars[I].Y < 0 then
        FStars[I].Y := FStars[I].Y + H;
    end;
  end;

  if FFlightRunning and not FThrustersDetached and
    (TankBar.Position <= TankBar.Min) and (FFuelCapacityGallons > 0) and
    (FAcceleration > -9.81) then
  begin
    { Out of fuel: engines stop and gravity takes over. }
    FAcceleration := -9.81;
    FlightStatusLabel.Caption := 'Engine cut-off: out of fuel';
  end;

  if FFlightRunning and not FFlightOver and (FAltitude < 0) then
  begin
    FAltitude := 0;
    FVelocity := 0;
    FFlightOver := True;
    AnimationTimer.Enabled := False;
    FFlightRunning := False;
    FlightStatusLabel.Caption := 'MISSION LOST: the rocket fell back';
    StartButton.Caption := 'Start';
  end;

  if FFlightRunning then
  begin
    if not FThrustersDetached and
      (FAltitude * MetersToFeet >= ThrusterJettisonAltitudeFeet) then
    begin
      FThrustersDetached := True;
      { Boosters drop away; the lighter core stage keeps climbing. }
      FAcceleration := CoreStageAcceleration;
      FOrbitReached := True;
      FlightStatusLabel.Caption := 'Booster separation: on the way to orbit';
      FContinueButton.Visible := True;
      FContinueButton.BringToFront;
    end;

    if FThrustersDetached then
    begin
      FThrusterDriftX := FThrusterDriftX +
        ThrusterSeparationSpeed * DeltaTime;
      FThrusterDriftY := FThrusterDriftY +
        FThrusterDriftVelocityY * DeltaTime +
        0.5 * ThrusterSeparationGravity * DeltaTime * DeltaTime;
      FThrusterDriftVelocityY := FThrusterDriftVelocityY +
        ThrusterSeparationGravity * DeltaTime;
    end;
  end;

  UpdateTelemetry;
  ScenePaintBox.Invalidate;
end;

procedure TfrmLaunch.StartButtonClick(Sender: TObject);
begin
  if not FHasParameters then
    Exit;

  if FCountdownTimer.Enabled then
    Exit;

  if FFlightRunning then
  begin
    AnimationTimer.Enabled := False;
    FFlightRunning := False;
    StartButton.Caption := 'Resume';
    FlightStatusLabel.Caption := 'Flight: paused';
    ScenePaintBox.Invalidate;
    Exit;
  end;

  StartFlight;
end;

procedure TfrmLaunch.StartFlight;
begin
  if not FHasParameters then
    Exit;
  FFlightRunning := True;
  FAnimationStopwatch := TStopwatch.StartNew;
  AnimationTimer.Enabled := True;
  StartButton.Caption := 'Pause';
  if FThrust <= FMass * 9.81 then
    FlightStatusLabel.Caption := 'No liftoff: thrust too low'
  else
    FlightStatusLabel.Caption := 'Flight: ascending';
  UpdateTelemetry;
  ScenePaintBox.Invalidate;
end;

procedure TfrmLaunch.ResetFlight;
var
  I: Integer;
begin
  FCountdownTimer.Enabled := False;
  FCountdownVisible := False;
  AnimationTimer.Enabled := False;
  FFlightRunning := False;
  FHasParameters := False;
  FMass := 0;
  FThrust := 0;
  FAltitude := 0;
  FVelocity := 0;
  FAcceleration := 0;
  FThrustersDetached := False;
  FThrusterDriftX := 0;
  FThrusterDriftY := 0;
  FThrusterDriftVelocityY := 0;
  FFuelConsumptionRemainder := 0;
  FOrbitReached := False;
  FFlightOver := False;
  if Assigned(FContinueButton) then
    FContinueButton.Visible := False;
  if FFuelCapacityGallons > 0 then
    TankBar.Position := TankBar.Max
  else
    TankBar.Position := TankBar.Min;
  UpdateFuelDisplay;
  StartButton.Caption := 'Start';
  FlightStatusLabel.Caption := 'Flight: ready';
  HelpLabel.Caption := 'Thrust must exceed rocket weight (mass x 9.81 N) to lift off. No drag model.';

  for I := Low(FClouds) to High(FClouds) do
  begin
    FClouds[I].X := Random(Max(1, ScenePaintBox.Width));
    FClouds[I].Y := Random(Max(1, ScenePaintBox.Height));
  end;
  for I := Low(FStars) to High(FStars) do
  begin
    FStars[I].X := Random(Max(1, ScenePaintBox.Width));
    FStars[I].Y := Random(Max(1, ScenePaintBox.Height));
  end;

  UpdateTelemetry;
  ScenePaintBox.Invalidate;
end;

procedure TfrmLaunch.ResetButtonClick(Sender: TObject);
var
  WasPrepared: Boolean;
  Mass, Thrust: Double;
begin
  WasPrepared := FHasParameters;
  Mass := FMass;
  Thrust := FThrust;
  ResetFlight;
  if WasPrepared then
  begin
    FMass := Mass;
    FThrust := Thrust;
    FAcceleration := FThrust / FMass - 9.81;
    FHasParameters := True;
    UpdateTelemetry;
    BeginCountdown;
  end;
end;

procedure TfrmLaunch.UpdateTelemetry;
begin
  AltitudeLabel.Caption := 'Distance up: ' +
    FormatFloat('#,##0.00', FAltitude * MetersToFeet) + ' ft';
  VelocityLabel.Caption := 'Speed: ' + FormatFloat('#,##0.00', FVelocity) + ' m/s';
  AccelerationLabel.Caption := 'Net accel: ' +
    FormatFloat('#,##0.00', FAcceleration) + ' m/s^2';
  if FHasParameters then
    HelpLabel.Caption := 'Mass: ' + FormatFloat('#,##0.00', FMass) +
      ' kg  |  Thrust: ' + FormatFloat('#,##0.00', FThrust) + ' N' +
      '  |  Lift-off needs > ' + FormatFloat('#,##0.00', FMass * 9.81) +
      ' N  |  T/W ' + FormatFloat('0.00', FThrust / Max(1, FMass * 9.81)) +
      '  |  boosters separate at 100,000 ft';
end;

procedure TfrmLaunch.UpdateFuelDisplay;
begin
  if FFuelCapacityGallons <= 0 then
    FuelLabel.Caption := 'Fuel: not loaded'
  else
    FuelLabel.Caption := 'Fuel: ' +
      FormatFloat('#,##0', TankBar.Position) + ' / ' +
      FormatFloat('#,##0', TankBar.Max) + ' US gal';
end;

initialization
  RegisterClass(TLaunchSceneControl);

finalization
  UnRegisterClass(TLaunchSceneControl);

end.
