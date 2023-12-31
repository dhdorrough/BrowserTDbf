unit dbf_parser;

// BCC Software Modifications
// 11/02/2011 pb  CR 19713- Comparison operators should be case sensitive for an index
// 11/01/2011 pb  CR 19713- Comparison operators should use collation
// 04/29/2011 pb  CR 18895- Take into account language driver when converting case
// 04/28/2011 pb  CR 18884- Unary plus (+) operator may result in an expression index equivalent to a single field index
// 04/26/2011 pb  CR 18957- Use EParserException for parser error
// 04/15/2011 pb  CR 18893- RecNo() function
// 04/11/2011 pb  CR 18908- etString + etFloat = etFloat + etString = etString
// 04/11/2011 pb  CR 18908- Null value in an expression
// 04/06/2011 pb  CR 18901- Level 7 index key of type @ (Date/Time), O (Double), I (Integer), + (AutoIncrement)
// 04/06/2011 pb  CR 18562- Null value in index key of type D
// 04/04/2011 pb  CR 18890- Check buffer size when building index key
// 04/04/2011 pb  CR 18840- Null value in level 7 C field is NUL characters, not spaces

interface

{$I dbf_common.inc}

uses
  SysUtils,
  Classes,
{$ifdef KYLIX}
  Libc,
{$endif}
{$ifndef WINDOWS}
  dbf_wtil,
{$endif}
  db,
  dbf_prscore,
  dbf_common,
  dbf_fields,
  dbf_prsdef,
  dbf_prssupp;

type

  TDbfParser = class(TCustomExpressionParser)
  private
    FDbfFile: Pointer;
    FFieldVarList: TStringList;
    FIsExpression: Boolean;       // expression or simple field?
    FFieldType: TExpressionType;
    FCaseInsensitive: Boolean;
    FRawStringFields: Boolean;
    FPartialMatch: boolean;
    FRecNoVariable: TVariable; // 04/15/2011 pb  CR 18893

    function GetResultBufferSize: Integer; // 04/04/2011 pb  CR 18890
    function GetDbfFieldDef: TDbfFieldDef; // 04/06/2011 pb  CR 18901
    procedure SubstituteVariables(var ExprRec: PExpressionRec); // 04/15/2011 pb  CR 18893
  protected
    FCurrentExpression: string;

    procedure FillExpressList; override;
    procedure HandleUnknownVariable(VarName: string); override;
    function  GetVariableInfo(VarName: string): TDbfFieldDef;
    function  CurrentExpression: string; override;
    procedure ValidateExpression(AExpression: string); virtual;
    function  GetResultType: TExpressionType; override;
    function  GetResultLen: Integer;

    procedure SetCaseInsensitive(NewInsensitive: Boolean);
    procedure SetRawStringFields(NewRawFields: Boolean);
    procedure SetPartialMatch(NewPartialMatch: boolean);
    procedure OptimizeExpr(var ExprRec: PExpressionRec); override; // 04/15/2011 pb  CR 18893
  public
//  constructor Create(ADbfFile: Pointer);
    constructor Create(ADbfFile: Pointer); virtual; // 11/02/2011 pb  CR 19713
    destructor Destroy; override;

    procedure ClearExpressions; override;

    procedure ParseExpression(AExpression: string); virtual;
//  function ExtractFromBuffer(Buffer: PChar): PChar; virtual;
    function ExtractFromBuffer(Buffer: PChar; RecNo: Integer): PChar; virtual; // 04/15/2011 pb  CR 18893
//  function ExtractFromBuffer(Buffer: PChar; var IsNull: Boolean): PChar; overload; virtual; // 04/11/2011 pb  CR 18908- Null value in an expression
    function ExtractFromBuffer2(Buffer: PChar; RecNo: Integer; var IsNull: Boolean): PChar; virtual; // 04/11/2011 pb  CR 18908- Null value in an expression // 04/15/2011 pb  CR 18893

    property DbfFile: Pointer read FDbfFile write FDbfFile;
    property Expression: string read FCurrentExpression;
    property ResultLen: Integer read GetResultLen;
    property ResultBufferSize: Integer read GetResultBufferSize;
    property DbfFieldDef: TDbfFieldDef read GetDbfFieldDef; // 04/06/2011 pb  CR 18901

    property CaseInsensitive: Boolean read FCaseInsensitive write SetCaseInsensitive;
    property RawStringFields: Boolean read FRawStringFields write SetRawStringFields;
    property PartialMatch: boolean read FPartialMatch write SetPartialMatch;
  end;

implementation

uses
  dbf,
  Dbf_Collate,
  dbf_dbffile,
  dbf_str,
  dbf_lang
{$ifdef WINDOWS}
  ,Windows
{$endif}
  ;

type
// TFieldVar aids in retrieving field values from records
// in their proper type

  TFieldVar = class(TObject)
  private
    FFieldDef: TDbfFieldDef;
    FDbfFile: TDbfFile;
    FFieldName: string;
    FExprWord: TExprWord;
    FIsNull: Boolean; // 04/11/2011 pb  CR 18908
    FIsNullPtr: PBoolean; // 04/11/2011 pb  CR 18908
  protected
    function GetFieldVal: Pointer; virtual; abstract;
    function GetFieldType: TExpressionType; virtual; abstract;
    procedure SetExprWord(NewExprWord: TExprWord); virtual;

    property ExprWord: TExprWord read FExprWord write SetExprWord;
  public
    constructor Create(UseFieldDef: TDbfFieldDef; ADbfFile: TDbfFile);

    procedure Refresh(Buffer: PChar); virtual; abstract;

    property FieldVal: Pointer read GetFieldVal;
    property FieldDef: TDbfFieldDef read FFieldDef;
    property FieldType: TExpressionType read GetFieldType;
    property DbfFile: TDbfFile read FDbfFile;
    property FieldName: string read FFieldName;
    property IsNullPtr: PBoolean read FIsNullPtr; // 04/11/2011 pb  CR 18908
  end;

  TStringFieldVar = class(TFieldVar)
  protected
    FFieldVal: PChar;
    FRawStringField: boolean;

    function GetFieldVal: Pointer; override;
    function GetFieldType: TExpressionType; override;
    procedure SetExprWord(NewExprWord: TExprWord); override;
    procedure SetRawStringField(NewRaw: boolean);
    procedure UpdateExprWord;
  public
    constructor Create(UseFieldDef: TDbfFieldDef; ADbfFile: TDbfFile);
    destructor Destroy; override;

    procedure Refresh(Buffer: PChar); override;

    property RawStringField: boolean read FRawStringField write SetRawStringField;
  end;

  TFloatFieldVar = class(TFieldVar)
  private
    FFieldVal: Double;
  protected
    function GetFieldVal: Pointer; override;
    function GetFieldType: TExpressionType; override;
  public
    procedure Refresh(Buffer: PChar); override;
  end;

  TIntegerFieldVar = class(TFieldVar)
  private
    FFieldVal: Integer;
  protected
    function GetFieldVal: Pointer; override;
    function GetFieldType: TExpressionType; override;
  public
    procedure Refresh(Buffer: PChar); override;
  end;

{$ifdef SUPPORT_INT64}
  TLargeIntFieldVar = class(TFieldVar)
  private
    FFieldVal: Int64;
  protected
    function GetFieldVal: Pointer; override;
    function GetFieldType: TExpressionType; override;
  public
    procedure Refresh(Buffer: PChar); override;
  end;
{$endif}

  TDateTimeFieldVar = class(TFieldVar)
  private
    FFieldVal: TDateTimeRec;
    function GetFieldType: TExpressionType; override;
  protected
    function GetFieldVal: Pointer; override;
  public
    procedure Refresh(Buffer: PChar); override;
  end;

  TBooleanFieldVar = class(TFieldVar)
  private
    FFieldVal: boolean;
    function GetFieldType: TExpressionType; override;
  protected
    function GetFieldVal: Pointer; override;
  public
    procedure Refresh(Buffer: PChar); override;
  end;

{ TFieldVar }

constructor TFieldVar.Create(UseFieldDef: TDbfFieldDef; ADbfFile: TDbfFile);
begin
  inherited Create;

  // store field
  FFieldDef := UseFieldDef;
  FDbfFile := ADbfFile;
  FFieldName := UseFieldDef.FieldName;
  FIsNullPtr := @FIsNull; // 04/11/2011 pb  CR 18908
end;

procedure TFieldVar.SetExprWord(NewExprWord: TExprWord);
begin
  FExprWord := NewExprWord;
end;

{ TStringFieldVar }

constructor TStringFieldVar.Create(UseFieldDef: TDbfFieldDef; ADbfFile: TDbfFile);
begin
  inherited;
  FRawStringField := true;
end;

destructor TStringFieldVar.Destroy;
begin
  if not FRawStringField then
    FreeMem(FFieldVal);

  inherited;
end;

function TStringFieldVar.GetFieldVal: Pointer;
begin
  Result := @FFieldVal;
end;

function TStringFieldVar.GetFieldType: TExpressionType;
begin
  Result := etString;
end;

procedure TStringFieldVar.Refresh(Buffer: PChar);
var
  Len: Integer;
  Src: PChar;
begin
  Src := Buffer+FieldDef.Offset;
  if not FRawStringField then
  begin
    // copy field data
    Len := FieldDef.Size;
//  while (Len >= 1) and (Src[Len-1] = ' ') do Dec(Len);
    while (Len >= 1) and ((Src[Len-1] = ' ') or (Src[Len-1] = #0)) do Dec(Len); // 04/04/2011 pb  CR 18840
    // translate to ANSI
    Len := TranslateString(DbfFile.UseCodePage, GetACP, Src, FFieldVal, Len);
    FFieldVal[Len] := #0;
  end else
    FFieldVal := Src;
  FIsNull := not FDbfFile.GetFieldDataFromDef(FieldDef, FieldDef.FieldType, Buffer, nil, false); // 04/11/2011 pb  CR 18908
end;

procedure TStringFieldVar.SetExprWord(NewExprWord: TExprWord);
begin
  inherited;
  UpdateExprWord;
end;

procedure TStringFieldVar.UpdateExprWord;
begin
  if FRawStringField then
    FExprWord.FixedLen := FieldDef.Size
  else
    FExprWord.FixedLen := -1;
end;

procedure TStringFieldVar.SetRawStringField(NewRaw: boolean);
begin
  if NewRaw = FRawStringField then exit;
  FRawStringField := NewRaw;
  if NewRaw then
    FreeMem(FFieldVal)
  else
    GetMem(FFieldVal, FieldDef.Size*3+1);
  UpdateExprWord;
end;

//--TFloatFieldVar-----------------------------------------------------------
function TFloatFieldVar.GetFieldVal: Pointer;
begin
  Result := @FFieldVal;
end;

function TFloatFieldVar.GetFieldType: TExpressionType;
begin
  Result := etFloat;
end;

procedure TFloatFieldVar.Refresh(Buffer: PChar);
begin
  // database width is default 64-bit double
//if not FDbfFile.GetFieldDataFromDef(FieldDef, FieldDef.FieldType, Buffer, @FFieldVal, false) then
  FIsNull := not FDbfFile.GetFieldDataFromDef(FieldDef, FieldDef.FieldType, Buffer, @FFieldVal, false); // 04/11/2011 pb  CR 18908
  if FIsNull then // 04/11/2011 pb  CR 18908
    FFieldVal := 0.0;
end;

//--TIntegerFieldVar----------------------------------------------------------
function TIntegerFieldVar.GetFieldVal: Pointer;
begin
  Result := @FFieldVal;
end;

function TIntegerFieldVar.GetFieldType: TExpressionType;
begin
  Result := etInteger;
end;

procedure TIntegerFieldVar.Refresh(Buffer: PChar);
begin
//  FFieldVal := 0;
//  FDbfFile.GetFieldDataFromDef(FieldDef, FieldDef.FieldType, Buffer, @FFieldVal, false);
  FIsNull := not FDbfFile.GetFieldDataFromDef(FieldDef, FieldDef.FieldType, Buffer, @FFieldVal, false); // 04/11/2011 pb  CR 18908
  if FIsNull then
    FFieldVal := 0;
end;

{$ifdef SUPPORT_INT64}

//--TLargeIntFieldVar----------------------------------------------------------
function TLargeIntFieldVar.GetFieldVal: Pointer;
begin
  Result := @FFieldVal;
end;

function TLargeIntFieldVar.GetFieldType: TExpressionType;
begin
  Result := etLargeInt;
end;

procedure TLargeIntFieldVar.Refresh(Buffer: PChar);
begin
//  if not FDbfFile.GetFieldDataFromDef(FieldDef, FieldDef.FieldType, Buffer, @FFieldVal, false) then
  FIsNull := not FDbfFile.GetFieldDataFromDef(FieldDef, FieldDef.FieldType, Buffer, @FFieldVal, false); // 04/11/2011 pb  CR 18908
  if FIsNull then // 04/11/2011 pb  CR 18908
    FFieldVal := 0;
end;

{$endif}

//--TDateTimeFieldVar---------------------------------------------------------
function TDateTimeFieldVar.GetFieldVal: Pointer;
begin
  Result := @FFieldVal;
end;

function TDateTimeFieldVar.GetFieldType: TExpressionType;
begin
  Result := etDateTime;
end;

procedure TDateTimeFieldVar.Refresh(Buffer: PChar);
begin
//if not FDbfFile.GetFieldDataFromDef(FieldDef, ftDateTime, Buffer, @FFieldVal, false) then
  FIsNull:= not FDbfFile.GetFieldDataFromDef(FieldDef, ftDateTime, Buffer, @FFieldVal, false); // 04/11/2011 pb  CR 18908
  if FIsNull then // 04/11/2011 pb  CR 18908
    FFieldVal.DateTime := 0.0;
end;

//--TBooleanFieldVar---------------------------------------------------------
function TBooleanFieldVar.GetFieldVal: Pointer;
begin
  Result := @FFieldVal;
end;

function TBooleanFieldVar.GetFieldType: TExpressionType;
begin
  Result := etBoolean;
end;

procedure TBooleanFieldVar.Refresh(Buffer: PChar);
var
  lFieldVal: word;
begin
  FIsNull := not FDbfFile.GetFieldDataFromDef(FieldDef, ftBoolean, Buffer, @lFieldVal, false); // 04/11/2011 pb  CR 18908
//if FDbfFile.GetFieldDataFromDef(FieldDef, ftBoolean, Buffer, @lFieldVal, false) then
//  FFieldVal := lFieldVal <> 0
//else
//  FFieldVal := false;
  if FIsNull then // 04/11/2011 pb  CR 18908
    FFieldVal := false
  else
    FFieldVal := lFieldVal <> 0;
end;

{ TRecNoVariable }

// 04/15/2011 pb  CR 18893- RecNo() function

type
  TRecNoVariable = class(TIntegerVariable)
  private
    FRecNo: Integer;
  public
    constructor Create; reintroduce;
    procedure Refresh(RecNo: Integer);
  end;

constructor TRecNoVariable.Create;
begin
  inherited Create(EmptyStr, @FRecNo, nil, nil);
end;

procedure TRecNoVariable.Refresh(RecNo: Integer);
begin
  FRecNo := RecNo;
end;

//--TDbfParser---------------------------------------------------------------

constructor TDbfParser.Create(ADbfFile: Pointer);
var
  LangId: Byte; // 11/01/2011 pb  CR 19713
begin
  FDbfFile := ADbfFile;
  FFieldVarList := TStringList.Create;
  FCaseInsensitive := true;
  FRawStringFields := true;
  inherited Create;
  if Assigned(FDbfFile) then
  begin
    LangId := TDbfFile(FDbfFile).FileLangId; // 11/01/2011 pb  CR 19713
//  FExpressionContext.LocaleID := LangId_To_Locale[TDbfFile(FDbfFile).FileLangId]; // 04/29/2011 pb  CR 18895
    FExpressionContext.LocaleID := LangId_To_Locale[LangId]; // 11/01/2011 pb  CR 19713
    if LangId <> 0 then // 11/01/2011 pb  CR 19713
      FExpressionContext.Collation := GetCollationTable(LangId); // 11/01/2011 pb  CR 19713
  end;
end;

destructor TDbfParser.Destroy;
begin
  ClearExpressions;
  inherited;
  FreeAndNil(FFieldVarList);
  FreeAndNil(FRecNoVariable); // 04/15/2011 pb  CR 18893
end;

function TDbfParser.GetResultType: TExpressionType;
begin
  // if not a real expression, return type ourself
  if FIsExpression then
    Result := inherited GetResultType
  else
    Result := FFieldType;
end;

function TDbfParser.GetResultLen: Integer;
begin
  // set result len for fixed length expressions / fields
  case ResultType of
    etBoolean:  Result := 1;
    etInteger:  Result := 4;
    etFloat:    Result := 8;
    etDateTime: Result := 8;
    etString:
    begin
      if not FIsExpression and (TStringFieldVar(FFieldVarList.Objects[0]).RawStringField) then
        Result := TStringFieldVar(FFieldVarList.Objects[0]).FieldDef.Size
      else
        Result := -1;
    end;
  else
    Result := -1;
  end;
end;

procedure TDbfParser.SetCaseInsensitive(NewInsensitive: Boolean);
begin
  if FCaseInsensitive <> NewInsensitive then
  begin
    // clear and regenerate functions
    FCaseInsensitive := NewInsensitive;
    FillExpressList;
  end;
end;

procedure TDbfParser.SetPartialMatch(NewPartialMatch: boolean);
begin
  if FPartialMatch <> NewPartialMatch then
  begin
    // refill function list
    FPartialMatch := NewPartialMatch;
    FillExpressList;
  end;
end;

procedure TDbfParser.OptimizeExpr(var ExprRec: PExpressionRec); // 04/15/2011 pb  CR 18893
begin
  inherited OptimizeExpr(ExprRec);
  SubstituteVariables(ExprRec);
end;

procedure TDbfParser.SetRawStringFields(NewRawFields: Boolean);
var
  I: integer;
begin
  if FRawStringFields <> NewRawFields then
  begin
    // clear and regenerate functions, custom fields will be deleted too
    FRawStringFields := NewRawFields;
    for I := 0 to FFieldVarList.Count - 1 do
      if FFieldVarList.Objects[I] is TStringFieldVar then
        TStringFieldVar(FFieldVarList.Objects[I]).RawStringField := NewRawFields;
  end;
end;

procedure TDbfParser.FillExpressList;
var
  lExpression: string;
begin
  lExpression := FCurrentExpression;
  ClearExpressions;
  FWordsList.FreeAll;
  FWordsList.AddList(DbfWordsGeneralList, 0, DbfWordsGeneralList.Count - 1);
  if FCaseInsensitive then
  begin
    FWordsList.AddList(DbfWordsInsensGeneralList, 0, DbfWordsInsensGeneralList.Count - 1);
    if FPartialMatch then
    begin
      FWordsList.AddList(DbfWordsInsensPartialList, 0, DbfWordsInsensPartialList.Count - 1);
    end else begin
      FWordsList.AddList(DbfWordsInsensNoPartialList, 0, DbfWordsInsensNoPartialList.Count - 1);
    end;
  end else begin
    FWordsList.AddList(DbfWordsSensGeneralList, 0, DbfWordsSensGeneralList.Count - 1);
    if FPartialMatch then
    begin
      FWordsList.AddList(DbfWordsSensPartialList, 0, DbfWordsSensPartialList.Count - 1);
    end else begin
      FWordsList.AddList(DbfWordsSensNoPartialList, 0, DbfWordsSensNoPartialList.Count - 1);
    end;
  end;
  if Length(lExpression) > 0 then
    ParseExpression(lExpression);
end;

function TDbfParser.GetVariableInfo(VarName: string): TDbfFieldDef;
begin
  Result := TDbfFile(FDbfFile).GetFieldInfo(VarName);
end;

procedure TDbfParser.HandleUnknownVariable(VarName: string);
var
  FieldInfo: TDbfFieldDef;
  TempFieldVar: TFieldVar;
  VariableFieldInfo: TVariableFieldInfo; // 04/11/2011 pb  CR 18908
begin
  // is this variable a fieldname?
  FieldInfo := GetVariableInfo(VarName);
  if FieldInfo = nil then
//  raise EDbfError.CreateFmt(STRING_INDEX_BASED_ON_UNKNOWN_FIELD, [VarName]);
    raise EParserException.CreateFmt(STRING_INDEX_BASED_ON_UNKNOWN_FIELD, [VarName]); // 04/26/2011 pb  CR 18957

  // define field in parser
  FillChar(VariableFieldInfo, SizeOf(VariableFieldInfo), 0); // 04/11/2011 pb  CR 18908
  VariableFieldInfo.DbfFieldDef := FieldInfo; // 04/28/2011 pb  CR 18884
  VariableFieldInfo.NativeFieldType := FieldInfo.NativeFieldType; // 04/11/2011 pb  CR 18908
  VariableFieldInfo.Size := FieldInfo.Size; // 04/11/2011 pb  CR 18908
  VariableFieldInfo.Precision := FieldInfo.Precision; // 04/11/2011 pb  CR 18908
  case FieldInfo.FieldType of
    ftString:
      begin
        TempFieldVar := TStringFieldVar.Create(FieldInfo, TDbfFile(FDbfFile));
//      TempFieldVar.ExprWord := DefineStringVariable(VarName, TempFieldVar.FieldVal);
        TempFieldVar.ExprWord := DefineStringVariable(VarName, TempFieldVar.FieldVal, TempFieldVar.IsNullPtr, @VariableFieldInfo); // 04/11/2011 pb  CR 18908
        TStringFieldVar(TempFieldVar).RawStringField := FRawStringFields;
      end;
    ftBoolean:
      begin
        TempFieldVar := TBooleanFieldVar.Create(FieldInfo, TDbfFile(FDbfFile));
//      TempFieldVar.ExprWord := DefineBooleanVariable(VarName, TempFieldVar.FieldVal);
        TempFieldVar.ExprWord := DefineBooleanVariable(VarName, TempFieldVar.FieldVal, TempFieldVar.IsNullPtr, @VariableFieldInfo); // 04/11/2011 pb  CR 18908
      end;
    ftFloat:
      begin
        TempFieldVar := TFloatFieldVar.Create(FieldInfo, TDbfFile(FDbfFile));
//      TempFieldVar.ExprWord := DefineFloatVariable(VarName, TempFieldVar.FieldVal);
        TempFieldVar.ExprWord := DefineFloatVariable(VarName, TempFieldVar.FieldVal, TempFieldVar.IsNullPtr, @VariableFieldInfo); // 04/11/2011 pb  CR 18908
      end;
    ftAutoInc, ftInteger, ftSmallInt:
      begin
        TempFieldVar := TIntegerFieldVar.Create(FieldInfo, TDbfFile(FDbfFile));
//      TempFieldVar.ExprWord := DefineIntegerVariable(VarName, TempFieldVar.FieldVal);
        TempFieldVar.ExprWord := DefineIntegerVariable(VarName, TempFieldVar.FieldVal, TempFieldVar.IsNullPtr, @VariableFieldInfo); // 04/11/2011 pb  CR 18908
      end;
{$ifdef SUPPORT_INT64}
    ftLargeInt:
      begin
        TempFieldVar := TLargeIntFieldVar.Create(FieldInfo, TDbfFile(FDbfFile));
//      TempFieldVar.ExprWord := DefineLargeIntVariable(VarName, TempFieldVar.FieldVal);
        TempFieldVar.ExprWord := DefineLargeIntVariable(VarName, TempFieldVar.FieldVal, TempFieldVar.IsNullPtr, @VariableFieldInfo); // 04/11/2011 pb  CR 18908
      end;
{$endif}
    ftDate, ftDateTime:
      begin
        TempFieldVar := TDateTimeFieldVar.Create(FieldInfo, TDbfFile(FDbfFile));
//      TempFieldVar.ExprWord := DefineDateTimeVariable(VarName, TempFieldVar.FieldVal);
        TempFieldVar.ExprWord := DefineDateTimeVariable(VarName, TempFieldVar.FieldVal, TempFieldVar.IsNullPtr, @VariableFieldInfo); // 04/11/2011 pb  CR 18908
      end;
  else
//  raise EDbfError.CreateFmt(STRING_INDEX_BASED_ON_INVALID_FIELD, [VarName]);
    raise EParserException.CreateFmt(STRING_INDEX_BASED_ON_INVALID_FIELD, [VarName]); // 04/26/2011 pb  CR 18957
  end;

  // add to our own list
  FFieldVarList.AddObject(VarName, TempFieldVar);
end;

function TDbfParser.CurrentExpression: string;
begin
  Result := FCurrentExpression;
end;

procedure TDbfParser.ClearExpressions;
var
  I: Integer;
begin
  inherited;

  // test if already freed
  if FFieldVarList <> nil then
  begin
    // free field list
    for I := 0 to FFieldVarList.Count - 1 do
    begin
      // replacing with nil = undefining variable
      FWordsList.DoFree(TFieldVar(FFieldVarList.Objects[I]).FExprWord);
      TFieldVar(FFieldVarList.Objects[I]).Free;
    end;
    FFieldVarList.Clear;
  end;

  // clear expression
  FCurrentExpression := EmptyStr;
end;

procedure TDbfParser.ValidateExpression(AExpression: string);
begin
end;

procedure TDbfParser.ParseExpression(AExpression: string);
begin
  // clear any current expression
  ClearExpressions;

  // is this a simple field or complex expression?
  FIsExpression := GetVariableInfo(AExpression) = nil;
  if FIsExpression then
  begin
    // parse requested
    CompileExpression(AExpression);
  end else begin
    // simple field, create field variable for it
    HandleUnknownVariable(AExpression);
    FFieldType := TFieldVar(FFieldVarList.Objects[0]).FieldType;
  end;

  ValidateExpression(AExpression);

  // if no errors, assign current expression
  FCurrentExpression := AExpression;
end;

//function TDbfParser.ExtractFromBuffer(Buffer: PChar): PChar;
function TDbfParser.ExtractFromBuffer(Buffer: PChar; RecNo: Integer): PChar; // 04/15/2011 pb  CR 18893
var
  IsNull: Boolean; // 04/11/2011 pb  CR 18908
begin
//Result := ExtractFromBuffer(Buffer, IsNull); // 04/11/2011 pb  CR 18908
  Result := ExtractFromBuffer2(Buffer, RecNo, IsNull); // 04/11/2011 pb  CR 18908 // 04/15/2011 pb  CR 18893
end;

//function TDbfParser.ExtractFromBuffer(Buffer: PChar; var IsNull: Boolean): PChar;
function TDbfParser.ExtractFromBuffer2(Buffer: PChar; RecNo: Integer; var IsNull: Boolean): PChar; // 04/15/2011 pb  CR 18893
var
  I: Integer;
  FieldVar: TFieldVar; // 04/11/2011 pb  CR 18908
begin
  // prepare all field variables
  for I := 0 to FFieldVarList.Count - 1 do
    TFieldVar(FFieldVarList.Objects[I]).Refresh(Buffer);
  if Assigned(FRecNoVariable) then // 04/15/2011 pb  CR 18893
    TRecNoVariable(FRecNoVariable).Refresh(RecNo); // 04/15/2011 pb  CR 18893

  // complex expression?
  if FIsExpression then
  begin
    // execute expression
    EvaluateCurrent;
    Result := ExpResult;
    if Assigned(CurrentRec) then
      IsNull := LastRec.IsNullPtr^ // 04/11/2011 pb  CR 18908
    else
      IsNull := False;
  end else begin
    // simple field, get field result
    Result := TFieldVar(FFieldVarList.Objects[0]).FieldVal;
    // if string then dereference
    if FFieldType = etString then
      Result := PPChar(Result)^;
    FieldVar:= TFieldVar(FFieldVarList.Objects[0]);
    IsNull := FieldVar.IsNullPtr^; // 04/11/2011 pb  CR 18908
  end;
end;

function TDbfParser.GetResultBufferSize: Integer; // 04/04/2011 pb  CR 18890
begin
  if ResultLen >= 0 then
    Result := ResultLen
  else
    Result := ExpResultSize;
end;

function TDbfParser.GetDbfFieldDef: TDbfFieldDef; // 04/06/2011 pb  CR 18901
var
  FieldVar: TFieldVar;
  FieldInfo: PVariableFieldInfo;
begin
  if FIsExpression then
  begin
    Result := nil;
    if Assigned(LastRec) and (LastRec^.ExprWord is TVariable) then // 04/28/2011 pb  CR 18884
    begin
      FieldInfo := TVariable(LastRec^.ExprWord).FieldInfo; // 04/28/2011 pb  CR 18884
      if Assigned(FieldInfo) then
        Result := FieldInfo.DbfFieldDef; // 04/28/2011 pb  CR 18884
    end;
  end
  else
  begin
    FieldVar:= TFieldVar(FFieldVarList.Objects[0]);
    Result := FieldVar.FieldDef;
  end;
end;

procedure TDbfParser.SubstituteVariables(var ExprRec: PExpressionRec); // 04/15/2011 pb  CR 18893
var
  Index: Integer;
  NewExprRec: PExpressionRec;
  Variable: TVariable;
begin
  if @ExprRec.Oper = @FuncRecNo then
  begin
    NewExprRec := MakeRec;
    try
      if Assigned(FRecNoVariable) then
        Variable := FRecNoVariable
      else
        Variable := TRecNoVariable.Create;
      try
        NewExprRec.ExprWord := Variable;
        NewExprRec.Oper := NewExprRec.ExprWord.ExprFunc;
        NewExprRec.Args[0] := NewExprRec.ExprWord.AsPointer;
        CurrentRec := nil;
        DisposeList(ExprRec);
        ExprRec := NewExprRec;
      except
        if not Assigned(FRecNoVariable) then
          FreeAndNil(Variable);
        raise;
      end;
      FRecNoVariable:= Variable;
    except
      DisposeList(NewExprRec);
      raise;
    end;
  end
  else
  begin
    for Index := 0 to Pred(ExprRec^.ExprWord.MaxFunctionArg) do
      if ExprRec^.ArgList[Index] <> nil then
        SubstituteVariables(ExprRec^.ArgList[Index]);
  end;
end;

end.

