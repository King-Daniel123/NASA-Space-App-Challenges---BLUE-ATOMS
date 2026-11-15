unit StartUp_u;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg, Vcl.ExtCtrls, XPStyleActnCtrls;

type
  TfrmStart = class(TForm)
    Image1: TImage;
    Image2: TImage;
    ProgressBar1: TProgressBar;
    lblLoading: TLabel;
    btnStart: TButton;
    btnHow: TButton;
    Timer1: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
    procedure btnHowClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  frmStart: TfrmStart;

implementation
uses Game, Unit1;

{$R *.dfm}

procedure TfrmStart.btnStartClick(Sender: TObject);
begin
     frmGame.show;
     frmStart.hide;
end;

procedure TfrmStart.btnHowClick(Sender: TObject);
begin
  ShowAtomicMission(Game.arrRocket[Game.Rocket]);
end;

procedure TfrmStart.FormCreate(Sender: TObject);
begin
     btnStart.visible := False;
     btnHow.Visible := False;
     progressbar1.BackgroundColor := clPurple;

end;

procedure TfrmStart.Timer1Timer(Sender: TObject);
begin
ProgressBar1.Position := ProgressBar1.Position + 1;

  if ProgressBar1.Position >= 100 then
  begin
    Timer1.Enabled := False;
    btnStart.Visible := True;
    btnHow.Visible := True;
    lblLoading.Visible := False;
    progressbar1.Visible := False;
  end;
end;

end.
