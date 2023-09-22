{$undef OldVersion}
unit uBrowserTDbf;

// 03/04/2011 dhd CR 18373-10 added IndexName & Expression value display
// 03/04/2011 dhd CR 18373-9 added ability to find record by key
// 03/04/2011 dhd CR 18373-8 added ability to filter on field
// 02/10/2011 dhd CR 18373-7 remove obsolete code related to string search
// 02/10/2011 dhd CR 18373-6 display error on locale error
// 02/10/2011 dhd CR 18373-5 ability to specify a filter expression
// 02/10/2011 dhd CR 18373-4 ability to show hidden records
// 02/10/2011 dhd CR 18373-3 ability to go to record number
// 01/03/2011 spb CR 18373-2 remove reference to QForms
// 02/10/2011 dhd CR 18373-1 Modify browser to remove dependency on BDE and use TDbf instead

interface

uses
  SysUtils, Classes, 
  Forms, Menus, Dialogs, Grids, DBGrids, DBCtrls, Controls,
  StdCtrls, ExtCtrls,
  uBrowseMemo, DB, dbf_idxfile, dbf, GetString;

const
  Version = '1.10';
  
type
  TForm_Browser = class(TForm)
    Panel1: TPanel;
    Panel2: TPanel;
    OpenDialog1: TOpenDialog;
    Panel4: TPanel;
    DBNavigator1: TDBNavigator;
    lblRecordNumber: TLabel;
    btnRecNo: TButton;
    MainMenu1: TMainMenu;
    File1: TMenuItem;
    Exit1: TMenuItem;
    N2: TMenuItem;
    Open1: TMenuItem;
    Close1: TMenuItem;
    Navigate1: TMenuItem;
    FindRecord1: TMenuItem;
    AddRecord1: TMenuItem;
    TopRecord1: TMenuItem;
    PreviousRecord1: TMenuItem;
    NextRepord1: TMenuItem;
    BottomRecord1: TMenuItem;
    HideRecord1: TMenuItem;
    N1: TMenuItem;
    Order1: TMenuItem;
    N3: TMenuItem;
    RebuildIndexes1: TMenuItem;
    N4: TMenuItem;
    RecentDBFs1: TMenuItem;
    Label_DBFName: TLabel;
    FindDialog1: TFindDialog;
    PackTable1: TMenuItem;
    PopupMenu1: TPopupMenu;
    DisplayMemoasText1: TMenuItem;
    DisplayMemoasObjects1: TMenuItem;
    MovetoFirstColumn1: TMenuItem;
    DataSource1: TDataSource;
    DBGrid1: TDBGrid;
    GotoRecord1: TMenuItem;
    ShowHiddenRecords1: TMenuItem;
    N5: TMenuItem;
    SpecifyFilterExpression1: TMenuItem;
    Help1: TMenuItem;
    AboutTDbfBrowser1: TMenuItem;
    FindKey1: TMenuItem;
    lblIsNullField: TLabel;
    lblHiddenRecord: TLabel;
    procedure Table1AfterScroll(DataSet: TDataSet);
    procedure FormCreate(Sender: TObject);
    procedure DBGrid1DblClick(Sender: TObject);
    procedure Table1AfterOpen(DataSet: TDataSet);
    procedure btnRebuildIndexesClick(Sender: TObject);
    procedure Open1Click(Sender: TObject);
    procedure Exit1Click(Sender: TObject);
    procedure Navigate1Click(Sender: TObject);
    procedure Close1Click(Sender: TObject);
    procedure AddRecord1Click(Sender: TObject);
    procedure TopRecord1Click(Sender: TObject);
    procedure PreviousRecord1Click(Sender: TObject);
    procedure NextRepord1Click(Sender: TObject);
    procedure BottomRecord1Click(Sender: TObject);
    procedure HideRecord1Click(Sender: TObject);
    procedure RebuildIndexes1Click(Sender: TObject);
    procedure FindDialog1Find(Sender: TObject);
    procedure FindRecord1Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure PackTable1Click(Sender: TObject);
    procedure DisplayMemoasText1Click(Sender: TObject);
    procedure DisplayMemoasObjects1Click(Sender: TObject);
    procedure PopupMenu1Popup(Sender: TObject);
    procedure MovetoFirstColumn1Click(Sender: TObject);
    procedure GotoRecord1Click(Sender: TObject);
    procedure ShowHiddenRecords1Click(Sender: TObject);
    procedure btnRecNoClick(Sender: TObject);
    procedure SpecifyFilterExpression1Click(Sender: TObject);
    procedure AboutTDbfBrowser1Click(Sender: TObject);
    procedure FindKey1Click(Sender: TObject);
    procedure DBGrid1CellClick(Column: TColumn);
    procedure DBGrid1ColEnter(Sender: TObject);
  private
    { Private declarations }
    fDefaultPath: string;
    fFilterExpression: string;
    fHomeDir: string;
    fIniFileName: string;
    fLastSearch: string;
    RecentDBFs: TStringList;
    BrowseMemoList: TList;
    procedure OrderClick(Sender: TObject);
    procedure Enable_Stuff;
    procedure EnableNavigateMenu;
    procedure ReBuildIndexes;
    procedure UpdateTagNames;
    procedure CloseDBF;
    procedure UpdateRecentDBFsMenuItem;
    procedure DisplayMemoAsObjects(BrowseHow: TBrowseHow);
    procedure Table1AfterInsert(DataSet: TDataSet);
    procedure UpdateOpenMemoFields;
    procedure GotoRecordNumber;
    procedure Table1LocaleError(var Error: TLocaleError;
      var Solution: TLocaleSolution);
    procedure TestForNull;
  public
    { Public declarations }
    Table1: TDbf;
//  DataSource1: TDataSource;
    procedure OpenDBF(lfn: string);
    procedure AddHistoryItem(lfn: string);
    procedure SaveHistoryList;
    procedure OpenRecentDBF(Sender: TObject);
    Destructor Destroy; override;
  end;

var
  Form_Browser: TForm_Browser;
  
implementation

{$IfDef MsWindows}
{$R *.dfm}
{$EndIf}

uses
  MyUtils, IniFiles, GotoRecNo, uAbout, Variants;

const
  MAXHISTORY = 10;
  FILE_HISTORY = 'File History';
  FILE_PATHS   = 'File Paths';
  DEFAULT_PATH = 'Default Path';
  BROWSERINI   = 'Browser.ini';

{$IFDEF MSWINDOWS}
  HOMEDIR      = 'USERPROFILE';
{$EndIf}
{$IfDef Linux}
  HOMEDIR      = 'HOME';
{$EndIf}

procedure TForm_Browser.SaveHistoryList;
  var
    i: integer;
    IniFile: TIniFile;
begin { TForm_Browser.SaveHistoryList }
  IniFile := TIniFile.Create(fIniFileName);
  try
    with RecentDBFs do
      for i := 0 to Count-1 do
        IniFile.WriteString(FILE_HISTORY, 'File'+IntToStr(i), RecentDBFs[i]);
    IniFile.WriteString(FILE_PATHS, DEFAULT_PATH, fDefaultPath);
  finally
    IniFile.Free;
  end;
end;  { TForm_Browser.SaveHistoryList }


procedure TForm_Browser.Table1AfterScroll(DataSet: TDataSet);
begin
  with DataSet as TDbf do
    if not ControlsDisabled then
      begin
        if PhysicalRecordCount > 0 then
          begin
            lblRecordNumber.Caption := Format('%0.n/%0.n', [RecNo * 1.0, PhysicalRecordCount*1.0]);
            if (IndexName <> '') then
              lblRecordNumber.Hint := Format('%s: %s', [IndexName, Indexes.GetIndexByName(IndexName).Expression])
            else
              lblRecordNumber.Hint := 'Record number order';
          end
        else
          lblRecordNumber.Caption := 'No records';
        btnRecNo.Caption  := 'Rec #';
        EnableNavigateMenu;
        UpdateOpenMemoFields;
        lblHiddenRecord.Visible := IsDeleted;
        TestForNull;
      end;
end;

procedure TForm_Browser.Table1AfterInsert(DataSet: TDataSet);
begin
  DBGrid1.SelectedField := DataSet.Fields[0];
end;


procedure TForm_Browser.CloseDBF;
  var
    i: integer;
begin
  with Table1 do
    if Active then
      begin
        if State in [dsEdit, dsInsert] then
          Post;
        Active := false;
        for i := 0 to BrowseMemoList.Count-1 do
          TForm(BrowseMemoList[i]).Free;
        BrowseMemoList.Clear;
        Label_DBFName.Caption := '';
        SaveHistoryList;
      end;
  Enable_Stuff;
end;

procedure TForm_Browser.OpenDBF(lfn: string);
  var
    ext: string[4];
begin
  with Table1 do
    begin
      CloseDBF;
      FilePathFull := ExtractFilePath(lfn);
      TableName    := ExtractFileName(lfn);
      Ext          := UpperCase(ExtractFileExt(lfn));
      IndexName    := '';
      try
        Active       := true;
        Label_DBFName.Caption := Format('%s (TableLevel=%d)', [lfn, TableLevel]);
        AddHistoryItem(lfn);
        ShowHiddenRecords1.Checked := ShowDeleted;
        fDefaultPath := ExtractFilePath(lfn);
      except
        on E: Exception do
        begin
          E.Message:= Format('Unable to open %s [%s]', [lfn, E.message]);
          raise;
        end;
      end;
    end;
  Enable_Stuff;
end;

procedure TForm_Browser.Enable_Stuff;
begin
  with Table1 do
    begin
      Open1.Enabled             := not Active;
      Close1.Enabled            := Active;
      RebuildIndexes1.Enabled   := Active;
      PackTable1.Enabled        := Active;
      if not Active then
        begin
//          Edit1.Caption := '';
          lblRecordNumber.Caption   := '';
          lblIsNullField.Visible    := false;
        end;
    end;
  EnableNavigateMenu;
end;

procedure TForm_Browser.Table1LocaleError(var Error: TLocaleError; var Solution: TLocaleSolution);
var
  msg: string;
begin
  case Error of
    leNone:               Msg := 'None';
    leUnknown:            Msg := 'Unknown';
    leTableIndexMismatch: Msg := 'Table index mismatch';
    leNotAvailable:       Msg := 'Not available';
  end;
  raise Exception.CreateFmt('Locale error when opening "%s" [%s]', [Table1.TableName, Msg]);
end;


procedure TForm_Browser.FormCreate(Sender: TObject);
  var
    IniFile: TIniFile;
    b    : boolean;
    lfn  : string;
begin { TForm_Browser.FormCreate }
{$IfDef Linux}
  fHomeDir       := GetEnvironmentVariable('HOME');
  fIniFileName   := fHomeDir + '/' + BROWSERINI;
{$EndIf}
{$IfDef MSWindows}
  fHomeDir       := GetEnvironmentVariable(HOMEDIR) + '\My Documents';
  fIniFileName   := fHomeDir + '\' + BROWSERINI;
{$EndIf}
  Label_DBFName.Caption := '';
  Table1 := TDbf.Create(self);
  with Table1 do
    begin
      AfterOpen   := Table1AfterOpen;
      AfterScroll := Table1AfterScroll;
      AfterInsert := Table1AfterInsert;
      OnLocaleError := Table1LocaleError;
    end;
  DataSource1.DataSet := Table1;
  DBGrid1.DataSource  := DataSource1;
  DBNavigator1.DataSource := DataSource1;

  RecentDBFs          := TStringList.Create;
  BrowseMemoList      := TList.Create;

  IniFile := TIniFile.Create(fIniFileName);
  try
    lfn := IniFile.ReadString(FILE_HISTORY, 'File'+IntToStr(RecentDBFs.Count), '');
    b   := lfn <> '';
    while b do
      begin
        RecentDBFs.Add(Lfn);
        if RecentDBFs.Count < MAXHISTORY then
          begin
            lfn := IniFile.ReadString(FILE_HISTORY, 'File'+IntToStr(RecentDBFs.Count), '');
            b   := lfn <> '';
          end
        else
          b := false;
      end;

    fDefaultPath := IniFile.ReadString(FILE_PATHS, DEFAULT_PATH, '');
  finally
    IniFile.Free;
  end;

  UpdateRecentDBFsMenuItem;

  if ParamStr(1) <> '' then { if passed a parameter, try to use it as lfn }
    OpenDBF(ParamStr(1));

  Enable_Stuff;
end;  { TForm_Browser.FormCreate }

procedure TForm_Browser.AddHistoryItem(lfn: string);
  var
    i: integer;
begin { TForm_Browser.AddHistoryItem }
  with RecentDBFs do
    begin
      i := IndexOf(lfn);
      if i >= 0 then { already in list }
        begin
          if i > 0 then  { not already at top }
            begin
              Delete(i);
              Insert(0, lfn);        { move to the top }
            end;
        end else
      if Count = MAXHISTORY then { history list is full }
        begin
          Delete(MAXHISTORY-1);  { delete the oldest }
          Insert(0, lfn);        { add newset at the top }
        end
      else
        Insert(0, lfn);          { add at the top }
    end;
  UpdateRecentDBFsMenuItem;
end;  { TForm_Browser.AddHistoryItem }

procedure TForm_Browser.UpdateRecentDBFsMenuItem;
  var
    i: integer;
    aMenuItem: TMenuItem;
begin
  with RecentDBFs1 do
    begin
      { empty previous 'Recent DBFs' sub-menu }
      for i := Count-1 downto 0 do
        Delete(i);

      for i := 0 to RecentDBFs.Count-1 do
        begin
          aMenuItem := TMenuItem.Create(self);
          with aMenuItem do
            begin
              Caption := RecentDBFs[i];
              OnClick := OpenRecentDBF;
              AutoHotkeys := maManual;
            end;
          Add(aMenuItem);
        end;
    end;
end;



procedure TForm_Browser.DBGrid1DblClick(Sender: TObject);
  var
    aBrowseMemo: TForm;
begin
  aBrowseMemo := TfrmBrowseMemo.Create(self, DataSource1, DBGrid1.SelectedField, bhAsText);
  BrowseMemoList.Add(aBrowseMemo);
  aBrowseMemo.Show;
end;

procedure TForm_Browser.Table1AfterOpen(DataSet: TDataSet);
begin
  Table1AfterScroll(DataSet);
  UpdateTagNames;
end;

procedure TForm_Browser.UpdateTagNames;
  var
    aMenuItem: TMenuItem;
    i: integer;
    Items: TStringList;
begin
  with Table1 do
    begin
      Items := TStringList.Create;
      try
        Items.Clear;
        GetIndexNames(Items);
        Items.Add('(recno order)');

        { empty old 'Order' sub-menu }

        with Order1 do
          for i := Count-1 downto 0 do
            Delete(i);

        { Add items to 'Order1' sub-menu }
        for i := Items.Count-1 downto 0 do
          begin
            aMenuItem := TMenuItem.Create(self);
            aMenuItem.Caption   := Items[i];
            aMenuItem.OnClick   := OrderClick;
            aMenuItem.RadioItem := true;
            if i = Items.Count - 1 then
              aMenuItem.Checked := true;  // check the (recno) item
            Order1.Add(aMenuItem);
          end;
      finally
        Items.Free;
      end;
    end;
end;


procedure TForm_Browser.btnRebuildIndexesClick(Sender: TObject);
begin
  RebuildIndexes;
end;


procedure TForm_Browser.Open1Click(Sender: TObject);
begin
  with OpenDialog1 do
    begin
      InitialDir := fDefaultPath;
      if Execute then
        OpenDBF(FileName);
    end;
end;

procedure TForm_Browser.Exit1Click(Sender: TObject);
begin
  Close;
end;

procedure TForm_Browser.Navigate1Click(Sender: TObject);
begin
  EnableNavigateMenu;
end;

procedure TForm_Browser.EnableNavigateMenu;
begin
  with Table1 do
    begin
      Open1.Enabled            := not Active;
      Close1.Enabled           := Active;
      Navigate1.Enabled        := Active;
      FindRecord1.Enabled      := not EOF;
      AddRecord1.Enabled       := Active;
      TopRecord1.Enabled       := not BOF;
      PreviousRecord1.Enabled  := not BOF;
      NextRepord1.Enabled      := not EOF;
      BottomRecord1.Enabled    := not EOF;
      Order1.Enabled           := Active;
      btnRecNo.Enabled         := Active;
      FindKey1.Enabled         := Active and (IndexName <> '');
    end;
end;


procedure TForm_Browser.Close1Click(Sender: TObject);
begin
  CloseDBF;
end;

procedure TForm_Browser.AddRecord1Click(Sender: TObject);
begin
  Table1.Append;
end;

procedure TForm_Browser.TopRecord1Click(Sender: TObject);
begin
  Table1.First;
end;

procedure TForm_Browser.PreviousRecord1Click(Sender: TObject);
begin
  Table1.Prior;
end;

procedure TForm_Browser.NextRepord1Click(Sender: TObject);
begin
  Table1.Next;
end;

procedure TForm_Browser.BottomRecord1Click(Sender: TObject);
begin
  Table1.Last;
end;

procedure TForm_Browser.HideRecord1Click(Sender: TObject);
begin
  Table1.Delete;
end;

procedure TForm_Browser.RebuildIndexes1Click(Sender: TObject);
begin
  RebuildIndexes;
end;

procedure TForm_Browser.OrderClick(Sender: TObject);
  var
    idx: integer;
    aMenuItem: TMenuItem;
begin
  with Table1 do
    begin
      aMenuItem := TMenuItem(Sender);
      idx := Order1.IndexOf(aMenuItem);
      if idx > 0 then { index selected }
        begin
          IndexName := aMenuItem.Caption;
          aMenuItem.Checked := true;
        end
      else
        begin
          IndexName := '';   // recno order selected
          aMenuItem.Checked := true;
        end;
    end;
  Table1AfterScroll(Table1);
end;

procedure TForm_Browser.OpenRecentDBF(Sender: TObject);
begin
  with Sender as TMenuItem do
    OpenDBF(Caption);
end;

procedure TForm_Browser.FindDialog1Find(Sender: TObject);
  label
    FOUND_IT;
  var
    i: integer;
    Saved_Recno: integer;
    FoundIt: boolean;
    MatchString: string;
    FldNr: integer;
    temp2: string;
begin { TForm_Browser.FindDialog1Find }
  with FindDialog1 do
    begin
      MatchString := UpperCase(FindText);
      with Table1 do
        begin
          DisableControls;
          Saved_Recno := Recno;
          FoundIt     := false;
          FldNr       := -1;   // just to keep compiler happy
          Next;                // start searching at next record
          while not EOF do
            begin
              for i := 0 to Fields.Count-1 do
                with Fields[i] do
                  begin
                    Temp2 := UpperCase(AsString);
                    FoundIt := Pos(MatchString, Temp2) > 0;
                    if FoundIt then
                      begin
                        FldNr := i;
                        goto FOUND_IT;
                      end;
                  end;
              Next;
            end;
FOUND_IT:
          EnableControls;
          if FoundIt then
            begin
              DBGrid1.SelectedField := Fields[FldNr];
//            FindDialog1.CloseDialog;
            end
          else
            begin
              Recno := Saved_Recno;
              raise Exception.CreateFmt('Search string "%s" could not be found', [FindText]);
            end;
          Table1AfterScroll(Table1);  // do it with Controls Enabled
        end;
  end;
end;  { TForm_Browser.FindDialog1Find }

procedure TForm_Browser.FindRecord1Click(Sender: TObject);
begin
  FindDialog1.Execute;
end;

procedure TForm_Browser.FormClose(Sender: TObject;
  var Action: TCloseAction);
begin
  SaveHistoryList;
end;

procedure TForm_Browser.PackTable1Click(Sender: TObject);
begin
  with Table1 do
    begin
      close;
      Exclusive := true;
      open;
      PackTable;
      close;
      Exclusive := false;
      Open;
    end;
end;

procedure TForm_Browser.ReBuildIndexes;
begin
  with Table1 do
    begin
      close;
      Exclusive := true;
      open;
      RegenerateIndexes;
      close;
      Exclusive := false;
      Open;
    end;
end;

procedure TForm_Browser.DisplayMemoasText1Click(Sender: TObject);
  var
    aBrowseMemo: TForm;
begin
  aBrowseMemo := TfrmBrowseMemo.Create(self, DataSource1, DBGrid1.SelectedField, bhAsText);
  BrowseMemoList.Add(aBrowseMemo);
  aBrowseMemo.Show;
end;

procedure TForm_Browser.DisplayMemoAsObjects(BrowseHow: TBrowseHow);
  var
    aBrowseMemo: TForm;
begin
  aBrowseMemo := TfrmBrowseMemo.Create(self, DataSource1, DBGrid1.SelectedField, BrowseHow);
  BrowseMemoList.Add(aBrowseMemo);
  aBrowseMemo.Show;
end;

procedure TForm_Browser.DisplayMemoasObjects1Click(Sender: TObject);
begin
  DisplayMemoAsObjects(bhAsObject);
end;

procedure TForm_Browser.PopupMenu1Popup(Sender: TObject);
  var
    b1, b2: boolean;
begin
  b1 := DBGrid1.SelectedField is TBlobField;
  DisplayMemoasText1.Enabled := b1;
  if b1 then
    begin
      b2 := MemoContainsObject(DBGrid1.SelectedField);
      DisplayMemoasObjects1.Enabled := b2;
    end
  else
    DisplayMemoasObjects1.Enabled := false;
end;

procedure TForm_Browser.MovetoFirstColumn1Click(Sender: TObject);
begin
  DBGrid1.SelectedField := Table1.Fields[0];
end;

procedure TForm_Browser.UpdateOpenMemoFields;
  var
    i: integer;
begin
  for i := 0 to BrowseMemoList.Count-1 do
    with TfrmBrowseMemo(BrowseMemoList[i]) do
      begin
        if BrowseHow = bhAsObject then
          UpdateObjectMemo;
      end;
end;

destructor TForm_Browser.Destroy;
begin
  FreeAndNil(Table1);
  inherited;
end;

procedure TForm_Browser.GotoRecord1Click(Sender: TObject);
begin
  GotoRecordNumber;
end;

procedure TForm_Browser.ShowHiddenRecords1Click(Sender: TObject);
begin
  ShowHiddenRecords1.Checked := not ShowHiddenRecords1.Checked;
  Table1.ShowDeleted := ShowHiddenRecords1.Checked;
  Table1.Refresh;
end;

procedure TForm_Browser.GotoRecordNumber;
begin
  if frmGotoRecNo.ShowModal = mrOk then
    if Table1.Active then
      Table1.RecNo := frmGotoRecNo.OvcNumericField1.AsInteger;
end;

procedure TForm_Browser.btnRecNoClick(Sender: TObject);
begin
  GotoRecordNumber;
end;

procedure TForm_Browser.SpecifyFilterExpression1Click(Sender: TObject);
var
  GetInfo: TGetInfo;
begin
  frmGetString := TfrmGetString.Create(self, @GetInfo);
  with GetInfo do
    begin
      WindowCaption := 'Enter Filter Expression';
      value         := fFilterExpression;
    end;
  with frmGetString do
    begin
      Edit1.Text := fFilterExpression;
      if ShowModal = mrOk then
        begin
          fFilterExpression := Edit1.Text;
          Table1.Filter := fFilterExpression;
        end;
    end;
end;

procedure TForm_Browser.AboutTDbfBrowser1Click(Sender: TObject);
begin
  AboutBox.ShowModal;
end;

procedure TForm_Browser.FindKey1Click(Sender: TObject);
{$IfNDef Oldversion}
var
  GetInfo: TGetInfo;
  List: TStringList;
  Field: TField;
  FieldName: string;
  i: integer;
{$EndIf}
begin
{$IfNDef Oldversion}
  with GetInfo do
    begin
      WindowCaption := 'Enter key value';
      with Table1 do
        Label1Caption := Format('Enter key values for %s: %s', [IndexName, IndexDefs.GetIndexByName(IndexName).Expression]);
      Label2Caption := 'FieldName1=value1,FieldName2=Value2,...';
      Value := fLastSearch;
    end;
  frmGetString   := TFrmGetString.Create(self, @GetInfo);
  List           := TStringList.Create;
  List.Delimiter := ',';
  try
    with frmGetString do
      begin
        if ShowModal = mrOk then
          begin
            List.DelimitedText := GetInfo.value;
            fLastSearch        := GetInfo.value;
            Table1.SetKey;
            for i := 0 to List.Count-1 do
              begin
                FieldName := List.Names[i];
                Field     := Table1.FieldByName(FieldName);
                if Assigned(Field) then
                  Field.AsString := List.Values[FieldName]
                else
                  begin
                    AlertFmt('Field "%s" not found in table "%s"', [FieldName, Table1.TableName]);
                    Exit;
                  end;
              end;

            if not Table1.GotoKey then
              Alert('Unable to locate key');
          end;
      end;
  finally
    List.Free;
    FreeAndNil(frmGetString);
  end;
{$EndIf}
end;

procedure TForm_Browser.TestForNull;
begin
  lblIsNullField.Visible := DBGrid1.SelectedField.IsNull;
end;


procedure TForm_Browser.DBGrid1CellClick(Column: TColumn);
begin
  TestForNull;
end;

procedure TForm_Browser.DBGrid1ColEnter(Sender: TObject);
begin
  TestForNull;
end;

initialization
end.
