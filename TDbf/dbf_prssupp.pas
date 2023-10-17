unit dbf_prssupp;

// Modifications by BCC Software
// 05/05/2011 pb  CR 18916- It may need to use exponential notation in a Numeric (N) or Float (F) field with 0 precision, if the size is insufficient for all digits, eg. 1000000 is "   1E6" in N6.0 field.
// 05/05/2011 pb  CR 18984- Number to string conversion is inconsistent and does not properly take into account the width

// parse support

{$I dbf_common.inc}

interface

uses
  Classes;

type

  {TOCollection interfaces between OWL TCollection and VCL TList}

  TOCollection = class(TList)
  public
    procedure AtFree(Index: Integer);
    procedure FreeAll;
    procedure DoFree(Item: Pointer);
    procedure FreeItem(Item: Pointer); virtual;
    destructor Destroy; override;
  end;

  TNoOwnerCollection = class(TOCollection)
  public
    procedure FreeItem(Item: Pointer); override;
  end;

  { TSortedCollection object }

  TSortedCollection = class(TOCollection)
  public
    function Compare(Key1, Key2: Pointer): Integer; virtual; abstract;
    function IndexOf(Item: Pointer): Integer; virtual;
    procedure Add(Item: Pointer); virtual;
    procedure AddReplace(Item: Pointer); virtual;
    procedure AddList(Source: TList; FromIndex, ToIndex: Integer);
    {if duplicate then replace the duplicate else add}
    function KeyOf(Item: Pointer): Pointer; virtual;
    function Search(Key: Pointer; var Index: Integer): Boolean; virtual;
  end;

  { TStrCollection object }

  TStrCollection = class(TSortedCollection)
  public
    function Compare(Key1, Key2: Pointer): Integer; override;
    procedure FreeItem(Item: Pointer); override;
  end;

(*
function GetStrFromInt(Val: Integer; const Dst: PChar): Integer;
procedure GetStrFromInt_Width(Val: Integer; const Width: Integer; const Dst: PChar; const PadChar: Char);
{$ifdef SUPPORT_INT64}
function  GetStrFromInt64(Val: Int64; const Dst: PChar): Integer;
procedure GetStrFromInt64_Width(Val: Int64; const Width: Integer; const Dst: PChar; const PadChar: Char);
{$endif}
*)

const
  DBF_POSITIVESIGN = '+'; // 05/05/2011 pb  CR 18916
  DBF_NEGATIVESIGN = '-'; // 05/05/2011 pb  CR 18984
  DBF_DECIMAL = '.'; // 05/05/2011 pb  CR 18984
  DBF_EXPSIGN = 'E'; // 05/05/2011 pb  CR 18984
  DBF_ZERO = '0'; // 05/05/2011 pb  CR 18984
  DBF_NINE = '9'; // 05/05/2011 pb  CR 18916


function IntToStrWidth(Val: {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif}; const FieldSize: Integer; const Dest: PChar; Pad: Boolean; PadChar: Char): Integer; // 05/05/2011 pb  CR 18984
function FloatToStrWidth(const Val: Extended; const FieldSize, FieldPrec: Integer; const Dest: PChar; Pad: Boolean): Integer; // 05/05/2011 pb  CR 18984

function StrToIntWidth(var IntValue: {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif}; Src: Pointer; Size: Integer; Default: Integer): Boolean;
function StrToInt32Width(var IntValue: Integer; Src: Pointer; Size: Integer; Default: Integer): Boolean;
function StrToFloatWidth(var FloatValue: Extended; const Src: PChar; const Size: Integer; Default: Extended): Boolean;

implementation

uses SysUtils;

destructor TOCollection.Destroy;
begin
  FreeAll;
  inherited Destroy;
end;

procedure TOCollection.AtFree(Index: Integer);
var
  Item: Pointer;
begin
  Item := Items[Index];
  Delete(Index);
  FreeItem(Item);
end;


procedure TOCollection.FreeAll;
var
  I: Integer;
begin
  try
    for I := 0 to Count - 1 do
      FreeItem(Items[I]);
  finally
    Count := 0;
  end;
end;

procedure TOCollection.DoFree(Item: Pointer);
begin
  AtFree(IndexOf(Item));
end;

procedure TOCollection.FreeItem(Item: Pointer);
begin
  if (Item <> nil) then
    with TObject(Item) as TObject do
      Free;
end;

{----------------------------------------------------------------virtual;
  Implementing TNoOwnerCollection
  -----------------------------------------------------------------}

procedure TNoOwnerCollection.FreeItem(Item: Pointer);
begin
end;

{ TSortedCollection }

function TSortedCollection.IndexOf(Item: Pointer): Integer;
var
  I: Integer;
begin
  IndexOf := -1;
  if Search(KeyOf(Item), I) then
  begin
    while (I < Count) and (Item <> Items[I]) do
      Inc(I);
    if I < Count then IndexOf := I;
  end;
end;

procedure TSortedCollection.AddReplace(Item: Pointer);
var
  Index: Integer;
begin
  if Search(KeyOf(Item), Index) then
    Delete(Index);
  Add(Item);
end;

procedure TSortedCollection.Add(Item: Pointer);
var
  I: Integer;
begin
  Search(KeyOf(Item), I);
  Insert(I, Item);
end;

procedure TSortedCollection.AddList(Source: TList; FromIndex, ToIndex: Integer);
var
  I: Integer;
begin
  for I := FromIndex to ToIndex do
    Add(Source.Items[I]);
end;

function TSortedCollection.KeyOf(Item: Pointer): Pointer;
begin
  Result := Item;
end;

function TSortedCollection.Search(Key: Pointer; var Index: Integer): Boolean;
var
  L, H, I, C: Integer;
begin
  Result := false;
  L := 0;
  H := Count - 1;
  while L <= H do
  begin
    I := (L + H) div 2;
    C := Compare(KeyOf(Items[I]), Key);
    if C < 0 then
      L := I + 1
    else begin
      H := I - 1;
      Result := C = 0;
    end;
  end;
  Index := L;
end;

{ TStrCollection }

function TStrCollection.Compare(Key1, Key2: Pointer): Integer;
begin
  Compare := StrComp(Key1, Key2);
end;

procedure TStrCollection.FreeItem(Item: Pointer);
begin
  StrDispose(Item);
end;

(*
// it seems there is no pascal function to convert an integer into a PChar???
// NOTE: in dbf_dbffile.pas there is also a convert routine, but is slightly different

function GetStrFromInt(Val: Integer; const Dst: PChar): Integer;
var
  Temp: array[0..10] of Char;
  I, J: Integer;
begin
  Val := Abs(Val);
  // we'll have to store characters backwards first
  I := 0;
  J := 0;
  repeat
    Temp[I] := Chr((Val mod 10) + Ord('0'));
    Val := Val div 10;
    Inc(I);
  until Val = 0;

  // remember number of digits
  Result := I;
  // copy value, remember: stored backwards
  repeat
    Dst[J] := Temp[I-1];
    Inc(J);
    Dec(I);
  until I = 0;
  // done!
end;

// it seems there is no pascal function to convert an integer into a PChar???

procedure GetStrFromInt_Width(Val: Integer; const Width: Integer; const Dst: PChar; const PadChar: Char);
var
  Temp: array[0..10] of Char;
  I, J: Integer;
  NegSign: boolean;
begin
  {$I getstrfromint.inc}
end;

{$ifdef SUPPORT_INT64}

procedure GetStrFromInt64_Width(Val: Int64; const Width: Integer; const Dst: PChar; const PadChar: Char);
var
  Temp: array[0..19] of Char;
  I, J: Integer;
  NegSign: boolean;
begin
  {$I getstrfromint.inc}
end;

function GetStrFromInt64(Val: Int64; const Dst: PChar): Integer;
var
  Temp: array[0..19] of Char;
  I, J: Integer;
begin
  Val := Abs(Val);
  // we'll have to store characters backwards first
  I := 0;
  J := 0;
  repeat
    Temp[I] := Chr((Val mod 10) + Ord('0'));
    Val := Val div 10;
    Inc(I);
  until Val = 0;

  // remember number of digits
  Result := I;
  // copy value, remember: stored backwards
  repeat
    Dst[J] := Temp[I-1];
    inc(J);
    dec(I);
  until I = 0;
  // done!
end;

{$endif}
*)

var
  DbfFormatSettings: TFormatSettings; // 05/05/2011 pb  CR 18916

type
  TFloatResult = record // 05/05/2011 pb  CR 18984
    Dest: PChar;
    P: PChar;
    FieldSize: Integer;
    FieldPrec: Integer;
    Len: Integer;
  end;

procedure FloatPutChar(var FloatResult: TFloatResult; C: Char); // 05/05/2011 pb  CR 18984
begin
  Inc(FloatResult.Len);
  if FloatResult.Len <= FloatResult.FieldSize then
  begin
    FloatResult.P^ := C;
    Inc(FloatResult.P);
  end;
end;

procedure FloatReset(var FloatResult: TFloatResult); // 05/05/2011 pb  CR 18984
begin
  FloatResult.P := FloatResult.Dest;
  FloatResult.Len := 0;
end;

procedure DecimalToDbfStr(var FloatResult: TFloatResult; const FloatRec: TFloatRec; Exponent: SmallInt; FieldPrec: Integer); // 05/05/2011 pb  CR 18984
var
  Digit: SmallInt;
  DigitCount: SmallInt;
  DigitMin: SmallInt;
  DigitMax: SmallInt;
  DigitChar: Char;
  DecCount: Integer;
begin
  FloatReset(FloatResult);
  if FloatRec.Negative then
    FloatPutChar(FloatResult, DBF_NEGATIVESIGN);
  DigitCount := StrLen(FloatRec.Digits);
  if Exponent <= 0 then
  begin
    DigitMin := Exponent;
    FloatPutChar(FloatResult, DBF_ZERO);
  end
  else
    DigitMin := Low(FloatRec.Digits);
  if Exponent > DigitCount then
    DigitMax := Exponent
  else
    DigitMax := DigitCount;
  Digit := DigitMin;
  DecCount := -1;
  while (Digit < DigitMax) or ((FieldPrec <> 0) and (DecCount < FieldPrec) and (FloatResult.Len < FloatResult.FieldSize - Ord(DecCount<0))) do
  begin
    if (Digit >= 0) and (Digit < DigitCount) then
      DigitChar := FloatRec.Digits[Digit]
    else
      DigitChar := DBF_ZERO;
    if Digit=Exponent then
    begin
      FloatPutChar(FloatResult, DBF_DECIMAL);
      DecCount := 0;
    end;
    FloatPutChar(FloatResult, DigitChar);
    Inc(Digit);
    if DecCount >= 0 then
      Inc(DecCount);
  end;
end;

procedure DecimalToDbfStrFormat(var FloatResult: TFloatResult; const FloatRec: TFloatRec; Format: TFloatFormat; FieldPrec: Integer); // 05/05/2011 pb  CR 18984
var
  Exponent: SmallInt;
  ExponentBuffer: array[1..5] of Char;
  Index: Byte;
begin
  if Format=ffExponent then
  begin
    DecimalToDbfStr(FloatResult, FloatRec, 1, 0);
    Exponent:= Pred(FloatRec.Exponent);
    if Exponent<>0 then
    begin
      FloatPutChar(FloatResult, DBF_EXPSIGN);
      if Exponent<0 then
      begin
        FloatPutChar(FloatResult, DBF_NEGATIVESIGN);
        Exponent:= -Exponent;
      end;
      Index:= 0;
      while Exponent<>0 do
      begin
        Inc(Index);
        ExponentBuffer[Index] := Char(Ord(DBF_ZERO) + (Exponent mod 10));
        Exponent := Exponent div 10;
      end;
      while Index>0 do
      begin
        FloatPutChar(FloatResult, ExponentBuffer[Index]);
        Dec(Index);
      end;
    end;
  end
  else
    DecimalToDbfStr(FloatResult, FloatRec, FloatRec.Exponent, FieldPrec);
end;

procedure FloatToDbfStrFormat(var FloatResult: TFloatResult; const FloatRec: TFloatRec; Format: TFloatFormat; FieldPrec: Integer; FloatValue: Extended); // 05/05/2011 pb  CR 18984
var
  FloatRec2: TFloatRec;
  Precision: Integer;
begin
  DecimalToDbfStrFormat(FloatResult, FloatRec, Format, FieldPrec);
  Precision:= Integer(StrLen(FloatRec.Digits));
  if FloatResult.Len > FloatResult.FieldSize then
  begin
    Precision:= Precision - (FloatResult.Len - FloatResult.FieldSize);
    if FloatRec.Exponent = FloatResult.FieldSize-Ord(FloatRec.Negative) then
      Inc(Precision);
    if Precision>0 then
    begin
      FloatToDecimal(FloatRec2, FloatValue, fvExtended, Precision, FieldPrec);
      DecimalToDbfStrFormat(FloatResult, FloatRec2, Format, FieldPrec);
      if FloatResult.Len > FloatResult.FieldSize then
        FloatResult.Len := 0;
    end
    else
       FloatResult.Len := 0;
  end;
end;

function NumberPad(const FloatResult: TFloatResult; const Dest: PChar; Pad: Boolean; PadChar: Char): Integer; // 05/05/2011 pb  CR 18984
begin
  Result:= FloatResult.Len;
  if Pad and (FloatResult.Len <> FloatResult.FieldSize) then
  begin
    Move(Dest^, (Dest+FloatResult.FieldSize-FloatResult.Len)^, FloatResult.Len);
    FillChar(Dest^, FloatResult.FieldSize-FloatResult.Len, PadChar);
    Result:= FloatResult.FieldSize;
  end;
end;

function IntToStrWidth(Val: {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif}; const FieldSize: Integer; const Dest: PChar; Pad: Boolean; PadChar: Char): Integer; // 05/05/2011 pb  CR 18984
var
  FloatResult: TFloatResult;
  Negative: Boolean;
  IntValue: Integer;
  Buffer: array[0..{$ifdef SUPPORT_INT64}18{$else}9{$endif}] of Char;
  P: PChar;
begin
  FillChar(FloatResult, SizeOf(FloatResult), 0);
  FloatResult.Dest := Buffer;
  FloatResult.FieldSize := FieldSize;
  FloatReset(FloatResult);
  Negative := Val<0;
  if Negative then
    IntValue := -Val
  else
    IntValue := Val;
  repeat
    FloatPutChar(FloatResult, Char(Ord(DBF_ZERO) + (IntValue mod 10)));
    IntValue := IntValue div 10;
  until IntValue = 0;
  P:= FloatResult.P;
  FloatResult.Dest := Dest;
  if FloatResult.Len+Ord(Negative) > FieldSize then
  begin
    if PadChar<>DBF_ZERO then
      FloatResult.Len := FloatToStrWidth(Val, FieldSize, 0, Dest, Pad)
    else
      FloatResult.Len := 0;
  end
  else
  begin
    FloatReset(FloatResult);
    if Negative then
      FloatPutChar(FloatResult, DBF_NEGATIVESIGN);
    repeat
      Dec(P);
      FloatPutChar(FloatResult, P^);
    until P=Buffer;
  end;
  Result:= NumberPad(FloatResult, Dest, Pad, PadChar);
end;

function Int64ToStrWidth(Val: Int64; const FieldSize: Integer; const Dest: PChar; Pad: Boolean; PadChar: Char): Integer; // 05/05/2011 pb  CR 18984
begin
  Result:= IntToStrWidth(Val, FieldSize, Dest, Pad, PadChar);
end;

function FloatToStrWidth(const Val: Extended; const FieldSize, FieldPrec: Integer; const Dest: PChar; Pad: Boolean): Integer; // 05/05/2011 pb  CR 18984
var
  FloatResult: TFloatResult;
  FloatRec: TFloatRec;
begin
  FillChar(FloatResult, SizeOf(FloatResult), 0);
  FloatResult.Dest := Dest;
  FloatResult.FieldSize := FieldSize;
  FloatToDecimal(FloatRec, Val, fvExtended, 15, FieldPrec);
  if FloatRec.Exponent <= 15 then
    FloatToDbfStrFormat(FloatResult, FloatRec, ffFixed, FieldPrec, Val);
  if FloatResult.Len = 0 then
    FloatToDbfStrFormat(FloatResult, FloatRec, ffExponent, FieldPrec, Val);
  Result:= NumberPad(FloatResult, Dest, Pad, ' ');
end;

function StrToIntWidth(var IntValue: {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif}; Src: Pointer; Size: Integer; Default: Integer): Boolean; // 05/05/2011 pb  CR 18916
var
  P: PChar;
  Negative: Boolean;
  Digit: Byte;
  FloatValue: Extended;
begin
  P := Src;
{$BOOLEVAL ON}
  while (P < PChar(Src) + Size) and (P^ = ' ') do
    Inc(P);
{$BOOLEVAL OFF}
  Dec(Size, P - Src);
  Src := P;
  Result := Size <> 0;
  if Result then
  begin
    IntValue := 0;
    Negative := False;
    case P^ of
      DBF_POSITIVESIGN: Inc(P);
      DBF_NEGATIVESIGN:
      begin
        Negative := True;
        Inc(P);
      end;
    end;
    repeat
      if P^ in [DBF_ZERO..DBF_NINE] then
      begin
        Digit := Ord(P^) - Ord(DBF_ZERO);
        if IntValue < 0 then
          Result := IntValue >= (Low(IntValue) + Digit) div 10
        else
          Result := IntValue <= (High(IntValue) - Digit) div 10;
        if Result then
          IntValue := IntValue * 10;
        if IntValue >= 0 then
          Inc(IntValue, Digit)
        else
          Dec(IntValue, Digit);
        if Negative and (IntValue <>0) then
        begin
          IntValue := -IntValue;
          Negative := False;
        end;
      end
      else
        Result := False;
      Inc(P);
    until (P = PChar(Src) + Size) or (not Result);
    if not Result then
    begin
      Result := StrToFloatWidth(FloatValue, Src, Size, Default);
      if Result then
        IntValue:= Round(FloatValue);
    end;
    if not Result then
      IntValue := Default;
  end;
end;

function StrToInt32Width(var IntValue: Integer; Src: Pointer; Size: Integer; Default: Integer): Boolean; // 05/05/2011 pb  CR 18916
{$ifdef SUPPORT_INT64}
var
  AIntValue: Int64;
begin
  Result := StrToIntWidth(AIntValue, Src, Size, Default);
  if Result then
  begin
    Result := (AIntValue >= Low(IntValue)) and (AIntValue <= High(IntValue));
    if Result then
      IntValue := AIntValue
    else
      IntValue := Default;
  end;
{$else}
begin
  Result := StrToIntWidth(IntValue, Src, Size, Default);
{$endif}
end;

function StrToFloatWidth(var FloatValue: Extended; const Src: PChar; const Size: Integer; Default: Extended): Boolean; // 05/05/2011 pb  CR 18916
var
  Buffer: array[0..20] of Char;
begin
  Result := Size < SizeOf(Buffer);
  if Result then
  begin
    Move(Src^, Buffer, Size);
    Buffer[Size] := #0;
    Result:= TextToFloat(@Buffer, FloatValue {$ifndef VER1_0}, fvExtended{$endif}, DbfFormatSettings);
  end;
  if not Result then
    FloatValue := Default;
end;

initialization
  FillChar(DbfFormatSettings, SizeOf(DbfFormatSettings), 0); // 05/05/2011 pb  CR 18916
  DbfFormatSettings.DecimalSeparator:= DBF_DECIMAL; // 05/05/2011 pb  CR 18916

end.

