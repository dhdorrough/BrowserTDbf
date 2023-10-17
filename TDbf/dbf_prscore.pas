unit dbf_prscore;

// Modifications by BCC Software
// 11/10/2011 pb  CR 19542- Implement SUBSTR() with two arguments
// 11/01/2011 pb  CR 19713- Comparison operators should use collation
// 08/09/2011 pb  CR 19354- Check for too many parameters when looking for alternative function/operator signatures is incorrect
// 08/04/2011 pb  CR 19339- Do not dispose of nodes with @ExprFunc = nil to prevent it from setting an ArgList[] member to nil
// 05/25/2011 pb  CR 18536- Chr() function
// 05/05/2011 pb  CR 18984- Number to string conversion is inconsistent and does not properly take into account the width
// 04/29/2011 pb  CR 18895- Take into account language driver when converting case
// 04/28/2011 pb  CR 18536- Val() function
// 04/28/2011 pb  CR 18536- Empty() function
// 04/28/2011 pb  CR 18536- LTrim(), RTrim() and Trim() should do nothing when validating, so that Key Length calculations is correct
// 04/28/2011 pb  CR 18536- Implemented LTrim() using FuncLTrim
// 04/28/2011 pb  CR 18536- Trim() and RTrim() should not remove leading spaces
// 04/28/2011 pb  CR 18536- Asc() function needs to disregard trailing spaces and return etInteger
// 04/28/2011 pb  CR 18536- Left() and Right() functions need to check second parameter
// 04/28/2011 pb  CR 18884- Unary plus (+) operator
// 04/28/2011 pb  CR 18884- Unary minus (-) operator
// 04/27/2011 pb  CR 18959- etString - etString = etString
// 04/27/2011 pb  CR 18959- etString - etDateTime = etDateTime - etString = etString
// 04/27/2011 pb  CR 18959- etString - etFloat = etFloat - etString = etString
// 04/27/2011 pb  CR 18959- etString - etInteger = etInteger - etString = etString
// 04/27/2011 pb  CR 18959- etString - etLargeInt = etLargeInt - etString = etString
// 04/27/2011 pb  CR 18890- Reinitialize dynamic buffer
// 04/27/2011 pb  CR 18959- FExpressionContext holds context-specific information the evaluation functions need to know
// 04/27/2011 pb  CR 18959- etDateTime - etLargeInt = etDateTime
// 04/27/2011 pb  CR 18959- etDateTime - etInteger = etDateTime
// 04/27/2011 pb  CR 18959- etDateTime - etFloat = etDateTime
// 04/27/2011 pb  CR 18959- etDateTime - etDateTime = etFloat
// 04/15/2011 pb  CR 18892- Proper() function
// 04/15/2011 pb  CR 18893- RecNo() function
// 04/15/2011 pb  CR 18536- A function varies unless otherwise indicated, even if it has 0 parameters
// 04/13/2011 pb  CR 18922- DTOS(null) should be null
// 04/13/2011 pb  CR 18908- Left-to-right evaluation of operators with equal precedance
// 04/11/2011 pb  CR 18908- etString + etDateTime = etDateTime + etString = etString
// 04/11/2011 pb  CR 18908- etString + etFloat = etFloat + etString = etString
// 04/11/2011 pb  CR 18908- etString + etInteger = etInteger + etString = etString
// 04/11/2011 pb  CR 18908- etString + etLargeInt = etLargeInt + etString = etString
// 04/11/2011 pb  CR 18908- etDateTime + etFloat = etFloat + etDateTime = etDateTime
// 04/11/2011 pb  CR 18908- etDateTime + etLargeInt = etLargeInt + etDateTime = etDateTime
// 04/11/2011 pb  CR 18908- Null value in an expression
// 04/08/2011 pb  CR 18544- In an expression of the form S <- S+L convert the integer to a string and then concatenate
// 04/04/2011 pb  CR 18890- Check buffer size when building index key
// 04/04/2011 pb  CR 18890- Initialize result buffer
// 03/29/2011 dhd CR 18536- Use Trim() before evaluating Val(); evaluate to 0 if non-numeric
// 03/24/2011 dhd CR 18536- Implement parser functions: I <- Ceil(F), F <- Ceil(F), F <- Round(F, F), F <- Float(F, I), Date()
// 01/27/2011 dhd CR 18536- Fixed potential Access Violation in Upper, Lower if Resize is called
// 01/27/2011 dhd CR 18536- Implement parser functions: Soundex, Left, Right, Day, Month, Year, Str, Abs, IIF, Trim, Len, RTrim, LTrim, Chr, Asc, At, Val, Empty, CDOW
// 01/27/2011 dhd CR 18544- In an expression of the form S <- I+S, S <- L+S, S <- S+I convert the integer to a string and then concatenate

{--------------------------------------------------------------
| TCustomExpressionParser
|
| - contains core expression parser
|
| This code is based on code from:
|
| Original author: Egbert van Nes
| With contributions of: John Bultena and Ralf Junker
| Homepage: http://www.slm.wau.nl/wkao/parseexpr.html
|
| see also: http://www.datalog.ro/delphi/parser.html
|   (Renate Schaaf (schaaf at math.usu.edu), 1993
|    Alin Flaider (aflaidar at datalog.ro), 1996
|    Version 9-10: Stefan Hoffmeister, 1996-1997)
|
|---------------------------------------------------------------}

interface

{$I dbf_common.inc}

uses
  SysUtils,
  Classes,
  Db,
  Windows,
  dbf_prssupp,
  dbf_prsdef;

{$define ENG_NUMBERS}

// ENG_NUMBERS will force the use of english style numbers 8.1 instead of 8,1
//   (if the comma is your decimal separator)
// the advantage is that arguments can be separated with a comma which is
// fairly common, otherwise there is ambuigity: what does 'var1,8,4,4,5' mean?
// if you don't define ENG_NUMBERS and DecimalSeparator is a comma then
// the argument separator will be a semicolon ';'

type

  TCustomExpressionParser = class(TObject)
  private
    FHexChar: Char;
    FArgSeparator: Char;
    FDecimalSeparator: Char;
    FOptimize: Boolean;
    FConstantsList: TOCollection;
    FLastRec: PExpressionRec;
    FCurrentRec: PExpressionRec;
    FExpResult: PChar;
    FExpResultPos: PChar;
    FExpResultSize: Integer;

    procedure ParseString(AnExpression: string; DestCollection: TExprCollection);
    function  MakeTree(Expr: TExprCollection; FirstItem, LastItem: Integer): PExpressionRec;
    procedure MakeLinkedList(var ExprRec: PExpressionRec; Memory: PPChar;
        MemoryPos: PPChar; MemSize: PInteger);
    procedure Check(AnExprList: TExprCollection);
    procedure CheckArguments(ExprRec: PExpressionRec);
    procedure RemoveConstants(var ExprRec: PExpressionRec);
    function ResultCanVary(ExprRec: PExpressionRec): Boolean;
  protected
    FExpressionContext: TExpressionContext; // 04/27/2011 pb  CR 18959
    FWordsList: TSortedCollection;

    function MakeRec: PExpressionRec; virtual;
    procedure FillExpressList; virtual; abstract;
    procedure HandleUnknownVariable(VarName: string); virtual; abstract;

    procedure CompileExpression(AnExpression: string);
    procedure EvaluateCurrent;
    procedure DisposeList(ARec: PExpressionRec);
    procedure DisposeTree(ExprRec: PExpressionRec);
    function CurrentExpression: string; virtual; abstract;
    function GetResultType: TExpressionType; virtual;
    function IsIndex: Boolean; virtual; // 04/11/2011 pb  CR 18908
    procedure OptimizeExpr(var ExprRec: PExpressionRec); virtual; // 04/15/2011 pb  CR 18893

    property CurrentRec: PExpressionRec read FCurrentRec write FCurrentRec;
    property LastRec: PExpressionRec read FLastRec write FLastRec;
    property ExpResult: PChar read FExpResult;
    property ExpResultPos: PChar read FExpResultPos write FExpResultPos;

  public
    constructor Create;
    destructor Destroy; override;

//  function DefineFloatVariable(AVarName: string; AValue: PDouble): TExprWord;
    function DefineFloatVariable(AVarName: string; AValue: PDouble; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo): TExprWord; // 04/11/2011 pb  CR 18908
//  function DefineIntegerVariable(AVarName: string; AValue: PInteger): TExprWord;
    function DefineIntegerVariable(AVarName: string; AValue: PInteger; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo): TExprWord; // 04/11/2011 pb  CR 18908
//    procedure DefineSmallIntVariable(AVarName: string; AValue: PSmallInt);
{$ifdef SUPPORT_INT64}
//  function DefineLargeIntVariable(AVarName: string; AValue: PLargeInt): TExprWord;
    function DefineLargeIntVariable(AVarName: string; AValue: PLargeInt; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo): TExprWord; // 04/11/2011 pb  CR 18908
{$endif}
//  function DefineDateTimeVariable(AVarName: string; AValue: PDateTimeRec): TExprWord;
    function DefineDateTimeVariable(AVarName: string; AValue: PDateTimeRec; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo): TExprWord; // 04/11/2011 pb  CR 18908
//  function DefineBooleanVariable(AVarName: string; AValue: PBoolean): TExprWord;
    function DefineBooleanVariable(AVarName: string; AValue: PBoolean; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo): TExprWord; // 04/11/2011 pb  CR 18908
//  function DefineStringVariable(AVarName: string; AValue: PPChar): TExprWord;
    function DefineStringVariable(AVarName: string; AValue: PPChar; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo): TExprWord; // 04/11/2011 pb  CR 18908
    function DefineFunction(AFunctName, AShortName, ADescription, ATypeSpec: string;
        AMinFunctionArg: Integer; AResultType: TExpressionType; AFuncAddress: TExprFunc): TExprWord;
    procedure Evaluate(AnExpression: string);
    function AddExpression(AnExpression: string): Integer;
    procedure ClearExpressions; virtual;
//    procedure GetGeneratedVars(AList: TList);
    procedure GetFunctionNames(AList: TStrings);
    function GetFunctionDescription(AFunction: string): string;
    property HexChar: Char read FHexChar write FHexChar;
    property ArgSeparator: Char read FArgSeparator write FArgSeparator;
    property Optimize: Boolean read FOptimize write FOptimize;
    property ResultType: TExpressionType read GetResultType;
    property ExpResultSize: Integer read fExpResultSize; // 04/04/2011 pb  CR 18890


    //if optimize is selected, constant expressions are tried to remove
    //such as: 4*4*x is evaluated as 16*x and exp(1)-4*x is repaced by 2.17 -4*x
  end;


//--Expression functions-----------------------------------------------------

//procedure FuncFloatToStr(Param: PExpressionRec);
//procedure FuncIntToStr_Gen(Param: PExpressionRec; Val: {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif});
//procedure FuncIntToStr(Param: PExpressionRec);
//{$ifdef SUPPORT_INT64}
//procedure FuncInt64ToStr(Param: PExpressionRec);
//{$endif}
procedure FuncStr      (Param: PExpressionRec); // 05/05/2011 pb  CR 18984
procedure FuncDateToStr(Param: PExpressionRec);
procedure FuncSubString(Param: PExpressionRec);
procedure FuncUppercase(Param: PExpressionRec);
procedure FuncLowercase(Param: PExpressionRec);
procedure FuncProper   (Param: PExpressionRec); // 04/15/2011 pb  CR 18892

procedure FuncLeft     (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncRight    (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncIIF_S_SS (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncIIF_F_FF (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncIIF_I_II (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncSoundex  (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncDay      (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncMonth    (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncYear     (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncCDOW     (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncAbs_F_F  (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncAbs_I_I  (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
{$ifdef SUPPORT_INT64}
procedure FuncAbs_F_L  (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
{$endif}
procedure FuncEmpty    (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncLen_F_S  (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
{$ifdef SUPPORT_INT64}
procedure FuncLen_L_S  (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
{$endif}
procedure FuncLen_I_S  (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncRTrim    (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncLTrim    (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncChr      (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncAt       (Param: PexpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncAsc      (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
//procedure FuncVal_I    (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
//procedure FuncVal_F    (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
//procedure FuncVal_L    (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
procedure FuncVal      (Param: PExpressionRec); // 04/28/2011 pb  CR 18536
procedure FuncRound_F_FF(Param: PExpressionRec); // 03/23/2011 dhd CR 18536
procedure FuncRound_F_FI(Param: PExpressionRec); // 03/23/2011 dhd CR 18536
procedure FuncCeil_I_F (Param: PExpressionRec); // 03/23/2011 dhd CR 18536
procedure FuncCeil_F_F (Param: PExpressionRec); // 03/23/2011 dhd CR 18536
procedure FuncDate     (Param: PExpressionRec); // 03/23/2011 dhd CR 18536
procedure FuncRecNo    (Param: PExpressionRec); // 04/15/2011 pb  CR 18893

procedure FuncAdd_F_FF(Param: PExpressionRec);
procedure FuncAdd_F_FI(Param: PExpressionRec);
procedure FuncAdd_F_II(Param: PExpressionRec);
procedure FuncAdd_F_IF(Param: PExpressionRec);
{$ifdef SUPPORT_INT64}
procedure FuncAdd_F_FL(Param: PExpressionRec);
procedure FuncAdd_F_IL(Param: PExpressionRec);
procedure FuncAdd_F_LL(Param: PExpressionRec);
procedure FuncAdd_F_LF(Param: PExpressionRec);
procedure FuncAdd_F_LI(Param: PExpressionRec);
{$endif}
procedure FuncAdd_D_DF(Param: PExpressionRec); // 04/08/2011 pb  CR 18908
procedure FuncAdd_D_DI(Param: PExpressionRec); // 04/08/2011 pb  CR 18908
procedure FuncAdd_D_DL(Param: PExpressionRec); // 04/08/2011 pb  CR 18908
procedure FuncAdd_D_FD(Param: PExpressionRec); // 04/08/2011 pb  CR 18908
procedure FuncAdd_D_ID(Param: PExpressionRec); // 04/08/2011 pb  CR 18908
procedure FuncAdd_D_LD(Param: PExpressionRec); // 04/08/2011 pb  CR 18908
procedure FuncAdd_S(Param: PExpressionRec); // 04/08/2011 pb  CR 18908
procedure FuncSub_D_DF(Param: PExpressionRec); // 04/27/2011 pb  CR 18959
procedure FuncSub_D_DI(Param: PExpressionRec); // 04/27/2011 pb  CR 18959
procedure FuncSub_F_FF(Param: PExpressionRec);
procedure FuncSub_F_FI(Param: PExpressionRec);
procedure FuncSub_F_II(Param: PExpressionRec);
procedure FuncSub_F_IF(Param: PExpressionRec);
procedure FuncSub_F_DD(Param: PExpressionRec); // 04/27/2011 pb  CR 18959
{$ifdef SUPPORT_INT64}
procedure FuncSub_D_DL(Param: PExpressionRec); // 04/27/2011 pb  CR 18959
procedure FuncSub_F_FL(Param: PExpressionRec);
procedure FuncSub_F_IL(Param: PExpressionRec);
procedure FuncSub_F_LL(Param: PExpressionRec);
procedure FuncSub_F_LF(Param: PExpressionRec);
procedure FuncSub_F_LI(Param: PExpressionRec);
{$endif}
procedure FuncSub_S(Param: PExpressionRec); // 04/27/2011 pb  CR 18959
procedure FuncNegate(Param: PExpressionRec); // 04/27/2011 pb  CR 18884
procedure FuncMul_F_FF(Param: PExpressionRec);
procedure FuncMul_F_FI(Param: PExpressionRec);
procedure FuncMul_F_II(Param: PExpressionRec);
procedure FuncMul_F_IF(Param: PExpressionRec);
{$ifdef SUPPORT_INT64}
procedure FuncMul_F_FL(Param: PExpressionRec);
procedure FuncMul_F_IL(Param: PExpressionRec);
procedure FuncMul_F_LL(Param: PExpressionRec);
procedure FuncMul_F_LF(Param: PExpressionRec);
procedure FuncMul_F_LI(Param: PExpressionRec);
{$endif}
procedure FuncDiv_F_FF(Param: PExpressionRec);
procedure FuncDiv_F_FI(Param: PExpressionRec);
procedure FuncDiv_F_II(Param: PExpressionRec);
procedure FuncDiv_F_IF(Param: PExpressionRec);
{$ifdef SUPPORT_INT64}
procedure FuncDiv_F_FL(Param: PExpressionRec);
procedure FuncDiv_F_IL(Param: PExpressionRec);
procedure FuncDiv_F_LL(Param: PExpressionRec);
procedure FuncDiv_F_LF(Param: PExpressionRec);
procedure FuncDiv_F_LI(Param: PExpressionRec);
{$endif}
procedure FuncStrI_EQ(Param: PExpressionRec);
procedure FuncStrI_NEQ(Param: PExpressionRec);
procedure FuncStrI_LT(Param: PExpressionRec);
procedure FuncStrI_GT(Param: PExpressionRec);
procedure FuncStrI_LTE(Param: PExpressionRec);
procedure FuncStrI_GTE(Param: PExpressionRec);
procedure FuncStr_EQ(Param: PExpressionRec);
procedure FuncStr_NEQ(Param: PExpressionRec);
procedure FuncStr_LT(Param: PExpressionRec);
procedure FuncStr_GT(Param: PExpressionRec);
procedure FuncStr_LTE(Param: PExpressionRec);
procedure FuncStr_GTE(Param: PExpressionRec);
procedure Func_FF_EQ(Param: PExpressionRec);
procedure Func_FF_NEQ(Param: PExpressionRec);
procedure Func_FF_LT(Param: PExpressionRec);
procedure Func_FF_GT(Param: PExpressionRec);
procedure Func_FF_LTE(Param: PExpressionRec);
procedure Func_FF_GTE(Param: PExpressionRec);
procedure Func_FI_EQ(Param: PExpressionRec);
procedure Func_FI_NEQ(Param: PExpressionRec);
procedure Func_FI_LT(Param: PExpressionRec);
procedure Func_FI_GT(Param: PExpressionRec);
procedure Func_FI_LTE(Param: PExpressionRec);
procedure Func_FI_GTE(Param: PExpressionRec);
procedure Func_II_EQ(Param: PExpressionRec);
procedure Func_II_NEQ(Param: PExpressionRec);
procedure Func_II_LT(Param: PExpressionRec);
procedure Func_II_GT(Param: PExpressionRec);
procedure Func_II_LTE(Param: PExpressionRec);
procedure Func_II_GTE(Param: PExpressionRec);
procedure Func_IF_EQ(Param: PExpressionRec);
procedure Func_IF_NEQ(Param: PExpressionRec);
procedure Func_IF_LT(Param: PExpressionRec);
procedure Func_IF_GT(Param: PExpressionRec);
procedure Func_IF_LTE(Param: PExpressionRec);
procedure Func_IF_GTE(Param: PExpressionRec);
{$ifdef SUPPORT_INT64}
procedure Func_LL_EQ(Param: PExpressionRec);
procedure Func_LL_NEQ(Param: PExpressionRec);
procedure Func_LL_LT(Param: PExpressionRec);
procedure Func_LL_GT(Param: PExpressionRec);
procedure Func_LL_LTE(Param: PExpressionRec);
procedure Func_LL_GTE(Param: PExpressionRec);
procedure Func_LF_EQ(Param: PExpressionRec);
procedure Func_LF_NEQ(Param: PExpressionRec);
procedure Func_LF_LT(Param: PExpressionRec);
procedure Func_LF_GT(Param: PExpressionRec);
procedure Func_LF_LTE(Param: PExpressionRec);
procedure Func_LF_GTE(Param: PExpressionRec);
procedure Func_FL_EQ(Param: PExpressionRec);
procedure Func_FL_NEQ(Param: PExpressionRec);
procedure Func_FL_LT(Param: PExpressionRec);
procedure Func_FL_GT(Param: PExpressionRec);
procedure Func_FL_LTE(Param: PExpressionRec);
procedure Func_FL_GTE(Param: PExpressionRec);
procedure Func_LI_EQ(Param: PExpressionRec);
procedure Func_LI_NEQ(Param: PExpressionRec);
procedure Func_LI_LT(Param: PExpressionRec);
procedure Func_LI_GT(Param: PExpressionRec);
procedure Func_LI_LTE(Param: PExpressionRec);
procedure Func_LI_GTE(Param: PExpressionRec);
procedure Func_IL_EQ(Param: PExpressionRec);
procedure Func_IL_NEQ(Param: PExpressionRec);
procedure Func_IL_LT(Param: PExpressionRec);
procedure Func_IL_GT(Param: PExpressionRec);
procedure Func_IL_LTE(Param: PExpressionRec);
procedure Func_IL_GTE(Param: PExpressionRec);
{$endif}
procedure Func_AND(Param: PExpressionRec);
procedure Func_OR(Param: PExpressionRec);
procedure Func_NOT(Param: PExpressionRec);

var
  DbfWordsSensGeneralList, DbfWordsInsensGeneralList: TExpressList;
  DbfWordsSensPartialList, DbfWordsInsensPartialList: TExpressList;
  DbfWordsSensNoPartialList, DbfWordsInsensNoPartialList: TExpressList;
  DbfWordsGeneralList: TExpressList;

implementation

uses
  Math,
  Dbf_Collate, dbf_lang;

const
  BAD_DATE = 0; // 01/27/2011 dhd CR 18536

procedure LinkVariable(ExprRec: PExpressionRec);
begin
  with ExprRec^ do
  begin
    if ExprWord.IsVariable then
    begin
      // copy pointer to variable
      Args[0] := ExprWord.AsPointer;
      // store length as second parameter
      Args[1] := PChar(ExprWord.LenAsPointer);
      IsNullPtr := ExprWord.IsNullPtr; // 04/11/2011 pb  CR 18908
    end
    else
      IsNullPtr := @ExprRec^.IsNull; // 04/11/2011 pb  CR 18908
  end;
end;

procedure LinkVariables(ExprRec: PExpressionRec);
var
  I: integer;
begin
  with ExprRec^ do
  begin
    I := 0;
    while (I < MaxArg) and (ArgList[I] <> nil) do
    begin
      LinkVariables(ArgList[I]);
      Inc(I);
    end;
  end;
  LinkVariable(ExprRec);
end;

{ TCustomExpressionParser }

constructor TCustomExpressionParser.Create;
begin
  inherited;

  FHexChar := '$';
{$IFDEF ENG_NUMBERS}
  FDecimalSeparator := '.';
  FArgSeparator := ',';
{$ELSE}
  FDecimalSeparator := DecimalSeparator;
  if DecimalSeparator = ',' then
    FArgSeparator := ';'
  else
    FArgSeparator := ',';
{$ENDIF}
  FConstantsList := TOCollection.Create;
  FWordsList := TExpressList.Create;
  GetMem(FExpResult, ArgAllocSize);
  FExpResultPos := FExpResult;
  FExpResultSize := ArgAllocSize;
  FillChar(FExpResultPos^, FExpResultSize, 0); // 04/04/2011 pb  CR 18890
  FOptimize := true;
  FExpressionContext.LocaleID := GetThreadLocale; // 04/29/2011 pb  CR 18895
  FExpressionContext.Collation := BINARY_COLLATION; // 11/01/2011 pb  CR 19713
  FillExpressList;
end;

destructor TCustomExpressionParser.Destroy;
begin
  ClearExpressions;
  FreeMem(FExpResult);
  FConstantsList.Free;
  FWordsList.Free;

  inherited;
end;

procedure TCustomExpressionParser.CompileExpression(AnExpression: string);
var
  ExpColl: TExprCollection;
  ExprTree: PExpressionRec;
begin
  if Length(AnExpression) > 0 then
  begin
    ExprTree := nil;
    ExpColl := TExprCollection.Create;
    try
      //    FCurrentExpression := anExpression;
      ParseString(AnExpression, ExpColl);
      Check(ExpColl);
      ExprTree := MakeTree(ExpColl, 0, ExpColl.Count - 1);
      FCurrentRec := nil;
      CheckArguments(ExprTree);
//    LinkVariables(ExprTree);
      if Optimize then
//      RemoveConstants(ExprTree);
        OptimizeExpr(ExprTree); // 04/15/2011 pb  CR 18893
      // all constant expressions are evaluated and replaced by variables
      LinkVariables(ExprTree); // 04/15/2011 pb  CR 18893
      FCurrentRec := nil;
      FExpResultPos := FExpResult;
      MakeLinkedList(ExprTree, @FExpResult, @FExpResultPos, @FExpResultSize);
    except
      on E: Exception do
      begin
        DisposeTree(ExprTree);
        ExpColl.Free;
        raise;
      end;
    end;
    ExpColl.Free;
  end;
end;

procedure TCustomExpressionParser.CheckArguments(ExprRec: PExpressionRec);
var
  TempExprWord: TExprWord;
  I, error, firstFuncIndex, funcIndex: Integer;
  foundAltFunc: Boolean;

  procedure FindAlternate;
  begin
    // see if we can find another function
    if funcIndex < 0 then
    begin
      firstFuncIndex := FWordsList.IndexOf(ExprRec^.ExprWord);
      funcIndex := firstFuncIndex;
    end;
    // check if not last function
    if (0 <= funcIndex) and (funcIndex < FWordsList.Count - 1) then
    begin
      inc(funcIndex);
      TempExprWord := TExprWord(FWordsList.Items[funcIndex]);
      if FWordsList.Compare(FWordsList.KeyOf(ExprRec^.ExprWord), FWordsList.KeyOf(TempExprWord)) = 0 then
      begin
        ExprRec^.ExprWord := TempExprWord;
        ExprRec^.Oper := ExprRec^.ExprWord.ExprFunc;
        foundAltFunc := true;
      end;
    end;
  end;

  procedure InternalCheckArguments;
  begin
    I := 0;
    error := 0;
    foundAltFunc := false;
    with ExprRec^ do
    begin
      if WantsFunction <> (ExprWord.IsFunction and not ExprWord.IsOperator) then
      begin
        error := 4;
        exit;
      end;

//      while (I < ExprWord.MaxFunctionArg) and (ArgList[I] <> nil) and (error = 0) do
      while (ArgList[I] <> nil) and (error = 0) do // 08/09/2011 pb  CR 19354
      begin
        if I < ExprWord.MaxFunctionArg then // 08/09/2011 pb  CR 19354
        begin
          // test subarguments first
          CheckArguments(ArgList[I]);

          // test if correct type
          if (ArgList[I]^.ExprWord.ResultType <> ExprCharToExprType(ExprWord.TypeSpec[I+1])) then
            error := 2;
        end;

        // goto next argument
        Inc(I);
      end;

      // test if enough parameters passed; I = num args user passed
      if (error = 0) and (I < ExprWord.MinFunctionArg) then
        error := 1;

      // test if too many parameters passed
      if (error = 0) and (I > ExprWord.MaxFunctionArg) then
        error := 3;
    end;
  end;

begin
  funcIndex := -1;
  repeat
    InternalCheckArguments;

    // error occurred?
    if error <> 0 then
      FindAlternate;
  until (error = 0) or not foundAltFunc;

  // maybe it's an undefined variable
  if (error <> 0) and not ExprRec^.WantsFunction and (firstFuncIndex >= 0) then
  begin
    HandleUnknownVariable(ExprRec^.ExprWord.Name);
    { must not add variable as first function in this set of duplicates,
      otherwise following searches will not find it }
    FWordsList.Exchange(firstFuncIndex, firstFuncIndex+1);
    ExprRec^.ExprWord := TExprWord(FWordsList.Items[firstFuncIndex+1]);
    ExprRec^.Oper := ExprRec^.ExprWord.ExprFunc;
    InternalCheckArguments;
  end;

  if (error = 0) and ((@ExprRec^.Oper = @FuncAdd_S) or (@ExprRec^.Oper = @FuncSub_S)) and (not IsIndex) then // 04/11/2011 pb  CR 18908 // 04/27/2011 pb  CR 18959
    error := 2; // 04/11/2011 pb  CR 18908 // 04/27/2011 pb  CR 18959

  // fatal error?
  case error of
    1: raise EParserException.Create('Function or operand has too few arguments');
    2: raise EParserException.Create('Argument type mismatch');
    3: raise EParserException.Create('Function or operand has too many arguments');
    4: raise EParserException.Create('No function with this name, remove brackets for variable');
  end;
end;

function TCustomExpressionParser.ResultCanVary(ExprRec: PExpressionRec):
  Boolean;
var
  I: Integer;
  ArgCount: Integer; // 04/15/2011 pb  CR 18536
  CanVaryCount: Integer; // 04/15/2011 pb  CR 18536
begin
  with ExprRec^ do
  begin
    Result := ExprWord.CanVary;
    if not Result then
    begin
      ArgCount := 0; // 04/15/2011 pb  CR 18536
      CanVaryCount := 0;  // 04/15/2011 pb  CR 18536
      for I := 0 to ExprWord.MaxFunctionArg - 1 do
      begin
//      if (ArgList[I] <> nil) and ResultCanVary(ArgList[I]) then
//      begin
//        Result := true;
//        Exit;
//      end
        if (ArgList[I] <> nil) then // 04/15/2011 pb  CR 18536
        begin
          Inc(ArgCount);
          if ResultCanVary(ArgList[I]) then
            Inc(CanVaryCount);
        end;
      end;
      if (ArgCount <> 0) and (CanVaryCount = 0) then // 04/15/2011 pb  CR 18536
        Result := False;
    end;
  end;
end;

procedure TCustomExpressionParser.RemoveConstants(var ExprRec: PExpressionRec);
var
  I: Integer;
begin
  if not ResultCanVary(ExprRec) then
  begin
    if not ExprRec^.ExprWord.IsVariable then
    begin
      // reset current record so that make list generates new
      FCurrentRec := nil;
      FExpResultPos := FExpResult;
      MakeLinkedList(ExprRec, @FExpResult, @FExpResultPos, @FExpResultSize);

      try
        // compute result
        EvaluateCurrent;

        // make new record to store constant in
        ExprRec := MakeRec;

        // check result type
        with ExprRec^ do
        begin
          case ResultType of
            etBoolean: ExprWord := TBooleanConstant.Create(EmptyStr, PBoolean(FExpResult)^);
            etFloat: ExprWord := TFloatConstant.CreateAsDouble(EmptyStr, PDouble(FExpResult)^);
            etString: ExprWord := TStringConstant.Create(FExpResult);
          end;

          // fill in structure
          Oper := ExprWord.ExprFunc;
          Args[0] := ExprWord.AsPointer;
          FConstantsList.Add(ExprWord);
        end;
      finally
        DisposeList(FCurrentRec);
        FCurrentRec := nil;
      end;
    end;
  end else
    with ExprRec^ do
    begin
      for I := 0 to ExprWord.MaxFunctionArg - 1 do
        if ArgList[I] <> nil then
          RemoveConstants(ArgList[I]);
    end;
end;

procedure TCustomExpressionParser.DisposeTree(ExprRec: PExpressionRec);
var
  I: Integer;
begin
  if ExprRec <> nil then
  begin
    with ExprRec^ do
    begin
      if ExprWord <> nil then
        for I := 0 to ExprWord.MaxFunctionArg - 1 do
          DisposeTree(ArgList[I]);
      if Res <> nil then
        Res.Free;
    end;
    Dispose(ExprRec);
  end;
end;

procedure TCustomExpressionParser.DisposeList(ARec: PExpressionRec);
var
  TheNext: PExpressionRec;
  I: Integer;
begin
  if ARec <> nil then
    repeat
      TheNext := ARec^.Next;
      if ARec^.Res <> nil then
        ARec^.Res.Free;
      I := 0;
      while ARec^.ArgList[I] <> nil do
      begin
        FreeMem(ARec^.Args[I]);
        Inc(I);
      end;
      Dispose(ARec);
      ARec := TheNext;
    until ARec = nil;
end;

procedure TCustomExpressionParser.MakeLinkedList(var ExprRec: PExpressionRec;
  Memory: PPChar; MemoryPos: PPChar; MemSize: PInteger);
var
  I: Integer;
begin
  // test function type
  if @ExprRec^.ExprWord.ExprFunc = nil then
  begin
    // special 'no function' function
    // indicates no function is present -> we can concatenate all instances
    // we don't create new arguments...these 'fall' through
    // use destination as we got it
    I := 0;
    while ExprRec^.ArgList[I] <> nil do
    begin
      // convert arguments to list
      MakeLinkedList(ExprRec^.ArgList[I], Memory, MemoryPos, MemSize);
      // goto next argument
      Inc(I);
    end;
    // don't need this record anymore
// 08/04/2011 pb  CR 19339- ExprRec may be a member of ArgList[]
//  Dispose(ExprRec);
//  ExprRec := nil;
  end else begin
    // inc memory pointer so we know if we are first
    ExprRec^.ResetDest := MemoryPos^ = Memory^;
    Inc(MemoryPos^);
    // convert arguments to list
    I := 0;
    while ExprRec^.ArgList[I] <> nil do
    begin
      // save variable type for easy access
      ExprRec^.ArgsType[I] := ExprRec^.ArgList[I]^.ExprWord.ResultType;
      // check if we need to copy argument, variables in general do not
      // need copying, except for fixed len strings which are not
      // null-terminated
//      if ExprRec^.ArgList[I].ExprWord.NeedsCopy then
//      begin
        // get memory for argument
        GetMem(ExprRec^.Args[I], ArgAllocSize);
        ExprRec^.ArgsPos[I] := ExprRec^.Args[I];
        ExprRec^.ArgsSize[I] := ArgAllocSize;
        MakeLinkedList(ExprRec^.ArgList[I], @ExprRec^.Args[I], @ExprRec^.ArgsPos[I],
            @ExprRec^.ArgsSize[I]);
//      end else begin
        // copy reference
//        ExprRec^.Args[I] := ExprRec^.ArgList[I].Args[0];
//        ExprRec^.ArgsPos[I] := ExprRec^.Args[I];
//        ExprRec^.ArgsSize[I] := 0;
//        FreeMem(ExprRec^.ArgList[I]);
//        ExprRec^.ArgList[I] := nil;
//      end;

      // goto next argument
      Inc(I);
    end;

    // link result to target argument
    ExprRec^.Res := TDynamicType.Create(Memory, MemoryPos, MemSize);
  end; // 08/04/2011 pb  CR 19339

    // link to next operation
    if FCurrentRec = nil then
    begin
      FCurrentRec := ExprRec;
      FLastRec := ExprRec;
    end else begin
      FLastRec^.Next := ExprRec;
      FLastRec := ExprRec;
    end;
//end;
end;

function TCustomExpressionParser.MakeTree(Expr: TExprCollection; 
  FirstItem, LastItem: Integer): PExpressionRec;

{
- This is the most complex routine, it breaks down the expression and makes
  a linked tree which is used for fast function evaluations
- it is implemented recursively
}

var
  I, IArg, IStart, IEnd, lPrec, brCount: Integer;
  ExprWord: TExprWord;
begin
  // remove redundant brackets
  brCount := 0;
  while (FirstItem+brCount < LastItem) and (TExprWord(
      Expr.Items[FirstItem+brCount]).ResultType = etLeftBracket) do
    Inc(brCount);
  I := LastItem;
  while (I > FirstItem) and (TExprWord(
      Expr.Items[I]).ResultType = etRightBracket) do
    Dec(I);
  // test max of start and ending brackets
  if brCount > (LastItem-I) then
    brCount := LastItem-I;
  // count number of bracket pairs completely open from start to end
  // IArg is min.brCount
  I := FirstItem + brCount;
  IArg := brCount;
  while (I <= LastItem - brCount) and (brCount > 0) do
  begin
    case TExprWord(Expr.Items[I]).ResultType of
      etLeftBracket: Inc(brCount);
      etRightBracket: 
        begin
          Dec(brCount);
          if brCount < IArg then
            IArg := brCount;
        end;
    end;
    Inc(I);
  end;
  // useful pair bracket count, is in minimum, is IArg
  brCount := IArg;
  // check if subexpression closed within (bracket level will be zero)
  if brCount > 0 then
  begin
    Inc(FirstItem, brCount);
    Dec(LastItem, brCount);
  end;

  // check for empty range
  if LastItem < FirstItem then
  begin
    Result := nil;
    exit;
  end;

  // get new record
  Result := MakeRec;

  // simple constant, variable or function?
  if LastItem = FirstItem then
  begin
    Result^.ExprWord := TExprWord(Expr.Items[FirstItem]);
    Result^.Oper := Result^.ExprWord.ExprFunc;
    exit;
  end;

  // no...more complex, find operator with lowest precedence
  brCount := 0;
  IArg := 0;
  IEnd := FirstItem-1;
  lPrec := -1;
  for I := FirstItem to LastItem do
  begin
    ExprWord := TExprWord(Expr.Items[I]);
//  if (brCount = 0) and ExprWord.IsOperator and (TFunction(ExprWord).OperPrec > lPrec) then
    if (brCount = 0) and ExprWord.IsOperator and (TFunction(ExprWord).OperPrec >= lPrec) then // 04/13/2011 pb  CR 18908
    begin
      IEnd := I;
      lPrec := TFunction(ExprWord).OperPrec;
    end;
    case ExprWord.ResultType of
      etLeftBracket: Inc(brCount);
      etRightBracket: Dec(brCount);
    end;
  end;

  // operator found ?
  if IEnd >= FirstItem then
  begin
    // save operator
    Result^.ExprWord := TExprWord(Expr.Items[IEnd]);
    Result^.Oper := Result^.ExprWord.ExprFunc;
    // recurse into left part if present
    if IEnd > FirstItem then
    begin
      Result^.ArgList[IArg] := MakeTree(Expr, FirstItem, IEnd-1);
      Inc(IArg);
    end;
    // recurse into right part if present
    if IEnd < LastItem then
      Result^.ArgList[IArg] := MakeTree(Expr, IEnd+1, LastItem);
  end else 
  if TExprWord(Expr.Items[FirstItem]).IsFunction then 
  begin
    // save function
    Result^.ExprWord := TExprWord(Expr.Items[FirstItem]);
    Result^.Oper := Result^.ExprWord.ExprFunc;
    Result^.WantsFunction := true;
    // parse function arguments
    IEnd := FirstItem + 1;
    IStart := IEnd;
    brCount := 0;
    if TExprWord(Expr.Items[IEnd]).ResultType = etLeftBracket then
    begin
      // opening bracket found, first argument expression starts at next index
      Inc(brCount);
      Inc(IStart);
      while (IEnd < LastItem) and (brCount <> 0) do
      begin
        Inc(IEnd);
        case TExprWord(Expr.Items[IEnd]).ResultType of
          etLeftBracket: Inc(brCount);
          etComma:
            if brCount = 1 then
            begin
              // argument separation found, build tree of argument expression
              Result^.ArgList[IArg] := MakeTree(Expr, IStart, IEnd-1);
              Inc(IArg);
              IStart := IEnd + 1;
            end;
          etRightBracket: Dec(brCount);
        end;
      end;

      // parse last argument
      Result^.ArgList[IArg] := MakeTree(Expr, IStart, IEnd-1);
    end;
  end else
    raise EParserException.Create('Operator/function missing');
end;

procedure TCustomExpressionParser.ParseString(AnExpression: string; DestCollection: TExprCollection);
var
  isConstant: Boolean;
  I, I1, I2, Len, DecSep: Integer;
  W, S: string;
  TempWord: TExprWord;

  procedure ReadConstant(AnExpr: string; isHex: Boolean);
  begin
    isConstant := true;
    while (I2 <= Len) and ((AnExpr[I2] in ['0'..'9']) or
      (isHex and (AnExpr[I2] in ['a'..'f', 'A'..'F']))) do
      Inc(I2);
    if I2 <= Len then
    begin
      if AnExpr[I2] = FDecimalSeparator then
      begin
        Inc(I2);
        while (I2 <= Len) and (AnExpr[I2] in ['0'..'9']) do
          Inc(I2);
      end;
      if (I2 <= Len) and (AnExpr[I2] = 'e') then
      begin
        Inc(I2);
        if (I2 <= Len) and (AnExpr[I2] in ['+', '-']) then
          Inc(I2);
        while (I2 <= Len) and (AnExpr[I2] in ['0'..'9']) do
          Inc(I2);
      end;
    end;
  end;

  procedure ReadWord(AnExpr: string);
  var
    OldI2: Integer;
    constChar: Char;
  begin
    isConstant := false;
    I1 := I2;
    while (I1 < Len) and (AnExpr[I1] = ' ') do
      Inc(I1);
    I2 := I1;
    if I1 <= Len then
    begin
      if AnExpr[I2] = HexChar then
      begin
        Inc(I2);
        OldI2 := I2;
        ReadConstant(AnExpr, true);
        if I2 = OldI2 then
        begin
          isConstant := false;
          while (I2 <= Len) and (AnExpr[I2] in ['a'..'z', 'A'..'Z', '_', '0'..'9']) do
            Inc(I2);
        end;
      end
      else if AnExpr[I2] = FDecimalSeparator then
        ReadConstant(AnExpr, false)
      else
        case AnExpr[I2] of
          '''', '"':
            begin
              isConstant := true;
              constChar := AnExpr[I2];
              Inc(I2);
              while (I2 <= Len) and (AnExpr[I2] <> constChar) do
                Inc(I2);
              if I2 <= Len then
                Inc(I2);
            end;
          'a'..'z', 'A'..'Z', '_':
            begin
              while (I2 <= Len) and (AnExpr[I2] in ['a'..'z', 'A'..'Z', '_', '0'..'9']) do
                Inc(I2);
            end;
          '>', '<':
            begin
              if (I2 <= Len) then
                Inc(I2);
              if AnExpr[I2] in ['=', '<', '>'] then
                Inc(I2);
            end;
          '=':
            begin
              if (I2 <= Len) then
                Inc(I2);
              if AnExpr[I2] in ['<', '>', '='] then
                Inc(I2);
            end;
          '&':
            begin
              if (I2 <= Len) then
                Inc(I2);
              if AnExpr[I2] in ['&'] then
                Inc(I2);
            end;
          '|':
            begin
              if (I2 <= Len) then
                Inc(I2);
              if AnExpr[I2] in ['|'] then
                Inc(I2);
            end;
          ':':
            begin
              if (I2 <= Len) then
                Inc(I2);
              if AnExpr[I2] = '=' then
                Inc(I2);
            end;
          '!':
            begin
              if (I2 <= Len) then
                Inc(I2);
              if AnExpr[I2] = '=' then //support for !=
                Inc(I2);
            end;
          '+':
            begin
              Inc(I2);
              if (AnExpr[I2] = '+') and FWordsList.Search(PChar('++'), I) then
                Inc(I2);
            end;
          '-':
            begin
              Inc(I2);
              if (AnExpr[I2] = '-') and FWordsList.Search(PChar('--'), I) then
                Inc(I2);
            end;
          '^', '/', '\', '*', '(', ')', '%', '~', '$':
            Inc(I2);
          '0'..'9':
            ReadConstant(AnExpr, false);
        else
          begin
            Inc(I2);
          end;
        end;
    end;
  end;

begin
  I2 := 1;
  S := Trim(AnExpression);
  Len := Length(S);
  repeat
    ReadWord(S);
    W := Trim(Copy(S, I1, I2 - I1));
    if isConstant then
    begin
      if W[1] = HexChar then
      begin
        // convert hexadecimal to decimal
        W[1] := '$';
        W := IntToStr(StrToInt(W));
      end;
      if (W[1] = '''') or (W[1] = '"') then
        TempWord := TStringConstant.Create(W)
      else begin
        DecSep := Pos(FDecimalSeparator, W);
        if (DecSep > 0) then
        begin
{$IFDEF ENG_NUMBERS}
          // we'll have to convert FDecimalSeparator into DecimalSeparator
          // otherwise the OS will not understand what we mean
          W[DecSep] := DecimalSeparator;
{$ENDIF}
          TempWord := TFloatConstant.Create(W, W)
        end else begin
          TempWord := TIntegerConstant.Create(StrToInt(W));
        end;
      end;
      DestCollection.Add(TempWord);
      FConstantsList.Add(TempWord);
    end
    else if Length(W) > 0 then
      if FWordsList.Search(PChar(W), I) then
      begin
        DestCollection.Add(FWordsList.Items[I])
      end else begin
        // unknown variable -> fire event
        HandleUnknownVariable(W);
        // try to search again
        if FWordsList.Search(PChar(W), I) then
        begin
          DestCollection.Add(FWordsList.Items[I])
        end else begin
          raise EParserException.Create('Unknown variable '''+W+''' found.');
        end;
      end;
  until I2 > Len;
end;

procedure TCustomExpressionParser.Check(AnExprList: TExprCollection);
var
  I, J, K, L: Integer;
begin
  AnExprList.Check;
  with AnExprList do
  begin
    I := 0;
    while I < Count do
    begin
      {----CHECK ON DOUBLE MINUS OR DOUBLE PLUS----}
      if ((TExprWord(Items[I]).Name = '-') or
        (TExprWord(Items[I]).Name = '+'))
        and ((I = 0) or
        (TExprWord(Items[I - 1]).ResultType = etComma) or
        (TExprWord(Items[I - 1]).ResultType = etLeftBracket) or
        (TExprWord(Items[I - 1]).IsOperator and (TExprWord(Items[I - 1]).MaxFunctionArg
        = 2))) then
      begin
        {replace e.g. ----1 with +1}
        if TExprWord(Items[I]).Name = '-' then
          K := -1
        else
          K := 1;
        L := 1;
        while (I + L < Count) and ((TExprWord(Items[I + L]).Name = '-')
          or (TExprWord(Items[I + L]).Name = '+')) and ((I + L = 0) or
          (TExprWord(Items[I + L - 1]).ResultType = etComma) or
          (TExprWord(Items[I + L - 1]).ResultType = etLeftBracket) or
          (TExprWord(Items[I + L - 1]).IsOperator and (TExprWord(Items[I + L -
          1]).MaxFunctionArg = 2))) do
        begin
          if TExprWord(Items[I + L]).Name = '-' then
            K := -1 * K;
          Inc(L);
        end;
        if L > 0 then
        begin
          Dec(L);
          for J := I + 1 to Count - 1 - L do
            Items[J] := Items[J + L];
          Count := Count - L;
        end;
        if K = -1 then
        begin
          if FWordsList.Search(pchar('-@'), J) then
            Items[I] := FWordsList.Items[J];
        end
        else if FWordsList.Search(pchar('+@'), J) then
          Items[I] := FWordsList.Items[J];
      end;
      {----CHECK ON DOUBLE NOT----}
      if (TExprWord(Items[I]).Name = 'not')
        and ((I = 0) or
        (TExprWord(Items[I - 1]).ResultType = etLeftBracket) or
        TExprWord(Items[I - 1]).IsOperator) then
      begin
        {replace e.g. not not 1 with 1}
        K := -1;
        L := 1;
        while (I + L < Count) and (TExprWord(Items[I + L]).Name = 'not') and ((I
          + L = 0) or
          (TExprWord(Items[I + L - 1]).ResultType = etLeftBracket) or
          TExprWord(Items[I + L - 1]).IsOperator) do
        begin
          K := -K;
          Inc(L);
        end;
        if L > 0 then
        begin
          if K = 1 then
          begin //remove all
            for J := I to Count - 1 - L do
              Items[J] := Items[J + L];
            Count := Count - L;
          end
          else
          begin //keep one
            Dec(L);
            for J := I + 1 to Count - 1 - L do
              Items[J] := Items[J + L];
            Count := Count - L;
          end
        end;
      end;
      {-----MISC CHECKS-----}
      if (TExprWord(Items[I]).IsVariable) and ((I < Count - 1) and
        (TExprWord(Items[I + 1]).IsVariable)) then
        raise EParserException.Create('Missing operator between '''+TExprWord(Items[I]).Name+''' and '''+TExprWord(Items[I]).Name+'''');
      if (TExprWord(Items[I]).ResultType = etLeftBracket) and (I >= Count - 1) then
        raise EParserException.Create('Missing closing bracket');
      if (TExprWord(Items[I]).ResultType = etRightBracket) and ((I < Count - 1) and
        (TExprWord(Items[I + 1]).ResultType = etLeftBracket)) then
        raise EParserException.Create('Missing operator between )(');
      if (TExprWord(Items[I]).ResultType = etRightBracket) and ((I < Count - 1) and
        (TExprWord(Items[I + 1]).IsVariable)) then
        raise EParserException.Create('Missing operator between ) and constant/variable');
      if (TExprWord(Items[I]).ResultType = etLeftBracket) and ((I > 0) and
        (TExprWord(Items[I - 1]).IsVariable)) then
        raise EParserException.Create('Missing operator between constant/variable and (');

      {-----CHECK ON INTPOWER------}
      if (TExprWord(Items[I]).Name = '^') and ((I < Count - 1) and
          (TExprWord(Items[I + 1]).ClassType = TIntegerConstant)) then
        if FWordsList.Search(PChar('^@'), J) then
          Items[I] := FWordsList.Items[J]; //use the faster intPower if possible
      Inc(I);
    end;
  end;
end;

procedure TCustomExpressionParser.EvaluateCurrent;
var
  TempRec: PExpressionRec;
begin
  if FCurrentRec <> nil then
  begin
    // get current record
    TempRec := FCurrentRec;
    // execute list
    repeat
      with TempRec^ do
      begin
        if Assigned(@Oper) then // 08/04/2011 pb  CR 19339
        begin
          // do we need to reset pointer?
          if ResetDest then
//          Res.MemoryPos^ := Res.Memory^;
            Res.Rewind; // 04/27/2011 pb  CR 18890

          IsNull := False; // 04/11/2011 pb  CR 18908
          Oper(TempRec);
        end;

        // goto next
        TempRec := Next;
      end;
    until TempRec = nil;
  end;
end;

function TCustomExpressionParser.DefineFunction(AFunctName, AShortName, ADescription, ATypeSpec: string;
  AMinFunctionArg: Integer; AResultType: TExpressionType; AFuncAddress: TExprFunc): TExprWord;
begin
  Result := TFunction.Create(AFunctName, AShortName, ATypeSpec, AMinFunctionArg, AResultType, AFuncAddress, ADescription);
  FWordsList.Add(Result);
end;

//function TCustomExpressionParser.DefineIntegerVariable(AVarName: string; AValue: PInteger): TExprWord;
function TCustomExpressionParser.DefineIntegerVariable(AVarName: string; AValue: PInteger; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo): TExprWord; // 04/11/2011 pb  CR 18908
begin
//Result := TIntegerVariable.Create(AVarName, AValue);
  Result := TIntegerVariable.Create(AVarName, AValue, AIsNullPtr, AFieldInfo); // 04/11/2011 pb  CR 18908
  FWordsList.Add(Result);
end;

{$ifdef SUPPORT_INT64}

//function TCustomExpressionParser.DefineLargeIntVariable(AVarName: string; AValue: PLargeInt): TExprWord;
function TCustomExpressionParser.DefineLargeIntVariable(AVarName: string; AValue: PLargeInt; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo): TExprWord; // 04/11/2011 pb  CR 18908
begin
//  Result := TLargeIntVariable.Create(AVarName, AValue);
  Result := TLargeIntVariable.Create(AVarName, AValue, AIsNullPtr, AFieldInfo); // 04/11/2011 pb  CR 18908
  FWordsList.Add(Result);
end;

{$endif}

//function TCustomExpressionParser.DefineDateTimeVariable(AVarName: string; AValue: PDateTimeRec): TExprWord;
function TCustomExpressionParser.DefineDateTimeVariable(AVarName: string; AValue: PDateTimeRec; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo): TExprWord; // 04/11/2011 pb  CR 18908
begin
//Result := TDateTimeVariable.Create(AVarName, AValue);
  Result := TDateTimeVariable.Create(AVarName, AValue, AIsNullPtr, AFieldInfo); // 04/11/2011 pb  CR 18908
  FWordsList.Add(Result);
end;

//function TCustomExpressionParser.DefineBooleanVariable(AVarName: string; AValue: PBoolean): TExprWord;
function TCustomExpressionParser.DefineBooleanVariable(AVarName: string; AValue: PBoolean; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo): TExprWord; // 04/11/2011 pb  CR 18908
begin
  Result := TBooleanVariable.Create(AVarName, AValue, AIsNullPtr, AFieldInfo); // 04/11/2011 pb  CR 18908
  FWordsList.Add(Result);
end;

//function TCustomExpressionParser.DefineFloatVariable(AVarName: string; AValue: PDouble): TExprWord;
function TCustomExpressionParser.DefineFloatVariable(AVarName: string; AValue: PDouble; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo): TExprWord; // 04/11/2011 pb  CR 18908
begin
//Result := TFloatVariable.Create(AVarName, AValue);
  Result := TFloatVariable.Create(AVarName, AValue, AIsNullPtr, AFieldInfo); // 04/11/2011 pb  CR 18908
  FWordsList.Add(Result);
end;

//function TCustomExpressionParser.DefineStringVariable(AVarName: string; AValue: PPChar): TExprWord;
function TCustomExpressionParser.DefineStringVariable(AVarName: string; AValue: PPChar; AIsNullPtr: PBoolean; AFieldInfo: PVariableFieldInfo): TExprWord; // 04/11/2011 pb  CR 18908
begin
//  Result := TStringVariable.Create(AVarName, AValue);
  Result := TStringVariable.Create(AVarName, AValue, AIsNullPtr, AFieldInfo); // 04/11/2011 pb  CR 18908
  FWordsList.Add(Result);
end;

{
procedure TCustomExpressionParser.GetGeneratedVars(AList: TList);
var
  I: Integer;
begin
  AList.Clear;
  with FWordsList do
    for I := 0 to Count - 1 do
    begin
      if TObject(Items[I]).ClassType = TGeneratedVariable then
        AList.Add(Items[I]);
    end;
end;
}

function TCustomExpressionParser.GetResultType: TExpressionType;
begin
  Result := etUnknown;
  if FCurrentRec <> nil then
  begin
    //LAST operand should be boolean -otherwise If(,,) doesn't work
    while (FLastRec^.Next <> nil) do
      FLastRec := FLastRec^.Next;
    if FLastRec^.ExprWord <> nil then
      Result := FLastRec^.ExprWord.ResultType;
  end;
end;

function TCustomExpressionParser.IsIndex: Boolean; // 04/11/2011 pb  CR 18908
begin
  Result := False;
end;

procedure TCustomExpressionParser.OptimizeExpr(var ExprRec: PExpressionRec); // 04/15/2011 pb  CR 18893
begin
  RemoveConstants(ExprRec);
end;

function TCustomExpressionParser.MakeRec: PExpressionRec;
var
  I: Integer;
begin
  New(Result);
  Result^.Oper := nil;
  Result^.AuxData := nil;
  Result^.WantsFunction := false;
  for I := 0 to MaxArg - 1 do
  begin
    Result^.Args[I] := nil;
    Result^.ArgsPos[I] := nil;
    Result^.ArgsSize[I] := 0;
    Result^.ArgsType[I] := etUnknown;
    Result^.ArgList[I] := nil;
  end;
  Result^.Res := nil;
  Result^.Next := nil;
  Result^.ExprWord := nil;
  Result^.ResetDest := false;
  Result^.ExpressionContext := @FExpressionContext; // 04/27/2011 pb  CR 18959
end;

procedure TCustomExpressionParser.Evaluate(AnExpression: string);
begin
  if Length(AnExpression) > 0 then
  begin
    AddExpression(AnExpression);
    EvaluateCurrent;
  end;
end;

function TCustomExpressionParser.AddExpression(AnExpression: string): Integer;
begin
  if Length(AnExpression) > 0 then
  begin
    Result := 0;
    CompileExpression(AnExpression);
  end else
    Result := -1;
  //CurrentIndex := Result;
end;

procedure TCustomExpressionParser.ClearExpressions;
begin
  DisposeList(FCurrentRec);
  FCurrentRec := nil;
  FLastRec := nil;
end;

function TCustomExpressionParser.GetFunctionDescription(AFunction: string):
  string;
var
  S: string;
  p, I: Integer;
begin
  S := AFunction;
  p := Pos('(', S);
  if p > 0 then
    S := Copy(S, 1, p - 1);
  if FWordsList.Search(pchar(S), I) then
    Result := TExprWord(FWordsList.Items[I]).Description
  else
    Result := EmptyStr;
end;

procedure TCustomExpressionParser.GetFunctionNames(AList: TStrings);
var
  I, J: Integer;
  S: string;
begin
  with FWordsList do
    for I := 0 to Count - 1 do
      with TExprWord(FWordsList.Items[I]) do
        if Length(Description) > 0 then
        begin
          S := Name;
          if MaxFunctionArg > 0 then
          begin
            S := S + '(';
            for J := 0 to MaxFunctionArg - 2 do
              S := S + ArgSeparator;
            S := S + ')';
          end;
          AList.Add(S);
        end;
end;


//--Expression functions-----------------------------------------------------

(*
procedure FuncFloatToStr(Param: PExpressionRec);
var
  width, numDigits, resWidth: Integer;
  extVal: Extended;
begin
  with Param^ do
  begin
    // get params;
    numDigits := 0;
    if Args[1] <> nil then
      width := PInteger(Args[1])^
    else
      width := 18;
    if Args[2] <> nil then
      numDigits := PInteger(Args[2])^;
    // convert to string
    Res.AssureSpace(width);
    extVal := PDouble(Args[0])^;
    resWidth := FloatToText(Res.MemoryPos^, extVal, {$ifndef FPC_VERSION}fvExtended,{$endif} ffFixed, 18, numDigits);
    // always use dot as decimal separator
    if numDigits > 0 then
      Res.MemoryPos^[resWidth-numDigits-1] := '.';
    // result width smaller than requested width? -> add space to compensate
    if (Args[1] <> nil) and (resWidth < width) then
    begin
      // move string so that it's right-aligned
      Move(Res.MemoryPos^^, (Res.MemoryPos^)[width-resWidth], resWidth);
      // fill gap with spaces
      FillChar(Res.MemoryPos^^, width-resWidth, ' ');
      // resWidth has been padded, update
      resWidth := width;
    end else if resWidth > width then begin
      // result width more than requested width, cut
      resWidth := width;
    end;
    // advance pointer
    Inc(Res.MemoryPos^, resWidth);
    // null-terminate
    Res.MemoryPos^^ := #0;
  end;
end;

procedure FuncIntToStr_Gen(Param: PExpressionRec; Val: {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif});
var
  width: Integer;
begin
  with Param^ do
  begin
    // width specified?
    if Args[1] <> nil then
    begin
      // convert to string
      width := PInteger(Args[1])^;
{$ifdef SUPPORT_INT64}
      GetStrFromInt64_Width
{$else}
      GetStrFromInt_Width
{$endif}
        (Val, width, Res.MemoryPos^, #32);
      // advance pointer
      Inc(Res.MemoryPos^, width);
      // need to add decimal?
      if Args[2] <> nil then
      begin
        // get number of digits
        width := PInteger(Args[2])^;
        // add decimal dot
        Res.MemoryPos^^ := '.';
        Inc(Res.MemoryPos^);
        // add zeroes
        FillChar(Res.MemoryPos^^, width, '0');
        // go to end
        Inc(Res.MemoryPos^, width);
      end;
    end else begin
      // convert to string
      width := 
{$ifdef SUPPORT_INT64}
        GetStrFromInt64
{$else}
        GetStrFromInt
{$endif}
          (Val, Res.MemoryPos^);
      // advance pointer
      Inc(Param^.Res.MemoryPos^, width);
    end;
    // null-terminate
    Res.MemoryPos^^ := #0;
  end;
end;

procedure FuncIntToStr(Param: PExpressionRec);
begin
  FuncIntToStr_Gen(Param, PInteger(Param^.Args[0])^);
end;

{$ifdef SUPPORT_INT64}

procedure FuncInt64ToStr(Param: PExpressionRec);
begin
  FuncIntToStr_Gen(Param, PInt64(Param^.Args[0])^);
end;

{$endif}
*)

procedure FuncStr(Param: PExpressionRec); // 05/05/2011 pb  CR 18984
var
  Size: Integer;
  Precision: Integer;
  PadChar: Char;
{$ifdef SUPPORT_INT64}
  IntValue: Int64;
{$else}
  IntValue: Integer;
{$endif}
  FloatValue: Extended;
  Len: Integer;
begin
  if Param^.Args[1] <> nil then
    Size := PInteger(Param^.Args[1])^
  else
  begin
    case Param^.ArgsType[0] of
      etInteger: Size := 11;
      etLargeInt: Size := 20;
    else
      Size := 10;
    end;
  end;
  if Param^.Args[2] <> nil then
    Precision := PInteger(Param^.Args[2])^
  else
    Precision := 0;
  if Param^.Args[3] <> nil then
    PadChar := Param^.Args[0]^
  else
    PadChar := #0;
  if PadChar = #0 then
    PadChar := ' ';
  Param^.Res.AssureSpace(Succ(Size));
  if (Precision = 0) and (Param^.ArgsType[0] in [etInteger, etLargeInt]) then
  begin
{$ifdef SUPPORT_INT64}
    if Param^.ArgsType[0] = etLargeInt then
      IntValue := PInt64(Param^.Args[0])^
    else
{$endif}
      IntValue := PInteger(Param^.Args[0])^;
    Len := IntToStrWidth(IntValue, Size, Param^.Res.MemoryPos^, True, PadChar);
  end
  else
  begin
    FloatValue := PDouble(Param^.Args[0])^;
    Len := FloatToStrWidth(FloatValue, Size, Precision, Param^.Res.MemoryPos^, True);
  end;
  Inc(Param^.Res.MemoryPos^, Len);
  Param^.Res.MemoryPos^^ := #0;
end;

procedure FuncDateToStr(Param: PExpressionRec);
var
  TempStr: string;
begin
  with Param^ do
  begin
    // create in temporary string
    DateTimeToString(TempStr, 'yyyymmdd', PDateTimeRec(Args[0])^.DateTime);
    if ArgList[0]^.IsNullPtr^ then // 04/13/2011 pb  CR 18922
      FillChar(pChar(TempStr)^, Length(TempStr), ' '); // 04/13/2011 pb  CR 18922
    // copy to buffer
    Res.Append(PChar(TempStr), Length(TempStr));
  end;
end;

procedure FuncSubString(Param: PExpressionRec);
var
  srcLen, index, count: Integer;
begin
  with Param^ do
  begin
    srcLen := StrLen(Args[0]);
    index := PInteger(Args[1])^ - 1;
    if Args[2] <> nil then
    begin
      count := PInteger(Args[2])^;
      if index + count > srcLen then
        count := srcLen - index;
    end else
      count := srcLen - index;
    Res.Append(Args[0]+index, count)
  end;
end;

procedure FuncAbs_I_I(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  anInteger: integer;
begin
  with Param^ do
  begin
    anInteger := Abs(PInteger(Args[0])^);
    PInteger(Res.MemoryPos^)^ := anInteger;
  end;
end;

procedure FuncAbs_F_F(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  aDouble: Double;
begin
  with Param^ do
  begin
    aDouble := Abs(PDouble(Args[0])^);
    PDouble(Res.MemoryPos^)^ := aDouble;
  end;
end;

{$ifdef SUPPORT_INT64}
procedure FuncAbs_F_L(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  aDouble: Double;
begin
  with Param^ do
  begin
    aDouble := Abs(PLargeInt(Args[0])^);
    PDouble(Res.MemoryPos^)^ := aDouble;
  end;
end;
{$endif}

(*
procedure FuncAsc(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  TempStr: string;
begin
  with Param^ do
    begin
      TempStr := Args[0];
      if Length(TempStr) > 0 then
        PInteger(Res.MemoryPos^)^ := Ord(TempStr[1]);
    end;
end;
*)

procedure FuncAsc(Param: PExpressionRec); // 04/28/2011 pb  CR 18536
begin
  if ExprStrLen(Param^.Args[0], False) > 0 then
    PInteger(Param^.Res.MemoryPos^)^ := Ord(Param^.Args[0]^);
end;

procedure FuncAt(Param: PexpressionRec); // 01/27/2011 dhd CR 18536
begin
 with Param^ do
   PInteger(Res.MemoryPos^)^ := Pos(Args[0], Args[1]);
end;


procedure FuncCDOW(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  aDate: TDateTime;
  temp: string;
begin
  with Param^ do
  begin
    aDate := PDateTimeRec(Args[0])^.DateTime;
    if aDate <> BAD_DATE then
      temp := ShortDayNames[Sysutils.DayOfWeek(aDate)]
    else
      temp := '   ';

    Res.Append(pchar(temp), Length(temp));
  end;
end;

procedure FuncCeil_I_F (Param: PExpressionRec);  // 03/23/2011 dhd CR 18536
begin
  with Param^ do
  begin
    PInteger(Res.MemoryPos^)^ := Ceil(PDouble(Args[0])^);
  end;
end;

procedure FuncCeil_F_F (Param: PExpressionRec);  // 03/23/2011 dhd CR 18536
begin
  with Param^ do
  begin
    PDouble(Res.MemoryPos^)^ := Ceil(PDouble(Args[0])^);
  end;
end;

(*
procedure FuncChr(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  n: integer;
begin
  with Param^ do
  begin
    n := PInteger(Args[0])^;
    if (n >= 0) and (n <= 255) then
      Res.Append(pchar(Chr(n)), 1);
  end;
end;
*)

procedure FuncChr(Param: PExpressionRec); // 05/05/2011 pb  CR 18536
var
  IntValue: Integer;
begin
  if Param^.ExpressionContext.Validating then
    IntValue:= Ord(' ')
  else
    IntValue := PInteger(Param^.Args[0])^;
  if (IntValue >= Low(Byte)) and (IntValue <= High(Byte)) then
    Param^.Res.Append(@IntValue, SizeOf(Byte));
end;

procedure FuncDate(Param: PExpressionRec);  // 03/23/2011 dhd CR 18536
begin
  with Param^ do
    PDateTime(Res.MemoryPos^)^ := Now;
end;

procedure FuncRecNo(Param: PExpressionRec); // 04/15/2011 pb  CR 18893
begin
  PInteger(Param^.Res.MemoryPos^)^ := -1;
end;

procedure FuncDay(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  aDate: TDateTime;
  Year, Month, Day: word;
begin
  with Param^ do
  begin
    aDate := PDateTimeRec(Args[0])^.DateTime;
    if aDate <> BAD_DATE then
      begin
        DecodeDate(aDate, Year, Month, Day);
        PInteger(Res.MemoryPos^)^ := Day;
      end
    else
      PInteger(Res.MemoryPos^)^ := 0;
  end;
end;

(*
procedure FuncEmpty(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  src: pchar;
begin
  with Param^ do
  begin
    Src := Args[0];
    while Src^ <> #0 do
      begin
        if Src^ <> ' ' then
          begin
            PBoolean(Res.MemoryPos^)^ := false;
            exit;
          end;
        Inc(Src);
      end;
    PBoolean(Res.MemoryPos^)^ := true;
  end;
end;
*)

procedure FuncEmpty(Param: PExpressionRec); // 04/28/2011 pb  CR 18536
begin
  case Param^.ArgsType[0] of
    etDateTime: PBoolean(Param^.Res.MemoryPos^)^ := PDateTime(Param^.Args[0])^ = 0;
    etFloat: PBoolean(Param^.Res.MemoryPos^)^ := PDouble(Param^.Args[0])^ = 0;
    etInteger: PBoolean(Param^.Res.MemoryPos^)^ := PInteger(Param^.Args[0])^ = 0;
{$ifdef SUPPORT_INT64}
    etLargeInt: PBoolean(Param^.Res.MemoryPos^)^ := PLargeInt(Param^.Args[0])^ = 0;
{$endif}
    etString: PBoolean(Param^.Res.MemoryPos^)^ := ExprStrLen(Param^.Args[0], False) = 0;
  end;
end;

// S = IIF(B, S1, S2)
procedure FuncIIF_S_SS(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  cond: boolean;
begin
  with Param^ do
  begin
    cond := PBoolean(Args[0])^;
    if cond then
      Res.Append(Args[1], StrLen(Args[1]))
    else
      Res.Append(Args[2], StrLen(Args[2]));
  end;
end;

// F = IIF(B, F1, F2)
procedure FuncIIF_F_FF   (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  cond: boolean;
begin
  with Param^ do
  begin
    cond := PBoolean(Args[0])^;
    if cond then
      PDouble(Res.MemoryPos^)^ := PDouble(Args[1])^
    else
      PDouble(Res.MemoryPos^)^ := PDouble(Args[2])^;
  end;
end;

// I = IIF(B, I1, I2)
procedure FuncIIF_I_II   (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  cond: boolean;
begin
  with Param^ do
  begin
    cond := PBoolean(Args[0])^;
    if cond then
      PInteger(Res.MemoryPos^)^ := PInteger(Args[1])^
    else
      PInteger(Res.MemoryPos^)^ := PInteger(Args[2])^;
  end;
end;

procedure FuncLeft(Param: PExpressionRec);  // 01/27/2011 dhd CR 18536
var
  srcLen, count: Integer;
begin
  with Param^ do
  begin
    srcLen := StrLen(Args[0]);
    count  := PInteger(Args[1])^;
    if count > srcLen then
      count := srcLen;
    if count > 0 then // 04/28/2011 pb  CR 18536
      Res.Append(Args[0], count);
  end;
end;

procedure FuncLen_F_S  (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  srcLen: integer;
begin
  with Param^ do
  begin
    srcLen := StrLen(Args[0]);
    PDouble(Res.MemoryPos^)^ := srcLen;
  end;
end;

{$ifdef SUPPORT_INT64}
procedure FuncLen_L_S  (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  srcLen: integer;
begin
  with Param^ do
  begin
    srcLen := StrLen(Args[0]);
    PLargeInt(Res.MemoryPos^)^ := srcLen;
  end;
end;
{$endif}

procedure FuncLen_I_S  (Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  srcLen: integer;
begin
  with Param^ do
  begin
    srcLen := StrLen(Args[0]);
    PInteger(Res.MemoryPos^)^ := srcLen;
  end;
end;

procedure FuncMonth(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  aDate: TDateTime;
  Year, Month, Day: word;
begin
  with Param^ do
  begin
    aDate := PDateTimeRec(Args[0])^.DateTime;
    if aDate <> BAD_DATE then
      begin
        DecodeDate(aDate, Year, Month, Day);
        PInteger(Res.MemoryPos^)^ := Month;
      end
    else
      PInteger(Res.MemoryPos^)^ := 0;
  end;
end;

procedure FuncRight(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  srcLen, count, OffSet: Integer;
begin
  with Param^ do
  begin
    srcLen := StrLen(Args[0]);
    count  := PInteger(Args[1])^;
    if count > srcLen then
      count := srcLen;
    OffSet := srcLen - count;
    if count > 0 then // 04/28/2011 pb  CR 18536
      Res.Append(Args[0]+Offset, count);
  end;
end;

(*
procedure FuncVal_I(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  n: integer;
begin
  with Param^ do
    begin
      try
        n := StrToInt(Trim(Args[0]));
      except
        n := 0;
      end;
      PInteger(Res.MemoryPos^)^ := n;
    end;
end;

procedure FuncVal_L(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  n: LargeInt;
begin
  with Param^ do
    begin
      try
        n := StrToInt(Trim(Args[0]));
      except
        n := 0;
      end;
      PLargeInt(Res.MemoryPos^)^ := n;
    end;
end;

procedure FuncVal_F(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  d: double;
begin
  with Param^ do
    begin
      try
        d := StrToFloat(Trim(Args[0]));
      except
        d := 0.0;
      end;
      PDouble(Res.MemoryPos^)^ := d;
    end;
end;
*)

procedure FuncVal(Param: PExpressionRec); // 04/28/2011 pb  CR 18536
var
  Index: Integer;
  TempStr: string;
  Code: Integer;
begin
  TempStr := TrimLeft(Param^.Args[0]);
  Index := 0;
{$BOOLEVAL OFF}
  while (Index<Length(TempStr)) and (TempStr[Succ(Index)] in [DBF_ZERO..DBF_NINE, DBF_POSITIVESIGN, DBF_NEGATIVESIGN, DBF_DECIMAL]) do
    Inc(Index);
{$BOOLEVAL ON}
  SetLength(TempStr, Index);
  case Param^.ExprWord.ResultType of
    etFloat: Val(TempStr, PDouble(Param^.Res.MemoryPos^)^, Code);
    etInteger: Val(TempStr, PInteger(Param^.Res.MemoryPos^)^, Code);
{$ifdef SUPPORT_INT64}
    etLargeInt: Val(TempStr, PLargeInt(Param^.Res.MemoryPos^)^, Code);
{$endif}
  end;
end;

procedure FuncYear(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  aDate: TDateTime;
  Year, Month, Day: word;
begin
  with Param^ do
  begin
    aDate := PDateTimeRec(Args[0])^.DateTime;
    if aDate <> BAD_DATE then
      begin
        DecodeDate(aDate, Year, Month, Day);
        PInteger(Res.MemoryPos^)^ := Year;
      end
    else
      PInteger(Res.MemoryPos^)^ := 0;
  end;
end;

procedure FuncRound_F_FF(Param: PExpressionRec); // 03/23/2011 dhd CR 18536
var
  N: integer;
begin
  with Param^ do
  begin
    N := Trunc(PDouble(Args[1])^);
    PDouble(res.MemoryPos^)^ := RoundTo(PDouble(Args[0])^, -N);
  end;
end;

procedure FuncRound_F_FI(Param: PExpressionRec); // 03/23/2011 dhd CR 18536
var
  N: integer;
begin
  with Param^ do
  begin
    N := PInteger(Args[1])^;
    PDouble(res.MemoryPos^)^ := RoundTo(PDouble(Args[0])^, -N);
  end;
end;

{$I soundex.inc}
procedure FuncSoundex(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  src: pchar;
  Dest: string;
begin
  with Param^ do
  begin
    Src := Args[0];
    Dest := Soundex(src);
    res.Append(pchar(Dest), Length(Dest));
  end;
end;

(*
procedure FuncTrim(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  TempStr: string;
begin
  with Param^ do
  begin
    TempStr := Trim(Args[0]);
    res.Append(pchar(TempStr), Length(TempStr));
  end;
end;
*)

procedure FuncRTrim(Param: PExpressionRec); // 04/28/2011 pb  CR 18536
var
  TempStr: string;
begin
  if Param^.ExpressionContext^.Validating then
    Param^.Res.Append(Param^.Args[0], StrLen(Param^.Args[0]))
  else
  begin
    TempStr := TrimRight(Param^.Args[0]);
    Param^.Res.Append(pchar(TempStr), Length(TempStr));
  end;
end;

(*
procedure FuncLTrim(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  TempStr: string;
begin
  with Param^ do
  begin
    TempStr := TrimLeft(Args[0]);
    res.Append(pchar(TempStr), Length(TempStr));
  end;
end;
*)

procedure FuncLTrim(Param: PExpressionRec); // 04/28/2011 pb  CR 18536
var
  TempStr: string;
begin
  if Param^.ExpressionContext^.Validating then
    Param^.Res.Append(Param^.Args[0], StrLen(Param^.Args[0]))
  else
  begin
    TempStr := TrimLeft(Param^.Args[0]);
    Param^.Res.Append(PChar(TempStr), Length(TempStr));
  end;
end;

(*
procedure FuncUppercase(Param: PExpressionRec);
var
  dest: PChar;
begin
  with Param^ do
  begin
    // first copy
    dest := (Res.MemoryPos)^;
    Res.Append(Args[0], StrLen(Args[0]));
    // make uppercase
    AnsiStrUpper(dest);
  end;
end;
*)

procedure FuncUppercase(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  src: PChar;
begin
  with Param^ do
  begin
//    src  := AnsiStrUpper(Args[0]);
    src := DbfStrUpper(Param.ExpressionContext.LocaleID, Args[0]); // 04/29/2011 pb  CR 18895
    Res.Append(src, StrLen(src));
  end;
end;

(*
procedure FuncLowercase(Param: PExpressionRec);
var
  dest: PChar;
begin
  with Param^ do
  begin
    // first copy
    dest := (Res.MemoryPos)^;
    Res.Append(Args[0], StrLen(Args[0]));
    // make lowercase
    AnsiStrLower(dest);
  end;
end;
*)

procedure FuncLowercase(Param: PExpressionRec); // 01/27/2011 dhd CR 18536
var
  src: PChar;
begin
  with Param^ do
  begin
//    src  := AnsiStrLower(Args[0]);
    src := DbfStrLower(Param.ExpressionContext.LocaleID, Args[0]); // 04/29/2011 pb  CR 18895
    Res.Append(src, StrLen(src));
  end;
end;

procedure FuncProper(Param: PExpressionRec); // 04/15/2011 pb  CR 18892
var
  P: PChar;
  Len: Integer;
  Index: Integer;
  NewWord: Boolean;
  Buffer: array[0..1] of Char;
begin
  P := Param^.Args[0];
  Len := StrLen(P);
  NewWord := True;
  Buffer[1]:= #0;
  for Index:= 1 to Len do
  begin
    if P^ = ' ' then
      NewWord := True
    else
    begin
      Buffer[0] := P^;
      if NewWord then
      begin
        P^ := DbfStrUpper(Param.ExpressionContext.LocaleID, Buffer)^; // 04/29/2011 pb  CR 18895
        NewWord := False;
      end
      else
        P^ := DbfStrLower(Param.ExpressionContext.LocaleID, Buffer)^; // 04/29/2011 pb  CR 18895
    end;
    Inc(P);
  end;
  Param^.Res.Append(Param^.Args[0], Len);
end;

procedure FuncAddSub_CheckNull(Param: PExpressionRec); // 04/11/2011 pb  CR 18908
begin
  if (Param^.ArgList[0]^.IsNullPtr^) and (Param^.ArgList[1]^.IsNullPtr^) then
    Param^.IsNull := True;
end;

procedure FuncAdd_F_FF(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^ + PDouble(Args[1])^;
  FuncAddSub_CheckNull(Param); // 04/11/2011 pb  CR 18908
end;

procedure FuncAdd_F_FI(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^ + PInteger(Args[1])^;
  FuncAddSub_CheckNull(Param); // 04/11/2011 pb  CR 18908
end;

procedure FuncAdd_F_II(Param: PExpressionRec);
begin
  with Param^ do
    PInteger(Res.MemoryPos^)^ := PInteger(Args[0])^ + PInteger(Args[1])^;
  FuncAddSub_CheckNull(Param); // 04/11/2011 pb  CR 18908
end;

procedure FuncAdd_F_IF(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PInteger(Args[0])^ + PDouble(Args[1])^;
  FuncAddSub_CheckNull(Param); // 04/11/2011 pb  CR 18908
end;

{$ifdef SUPPORT_INT64}

procedure FuncAdd_F_FL(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^ + PInt64(Args[1])^;
  FuncAddSub_CheckNull(Param); // 04/11/2011 pb  CR 18908
end;

procedure FuncAdd_F_IL(Param: PExpressionRec);
begin
  with Param^ do
    PInt64(Res.MemoryPos^)^ := PInteger(Args[0])^ + PInt64(Args[1])^;
  FuncAddSub_CheckNull(Param); // 04/11/2011 pb  CR 18908
end;

procedure FuncAdd_F_LL(Param: PExpressionRec);
begin
  with Param^ do
    PInt64(Res.MemoryPos^)^ := PInt64(Args[0])^ + PInt64(Args[1])^;
  FuncAddSub_CheckNull(Param); // 04/11/2011 pb  CR 18908
end;

procedure FuncAdd_F_LF(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PInt64(Args[0])^ + PDouble(Args[1])^;
  FuncAddSub_CheckNull(Param); // 04/11/2011 pb  CR 18908
end;

procedure FuncAdd_F_LI(Param: PExpressionRec);
begin
  with Param^ do
    PInt64(Res.MemoryPos^)^ := PInt64(Args[0])^ + PInteger(Args[1])^;
  FuncAddSub_CheckNull(Param); // 04/11/2011 pb  CR 18908
end;

{$endif}

procedure FuncAdd_D_DF(Param: PExpressionRec);  // 04/08/2011 pb  CR 18908
begin
  PDateTime(Param^.Res.MemoryPos^)^ := PDateTime(Param^.Args[0])^ + PDouble(Param^.Args[1])^;
  FuncAddSub_CheckNull(Param);
end;

procedure FuncAdd_D_DI(Param: PExpressionRec);  // 04/08/2011 pb  CR 18908
begin
  PDateTime(Param^.Res.MemoryPos^)^ := PDateTime(Param^.Args[0])^ + PInteger(Param^.Args[1])^;
  FuncAddSub_CheckNull(Param);
end;

procedure FuncAdd_D_DL(Param: PExpressionRec);  // 04/08/2011 pb  CR 18908
begin
  PDateTime(Param^.Res.MemoryPos^)^ := PDateTime(Param^.Args[0])^ + PInt64(Param^.Args[1])^;
  FuncAddSub_CheckNull(Param);
end;

procedure FuncAdd_D_FD(Param: PExpressionRec);  // 04/08/2011 pb  CR 18908
begin
  PDateTime(Param^.Res.MemoryPos^)^ := PDouble(Param^.Args[0])^ + PDateTime(Param^.Args[1])^;
  FuncAddSub_CheckNull(Param);
end;

procedure FuncAdd_D_ID(Param: PExpressionRec);  // 04/08/2011 pb  CR 18908
begin
  PDateTime(Param^.Res.MemoryPos^)^ := PInteger(Param^.Args[0])^ + PDateTime(Param^.Args[1])^;
  FuncAddSub_CheckNull(Param);
end;

procedure FuncAdd_D_LD(Param: PExpressionRec);  // 04/08/2011 pb  CR 18908
begin
  PDateTime(Param^.Res.MemoryPos^)^ := PInt64(Param^.Args[0])^ + PDateTime(Param^.Args[1])^;
  FuncAddSub_CheckNull(Param);
end;

procedure FuncAddSub_S(Param: PExpressionRec; Pad: Boolean);  // 04/08/2011 pb  CR 18908
var
  ArgIndex: Integer;
  FloatValue: Extended;
  StringValue: string;
  Buffer: array[0..19] of Char;
  Len: Integer;
  ResSource: PChar;
  ResLength: Integer;
  Arg: PChar;
  ArgType: TExpressionType;
  ArgIsNull: Boolean;
  Precision: Integer;
  Variable: TVariable;
  FieldInfo: PVariableFieldInfo;
begin
  ArgIndex:= 0;
  while (ArgIndex >= 0) and (ArgIndex < MaxArg) do
  begin
    if Assigned(Param^.ArgList[ArgIndex]) then
    begin
      ResSource := nil;
      ResLength := 0;
      Len := 0;
      Arg := Param^.Args[ArgIndex];
      ArgType := Param^.ArgsType[ArgIndex];
      ArgIsNull := Param^.ArgList[ArgIndex]^.IsNullPtr^;
      if (not ArgIsNull) or Pad then // 04/27/2011 pb  CR 18959
      begin
        case ArgType of
          etString:
          begin
            ResSource := Arg;
            ResLength := ExprStrLen(Arg, Pad); // 04/27/2011 pb  CR 18959
          end;
          etFloat:
          begin
            ResSource := @Buffer;
            ResLength := 20;
            Precision := 4;
            FloatValue := PDouble(Arg)^;
            if Param^.ArgList[ArgIndex]^.ExprWord is TVariable then
            begin
              Variable := TVariable(Param^.ArgList[ArgIndex]^.ExprWord);
              FieldInfo := Variable.FieldInfo;
              if Assigned(FieldInfo) then
              begin
                case FieldInfo.NativeFieldType of
                  'F', 'N':
                  begin
                    if ((FieldInfo.Size > 0) and (FieldInfo.Size <= ResLength)) and (FieldInfo.Precision >= 0) then
                    begin
                      ResLength := FieldInfo.Size;
                      Precision := FieldInfo.Precision;
                    end;
                  end;
                end;
              end;
            end;
            if not ArgIsNull then
              Len := FloatToStrWidth(FloatValue, ResLength, Precision, ResSource, Pad);
            if not Pad then // 04/27/2011 pb  CR 18959
              ResLength := Len; // 04/27/2011 pb  CR 18959
          end;
          etInteger,
          etLargeInt:
          begin
            ResSource := @Buffer;
            ResLength := 11;
            if not ArgIsNull then
              Len:= IntToStrWidth(PInteger(Arg)^, ResLength, ResSource, Pad, ' ');
            if not Pad then
              ResLength := Len;
          end;
          etDateTime:
          begin
            ResLength := 8;
            if ArgIsNull then
              ResSource := @Buffer
            else
            begin
              StringValue := FormatDateTime('YYYYMMDD', PDateTime(Arg)^);
              Len := ResLength;
              ResSource := pChar(StringValue);
            end;
          end;
        end;
      end;
      if Assigned(ResSource) then
      begin
//      if ArgType <> etString then
        if (ArgType <> etString) and Pad then // 04/27/2011 pb  CR 18959
          FillChar(ResSource^, ResLength - Len, ' ');
        if ResLength <> 0 then // 04/27/2011 pb  CR 18959
          Param^.Res.Append(ResSource, ResLength);
      end;
      Inc(ArgIndex);
    end
    else
      ArgIndex := -1;
  end;
end;

procedure FuncAdd_S(Param: PExpressionRec);  // 04/08/2011 pb  CR 18908
begin
  FuncAddSub_S(Param, True);
end;

procedure FuncSub_D_DF(Param: PExpressionRec); // 04/27/2011 pb  CR 18959
begin
  PDateTime(Param^.Res.MemoryPos^)^ := PDateTime(Param^.Args[0])^ - PDouble(Param^.Args[1])^;
  FuncAddSub_CheckNull(Param);
end;

procedure FuncSub_D_DI(Param: PExpressionRec); // 04/27/2011 pb  CR 18959
begin
  PDateTime(Param^.Res.MemoryPos^)^ := PDateTime(Param^.Args[0])^ - PInteger(Param^.Args[1])^;
  FuncAddSub_CheckNull(Param);
end;

procedure FuncSub_F_FF(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^ - PDouble(Args[1])^;
end;

procedure FuncSub_F_FI(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^ - PInteger(Args[1])^;
end;

procedure FuncSub_F_II(Param: PExpressionRec);
begin
  with Param^ do
    PInteger(Res.MemoryPos^)^ := PInteger(Args[0])^ - PInteger(Args[1])^;
end;

procedure FuncSub_F_IF(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PInteger(Args[0])^ - PDouble(Args[1])^;
end;

procedure FuncSub_F_DD(Param: PExpressionRec); // 04/27/2011 pb  CR 18959
begin
  PDouble(Param^.Res.MemoryPos^)^ := PDateTime(Param^.Args[0])^ - PDateTime(Param^.Args[1])^;
  FuncAddSub_CheckNull(Param);
end;

{$ifdef SUPPORT_INT64}

procedure FuncSub_D_DL(Param: PExpressionRec); // 04/27/2011 pb  CR 18959
begin
  PDateTime(Param^.Res.MemoryPos^)^ := PDateTime(Param^.Args[0])^ - PLargeInt(Param^.Args[1])^;
  FuncAddSub_CheckNull(Param);
end;

procedure FuncSub_F_FL(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^ - PInt64(Args[1])^;
end;

procedure FuncSub_F_IL(Param: PExpressionRec);
begin
  with Param^ do
    PInt64(Res.MemoryPos^)^ := PInteger(Args[0])^ - PInt64(Args[1])^;
end;

procedure FuncSub_F_LL(Param: PExpressionRec);
begin
  with Param^ do
    PInt64(Res.MemoryPos^)^ := PInt64(Args[0])^ - PInt64(Args[1])^;
end;

procedure FuncSub_F_LF(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PInt64(Args[0])^ - PDouble(Args[1])^;
end;

procedure FuncSub_F_LI(Param: PExpressionRec);
begin
  with Param^ do
    PInt64(Res.MemoryPos^)^ := PInt64(Args[0])^ - PInteger(Args[1])^;
end;

{$endif}

procedure FuncSub_S(Param: PExpressionRec); // 04/27/2011 pb  CR 18959
begin
  FuncAddSub_S(Param, Param^.ExpressionContext^.Validating);
end;

procedure FuncNegate(Param: PExpressionRec); // 04/27/2011 pb  CR 18884
begin
  Param^.IsNull := Param^.ArgList[0]^.IsNullPtr^;
  case Param^.ArgsType[0] of
    etFloat: PDouble(Param^.Res.MemoryPos^)^ := -PDouble(Param^.Args[0])^;
    etInteger: PInteger(Param^.Res.MemoryPos^)^ := -PInteger(Param^.Args[0])^;
{$ifdef SUPPORT_INT64}
    etLargeInt: PLargeInt(Param^.Res.MemoryPos^)^ := -PLargeInt(Param^.Args[0])^;
{$endif}
  end;
end;

procedure FuncMul_F_FF(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^ * PDouble(Args[1])^;
end;

procedure FuncMul_F_FI(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^ * PInteger(Args[1])^;
end;

procedure FuncMul_F_II(Param: PExpressionRec);
begin
  with Param^ do
    PInteger(Res.MemoryPos^)^ := PInteger(Args[0])^ * PInteger(Args[1])^;
end;

procedure FuncMul_F_IF(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PInteger(Args[0])^ * PDouble(Args[1])^;
end;

{$ifdef SUPPORT_INT64}

procedure FuncMul_F_FL(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^ * PInt64(Args[1])^;
end;

procedure FuncMul_F_IL(Param: PExpressionRec);
begin
  with Param^ do
    PInt64(Res.MemoryPos^)^ := PInteger(Args[0])^ * PInt64(Args[1])^;
end;

procedure FuncMul_F_LL(Param: PExpressionRec);
begin
  with Param^ do
    PInt64(Res.MemoryPos^)^ := PInt64(Args[0])^ * PInt64(Args[1])^;
end;

procedure FuncMul_F_LF(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PInt64(Args[0])^ * PDouble(Args[1])^;
end;

procedure FuncMul_F_LI(Param: PExpressionRec);
begin
  with Param^ do
    PInt64(Res.MemoryPos^)^ := PInt64(Args[0])^ * PInteger(Args[1])^;
end;

{$endif}

procedure FuncDiv_F_FF(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^ / PDouble(Args[1])^;
end;

procedure FuncDiv_F_FI(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^ / PInteger(Args[1])^;
end;

procedure FuncDiv_F_II(Param: PExpressionRec);
begin
  with Param^ do
    PInteger(Res.MemoryPos^)^ := PInteger(Args[0])^ div PInteger(Args[1])^;
end;

procedure FuncDiv_F_IF(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PInteger(Args[0])^ / PDouble(Args[1])^;
end;

{$ifdef SUPPORT_INT64}

procedure FuncDiv_F_FL(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PDouble(Args[0])^ / PInt64(Args[1])^;
end;

procedure FuncDiv_F_IL(Param: PExpressionRec);
begin
  with Param^ do
    PInt64(Res.MemoryPos^)^ := PInteger(Args[0])^ div PInt64(Args[1])^;
end;

procedure FuncDiv_F_LL(Param: PExpressionRec);
begin
  with Param^ do
    PInt64(Res.MemoryPos^)^ := PInt64(Args[0])^ div PInt64(Args[1])^;
end;

procedure FuncDiv_F_LF(Param: PExpressionRec);
begin
  with Param^ do
    PDouble(Res.MemoryPos^)^ := PInt64(Args[0])^ / PDouble(Args[1])^;
end;

procedure FuncDiv_F_LI(Param: PExpressionRec);
begin
  with Param^ do
    PInt64(Res.MemoryPos^)^ := PInt64(Args[0])^ div PInteger(Args[1])^;
end;

{$endif}

function FuncStr_Compare(Param: PExpressionRec): Integer; // 11/01/2011 pb  CR 19713
begin
  with Param^ do
    Result := DbfCompareString(ExpressionContext.Collation, Args[0], StrLen(Args[0]), Args[1], StrLen(Args[1])) - 2;
end;

function FuncStrI_Compare(Param: PExpressionRec): Integer; // 11/01/2011 pb  CR 19713
begin
  with Param^ do
  begin
    DbfStrUpper(ExpressionContext.LocaleID, Args[0]);
    DbfStrUpper(ExpressionContext.LocaleID, Args[1]);
  end;
  Result := FuncStr_Compare(Param);
end;

procedure FuncStrI_EQ(Param: PExpressionRec);
begin
  with Param^ do
//  Res.MemoryPos^^ := Char(AnsiStrIComp(Args[0], Args[1]) = 0);
    Res.MemoryPos^^ := Char(FuncStrI_Compare(Param) = 0); // 11/01/2011 pb  CR 19713
end;

procedure FuncStrIP_EQ(Param: PExpressionRec);
var
  arg0len, arg1len: integer;
  match: boolean;
  str0, str1: string;
begin
  with Param^ do
  begin
    arg1len := StrLen(Args[1]);
    if Args[1][0] = '*' then
    begin
      if Args[1][arg1len-1] = '*' then
      begin
//      str0 := AnsiStrUpper(Args[0]);
//      str1 := AnsiStrUpper(Args[1]+1);
        str0 := DbfStrUpper(Param^.ExpressionContext.LocaleID, Args[0]); // 04/29/2011 pb  CR 18895
        str1 := DbfStrUpper(Param^.ExpressionContext.LocaleID, Args[1]+1); // 04/29/2011 pb  CR 18895
        setlength(str1, arg1len-2);
        match := AnsiPos(str0, str1) = 0;
      end else begin
        arg0len := StrLen(Args[0]);
        // at least length without asterisk
        match := arg0len >= arg1len - 1;
        if match then
          match := AnsiStrLIComp(Args[0]+(arg0len-arg1len+1), Args[1]+1, arg1len-1) = 0;
      end;
    end else
    if Args[1][arg1len-1] = '*' then
    begin
      arg0len := StrLen(Args[0]);
      match := arg0len >= arg1len - 1;
      if match then
        match := AnsiStrLIComp(Args[0], Args[1], arg1len-1) = 0;
    end else begin
      match := AnsiStrIComp(Args[0], Args[1]) = 0;
    end;
    Res.MemoryPos^^ := Char(match);
  end;
end;

procedure FuncStrI_NEQ(Param: PExpressionRec);
begin
  with Param^ do
//  Res.MemoryPos^^ := Char(AnsiStrIComp(Args[0], Args[1]) <> 0);
    Res.MemoryPos^^ := Char(FuncStrI_Compare(Param) <> 0); // 11/01/2011 pb  CR 19713
end;

procedure FuncStrI_LT(Param: PExpressionRec);
begin
  with Param^ do
//  Res.MemoryPos^^ := Char(AnsiStrIComp(Args[0], Args[1]) < 0);
    Res.MemoryPos^^ := Char(FuncStrI_Compare(Param) < 0); // 11/01/2011 pb  CR 19713
end;

procedure FuncStrI_GT(Param: PExpressionRec);
begin
  with Param^ do
//  Res.MemoryPos^^ := Char(AnsiStrIComp(Args[0], Args[1]) > 0);
    Res.MemoryPos^^ := Char(FuncStrI_Compare(Param) > 0); // 11/01/2011 pb  CR 19713
end;

procedure FuncStrI_LTE(Param: PExpressionRec);
begin
  with Param^ do
//    Res.MemoryPos^^ := Char(AnsiStrIComp(Args[0], Args[1]) <= 0);
    Res.MemoryPos^^ := Char(FuncStrI_Compare(Param) <= 0); // 11/01/2011 pb  CR 19713
end;

procedure FuncStrI_GTE(Param: PExpressionRec);
begin
  with Param^ do
//  Res.MemoryPos^^ := Char(AnsiStrIComp(Args[0], Args[1]) >= 0);
    Res.MemoryPos^^ := Char(FuncStrI_Compare(Param) >= 0); // 11/01/2011 pb  CR 19713
end;

procedure FuncStrP_EQ(Param: PExpressionRec);
var
  arg0len, arg1len: integer;
  match: boolean;
begin
  with Param^ do
  begin
    arg1len := StrLen(Args[1]);
    if Args[1][0] = '*' then
    begin
      if Args[1][arg1len-1] = '*' then
      begin
        Args[1][arg1len-1] := #0;
        match := AnsiStrPos(Args[0], Args[1]+1) <> nil;
        Args[1][arg1len-1] := '*';
      end else begin
        arg0len := StrLen(Args[0]);
        // at least length without asterisk
        match := arg0len >= arg1len - 1;
        if match then
          match := AnsiStrLComp(Args[0]+(arg0len-arg1len+1), Args[1]+1, arg1len-1) = 0;
      end;
    end else
    if Args[1][arg1len-1] = '*' then
    begin
      arg0len := StrLen(Args[0]);
      match := arg0len >= arg1len - 1;
      if match then
        match := AnsiStrLComp(Args[0], Args[1], arg1len-1) = 0;
    end else begin
      match := AnsiStrComp(Args[0], Args[1]) = 0;
    end;
    Res.MemoryPos^^ := Char(match);
  end;
end;

procedure FuncStr_EQ(Param: PExpressionRec);
begin
  with Param^ do
//  Res.MemoryPos^^ := Char(AnsiStrComp(Args[0], Args[1]) = 0);
    Res.MemoryPos^^ := Char(FuncStr_Compare(Param) = 0); // 11/01/2011 pb  CR 19713
end;

procedure FuncStr_NEQ(Param: PExpressionRec);
begin
  with Param^ do
//  Res.MemoryPos^^ := Char(AnsiStrComp(Args[0], Args[1]) <> 0);
    Res.MemoryPos^^ := Char(FuncStr_Compare(Param) <> 0); // 11/01/2011 pb  CR 19713
end;

procedure FuncStr_LT(Param: PExpressionRec);
begin
  with Param^ do
//  Res.MemoryPos^^ := Char(AnsiStrComp(Args[0], Args[1]) < 0);
    Res.MemoryPos^^ := Char(FuncStr_Compare(Param) < 0); // 11/01/2011 pb  CR 19713
end;

procedure FuncStr_GT(Param: PExpressionRec);
begin
  with Param^ do
//  Res.MemoryPos^^ := Char(AnsiStrComp(Args[0], Args[1]) > 0);
    Res.MemoryPos^^ := Char(FuncStr_Compare(Param) > 0); // 11/01/2011 pb  CR 19713
end;

procedure FuncStr_LTE(Param: PExpressionRec);
begin
  with Param^ do
//  Res.MemoryPos^^ := Char(AnsiStrComp(Args[0], Args[1]) <= 0);
    Res.MemoryPos^^ := Char(FuncStr_Compare(Param) <= 0); // 11/01/2011 pb  CR 19713
end;

procedure FuncStr_GTE(Param: PExpressionRec);
begin
  with Param^ do
//  Res.MemoryPos^^ := Char(AnsiStrComp(Args[0], Args[1]) >= 0);
    Res.MemoryPos^^ := Char(FuncStr_Compare(Param) >= 0); // 11/01/2011 pb  CR 19713
end;

procedure Func_FF_EQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   =  PDouble(Args[1])^);
end;

procedure Func_FF_NEQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   <> PDouble(Args[1])^);
end;

procedure Func_FF_LT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   <  PDouble(Args[1])^);
end;

procedure Func_FF_GT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   >  PDouble(Args[1])^);
end;

procedure Func_FF_LTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   <= PDouble(Args[1])^);
end;

procedure Func_FF_GTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   >= PDouble(Args[1])^);
end;

procedure Func_FI_EQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   =  PInteger(Args[1])^);
end;

procedure Func_FI_NEQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   <> PInteger(Args[1])^);
end;

procedure Func_FI_LT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   <  PInteger(Args[1])^);
end;

procedure Func_FI_GT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   >  PInteger(Args[1])^);
end;

procedure Func_FI_LTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   <= PInteger(Args[1])^);
end;

procedure Func_FI_GTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   >= PInteger(Args[1])^);
end;

procedure Func_II_EQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  =  PInteger(Args[1])^);
end;

procedure Func_II_NEQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  <> PInteger(Args[1])^);
end;

procedure Func_II_LT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  <  PInteger(Args[1])^);
end;

procedure Func_II_GT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  >  PInteger(Args[1])^);
end;

procedure Func_II_LTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  <= PInteger(Args[1])^);
end;

procedure Func_II_GTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  >= PInteger(Args[1])^);
end;

procedure Func_IF_EQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  =  PDouble(Args[1])^);
end;

procedure Func_IF_NEQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  <> PDouble(Args[1])^);
end;

procedure Func_IF_LT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  <  PDouble(Args[1])^);
end;

procedure Func_IF_GT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  >  PDouble(Args[1])^);
end;

procedure Func_IF_LTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  <= PDouble(Args[1])^);
end;

procedure Func_IF_GTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  >= PDouble(Args[1])^);
end;

{$ifdef SUPPORT_INT64}

procedure Func_LL_EQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    =  PInt64(Args[1])^);
end;

procedure Func_LL_NEQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    <> PInt64(Args[1])^);
end;

procedure Func_LL_LT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    <  PInt64(Args[1])^);
end;

procedure Func_LL_GT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    >  PInt64(Args[1])^);
end;

procedure Func_LL_LTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    <= PInt64(Args[1])^);
end;

procedure Func_LL_GTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    >= PInt64(Args[1])^);
end;

procedure Func_LF_EQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    =  PDouble(Args[1])^);
end;

procedure Func_LF_NEQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    <> PDouble(Args[1])^);
end;

procedure Func_LF_LT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    <  PDouble(Args[1])^);
end;

procedure Func_LF_GT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    >  PDouble(Args[1])^);
end;

procedure Func_LF_LTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    <= PDouble(Args[1])^);
end;

procedure Func_LF_GTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    >= PDouble(Args[1])^);
end;

procedure Func_FL_EQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   =  PInt64(Args[1])^);
end;

procedure Func_FL_NEQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   <> PInt64(Args[1])^);
end;

procedure Func_FL_LT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   <  PInt64(Args[1])^);
end;

procedure Func_FL_GT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   >  PInt64(Args[1])^);
end;

procedure Func_FL_LTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   <= PInt64(Args[1])^);
end;

procedure Func_FL_GTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PDouble(Args[0])^   >= PInt64(Args[1])^);
end;

procedure Func_LI_EQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    =  PInteger(Args[1])^);
end;

procedure Func_LI_NEQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    <> PInteger(Args[1])^);
end;

procedure Func_LI_LT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    <  PInteger(Args[1])^);
end;

procedure Func_LI_GT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    >  PInteger(Args[1])^);
end;

procedure Func_LI_LTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    <= PInteger(Args[1])^);
end;

procedure Func_LI_GTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInt64(Args[0])^    >= PInteger(Args[1])^);
end;

procedure Func_IL_EQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  =  PInt64(Args[1])^);
end;

procedure Func_IL_NEQ(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  <> PInt64(Args[1])^);
end;

procedure Func_IL_LT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  <  PInt64(Args[1])^);
end;

procedure Func_IL_GT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  >  PInt64(Args[1])^);
end;

procedure Func_IL_LTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  <= PInt64(Args[1])^);
end;

procedure Func_IL_GTE(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(PInteger(Args[0])^  >= PInt64(Args[1])^);
end;

{$endif}

procedure Func_AND(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(Boolean(Args[0]^) and Boolean(Args[1]^));
end;

procedure Func_OR(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(Boolean(Args[0]^) or Boolean(Args[1]^));
end;

procedure Func_NOT(Param: PExpressionRec);
begin
  with Param^ do
    Res.MemoryPos^^ := Char(not Boolean(Args[0]^));
end;

initialization

  DbfWordsGeneralList := TExpressList.Create;
  DbfWordsInsensGeneralList := TExpressList.Create;
  DbfWordsInsensNoPartialList := TExpressList.Create;
  DbfWordsInsensPartialList := TExpressList.Create;
  DbfWordsSensGeneralList := TExpressList.Create;
  DbfWordsSensNoPartialList := TExpressList.Create;
  DbfWordsSensPartialList := TExpressList.Create;

  with DbfWordsGeneralList do
  begin
    // basic function functionality
    Add(TLeftBracket.Create('(', nil));
    Add(TRightBracket.Create(')', nil));
    Add(TComma.Create(',', nil));

    // operators - name, param types, result type, func addr, precedence
    Add(TFunction.CreateOper('+', 'SS', etString,   nil,          40));
    Add(TFunction.CreateOper('+', 'FF', etFloat,    FuncAdd_F_FF, 40));
    Add(TFunction.CreateOper('+', 'FI', etFloat,    FuncAdd_F_FI, 40));
    Add(TFunction.CreateOper('+', 'IF', etFloat,    FuncAdd_F_IF, 40));
    Add(TFunction.CreateOper('+', 'II', etInteger,  FuncAdd_F_II, 40));
{$ifdef SUPPORT_INT64}
    Add(TFunction.CreateOper('+', 'FL', etFloat,    FuncAdd_F_FL, 40));
    Add(TFunction.CreateOper('+', 'IL', etLargeInt, FuncAdd_F_IL, 40));
    Add(TFunction.CreateOper('+', 'LF', etFloat,    FuncAdd_F_LF, 40));
    Add(TFunction.CreateOper('+', 'LL', etLargeInt, FuncAdd_F_LI, 40));
    Add(TFunction.CreateOper('+', 'LI', etLargeInt, FuncAdd_F_LL, 40));
{$endif}
    Add(TFunction.CreateOper('+', 'DF', etDateTime, FuncAdd_D_DF, 40)); // 04/08/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'DI', etDateTime, FuncAdd_D_DI, 40)); // 04/08/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'DL', etDateTime, FuncAdd_D_DL, 40)); // 04/08/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'FD', etDateTime, FuncAdd_D_FD, 40)); // 04/08/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'ID', etDateTime, FuncAdd_D_ID, 40)); // 04/08/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'LD', etDateTime, FuncAdd_D_LD, 40)); // 04/08/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'DS', etString,   FuncAdd_S,    40)); // 04/11/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'FS', etString,   FuncAdd_S,    40)); // 04/11/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'IS', etString,   FuncAdd_S,    40)); // 04/11/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'LS', etString,   FuncAdd_S,    40)); // 04/11/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'SD', etString,   FuncAdd_S,    40)); // 04/11/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'SF', etString,   FuncAdd_S,    40)); // 04/11/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'SI', etString,   FuncAdd_S,    40)); // 04/11/2011 pb  CR 18908
    Add(TFunction.CreateOper('+', 'SL', etString,   FuncAdd_S,    40)); // 04/11/2011 pb  CR 18908
    Add(TFunction.CreateOper('-', 'DF', etDateTime, FuncSub_D_DF, 40)); // 04/27/2011 pb  CR 18959
    Add(TFunction.CreateOper('-', 'DI', etDateTime, FuncSub_D_DI, 40)); // 04/27/2011 pb  CR 18959
    Add(TFunction.CreateOper('-', 'FF', etFloat,    FuncSub_F_FF, 40));
    Add(TFunction.CreateOper('-', 'FI', etFloat,    FuncSub_F_FI, 40));
    Add(TFunction.CreateOper('-', 'IF', etFloat,    FuncSub_F_IF, 40));
    Add(TFunction.CreateOper('-', 'II', etInteger,  FuncSub_F_II, 40));
    Add(TFunction.CreateOper('-', 'DD', etFloat,    FuncSub_F_DD, 40)); // 04/27/2011 pb  CR 18959
{$ifdef SUPPORT_INT64}
    Add(TFunction.CreateOper('-', 'DL', etDateTime, FuncSub_D_DL, 40)); // 04/27/2011 pb  CR 18959
    Add(TFunction.CreateOper('-', 'FL', etFloat,    FuncSub_F_FL, 40));
    Add(TFunction.CreateOper('-', 'IL', etLargeInt, FuncSub_F_IL, 40));
    Add(TFunction.CreateOper('-', 'LF', etFloat,    FuncSub_F_LF, 40));
    Add(TFunction.CreateOper('-', 'LL', etLargeInt, FuncSub_F_LI, 40));
    Add(TFunction.CreateOper('-', 'LI', etLargeInt, FuncSub_F_LL, 40));
{$endif}
    Add(TFunction.CreateOper('-', 'DS', etString,   FuncSub_S,    40)); // 04/27/2011 pb  CR 18959
    Add(TFunction.CreateOper('-', 'FS', etString,   FuncSub_S,    40)); // 04/27/2011 pb  CR 18959
    Add(TFunction.CreateOper('-', 'IS', etString,   FuncSub_S,    40)); // 04/27/2011 pb  CR 18959
    Add(TFunction.CreateOper('-', 'LS', etString,   FuncSub_S,    40)); // 04/27/2011 pb  CR 18959
    Add(TFunction.CreateOper('-', 'SD', etString,   FuncSub_S,    40)); // 04/27/2011 pb  CR 18959
    Add(TFunction.CreateOper('-', 'SF', etString,   FuncSub_S,    40)); // 04/27/2011 pb  CR 18959
    Add(TFunction.CreateOper('-', 'SI', etString,   FuncSub_S,    40)); // 04/27/2011 pb  CR 18959
    Add(TFunction.CreateOper('-', 'SL', etString,   FuncSub_S,    40)); // 04/27/2011 pb  CR 18959
    Add(TFunction.CreateOper('-', 'SS', etString,   FuncSub_S,    40)); // 04/27/2011 pb  CR 18959
    Add(TFunction.CreateOper('+', 'D',  etDateTime, nil,          40)); // 04/28/2011 pb  CR 18884
    Add(TFunction.CreateOper('+', 'F',  etFloat,    nil,          40)); // 04/28/2011 pb  CR 18884
    Add(TFunction.CreateOper('+', 'I',  etInteger,  nil,          40)); // 04/28/2011 pb  CR 18884
    Add(TFunction.CreateOper('+', 'S',  etString,   nil,          40)); // 04/28/2011 pb  CR 18884
    Add(TFunction.CreateOper('-', 'F',  etFloat,    FuncNegate,   40)); // 04/28/2011 pb  CR 18884
    Add(TFunction.CreateOper('-', 'I',  etInteger,  FuncNegate,   40)); // 04/28/2011 pb  CR 18884
{$ifdef SUPPORT_INT64}
    Add(TFunction.CreateOper('+', 'L',  etLargeInt, nil,          40)); // 04/28/2011 pb  CR 18884
    Add(TFunction.CreateOper('-', 'L',  etLargeInt, FuncNegate,   40)); // 04/28/2011 pb  CR 18884
{$endif}
    Add(TFunction.CreateOper('*', 'FF', etFloat,    FuncMul_F_FF, 40));
    Add(TFunction.CreateOper('*', 'FI', etFloat,    FuncMul_F_FI, 40));
    Add(TFunction.CreateOper('*', 'IF', etFloat,    FuncMul_F_IF, 40));
    Add(TFunction.CreateOper('*', 'II', etInteger,  FuncMul_F_II, 40));
{$ifdef SUPPORT_INT64}
    Add(TFunction.CreateOper('*', 'FL', etFloat,    FuncMul_F_FL, 40));
    Add(TFunction.CreateOper('*', 'IL', etLargeInt, FuncMul_F_IL, 40));
    Add(TFunction.CreateOper('*', 'LF', etFloat,    FuncMul_F_LF, 40));
    Add(TFunction.CreateOper('*', 'LL', etLargeInt, FuncMul_F_LI, 40));
    Add(TFunction.CreateOper('*', 'LI', etLargeInt, FuncMul_F_LL, 40));
{$endif}
    Add(TFunction.CreateOper('/', 'FF', etFloat,    FuncDiv_F_FF, 40));
    Add(TFunction.CreateOper('/', 'FI', etFloat,    FuncDiv_F_FI, 40));
    Add(TFunction.CreateOper('/', 'IF', etFloat,    FuncDiv_F_IF, 40));
    Add(TFunction.CreateOper('/', 'II', etInteger,  FuncDiv_F_II, 40));
{$ifdef SUPPORT_INT64}
    Add(TFunction.CreateOper('/', 'FL', etFloat,    FuncDiv_F_FL, 40));
    Add(TFunction.CreateOper('/', 'IL', etLargeInt, FuncDiv_F_IL, 40));
    Add(TFunction.CreateOper('/', 'LF', etFloat,    FuncDiv_F_LF, 40));
    Add(TFunction.CreateOper('/', 'LL', etLargeInt, FuncDiv_F_LI, 40));
    Add(TFunction.CreateOper('/', 'LI', etLargeInt, FuncDiv_F_LL, 40));
{$endif}

    Add(TFunction.CreateOper('=', 'FF', etBoolean, Func_FF_EQ , 80));
    Add(TFunction.CreateOper('<', 'FF', etBoolean, Func_FF_LT , 80));
    Add(TFunction.CreateOper('>', 'FF', etBoolean, Func_FF_GT , 80));
    Add(TFunction.CreateOper('<=','FF', etBoolean, Func_FF_LTE, 80));
    Add(TFunction.CreateOper('>=','FF', etBoolean, Func_FF_GTE, 80));
    Add(TFunction.CreateOper('<>','FF', etBoolean, Func_FF_NEQ, 80));
    Add(TFunction.CreateOper('=', 'FI', etBoolean, Func_FI_EQ , 80));
    Add(TFunction.CreateOper('<', 'FI', etBoolean, Func_FI_LT , 80));
    Add(TFunction.CreateOper('>', 'FI', etBoolean, Func_FI_GT , 80));
    Add(TFunction.CreateOper('<=','FI', etBoolean, Func_FI_LTE, 80));
    Add(TFunction.CreateOper('>=','FI', etBoolean, Func_FI_GTE, 80));
    Add(TFunction.CreateOper('<>','FI', etBoolean, Func_FI_NEQ, 80));
    Add(TFunction.CreateOper('=', 'II', etBoolean, Func_II_EQ , 80));
    Add(TFunction.CreateOper('<', 'II', etBoolean, Func_II_LT , 80));
    Add(TFunction.CreateOper('>', 'II', etBoolean, Func_II_GT , 80));
    Add(TFunction.CreateOper('<=','II', etBoolean, Func_II_LTE, 80));
    Add(TFunction.CreateOper('>=','II', etBoolean, Func_II_GTE, 80));
    Add(TFunction.CreateOper('<>','II', etBoolean, Func_II_NEQ, 80));
    Add(TFunction.CreateOper('=', 'IF', etBoolean, Func_IF_EQ , 80));
    Add(TFunction.CreateOper('<', 'IF', etBoolean, Func_IF_LT , 80));
    Add(TFunction.CreateOper('>', 'IF', etBoolean, Func_IF_GT , 80));
    Add(TFunction.CreateOper('<=','IF', etBoolean, Func_IF_LTE, 80));
    Add(TFunction.CreateOper('>=','IF', etBoolean, Func_IF_GTE, 80));
    Add(TFunction.CreateOper('<>','IF', etBoolean, Func_IF_NEQ, 80));
{$ifdef SUPPORT_INT64}
    Add(TFunction.CreateOper('=', 'LL', etBoolean, Func_LL_EQ , 80));
    Add(TFunction.CreateOper('<', 'LL', etBoolean, Func_LL_LT , 80));
    Add(TFunction.CreateOper('>', 'LL', etBoolean, Func_LL_GT , 80));
    Add(TFunction.CreateOper('<=','LL', etBoolean, Func_LL_LTE, 80));
    Add(TFunction.CreateOper('>=','LL', etBoolean, Func_LL_GTE, 80));
    Add(TFunction.CreateOper('<>','LL', etBoolean, Func_LL_NEQ, 80));
    Add(TFunction.CreateOper('=', 'LF', etBoolean, Func_LF_EQ , 80));
    Add(TFunction.CreateOper('<', 'LF', etBoolean, Func_LF_LT , 80));
    Add(TFunction.CreateOper('>', 'LF', etBoolean, Func_LF_GT , 80));
    Add(TFunction.CreateOper('<=','LF', etBoolean, Func_LF_LTE, 80));
    Add(TFunction.CreateOper('>=','LF', etBoolean, Func_LF_GTE, 80));
    Add(TFunction.CreateOper('<>','FI', etBoolean, Func_LF_NEQ, 80));
    Add(TFunction.CreateOper('=', 'LI', etBoolean, Func_LI_EQ , 80));
    Add(TFunction.CreateOper('<', 'LI', etBoolean, Func_LI_LT , 80));
    Add(TFunction.CreateOper('>', 'LI', etBoolean, Func_LI_GT , 80));
    Add(TFunction.CreateOper('<=','LI', etBoolean, Func_LI_LTE, 80));
    Add(TFunction.CreateOper('>=','LI', etBoolean, Func_LI_GTE, 80));
    Add(TFunction.CreateOper('<>','LI', etBoolean, Func_LI_NEQ, 80));
    Add(TFunction.CreateOper('=', 'FL', etBoolean, Func_FL_EQ , 80));
    Add(TFunction.CreateOper('<', 'FL', etBoolean, Func_FL_LT , 80));
    Add(TFunction.CreateOper('>', 'FL', etBoolean, Func_FL_GT , 80));
    Add(TFunction.CreateOper('<=','FL', etBoolean, Func_FL_LTE, 80));
    Add(TFunction.CreateOper('>=','FL', etBoolean, Func_FL_GTE, 80));
    Add(TFunction.CreateOper('<>','FL', etBoolean, Func_FL_NEQ, 80));
    Add(TFunction.CreateOper('=', 'IL', etBoolean, Func_IL_EQ , 80));
    Add(TFunction.CreateOper('<', 'IL', etBoolean, Func_IL_LT , 80));
    Add(TFunction.CreateOper('>', 'IL', etBoolean, Func_IL_GT , 80));
    Add(TFunction.CreateOper('<=','IL', etBoolean, Func_IL_LTE, 80));
    Add(TFunction.CreateOper('>=','IL', etBoolean, Func_IL_GTE, 80));
    Add(TFunction.CreateOper('<>','IL', etBoolean, Func_IL_NEQ, 80));
{$endif}

    Add(TFunction.CreateOper('NOT', 'B',  etBoolean, Func_NOT, 85));
    Add(TFunction.CreateOper('AND', 'BB', etBoolean, Func_AND, 90));
    Add(TFunction.CreateOper('OR',  'BB', etBoolean, Func_OR, 100));

    // Functions - name, description, param types, min params, result type, Func addr
//  Add(TFunction.Create('STR',       '',      'FII', 1, etString, FuncFloatToStr, ''));
//  Add(TFunction.Create('STR',       '',      'III', 1, etString, FuncIntToStr, ''));
    Add(TFunction.Create('STR',       '',      'FIIS',1, etString, FuncStr,       '')); // 05/05/2011 pb  CR 18984
    Add(TFunction.Create('STR',       '',      'IIIS',1, etString, FuncStr,       '')); // 05/05/2011 pb  CR 18984
    Add(TFunction.Create('STR',       '',      'LIIS',1, etString, FuncStr,       '')); // 05/05/2011 pb  CR 18984
    Add(TFunction.Create('DTOS',      '',      'D',   1, etString, FuncDateToStr, ''));
    Add(TFunction.Create('SUBSTR',    'SUBS',  'SII', 3, etString, FuncSubString, ''));
    Add(TFunction.Create('SUBSTR',    'SUBS',  'SI',  2, etString, FuncSubString, '')); // 11/10/2011 pb  CR 19542
    Add(TFunction.Create('UPPERCASE', 'UPPER', 'S',   1, etString, FuncUppercase, ''));
    Add(TFunction.Create('LOWERCASE', 'LOWER', 'S',   1, etString, FuncLowercase, ''));
    Add(TFunction.Create('PROPER',    '',      'S',   1, etString, FuncProper,    '')); // 04/15/2011 pb  CR 18892

    Add(TFunction.Create('LEFT',      '',      'SI',  2, etString,   FuncLeft,       '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('RIGHT',     '',      'SI',  2, etString,   FuncRight,      '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('IIF',       '',      'BSS', 3, etString,   FuncIIF_S_SS,   '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('IIF',       '',      'BFF', 3, etFloat,    FuncIIF_F_FF,   '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('IIF',       '',      'BII', 3, etInteger,  FuncIIF_I_II,   '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('SOUNDEX',   '',      'S',   1, etString,   FuncSoundex,    '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('DAY',       '',      'D',   1, etInteger,  FuncDay,        '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('MONTH',     '',      'D',   1, etInteger,  FuncMonth,      '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('YEAR',      '',      'D',   1, etInteger,  FuncYear,       '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('CDOW',      '',      'D',   1, etString,   FuncCDOW,       '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('ABS',       '',      'I',   1, etInteger,  FuncAbs_I_I,    '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('ABS',       '',      'F',   1, etFloat,    FuncAbs_F_F,    '')); // 01/27/2011 dhd CR 18536
{$ifdef SUPPORT_INT64}
    Add(TFunction.Create('ABS',       '',      'L',   1, etFloat,    FuncAbs_F_L,    '')); // 01/27/2011 dhd CR 18536
{$endif}
//  Add(TFunction.Create('EMPTY',     '',      'S',   1, etString,   FuncEmpty,      '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('EMPTY',     '',      'D',   1, etBoolean,  FuncEmpty,      '')); // 04/28/2011 pb  CR 18536
    Add(TFunction.Create('EMPTY',     '',      'F',   1, etBoolean,  FuncEmpty,      '')); // 04/28/2011 pb  CR 18536
    Add(TFunction.Create('EMPTY',     '',      'I',   1, etBoolean,  FuncEmpty,      '')); // 04/28/2011 pb  CR 18536
{$ifdef SUPPORT_INT64}
    Add(TFunction.Create('EMPTY',     '',      'L',   1, etBoolean,  FuncEmpty,      '')); // 04/28/2011 pb  CR 18536
{$endif}
    Add(TFunction.Create('EMPTY',     '',      'S',   1, etBoolean,  FuncEmpty,      '')); // 04/28/2011 pb  CR 18536
    Add(TFunction.Create('LEN',       '',      'S',   1, etInteger,  FuncLen_I_S,    '')); // 01/27/2011 dhd CR 18536
{$ifdef SUPPORT_INT64}
    Add(TFunction.Create('LEN',       '',      'S',   1, etLargeInt, FuncLen_L_S,    '')); // 01/27/2011 dhd CR 18536
{$endif}
    Add(TFunction.Create('LEN',       '',      'S',   1, etFloat,    FuncLen_F_S,    '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('LTRIM',     '',      'S',   1, etString,   FuncLTrim,      '')); // 04/28/2011 pb  CR 18536
//  Add(TFunction.Create('TRIM',      '',      'S',   1, etString,   FuncTrim,       '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('TRIM',      '',      'S',   1, etString,   FuncRTrim,      '')); // 04/28/2011 pb  CR 18536
//  Add(TFunction.Create('RTRIM',     '',      'S',   1, etString,   FuncTrim,       '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('RTRIM',     '',      'S',   1, etString,   FuncRTrim,      '')); // 04/28/2011 pb  CR 18536
//  Add(TFunction.Create('CHR',       '',      'I',   1, etInteger,  FuncChr,        '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('CHR',       '',      'I',   1, etString,   FuncChr,        '')); // 05/05/2011 pb  CR 18536
    Add(TFunction.Create('AT',        '',      'SS',  2, etInteger,  FuncAt,         '')); // 01/27/2011 dhd CR 18536
//  Add(TFunction.Create('ASC',       '',      'S',   1, etString,   FuncAsc,        '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('ASC',       '',      'S',   1, etInteger,  FuncAsc,        '')); // 04/28/2011 pb  CR 18536
//  Add(TFunction.Create('VAL',       '',      'S',   1, etInteger,  FuncVal_I,      '')); // 01/27/2011 dhd CR 18536
//  Add(TFunction.Create('VAL',       '',      'S',   1, etFloat,    FuncVal_F,      '')); // 01/27/2011 dhd CR 18536
//  Add(TFunction.Create('VAL',       '',      'L',   1, etLargeInt, FuncVal_L,      '')); // 01/27/2011 dhd CR 18536
    Add(TFunction.Create('VAL',       '',      'S',   1, etFloat,    FuncVal,        '')); // 04/28/2011 pb  CR 18536
    Add(TFunction.Create('VAL',       '',      'S',   1, etInteger,  FuncVal,        '')); // 04/28/2011 pb  CR 18536
    Add(TFunction.Create('VAL',       '',      'S',   1, etLargeInt, FuncVal,        '')); // 04/28/2011 pb  CR 18536
    Add(TFunction.Create('ROUND',     '',      'FI',  2, etFloat,    FuncRound_F_FI, '')); // 03/23/2011 dhd CR 18536
    Add(TFunction.Create('ROUND',     '',      'FF',  2, etFloat,    FuncRound_F_FF, '')); // 03/23/2011 dhd CR 18536
    Add(TFunction.Create('CEILING',   'CEIL',  'F',   1, etInteger,  FuncCeil_I_F,   '')); // 03/23/2011 dhd CR 18536
    Add(TFunction.Create('CEILING',   'CEIL',  'F',   1, etFloat,    FuncCeil_F_F,   '')); // 03/23/2011 dhd CR 18536
    Add(TFunction.Create('DATE',      '',      '',    0, etDateTime, FuncDate,       '')); // 03/23/2011 dhd CR 18536
    Add(TFunction.Create('RECNO',     '',      '',    0, etInteger,  FuncRecNo,      '')); // 04/15/2011 pb  CR 18893
  end;

  with DbfWordsInsensGeneralList do
  begin
    Add(TFunction.CreateOper('<', 'SS', etBoolean, FuncStrI_LT , 80));
    Add(TFunction.CreateOper('>', 'SS', etBoolean, FuncStrI_GT , 80));
    Add(TFunction.CreateOper('<=','SS', etBoolean, FuncStrI_LTE, 80));
    Add(TFunction.CreateOper('>=','SS', etBoolean, FuncStrI_GTE, 80));
    Add(TFunction.CreateOper('<>','SS', etBoolean, FuncStrI_NEQ, 80));
  end;

  with DbfWordsInsensNoPartialList do
    Add(TFunction.CreateOper('=', 'SS', etBoolean, FuncStrI_EQ , 80));

  with DbfWordsInsensPartialList do
    Add(TFunction.CreateOper('=', 'SS', etBoolean, FuncStrIP_EQ, 80));

  with DbfWordsSensGeneralList do
  begin
    Add(TFunction.CreateOper('<', 'SS', etBoolean, FuncStr_LT , 80));
    Add(TFunction.CreateOper('>', 'SS', etBoolean, FuncStr_GT , 80));
    Add(TFunction.CreateOper('<=','SS', etBoolean, FuncStr_LTE, 80));
    Add(TFunction.CreateOper('>=','SS', etBoolean, FuncStr_GTE, 80));
    Add(TFunction.CreateOper('<>','SS', etBoolean, FuncStr_NEQ, 80));
  end;

  with DbfWordsSensNoPartialList do
    Add(TFunction.CreateOper('=', 'SS', etBoolean, FuncStr_EQ , 80));

  with DbfWordsSensPartialList do
    Add(TFunction.CreateOper('=', 'SS', etBoolean, FuncStrP_EQ , 80));

finalization

  DbfWordsGeneralList.Free;
  DbfWordsInsensGeneralList.Free;
  DbfWordsInsensNoPartialList.Free;
  DbfWordsInsensPartialList.Free;
  DbfWordsSensGeneralList.Free;
  DbfWordsSensNoPartialList.Free;
  DbfWordsSensPartialList.Free;
end.

