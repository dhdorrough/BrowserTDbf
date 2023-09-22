unit uAbout;

interface

uses Windows, SysUtils, Classes, Graphics, Forms, Controls, StdCtrls,
  Buttons, ExtCtrls;

type
  TAboutBox = class(TForm)
    Panel1: TPanel;
    ProgramIcon: TImage;
    ProductName: TLabel;
    lblVersion: TLabel;
    Copyright: TLabel;
    Comments: TLabel;
    OKButton: TButton;
  private
    { Private declarations }
  public
    { Public declarations }
    Constructor Create(aOwner: TComponent); override;
  end;

var
  AboutBox: TAboutBox;

implementation

{$R *.dfm}

uses
  uBrowserTDbf;

{ TAboutBox }

constructor TAboutBox.Create(aOwner: TComponent);
begin
  inherited;

  lblVersion.Caption := Format('Version %s', [uBrowserTDbf.Version]);

end;

end.
 
