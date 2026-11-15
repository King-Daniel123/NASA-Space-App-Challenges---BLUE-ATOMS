unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Types,
  Winapi.GDIPAPI, Winapi.GDIPOBJ,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls;

type
  TFlightStage = (fsReady, fsLaunch, fsOrbit, fsLanding, fsLanded, fsCrashed);
  TLandingMode = (lmManual, lmAutomatic);

  TMoonOutcome = record
    Flown: Boolean;
    Landed: Boolean;
    FuelLeft: Double;
  end;

  TForm1 = class(TForm)
  private
    FTimer: TTimer;
    FStage: TFlightStage;
    FSpaceDown: Boolean;
    FModeKeyDown: Boolean;
    FLeftDown: Boolean;
    FRightDown: Boolean;
    FUpDown: Boolean;
    FDownDown: Boolean;
    FOrbitCaptured: Boolean;
    FOrbitFailed: Boolean;
    FOrbitStableTime: Double;
    FOrbitLockedTime: Double;
    FLandingMode: TLandingMode;
    FLandingThrusting: Boolean;
    FBackgroundImage: TGPImage;
    FRocketImage: TGPImage;
    FEarthImage: TGPImage;
    FMoonImage: TGPImage;
    FFlagImage: TGPImage;
    FAltitude: Double;
    FVerticalSpeed: Double;
    FHorizontalPosition: Double;
    FHorizontalSpeed: Double;
    FFuel: Double;
    FAngle: Double;
    FOrbitAngle: Double;
    FLastTick: Cardinal;
    FStartFuel: Double;
    procedure FormPaint(Sender: TObject);
    procedure GameTick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure StartMission;
    procedure StartLanding;
    procedure ResetMission;
    procedure DrawBackground;
    procedure DrawRocket(X, Y: Integer; Angle: Double);
    procedure DrawImage(Image: TGPImage; X, Y, Width, Height: Integer;
      Angle: Double = 0);
    procedure DrawHud;
    procedure DrawLaunchScene;
    procedure DrawOrbitScene;
    procedure DrawLandingScene;
    procedure DrawMessage(const Title, Detail: string);
    procedure DrawHowToPlay;
    procedure DrawKeyCap(X, Y: Integer; const Caption: string);
    procedure DrawFlightHint;
    procedure DrawText(X, Y: Integer; const Text: string; Size: Integer;
      TextColor: TColor; Bold: Boolean = False);
    function StageName: string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetRocketImage(const RocketFileName: string);
    procedure SetStartFuel(Percent: Double);
  end;

var
  Form1: TForm1;

function ShowAtomicMission(const RocketFileName: string;
  StartFuelPercent: Double = 100): TMoonOutcome;

implementation

uses
  System.Math;

{$R *.dfm}

const
  OrbitTargetAltitude = 100;
  OrbitSafeMinimum = 60;
  OrbitSafeMaximum = 140;
  OrbitCaptureTolerance = 2;
  MoonGravity = 1.62;
  LandingThrustAcceleration = 4.5;
  LaunchFuelUseRate = 1.0;
  OrbitFuelUseRate = 0.25;
  LandingFuelUseRate = 0.25;

constructor TForm1.Create(AOwner: TComponent);
var
  AssetPath: string;
begin
  inherited Create(AOwner);
  Caption := 'Atomic Space | Mission Control';
  ClientWidth := 1000;
  ClientHeight := 700;
  Constraints.MinWidth := 760;
  Constraints.MinHeight := 660;
  Color := RGB(13, 7, 30);
  Font.Name := 'Segoe UI';
  Font.Color := clWhite;
  DoubleBuffered := True;
  KeyPreview := True;
  OnPaint := FormPaint;
  OnKeyDown := FormKeyDown;
  OnKeyUp := FormKeyUp;
  Randomize;
  AssetPath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'Assets\MoonMission\';
  if not FileExists(AssetPath + 'background.png') then
  begin
    AssetPath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
      'Assets\';
    if not FileExists(AssetPath + 'background.png') then
    begin
      AssetPath := ExpandFileName(ExtractFilePath(ParamStr(0)) +
        '..\..\Assets\MoonMission\');
      if not FileExists(AssetPath + 'background.png') then
        AssetPath := ExpandFileName(ExtractFilePath(ParamStr(0)) +
          '..\..\Assets\');
    end;
  end;
  if not FileExists(AssetPath + 'rocket.png') or
    not FileExists(AssetPath + 'earth.png') or
    not FileExists(AssetPath + 'moon.png') or
    not FileExists(AssetPath + 'flag.png') or
    not FileExists(AssetPath + 'background.png') then
    raise Exception.CreateFmt('Game images were not found in %s', [AssetPath]);
  FRocketImage := TGPImage.Create(PWideChar(AssetPath + 'rocket.png'));
  FEarthImage := TGPImage.Create(PWideChar(AssetPath + 'earth.png'));
  FMoonImage := TGPImage.Create(PWideChar(AssetPath + 'moon.png'));
  FFlagImage := TGPImage.Create(PWideChar(AssetPath + 'flag.png'));
  FBackgroundImage := TGPImage.Create(PWideChar(AssetPath + 'background.png'));
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 30;
  FTimer.OnTimer := GameTick;
  FLastTick := GetTickCount;
  FStartFuel := 100;
  ResetMission;
  FTimer.Enabled := True;
end;

procedure TForm1.SetRocketImage(const RocketFileName: string);
var
  RocketPath: string;
  NewRocketImage: TGPImage;
begin
  RocketPath := RocketFileName;
  if not FileExists(RocketPath) then
    RocketPath := IncludeTrailingPathDelimiter(
      ExtractFilePath(ParamStr(0))) + 'Assets\Base_Models\' +
      ExtractFileName(RocketFileName);
  if not FileExists(RocketPath) then
    raise Exception.CreateFmt('Selected rocket image was not found: %s',
      [RocketFileName]);

  NewRocketImage := TGPImage.Create(PWideChar(RocketPath));
  FRocketImage.Free;
  FRocketImage := NewRocketImage;
  Invalidate;
end;

destructor TForm1.Destroy;
begin
  FRocketImage.Free;
  FEarthImage.Free;
  FMoonImage.Free;
  FFlagImage.Free;
  FBackgroundImage.Free;
  inherited Destroy;
end;

procedure TForm1.SetStartFuel(Percent: Double);
begin
  FStartFuel := EnsureRange(Percent, 1, 100);
  ResetMission;
end;

function ShowAtomicMission(const RocketFileName: string;
  StartFuelPercent: Double): TMoonOutcome;
var
  MissionForm: TForm1;
begin
  Result.Flown := False;
  Result.Landed := False;
  Result.FuelLeft := 0;
  MissionForm := TForm1.Create(Application);
  try
    MissionForm.SetRocketImage(RocketFileName);
    MissionForm.SetStartFuel(StartFuelPercent);
    MissionForm.ShowModal;
    Result.Flown := MissionForm.FStage in [fsLanded, fsCrashed];
    Result.Landed := MissionForm.FStage = fsLanded;
    Result.FuelLeft := MissionForm.FFuel;
  finally
    MissionForm.Free;
  end;
end;

procedure TForm1.ResetMission;
begin
  FStage := fsReady;
  FAltitude := 0;
  FVerticalSpeed := 0;
  FHorizontalPosition := -300;
  FHorizontalSpeed := 0;
  FFuel := FStartFuel;
  FAngle := 0;
  FOrbitAngle := -Pi / 2;
  FSpaceDown := False;
  FModeKeyDown := False;
  FLeftDown := False;
  FRightDown := False;
  FUpDown := False;
  FDownDown := False;
  FLandingMode := lmManual;
  FLandingThrusting := False;
  FOrbitCaptured := False;
  FOrbitFailed := False;
  FOrbitStableTime := 0;
  FOrbitLockedTime := 0;
  FLastTick := GetTickCount;
  Invalidate;
end;

procedure TForm1.StartMission;
begin
  if FStage = fsReady then
  begin
    FStage := fsLaunch;
    FAltitude := 0;
    FVerticalSpeed := 0;
    FHorizontalPosition := 0;
    FHorizontalSpeed := 0;
    FFuel := FStartFuel;
  end;
end;

procedure TForm1.StartLanding;
begin
  FStage := fsLanding;
  FLandingMode := lmManual;
  FLandingThrusting := False;
  FAltitude := 1200;
  FVerticalSpeed := 0;
  FHorizontalPosition := -300;
  FHorizontalSpeed := 0;
  FAngle := 0;
  FSpaceDown := False;
  FLeftDown := False;
  FRightDown := False;
  FUpDown := False;
  FDownDown := False;
end;

procedure TForm1.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    VK_SPACE:
      begin
        FSpaceDown := True;
        if FStage = fsReady then
          StartMission
      end;
    VK_LEFT, Ord('A'): FLeftDown := True;
    VK_RIGHT, Ord('D'): FRightDown := True;
    VK_UP: FUpDown := True;
    VK_DOWN: FDownDown := True;
    Ord('M'):
      begin
        if (FStage = fsLanding) and not FModeKeyDown then
          if FLandingMode = lmManual then
            FLandingMode := lmAutomatic
          else
            FLandingMode := lmManual;
        FModeKeyDown := True;
      end;
    Ord('R'):
      if FStage = fsLanded then
        ResetMission
      else if FStage = fsCrashed then
        ResetMission;
    VK_RETURN:
      if (FStage = fsLanded) or (FStage = fsCrashed) then
        ModalResult := mrOk
      else if FStage = fsReady then
        ResetMission;
    VK_ESCAPE:
      ModalResult := mrCancel;
  end;
end;

procedure TForm1.FormKeyUp(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    VK_SPACE: FSpaceDown := False;
    VK_LEFT, Ord('A'): FLeftDown := False;
    VK_RIGHT, Ord('D'): FRightDown := False;
    VK_UP: FUpDown := False;
    VK_DOWN: FDownDown := False;
    Ord('M'): FModeKeyDown := False;
  end;
end;

procedure TForm1.GameTick(Sender: TObject);
var
  NowTick: Cardinal;
  DeltaTime: Double;
  Thrust: Double;
  TargetVerticalSpeed: Double;
  TargetHorizontalSpeed: Double;
  HorizontalThrust: Double;
begin
  NowTick := GetTickCount;
  DeltaTime := (NowTick - FLastTick) / 1000.0;
  FLastTick := NowTick;
  if DeltaTime > 0.08 then
    DeltaTime := 0.08;

  case FStage of
    fsLaunch:
      begin
        if FLeftDown then
          FAngle := Max(-0.65, FAngle - 0.9 * DeltaTime);
        if FRightDown then
          FAngle := Min(0.65, FAngle + 0.9 * DeltaTime);
        Thrust := 0;
        if FSpaceDown and (FFuel > 0) then
        begin
          Thrust := 20;
          FFuel := Max(0, FFuel - LaunchFuelUseRate * DeltaTime);
        end;
        FVerticalSpeed := FVerticalSpeed +
          (Thrust * Cos(FAngle) - 5.2) * DeltaTime;
        FHorizontalSpeed := FHorizontalSpeed +
          Thrust * Sin(FAngle) * DeltaTime;
        FAltitude := FAltitude + FVerticalSpeed * DeltaTime;
        FHorizontalPosition := FHorizontalPosition +
          FHorizontalSpeed * DeltaTime;
        if FAltitude >= 125 then
        begin
          FStage := fsOrbit;
          FAltitude := 96;
          FVerticalSpeed := -0.16;
          FOrbitAngle := -Pi / 2;
          FOrbitCaptured := False;
          FOrbitFailed := False;
          FOrbitStableTime := 0;
          FOrbitLockedTime := 0;
        end
        else if FAltitude < -8 then
          FStage := fsCrashed;
      end;
    fsOrbit:
      begin
        FOrbitAngle := FOrbitAngle + 0.34 * DeltaTime;
        if FOrbitCaptured then
        begin
          FOrbitLockedTime := FOrbitLockedTime + DeltaTime;
          if FOrbitLockedTime >= 1.5 then
          begin
            FSpaceDown := False;
            StartLanding;
          end;
        end
        else
        begin
          Thrust := 0;
          if (FUpDown <> FDownDown) and (FFuel > 0) then
          begin
            if FUpDown then
              Thrust := 0.22
            else
              Thrust := -0.22;
            FFuel := Max(0, FFuel - OrbitFuelUseRate * DeltaTime);
          end;
          FVerticalSpeed := FVerticalSpeed +
            (Thrust + 0.012 * Sin(FOrbitAngle * 1.7) -
            FVerticalSpeed * 0.12) * DeltaTime;
          FVerticalSpeed := EnsureRange(FVerticalSpeed, -0.8, 0.8);
          FAltitude := FAltitude + FVerticalSpeed * DeltaTime;
          if (FAltitude < OrbitSafeMinimum) or
            (FAltitude > OrbitSafeMaximum) then
          begin
            FOrbitFailed := True;
            FStage := fsCrashed;
          end
          else if (Abs(FAltitude - OrbitTargetAltitude) <=
            OrbitCaptureTolerance) and
            (Abs(FVerticalSpeed) <= 0.025) then
          begin
            FOrbitStableTime := FOrbitStableTime + DeltaTime;
            if FOrbitStableTime >= 3 then
            begin
              FOrbitCaptured := True;
              FOrbitLockedTime := 0;
            end;
          end
          else
            FOrbitStableTime := 0;
        end;
      end;
    fsLanding:
      begin
        Thrust := 0;
        HorizontalThrust := 0;
        if FLandingMode = lmAutomatic then
        begin
          if FAltitude > 150 then
            TargetVerticalSpeed := 30
          else if FAltitude > 40 then
            TargetVerticalSpeed := 8
          else if FAltitude > 10 then
            TargetVerticalSpeed := 3
          else
            TargetVerticalSpeed := 1.5;

          if FFuel > 0 then
          begin
            Thrust := EnsureRange(MoonGravity +
              (FVerticalSpeed - TargetVerticalSpeed) * 1.8,
              0.0, LandingThrustAcceleration);
            TargetHorizontalSpeed := EnsureRange(
              -FHorizontalPosition * 0.45, -16.0, 16.0);
            HorizontalThrust := EnsureRange(
              (TargetHorizontalSpeed - FHorizontalSpeed) * 1.8,
              -LandingThrustAcceleration, LandingThrustAcceleration);
            FFuel := Max(0, FFuel -
              (Thrust + Abs(HorizontalThrust)) /
              LandingThrustAcceleration * LandingFuelUseRate * DeltaTime);
          end;
          FLandingThrusting := Thrust > 0.2;
          FHorizontalSpeed := FHorizontalSpeed +
            HorizontalThrust * DeltaTime;
        end;
        if FLandingMode = lmManual then
        begin
          FLandingThrusting := FSpaceDown and (FFuel > 0);
          if FSpaceDown and (FFuel > 0) then
          begin
            Thrust := LandingThrustAcceleration;
            FFuel := Max(0, FFuel - LandingFuelUseRate * DeltaTime);
          end;
          if FLeftDown then
            FHorizontalSpeed := FHorizontalSpeed - 11 * DeltaTime;
          if FRightDown then
            FHorizontalSpeed := FHorizontalSpeed + 11 * DeltaTime;
          FHorizontalSpeed := FHorizontalSpeed *
            Power(0.985, DeltaTime * 30);
        end;
        FVerticalSpeed := FVerticalSpeed +
          (MoonGravity - Thrust) * DeltaTime;
        FAltitude := FAltitude - FVerticalSpeed * DeltaTime;
        FHorizontalPosition := FHorizontalPosition +
          FHorizontalSpeed * DeltaTime;
        if FAltitude <= 0 then
        begin
          FAltitude := 0;
          if (Abs(FHorizontalPosition) <= 75) and
            (Abs(FHorizontalSpeed) <= 22) and
            (FVerticalSpeed >= 0) and (FVerticalSpeed <= 7) then
            FStage := fsLanded
          else
            FStage := fsCrashed;
        end;
      end;
  end;
  Invalidate;
end;

function TForm1.StageName: string;
begin
  case FStage of
    fsReady: Result := 'READY FOR LAUNCH';
    fsLaunch: Result := 'ASCENT';
    fsOrbit:
      if FOrbitCaptured then
        Result := 'ORBIT CAPTURED'
      else
        Result := 'STABILIZE ORBIT';
    fsLanding:
      if FLandingMode = lmAutomatic then
        Result := 'AUTO LANDING'
      else
        Result := 'MANUAL LANDING';
    fsLanded: Result := 'MISSION COMPLETE';
  else
    Result := 'MISSION LOST';
  end;
end;

procedure TForm1.DrawText(X, Y: Integer; const Text: string; Size: Integer;
  TextColor: TColor; Bold: Boolean);
begin
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := Size;
  Canvas.Font.Color := TextColor;
  if Bold then
    Canvas.Font.Style := [fsBold]
  else
    Canvas.Font.Style := [];
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(X, Y, Text);
  Canvas.Brush.Style := bsSolid;
end;

procedure TForm1.DrawBackground;
var
  Graphics: TGPGraphics;
begin
  Graphics := TGPGraphics.Create(Canvas.Handle);
  try
    Graphics.DrawImage(FBackgroundImage, 0, 0, ClientWidth, ClientHeight);
  finally
    Graphics.Free;
  end;
end;

procedure TForm1.DrawRocket(X, Y: Integer; Angle: Double);
begin
  if (FSpaceDown and (FStage in [fsLaunch, fsLanding])) or
    ((FStage = fsLanding) and FLandingThrusting) then
  begin
    Canvas.Pen.Color := RGB(255, 168, 72);
    Canvas.Brush.Color := RGB(255, 116, 49);
    Canvas.Polygon([Point(X - 7, Y + 16), Point(X + 7, Y + 16),
      Point(X, Y + 34 + Random(9))]);
  end;
  DrawImage(FRocketImage, X, Y, 48, 64, Angle);
end;

procedure TForm1.DrawImage(Image: TGPImage; X, Y, Width, Height: Integer;
  Angle: Double);
var
  Graphics: TGPGraphics;
begin
  Graphics := TGPGraphics.Create(Canvas.Handle);
  try
    Graphics.TranslateTransform(X, Y);
    Graphics.RotateTransform(Angle * 180 / Pi);
    Graphics.DrawImage(Image, -(Width div 2), -(Height div 2), Width, Height);
  finally
    Graphics.Free;
  end;
end;

procedure TForm1.DrawHud;
var
  BarWidth: Integer;
  FuelWidth: Integer;
  FuelLeft: Integer;
  InfoRect: TRect;
  FuelColor: TColor;
  FuelPanel: TRect;
begin
  DrawText(28, 22, 'ATOMIC SPACE', 19, RGB(245, 238, 255), True);
  DrawText(29, 49, 'MISSION CONTROL  /  01', 9, RGB(167, 148, 190));

  InfoRect := Rect(27, 86, 278, 236);
  Canvas.Pen.Color := RGB(75, 52, 111);
  Canvas.Brush.Color := RGB(20, 10, 38);
  Canvas.RoundRect(InfoRect.Left, InfoRect.Top, InfoRect.Right,
    InfoRect.Bottom, 12, 12);
  DrawText(43, 99, 'FLIGHT STATUS', 9, RGB(184, 158, 210), True);
  DrawText(43, 121, StageName, 13, RGB(190, 132, 252), True);
  if FStage in [fsLanding, fsLanded, fsCrashed] then
  begin
    DrawText(43, 153, Format('ALTITUDE   %4.0f m', [Max(0, FAltitude)]),
      10, RGB(223, 214, 238));
    DrawText(43, 174, Format('VERTICAL   %4.1f m/s',
      [FVerticalSpeed]), 10, RGB(223, 214, 238));
    DrawText(43, 195, Format('HORIZONTAL %4.1f m/s',
      [FHorizontalSpeed]), 10, RGB(223, 214, 238));
    if FStage = fsLanding then
      if FLandingMode = lmAutomatic then
        DrawText(43, 214, 'MODE: AUTO  (M TO SWITCH)', 9,
          RGB(190, 132, 252), True)
      else
        DrawText(43, 214, 'MODE: MANUAL  (M TO SWITCH)', 9,
          RGB(223, 214, 238), True);
  end
  else if FStage = fsOrbit then
  begin
    DrawText(43, 153, Format('ALT   %5.1f km / TARGET 100', [FAltitude]),
      10, RGB(223, 214, 238));
    DrawText(43, 174, Format('RADIAL SPEED %+4.0f m/s',
      [FVerticalSpeed * 1000]), 10, RGB(223, 214, 238));
    if FOrbitCaptured then
      DrawText(43, 195, 'ORBIT LOCKED - LANDING NEXT', 9,
        RGB(190, 132, 252), True)
    else
      DrawText(43, 195, Format('LOCK STABILITY  %1.1f / 3.0 s',
        [FOrbitStableTime]), 9, RGB(223, 214, 238));
  end
  else
  begin
    DrawText(43, 155, Format('ALTITUDE   %4.0f km', [FAltitude]),
      10, RGB(223, 214, 238));
    DrawText(43, 177, Format('CLIMB      %4.1f km/s',
      [FVerticalSpeed]), 10, RGB(223, 214, 238));
  end;

  FuelLeft := Min(384, ClientWidth - 540);
  FuelPanel := Rect(FuelLeft - 24, ClientHeight - 95, FuelLeft + 526,
    ClientHeight - 12);
  Canvas.Pen.Color := RGB(96, 66, 133);
  Canvas.Brush.Color := RGB(20, 10, 38);
  Canvas.RoundRect(FuelPanel.Left, FuelPanel.Top, FuelPanel.Right,
    FuelPanel.Bottom, 9, 9);
  DrawText(FuelLeft, ClientHeight - 79,
    Format('FUEL REMAINING   %4.1f%%', [FFuel]), 10,
    RGB(222, 207, 239), True);
  BarWidth := 500;
  Canvas.Brush.Color := RGB(43, 28, 66);
  Canvas.FillRect(Rect(FuelLeft, ClientHeight - 50, FuelLeft + BarWidth,
    ClientHeight - 25));
  FuelWidth := Round(BarWidth * EnsureRange(FFuel / 100, 0.0, 1.0));
  if FFuel > 50 then
    FuelColor := RGB(168, 85, 247)
  else if FFuel > 20 then
    FuelColor := RGB(216, 180, 254)
  else
    FuelColor := RGB(240, 110, 165);
  if FuelWidth > 0 then
  begin
    Canvas.Brush.Color := FuelColor;
    Canvas.FillRect(Rect(FuelLeft, ClientHeight - 50,
      FuelLeft + FuelWidth, ClientHeight - 25));
  end;
  Canvas.Pen.Color := RGB(139, 110, 170);
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(FuelLeft, ClientHeight - 50,
    FuelLeft + BarWidth, ClientHeight - 25);
  Canvas.Brush.Style := bsSolid;

  DrawText(ClientWidth - 235, 27, 'MISSION  /  MOON', 10,
    RGB(194, 172, 221), True);
  DrawText(ClientWidth - 235, 47, '01  LAUNCH  >  02  MOON ORBIT', 9,
    RGB(158, 136, 184));
  DrawText(ClientWidth - 235, 64, '03  LANDING', 9, RGB(158, 136, 184));
end;

procedure TForm1.DrawLaunchScene;
var
  GroundY, RocketY: Integer;
begin
  GroundY := ClientHeight - 112;
  Canvas.Brush.Color := RGB(25, 12, 48);
  Canvas.Pen.Color := RGB(88, 59, 126);
  Canvas.Ellipse(ClientWidth div 2 - 370, GroundY - 94,
    ClientWidth div 2 + 370, GroundY + 520);
  Canvas.Brush.Color := RGB(33, 17, 51);
  Canvas.Pen.Color := RGB(109, 72, 151);
  Canvas.Rectangle(0, GroundY, ClientWidth, ClientHeight);
  Canvas.Pen.Color := RGB(157, 118, 204);
  Canvas.MoveTo(ClientWidth div 2 - 42, GroundY);
  Canvas.LineTo(ClientWidth div 2 - 42, GroundY - 75);
  Canvas.LineTo(ClientWidth div 2 + 42, GroundY - 75);
  Canvas.LineTo(ClientWidth div 2 + 42, GroundY);
  RocketY := GroundY - 87 - Round(FAltitude * 1.4);
  DrawRocket(ClientWidth div 2, RocketY, FAngle);
end;

procedure TForm1.DrawOrbitScene;
var
  CX, CY: Integer;
  OrbitRadius, ActualRadius, RocketX, RocketY: Integer;
begin
  CX := ClientWidth div 2;
  CY := ClientHeight div 2 + 35;
  OrbitRadius := Min(220, ClientWidth div 3);
  ActualRadius := OrbitRadius +
    Round((FAltitude - OrbitTargetAltitude) * 2);

  Canvas.Pen.Style := psDash;
  Canvas.Pen.Color := RGB(75, 52, 111);
  Canvas.Brush.Style := bsClear;
  Canvas.Ellipse(CX - OrbitRadius - 16, CY - OrbitRadius - 16,
    CX + OrbitRadius + 16, CY + OrbitRadius + 16);
  Canvas.Ellipse(CX - OrbitRadius + 16, CY - OrbitRadius + 16,
    CX + OrbitRadius - 16, CY + OrbitRadius - 16);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := RGB(168, 85, 247);
  Canvas.Ellipse(CX - OrbitRadius, CY - OrbitRadius,
    CX + OrbitRadius, CY + OrbitRadius);
  Canvas.Pen.Style := psDot;
  Canvas.Pen.Color := RGB(216, 180, 254);
  Canvas.Ellipse(CX - ActualRadius, CY - ActualRadius,
    CX + ActualRadius, CY + ActualRadius);
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsSolid;

  DrawImage(FMoonImage, CX, CY, 150, 150);
  DrawImage(FEarthImage, CX + OrbitRadius + 58,
    CY - OrbitRadius + 28, 54, 54);
  RocketX := CX + Round(ActualRadius * Cos(FOrbitAngle));
  RocketY := CY + Round(ActualRadius * Sin(FOrbitAngle));
  DrawRocket(RocketX, RocketY, FOrbitAngle + Pi / 2);
  DrawText(CX - 103, CY + 126, 'MOON ORBIT  /  TARGET 100 KM', 9,
    RGB(194, 172, 221), True);
  if FOrbitCaptured then
    DrawText(CX - 177, ClientHeight - 190,
      'MOON ORBIT CAPTURED  /  STARTING LANDING', 9,
      RGB(190, 132, 252), True)
  else
    DrawText(CX - 184, ClientHeight - 190,
      'UP: RAISE ALTITUDE     DOWN: LOWER ALTITUDE     HOLD PURPLE TRACK',
      9, RGB(210, 194, 228), True);
end;

procedure TForm1.DrawLandingScene;
var
  GroundY, RocketX, RocketY, I, TerrainY: Integer;
begin
  GroundY := ClientHeight - 126;
  Canvas.Brush.Color := RGB(44, 31, 58);
  Canvas.Pen.Color := RGB(44, 31, 58);
  Canvas.Rectangle(0, GroundY + 25, ClientWidth, ClientHeight);
  DrawImage(FMoonImage, ClientWidth div 2,
    GroundY + Round(ClientWidth * 0.6), Round(ClientWidth * 1.5),
    Round(ClientWidth * 1.5));
  for I := 0 to 11 do
  begin
    TerrainY := GroundY + 42 + (I mod 4) * 21;
    Canvas.Pen.Color := RGB(94, 69, 113);
    Canvas.MoveTo((I * 109) mod ClientWidth, TerrainY);
    Canvas.LineTo((I * 109) mod ClientWidth + 34, TerrainY + 3);
  end;

  Canvas.Pen.Width := 3;
  Canvas.Pen.Color := RGB(197, 153, 255);
  Canvas.MoveTo(ClientWidth div 2 - 47, GroundY + 4);
  Canvas.LineTo(ClientWidth div 2 + 47, GroundY + 4);
  Canvas.Pen.Width := 1;
  DrawText(ClientWidth div 2 - 50, GroundY + 15, 'LANDING ZONE',
    8, RGB(215, 186, 255), True);

  RocketX := ClientWidth div 2 + Round(FHorizontalPosition * 0.48);
  RocketY := GroundY - 28 - Round(Max(0, FAltitude) * 0.32);
  DrawRocket(RocketX, RocketY, -FHorizontalSpeed * 0.012);
  if FStage = fsLanded then
    DrawImage(FFlagImage, ClientWidth div 2 + 160, GroundY - 43, 210, 126);

  DrawText(ClientWidth div 2 - 85, 100,
    Format('DISTANCE TO PAD  %4.0f m', [Abs(FHorizontalPosition)]),
    10, RGB(211, 197, 225), True);
end;

procedure TForm1.DrawMessage(const Title, Detail: string);
var
  Box: TRect;
  TextWidth: Integer;
begin
  Box := Rect(ClientWidth div 2 - 240, ClientHeight div 2 - 98,
    ClientWidth div 2 + 240, ClientHeight div 2 + 98);
  Canvas.Brush.Color := RGB(20, 10, 38);
  Canvas.Pen.Color := RGB(104, 69, 143);
  Canvas.RoundRect(Box.Left, Box.Top, Box.Right, Box.Bottom, 18, 18);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 24;
  Canvas.Font.Style := [fsBold];
  TextWidth := Canvas.TextWidth(Title);
  DrawText(ClientWidth div 2 - TextWidth div 2, Box.Top + 35, Title,
    24, RGB(245, 238, 255), True);
  Canvas.Font.Size := 11;
  TextWidth := Canvas.TextWidth(Detail);
  DrawText(ClientWidth div 2 - TextWidth div 2, Box.Top + 91, Detail,
    11, RGB(196, 177, 216));
end;

procedure TForm1.DrawHowToPlay;
var
  Box: TRect;
  X, Y, Center: Integer;
begin
  Box := Rect(ClientWidth div 2 - 320, ClientHeight div 2 - 230,
    ClientWidth div 2 + 320, ClientHeight div 2 + 230);
  Canvas.Brush.Color := RGB(20, 10, 38);
  Canvas.Pen.Color := RGB(168, 85, 247);
  Canvas.RoundRect(Box.Left, Box.Top, Box.Right, Box.Bottom, 18, 18);

  X := Box.Left + 28;
  Y := Box.Top + 20;
  Center := ClientWidth div 2;
  DrawText(X, Y, 'HOW TO PLAY', 22, RGB(245, 238, 255), True);
  DrawText(X, Y + 43, '1  LAUNCH', 12, RGB(190, 132, 252), True);
  DrawKeyCap(X, Y + 68, 'SPACE');
  DrawText(X + 73, Y + 72, 'Hold to launch. Release when orbit begins.',
    10, RGB(223, 214, 238));

  DrawText(X, Y + 111, '2  STAY IN MOON ORBIT', 12,
    RGB(190, 132, 252), True);
  DrawKeyCap(X, Y + 136, 'UP');
  DrawKeyCap(X + 65, Y + 136, 'DOWN');
  DrawText(X + 142, Y + 140, 'Tap to target 100 km. Safe range: 60-140 km.',
    10, RGB(223, 214, 238));
  DrawText(X + 73, Y + 166,
    'Climbing too fast? Tap DOWN. Falling? Tap UP.',
    10, RGB(223, 214, 238));
  DrawText(X + 73, Y + 186, 'Hold the purple orbit steady for 3 seconds.',
    10, RGB(223, 214, 238));
  DrawText(X + 73, Y + 206,
    'Tap UP or DOWN alone (0.25% fuel/sec); pressing both cancels for free.',
    10, RGB(223, 214, 238));

  DrawText(X, Y + 225, '3  CHOOSE YOUR LANDING MODE', 12,
    RGB(190, 132, 252), True);
  DrawKeyCap(X, Y + 250, 'M');
  DrawText(X + 73, Y + 254,
    'During landing, press to switch between AUTO and MANUAL.',
    10, RGB(223, 214, 238));
  DrawText(X, Y + 282,
    'AUTO: autopilot guides to the pad and manages braking.',
    10, RGB(223, 214, 238));
  DrawText(X, Y + 306,
    'MANUAL: SPACE brakes against gravity; A / D or arrows steer.',
    10, RGB(223, 214, 238));
  DrawText(X, Y + 326,
    'Land on the pad below 7 m/s down and 22 m/s sideways.',
    10, RGB(223, 214, 238));

  Canvas.Pen.Color := RGB(75, 52, 111);
  Canvas.MoveTo(X, Y + 376);
  Canvas.LineTo(Box.Right - 28, Y + 376);
  DrawText(X, Y + 389, 'R  RESTART', 9, RGB(210, 194, 228), True);
  DrawText(Center + 10, Y + 389, 'A smooth landing beats a fast one.',
    9, RGB(190, 132, 252), True);
end;

procedure TForm1.DrawKeyCap(X, Y: Integer; const Caption: string);
var
  TextWidth: Integer;
begin
  Canvas.Pen.Color := RGB(124, 89, 158);
  Canvas.Brush.Color := RGB(47, 30, 73);
  Canvas.RoundRect(X, Y, X + 58, Y + 25, 6, 6);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 9;
  Canvas.Font.Style := [fsBold];
  TextWidth := Canvas.TextWidth(Caption);
  DrawText(X + (58 - TextWidth) div 2, Y + 4, Caption, 9,
    RGB(245, 238, 255), True);
end;

procedure TForm1.DrawFlightHint;
var
  HintText: string;
  Box: TRect;
begin
  case FStage of
    fsLaunch:
      HintText := 'HOLD SPACE TO CLIMB (2.5% FUEL/SEC)  |  A / D TO STEER';
    fsOrbit:
      if FOrbitCaptured then
        HintText := 'ORBIT LOCKED  |  LANDING STARTS AUTOMATICALLY'
      else if FUpDown and FDownDown then
        HintText := 'UP + DOWN CANCEL OUT  |  NO THRUST OR FUEL USED'
      else if (FVerticalSpeed > 0.02) and
        (FAltitude >= OrbitTargetAltitude - 5) then
        HintText := 'CLIMBING  |  TAP DOWN TO SLOW  |  0.25% FUEL/SEC WHILE HELD'
      else if (FVerticalSpeed < -0.02) and
        (FAltitude <= OrbitTargetAltitude + 5) then
        HintText := 'FALLING  |  TAP UP TO SLOW  |  0.25% FUEL/SEC WHILE HELD'
      else if FAltitude < OrbitTargetAltitude - OrbitCaptureTolerance then
        HintText := 'BELOW TARGET  |  TAP UP TO RAISE ORBIT  |  0.25% FUEL/SEC WHILE HELD'
      else if FAltitude > OrbitTargetAltitude + OrbitCaptureTolerance then
        HintText := 'ABOVE TARGET  |  TAP DOWN TO LOWER ORBIT  |  0.25% FUEL/SEC WHILE HELD'
      else
        HintText := 'NEAR TARGET  |  RELEASE KEYS AND LET THE ROCKET SETTLE';
    fsLanding:
      if FLandingMode = lmAutomatic then
        HintText := 'AUTO LANDING  |  AUTOPILOT GUIDES TO PAD  |  PRESS M FOR MANUAL'
      else
        HintText := 'MANUAL  |  SPACE BRAKES AGAINST GRAVITY  |  A / D STEER  |  M = AUTO';
  else
    HintText := '';
  end;
  if HintText = '' then
    Exit;

  Box := Rect(28, ClientHeight - 166, ClientWidth - 28,
    ClientHeight - 138);
  Canvas.Pen.Color := RGB(75, 52, 111);
  Canvas.Brush.Color := RGB(20, 10, 38);
  Canvas.RoundRect(Box.Left, Box.Top, Box.Right, Box.Bottom, 8, 8);
  DrawText(Box.Left + 12, Box.Top + 6, HintText, 9,
    RGB(230, 219, 244), True);
end;

procedure TForm1.FormPaint(Sender: TObject);
begin
  DrawBackground;
  case FStage of
    fsReady, fsLaunch: DrawLaunchScene;
    fsOrbit: DrawOrbitScene;
    fsCrashed:
      if FOrbitFailed then
        DrawOrbitScene
      else
        DrawLandingScene;
    fsLanding, fsLanded: DrawLandingScene;
  end;
  DrawHud;
  DrawFlightHint;
  case FStage of
    fsReady:
      DrawHowToPlay;
    fsLanded:
      DrawMessage('SUCCESSFUL LANDING',
        'Touchdown! ENTER: mission report   R: fly again');
    fsCrashed:
      if FOrbitFailed then
        DrawMessage('ORBIT LOST',
          'Left the 60-140 km orbit. ENTER: report   R: retry')
      else
        DrawMessage('MISSION FAILED',
          'Too hard or off the pad. ENTER: report   R: retry');
  end;
end;

end.
