program AtomicSpace_p;

uses
  Vcl.Forms,
  StartUp_u in 'StartUp_u.pas' {frmStart},
  Rocket_Plan in 'Rocket_Plan.pas' {frmRocket},
  Game in 'Game.pas' {frmGame},
  Launch_u in 'Launch_u.pas' {frmLaunch},
  Unit1 in 'Unit1.pas' {Form1},
  MissionPlan_u in 'MissionPlan_u.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmStart, frmStart);
  Application.CreateForm(TfrmRocket, frmRocket);
  Application.CreateForm(TfrmGame, frmGame);
  Application.CreateForm(TfrmLaunch, frmLaunch);
  Application.Run;
end.
