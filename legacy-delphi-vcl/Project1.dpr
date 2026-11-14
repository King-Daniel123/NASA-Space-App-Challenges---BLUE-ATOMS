program Project1;

uses
  Vcl.Forms,
  Unit1 in 'Unit1.pas' {frmLaunch},
  Unit2 in 'Unit2.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmLaunch, frmLaunch);
  Application.Run;
end.
