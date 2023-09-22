unit uBrowseMemo;

interface

uses
  SysUtils, Classes, DB,
  Forms, Dialogs,
  Menus, StdCtrls, DBCtrls, ComCtrls, Controls, ExtCtrls;

type
  TBrowseHow = (bhAsText, bhAsObject);

  TfrmBrowseMemo = class(TForm)
    Panel1: TPanel;
    Panel2: TPanel;
    Button1: TButton;
    cbWordWrap: TCheckBox;
    PageControl1: TPageControl;
    Tabsheet_AsText: TTabSheet;
    Tabsheet_AsObject: TTabSheet;
    MemoText: TDBMemo;
    MemoObject: TMemo;
    MainMenu1: TMainMenu;
    File1: TMenuItem;
    Exit1: TMenuItem;
    Edit1: TMenuItem;
    Find1: TMenuItem;
    FindDialog1: TFindDialog;
    FindAgain1: TMenuItem;
    Print1: TMenuItem;
    PrintSetup1: TMenuItem;
    procedure Button1Click(Sender: TObject);
    procedure Panel1Resize(Sender: TObject);
    procedure cbWordWrapClick(Sender: TObject);
    procedure Find1Click(Sender: TObject);
    procedure FindAgain1Click(Sender: TObject);
    procedure Edit1Click(Sender: TObject);
    procedure Print1Click(Sender: TObject);
    procedure PrintSetup1Click(Sender: TObject);
    procedure Exit1Click(Sender: TObject);
  private
    { Private declarations }
    fBrowseHow: TBrowseHow;
    fBuffer: pchar;
    fBufPtr: pchar;
    fBufEnd: pchar;
    fField: TField;
    procedure FindDialogOnFind(Sender: TObject);
    function FindNext: pchar;
    procedure ShowFoundText(p: pchar);
  public
    { Public declarations }
    constructor Create( AOwner: TComponent;
                        aDataSource: TDataSource;
                        aField: TField;
                        aBrowseHow: TBrowseHow); reintroduce;
    procedure UpdateObjectMemo;
    property BrowseHow: TBrowseHow
             read fBrowseHow;
  end;

var
  frmBrowseMemo: TfrmBrowseMemo;

function MemoContainsObject(aField: TField): boolean;

implementation

{$R *.dfm}

uses
  MyUtils;

procedure TfrmBrowseMemo.UpdateObjectMemo;
  var
    Input: TStream;
    Output: TMemoryStream;
    DataSet: TDataset;
begin
  if fField is TBlobField then
    begin
      DataSet := fField.DataSet;
      if not DataSet.Eof then
        begin
          MemoText.Clear;
          Input  := DataSet.CreateBlobStream(fField, bmRead);
          Output := TMemoryStream.Create;
          try
            ObjectBinaryToText(Input, Output);
            Output.Position := 0;
            MemoObject.Lines.LoadFromStream(Output);
          finally
            Input.Free;
            Output.Free;
          end;
        end;
    end;
end;

constructor TfrmBrowseMemo.Create( AOwner: TComponent;
                                aDataSource: TDataSource;
                                aField: TField;
                                aBrowseHow: TBrowseHow);
begin
  inherited Create(Owner);
  fBrowseHow         := aBrowseHow;
  Caption            := 'Memo: ' + aField.DisplayName;
  case BrowseHow of
    bhAsText:
      begin
        MemoText.DataSource := aDataSource;
        MemoText.DataField  := aField.FieldName;
        PageControl1.ActivePage := TabSheet_AsText;
      end;
    bhAsObject:
      begin
        fField := aField;
        UpdateObjectMemo;
        PageControl1.ActivePage := Tabsheet_AsObject;
      end;
  end;
end;

procedure TfrmBrowseMemo.Button1Click(Sender: TObject);
begin
  Close;
end;

procedure TfrmBrowseMemo.Panel1Resize(Sender: TObject);
begin
  Button1.Left := (Panel1.Width - Button1.Width) div 2;
end;

procedure TfrmBrowseMemo.cbWordWrapClick(Sender: TObject);
begin
  case fBrowseHow of
    bhAsText:
      begin
        MemoText.WordWrap := cbWordWrap.Checked;
        if MemoText.WordWrap then
          MemoText.ScrollBars  := ssVertical
        else
          MemoText.ScrollBars  := ssBoth;
      end;
    bhAsObject:
      begin
        MemoObject.WordWrap := cbWordWrap.Checked;
        if MemoObject.WordWrap then
          MemoObject.ScrollBars  := ssVertical
        else
          MemoObject.ScrollBars  := ssBoth;
      end;
  end;

end;

function MemoContainsObject(aField: TField): boolean;
  var
    Input: TStream;
    Output: TMemoryStream;
begin
  result := false;
  if aField is TBlobField then
    begin
//    Input  := TBlobStream.Create(aField as TBlobField, bmRead);
      Input  := aField.DataSet.CreateBlobStream(aField, bmRead);
      Output := TMemoryStream.Create;
      try
        try
          ObjectBinaryToText(Input, Output);
          result := true;
        except
          result := false;
        end;
      finally
        Input.Free;
        Output.Free;
      end;
    end;
end;


procedure TfrmBrowseMemo.Find1Click(Sender: TObject);
begin
  with FindDialog1 do
    begin
      OnFind  := FindDialogOnFind;
      case fBrowseHow of
        bhAsText:
          begin
            fBuffer := MemoText.Lines.GetText;
            fBufPtr := fBuffer;
            fBufEnd := fBuffer + Length(MemoText.Lines.Text);
          end;
        bhAsObject:
          begin
            fBuffer := MemoObject.Lines.GetText;
            fBufPtr := fBuffer;
            fBufEnd := fBuffer + Length(MemoObject.Lines.Text);
          end;
      end;
      Execute;
    end;
end;

procedure TfrmBrowseMemo.FindDialogOnFind(Sender: TObject);
begin
  ShowFoundText(FindNext);
//FindDialog1.CloseDialog;
end;

procedure TfrmBrowseMemo.ShowFoundText(p: pchar);
begin
  if p <> nil then
    case fBrowseHow of
      bhAsText:
        begin
          MemoText.SelStart  := p - fBuffer;
          MemoText.SelLength := Length(FindDialog1.FindText);
          MemoText.SetFocus;
        end;
      bhAsObject:
        begin
          MemoObject.SelStart  := p - fBuffer;
          MemoObject.SelLength := Length(FindDialog1.FindText);
          MemoObject.SetFocus;
        end;
    end
  else
    raise Exception.Create('Not found');
end;

function MyStrPos(buf: pchar; target: pchar; bufend : pchar; IgnoreCase: boolean): pchar;
  var
    mode : tSEARCH_TYPE;
    len  : integer;
    i: integer;
begin
  len  := StrLen(Target);
  mode := SEARCHING;
  repeat
    if (buf + len) > bufend then
      mode := NOT_FOUND
    else
      begin
        if IgnoreCase then
          i := StrLIComp(buf, target, len)
        else
          i := StrLComp(buf, target, len);

        if i = 0 then
          mode := SEARCH_FOUND
        else
          inc(buf);
      end;

  until mode <> SEARCHING;
  if mode = SEARCH_FOUND then
    result := buf
  else
    result := nil;
end;

function TfrmBrowseMemo.FindNext: pchar;
  var
    MatchString: string;
    IgnoreCase: boolean;
begin
  with FindDialog1 do
    begin
      IgnoreCase := not (frMatchCase in Options);
      MatchString := FindText;

      result := MyStrPos(pchar(fBufPtr), pchar(MatchString), fBufEnd, IgnoreCase);

      if result <> nil then
        fBufPtr := result + Length(MatchString);
    end;
end;



procedure TfrmBrowseMemo.FindAgain1Click(Sender: TObject);
begin
  with FindDialog1 do
    begin
      fBufPtr := fBufPtr + Length(FindText);
      ShowFoundText(FindNext);
    end;
end;

procedure TfrmBrowseMemo.Edit1Click(Sender: TObject);
begin
  FindAgain1.Enabled := Assigned(fBufPtr);
end;

procedure TfrmBrowseMemo.Print1Click(Sender: TObject);
//var
//  Printer: TextFile;
//  i: integer;
begin
(*
  AssignPrn(Printer);
  ReWrite(Printer);
  try
    if PageControl1.ActivePage = Tabsheet_AsText then
      begin
        with MemoText do
          begin
            for i := 0 to Lines.Count-1 do
              Writeln(Printer, Lines[i]);
          end;
      end else
    if PageControl1.ActivePage = Tabsheet_AsObject then
      begin
        with MemoObject do
          begin
            for i := 0 to Lines.Count-1 do
              Writeln(Printer, Lines[i]);
          end;
      end
    else
      raise Exception.Create('System Error: Unknown tabsheet');
  finally
    CloseFile(Printer);
  end;
*)
end;

procedure TfrmBrowseMemo.PrintSetup1Click(Sender: TObject);
begin
//with PrinterSetupDialog1 do
//  begin
//    Execute;
//  end;
end;

procedure TfrmBrowseMemo.Exit1Click(Sender: TObject);
begin
  Close;
end;

end.
