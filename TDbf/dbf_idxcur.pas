unit dbf_idxcur;

// Modifications by BCC Software
// 11/04/2011 pb  CR 19723- Correct key violation handling
// 08/18/2011 pb  CR 19448- 64-bit sequential record numbers to avoid "Integer overflow"
// 04/13/2011 pb  CR 18918- Do not remove inserted record from other indexes if there is a key violation during a copy or restructure

interface

{$I dbf_common.inc}

uses
  SysUtils,
  Classes,
  dbf_cursor,
  dbf_idxfile,
  dbf_prsdef,
  dbf_common;

type

//====================================================================
//=== Index support
//====================================================================
  TIndexCursor = class(TVirtualCursor)
  private
    FIndexFile: TIndexFile;
  protected
    function  GetPhysicalRecNo: Integer; override;
//  function  GetSequentialRecNo: Integer; override;
    function  GetSequentialRecNo: TSequentialRecNo; override; // 08/18/2011 pb  CR 19448
//  function  GetSequentialRecordCount: Integer; override;
    function  GetSequentialRecordCount: TSequentialRecNo; override; // 08/18/2011 pb  CR 19448
    procedure SetPhysicalRecNo(RecNo: Integer); override;
//  procedure SetSequentialRecNo(RecNo: Integer); override;
    procedure SetSequentialRecNo(RecNo: TSequentialRecNo); override; // 08/18/2011 pb  CR 19448

  public
    constructor Create(DbfIndexFile: TIndexFile);
    destructor Destroy; override;

    function  Next: Boolean; override;
    function  Prev: Boolean; override;
    procedure First; override;
    procedure Last; override;

//  procedure Insert(RecNo: Integer; Buffer: PChar);
//  procedure Insert(RecNo: Integer; Buffer: PChar; AllowKeyViolation: Boolean); // 04/13/2011 pb  CR 18918
    procedure Insert(RecNo: Integer; Buffer: PChar; AUniqueMode: TIndexUniqueType); // 11/04/2011 pb  CR 19723
    procedure Update(RecNo: Integer; PrevBuffer, NewBuffer: PChar);

{$ifdef SUPPORT_VARIANTS}
    function  VariantToBuffer(Key: Variant; ABuffer: PChar): TExpressionType;
{$endif}
    function  CheckUserKey(Key: PChar; StringBuf: PChar): PChar;

    property IndexFile: TIndexFile read FIndexFile;
  end;

//====================================================================
//  TIndexCursor = class;
//====================================================================
  PIndexPosInfo = ^TIndexPage;

//====================================================================
implementation

//==========================================================
//============ TIndexCursor
//==========================================================
constructor TIndexCursor.Create(DbfIndexFile: TIndexFile);
begin
  inherited Create(DbfIndexFile);

  FIndexFile := DbfIndexFile;
end;

destructor TIndexCursor.Destroy; {override;}
begin
  inherited Destroy;
end;

//procedure TIndexCursor.Insert(RecNo: Integer; Buffer: PChar);
//procedure TIndexCursor.Insert(RecNo: Integer; Buffer: PChar; AllowKeyViolation: Boolean); // 04/13/2011 pb  CR 18918
procedure TIndexCursor.Insert(RecNo: Integer; Buffer: PChar; AUniqueMode: TIndexUniqueType); // 11/04/2011 pb  CR 19723
begin
//TIndexFile(PagedFile).Insert(RecNo,Buffer);
//TIndexFile(PagedFile).Insert(RecNo, Buffer, AllowKeyViolation); // 04/13/2011 pb  CR 18918
  TIndexFile(PagedFile).Insert(RecNo, Buffer, AUniqueMode); // 11/04/2011 pb  CR 19723
  // TODO SET RecNo and Key
end;

procedure TIndexCursor.Update(RecNo: Integer; PrevBuffer, NewBuffer: PChar);
begin
  TIndexFile(PagedFile).Update(RecNo, PrevBuffer, NewBuffer);
end;

procedure TIndexCursor.First;
begin
  TIndexFile(PagedFile).First;
end;

procedure TIndexCursor.Last;
begin
  TIndexFile(PagedFile).Last;
end;

function TIndexCursor.Prev: Boolean;
begin
  Result := TIndexFile(PagedFile).Prev;
end;

function TIndexCursor.Next: Boolean;
begin
  Result := TIndexFile(PagedFile).Next;
end;

function TIndexCursor.GetPhysicalRecNo: Integer;
begin
  Result := TIndexFile(PagedFile).PhysicalRecNo;
end;

procedure TIndexCursor.SetPhysicalRecNo(RecNo: Integer);
begin
  TIndexFile(PagedFile).PhysicalRecNo := RecNo;
end;

//function TIndexCursor.GetSequentialRecordCount: Integer;
function TIndexCursor.GetSequentialRecordCount: TSequentialRecNo; // 08/18/2011 pb  CR 19448
begin
  Result := TIndexFile(PagedFile).SequentialRecordCount;
end;

//function TIndexCursor.GetSequentialRecNo: Integer;
function TIndexCursor.GetSequentialRecNo: TSequentialRecNo; // 08/18/2011 pb  CR 19448
begin
  Result := TIndexFile(PagedFile).SequentialRecNo;
end;

//procedure TIndexCursor.SetSequentialRecNo(RecNo: Integer);
procedure TIndexCursor.SetSequentialRecNo(RecNo: TSequentialRecNo); // 08/18/2011 pb  CR 19448
begin
  TIndexFile(PagedFile).SequentialRecNo := RecNo;
end;

{$ifdef SUPPORT_VARIANTS}

function TIndexCursor.VariantToBuffer(Key: Variant; ABuffer: PChar): TExpressionType;
// assumes ABuffer is large enough ie. at least max key size
var
  currLen: Integer;
begin
  if (TIndexFile(PagedFile).KeyType='N') then
  begin
    PDouble(ABuffer)^ := Key;
    if (TIndexFile(PagedFile).IndexVersion <> xBaseIII) then
    begin
      // make copy of userbcd to buffer
      Move(TIndexFile(PagedFile).PrepareKey(ABuffer, etFloat)[0], ABuffer[0], 11);
    end;
    Result := etInteger;
  end else begin
    StrPLCopy(ABuffer, Key, TIndexFile(PagedFile).KeyLen);
    // we have null-terminated string, pad with spaces if string too short
    currLen := StrLen(ABuffer);
    FillChar(ABuffer[currLen], TIndexFile(PagedFile).KeyLen-currLen, ' ');
    Result := etString;
  end;
end;

{$endif}

function TIndexCursor.CheckUserKey(Key: PChar; StringBuf: PChar): PChar;
var
  keyLen, userLen: Integer;
begin
  // default is to use key
  Result := Key;
  // if key is double, then no check
  if (TIndexFile(PagedFile).KeyType = 'N') then
  begin
    // nothing needs to be done
  end else begin
    // check if string long enough then no copying needed
    userLen := StrLen(Key);
    keyLen := TIndexFile(PagedFile).KeyLen;
    if userLen < keyLen then
    begin
      // copy string
      Move(Key^, StringBuf[0], userLen);
      // add spaces to searchstring
      FillChar(StringBuf[userLen], keyLen - userLen, ' ');
      // set buffer to temporary buffer
      Result := StringBuf;
    end;
  end;
end;

end.

