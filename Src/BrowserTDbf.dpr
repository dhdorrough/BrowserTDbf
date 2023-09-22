program BrowserTDbf;

{%File '..\..\..\LibSrc\Soundex.inc'}
{%File '..\..\..\changes\Versions.txt'}

uses
  QForms,
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
