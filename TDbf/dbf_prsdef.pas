unit dbf_prsdef;

// Modifications by BCC Software
// 11/01/2011 pb  CR 19713- Comparison operators should use collation
// 05/05/2011 pb  CR 18984- Number to string conversion is inconsistent and does not properly take into account the width
// 04/29/2011 pb  CR 18895- Take into account language driver when converting case
// 04/28/2011 pb  CR 18884- Unary plus (+) operator
// 04/27/2011 pb  CR 18890- Reinitialize dynamic buffer
// 04/27/2011 pb  CR 18959- Minus (-) operator concatenates a string without trailing spaces
// 04/27/2011 pb  CR 18959- FExpressionContext holds context-specific information the evaluation functions need to know
// 04/15/2011 pb  CR 18536- A function varies unless otherwise specified
// 04/11/2011 pb  CR 18908- Null value in an expression
// 04/04/2011 pb  CR 18897- Null value in level 7 character field should be represented as spaces in an index key
// 04/04/2011 pb  CR 18890- Initialize dynamic buffer
// 03/04/2011 pb  CR 18611- Thread-safe reference counting of TExprWord objects

interface

{$I dbf_common.inc}

uses
  SysUtils,
  Classes,
  Db,
  Windows,
  Dbf_Collate, dbf_prssupp;

const
  MaxArg = 6;
  ArgAllocSize = 32;

type
  TExpressionType = (etInteger, etString, etBoolean, etLargeInt, etFloat, etDateTime,
    etLeftBracket, etRightBracket, etComma, etUnknown);

  PPChar = ^PChar;
  PBoolean = ^Boolean;
  PInteger = ^Integer;
  PDateTime = ^TDateTime;
  EParserException = class(Exception);
  PExpressionRec = ^TExpressionRec;
  PDynamicType = ^TDynamicType;
  PDateTimeRec = ^TDateTimeRec;
{$ifdef SUPPORT_INT64}
  PLargeInt = ^Int64;
{$endif}

  TExprWord = class;

  TExprFunc = procedure(Expr: PExpressionRec);

//-----

  TDynamicType = class(TObject)
  private
    FMemory: PPChar;
    FMemoryPos: PPChar;
    FSize: PInteger;
  public
    constructor Create(DestMem, DestPos: PPChar; ASize: PInteger);

    procedure AssureSpace(ASize: Integer);
    procedure Resize(NewSize: Integer; Exact: Boolean);
    procedure Rewind;
    procedure Append(Source: PChar; Length: Integer);
    procedure AppendInteger(Source: Integer);

    property Memory: PPChar read FMemory;
    property MemoryPos: PPChar read FMemoryPos;
    property Size: PInteger read FSize;
  end;

  TExpressionContext = record // 04/27/2011 pb  CR 18959
    Validating: Boolean;
    LocaleID: LCID; // 04/29/2011 pb  CR 18895
    Collation: PCollationTable; // 11/01/2011 pb  CR 19713
  end;
  PExpressionContext = ^TExpressionContext;

  TExpressionRec = record
    //used both as linked tree and linked list for maximum evaluation efficiency
    Oper: TExprFunc;
    Next: PExpressionRec;
    Res: TDynamicType;
    ExprWord: TExprWord;
    AuxData: pointer;
    ResetDest: boolean;
    WantsFunction: boolean;
    Args: array[0..MaxArg-1] of PChar;
    ArgsPos: array[0..MaxArg-1] of PChar;
    ArgsSize: array[0..MaxArg-1] of Integer;
    ArgsType: array[0..MaxArg-1] of TExpressionType;
    ArgList: array[0..MaxArg-1] of PExpressionRec;
    IsNull: Boolean; // 04/11/2011 pb  CR 18908
    IsNullPtr: PBoolean; // 04/11/2011 pb  CR 18908
    ExpressionContext: PExpressionContext; // 04/27/2011 pb  CR 18959
  end;

  TExprCollection = class(TNoOwnerCollection)
  public
    procedure Check;
    procedure EraseExtraBrackets;
  end;

  TExprWordRec = record
    Name: PChar;
    ShortName: PChar;
    IsOperator: Boolean;
    IsVariable: Boolean;
    IsFunction: Boolean;
    NeedsCopy: Boolean;
    FixedLen: Boolean;
    CanVary: Boolean;
    ResultType: TExpressionType;
    MinArg: Integer;
    MaxArg: Integer;
    TypeSpec: PChar;
    Description: PChar;
    ExprFunc: TExprFunc;
  end;

  TExprWord = class(TObject)
  private
    FName: string;
    FExprFunc: TExprFunc;
    FIsNull: Boolean; // 04/11/2011 pb  CR 18908
    FIsNullPtr: PBoolean; // 04/11/2011 pb  CR 18908
  protected
//  FRefCount: Cardinal;
    FRefCount: Integer; // 03/04/2011 pb  CR 18611- InterlockedIncrement expects an Integer

    function GetIsOperator: Boolean; virtual;
    function GetIsVariable: Boolean;
    function GetNeedsCopy: Boolean;
    function GetFixedLen: Integer; virtual;
    function GetCanVary: Boolean; virtual;
    function GetResultType: TExpressionType; virtual;
    function GetMinFunctionArg: Integer; virtual;
    function GetMaxFunctionArg: Integer; virtual;
    function GetDescription: string; virtual;
    function GetTypeSpec: string; virtual;
    function GetShortName: string; virtual;
    procedure SetFixedLen(NewLen: integer); virtual;
  public
    constructor Create(AName: string; AExprFunc: TExprFunc);
    constructor Create2(AName: string; AExprFunc: TExprFunc; AIsNullPtr: PBoolean); // 04/11/2011 pb  CR 18908

    function LenAsPointer: PInteger; virtual;
    function AsPointer: PChar; virtual;
    function IsFunction: Boolean; virtual;

    property ExprFunc: TExprFunc read FExprFunc;
    property IsOperator: Boolean read GetIsOperator;
    property CanVary: Boolean read GetCanVary;
    property IsVariable: Boolean read GetIsVariable;
    property NeedsCopy: Boolean read GetNeedsCopy;
    property FixedLen: Integer read GetFixedLen write SetFixedLen;
    property ResultType: TExpressionType read GetResultType;
    property MinFunctionArg: Integer read GetMinFunctionArg;
    property MaxFunctionArg: Integer read GetMaxFunctionArg;
    property Name: string read FName;
    property ShortName: string read GetShortName;
    property Description: string read GetDescription;
    property TypeSpec: string read GetTypeSpec;
    property IsNullPtr: PBoolean read FIsNullPtr; // 04/11/2011 pb  CR 18908
  end;

  TExpressShortList = class(TSortedCollection)
  public
    function KeyOf(Item: Pointer): Pointer; override;
    function Compare(Key1, Key2: Pointer): Integer; override;
    procedure FreeItem(Item: Pointer); override;
  end;

  TExpressList = class(TSortedCollection)
  private
    FShortList: TExpressShortList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(Item: Pointer); override;
    function  KeyOf(Item: Pointer): Pointer; override;
    function  Compare(Key1, Key2: Pointer): Integer; override;
    function  Search(Key: Pointer; var Index: Integer): Boolean; override;
    procedure FreeItem(Item: Pointer); override;
  end;

  TConstant = class(TExprWord)
  private
    FResultType: TExpressionType;
  protected
    function GetResultType: TExpressionType; override;
  public
    constructor Create(AName: string; AVarType: TExpressionType; AExprFunc: TExprFunc);
  end;

  TFloatConstant = class(TConstant)
  private
    FValue: Double;
  public
    // not overloaded to support older Delphi versions
    constructor Create(AName: string; AValue: string);
    constructor CreateAsDouble(AName: string; AValue: Double);

    function AsPointer: PChar; override;

    property Value: Double read FValue write FValue;
  end;

  TUserConstant = class(TFloatConstant)
  private
    FDescription: string;
  protected
    function GetDescription: string; override;
  public
    constructor CreateAsDouble(AName, Descr: string; AValue: Double);
  end;

  TStringConstant = class(TConstant)
  private
    FValue: string;
  public
    constructor Create(AValue: string);

    function AsPointer: PChar; override;
  end;

  TIntegerConstant = class(TConstant)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);

    function AsPointer: PChar; override;
  end;

  TBooleanConstant = class(TConstant)
  private
    FValue: Boolean;
  public
    // not overloaded to support older Delphi versions
    constructor Create(AName: string; AValue: Boolean);

    function AsPointer: PChar; override;

    property Value: Boolean read FValue write FValue;
  end;

  TVariableFieldInfo = record // 04/11/2011 pb  CR 18908
    DbfFieldDef: Pointer; // 04/28/2011 pb  CR 18884
    NativeFieldType: Char;
    Size: Integer;
    Precision: Integer;
  end;
  PVariableFieldInfo = ^TVariableFieldInfo;

  TVariable = class(TExprWord)
  private
    FResultType: TExpressionType;
    FFieldInfo: TVariableFieldInfo; // 04/11/2011 pb  CR 18908
    FFieldInfoValid: Boolean; // 04/11/2011 pb  CR 18908
    function GetFieldInfo: PVariableFieldInfo; // 04/11/2011 pb  CR 18908
  protected
    function GetCanVary: Boolean; override;
    function GetResultType: TExpressionType; override;
  public
//  constructor Create(AName: string; AVarType: TExpressionType; AExprFunc: TExprFunc);
    constructor Create(AName: string; AVarType: TExpressionType; AExprFunc: TExprFunc; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908
    property FieldInfo: PVariableFieldInfo read GetFieldInfo; // 04/11/2011 pb  CR 18908
  end;

  TFloatVariable = class(TVariable)
  private
    FValue: PDouble;
    FIsNullPtr: PBoolean; // 04/11/2011 pb  CR 18908
  public
//  constructor Create(AName: string; AValue: PDouble);
    constructor Create(AName: string; AValue: PDouble; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908

    function AsPointer: PChar; override;
    property IsNullPtr: PBoolean read FIsNullPtr; // 04/11/2011 pb  CR 18908
  end;

  TStringVariable = class(TVariable)
  private
    FValue: PPChar;
    FFixedLen: Integer;
  protected
    function GetFixedLen: Integer; override;
    procedure SetFixedLen(NewLen: integer); override;
  public
//  constructor Create(AName: string; AValue: PPChar);
    constructor Create(AName: string; AValue: PPChar; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908

    function LenAsPointer: PInteger; override;
    function AsPointer: PChar; override;

    property FixedLen: Integer read FFixedLen;
  end;

  TDateTimeVariable = class(TVariable)
  private
    FValue: PDateTimeRec;
  public
//  constructor Create(AName: string; AValue: PDateTimeRec);
    constructor Create(AName: string; AValue: PDateTimeRec; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908

    function AsPointer: PChar; override;
  end;

  TIntegerVariable = class(TVariable)
  private
    FValue: PInteger;
  public
//  constructor Create(AName: string; AValue: PInteger);
    constructor Create(AName: string; AValue: PInteger; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908

    function AsPointer: PChar; override;
  end;

{$ifdef SUPPORT_INT64}

  TLargeIntVariable = class(TVariable)
  private
    FValue: PLargeInt;
  public
//  constructor Create(AName: string; AValue: PLargeInt);
    constructor Create(AName: string; AValue: PLargeInt; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908

    function AsPointer: PChar; override;
  end;

{$endif}

  TBooleanVariable = class(TVariable)
  private
    FValue: PBoolean;
  public
//  constructor Create(AName: string; AValue: PBoolean);
    constructor Create(AName: string; AValue: PBoolean; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908

    function AsPointer: PChar; override;
  end;

  TLeftBracket = class(TExprWord)
    function GetResultType: TExpressionType; override;
  end;

  TRightBracket = class(TExprWord)
  protected
    function GetResultType: TExpressionType; override;
  end;

  TComma = class(TExprWord)
  protected
    function GetResultType: TExpressionType; override;
  end;

  TFunction = class(TExprWord)
  private
    FIsOperator: Boolean;
    FOperPrec: Integer;
    FMinFunctionArg: Integer;
    FMaxFunctionArg: Integer;
    FDescription: string;
    FTypeSpec: string;
    FShortName: string;
    FResultType: TExpressionType;
  protected
    function GetCanVary: Boolean; override; // 04/15/2011 pb  CR 18536
    function GetDescription: string; override;
    function GetIsOperator: Boolean; override;
    function GetMinFunctionArg: Integer; override;
    function GetMaxFunctionArg: Integer; override;
    function GetResultType: TExpressionType; override;
    function GetTypeSpec: string; override;
    function GetShortName: string; override;

    procedure InternalCreate(AName, ATypeSpec: string; AMinFuncArg: Integer; AResultType: TExpressionType;
      AExprFunc: TExprFunc; AIsOperator: Boolean; AOperPrec: Integer);
  public
    constructor Create(AName, AShortName, ATypeSpec: string; AMinFuncArg: Integer; AResultType: TExpressionType; AExprFunc: TExprFunc; Descr: string);
    constructor CreateOper(AName, ATypeSpec: string; AResultType: TExpressionType; AExprFunc: TExprFunc; AOperPrec: Integer);

    function IsFunction: Boolean; override;

    property OperPrec: Integer read FOperPrec;
    property TypeSpec: string read FTypeSpec;
  end;

// 04/15/2011 pb  CR 18536- A function varies unless otherwise specified
(*
  TVaryingFunction = class(TFunction)
    // Functions that can vary for ex. random generators
    // should be TVaryingFunction to be sure that they are
    // always evaluated
  protected
    function GetCanVary: Boolean; override;
  end;
*)

const
  ListChar = ','; {the delimiter used with the 'in' operator: e.g.,
  ('a' in 'a,b') =True
  ('c' in 'a,b') =False}

function ExprCharToExprType(ExprChar: Char): TExpressionType;
function ExprStrLen(P: PChar; IncludeTrailingSpaces: Boolean): Integer; // 04/27/2011 pb  CR 18959
procedure ExprTrailingNulsToSpace(P: PChar; Len: Integer); // 04/04/2011 pb  CR 18897

implementation

function ExprCharToExprType(ExprChar: Char): TExpressionType;
begin
  case ExprChar of
    'B': Result := etBoolean;
    'I': Result := etInteger;
    'L': Result := etLargeInt;
    'F': Result := etFloat;
    'D': Result := etDateTime;
    'S': Result := etString;
  else
    Result := etUnknown;
  end;
end;

function ExprStrLen(P: PChar; IncludeTrailingSpaces: Boolean): Integer; // 04/27/2011 pb  CR 18959
begin
  Result := StrLen(P);
  if not IncludeTrailingSpaces then
{$BOOLEVAL OFF}
    while (Result > 0) and ((P + Pred(Result))^ = ' ') do
      Dec(Result);
{$BOOLEVAL ON}
end;

procedure ExprTrailingNulsToSpace(P: PChar; Len: Integer); // 04/04/2011 pb  CR 18897
var
  I: Integer;
begin
  if Len <> 0 then
  begin
    I := Len - 1;
    repeat
      if (P+I)^ = #0 then
      begin
        (P+I)^ := ' ';
        Dec(I);
      end
      else
        I:= -1;
    until I<0;
  end;
end;

procedure _FloatVariable(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^;
end;

procedure _BooleanVariable(Param: PExpressionRec);
begin
  with Param^ do
    PBoolean(Res.MemoryPos^)^ := PBoolean(Args[0])^;
end;

procedure _StringConstant(Param: PExpressionRec);
begin
  with Param^ do
    Res.Append(Args[0], StrLen(Args[0]));
end;

procedure _StringVariable(Param: PExpressionRec);
var
  length: integer;
  P: PChar; // 04/04/2011 pb  CR 18897
begin
  with Param^ do
  begin
    length := PInteger(Args[1])^;
    P := PPChar(Args[0])^; // 04/04/2011 pb  CR 18897
    if length = -1 then
//    length := StrLen(PPChar(Args[0])^);
      length := StrLen(P) // 04/04/2011 pb  CR 18897
    else
      ExprTrailingNulsToSpace(P, length); // 04/04/2011 pb  CR 18897
//  Res.Append(PPChar(Args[0])^, length);
    Res.Append(P, length); // 04/04/2011 pb  CR 18897
  end;
end;

procedure _DateTimeVariable(Param: PExpressionRec);
begin
  with Param^ do
    PDateTimeRec(Res.MemoryPos^)^ := PDateTimeRec(Args[0])^;
end;

procedure _IntegerVariable(Param: PExpressionRec);
begin
  with Param^ do
    PInteger(Res.MemoryPos^)^ := PInteger(Args[0])^;
end;

{
procedure _SmallIntVariable(Param: PExpressionRec);
begin
  with Param^ do
    PSmallInt(Res.MemoryPos^)^ := PSmallInt(Args[0])^;
end;
}

{$ifdef SUPPORT_INT64}

procedure _LargeIntVariable(Param: PExpressionRec);
begin
  with Param^ do
    PLargeInt(Res.MemoryPos^)^ := PLargeInt(Args[0])^;
end;

{$endif}

{ TExpressionWord }

constructor TExprWord.Create(AName: string; AExprFunc: TExprFunc);
begin
  Create2(AName, AExprFunc, nil);
end;

constructor TExprWord.Create2(AName: string; AExprFunc: TExprFunc; AIsNullPtr: PBoolean);
begin
  FName := AName;
  FExprFunc := AExprFunc;
  if Assigned(AIsNullPtr) then // 04/11/2011 pb  CR 18908
    FIsNullPtr:= AIsNullPtr // 04/11/2011 pb  CR 18908
  else
    FIsNullPtr:= @FIsNull; // 04/11/2011 pb  CR 18908
end;

function TExprWord.GetCanVary: Boolean;
begin
  Result := False;
end;

function TExprWord.GetDescription: string;
begin
  Result := EmptyStr;
end;

function TExprWord.GetShortName: string;
begin
  Result := EmptyStr;
end;

function TExprWord.GetIsOperator: Boolean;
begin
  Result := False;
end;

function TExprWord.GetIsVariable: Boolean;
begin
  // delphi wants to call the function pointed to by the variable, use '@'
  // fpc simply returns pointer to function, no '@' needed
  Result := (@FExprFunc = @_StringVariable)         or
            (@FExprFunc = @_StringConstant)         or
            (@FExprFunc = @_FloatVariable)          or
            (@FExprFunc = @_IntegerVariable)        or
//            (FExprFunc = @_SmallIntVariable)       or
{$ifdef SUPPORT_INT64}
            (@FExprFunc = @_LargeIntVariable)       or
{$endif}
            (@FExprFunc = @_DateTimeVariable)       or
            (@FExprFunc = @_BooleanVariable);
end;

function TExprWord.GetNeedsCopy: Boolean;
begin
  Result := (@FExprFunc <> @_StringConstant)         and
//            (@FExprFunc <> @_StringVariable)         and
//            (@FExprFunc <> @_StringVariableFixedLen) and
// string variable cannot be used as normal parameter
// because it is indirectly referenced and possibly
// not null-terminated (fixed len)
            (@FExprFunc <> @_FloatVariable)          and
            (@FExprFunc <> @_IntegerVariable)        and
//            (FExprFunc <> @_SmallIntVariable)       and
{$ifdef SUPPORT_INT64}
            (@FExprFunc <> @_LargeIntVariable)       and
{$endif}
            (@FExprFunc <> @_DateTimeVariable)       and
            (@FExprFunc <> @_BooleanVariable);
end;

function TExprWord.GetFixedLen: Integer;
begin
  // -1 means variable, non-fixed length
  Result := -1;
end;

function TExprWord.GetMinFunctionArg: Integer;
begin
  Result := 0;
end;

function TExprWord.GetMaxFunctionArg: Integer;
begin
  Result := 0;
end;

function TExprWord.GetResultType: TExpressionType;
begin
  Result := etUnknown;
end;

function TExprWord.GetTypeSpec: string;
begin
  Result := EmptyStr;
end;

function TExprWord.AsPointer: PChar;
begin
  Result := nil;
end;

function TExprWord.LenAsPointer: PInteger;
begin
  Result := nil;
end;

function TExprWord.IsFunction: Boolean;
begin
  Result := False;
end;

procedure TExprWord.SetFixedLen(NewLen: integer);
begin
end;

{ TConstant }

constructor TConstant.Create(AName: string; AVarType: TExpressionType; AExprFunc: TExprFunc);
begin
  inherited Create(AName, AExprFunc);

  FResultType := AVarType;
end;

function TConstant.GetResultType: TExpressionType;
begin
  Result := FResultType;
end;

{ TFloatConstant }

constructor TFloatConstant.Create(AName, AValue: string);
begin
  inherited Create(AName, etFloat, _FloatVariable);

  if Length(AValue) > 0 then
    FValue := StrToFloat(AValue)
  else
    FValue := 0.0;
end;

constructor TFloatConstant.CreateAsDouble(AName: string; AValue: Double);
begin
  inherited Create(AName, etFloat, _FloatVariable);

  FValue := AValue;
end;

function TFloatConstant.AsPointer: PChar;
begin
  Result := PChar(@FValue);
end;

{ TUserConstant }

constructor TUserConstant.CreateAsDouble(AName, Descr: string; AValue: Double);
begin
  FDescription := Descr;

  inherited CreateAsDouble(AName, AValue);
end;

function TUserConstant.GetDescription: string;
begin
  Result := FDescription;
end;

{ TStringConstant }

constructor TStringConstant.Create(AValue: string);
var
  firstChar, lastChar: Char;
begin
  inherited Create(AValue, etString, _StringConstant);

  firstChar := AValue[1];
  lastChar := AValue[Length(AValue)];
  if (firstChar = lastChar) and ((firstChar = '''') or (firstChar = '"')) then
    FValue := Copy(AValue, 2, Length(AValue) - 2)
  else
    FValue := AValue;
end;

function TStringConstant.AsPointer: PChar;
begin
  Result := PChar(FValue);
end;

{ TBooleanConstant }

constructor TBooleanConstant.Create(AName: string; AValue: Boolean);
begin
  inherited Create(AName, etBoolean, _BooleanVariable);

  FValue := AValue;
end;

function TBooleanConstant.AsPointer: PChar;
begin
  Result := PChar(@FValue);
end;

{ TIntegerConstant }

constructor TIntegerConstant.Create(AValue: Integer);
begin
  inherited Create(IntToStr(AValue), etInteger, _IntegerVariable);

  FValue := AValue;
end;

function TIntegerConstant.AsPointer: PChar;
begin
  Result := PChar(@FValue);
end;

{ TVariable }

//constructor TVariable.Create(AName: string; AVarType: TExpressionType; AExprFunc: TExprFunc);
constructor TVariable.Create(AName: string; AVarType: TExpressionType; AExprFunc: TExprFunc; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908
begin
// inherited Create(AName, AExprFunc);
  inherited Create2(AName, AExprFunc, AIsNullPtr); // 04/11/2011 pb  CR 18908

  FResultType := AVarType;
  if Assigned(AFieldInfo) then // 04/11/2011 pb  CR 18908
  begin
    FFieldInfo := AFieldInfo^;
    FFieldInfoValid := True;
  end
end;

function TVariable.GetCanVary: Boolean;
begin
  Result := True;
end;

function TVariable.GetResultType: TExpressionType;
begin
  Result := FResultType;
end;

function TVariable.GetFieldInfo: PVariableFieldInfo; // 04/11/2011 pb  CR 18908
begin
  if FFieldInfoValid then
    Result := @FFieldInfo
  else
    Result := nil;
end;

{ TFloatVariable }

//constructor TFloatVariable.Create(AName: string; AValue: PDouble);
constructor TFloatVariable.Create(AName: string; AValue: PDouble; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908
begin
// inherited Create(AName, etFloat, _FloatVariable);
  inherited Create(AName, etFloat, _FloatVariable, AIsNullPtr, AFieldInfo); // 04/11/2011 pb  CR 18908
  FValue := AValue;
end;

function TFloatVariable.AsPointer: PChar;
begin
  Result := PChar(FValue);
end;

{ TStringVariable }

//constructor TStringVariable.Create(AName: string; AValue: PPChar);
constructor TStringVariable.Create(AName: string; AValue: PPChar; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908
begin
  // variable or fixed length?
//inherited Create(AName, etString, _StringVariable);
  inherited Create(AName, etString, _StringVariable, AIsNullPtr, AFieldInfo); // 04/11/2011 pb  CR 18908

  // store pointer to string
  FValue := AValue;
  FFixedLen := -1;
end;

function TStringVariable.AsPointer: PChar;
begin
  Result := PChar(FValue);
end;

function TStringVariable.GetFixedLen: Integer;
begin
  Result := FFixedLen;
end;

function TStringVariable.LenAsPointer: PInteger;
begin
  Result := @FFixedLen;
end;

procedure TStringVariable.SetFixedLen(NewLen: integer);
begin
  FFixedLen := NewLen;
end;

{ TDateTimeVariable }

//constructor TDateTimeVariable.Create(AName: string; AValue: PDateTimeRec);
constructor TDateTimeVariable.Create(AName: string; AValue: PDateTimeRec; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908
begin
//inherited Create(AName, etDateTime, _DateTimeVariable);
  inherited Create(AName, etDateTime, _DateTimeVariable, AIsNullPtr, AFieldInfo); // 04/11/2011 pb  CR 18908
  FValue := AValue;
end;

function TDateTimeVariable.AsPointer: PChar;
begin
  Result := PChar(FValue);
end;

{ TIntegerVariable }

//constructor TIntegerVariable.Create(AName: string; AValue: PInteger);
constructor TIntegerVariable.Create(AName: string; AValue: PInteger; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo);
begin
//inherited Create(AName, etInteger, _IntegerVariable);
  inherited Create(AName, etInteger, _IntegerVariable, AIsNullPtr, AFieldInfo); // 04/11/2011 pb  CR 18908
  FValue := AValue;
end;

function TIntegerVariable.AsPointer: PChar;
begin
  Result := PChar(FValue);
end;

{$ifdef SUPPORT_INT64}

{ TLargeIntVariable }

//constructor TLargeIntVariable.Create(AName: string; AValue: PLargeInt);
constructor TLargeIntVariable.Create(AName: string; AValue: PLargeInt; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908
begin
//inherited Create(AName, etLargeInt, _LargeIntVariable);
  inherited Create(AName, etLargeInt, _LargeIntVariable, AIsNullPtr, AFieldInfo); // 04/11/2011 pb  CR 18908
  FValue := AValue;
end;

function TLargeIntVariable.AsPointer: PChar;
begin
  Result := PChar(FValue);
end;

{$endif}

{ TBooleanVariable }

//constructor TBooleanVariable.Create(AName: string; AValue: PBoolean);
constructor TBooleanVariable.Create(AName: string; AValue: PBoolean; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo); // 04/11/2011 pb  CR 18908
begin
//inherited Create(AName, etBoolean, _BooleanVariable);
  inherited Create(AName, etBoolean, _BooleanVariable, AIsNullPtr, AFieldInfo); // 04/11/2011 pb  CR 18908
  FValue := AValue;
end;

function TBooleanVariable.AsPointer: PChar;
begin
  Result := PChar(FValue);
end;

{ TLeftBracket }

function TLeftBracket.GetResultType: TExpressionType;
begin
  Result := etLeftBracket;
end;

{ TRightBracket }

function TRightBracket.GetResultType: TExpressionType;
begin
  Result := etRightBracket;
end;

{ TComma }

function TComma.GetResultType: TExpressionType;
begin
  Result := etComma;
end;

{ TExpressList }

constructor TExpressList.Create;
begin
  inherited;

  FShortList := TExpressShortList.Create;
end;

destructor TExpressList.Destroy;
begin
  inherited;
  FShortList.Free;
end;

procedure TExpressList.Add(Item: Pointer);
var
  I: Integer;
begin
  inherited;

  { remember we reference the object }
//Inc(TExprWord(Item).FRefCount);
  InterlockedIncrement(TExprWord(Item).FRefCount); // 03/04/2011 pb  CR 18611- Thread-safe reference counting

  { also add ShortName as reference }
  if Length(TExprWord(Item).ShortName) > 0 then
  begin
    FShortList.Search(FShortList.KeyOf(Item), I);
    FShortList.Insert(I, Item);
  end;
end;

function TExpressList.Compare(Key1, Key2: Pointer): Integer;
begin
  Result := StrIComp(PChar(Key1), PChar(Key2));
end;

function TExpressList.KeyOf(Item: Pointer): Pointer;
begin
  Result := PChar(TExprWord(Item).Name);
end;

procedure TExpressList.FreeItem(Item: Pointer);
begin
//Dec(TExprWord(Item).FRefCount);
//FShortList.Remove(Item);
//if TExprWord(Item).FRefCount = 0 then
//  inherited;
  if InterlockedDecrement(TExprWord(Item).FRefCount) = 0 then // 03/04/2011 pb  CR 18611- Thread-safe reference counting
  begin
    FShortList.Remove(Item);
    inherited;
  end;
end;

function TExpressList.Search(Key: Pointer; var Index: Integer): Boolean;
var
  SecIndex: Integer;
begin
  Result := inherited Search(Key, Index);
  if not Result then
  begin
    Result := FShortList.Search(Key, SecIndex);
    if Result then
      Index := IndexOf(FShortList.Items[SecIndex]);
  end;
end;

function TExpressShortList.Compare(Key1, Key2: Pointer): Integer;
begin
  Result := StrIComp(PChar(Key1), PChar(Key2));
end;

function TExpressShortList.KeyOf(Item: Pointer): Pointer;
begin
  Result := PChar(TExprWord(Item).ShortName);
end;

procedure TExpressShortList.FreeItem(Item: Pointer);
begin
end;

{ TExprCollection }

procedure TExprCollection.Check;
var
  brCount, I: Integer;
begin
  brCount := 0;
  for I := 0 to Count - 1 do
  begin
    case TExprWord(Items[I]).ResultType of
      etLeftBracket: Inc(brCount);
      etRightBracket: Dec(brCount);
    end;
  end;
  if brCount <> 0 then
    raise EParserException.Create('Unequal brackets');
end;

procedure TExprCollection.EraseExtraBrackets;
var
  I: Integer;
  brCount: Integer;
begin
  if (TExprWord(Items[0]).ResultType = etLeftBracket) then
  begin
    brCount := 1;
    I := 1;
    while (I < Count) and (brCount > 0) do
    begin
      case TExprWord(Items[I]).ResultType of
        etLeftBracket: Inc(brCount);
        etRightBracket: Dec(brCount);
      end;
      Inc(I);
    end;
    if (brCount = 0) and (I = Count) and (TExprWord(Items[I - 1]).ResultType =
      etRightBracket) then
    begin
      for I := 0 to Count - 3 do
        Items[I] := Items[I + 1];
      Count := Count - 2;
      EraseExtraBrackets; //Check if there are still too many brackets
    end;
  end;
end;

{ TFunction }

constructor TFunction.Create(AName, AShortName, ATypeSpec: string; AMinFuncArg: Integer; AResultType: TExpressionType;
  AExprFunc: TExprFunc; Descr: string);
begin
  //to increase compatibility don't use default parameters
  FDescription := Descr;
  FShortName := AShortName;
  InternalCreate(AName, ATypeSpec, AMinFuncArg, AResultType, AExprFunc, false, 0);
end;

constructor TFunction.CreateOper(AName, ATypeSpec: string; AResultType: TExpressionType;
  AExprFunc: TExprFunc; AOperPrec: Integer);
begin
  InternalCreate(AName, ATypeSpec, -1, AResultType, AExprFunc, true, AOperPrec);
end;

procedure TFunction.InternalCreate(AName, ATypeSpec: string; AMinFuncArg: Integer; AResultType: TExpressionType;
  AExprFunc: TExprFunc; AIsOperator: Boolean; AOperPrec: Integer);
begin
  inherited Create(AName, AExprFunc);

  FMaxFunctionArg := Length(ATypeSpec);
  FMinFunctionArg := AMinFuncArg;
  if AMinFuncArg = -1 then
    FMinFunctionArg := FMaxFunctionArg;
  FIsOperator := AIsOperator;
  FOperPrec := AOperPrec;
  FTypeSpec := ATypeSpec;
  FResultType := AResultType;

  // check correctness
  if FMaxFunctionArg > MaxArg then
    raise EParserException.Create('Too many arguments');
end;

// 04/15/2011 pb  CR 18536- A function varies unless otherwise specified
function TFunction.GetCanVary: Boolean;
begin
  Result := True;
end;

function TFunction.GetDescription: string;
begin
  Result := FDescription;
end;

function TFunction.GetIsOperator: Boolean;
begin
  Result := FIsOperator;
end;

function TFunction.GetMinFunctionArg: Integer;
begin
  Result := FMinFunctionArg;
end;

function TFunction.GetMaxFunctionArg: Integer;
begin
  Result := FMaxFunctionArg;
end;

function TFunction.GetResultType: TExpressionType;
begin
  Result := FResultType;
end;

function TFunction.GetShortName: string;
begin
  Result := FShortName;
end;

function TFunction.GetTypeSpec: string;
begin
  Result := FTypeSpec;
end;

function TFunction.IsFunction: Boolean;
begin
  Result := True;
end;

{ TVaryingFunction }

// 04/15/2011 pb  CR 18536- A function varies unless otherwise specified
(*
function TVaryingFunction.GetCanVary: Boolean;
begin
  Result := True;
end;
*)

{ TDynamicType }

constructor TDynamicType.Create(DestMem, DestPos: PPChar; ASize: PInteger);
begin
  inherited Create;

  FMemory := DestMem;
  FMemoryPos := DestPos;
  FSize := ASize;
end;

procedure TDynamicType.Rewind;
begin
  FMemoryPos^ := FMemory^;
  FillChar(FMemory^^, FSize^, 0); // 04/27/2011 pb  CR 18890
end;

procedure TDynamicType.AssureSpace(ASize: Integer);
begin
  // need more memory?
  if ((FMemoryPos^) - (FMemory^) + ASize) > (FSize^) then
    Resize((FMemoryPos^) - (FMemory^) + ASize, False);
end;

procedure TDynamicType.Resize(NewSize: Integer; Exact: Boolean);
var
  tempBuf: PChar;
  bytesCopy, pos: Integer;
begin
  // if not exact requested make newlength a multiple of ArgAllocSize
  if not Exact then
    NewSize := NewSize div ArgAllocSize * ArgAllocSize + ArgAllocSize;
  // create new buffer
  GetMem(tempBuf, NewSize);
  FillChar(tempBuf^, NewSize, 0); // 04/04/2011 pb  CR 18890
  // copy memory
  bytesCopy := FSize^;
  if bytesCopy > NewSize then
    bytesCopy := NewSize;
  Move(FMemory^^, tempBuf^, bytesCopy);
  // save position in string
  pos := FMemoryPos^ - FMemory^;
  // delete old mem
  FreeMem(FMemory^);
  // assign new
  FMemory^ := tempBuf;
  FSize^ := NewSize;
  // assign position
  FMemoryPos^ := FMemory^ + pos;
end;

procedure TDynamicType.Append(Source: PChar; Length: Integer);
begin
  // make room for string plus null-terminator
  AssureSpace(Length+4);
  // copy
  Move(Source^, FMemoryPos^^, Length);
  Inc(FMemoryPos^, Length);
  // null-terminate
  FMemoryPos^^ := #0;
end;

procedure TDynamicType.AppendInteger(Source: Integer);
begin
  // make room for number
  AssureSpace(12);
//Inc(FMemoryPos^, GetStrFromInt(Source, FMemoryPos^));
  Inc(FMemoryPos^, IntToStrWidth(Source, 11, FMemoryPos^, False, #0)); // 05/05/2011 pb  CR 18984
  FMemoryPos^^ := #0;
end;

end.

