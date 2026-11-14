unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls,
  Vcl.Imaging.pngimage, System.Diagnostics, System.Math, Vcl.Imaging.jpeg;

type
  TfrmLaunch = class(TForm)
    imgBackground: TImage;
    imgGround: TImage;
    Image1: TImage;
    imgThruster2: TImage;
    imgThruster1: TImage;
    tmrMovement: TTimer;
    lblheight: TLabel;
    btnStart: TButton;
    procedure FormCreate(Sender: TObject);
    procedure time(Sender: TObject);
    procedure tmrMovementTimer(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
  private
    { Private declarations }
    procedure createcloud;
    procedure thrust;
  public
    { Public declarations }
  end;

var
  frmLaunch: TfrmLaunch;
  rSpeed: Integer;
  rA: Real;
  dt1, dt2: Real;
  rMass: Real;
  rForce: Real;
  iheight: Integer;
  NewTime1, newTime2, oldTime1, oldTime2: TTime;
  stopwatch1, stopwatch2: TStopwatch;
  arrCloud: array [1 .. 100] of TImage;
  tmrClouds: TTimer;
  iCountCloud: Integer;
  iNoClouds: Integer;

const
  Distance: Integer = 1000;
  rG: Real = 9.8;

implementation

procedure TfrmLaunch.thrust;
begin
  rMass := rMass - 10000;
  rA := (rForce / rMass);
  imgThruster1.Top := imgThruster1.Top + Round(rA * dt1);
  imgThruster2.Top := imgThruster2.Top + Round(rA * dt1);
end;

{$R *.dfm}
{$R SceneAssets.res}


procedure TfrmLaunch.btnStartClick(Sender: TObject);
begin
  rMass := strToFloat(InputBox('Mass', '', ''));
  rForce := strToFloat(InputBox('Force', '', ''));
  rA := (rForce / rMass);
  iheight := 0;
  rSpeed := 0;
  tmrMovement.Enabled := True;
  stopwatch1 := TStopwatch.StartNew;
end;

procedure TfrmLaunch.createcloud;
var
  I: Integer;
begin
  tmrClouds := TTimer.Create(Self);
  tmrClouds.Interval := 1000;
  tmrClouds.Enabled := False;
  iNoClouds := RandomRange(1, 11);
  for I := 1 to iNoClouds do
  begin
    arrCloud[I] := TImage.Create(frmLaunch);
    arrCloud[I].Parent := frmLaunch;
    arrCloud[I].Picture.LoadFromFile('Cloud.jpeg');
    arrCloud[I].Stretch := True;
    arrCloud[I].Height := RandomRange(60, 101);
    arrCloud[I].Width := Round(arrCloud[I].Height * 1.8);
    arrCloud[I].Top := RandomRange(-arrCloud[I].Height, 0);
    arrCloud[I].Left := RandomRange(0, Max(1, ClientWidth - arrCloud[I].Width + 1));
  end;
  tmrClouds.OnTimer := time;
  tmrClouds.Enabled := True;
end;

procedure TfrmLaunch.FormCreate(Sender: TObject);
begin
  Randomize;
  iCountCloud := 0;
end;

procedure TfrmLaunch.time(Sender: TObject);
var
  I: Integer;
begin
  for I := 1 to iNoClouds do
  begin
    arrCloud[I].Top := arrCloud[I].Top + Round(rA * dt1);
  end;
end;

procedure TfrmLaunch.tmrMovementTimer(Sender: TObject);
begin
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
end;

end.
