unit Rocket_Plan;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Imaging.pngimage,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.ToolWin, Vcl.ActnMan, Vcl.ActnCtrls,XPStyleActnCtrls,
  Vcl.ActnMenus;

type
  TfrmRocket = class(TForm)
    Image1: TImage;
    btnPrevious: TButton;
    btnNext: TButton;
    Image2: TImage;
    btnBase: TButton;
    btnThrust: TButton;
    memInfo: TMemo;
    imgRocket: TImage;
    imgThrust_2: TImage;
    imgThrust_1: TImage;
    ActionMainMenuBar1: TActionMainMenuBar;
    imgPresident: TImage;
    Timer1: TTimer;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  frmRocket: TfrmRocket;


implementation

{$R *.dfm}

procedure TfrmRocket.FormCreate(Sender: TObject);
begin

//ShowMessage('You are going to Plan Your Rocket Shape and structure based on the mission you are going to Implement.');
end;

end.
