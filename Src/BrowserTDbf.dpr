// Program was compiled with Delphi 7.0 (Build 8.1)
// Program uses Turbo Power Orpheus library (available on SourceForge)
// Program uses Turbo Power Systools library (available on SourceForge)
// Program Uses TDbf (https://sourceforge.net/projects/tdbf/)
program BrowserTDbf;
uses
  Forms,
  uBrowserTDbf in 'uBrowserTDbf.pas' {Form_Browser},
  uBrowseMemo in 'uBrowseMemo.pas' {frmBrowseMemo},
  GotoRecNo in 'GotoRecNo.pas' {frmGotoRecNo},
  uAbout in 'uAbout.pas' {AboutBox},
  MyUtils in '..\..\..\..\D7\Projects\MyUtils\MyUtils.pas',
  KillIt in '..\..\..\..\D7\Projects\MyUtils\KillIt.pas';

{$R *.RES}

begin
  Application.Initialize;
  Application.CreateForm(TForm_Browser, Form_Browser);
  Application.CreateForm(TfrmGotoRecNo, frmGotoRecNo);
  Application.CreateForm(TAboutBox, AboutBox);
  Application.Run;
end.
