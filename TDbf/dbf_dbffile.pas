unit dbf_dbffile;

// Modifications by BCC Software
// 12/13/2011 pb  CR 19853- Update FCachedSize when adding "back-link" to a FoxPro file
// 11/17/2011 pb  CR 19755- Flush file buffers when header is corrected on opening
// 11/15/2011 pb  CR 19762- Fix RecordCount in header
// 11/11/2011 pb  CR 19605- Add OnIndexInvalid event 
// 11/10/2011 pb  CR 19607- More detailed progress during bulk load index 
// 11/08/2011 pb  CR 19640- Default to TableLevel 5 instead of 4
// 11/04/2011 pb  CR 19723- Correct key violation handling
// 11/02/2011 pb  CR 19713- Comparison operators should be case sensitive for an index
// 10/28/2011 pb  CR 19699- When Exclusive and appending, defer updating header and EOF terminator until the file is closed
// 10/28/2011 pb  CR 19703- Fix behaviour if BufferAhead and IsSharedAccess
// 09/23/2011 pb  CR 19256- When restructuring table, bulk load indexes
// 08/18/2011 pb  CR 19448- 64-bit sequential record numbers to avoid "Integer overflow"
// 08/18/2011 pb  CR 19418- Do not attempt to write header when read only
// 08/01/2011 pb  CR 19322- When creating FoxPro table, use VerDBF = $30 instead of $02, since $02 is not valid according to the BDE and Visual FoxPro 6.0 itself
// 08/01/2011 pb  CR 19322- When restructuring a table, buffering causes a problem if there is unused space in the header when the table is re-opened
// 08/01/2011 pb  CR 19306- It can build an MDX file for a FoxPro table, so it should open it if present
// 07/27/2011 pb  CR 19293- In TDbfFile.RestructureTable, it is not handling a null value in a blob field correctly
// 07/18/2011 pb  CR 19257- Zap leaves up to 64 KB of data if BufferAhead is True
// 07/06/2011 pb  CR 19188- Recalculate KeyLen, etc. when regenerating indexes
// 06/24/2011 pb  CR 19106- Allow BDE-compatible index versioning to be overriden
// 06/22/2011 pb  CR 19106- Implement DeleteMdxFile, DeleteIndexFile
// 06/16/2011 pb  CR 19060- If there is an exception in Update, make sure that updates to other indexes are rolled back
// 06/14/2011 pb  CR 19115- Use BufferAhead and DisableResyncOnPost when table is exclusive or write locked, to improve performance
// 06/13/2011 pb  CR 18994- Bulk load index to minimize I/O
// 06/02/2011 pb  CR 19096- Use buffering when restructuring or packing table
// 05/27/2011 pb  CR 18759- Locking when adding a record
// 05/16/2011 pb  CR 18797- Allow LockFile/UnlockFile behaviour to be overriden
// 05/12/2011 pb  CR 19008- Option to include deleted records in a distinct index for compatibility with the BDE
// 05/10/2011 pb  CR 18996- CompatibleLockOffset = False uses large lock offset recommended for files of size >= LockStart on WinNT
// 05/05/2011 pb  CR 18916- It may need to use exponential notation in a Numeric (N) or Float (F) field with 0 precision, if the size is insufficient for all digits, eg. 1000000 is "   1E6" in N6.0 field.
// 05/05/2011 pb  CR 18984- Number to string conversion is inconsistent and does not properly take into account the width
// 05/04/2011 pb  CR 18913- In TDbf.CopyFrom, use BufferAhead and defer updating header and EOF terminator until it is done
// 04/26/2011 pb  CR 18707- When adding an index, set the production index flag only if it is a maintained index
// 04/13/2011 pb  CR 18918- Do not remove inserted record from other indexes if there is a key violation during a copy or restructure
// 04/08/2011 pb  CR 18910- Do not corrupt buffer if there is an exception in DbfStrToFloat
// 04/01/2011 pb  CR 18840- Null value in level 7 C field should be NUL characters, not spaces
// 03/25/2011 pb  CR 18820- Only lock a record if the table is shared
// 03/25/2011 pb  CR 18850- Correct writing of EOF character
// 03/11/2011 pb  CR 18782- Do not re-calculate auto-increment values during TDbf.CopyFrom
// 03/10/2011 pb  CR 18709- Progress and cancellation
// 03/04/2011 pb  CR 18759- If BDE has the table locked, TDbf allowed a record to be locked
// 02/18/2011 dhd CR 18611- force the globals to be created in the Main thread to prevent multi-threading problem
// 01/31/2011 dhd CR 18593- Do not update the table header when opening the table without changing anything

interface

{$I dbf_common.inc}

uses
  Classes, SysUtils,
{$ifdef WINDOWS}
  Windows,
{$else}
{$ifdef KYLIX}
  Libc, 
{$endif}
  Types, dbf_wtil,
{$endif}
  Db,
  dbf_common,
  dbf_cursor,
  dbf_pgfile,
  dbf_fields,
  dbf_memo,
  dbf_idxfile;

//====================================================================
//=== Dbf support (first part)
//====================================================================
//  TxBaseVersion = (xUnknown,xClipper,xBaseIII,xBaseIV,xBaseV,xFoxPro,xVisualFoxPro);
//  TPagedFileMode = (pfOpen,pfCreate);
//  TDbfGetMode = (xFirst,xPrev,xCurrent, xNext, xLast);
//  TDbfGetResult = (xOK, xBOF, xEOF, xError);

const
  SProgressPackingRecords = 'Packing records';   // 03/10/2011 pb  CR 18709
  SProgressReadingRecords = 'Reading records';   // 03/10/2011 pb  CR 18709
  SProgressRecordsAppended = 'Records appended'; // 03/10/2011 pb  CR 18709
  SProgressSortingRecords = 'Sorting records'; // 11/10/2011 pb  CR 19607
  SProgressWritingRecords = 'Writing records'; // 11/10/2011 pb  CR 19607

type

//====================================================================
  TDbfIndexMissingEvent = procedure(var DeleteLink: Boolean) of object;
  TDbfIndexInvalidEvent = procedure(Sender: TObject; var Handled, DeleteLink: Boolean) of object; // 11/11/2011 pb  CR 19605
  TUpdateNullField = (unClear, unSet);

//====================================================================
  TDbfGlobals = class;
//====================================================================

  TDbfFile = class(TPagedFile)
  protected
    FMdxFile: TIndexFile;
    FMemoFile: TMemoFile;
    FFieldDefs: TDbfFieldDefs;
    FIndexNames: TStringList;
    FIndexFiles: TList;
    FDbfVersion: TXBaseVersion;
    FPrevBuffer: PChar;
    FDefaultBuffer: PChar;
    FRecordBufferSize: Integer;
    FLockUserLen: DWORD;
    FFileCodePage: Cardinal;
    FUseCodePage: Cardinal;
    FFileLangId: Byte;
    FCountUse: Integer;
    FCurIndex: Integer;
    FForceClose: Boolean;
    FLockField: TDbfFieldDef;
    FNullField: TDbfFieldDef;
    FAutoIncPresent: Boolean;
    FCopyDateTimeAsString: Boolean;
    FDateTimeHandling: TDateTimeHandling;
//  FInCopyFrom: Boolean; // 03/11/2011 pb  CR 18782
    FInBatch: Boolean; // 05/04/2011 pb  CR 18913
    FOnLocaleError: TDbfLocaleErrorEvent;
    FOnIndexMissing: TDbfIndexMissingEvent;
    FOnIndexInvalid: TDbfIndexInvalidEvent; // 11/11/2011 pb  CR 19605
    FOnReadVersion: TDbfReadVersionEvent; // 06/24/2011 pb  CR 19106
    FOnWriteVersion: TDbfWriteVersionEvent; // 06/24/2011 pb  CR 19106
    FCompatibleDistinctIndex: Boolean; // 05/12/2011 pb  CR 19008
    FRecordCountDirty: Boolean; // 10/28/2011 pb  CR 19699 

    function  HasBlob: Boolean;
    function  GetMemoExt: string;

    function GetLanguageId: Integer;
    function GetLanguageStr: string;

    procedure RecordCountFlush; // 10/28/2011 pb  CR 19699
    procedure WriteEOFTerminator; // 05/04/2011 pb  CR 18913
  protected
    procedure ConstructFieldDefs;
    procedure InitDefaultBuffer;
    procedure UpdateNullField(Buffer: Pointer; AFieldDef: TDbfFieldDef; Action: TUpdateNullField);
    procedure WriteLockInfo(Buffer: PChar);

  public
    constructor Create;
    destructor Destroy; override;

    procedure Open;
    procedure Close;
    procedure Zap;
    procedure BatchStart; // 05/04/2011 pb  CR 18913
    procedure BatchUpdate; // 05/04/2011 pb  CR 18913
    procedure BatchFinish; // 05/04/2011 pb  CR 18913
    procedure UpdateLock; // 06/14/2011 pb  CR 19115
    procedure DeleteMdxFile; // 06/22/2011 pb  CR 19106

    procedure FinishCreate(AFieldDefs: TDbfFieldDefs; MemoSize: Integer);
    function GetIndexByName(AIndexName: string): TIndexFile;
    procedure SetRecordSize(NewSize: Integer); override;

    procedure TryExclusive; override;
    procedure EndExclusive; override;
    procedure OpenIndex(IndexName, IndexField: string; CreateIndex: Boolean; Options: TIndexOptions);
    function  DeleteIndex(const AIndexName: string): Boolean;
    procedure CloseIndex(AIndexName: string);
    procedure RepageIndex(AIndexFile: string);
    procedure CompactIndex(AIndexFile: string);
    function  Insert(Buffer: PChar): integer;
    procedure WriteHeader; override;
    procedure ApplyAutoIncToBuffer(DestBuf: PChar);     // dBase7 support. Writeback last next-autoinc value
    procedure FastPackTable;
    procedure RestructureTable(DbfFieldDefs: TDbfFieldDefs; Pack: Boolean);
    procedure Rename(DestFileName: string; NewIndexFileNames: TStrings; DeleteFiles: boolean);
    function  GetFieldInfo(FieldName: string): TDbfFieldDef;
    function  GetFieldData(Column: Integer; DataType: TFieldType; Src,Dst: Pointer; 
      NativeFormat: boolean): Boolean;
    function  GetFieldDataFromDef(AFieldDef: TDbfFieldDef; DataType: TFieldType; 
      Src, Dst: Pointer; NativeFormat: boolean): Boolean;
    procedure SetFieldData(Column: Integer; DataType: TFieldType; Src,Dst: Pointer; NativeFormat: boolean);
    procedure InitRecord(DestBuf: PChar);
//  procedure PackIndex(lIndexFile: TIndexFile; AIndexName: string);
    procedure PackIndex(lIndexFile: TIndexFile; AIndexName: string; CreateIndex: Boolean); // 07/06/2011 pb  CR 19188
    procedure RegenerateIndexes;
//  procedure LockRecord(RecNo: Integer; Buffer: PChar);
    procedure LockRecord(RecNo: Integer; Buffer: PChar; Resync: Boolean); // 10/28/2011 pb  CR 19703
    procedure UnlockRecord(RecNo: Integer; Buffer: PChar);
    procedure RecordDeleted(RecNo: Integer; Buffer: PChar);
    procedure RecordRecalled(RecNo: Integer; Buffer: PChar);
    procedure DeleteIndexFile(AIndexFile: TIndexFile); // 06/22/2011 pb  CR 19106

    property MemoFile: TMemoFile read FMemoFile;
    property FieldDefs: TDbfFieldDefs read FFieldDefs;
    property IndexNames: TStringList read FIndexNames;
    property IndexFiles: TList read FIndexFiles;
    property MdxFile: TIndexFile read FMdxFile;
    property LanguageId: Integer read GetLanguageId;
    property LanguageStr: string read GetLanguageStr;
    property FileCodePage: Cardinal read FFileCodePage;
    property UseCodePage: Cardinal read FUseCodePage write FUseCodePage;
    property FileLangId: Byte read FFileLangId write FFileLangId;
    property DbfVersion: TXBaseVersion read FDbfVersion write FDbfVersion;
    property PrevBuffer: PChar read FPrevBuffer;
    property ForceClose: Boolean read FForceClose;
    property CopyDateTimeAsString: Boolean read FCopyDateTimeAsString write FCopyDateTimeAsString;
    property DateTimeHandling: TDateTimeHandling read FDateTimeHandling write FDateTimeHandling;
//  property InCopyFrom: Boolean write FInCopyFrom; // 03/11/2011 pb  CR 18782
    property CompatibleDistinctIndex: Boolean read FCompatibleDistinctIndex write FCompatibleDistinctIndex; // 05/12/2011 pb  CR 19008

    property OnIndexMissing: TDbfIndexMissingEvent read FOnIndexMissing write FOnIndexMissing;
    property OnIndexInvalid: TDbfIndexInvalidEvent read FOnIndexInvalid write FOnIndexInvalid; // 11/11/2011 pb  CR 19605
    property OnLocaleError: TDbfLocaleErrorEvent read FOnLocaleError write FOnLocaleError;
    property OnReadVersion: TDbfReadVersionEvent read FOnReadVersion write FOnReadVersion; // 06/24/2011 pb  CR 19106
    property OnWriteVersion: TDbfWriteVersionEvent read FOnWriteVersion write FOnWriteVersion; // 06/24/2011 pb  CR 19106
  end;

//====================================================================
  TDbfCursor = class(TVirtualCursor)
  protected
    FPhysicalRecNo: Integer;
  public
    constructor Create(DbfFile: TDbfFile);
    function Next: Boolean; override;
    function Prev: Boolean; override;
    procedure First; override;
    procedure Last; override;

    function GetPhysicalRecNo: Integer; override;
    procedure SetPhysicalRecNo(RecNo: Integer); override;

//  function GetSequentialRecordCount: Integer; override;
    function GetSequentialRecordCount: TSequentialRecNo; override; // 08/18/2011 pb  CR 19448
//  function GetSequentialRecNo: Integer; override;
    function GetSequentialRecNo: TSequentialRecNo; override; // 08/18/2011 pb  CR 19448
//  procedure SetSequentialRecNo(RecNo: Integer); override;
    procedure SetSequentialRecNo(RecNo: TSequentialRecNo); override; // 08/18/2011 pb  CR 19448
  end;

//====================================================================
  TDbfGlobals = class
  protected
    FCodePages: TList;
    FCurrencyAsBCD: Boolean;
    FDefaultOpenCodePage: Integer;
    FDefaultCreateLangId: Byte;
    FUserName: string;
    FUserNameLen: DWORD;
	
    function  GetDefaultCreateCodePage: Integer;
    procedure SetDefaultCreateCodePage(NewCodePage: Integer);
    procedure InitUserName;
  public
    constructor Create;
    destructor Destroy; override;

    function CodePageInstalled(ACodePage: Integer): Boolean;

    property CurrencyAsBCD: Boolean read FCurrencyAsBCD write FCurrencyAsBCD;
    property DefaultOpenCodePage: Integer read FDefaultOpenCodePage write FDefaultOpenCodePage;
    property DefaultCreateCodePage: Integer read GetDefaultCreateCodePage write SetDefaultCreateCodePage;
    property DefaultCreateLangId: Byte read FDefaultCreateLangId write FDefaultCreateLangId;
    property UserName: string read FUserName;
    property UserNameLen: DWORD read FUserNameLen;
  end;

var
  DbfGlobals: TDbfGlobals;

implementation

uses
{$ifndef WINDOWS}
{$ifndef FPC}
  RTLConsts,
{$else}
  BaseUnix,
{$endif}
{$endif}
{$ifdef SUPPORT_MATH_UNIT}
  Math,
{$endif}
  dbf_str, dbf_lang, dbf_prssupp, dbf_prsdef;

const
//sDBF_DEC_SEP = '.'; // 05/05/2011 pb  CR 18984- Replaced with DBF_DECIMAL
  SEOFTerminator = $1A; // 05/04/2011 pb  CR 18913

{$I dbf_struct.inc}

(*
//====================================================================
// International separator
// thanks to Bruno Depero from Italy
// and Andreas Wöllenstein from Denmark
//====================================================================
function DbfStrToFloat(const Src: PChar; const Size: Integer): Extended;
var
  iPos: PChar;
  eValue: extended;
  endChar: Char;
begin
  // temp null-term string
  endChar := (Src + Size)^;
  try
    (Src + Size)^ := #0;
    // we only have to convert if decimal separator different
//  if DecimalSeparator <> sDBF_DEC_SEP then
    if DecimalSeparator <> DBF_DECIMAL then // 05/05/2011 pb  CR 18984
    begin
      // search dec sep
//    iPos := StrScan(Src, sDBF_DEC_SEP);
      iPos := StrScan(Src, DBF_DECIMAL); // 05/05/2011 pb  CR 18984
      // replace
      if iPos <> nil then
        iPos^ := DecimalSeparator;
    end else
      iPos := nil;
    // convert to double
    if TextToFloat(Src, eValue {$ifndef VER1_0}, fvExtended{$endif}) then
      Result := eValue
    else
      Result := 0;
    // restore dec sep
    if iPos <> nil then
//    iPos^ := sDBF_DEC_SEP;
      iPos^ := DBF_DECIMAL; // 05/05/2011 pb  CR 18984
    // restore Char of null-term
  finally // 04/08/2011 pb  CR 18910
    (Src + Size)^ := endChar;
  end;
end;

procedure FloatToDbfStr(const Val: Extended; const Size, Precision: Integer; const Dest: PChar);
var
  Buffer: array [0..24] of Char;
  resLen: Integer;
  iPos: PChar;
begin
  // convert to temporary buffer
  resLen := FloatToText(@Buffer[0], Val, {$ifndef FPC_VERSION}fvExtended,{$endif} ffFixed, Size, Precision);
  // prevent overflow in destination buffer
  if resLen > Size then
    resLen := Size;
  // null-terminate buffer
  Buffer[resLen] := #0;
  // we only have to convert if decimal separator different
  if DecimalSeparator <> sDBF_DEC_SEP then
  begin
    iPos := StrScan(@Buffer[0], DecimalSeparator);
    if iPos <> nil then
      iPos^ := sDBF_DEC_SEP;
  end;
  // fill destination with spaces
  FillChar(Dest^, Size, ' ');
  // now copy right-aligned to destination
  Move(Buffer[0], Dest[Size-resLen], resLen);
end;

function GetIntFromStrLength(Src: Pointer; Size: Integer; Default: Integer): Integer;
var
  endChar: Char;
  Code: Integer;
begin
  // save Char at pos term. null
  endChar := (PChar(Src) + Size)^;
  (PChar(Src) + Size)^ := #0;
  // convert
  Val(PChar(Src), Result, Code);
  // check success
  if Code <> 0 then
    Result := Default;
  // restore prev. ending Char
  (PChar(Src) + Size)^ := endChar;
end;
*)

//====================================================================
// TDbfFile
//====================================================================
constructor TDbfFile.Create;
begin
  // init variables first
  FFieldDefs := TDbfFieldDefs.Create(nil);
  FIndexNames := TStringList.Create;
  FIndexFiles := TList.Create;

  // now initialize inherited
  inherited;
end;

destructor TDbfFile.Destroy;
var
  I: Integer;
begin
  // close file
  Close;

  // free files
  for I := 0 to Pred(FIndexFiles.Count) do
    TPagedFile(FIndexFiles.Items[I]).Free;

  // free lists
  FreeAndNil(FIndexFiles);
  FreeAndNil(FIndexNames);
  FreeAndNil(FFieldDefs);

  // call ancestor
  inherited;
end;

procedure TDbfFile.Open;
var
  lMemoFileName: string;
  lMdxFileName: string;
  MemoFileClass: TMemoFileClass;
  I: Integer;
  deleteLink: Boolean;
  lModified: boolean;
  LangStr: PChar;
  version: byte;
  EOFTerminator: Byte; // 05/04/2011 pb  CR 18913
{$ifdef SUPPORT_INT64}
  lOffset: Int64; // 05/04/2011 pb  CR 18913
{$else}
  lOffset: Integer; // 05/04/2011 pb  CR 18913
{$endif}
  Handled: Boolean; // 11/11/2011 pb  CR 19605
begin
  // check if not already opened
  if not Active then
  begin
    // open requested file
    OpenFile;

    // check if we opened an already existing file
    lModified := false;
    if not FileCreated then
    begin
      HeaderSize := sizeof(rDbfHdr); // temporary
      // OH 2000-11-15 dBase7 support. I build dBase Tables with different
      // BDE dBase Level (1. without Memo, 2. with Memo)
      //                          Header Byte ($1d hex) (29 dec) -> Language driver ID.
      //  $03,$83 xBaseIII        Header Byte $1d=$00, Float -> N($13.$04) DateTime C($1E)
      //  $03,$8B xBaseIV/V       Header Byte $1d=$58, Float -> N($14.$04)
      //  $04,$8C xBaseVII        Header Byte $1d=$00  Float -> O($08)     DateTime @($08)
      //  $03,$F5 FoxPro Level 25 Header Byte $1d=$03, Float -> N($14.$04)
      // Access 97
      //  $03,$83 dBaseIII        Header Byte $1d=$00, Float -> N($13.$05) DateTime D($08)
      //  $03,$8B dBaseIV/V       Header Byte $1d=$00, Float -> N($14.$05) DateTime D($08)
      //  $03,$F5 FoxPro Level 25 Header Byte $1d=$09, Float -> N($14.$05) DateTime D($08)

      version := PDbfHdr(Header)^.VerDBF;
      case (version and $07) of
        $03:
          if LanguageID = 0 then
            FDbfVersion := xBaseIII
          else
//          FDbfVersion := xBaseIV;
            FDbfVersion := xBaseV; // 11/08/2011 pb  CR 19640
        $04:
          FDbfVersion := xBaseVII;
        $02, $05:
          FDbfVersion := xFoxPro;
      else
        // check visual foxpro
        if ((version and $FE) = $30) or (version = $F5) or (version = $FB) then
        begin
          FDbfVersion := xFoxPro;
        end else begin
          // not a valid DBF file
          raise EDbfError.Create(STRING_INVALID_DBF_FILE);
        end;
      end;
      FFieldDefs.DbfVersion := FDbfVersion;
      RecordSize := PDbfHdr(Header)^.RecordSize;
      HeaderSize := PDbfHdr(Header)^.FullHdrSize;
      if (HeaderSize = 0) or (RecordSize = 0) then
      begin
        HeaderSize := 0;
        RecordSize := 0;
        RecordCount := 0;
        FForceClose := true;
        exit;
      end;
      // check if specified recordcount correct
//    if PDbfHdr(Header)^.RecordCount <> RecordCount then
//    begin
        // This message was annoying
        // and was not understood by most people
        // ShowMessage('Invalid Record Count,'+^M+
        //             'RecordCount in Hdr : '+IntToStr(PDbfHdr(Header).RecordCount)+^M+
        //             'expected : '+IntToStr(RecordCount));
//      PDbfHdr(Header)^.RecordCount := RecordCount;
//      lModified := true;
//    end;
      // determine codepage
      if FDbfVersion >= xBaseVII then
      begin
        // cache language str
        LangStr := @PAfterHdrVII(PChar(Header) + SizeOf(rDbfHdr))^.LanguageDriverName;
        // VdBase 7 Language strings
        //  'DBWIN...' -> Charset 1252 (ansi)
        //  'DB999...' -> Code page 999, 9 any digit
        //  'DBHEBREW' -> Code page 1255 ??
        //  'FOX..999' -> Code page 999, 9 any digit
        //  'FOX..WIN' -> Charset 1252 (ansi)
        if (LangStr[0] = 'D') and (LangStr[1] = 'B') then
        begin
          if StrLComp(LangStr+2, 'WIN', 3) = 0 then
            FFileCodePage := 1252
          else
          if StrLComp(LangStr+2, 'HEBREW', 6) = 0 then
          begin
            FFileCodePage := 1255;
          end else begin
//          FFileCodePage := GetIntFromStrLength(LangStr+2, 3, 0);
            StrToInt32Width(Integer(FFileCodePage), LangStr+2, 3, 0); // 05/05/2011 pb  CR 18916
            if (Ord(LangStr[5]) >= Ord('0')) and (Ord(LangStr[5]) <= Ord('9')) then
              FFileCodePage := FFileCodePage * 10 + Ord(LangStr[5]) - Ord('0');
          end;
        end else
        if StrLComp(LangStr, 'FOX', 3) = 0 then
        begin
          if StrLComp(LangStr+5, 'WIN', 3) = 0 then
            FFileCodePage := 1252
          else
//          FFileCodePage := GetIntFromStrLength(LangStr+5, 3, 0)
            StrToInt32Width(Integer(FFileCodePage), LangStr+5, 3, 0); // 05/05/2011 pb  CR 18916
        end else begin
          FFileCodePage := 0;
        end;
        FFileLangId := GetLangId_From_LangName(LanguageStr);
      end else begin
        // FDbfVersion <= xBaseV
        FFileLangId := PDbfHdr(Header)^.Language;
        FFileCodePage := LangId_To_CodePage[FFileLangId];
      end;
      // determine used codepage, if no codepage, then use default codepage
      FUseCodePage := FFileCodePage;
      if FUseCodePage = 0 then
        FUseCodePage := DbfGlobals.DefaultOpenCodePage;
      // get list of fields
      ConstructFieldDefs;
      if PDbfHdr(Header)^.RecordCount <> RecordCount then // 11/15/2011 pb  CR 19762
      begin
        PDbfHdr(Header)^.RecordCount := RecordCount; // 11/15/2011 pb  CR 19762
        lModified := true; // 11/15/2011 pb  CR 19762
      end;
      // open blob file if present
      lMemoFileName := ChangeFileExt(FileName, GetMemoExt);
      if HasBlob then
      begin
        // open blob file
        if not FileExists(lMemoFileName) then
          MemoFileClass := TNullMemoFile
        else if FDbfVersion = xFoxPro then
          MemoFileClass := TFoxProMemoFile
        else
          MemoFileClass := TDbaseMemoFile;
        FMemoFile := MemoFileClass.Create(Self);
        FMemoFile.FileName := lMemoFileName;
        FMemoFile.Mode := Mode;
        FMemoFile.AutoCreate := false;
        FMemoFile.MemoRecordSize := 0;
        FMemoFile.DbfVersion := FDbfVersion;
        FMemoFile.Open;
        // set header blob flag corresponding to field list
        if FDbfVersion <> xFoxPro then
        begin
          if PDbfHdr(Header)^.VerDBF <> (PDbfHdr(Header)^.VerDBF or $80) then // 01/31/2011 dhd CR 18593
          begin
            PDbfHdr(Header)^.VerDBF := PDbfHdr(Header)^.VerDBF or $80;
            lModified := true;
          end;
        end;
      end else
        if FDbfVersion <> xFoxPro then
        begin
          if PDbfHdr(Header)^.VerDBF <> (PDbfHdr(Header)^.VerDBF and $7F) then // 01/31/2011 dhd CR 18593
          begin
            PDbfHdr(Header)^.VerDBF := PDbfHdr(Header)^.VerDBF and $7F;
            lModified := true;
          end
        end;
      // check if mdx flagged
//      if (FDbfVersion <> xFoxPro) and (PDbfHdr(Header)^.MDXFlag <> 0) then
      if PDbfHdr(Header)^.MDXFlag <> 0 then // 08/01/2011 pb  CR 19306
      begin
        // open mdx file if present
        lMdxFileName := ChangeFileExt(FileName, '.mdx');
        if FileExists(lMdxFileName) then
        begin
          // open file
          FMdxFile := TIndexFile.Create(Self);
          FMdxFile.FileName := lMdxFileName;
          FMdxFile.Mode := Mode;
          FMdxFile.AutoCreate := false;
          FMdxFile.OnLocaleError := FOnLocaleError;
          FMdxFile.OnReadVersion := FOnReadVersion; // 06/24/2011 pb  CR 19106
          FMdxFile.OnWriteVersion := FOnWriteVersion; // 06/24/2011 pb  CR 19106
          FMdxFile.CodePage := UseCodePage;
          FMdxFile.CompatibleDistinctIndex := FCompatibleDistinctIndex; // 05/12/2011 pb  CR 19008
          try
            FMdxFile.Open;
          except
            on E: Exception do // 11/11/2011 pb  CR 19605
            begin
              if (E is EDbfIndexError) or (E is EParserException) then
              begin
                FMdxFile.Close;
                Handled := False;
                deleteLink := False;
                if Assigned(FOnIndexInvalid) then
                  FOnIndexInvalid(Self, Handled, deleteLink);
                if not Handled then
                  raise;
                if deleteLink then
                begin
                  PDbfHdr(Header)^.MDXFlag := 0;
                  lModified := true;
                end;
              end
              else
                raise;
            end;
          else
            raise;
          end;
          // is index ready for use?
          if not FMdxFile.ForceClose then
          begin
            FIndexFiles.Add(FMdxFile);
            // get index tag names known
            FMdxFile.GetIndexNames(FIndexNames);
          end else begin
            // asked to close! close file
            FreeAndNil(FMdxFile);
          end;
        end else begin
          if FDbfVersion <> xFoxPro then // 08/01/2011 pb  CR 19306
          begin
            // ask user
            deleteLink := true;
            if Assigned(FOnIndexMissing) then
              FOnIndexMissing(deleteLink);
            // correct flag
            if deleteLink then
            begin
              PDbfHdr(Header)^.MDXFlag := 0;
              lModified := true;
            end else
              FForceClose := true;
          end;
        end;
      end;
    end;

    // record changes
//  if lModified then
    if lModified and (Mode <> pfReadOnly) then // 08/18/2011 pb  CR 19418
    begin
      WriteHeader;
      FlushOS; // 11/17/2011 pb  CR 19755
    end;

    // 05/04/2011 pb  CR 18913 - This avoids unecessary reading if BufferAhead is used
    lOffset:= CalcPageOffset(Succ(RecordCount));
    if Succ(lOffset)=FCachedSize then
      if (ReadBlock(@EOFTerminator, SizeOf(EOFTerminator), lOffset)=SizeOf(EOFTerminator)) and (EOFTerminator=SEOFTerminator) then
        Dec(FCachedSize);

    // open indexes
    for I := 0 to FIndexFiles.Count - 1 do
      TIndexFile(FIndexFiles.Items[I]).Open;
  end;
end;

procedure TDbfFile.Close;
var
  MdxIndex, I: Integer;
begin
  if Active then
  begin
    // close index files first
    MdxIndex := -1;
    for I := 0 to FIndexFiles.Count - 1 do
    begin
      TIndexFile(FIndexFiles.Items[I]).Close;
      if TIndexFile(FIndexFiles.Items[I]) = FMdxFile then
        MdxIndex := I;
    end;
    // free memo file if any
    FreeAndNil(FMemoFile);

    // now we can close physical dbf file
    RecordCountFlush; // 10/28/2011 pb  CR 19699
    CloseFile;

    // free FMdxFile, remove it from the FIndexFiles and Names lists
    if MdxIndex >= 0 then
      FIndexFiles.Delete(MdxIndex);
    I := 0;
    while I < FIndexNames.Count do
    begin
      if FIndexNames.Objects[I] = FMdxFile then
      begin
        FIndexNames.Delete(I);
      end else begin
        Inc(I);
      end;
    end;
    FreeAndNil(FMdxFile);
    FreeMemAndNil(Pointer(FPrevBuffer));
    FreeMemAndNil(Pointer(FDefaultBuffer));

    // reset variables
    FFileLangId := 0;
  end;
end;

procedure TDbfFile.FinishCreate(AFieldDefs: TDbfFieldDefs; MemoSize: Integer);
var
  lFieldDescIII: rFieldDescIII;
  lFieldDescVII: rFieldDescVII;
  lFieldDescPtr: Pointer;
  lFieldDef: TDbfFieldDef;
  lMemoFileName: string;
  I, lFieldOffset, lSize, lPrec: Integer;
  lHasBlob: Boolean;
  lLocaleID: LCID;

begin
  try
    // first reset file
    RecordCount := 0;
    lHasBlob := false;
    // determine codepage & locale
    if FFileLangId = 0 then
      FFileLangId := DbfGlobals.DefaultCreateLangId;
    FFileCodePage := LangId_To_CodePage[FFileLangId];
    lLocaleID := LangId_To_Locale[FFileLangId];
    FUseCodePage := FFileCodePage;
    // prepare header size
    if FDbfVersion = xBaseVII then
    begin
      // version xBaseVII without memo
      HeaderSize := SizeOf(rDbfHdr) + SizeOf(rAfterHdrVII);
      RecordSize := SizeOf(rFieldDescVII);
      FillChar(Header^, HeaderSize, #0);
      PDbfHdr(Header)^.VerDBF := $04;
      // write language string
      StrPLCopy(
        @PAfterHdrVII(PChar(Header)+SizeOf(rDbfHdr))^.LanguageDriverName[32],
        ConstructLangName(FFileCodePage, lLocaleID, false),
        63-32);
      lFieldDescPtr := @lFieldDescVII;
    end else begin
      // version xBaseIII/IV/V without memo
      HeaderSize := SizeOf(rDbfHdr) + SizeOf(rAfterHdrIII);
      RecordSize := SizeOf(rFieldDescIII);
      FillChar(Header^, HeaderSize, #0);
      if FDbfVersion = xFoxPro then
      begin
//      PDbfHdr(Header)^.VerDBF := $02
        PDbfHdr(Header)^.VerDBF := $30 // 08/01/2011 pb  CR 19322
      end else
        PDbfHdr(Header)^.VerDBF := $03;
      // standard language WE, dBase III no language support
      if FDbfVersion = xBaseIII then
        PDbfHdr(Header)^.Language := 0
      else
        PDbfHdr(Header)^.Language := FFileLangId;
      // init field ptr
      lFieldDescPtr := @lFieldDescIII;
    end;
    // begin writing fields
    FFieldDefs.Clear;
    // deleted mark 1 byte
    lFieldOffset := 1;
    for I := 1 to AFieldDefs.Count do
    begin
      lFieldDef := AFieldDefs.Items[I-1];

      // check if datetime conversion
      if FCopyDateTimeAsString then
        if lFieldDef.FieldType = ftDateTime then
        begin
          // convert to string
          lFieldDef.FieldType := ftString;
          lFieldDef.Size := 22;
        end;

      // update source
      lFieldDef.FieldName := AnsiUpperCase(lFieldDef.FieldName);
      lFieldDef.Offset := lFieldOffset;
      lHasBlob := lHasBlob or lFieldDef.IsBlob;

      // apply field transformation tricks
      lSize := lFieldDef.Size;
      lPrec := lFieldDef.Precision;
      if (lFieldDef.NativeFieldType = 'C')
{$ifndef USE_LONG_CHAR_FIELDS}
          and (FDbfVersion = xFoxPro)
{$endif}
                then
      begin
        lPrec := lSize shr 8;
        lSize := lSize and $FF;
      end;

      // update temp field props
      if FDbfVersion = xBaseVII then
      begin
        FillChar(lFieldDescVII, SizeOf(lFieldDescVII), #0);
        StrPLCopy(lFieldDescVII.FieldName, lFieldDef.FieldName, SizeOf(lFieldDescVII.FieldName)-1);
        lFieldDescVII.FieldType := lFieldDef.NativeFieldType;
        lFieldDescVII.FieldSize := lSize;
        lFieldDescVII.FieldPrecision := lPrec;
        lFieldDescVII.NextAutoInc := SwapIntLE(lFieldDef.AutoInc);
        //lFieldDescVII.MDXFlag := ???
      end else begin
        FillChar(lFieldDescIII, SizeOf(lFieldDescIII), #0);
        StrPLCopy(lFieldDescIII.FieldName, lFieldDef.FieldName, SizeOf(lFieldDescIII.FieldName)-1);
        lFieldDescIII.FieldType := lFieldDef.NativeFieldType;
        lFieldDescIII.FieldSize := lSize;
        lFieldDescIII.FieldPrecision := lPrec;
        if FDbfVersion = xFoxPro then
          lFieldDescIII.FieldOffset := SwapIntLE(lFieldOffset);
        if (PDbfHdr(Header)^.VerDBF = $02) and (lFieldDef.NativeFieldType in ['0', 'Y', 'T', 'O', '+']) then
          PDbfHdr(Header)^.VerDBF := $30;
        if (PDbfHdr(Header)^.VerDBF = $30) and (lFieldDef.NativeFieldType = '+') then
          PDbfHdr(Header)^.VerDBF := $31;
      end;

      // update our field list
      with FFieldDefs.AddFieldDef do
      begin
        Assign(lFieldDef);
        Offset := lFieldOffset;
        AutoInc := 0;
      end;

      // save field props
      WriteRecord(I, lFieldDescPtr);
      Inc(lFieldOffset, lFieldDef.Size);
    end;
    // end of header
    WriteChar($0D);
    Inc(FCachedSize); // 06/02/2011 pb  CR 19096

    // write memo bit
    if lHasBlob then
    begin
      if FDbfVersion = xBaseIII then
        PDbfHdr(Header)^.VerDBF := PDbfHdr(Header)^.VerDBF or $80
      else
      if FDbfVersion = xFoxPro then
      begin
        if PDbfHdr(Header)^.VerDBF = $02 then
          PDbfHdr(Header)^.VerDBF := $F5;
      end else
        PDbfHdr(Header)^.VerDBF := PDbfHdr(Header)^.VerDBF or $88;
    end;

    // update header
    PDbfHdr(Header)^.RecordSize := lFieldOffset;
    PDbfHdr(Header)^.FullHdrSize := HeaderSize + RecordSize * AFieldDefs.Count + 1;
    // add empty "back-link" info, whatever it is: 
    { A 263-byte range that contains the backlink, which is the relative path of 
      an associated database (.dbc) file, information. If the first byte is 0x00, 
      the file is not associated with a database. Therefore, database files always 
      contain 0x00. }
    if FDbfVersion = xFoxPro then
    begin
      Inc(PDbfHdr(Header)^.FullHdrSize, 263);
      Inc(FCachedSize, 263); // 12/13/2011 pb  CR 19853
    end;

    // write dbf header to disk
    inherited WriteHeader;
  finally
    RecordSize := PDbfHdr(Header)^.RecordSize;
    HeaderSize := PDbfHdr(Header)^.FullHdrSize;

    // write full header to disk (dbf+fields)
    WriteHeader;
  end;

  if HasBlob and (FMemoFile=nil) then
  begin
    lMemoFileName := ChangeFileExt(FileName, GetMemoExt);
    if FDbfVersion = xFoxPro then
      FMemoFile := TFoxProMemoFile.Create(Self)
    else
      FMemoFile := TDbaseMemoFile.Create(Self);
    FMemoFile.FileName := lMemoFileName;
    FMemoFile.Mode := Mode;
    FMemoFile.AutoCreate := AutoCreate;
    FMemoFile.MemoRecordSize := MemoSize;
    FMemoFile.DbfVersion := FDbfVersion;
    FMemoFile.Open;
  end;
end;

function TDbfFile.HasBlob: Boolean;
var
  I: Integer;
begin
  Result := false;
  for I := 0 to FFieldDefs.Count-1 do
    if FFieldDefs.Items[I].IsBlob then 
      Result := true;
end;

function TDbfFile.GetMemoExt: string;
begin
  if FDbfVersion = xFoxPro then
    Result := '.fpt'
  else
    Result := '.dbt';
end;

procedure TDbfFile.Zap;
begin
  FlushBuffer; // 07/18/2011 pb  CR 19257
  UpdateBufferSize; // 07/18/2011 pb  CR 19257
  // make recordcount zero
  RecordCount := 0;
  // update recordcount
  PDbfHdr(Header)^.RecordCount := RecordCount;
  // update disk header
  WriteHeader;
  FlushHeader; // 07/18/2011 pb  CR 19257
  // update indexes
  RegenerateIndexes;
end;

procedure TDbfFile.BatchStart; // 05/04/2011 pb  CR 18913
begin
// 06/14/2011 pb  CR 19115 - Moved to TDbfFile.UpdateLock
//{$ifdef USE_CACHE}
//  BufferAhead := True;
//{$else}
//  if not NeedLocks then
//    BufferAhead := True;
//{$endif}
  FInBatch := True;
end;

procedure TDbfFile.BatchUpdate; // 05/04/2011 pb  CR 18913
begin
  if not NeedLocks then
//begin
//  WriteEOFTerminator;
//  PDbfHdr(Header)^.RecordCount := RecordCount;
//  WriteHeader;
//end;
    RecordCountFlush; // 10/28/2011 pb  CR 19699
end;

procedure TDbfFile.BatchFinish; // 05/04/2011 pb  CR 18913
begin
  FInBatch := False;
// 06/14/2011 pb  CR 19115 - Moved to TDbfFile.UpdateLock
//{$ifdef USE_CACHE}
//  BufferAhead := False;
//{$else}
//  if not NeedLocks then
//    BufferAhead := False;
//{$endif}
end;

procedure TDbfFile.UpdateLock;
begin
{$ifdef USE_CACHE}
  BufferAhead := True;
{$else}
  BufferAhead := (not IsSharedAccess) or FFileLocked;
{$endif}
end;

procedure TDbfFile.DeleteMdxFile; // 06/22/2011 pb  CR 19106
begin
  PDbfHdr(Header)^.MDXFlag := 0;
  WriteHeader;
  DeleteIndexFile(MdxFile);
end;

procedure TDbfFile.WriteHeader;
var
  SystemTime: TSystemTime;
  lDataHdr: PDbfHdr;
//EofTerminator: Byte;
begin
  if (HeaderSize=0) then
    exit;

  //FillHeader(0);
  lDataHdr := PDbfHdr(Header);
  GetLocalTime(SystemTime);
  lDataHdr^.Year := SystemTime.wYear - 1900;
  lDataHdr^.Month := SystemTime.wMonth;
  lDataHdr^.Day := SystemTime.wDay;
//  lDataHdr.RecordCount := RecordCount;
  inherited WriteHeader;

// 03/25/2011 pb  CR 18850
// When updating the header only, this has no useful purpose.
// When modifying a record, this has no useful purpose and forces it to seek to the end of file, which is inefficient.
// When inserting a record, this is overwritten by a call to WriteRecord, it needs to happen after the call.
//EofTerminator := $1A;
//WriteBlock(@EofTerminator, 1, CalcPageOffset(RecordCount+1));
end;

procedure TDbfFile.ConstructFieldDefs;
var
  {lColumnCount,}lHeaderSize,lFieldSize: Integer;
  lPropHdrOffset, lFieldOffset: Integer;
  lFieldDescIII: rFieldDescIII;
  lFieldDescVII: rFieldDescVII;
  lFieldPropsHdr: rFieldPropsHdr;
  lStdProp: rStdPropEntry;
  TempFieldDef: TDbfFieldDef;
  lSize,lPrec,I, lColumnCount: Integer;
  lAutoInc: Cardinal;
  dataPtr: PChar;
  lNativeFieldType: Char;
  lFieldName: string;
  lCanHoldNull: boolean;
  lCurrentNullPosition: integer;
begin
  FFieldDefs.Clear;
  if DbfVersion >= xBaseVII then
  begin
    lHeaderSize := SizeOf(rAfterHdrVII) + SizeOf(rDbfHdr);
    lFieldSize := SizeOf(rFieldDescVII);
  end else begin
    lHeaderSize := SizeOf(rAfterHdrIII) + SizeOf(rDbfHdr);
    lFieldSize := SizeOf(rFieldDescIII);
  end;
  HeaderSize := lHeaderSize;
  RecordSize := lFieldSize;

  FLockField := nil;
  FNullField := nil;
  FAutoIncPresent := false;
  lColumnCount := (PDbfHdr(Header)^.FullHdrSize - lHeaderSize) div lFieldSize;
  lFieldOffset := 1;
  lAutoInc := 0;
  I := 1;
  lCurrentNullPosition := 0;
  lCanHoldNull := false;
  try
    // there has to be minimum of one field
    repeat
      // version field info?
      if FDbfVersion >= xBaseVII then
      begin
        ReadRecord(I, @lFieldDescVII);
        lFieldName := AnsiUpperCase(PChar(@lFieldDescVII.FieldName[0]));
        lSize := lFieldDescVII.FieldSize;
        lPrec := lFieldDescVII.FieldPrecision;
        lNativeFieldType := lFieldDescVII.FieldType;
        lAutoInc := SwapIntLE(lFieldDescVII.NextAutoInc);
        if lNativeFieldType = '+' then
          FAutoIncPresent := true;
      end else begin
        ReadRecord(I, @lFieldDescIII);
        lFieldName := AnsiUpperCase(PChar(@lFieldDescIII.FieldName[0]));
        lSize := lFieldDescIII.FieldSize;
        lPrec := lFieldDescIII.FieldPrecision;
        lNativeFieldType := lFieldDescIII.FieldType;
        lCanHoldNull := (FDbfVersion = xFoxPro) and 
          ((lFieldDescIII.FoxProFlags and $2) <> 0) and
          (lFieldName <> '_NULLFLAGS');
      end;

      // apply field transformation tricks
      if (lNativeFieldType = 'C') 
{$ifndef USE_LONG_CHAR_FIELDS}
          and (FDbfVersion = xFoxPro) 
{$endif}
                then
      begin
        lSize := lSize + lPrec shl 8;
        lPrec := 0;
      end;

      // add field
      TempFieldDef := FFieldDefs.AddFieldDef;
      with TempFieldDef do
      begin
        FieldName := lFieldName;
        Offset := lFieldOffset;
        Size := lSize;
        Precision := lPrec;
        AutoInc := lAutoInc;
        NativeFieldType := lNativeFieldType;
        if lCanHoldNull then
        begin
          NullPosition := lCurrentNullPosition;
          inc(lCurrentNullPosition);
        end else
          NullPosition := -1;
      end;

      // check valid field:
      //  1) non-empty field name
      //  2) known field type
      //  {3) no changes have to be made to precision or size}
      if (Length(lFieldName) = 0) or (TempFieldDef.FieldType = ftUnknown) then
        raise EDbfError.Create(STRING_INVALID_DBF_FILE);

      // determine if lock field present, if present, then store additional info
      if lFieldName = '_DBASELOCK' then
      begin
        FLockField := TempFieldDef;
        FLockUserLen := lSize - 8;
        if FLockUserLen > DbfGlobals.UserNameLen then
          FLockUserLen := DbfGlobals.UserNameLen;
      end else
      if UpperCase(lFieldName) = '_NULLFLAGS' then
        FNullField := TempFieldDef;

      // goto next field
      Inc(lFieldOffset, lSize);
      Inc(I);

      // continue until header termination character found
      // or end of header reached
    until (I > lColumnCount) or (ReadChar = $0D);

    // test if not too many fields
    if FFieldDefs.Count >= 4096 then
      raise EDbfError.CreateFmt(STRING_INVALID_FIELD_COUNT, [FFieldDefs.Count]);

    // do not check FieldOffset = PDbfHdr(Header).RecordSize because additional 
    // data could be present in record

    // get current position
    lPropHdrOffset := Stream.Position;

    // dBase 7 -> read field properties, test if enough space, maybe no header
    if (FDbfVersion = xBaseVII) and (lPropHdrOffset + Sizeof(lFieldPropsHdr) <
            PDbfHdr(Header)^.FullHdrSize) then
    begin
      // read in field properties header
      ReadBlock(@lFieldPropsHdr, SizeOf(lFieldPropsHdr), lPropHdrOffset);
      // read in standard properties
      lFieldOffset := lPropHdrOffset + lFieldPropsHdr.StartStdProps;
      for I := 0 to lFieldPropsHdr.NumStdProps - 1 do
      begin
        // read property data
        ReadBlock(@lStdProp, SizeOf(lStdProp), lFieldOffset+I*SizeOf(lStdProp));
        // is this a constraint?
        if lStdProp.FieldOffset = 0 then
        begin
          // this is a constraint...not implemented
        end else if lStdProp.FieldOffset <= FFieldDefs.Count then begin
          // get fielddef for this property
          TempFieldDef := FFieldDefs.Items[lStdProp.FieldOffset-1];
          // allocate space to store data
          TempFieldDef.AllocBuffers;
          // dataPtr = nil -> no data to retrieve
          dataPtr := nil;
          // store data
          case lStdProp.PropType of
            FieldPropType_Required: TempFieldDef.Required := true;
            FieldPropType_Default:
              begin
                dataPtr := TempFieldDef.DefaultBuf;
                TempFieldDef.HasDefault := true;
              end;
            FieldPropType_Min:
              begin
                dataPtr := TempFieldDef.MinBuf;
                TempFieldDef.HasMin := true;
              end;
            FieldPropType_Max:
              begin
                dataPtr := TempFieldDef.MaxBuf;
                TempFieldDef.HasMax := true;
              end;
          end;
          // get data for this property
          if dataPtr <> nil then
            ReadBlock(dataPtr, lStdProp.DataSize, lPropHdrOffset + lStdProp.DataOffset);
        end;
      end;
      // read custom properties...not implemented
      // read RI properties...not implemented
    end;
  finally
    HeaderSize := PDbfHdr(Header)^.FullHdrSize;
    RecordSize := PDbfHdr(Header)^.RecordSize;
  end;
end;

function TDbfFile.GetLanguageId: Integer;
begin
  Result := PDbfHdr(Header)^.Language;
end;

function TDbfFile.GetLanguageStr: String;
begin
  if FDbfVersion >= xBaseVII then
    Result := PAfterHdrVII(PChar(Header) + SizeOf(rDbfHdr))^.LanguageDriverName;
end;

procedure TDbfFile.RecordCountFlush; // 10/28/2011 pb  CR 19699
begin
  if FRecordCountDirty then
  begin
    WriteEOFTerminator;
    PDbfHdr(Header)^.RecordCount := RecordCount;
    WriteHeader;
    FRecordCountDirty := False;
  end;
end;

procedure TDbfFile.WriteEOFTerminator; // 05/04/2011 pb  CR 18913
var
  EOFTerminator: Byte;
begin
  EOFTerminator := SEOFTerminator;
  WriteBlock(@EOFTerminator, 1, CalcPageOffset(RecordCount+1));
end;

{
  I fill the holes with the last records.
  now we can do an 'in-place' pack
}
procedure TDbfFile.FastPackTable;
var
  iDel,iNormal: Integer;
  pDel,pNormal: PChar;

  function FindFirstDel: Boolean;
  begin
    while iDel<=iNormal do
    begin
      ReadRecord(iDel, pDel);
      if (PChar(pDel)^ <> ' ') then
      begin
        Result := true;
        exit;
      end;
      Inc(iDel);
    end;
    Result := false;
  end;

  function FindLastNormal: Boolean;
  begin
    while iNormal>=iDel do
    begin
      ReadRecord(iNormal, pNormal);
      if (PChar(pNormal)^= ' ') then
      begin
        Result := true;
        exit;
      end;
      dec(iNormal);
    end;
    Result := false;
  end;

begin
  if RecordSize < 1 then Exit;

  GetMem(pNormal, RecordSize);
  GetMem(pDel, RecordSize);
  try
    iDel := 1;
    iNormal := RecordCount;

    while FindFirstDel do
    begin
      // iDel is definitely deleted
      if FindLastNormal then
      begin
        // but is not anymore
        WriteRecord(iDel, pNormal);
        PChar(pNormal)^ := '*';
        WriteRecord(iNormal, pNormal);
      end else begin
        // Cannot found a record after iDel so iDel must be deleted
        dec(iDel);
        break;
      end;
    end;
    // FindFirstDel failed means than iDel is full
    RecordCount := iDel;
    RegenerateIndexes;
    // Pack Memofields
  finally
    FreeMem(pNormal);
    FreeMem(pDel);
  end;
end;

procedure TDbfFile.Rename(DestFileName: string; NewIndexFileNames: TStrings; DeleteFiles: boolean);
var
  lIndexFileNames: TStrings;
  lIndexFile: TIndexFile;
  NewBaseName: string;
  I: integer;
begin
  // get memory for index file list
  lIndexFileNames := TStringList.Create;
  try 
    // save index filenames
    for I := 0 to FIndexFiles.Count - 1 do
    begin
      lIndexFile := TIndexFile(IndexFiles[I]);
      lIndexFileNames.Add(lIndexFile.FileName);
      // prepare changing the dbf file name, needs changes in index files
      lIndexFile.PrepareRename(NewIndexFileNames[I]);
    end;

    // close file
    Close;

    if DeleteFiles then
    begin
      SysUtils.DeleteFile(DestFileName);
      SysUtils.DeleteFile(ChangeFileExt(DestFileName, GetMemoExt));
    end else begin
      I := 0;
      FindNextName(DestFileName, NewBaseName, I);
      SysUtils.RenameFile(DestFileName, NewBaseName);
      SysUtils.RenameFile(ChangeFileExt(DestFileName, GetMemoExt), 
        ChangeFileExt(NewBaseName, GetMemoExt));
    end;
    // delete old index files
    for I := 0 to NewIndexFileNames.Count - 1 do
      SysUtils.DeleteFile(NewIndexFileNames.Strings[I]);
    // rename the new dbf files
    SysUtils.RenameFile(FileName, DestFileName);
    SysUtils.RenameFile(ChangeFileExt(FileName, GetMemoExt), 
      ChangeFileExt(DestFileName, GetMemoExt));
    // rename new index files
    for I := 0 to NewIndexFileNames.Count - 1 do
      SysUtils.RenameFile(lIndexFileNames.Strings[I], NewIndexFileNames.Strings[I]);
  finally
    lIndexFileNames.Free;
  end;  
end;

type
  TRestructFieldInfo = record
    SourceOffset: Integer;
    DestOffset: Integer;
    Size: Integer;
  end;

  { assume nobody has more than 8192 fields, otherwise possibly range check error }
  PRestructFieldInfo = ^TRestructFieldInfoArray;
  TRestructFieldInfoArray = array[0..8191] of TRestructFieldInfo;

procedure TDbfFile.RestructureTable(DbfFieldDefs: TDbfFieldDefs; Pack: Boolean);
var
  DestDbfFile: TDbfFile;
  TempIndexDef: TDbfIndexDef;
  TempIndexFile: TIndexFile;
  DestFieldDefs: TDbfFieldDefs;
  TempDstDef, TempSrcDef: TDbfFieldDef;
  OldIndexFiles: TStrings;
  IndexName, NewBaseName: string;
  I, lRecNo, lFieldNo, lFieldSize, lBlobPageNo, lWRecNo, srcOffset, dstOffset: Integer;
  pBuff, pDestBuff: PChar;
  RestructFieldInfo: PRestructFieldInfo;
  BlobStream: TMemoryStream;
  last: Integer; // 03/10/2011 pb  CR 18709
begin
  // nothing to do?
  if (RecordSize < 1) or ((DbfFieldDefs = nil) and not Pack) then
    exit;

  // if no exclusive access, terrible things can happen!
  CheckExclusiveAccess;

  // make up some temporary filenames
  lRecNo := 0;
  FindNextName(FileName, NewBaseName, lRecNo);

  // select final field definition list
  if DbfFieldDefs = nil then
  begin
    DestFieldDefs := FFieldDefs;
  end else begin
    DestFieldDefs := DbfFieldDefs;
    // copy autoinc values
    for I := 0 to DbfFieldDefs.Count - 1 do
    begin
      lFieldNo := DbfFieldDefs.Items[I].CopyFrom;
      if (lFieldNo >= 0) and (lFieldNo < FFieldDefs.Count) then
        DbfFieldDefs.Items[I].AutoInc := FFieldDefs.Items[lFieldNo].AutoInc;
    end;
  end;

  // create temporary dbf
  DestDbfFile := TDbfFile.Create;
  DestDbfFile.FileName := NewBaseName;
  DestDbfFile.AutoCreate := true;
  DestDbfFile.Mode := pfExclusiveCreate;
  DestDbfFile.OnIndexMissing := FOnIndexMissing;
  DestDbfFile.OnLocaleError := FOnLocaleError;
  DestDbfFile.DbfVersion := FDbfVersion;
  DestDbfFile.FileLangId := FileLangId;
  DestDbfFile.Open;
  // create dbf header
  if FMemoFile <> nil then
    DestDbfFile.FinishCreate(DestFieldDefs, FMemoFile.RecordSize)
  else
    DestDbfFile.FinishCreate(DestFieldDefs, 512);
  DestDbfFile.UpdateLock; // 06/14/2011 pb  CR 19115

  // adjust size and offsets of fields
  GetMem(RestructFieldInfo, sizeof(TRestructFieldInfo)*DestFieldDefs.Count);
  for lFieldNo := 0 to DestFieldDefs.Count - 1 do
  begin
    TempDstDef := DestFieldDefs.Items[lFieldNo];
    if TempDstDef.CopyFrom >= 0 then
    begin
      TempSrcDef := FFieldDefs.Items[TempDstDef.CopyFrom];
      if TempDstDef.NativeFieldType in ['F', 'N'] then
      begin
        // get minimum field length
        lFieldSize := Min(TempSrcDef.Precision, TempDstDef.Precision) +
          Min(TempSrcDef.Size - TempSrcDef.Precision,
            TempDstDef.Size - TempDstDef.Precision);
        // if one has dec separator, but other not, we lose one digit
        if (TempDstDef.Precision > 0) xor
          ((TempSrcDef.NativeFieldType in ['F', 'N']) and (TempSrcDef.Precision > 0)) then
          Dec(lFieldSize);
        // should not happen, but check nevertheless (maybe corrupt data)
        if lFieldSize < 0 then
          lFieldSize := 0;
        srcOffset := TempSrcDef.Size - TempSrcDef.Precision -
          (TempDstDef.Size - TempDstDef.Precision);
        if srcOffset < 0 then
        begin
          dstOffset := -srcOffset;
          srcOffset := 0;
        end else begin
          dstOffset := 0;
        end;
      end else begin
        lFieldSize := Min(TempSrcDef.Size, TempDstDef.Size);
        srcOffset := 0;
        dstOffset := 0;
      end;
      with RestructFieldInfo[lFieldNo] do
      begin
        Size := lFieldSize;
        SourceOffset := TempSrcDef.Offset + srcOffset;
        DestOffset := TempDstDef.Offset + dstOffset;
      end;
    end;
  end;

  // add indexes
  TempIndexDef := TDbfIndexDef.Create(nil);
  for I := 0 to FIndexNames.Count - 1 do
  begin
    // get length of extension -> determines MDX or NDX
    IndexName := FIndexNames.Strings[I];
    TempIndexFile := TIndexFile(FIndexNames.Objects[I]);
    TempIndexFile.GetIndexInfo(IndexName, TempIndexDef);
    if Length(ExtractFileExt(IndexName)) > 0 then
    begin
      // NDX index, get unique file name
      lRecNo := 0;
      FindNextName(IndexName, IndexName, lRecNo);
    end;
    // add this index
    DestDbfFile.OpenIndex(IndexName, TempIndexDef.SortField, true, TempIndexDef.Options);
  end;
  TempIndexDef.Free;

  // get memory for record buffers
  GetMem(pBuff, RecordSize);
  BlobStream := TMemoryStream.Create;
  OldIndexFiles := TStringList.Create;
  // if restructure, we need memory for dest buffer, otherwise use source
  if DbfFieldDefs = nil then
    pDestBuff := pBuff
  else
    GetMem(pDestBuff, DestDbfFile.RecordSize);

  // let the games begin!
  try
    DestDbfFile.BatchStart; // 06/02/2011 pb  CR 19096
    try
//{$ifdef USE_CACHE}
//    BufferAhead := true;
//    DestDbfFile.BufferAhead := true;
//{$endif}
      lWRecNo := 1;
      last := RecordCount; // 03/10/2011 pb  CR 18709
      if Pack then
        DoProgress(0, last, SProgressPackingRecords); // 03/10/2011 pb  CR 18709
//      for lRecNo := 1 to RecordCount do
      for lRecNo := 1 to last do // 03/10/2011 pb  CR 18709
      begin
        // read record from original dbf
        ReadRecord(lRecNo, pBuff);
        // copy record?
        if (pBuff^ <> '*') or not Pack then
        begin
          // if restructure, initialize dest
          if DbfFieldDefs <> nil then
          begin
            DestDbfFile.InitRecord(pDestBuff);
            // copy deleted mark (the first byte)
            pDestBuff^ := pBuff^;
          end;

          if (DbfFieldDefs <> nil) or (FMemoFile <> nil) then
          begin
            // copy fields
            for lFieldNo := 0 to DestFieldDefs.Count-1 do
            begin
              TempDstDef := DestFieldDefs.Items[lFieldNo];
              // handle blob fields differently
              // don't try to copy new blob fields!
              // DbfFieldDefs = nil -> pack only
              // TempDstDef.CopyFrom >= 0 -> copy existing (blob) field
              if TempDstDef.IsBlob and ((DbfFieldDefs = nil) or (TempDstDef.CopyFrom >= 0)) then
              begin
                // get current blob blockno
//              if not GetFieldData(lFieldNo, ftInteger, pBuff, @lBlobPageNo, false);
                // valid blockno read?
//              if lBlobPageNo > 0 then
                if GetFieldData(lFieldNo, ftInteger, pBuff, @lBlobPageNo, false) and (lBlobPageNo > 0) then // 07/27/2011 pb  CR 19293
                begin
                  BlobStream.Clear;
                  FMemoFile.ReadMemo(lBlobPageNo, BlobStream);
                  BlobStream.Position := 0;
                  // always append
                  DestDbfFile.FMemoFile.WriteMemo(lBlobPageNo, 0, BlobStream);
                  // write new blockno
                  DestDbfFile.SetFieldData(lFieldNo, ftInteger, @lBlobPageNo, pDestBuff, false); // 07/27/2011 pb  CR 19293
                end;
//              // write new blockno
//              DestDbfFile.SetFieldData(lFieldNo, ftInteger, @lBlobPageNo, pDestBuff, false);
              end else if (DbfFieldDefs <> nil) and (TempDstDef.CopyFrom >= 0) then
              begin
                // copy content of field
                with RestructFieldInfo[lFieldNo] do
                  Move(pBuff[SourceOffset], pDestBuff[DestOffset], Size);
              end;
            end;
          end;

          // write record
          DestDbfFile.WriteRecord(lWRecNo, pDestBuff);
          // update indexes
// 09/23/2011 pb  CR 19256- Do not incrementally build indexes, it is slow
//        for I := 0 to DestDbfFile.IndexFiles.Count - 1 do
//          TIndexFile(DestDbfFile.IndexFiles.Items[I]).Insert(lWRecNo, pDestBuff);
//          TIndexFile(DestDbfFile.IndexFiles.Items[I]).Insert(lWRecNo, pDestBuff, True); // 04/13/2011 pb  CR 18918

          // go to next record
          Inc(lWRecNo);
        end;
        if Pack then
          DoProgress(lRecNo, last, SProgressPackingRecords); // 03/10/2011 pb  CR 18709
      end;

//{$ifdef USE_CACHE}
//    BufferAhead := false;
//    DestDbfFile.BufferAhead := false;
//{$endif}
      BufferAhead := false; // 08/01/2011 pb  CR 19322

      // save index filenames
      for I := 0 to FIndexFiles.Count - 1 do
        OldIndexFiles.Add(TIndexFile(IndexFiles[I]).FileName);

      // close dbf
      Close;

      // if restructure -> rename the old dbf files
      // if pack only -> delete the old dbf files
      DestDbfFile.Rename(FileName, OldIndexFiles, DbfFieldDefs = nil);
    
      // we have to reinit fielddefs if restructured
      Open;

      // crop deleted records
      RecordCount := lWRecNo - 1;
      // update date/time stamp, recordcount
//    PDbfHdr(Header)^.RecordCount := RecordCount;
//    WriteHeader;
      FRecordCountDirty := True; // 10/28/2011 pb  CR 19699
      BatchUpdate; // 06/02/2011 pb  CR 19096
    finally
      DestDbfFile.BatchFinish; // 06/02/2011 pb  CR 19096
    end;
  finally
    // close temporary file
    FreeAndNil(DestDbfFile);
    // free mem
    FreeAndNil(OldIndexFiles);
    FreeMem(pBuff);
    FreeAndNil(BlobStream);
    FreeMem(RestructFieldInfo);
    if DbfFieldDefs <> nil then
      FreeMem(pDestBuff);
  end;
  RegenerateIndexes; // 09/23/2011 pb  CR 19256- Bulk load indexes
end;

procedure TDbfFile.RegenerateIndexes;
var
  lIndexNo: Integer;
begin
  // recreate every index in every file
  for lIndexNo := 0 to FIndexFiles.Count-1 do
  begin
//  PackIndex(TIndexFile(FIndexFiles.Items[lIndexNo]), EmptyStr);
    PackIndex(TIndexFile(FIndexFiles.Items[lIndexNo]), EmptyStr, False); // 07/06/2011 pb  CR 19188
  end;
end;

function TDbfFile.GetFieldInfo(FieldName: string): TDbfFieldDef;
var
  I: Integer;
  lfi: TDbfFieldDef;
begin
  FieldName := AnsiUpperCase(FieldName);
  for I := 0 to FFieldDefs.Count-1 do
  begin
    lfi := TDbfFieldDef(FFieldDefs.Items[I]);
    if lfi.fieldName = FieldName then
    begin
      Result := lfi;
      exit;
    end;
  end;
  Result := nil;
end;

// NOTE: Dst may be nil!
function TDbfFile.GetFieldData(Column: Integer; DataType: TFieldType; 
  Src, Dst: Pointer; NativeFormat: boolean): Boolean;
var
  TempFieldDef: TDbfFieldDef;
begin
  TempFieldDef := TDbfFieldDef(FFieldDefs.Items[Column]);
  Result := GetFieldDataFromDef(TempFieldDef, DataType, Src, Dst, NativeFormat);
end;

// NOTE: Dst may be nil!
function TDbfFile.GetFieldDataFromDef(AFieldDef: TDbfFieldDef; DataType: TFieldType; 
  Src, Dst: Pointer; NativeFormat: boolean): Boolean;
var
  FieldOffset, FieldSize: Integer;
//  s: string;
  ldd, ldm, ldy, lth, ltm, lts: Integer;
  date: TDateTime;
  timeStamp: TTimeStamp;
  asciiContents: boolean;
  IntValue: Integer; // 05/05/2011 pb  CR 18916
  FloatValue: Extended; // 05/05/2011 pb  CR 18916

(*
{$ifdef SUPPORT_INT64}
  function GetInt64FromStrLength(Src: Pointer; Size: Integer; Default: Int64): Int64;
  var
    endChar: Char;
    Code: Integer;
  begin
    // save Char at pos term. null
    endChar := (PChar(Src) + Size)^;
    (PChar(Src) + Size)^ := #0;
    // convert
    Val(PChar(Src), Result, Code);
    // check success
    if Code <> 0 then Result := Default;
    // restore prev. ending Char
    (PChar(Src) + Size)^ := endChar;
  end;
{$endif}
*)

  procedure CorrectYear(var wYear: Integer);
  var wD, wM, wY, CenturyBase: Word;

{$ifndef DELPHI_5}
  // Delphi 3 standard-behavior no change possible
  const TwoDigitYearCenturyWindow= 0;
{$endif}

  begin
     if wYear >= 100 then
       Exit;
     DecodeDate(Date, wY, wm, wD);
     // use Delphi-Date-Window
     CenturyBase := wY{must be CurrentYear} - TwoDigitYearCenturyWindow;
     Inc(wYear, CenturyBase div 100 * 100);
     if (TwoDigitYearCenturyWindow > 0) and (wYear < CenturyBase) then
        Inc(wYear, 100);
  end;

  procedure SaveDateToDst;
  begin
    if not NativeFormat then
    begin
      // Delphi 5 requests a TDateTime
      PDateTime(Dst)^ := date;
    end else begin
      // Delphi 3 and 4 request a TDateTimeRec
      //  date is TTimeStamp.date
      //  datetime = msecs == BDE timestamp as we implemented it
      if DataType = ftDateTime then
      begin
        PDateTimeRec(Dst)^.DateTime := date;
      end else begin
        PLongInt(Dst)^ := DateTimeToTimeStamp(date).Date;
      end;
    end;
  end;

begin
  // test if non-nil source (record buffer)
  if Src = nil then
  begin
    Result := false;
    exit;
  end;

  // check Dst = nil, called with dst = nil to check empty field
  if (FNullField <> nil) and (Dst = nil) and (AFieldDef.NullPosition >= 0) then
  begin
    // go to byte with null flag of this field
    Src := PChar(Src) + FNullField.Offset + (AFieldDef.NullPosition shr 3);
    Result := (PByte(Src)^ and (1 shl (AFieldDef.NullPosition and $7))) <> 0;
    exit;
  end;
  
  FieldOffset := AFieldDef.Offset;
  FieldSize := AFieldDef.Size;
  Src := PChar(Src) + FieldOffset;
  asciiContents := false;
  Result := true;
  // field types that are binary and of which the fieldsize should not be truncated
  case AFieldDef.NativeFieldType of
    '+', 'I':
      begin
        if FDbfVersion <> xFoxPro then
        begin
          Result := PDWord(Src)^ <> 0;
          if Result and (Dst <> nil) then
          begin
            PDWord(Dst)^ := SwapIntBE(PDWord(Src)^);
            if Result then
              PInteger(Dst)^ := Integer(PDWord(Dst)^ xor $80000000);
          end;
        end else begin
          Result := true;
          if Dst <> nil then
            PInteger(Dst)^ := SwapIntLE(PInteger(Src)^);
        end;
      end;
    'O':
      begin
{$ifdef SUPPORT_INT64}
        Result := PInt64(Src)^ <> 0;
        if Result and (Dst <> nil) then
        begin
          SwapInt64BE(Src, Dst);
          if PInt64(Dst)^ > 0 then
            PInt64(Dst)^ := not PInt64(Dst)^
          else
            PDouble(Dst)^ := PDouble(Dst)^ * -1;
        end;
{$endif}
      end;
    '@':
      begin
        Result := (PInteger(Src)^ <> 0) and (PInteger(PChar(Src)+4)^ <> 0);
        if Result and (Dst <> nil) then
        begin
          SwapInt64BE(Src, Dst);
          if FDateTimeHandling = dtBDETimeStamp then
            date := BDETimeStampToDateTime(PDouble(Dst)^)
          else
            date := PDateTime(Dst)^;
          SaveDateToDst;
        end;
      end;
    'T':
      begin
        // all binary zeroes -> empty datetime
{$ifdef SUPPORT_INT64}        
        Result := PInt64(Src)^ <> 0;
{$else}        
        Result := (PInteger(Src)^ <> 0) or (PInteger(PChar(Src)+4)^ <> 0);
{$endif}        
        if Result and (Dst <> nil) then
        begin
          timeStamp.Date := SwapIntLE(PInteger(Src)^) - JulianDateDelta;
          timeStamp.Time := SwapIntLE(PInteger(PChar(Src)+4)^);
          date := TimeStampToDateTime(timeStamp);
          SaveDateToDst;
        end;
      end;
    'Y':
      begin
{$ifdef SUPPORT_INT64}
        Result := true;
        if Dst <> nil then
        begin
          PInt64(Dst)^ := SwapIntLE(PInt64(Src)^);
          if DataType = ftCurrency then
            PDouble(Dst)^ := PInt64(Dst)^ / 10000.0;
        end;
{$endif}
      end;
    'B':    // foxpro double
      begin
        if FDbfVersion = xFoxPro then
        begin
          Result := true;
          if Dst <> nil then
            PInt64(Dst)^ := SwapIntLE(PInt64(Src)^);
        end else
          asciiContents := true;
      end;
    'M':
      begin
        if FieldSize = 4 then
        begin
          Result := PInteger(Src)^ <> 0;
          if Dst <> nil then
            PInteger(Dst)^ := SwapIntLE(PInteger(Src)^);
        end else
          asciiContents := true;
      end;
  else
    asciiContents := true;
  end;
  if asciiContents then
  begin
    //    SetString(s, PChar(Src) + FieldOffset, FieldSize );
    //    s := {TrimStr(s)} TrimRight(s);
    // truncate spaces at end by shortening fieldsize
    //while (FieldSize > 0) and ((PChar(Src) + FieldSize - 1)^ = ' ') do
    // 03/31/2011 pb  CR 18840- Not recognizing NULL value in a level 7 C field
    while (FieldSize > 0) and (((PChar(Src) + FieldSize - 1)^ = ' ') or ((PChar(Src) + FieldSize - 1)^ = #0)) do
      dec(FieldSize);
    // if not string field, truncate spaces at beginning too
    if DataType <> ftString then
      while (FieldSize > 0) and (PChar(Src)^ = ' ') do
      begin
        inc(PChar(Src));
        dec(FieldSize);
      end;
    // return if field is empty
    Result := FieldSize > 0;
    if Result and (Dst <> nil) then     // data not needed if Result= false or Dst=nil
      case DataType of
      ftBoolean:
        begin
          // in DBase- FileDescription lowercase t is allowed too
          // with asking for Result= true s must be longer then 0
          // else it happens an AV, maybe field is NULL
          if (PChar(Src)^ = 'T') or (PChar(Src)^ = 't') then
            PWord(Dst)^ := 1
          else
            PWord(Dst)^ := 0;
        end;
      ftSmallInt:
//      PSmallInt(Dst)^ := GetIntFromStrLength(Src, FieldSize, 0);
      begin
        Result := StrToInt32Width(IntValue, Src, FieldSize, 0); // 05/05/2011 pb  CR 18916
        if Result then
          Result := (IntValue>=Low(SmallInt)) and (IntValue<=High(SmallInt));
        if Result then
          PSmallInt(Dst)^ := IntValue;
      end;
{$ifdef SUPPORT_INT64}
      ftLargeInt:
//      PLargeInt(Dst)^ := GetInt64FromStrLength(Src, FieldSize, 0);
        Result := StrToIntWidth(PInt64(Dst)^, Src, FieldSize, 0); // 05/05/2011 pb  CR 18916
{$endif}
      ftInteger:
//      PInteger(Dst)^ := GetIntFromStrLength(Src, FieldSize, 0);
        Result := StrToInt32Width(PInteger(Dst)^, Src, FieldSize, 0); // 05/05/2011 pb  CR 18916
      ftFloat, ftCurrency:
//      PDouble(Dst)^ := DbfStrToFloat(Src, FieldSize);
      begin
        Result := StrToFloatWidth(FloatValue, Src, FieldSize, 0); // 05/05/2011 pb  CR 18916
        if Result then
          PDouble(Dst)^:= FloatValue;
      end;
      ftDate, ftDateTime:
        begin
          // get year, month, day
//        ldy := GetIntFromStrLength(PChar(Src) + 0, 4, 1);
//        ldm := GetIntFromStrLength(PChar(Src) + 4, 2, 1);
//        ldd := GetIntFromStrLength(PChar(Src) + 6, 2, 1);
          StrToInt32Width(ldy, PChar(Src) + 0, 4, 1); // 05/05/2011 pb  CR 18916
          StrToInt32Width(ldm, PChar(Src) + 4, 2, 1); // 05/05/2011 pb  CR 18916
          StrToInt32Width(ldd, PChar(Src) + 6, 2, 1); // 05/05/2011 pb  CR 18916
          //if (ly<1900) or (ly>2100) then ly := 1900;
          //Year from 0001 to 9999 is possible
          //everyting else is an error, an empty string too
          //Do DateCorrection with Delphis possibillities for one or two digits
          if (ldy < 100) and (PChar(Src)[0] = #32) and (PChar(Src)[1] = #32) then
            CorrectYear(ldy);
          try
            date := EncodeDate(ldy, ldm, ldd);
          except
            date := 0;
          end;

          // time stored too?
          if (AFieldDef.FieldType = ftDateTime) and (DataType = ftDateTime) then
          begin
            // get hour, minute, second
//          lth := GetIntFromStrLength(PChar(Src) + 8,  2, 1);
//          ltm := GetIntFromStrLength(PChar(Src) + 10, 2, 1);
//          lts := GetIntFromStrLength(PChar(Src) + 12, 2, 1);
            StrToInt32Width(lth, PChar(Src) + 8,  2, 1); // 05/05/2011 pb  CR 18916
            StrToInt32Width(ltm, PChar(Src) + 10, 2, 1); // 05/05/2011 pb  CR 18916
            StrToInt32Width(lts, PChar(Src) + 12, 2, 1); // 05/05/2011 pb  CR 18916
            // encode
            try
              date := date + EncodeTime(lth, ltm, lts, 0);
            except
              date := 0;
            end;
          end;

          SaveDateToDst;
        end;
      ftString:
        StrLCopy(Dst, Src, FieldSize);
    end else begin
      case DataType of
      ftString:
        if Dst <> nil then
          PChar(Dst)[0] := #0;
      end;
    end;
  end;
end;

procedure TDbfFile.UpdateNullField(Buffer: Pointer; AFieldDef: TDbfFieldDef; 
  Action: TUpdateNullField);
var
  NullDst: pbyte;
  Mask: byte;
begin
  // this field has null setting capability
  NullDst := PByte(PChar(Buffer) + FNullField.Offset + (AFieldDef.NullPosition shr 3));
  Mask := 1 shl (AFieldDef.NullPosition and $7);
  if Action = unSet then
  begin
    // clear the field, set null flag
    NullDst^ := NullDst^ or Mask;
  end else begin
    // set field data, clear null flag
    NullDst^ := NullDst^ and not Mask;
  end;
end;

procedure TDbfFile.SetFieldData(Column: Integer; DataType: TFieldType; 
  Src, Dst: Pointer; NativeFormat: boolean);
const
  IsBlobFieldToPadChar: array[Boolean] of Char = (#32, '0');
  SrcNilToUpdateNullField: array[boolean] of TUpdateNullField = (unClear, unSet);
var
  FieldSize,FieldPrec: Integer;
  TempFieldDef: TDbfFieldDef;
  Len: Integer;
  IntValue: dword;
  year, month, day: Word;
  hour, minute, sec, msec: Word;
  date: TDateTime;
  timeStamp: TTimeStamp;
  asciiContents: boolean;

  procedure LoadDateFromSrc;
  begin
    if not NativeFormat then
    begin
      // Delphi 5, new format, passes a TDateTime
      date := PDateTime(Src)^;
    end else begin
      // Delphi 3 and 4, old "native" format, pass a TDateTimeRec with a time stamp
      //  date = integer
      //  datetime = msecs == BDETimeStampToDateTime as we implemented it
      if DataType = ftDateTime then
      begin
        date := PDouble(Src)^;
      end else begin
        timeStamp.Time := 0;
        timeStamp.Date := PLongInt(Src)^;
        date := TimeStampToDateTime(timeStamp);
      end;
    end;
  end;

begin
  TempFieldDef := TDbfFieldDef(FFieldDefs.Items[Column]);
  FieldSize := TempFieldDef.Size;
  FieldPrec := TempFieldDef.Precision;

  // if src = nil then write empty field
  // symmetry with above

  // foxpro has special _nullfield for flagging fields as `null'
  if (FNullField <> nil) and (TempFieldDef.NullPosition >= 0) then
    UpdateNullField(Dst, TempFieldDef, SrcNilToUpdateNullField[Src = nil]);

  // copy field data to record buffer
  Dst := PChar(Dst) + TempFieldDef.Offset;
  asciiContents := false;
  case TempFieldDef.NativeFieldType of
    '+', 'I':
      begin
        if FDbfVersion <> xFoxPro then
        begin
          if Src = nil then
            IntValue := 0
          else
            IntValue := PDWord(Src)^ xor $80000000;
          PDWord(Dst)^ := SwapIntBE(IntValue);
        end else begin
          if Src = nil then
            PDWord(Dst)^ := 0
          else
            PDWord(Dst)^ := SwapIntLE(PDWord(Src)^);
        end;
      end;
    'O':
      begin
{$ifdef SUPPORT_INT64}
        if Src = nil then
        begin
          PInt64(Dst)^ := 0;
        end else begin
          if PDouble(Src)^ < 0 then
            PInt64(Dst)^ := not PInt64(Src)^
          else
            PDouble(Dst)^ := (PDouble(Src)^) * -1;
          SwapInt64BE(Dst, Dst);
        end;
{$endif}
      end;
    '@':
      begin
        if Src = nil then
        begin
{$ifdef SUPPORT_INT64}
          PInt64(Dst)^ := 0;
{$else}          
          PInteger(Dst)^ := 0;
          PInteger(PChar(Dst)+4)^ := 0;
{$endif}
        end else begin
          LoadDateFromSrc;
          if FDateTimeHandling = dtBDETimeStamp then
            date := DateTimeToBDETimeStamp(date);
          SwapInt64BE(@date, Dst);
        end;
      end;
    'T':
      begin
        // all binary zeroes -> empty datetime
        if Src = nil then
        begin
{$ifdef SUPPORT_INT64}
          PInt64(Dst)^ := 0;
{$else}          
          PInteger(Dst)^ := 0;
          PInteger(PChar(Dst)+4)^ := 0;
{$endif}          
        end else begin
          LoadDateFromSrc;
          timeStamp := DateTimeToTimeStamp(date);
          PInteger(Dst)^ := SwapIntLE(timeStamp.Date + JulianDateDelta);
          PInteger(PChar(Dst)+4)^ := SwapIntLE(timeStamp.Time);
        end;
      end;
    'Y':
      begin
{$ifdef SUPPORT_INT64}
        if Src = nil then
        begin
          PInt64(Dst)^ := 0;
        end else begin
          case DataType of
            ftCurrency:
              PInt64(Dst)^ := Trunc(PDouble(Src)^ * 10000);
            ftBCD:
              PCurrency(Dst)^ := PCurrency(Src)^;
          end;
          SwapInt64LE(Dst, Dst);
        end;
{$endif}
      end;
    'B':
      begin
        if DbfVersion = xFoxPro then
        begin
          if Src = nil then
            PDouble(Dst)^ := 0
          else
            SwapInt64LE(Src, Dst);
        end else
          asciiContents := true;
      end;
    'M':
      begin
        if FieldSize = 4 then
        begin
          if Src = nil then
            PInteger(Dst)^ := 0
          else
            PInteger(Dst)^ := SwapIntLE(PInteger(Src)^);
        end else
          asciiContents := true;
      end;
  else
    asciiContents := true;
  end;
  if asciiContents then
  begin
    if Src = nil then
    begin
      if (FDbfVersion >= xBaseVII) and (DataType=ftString) then // 04/01/2011 pb  CR 18840
        FillChar(Dst^, FieldSize, #0) // 04/01/2011 pb  CR 18840
      else
        FillChar(Dst^, FieldSize, ' ');
    end else begin
      case DataType of
        ftBoolean:
          begin
            if PWord(Src)^ <> 0 then
              PChar(Dst)^ := 'T'
            else
              PChar(Dst)^ := 'F';
          end;
        ftSmallInt:
//        GetStrFromInt_Width(PSmallInt(Src)^, FieldSize, PChar(Dst), #32);
          IntToStrWidth(PSmallInt(Src)^, FieldSize, PChar(Dst), True, #32); // 05/05/2011 pb  CR 18916
{$ifdef SUPPORT_INT64}
        ftLargeInt:
//        GetStrFromInt64_Width(PLargeInt(Src)^, FieldSize, PChar(Dst), #32);
          IntToStrWidth(PInt64(Src)^, FieldSize, PChar(Dst), True, #32); // 05/05/2011 pb  CR 18916
{$endif}
        ftFloat, ftCurrency:
//        FloatToDbfStr(PDouble(Src)^, FieldSize, FieldPrec, PChar(Dst));
          FloatToStrWidth(PDouble(Src)^, FieldSize, FieldPrec, PChar(Dst), True); // 05/05/2011 pb  CR 18984
        ftInteger:
//        GetStrFromInt_Width(PInteger(Src)^, FieldSize, PChar(Dst),
//          IsBlobFieldToPadChar[TempFieldDef.IsBlob]);
          IntToStrWidth(PInteger(Src)^, FieldSize, PChar(Dst), True, IsBlobFieldToPadChar[TempFieldDef.IsBlob]); // 05/05/2011 pb  CR 18916
        ftDate, ftDateTime:
          begin
            LoadDateFromSrc;
            // decode
            DecodeDate(date, year, month, day);
            // format is yyyymmdd
//            GetStrFromInt_Width(year,  4, PChar(Dst),   '0');
//            GetStrFromInt_Width(month, 2, PChar(Dst)+4, '0');
//            GetStrFromInt_Width(day,   2, PChar(Dst)+6, '0');
            IntToStrWidth(year,  4, PChar(Dst),   True, DBF_ZERO); // 05/05/2011 pb  CR 18984
            IntToStrWidth(month, 2, PChar(Dst)+4, True, DBF_ZERO); // 05/05/2011 pb  CR 18984
            IntToStrWidth(day,   2, PChar(Dst)+6, True, DBF_ZERO); // 05/05/2011 pb  CR 18984
            // do time too if datetime
            if DataType = ftDateTime then
            begin
              DecodeTime(date, hour, minute, sec, msec);
              // format is hhmmss
//            GetStrFromInt_Width(hour,   2, PChar(Dst)+8,  '0');
//            GetStrFromInt_Width(minute, 2, PChar(Dst)+10, '0');
//            GetStrFromInt_Width(sec,    2, PChar(Dst)+12, '0');
              IntToStrWidth(hour,   2, PChar(Dst)+8,  True, DBF_ZERO); // 05/05/2011 pb  CR 18984
              IntToStrWidth(minute, 2, PChar(Dst)+10, True, DBF_ZERO); // 05/05/2011 pb  CR 18984
              IntToStrWidth(sec,    2, PChar(Dst)+12, True, DBF_ZERO); // 05/05/2011 pb  CR 18984
            end;
          end;
        ftString:
          begin
            // copy data
            Len := StrLen(Src);
            if Len > FieldSize then
              Len := FieldSize;
            Move(Src^, Dst^, Len);
            // fill remaining space with spaces
            FillChar((PChar(Dst)+Len)^, FieldSize - Len, ' ');
          end;
      end;  // case datatype
    end;
  end;
end;

procedure TDbfFile.InitDefaultBuffer;
var
  lRecordSize: integer;
  TempFieldDef: TDbfFieldDef;
  I: Integer;
begin
  lRecordSize := PDbfHdr(Header)^.RecordSize;
  // clear buffer (assume all string, fix specific fields later)
  //   note: Self.RecordSize is used for reading fielddefs too
  GetMem(FDefaultBuffer, lRecordSize+1);
  FillChar(FDefaultBuffer^, lRecordSize, ' ');
  
  // set nullflags field so that all fields are null
  if FNullField <> nil then
    FillChar(PChar(FDefaultBuffer+FNullField.Offset)^, FNullField.Size, $FF);

  // check binary and default fields
  for I := 0 to FFieldDefs.Count-1 do
  begin
    TempFieldDef := FFieldDefs.Items[I];
    // binary field? (foxpro memo fields are binary, but dbase not)
    if (TempFieldDef.NativeFieldType in ['I', 'O', '@', '+', '0', 'Y'])
        or ((TempFieldDef.NativeFieldType = 'M') and (TempFieldDef.Size = 4))
        or ((FDbfVersion >= xBaseVII) and (TempFieldDef.NativeFieldType='C') and (not TempFieldDef.HasDefault)) then // 04/01/2011 pb  CR 18840
      FillChar(PChar(FDefaultBuffer+TempFieldDef.Offset)^, TempFieldDef.Size, 0);
    // copy default value?
    if TempFieldDef.HasDefault then
    begin
      Move(TempFieldDef.DefaultBuf[0], FDefaultBuffer[TempFieldDef.Offset], TempFieldDef.Size);
      // clear the null flag, this field has a value
      if FNullField <> nil then
        UpdateNullField(FDefaultBuffer, TempFieldDef, unClear);
    end;
  end;
end;

procedure TDbfFile.InitRecord(DestBuf: PChar);
begin
  if FDefaultBuffer = nil then
    InitDefaultBuffer;
  Move(FDefaultBuffer^, DestBuf^, RecordSize);
end;

procedure TDbfFile.ApplyAutoIncToBuffer(DestBuf: PChar);
var
  TempFieldDef: TDbfFieldDef;
  I, NextVal, lAutoIncOffset: {LongWord} Cardinal;    {Delphi 3 does not know LongWord?}
begin
  if FAutoIncPresent then
  begin
    // if shared, reread header to find new autoinc values
// 05/27/2011 pb  CR 18759 - Already locked by TDbfFile.Insert
//  if NeedLocks then
//  begin
      // lock header so nobody else can use this value
//    LockPage(0, true);
//  end;

    // find autoinc fields
    for I := 0 to FFieldDefs.Count-1 do
    begin
      TempFieldDef := FFieldDefs.Items[I];
      if (TempFieldDef.NativeFieldType = '+') then
      begin
        // read current auto inc, from header or field, depending on sharing
        lAutoIncOffset := sizeof(rDbfHdr) + sizeof(rAfterHdrVII) + 
          FieldDescVII_AutoIncOffset + I * sizeof(rFieldDescVII);
        if NeedLocks then
        begin
          ReadBlock(@NextVal, 4, lAutoIncOffset);
          NextVal := SwapIntLE(NextVal);
        end else
          NextVal := TempFieldDef.AutoInc;
        // store to buffer, positive = high bit on, so flip it
        PCardinal(DestBuf+TempFieldDef.Offset)^ := SwapIntBE(NextVal or $80000000);
        // increase
        Inc(NextVal);
        TempFieldDef.AutoInc := NextVal;
        // write new value to header buffer
        PCardinal(FHeader+lAutoIncOffset)^ := SwapIntLE(NextVal);
      end;
    end;

    // write modified header (new autoinc values) to file
    WriteHeader;
    
    // release lock if locked
// 05/27/2011 pb  CR 18759
//  if NeedLocks then
//    UnlockPage(0);
  end;
end;

procedure TDbfFile.TryExclusive;
var
  I: Integer;
begin
  inherited;

  // exclusive succeeded? open index & memo exclusive too
  if Mode in [pfMemoryCreate..pfExclusiveOpen] then
  begin
    // indexes
    for I := 0 to FIndexFiles.Count - 1 do
      TPagedFile(FIndexFiles[I]).TryExclusive;
    // memo
    if FMemoFile <> nil then
      FMemoFile.TryExclusive;
  end;
end;

procedure TDbfFile.EndExclusive;
var
  I: Integer;
begin
  // end exclusive on index & memo too
  for I := 0 to FIndexFiles.Count - 1 do
    TPagedFile(FIndexFiles[I]).EndExclusive;
  // memo
  if FMemoFile <> nil then
    FMemoFile.EndExclusive;
  // dbf file
  inherited;
end;

procedure TDbfFile.OpenIndex(IndexName, IndexField: string; CreateIndex: Boolean; Options: TIndexOptions);
  //
  // assumes IndexName is not empty
  //
const
  // memcr, memop, excr, exopen, rwcr, rwopen, rdonly
  IndexOpenMode: array[boolean, pfMemoryCreate..pfReadOnly] of TPagedFileMode =
   ((pfMemoryCreate, pfMemoryCreate, pfExclusiveOpen, pfExclusiveOpen, pfReadWriteOpen, pfReadWriteOpen,
     pfReadOnly),
    (pfMemoryCreate, pfMemoryCreate, pfExclusiveCreate, pfExclusiveCreate, pfReadWriteCreate, pfReadWriteCreate,
     pfReadOnly));
var
  lIndexFile: TIndexFile;
  lIndexFileName: string;
  createMdxFile: Boolean;
  tempExclusive: boolean;
  addedIndexFile: Integer;
  addedIndexName: Integer;
begin
  // init
  addedIndexFile := -1;
  addedIndexName := -1;
  createMdxFile := false;
  // index already opened?
  lIndexFile := GetIndexByName(IndexName);
  if (lIndexFile <> nil) and (lIndexFile = FMdxFile) and CreateIndex then
  begin
    // index already exists in MDX file
    // delete it to save space, this causes a repage
    FMdxFile.DeleteIndex(IndexName);
    // index no longer exists
    lIndexFile := nil;
  end;
  if (lIndexFile = nil) and (IndexName <> EmptyStr) then
  begin
    // check if no extension, then create MDX index
    if Length(ExtractFileExt(IndexName)) = 0 then
    begin
      // check if mdx index already opened
      if FMdxFile <> nil then
      begin
        lIndexFileName := EmptyStr;
        lIndexFile := FMdxFile;
      end else begin
        lIndexFileName := ChangeFileExt(FileName, '.mdx');
        createMdxFile := true;
      end;
    end else begin
      lIndexFileName := IndexName;
    end;
    // do we need to open / create file?
    if lIndexFileName <> EmptyStr then
    begin
      // try to open / create the file
      lIndexFile := TIndexFile.Create(Self);
      lIndexFile.FileName := lIndexFileName;
      lIndexFile.Mode := IndexOpenMode[CreateIndex, Mode];
      lIndexFile.AutoCreate := CreateIndex or (Length(IndexField) > 0);
      lIndexFile.CodePage := UseCodePage;
      lIndexFile.OnLocaleError := FOnLocaleError;
      lIndexFile.OnReadVersion := FOnReadVersion; // 06/24/2011 pb  CR 19106
      lIndexFile.OnWriteVersion := FOnWriteVersion; // 06/24/2011 pb  CR 19106
      lIndexFile.CompatibleDistinctIndex := FCompatibleDistinctIndex; // 05/12/2011 pb  CR 19008
      lIndexFile.Open;
      // index file ready for use?
      if not lIndexFile.ForceClose then
      begin
        // if we had to create the index, store that info
        CreateIndex := lIndexFile.FileCreated;
        // check if trying to create empty index
        if CreateIndex and (IndexField = EmptyStr) then
        begin
          FreeAndNil(lIndexFile);
          CreateIndex := false;
          createMdxFile := false;
        end else begin
          // add new index file to list
          addedIndexFile := FIndexFiles.Add(lIndexFile);
        end;
        // created accompanying mdx file?
        if createMdxFile then
          FMdxFile := lIndexFile;
      end else begin
        // asked to close! close file
        FreeAndNil(lIndexFile);
      end;
    end;

    // check if file succesfully opened
    if lIndexFile <> nil then
    begin
      // add index to list
      addedIndexName := FIndexNames.AddObject(IndexName, lIndexFile);
    end;
  end;
  // create it or open it?
  if lIndexFile <> nil then
  begin
    if not CreateIndex then
      if lIndexFile = FMdxFile then
        CreateIndex := lIndexFile.IndexOf(IndexName) < 0;
    if CreateIndex then
    begin
      // try get exclusive mode
      tempExclusive := IsSharedAccess;
      if tempExclusive then TryExclusive;
      // always uppercase index expression
// 11/02/2011 pb  CR 19713- Removed
//    IndexField := AnsiUpperCase(IndexField);
      try
        try
          // create index if asked
          lIndexFile.CreateIndex(IndexField, IndexName, Options);
          // add all records
//        PackIndex(lIndexFile, IndexName);
          PackIndex(lIndexFile, IndexName, CreateIndex); // 07/06/2011 pb  CR 19188
          // if we wanted to open index readonly, but we created it, then reopen
          if Mode = pfReadOnly then
          begin
            lIndexFile.CloseFile;
            lIndexFile.Mode := pfReadOnly;
            lIndexFile.OpenFile;
          end;
          // if mdx file just created, write changes to dbf header
          // set MDX flag to true
          if lIndexFile = FMdxFile then // 04/26/2011 pb  CR 18707
          begin
            PDbfHdr(Header)^.MDXFlag := 1;
            WriteHeader;
          end;
        except
          on EDbfError do
          begin
            // :-( need to undo 'damage'....
            // remove index from list(s) if just added
            if addedIndexFile >= 0 then
              FIndexFiles.Delete(addedIndexFile);
            if addedIndexName >= 0 then
              FIndexNames.Delete(addedIndexName);
            // if no file created, do not destroy!
            if addedIndexFile >= 0 then
            begin
//            lIndexFile.Close;
//            Sysutils.DeleteFile(lIndexFileName);
//            if FMdxFile = lIndexFile then
//              FMdxFile := nil;
//            lIndexFile.Free;
              DeleteIndexFile(lIndexFile); // 06/22/2011 pb  CR 19106
            end;
            raise;
          end;
        end;
      finally
        // return to previous mode
        if tempExclusive then EndExclusive;
      end;
    end;
  end;
end;

//procedure TDbfFile.PackIndex(lIndexFile: TIndexFile; AIndexName: string);
procedure TDbfFile.PackIndex(lIndexFile: TIndexFile; AIndexName: string; CreateIndex: Boolean);
var
  prevMode: TIndexUpdateMode;
  prevIndex: string;
//cur, last: Integer;
{$ifdef USE_CACHE}
  cur, last: Integer; // 06/13/2011 pb  CR 18994
  prevCache: Integer;
  AUniqueMode: TIndexUniqueType;
{$endif}
begin
  // save current mode in case we change it
  prevMode := lIndexFile.UpdateMode;
  prevIndex := lIndexFile.IndexName;
  // check if index specified
  if Length(AIndexName) > 0 then
  begin
    // only pack specified index, not all
    lIndexFile.IndexName := AIndexName;
    lIndexFile.UpdateMode := umCurrent; // 07/06/2011 pb  CR 19188
    if not CreateIndex then // 07/06/2011 pb  CR 19188
      lIndexFile.CalcRegenerateIndexes; // 07/06/2011 pb  CR 19188
    lIndexFile.ClearIndex;
//  lIndexFile.UpdateMode := umCurrent;
  end else begin
    lIndexFile.IndexName := EmptyStr;
    lIndexFile.UpdateMode := umAll;
    if not CreateIndex then // 07/06/2011 pb  CR 19188
      lIndexFile.CalcRegenerateIndexes; // 07/06/2011 pb  CR 19188
    lIndexFile.Clear;
//  lIndexFile.UpdateMode := umAll; // 07/06/2011 pb  CR 19188
  end;
  // prepare update
//cur := 1;
//last := RecordCount;
{$ifdef USE_CACHE}
  cur := 1;
  last := RecordCount;
  BufferAhead := true;
  prevCache := lIndexFile.CacheSize;
  lIndexFile.CacheSize := GetFreeMemory;
  if lIndexFile.CacheSize < 16384 * 1024 then
    lIndexFile.CacheSize := 16384 * 1024;
{$endif}
  try
    try
{$ifdef USE_CACHE}
      if lIndexFile.UniqueMode = iuUnique then // 11/04/2011 pb  CR 19723
        AUniqueMode := iuDistinct // 11/04/2011 pb  CR 19723
      else
        AUniqueMode := lIndexFile.UniqueMode; // 11/04/2011 pb  CR 19723
      DoProgress(0, last, SProgressReadingRecords); // 03/10/2011 pb  CR 18709
      while cur <= last do
      begin
        ReadRecord(cur, FPrevBuffer);
//      lIndexFile.Insert(cur, FPrevBuffer);
//      lIndexFile.Insert(cur, FPrevBuffer, True); // 04/13/2011 pb  CR 18918
        lIndexFile.Insert(cur, FPrevBuffer, AUniqueMode); // 11/04/2011 pb  CR 19723
        if Assigned(FOnProgress) then // 03/10/2011 pb  CR 18709
          DoProgress(cur, last, SProgressReadingRecords); // 03/10/2011 pb  CR 18709
        inc(cur);
      end;
{$else}
      lIndexFile.OnProgress := FOnProgress; // 06/13/2011 pb  CR 18994
      try
        lIndexFile.BulkLoadIndexes; // 06/13/2011 pb  CR 18994
      finally
        lIndexFile.OnProgress := nil; // 06/13/2011 pb  CR 18994
      end;
{$endif}
    except
      on E: EDbfError do
      begin
        lIndexFile.DeleteIndex(lIndexFile.IndexName);
        raise;
      end;
    end;
  finally
    // restore previous mode
{$ifdef USE_CACHE}
    BufferAhead := false;
    lIndexFile.BufferAhead := true;
{$endif}
    lIndexFile.Flush;
{$ifdef USE_CACHE}
    lIndexFile.BufferAhead := false;
    lIndexFile.CacheSize := prevCache;
{$endif}
    lIndexFile.UpdateMode := prevMode;
    lIndexFile.IndexName := prevIndex;
  end;
end;

procedure TDbfFile.RepageIndex(AIndexFile: string);
var
  lIndexNo: Integer;
begin
  // DBF MDX index?
  if Length(AIndexFile) = 0 then
  begin
    if FMdxFile <> nil then
    begin
      // repage attached mdx
      FMdxFile.RepageFile;
    end;
  end else begin
    // search index file
    lIndexNo := FIndexNames.IndexOf(AIndexFile);
    // index found?
    if lIndexNo >= 0 then
      TIndexFile(FIndexNames.Objects[lIndexNo]).RepageFile;
  end;
end;

procedure TDbfFile.CompactIndex(AIndexFile: string);
var
  lIndexNo: Integer;
begin
  // DBF MDX index?
  if Length(AIndexFile) = 0 then
  begin
    if FMdxFile <> nil then
    begin
      // repage attached mdx
      FMdxFile.CompactFile;
    end;
  end else begin
    // search index file
    lIndexNo := FIndexNames.IndexOf(AIndexFile);
    // index found?
    if lIndexNo >= 0 then
      TIndexFile(FIndexNames.Objects[lIndexNo]).CompactFile;
  end;
end;

procedure TDbfFile.CloseIndex(AIndexName: string);
var
  lIndexNo: Integer;
  lIndex: TIndexFile;
begin
  // search index file
  lIndexNo := FIndexNames.IndexOf(AIndexName);
  // don't close mdx file
  if (lIndexNo >= 0) then
  begin
    // get index pointer
    lIndex := TIndexFile(FIndexNames.Objects[lIndexNo]);
    if (lIndex <> FMdxFile) then
    begin
      // close file
      lIndex.Free;
      // remove from lists
      FIndexFiles.Remove(lIndex);
      FIndexNames.Delete(lIndexNo);
      // was this the current index?
      if (FCurIndex = lIndexNo) then
      begin
        FCurIndex := -1;
        //FCursor := FDbfCursor;
      end;
    end;
  end;
end;

function TDbfFile.DeleteIndex(const AIndexName: string): Boolean;
var
  lIndexNo: Integer;
  lIndex: TIndexFile;
  lFileName: string;
begin
  // search index file
  lIndexNo := FIndexNames.IndexOf(AIndexName);
  Result := lIndexNo >= 0;
  // found index?
  if Result then
  begin
    // can only delete indexes from MDX files
    lIndex := TIndexFile(FIndexNames.Objects[lIndexNo]);
    if lIndex = FMdxFile then
    begin
      lIndex.DeleteIndex(AIndexName);
      // remove it from the list
      FIndexNames.Delete(lIndexNo);
      // no more MDX indexes?
      lIndexNo := FIndexNames.IndexOfObject(FMdxFile);
      if lIndexNo = -1 then
      begin
        // no MDX indexes left
        lIndexNo := FIndexFiles.IndexOf(FMdxFile);
        if lIndexNo >= 0 then
          FIndexFiles.Delete(lIndexNo);
        lFileName := FMdxFile.FileName;
        FreeAndNil(FMdxFile);
        // erase file
        Sysutils.DeleteFile(lFileName);
        // clear mdx flag
        PDbfHdr(Header)^.MDXFlag := 0;
        WriteHeader;
      end;
    end else begin
      // close index first
      CloseIndex(AIndexName);
      // delete file from disk
      SysUtils.DeleteFile(AIndexName);
    end;
  end;
end;

function TDbfFile.Insert(Buffer: PChar): integer;
type
  TErrorContext = (ecNone, ecInsert, ecWriteIndex, ecWriteDbf);
var
  newRecord: Integer;
  lIndex: TIndexFile;

  procedure RollBackIndexesAndRaise(Count: Integer; ErrorContext: TErrorContext);
  var
    errorMsg: string;
    I: Integer;
  begin
    // rollback committed indexes
    for I := 0 to Count-1 do
    begin
      lIndex := TIndexFile(FIndexFiles.Items[I]);
      lIndex.Delete(newRecord, Buffer);
    end;

    // reset any dbf file error
    ResetError;

    // if part of indexes committed -> always index error msg
    // if error while rolling back index -> index error msg
    case ErrorContext of
      ecInsert: begin TIndexFile(FIndexFiles.Items[Count]).InsertError; exit; end;
      ecWriteIndex: errorMsg := STRING_WRITE_INDEX_ERROR;
      ecWriteDbf: errorMsg := STRING_WRITE_ERROR;
    end;
    raise EDbfWriteError.Create(errorMsg);
  end;

var
  I: Integer;
  error: TErrorContext;
//EofTerminator: Byte;
  Locked: Boolean; // 05/27/2011 pb  CR 18759
begin
  Result := 0;
  Locked := LockPage(0, False); // 05/27/2011 pb  CR 18759
  if not Locked then // 05/27/2011 pb  CR 18759
    raise EDbfError.Create(STRING_RECORD_LOCKED); // 05/27/2011 pb  CR 18759
  try
    if not LockPage(-1, True) then // 05/27/2011 pb  CR 18759
      RaiseLastOSError; // 05/27/2011 pb  CR 18759
    try
      // get new record index
//    Result := 0; // 05/27/2011 pb  CR 18759
      newRecord := RecordCount+1;
      // lock record so we can write data
//    while not LockPage(newRecord, false) do
//      Inc(newRecord);
      if not LockPage(newRecord, False) then // 05/27/2011 pb  CR 18759
        RaiseLastOSError; // 05/27/2011 pb  CR 18759
      try
        UnlockPage(0);
        Locked := False;
        // write autoinc value
      //if not FInCopyFrom then // 03/11/2011 pb  CR 18782
        if not FInBatch then // 05/04/2011 pb  CR 18913
          ApplyAutoIncToBuffer(Buffer);
        error := ecNone;
        I := 0;
        while I < FIndexFiles.Count do
        begin
          lIndex := TIndexFile(FIndexFiles.Items[I]);
//        if not lIndex.Insert(newRecord, Buffer) then
//        if not lIndex.Insert(newRecord, Buffer, False) then // 04/13/2011 pb  CR 18918
          if not lIndex.Insert(newRecord, Buffer, lIndex.UniqueMode) then // 11/04/2011 pb  CR 19723
            error := ecInsert;
          if lIndex.WriteError then
            error := ecWriteIndex;
          if error <> ecNone then
          begin
            // if there's an index write error, I shouldn't
            // try to write the dbf header and the new record,
            // but raise an exception right away
//          UnlockPage(newRecord);
//          RollBackIndexesAndRaise(I, ecWriteIndex);
            RollBackIndexesAndRaise(I, error); // 06/16/2011 pb  CR 19060
          end;
          Inc(I);
        end;

//      if (not FInBatch) or FNeedLocks then // 05/04/2011 pb  CR 18913
        if NeedLocks then // 10/28/2011 pb  CR 19699
        begin
          // indexes ok -> continue inserting
          // update header record count
//        LockPage(0, true);
          // read current header
          ReadHeader;
          // increase current record count
          Inc(PDbfHdr(Header)^.RecordCount);
          // write header to disk
          WriteHeader;
          // done with header
//        UnlockPage(0);
        end
        else
          FRecordCountDirty := True; // 10/28/2011 pb  CR 19699

        if WriteError then
        begin
          // couldn't write header, so I shouldn't
          // even try to write the record.
          //
          // At this point I should "roll back"
          // the already written index records.
          // if this fails, I'm in deep trouble!
//        UnlockPage(newRecord);
          RollbackIndexesAndRaise(FIndexFiles.Count, ecWriteDbf);
        end;

        // write locking info
        if FLockField <> nil then
          WriteLockInfo(Buffer);
        // write buffer to disk
        WriteRecord(newRecord, Buffer);
        // 03/25/2011 pb  CR 18850 - This has to come after the call to WriteRecord, to prevent it from being overwritten
      //EofTerminator := $1A;
      //WriteBlock(@EofTerminator, 1, CalcPageOffset(RecordCount+1));
//      if (not FInBatch) or NeedLocks then // 05/04/2011 pb  CR 18913
        if NeedLocks then // 10/28/2011 pb  CR 19699
          WriteEOFTerminator; // 05/04/2011 pb  CR 18913

        // done updating, unlock
//      UnlockPage(newRecord);
        // error occurred while writing?
        if WriteError then
        begin
          // -- Tobias --
          // The record couldn't be written, so
          // the written index records and the
          // change to the header have to be
          // rolled back
//        LockPage(0, true);
          ReadHeader;
          Dec(PDbfHdr(Header)^.RecordCount);
          WriteHeader;
//        UnlockPage(0);
          // roll back indexes too
          RollbackIndexesAndRaise(FIndexFiles.Count, ecWriteDbf);
        end else
          Result := newRecord;
      finally
        UnlockPage(newRecord); // 05/27/2011 pb  CR 18759
      end;
    finally
      UnlockPage(-1); // 05/27/2011 pb  CR 18759
    end;
  finally
    if Locked then // 05/27/2011 pb  CR 18759
      UnlockPage(0); // 05/27/2011 pb  CR 18759
  end;
end;

procedure TDbfFile.WriteLockInfo(Buffer: PChar);
//
// *) assumes FHasLockField = true
//
var
  year, month, day, hour, minute, sec, msec: Word;
  lockoffset: integer;
begin
  // increase change count
  lockoffset := FLockField.Offset;
  Inc(PWord(Buffer+lockoffset)^);
  // set time
  DecodeDate(Now(), year, month, day);
  DecodeTime(Now(), hour, minute, sec, msec);
  Buffer[lockoffset+2] := Char(hour);
  Buffer[lockoffset+3] := Char(minute);
  Buffer[lockoffset+4] := Char(sec);
  // set date
  Buffer[lockoffset+5] := Char(year - 1900);
  Buffer[lockoffset+6] := Char(month);
  Buffer[lockoffset+7] := Char(day);
  // set name
  FillChar(Buffer[lockoffset+8], FLockField.Size-8, ' ');
  Move(DbfGlobals.UserName[1], Buffer[lockoffset+8], FLockUserLen);
end;

//procedure TDbfFile.LockRecord(RecNo: Integer; Buffer: PChar);
procedure TDbfFile.LockRecord(RecNo: Integer; Buffer: PChar; Resync: Boolean); // 10/28/2011 pb  CR 19703
var
  Locked : Boolean; // 03/04/2011 pb  CR 18759
begin
  if NeedLocks then // 03/25/2011 pb  CR 18820
  begin
    if FVirtualLocks then
    begin
//    if not LockSection(LockOffset, 1, False) then // 03/04/2011 pb  CR 18759- Test whether or not the table is locked, BDE compatible
      if not LockPage(0, False) then // 05/10/2011 pb  CR 18996
        raise EDbfError.Create(STRING_RECORD_LOCKED);
    end;
//  if LockPage(RecNo, false) then
    Locked := LockPage(RecNo, false);
    if FVirtualLocks then
//    UnlockSection(LockOffset, 1); // 03/04/2011 pb  CR 18759- Do not keep the table locked
      UnlockPage(0); // 05/10/2011 pb  CR 18996
  end
  else
    Locked := True; // 03/25/2011 pb  CR 18820
  if Locked then
  begin
    // reread data
    if Resync then // 10/28/2011 pb  CR 19703
      if ResyncSharedReadBuffer then // 10/28/2011 pb  CR 19703
        ReadRecord(RecNo, Buffer);
    // store previous data for updating indexes
    Move(Buffer^, FPrevBuffer^, RecordSize);
    // lock succeeded, update lock info, if field present
    if FLockField <> nil then
    begin
      // update buffer
      WriteLockInfo(Buffer);
      // write to disk
      WriteRecord(RecNo, Buffer);
    end;
  end else
    raise EDbfError.Create(STRING_RECORD_LOCKED);
end;

procedure TDbfFile.UnlockRecord(RecNo: Integer; Buffer: PChar);
var
  I: Integer;
  lIndex, lErrorIndex: TIndexFile;
begin
  // update indexes, possible key violation
  I := 0;
  while I < FIndexFiles.Count do
  begin
    lIndex := TIndexFile(FIndexFiles.Items[I]);
    if not lIndex.Update(RecNo, FPrevBuffer, Buffer) then
    begin
      // error -> rollback
      lErrorIndex := lIndex;
      while I > 0 do
      begin
        Dec(I);
        lIndex := TIndexFile(FIndexFiles.Items[I]);
        lIndex.Update(RecNo, Buffer, FPrevBuffer);
      end;
      lErrorIndex.InsertError;
    end;
    Inc(I);
  end;
  // write new record buffer, all keys ok
  WriteRecord(RecNo, Buffer);
  // done updating, unlock
  if NeedLocks then // 03/25/2011 pb  CR 18820
    UnlockPage(RecNo);
end;

procedure TDbfFile.RecordDeleted(RecNo: Integer; Buffer: PChar);
var
  I: Integer;
  lIndex: TIndexFile;
begin
  // notify indexes: record deleted
  for I := 0 to FIndexFiles.Count - 1 do
  begin
    lIndex := TIndexFile(FIndexFiles.Items[I]);
    lIndex.RecordDeleted(RecNo, Buffer);
  end;
end;

procedure TDbfFile.RecordRecalled(RecNo: Integer; Buffer: PChar);
var
  I: Integer;
  lIndex, lErrorIndex: TIndexFile;
begin
  // notify indexes: record recalled
  I := 0;
  while I < FIndexFiles.Count do
  begin
    lIndex := TIndexFile(FIndexFiles.Items[I]);
    if not lIndex.RecordRecalled(RecNo, Buffer) then
    begin
      lErrorIndex := lIndex;
      while I > 0 do
      begin
        Dec(I);
        lIndex.RecordDeleted(RecNo, Buffer);
      end;
      lErrorIndex.InsertError; // 06/16/2011 pb  CR 19060
    end;
    Inc(I);
  end;
end;

procedure TDbfFile.DeleteIndexFile(AIndexFile: TIndexFile); // 06/22/2011 pb  CR 19106
var
  Index: Integer;
begin
  for Index:= Pred(FIndexNames.Count) downto 0 do
    if FIndexNames.Objects[Index]=AIndexFile then
      FIndexNames.Delete(Index);
  FIndexFiles.Remove(AIndexFile);
  AIndexFile.Close;
  AIndexFile.DeleteFile;
  if FMdxFile = AIndexFile then
    FMdxFile := nil;
  AIndexFile.Free;
end;

procedure TDbfFile.SetRecordSize(NewSize: Integer);
begin
  if NewSize <> RecordSize then
  begin
    if FPrevBuffer <> nil then
      FreeMemAndNil(Pointer(FPrevBuffer));

    if NewSize > 0 then
      GetMem(FPrevBuffer, NewSize);
  end;
  inherited;
end;

function TDbfFile.GetIndexByName(AIndexName: string): TIndexFile;
var
  I: Integer;
begin
  I := FIndexNames.IndexOf(AIndexName);
  if I >= 0 then
    Result := TIndexFile(FIndexNames.Objects[I])
  else
    Result := nil;
end;

//====================================================================
// TDbfCursor
//====================================================================
constructor TDbfCursor.Create(DbfFile: TDbfFile);
begin
  inherited Create(DbfFile);
end;

function TDbfCursor.Next: Boolean;
begin
  if TDbfFile(PagedFile).IsRecordPresent(FPhysicalRecNo) then
  begin
    inc(FPhysicalRecNo);
    Result := TDbfFile(PagedFile).IsRecordPresent(FPhysicalRecNo);
  end else begin
    FPhysicalRecNo := TDbfFile(PagedFile).CachedRecordCount + 1;
    Result := false;
  end;
end;

function TDbfCursor.Prev: Boolean;
begin
  if FPhysicalRecNo > 0 then
    dec(FPhysicalRecNo)
  else
    FPhysicalRecNo := 0;
  Result := FPhysicalRecNo > 0;
end;

procedure TDbfCursor.First;
begin
  FPhysicalRecNo := 0;
end;

procedure TDbfCursor.Last;
var
  max: Integer;
begin
  max := TDbfFile(PagedFile).RecordCount;
  if max = 0 then
    FPhysicalRecNo := 0
  else
    FPhysicalRecNo := max + 1;
end;

function TDbfCursor.GetPhysicalRecNo: Integer;
begin
  Result := FPhysicalRecNo;
end;

procedure TDbfCursor.SetPhysicalRecNo(RecNo: Integer);
begin
  FPhysicalRecNo := RecNo;
end;

//function TDbfCursor.GetSequentialRecordCount: Integer;
function TDbfCursor.GetSequentialRecordCount: TSequentialRecNo; // 08/18/2011 pb  CR 19448
begin
  Result := TDbfFile(PagedFile).RecordCount;
end;

//function TDbfCursor.GetSequentialRecNo: Integer;
function TDbfCursor.GetSequentialRecNo: TSequentialRecNo; // 08/18/2011 pb  CR 19448
begin
  Result := FPhysicalRecNo;
end;

//procedure TDbfCursor.SetSequentialRecNo(RecNo: Integer);
procedure TDbfCursor.SetSequentialRecNo(RecNo: TSequentialRecNo); // 08/18/2011 pb  CR 19448
begin
  FPhysicalRecNo := RecNo;
end;

// codepage enumeration procedure
var
  TempCodePageList: TList;

// LPTSTR = PChar ok?

function CodePagesProc(CodePageString: PChar): Cardinal; stdcall;
var
  IntValue: Integer;
begin
  // add codepage to list
//TempCodePageList.Add(Pointer(GetIntFromStrLength(CodePageString, StrLen(CodePageString), -1)));
  if StrToInt32Width(IntValue, CodePageString, StrLen(CodePageString), -1) then
    TempCodePageList.Add(Pointer(IntValue));

  // continue enumeration
  Result := 1;
end;

//====================================================================
// TDbfGlobals
//====================================================================
constructor TDbfGlobals.Create;
begin
  FCodePages := TList.Create;
  FDefaultOpenCodePage := GetACP;
  // the following sets FDefaultCreateLangId
  DefaultCreateCodePage := GetACP;
  FCurrencyAsBCD := true;
  // determine which code pages are installed
  TempCodePageList := FCodePages;
  EnumSystemCodePages(@CodePagesProc, {CP_SUPPORTED} CP_INSTALLED);
  TempCodePageList := nil;
  InitUserName;
end;

procedure TDbfGlobals.InitUserName;
{$ifdef FPC}
{$ifndef WINDOWS}
var
  TempName: UTSName;
{$endif}
{$endif}
begin
{$ifdef WINDOWS}
  FUserNameLen := MAX_COMPUTERNAME_LENGTH+1;
  SetLength(FUserName, FUserNameLen);
  Windows.GetComputerName(PChar(FUserName), 
    {$ifdef DELPHI_3}Windows.DWORD({$endif}
      FUserNameLen
    {$ifdef DELPHI_3}){$endif}
    );
  SetLength(FUserName, FUserNameLen);
{$else}  
{$ifdef FPC}
  FpUname(TempName);
  FUserName := TempName.machine;
  FUserNameLen := Length(FUserName);
{$endif}  
{$endif}
end;

destructor TDbfGlobals.Destroy; {override;}
begin
  FCodePages.Free;
end;

function TDbfGlobals.GetDefaultCreateCodePage: Integer;
begin
  Result := LangId_To_CodePage[FDefaultCreateLangId];
end;

procedure TDbfGlobals.SetDefaultCreateCodePage(NewCodePage: Integer);
begin
  FDefaultCreateLangId := ConstructLangId(NewCodePage, GetUserDefaultLCID, false);
end;

function TDbfGlobals.CodePageInstalled(ACodePage: Integer): Boolean;
begin
  Result := FCodePages.IndexOf(Pointer(ACodePage)) >= 0;
end;

initialization
  DbfGlobals := TDbfGlobals.Create;  // 02/18/2011 dhd CR 18611- force the globals to be created in the Main thread to prevent multi-threading problem

finalization
  FreeAndNil(DbfGlobals);


(*
  Stuffs non implemented yet
  TFoxCDXHeader         = Record
    PointerRootNode     : Integer;
    PointerFreeList     : Integer;
    Reserved_8_11       : Cardinal;
    KeyLength           : Word;
    IndexOption         : Byte;
    IndexSignature      : Byte;
    Reserved_Null       : TFoxReservedNull;
    SortOrder           : Word;
    TotalExpressionLen  : Word;
    ForExpressionLen    : Word;
    Reserved_506_507    : Word;
    KeyExpressionLen    : Word;
    KeyForExpression    : TKeyForExpression;
  End;
  PFoxCDXHeader         = ^TFoxCDXHeader;

  TFoxCDXNodeCommon     = Record
    NodeAttributes      : Word;
    NumberOfKeys        : Word;
    PointerLeftNode     : Integer;
    PointerRightNode    : Integer;
  End;

  TFoxCDXNodeNonLeaf    = Record
    NodeCommon          : TFoxCDXNodeCommon;
    TempBlock           : Array [12..511] of Byte;
  End;
  PFoxCDXNodeNonLeaf    = ^TFoxCDXNodeNonLeaf;

  TFoxCDXNodeLeaf       = Packed Record
    NodeCommon          : TFoxCDXNodeCommon;
    BlockFreeSpace      : Word;
    RecordNumberMask    : Integer;
    DuplicateCountMask  : Byte;
    TrailByteCountMask  : Byte;
    RecNoBytes          : Byte;
    DuplicateCountBytes : Byte;
    TrailByteCountBytes : Byte;
    HoldingByteCount    : Byte;
    DataBlock           : TDataBlock;
  End;
  PFoxCDXNodeLeaf       = ^TFoxCDXNodeLeaf;

*)

end.

