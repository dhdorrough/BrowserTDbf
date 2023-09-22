unit GetString;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type
  TGetInfo = record
    WindowCaption: string;
    Label1Caption: string;
    Label2Caption: string;
    value: string;
  end;

  PGetInfo = ^TGetInfo;

  TfrmGetString = class(TForm)
    Edit1: TEdit;
    Button1: TButton;
    Button2: TButton;
    Label1: TLabel;
    Label2: TLabel;
    procedure Button2Click(Sender: TObject);
  private
    { Private declarations }
    fGetInfo: PGetInfo;
  public
    { Public declarations }
    constructor Create(aOwner: TComponent; GetInfo: PGetInfo); reintroduce;
  end;

var
  frmGetString: TfrmGetString;

implementation

{$R *.dfm}

{ TForm1 }

constructor TfrmGetString.Create(aOwner: TComponent; GetInfo: PGetInfo);
begin
  inherited Create(aOwner);
  fGetInfo := GetInfo;
  with GetInfo^ do
    begin
      Caption   := WindowCaption;
      Label1.Caption := Label1Caption;
      Label2.Caption := Label2Caption;
      Edit1.Text := Value;
    end;
end;

procedure TfrmGetString.Button2Click(Sender: TObject);
begin
  fGetInfo^.Value := Edit1.Text;
end;

end.
