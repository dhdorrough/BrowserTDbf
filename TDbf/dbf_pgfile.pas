unit dbf_pgfile;

// Modifications by BCC Software
// 11/17/2011 pb  CR 19755- Flush file buffers on close
// 10/28/2011 pb  CR 19703- Fix behaviour if BufferAhead and IsSharedAccess
// 10/28/2011 pb  CR 19176- Implement dynamic buffer size to optimize performance
// 06/24/2011 pb  CR 19106- Allow BDE-compatible index versioning to be overriden
// 05/27/2011 pb  CR 18759- Locking when adding a record
// 05/16/2011 pb  CR 18913- Set FBufferSize after SynchronizeBuffer
// 05/16/2011 pb  CR 18797- Allow LockFile/UnlockFile behaviour to be overriden
// 05/16/2011 pb  CR 18759- For consistency with the BDE, do not leave all records locked when locking the table
// 05/10/2011 pb  CR 18996- CompatibleLockOffset = False uses large lock offset recommended for files of size >= LockStart on WinNT
// 05/10/2011 pb  CR 18997- Report file errors
// 05/04/2011 pb  CR 18913- In TDbf.CopyFrom, use BufferAhead and defer updating header and EOF terminator until it is done
// 04/26/2011 pb  CR 18944- ReadHeader should return the number of bytes actually read
// 01/18/2011 dhd CR 18640- Failure to unlock table prior to closing table was causing an exception
// 03/04/2011 pb  CR 18372- Use 64-bit arithmetic for file offset and size, to support files over 4 GB in size
// 03/04/2011 pb  CR 18759- If BDE has the table locked, TDbf allowed a record to be locked
// 03/14/2011 pb  CR 18703- Make Win32 error code available if it fails to open the file
// 03/14/2011 pb  CR 18796- In pfExclusiveCreate and pfExclusiveOpen modes, do not open with file sharing
// 03/10/2011 pb  CR 18709- Progress and cancellation

interface

{$I dbf_common.inc}

uses
  Classes,
  SysUtils,
  dbf_common;

//const
//  MaxHeaders = 256;

type
  EPagedFile = Exception;

  TPagedFileMode = (pfNone, pfMemoryCreate, pfMemoryOpen, pfExclusiveCreate, 
    pfExclusiveOpen, pfReadWriteCreate, pfReadWriteOpen, pfReadOnly);

  // access levels:
  //
  // - memory            create
  // - exclusive         create/open
  // - read/write        create/open
  // - readonly                 open
  //
  // - memory            -*-share: N/A          -*-locks: disabled    -*-indexes: read/write
  // - exclusive_create  -*-share: exclusive    -*-locks: disabled    -*-indexes: read/write
  // - exclusive_open    -*-share: exclusive    -*-locks: disabled    -*-indexes: read/write
  // - readwrite_create  -*-share: deny none    -*-locks: enabled     -*-indexes: read/write
  // - readwrite_open    -*-share: deny none    -*-locks: enabled     -*-indexes: read/write
  // - readonly          -*-share: deny none    -*-locks: disabled    -*-indexes: readonly

  // 03/14/2011 pb  CR 18703
  EPagedFileOpenError = class(EFOpenError)
  private
    fErrorCode: DWORD;
  public
    constructor Create(FileName: string; AErrorCode: DWORD);
    property ErrorCode: DWORD read fErrorCode;
  end;

  TPagedFileProgressEvent = procedure(Sender: TObject; Position, Max: Integer; var Aborted: Boolean; Msg: string) of object; // 03/10/2011 pb  CR 18709
  TPagedFileLockUnlockFileEvent = procedure(Sender: TObject; var Handled: Boolean; var Result: Boolean; hFile: THandle; dwFileOffsetLow, dwFileOffsetHigh: DWORD; nNumberOfBytesLow, nNumberOfBytesHigh: DWORD; const AllPages: Boolean; const PageNo: Integer) of object; // 05/16/2011 pb  CR 18797
  TPagedFileControlsDisabledEvent = function: Boolean of object; // 10/28/2011 pb  CR 19703

type
  TPagedFile = class(TObject)
  protected
    FStream: TStream;
    FHeaderOffset: Integer;
    FHeaderSize: Integer;
    FRecordSize: Integer;
    FPageSize: Integer;         { need for MDX, where recordsize <> pagesize }
    FRecordCount: Integer;      { actually FPageCount, but we want to keep existing code }
    FPagesPerRecord: Integer;
    FCachedSize: {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif}; // 03/04/2011 pb  CR 18372
    FCachedRecordCount: Integer;
    FHeader: PChar;
    FActive: Boolean;
    FNeedRecalc: Boolean;
    FHeaderModified: Boolean;
    FPageOffsetByHeader: Boolean;   { do pages start after header or just at BOF? }
    FMode: TPagedFileMode;
    FTempMode: TPagedFileMode;
    FUserMode: TPagedFileMode;
    FAutoCreate: Boolean;
    FNeedLocks: Boolean;
    FVirtualLocks: Boolean;
    FFileLocked: Boolean;
    FFileName: string;
    FBufferPtr: Pointer;
    FBufferAhead: Boolean;
    FBufferPage: Integer;
{$ifdef SUPPORT_INT64}
    FBufferOffset: Int64; // 03/04/2011 pb  CR 18372
{$else}
    FBufferOffset: Integer;
{$endif}
    FBufferSize: Integer;
    FBufferReadSize: Integer;
    FBufferMaxSize: Integer;
    FBufferModified: Boolean;
    FWriteError: Boolean;
{$ifdef SUPPORT_INT64}
    FCompatibleLockOffset: Boolean; // 05/10/2011 pb  CR 18996
{$endif}
    FOnProgress: TPagedFileProgressEvent; // 03/10/2011 pb  CR 18709
    FOnLockFile: TPagedFileLockUnlockFileEvent;
    FOnUnlockFile: TPagedFileLockUnlockFileEvent;
    FOnControlsDisabled: TPagedFileControlsDisabledEvent; // 10/28/2011 pb  CR 19703
    FResyncSharedEnabled: Integer; // 10/28/2011 pb  CR 19703
  protected
    procedure SetHeaderOffset(NewValue: Integer); virtual;
    procedure SetRecordSize(NewValue: Integer); virtual;
    procedure SetHeaderSize(NewValue: Integer); virtual;
    procedure SetPageSize(NewValue: Integer);
    procedure SetPageOffsetByHeader(NewValue: Boolean); virtual;
    procedure SetRecordCount(NewValue: Integer);
    procedure SetBufferAhead(NewValue: Boolean);
    procedure SetFileName(NewName: string);
    procedure SetStream(NewStream: TStream);
{$ifdef SUPPORT_INT64}
//  function  LockSection(const Offset: Int64; const Length: Cardinal; const Wait: Boolean): Boolean; virtual; // 03/04/2011 pb  CR 18372
    function  LockSection(const Offset: Int64; const Length: Cardinal; const Wait, AllPages: Boolean; const PageNo: Integer): Boolean; virtual; // 05/16/2011 pb  CR 18797
//  function  UnlockSection(const Offset: Int64; const Length: Cardinal): Boolean; virtual; // 03/04/2011 pb  CR 18372
    function  UnlockSection(const Offset: Int64; const Length: Cardinal; const AllPages: Boolean; const PageNo: Integer): Boolean; virtual; // 05/16/2011 pb  CR 18797
{$else}
//  function  LockSection(const Offset, Length: Cardinal; const Wait: Boolean): Boolean; virtual;
    function  LockSection(const Offset, Length: Cardinal; const Wait, AllPages: Boolean; const PageNo: Integer): Boolean; virtual; // 05/16/2011 pb  CR 18797
//  function  UnlockSection(const Offset, Length: Cardinal): Boolean; virtual;
    function  UnlockSection(const Offset, Length: Cardinal; const AllPages: Boolean; const PageNo: Integer): Boolean; virtual; // 05/16/2011 pb  CR 18797
{$endif}
    procedure UpdateBufferSize;
    procedure RecalcPagesPerRecord;
//  procedure ReadHeader;
    function ReadHeader: Integer; // 04/26/2011 pb  CR 18944
    procedure FlushHeader;
    procedure FlushBuffer;
    procedure FlushOS; // 11/17/2011 pb  CR 19755
    function  ReadChar: Byte;
    procedure WriteChar(c: Byte);
{$ifdef SUPPORT_INT64}
    procedure CheckCachedSize(const APosition: Int64); // 03/04/2011 pb  CR 18372
{$else}
    procedure CheckCachedSize(const APosition: Integer);
{$endif}
    procedure SynchronizeBuffer(IntRecNum: Integer);
    function  ResyncSharedEnabled: Boolean; // 10/28/2011 pb  CR 19703
    function  ReadBuffer: Boolean; // 10/28/2011 pb  CR 19703
    function  Read(Buffer: Pointer; ASize: Integer): Integer;
//{$ifdef SUPPORT_INT64}
//    function  ReadBlock(const BlockPtr: Pointer; const ASize: Integer; const APosition: Int64): Integer; // 03/04/2011 pb  CR 18372
//{$else}
//    function  ReadBlock(const BlockPtr: Pointer; const ASize, APosition: Integer): Integer;
//{$endif}
    function  SingleReadRecord(IntRecNum: Integer; Buffer: Pointer): Integer;
//{$ifdef SUPPORT_INT64}
//    procedure WriteBlock(const BlockPtr: Pointer; const ASize: Integer; const APosition: Int64); // 03/04/2011 pb  CR 18372
//{$else}
//    procedure WriteBlock(const BlockPtr: Pointer; const ASize, APosition: Integer);
//{$endif}
    procedure SingleWriteRecord(IntRecNum: Integer; Buffer: Pointer);
    function  GetRecordCount: Integer;
{$ifdef SUPPORT_INT64}
    procedure UpdateCachedSize(CurrPos: Int64); // 03/04/2011 pb  CR 18372
{$else}
    procedure UpdateCachedSize(CurrPos: Integer);
{$endif}

    function DoLockFile(hFile: THandle; dwFileOffsetLow, dwFileOffsetHigh: DWORD; nNumberOfBytesToLockLow, nNumberOfBytesToLockHigh: DWORD; const AllPages: Boolean; const PageNo: Integer): Boolean; // 05/16/2011 pb  CR 18797
    function DoUnlockFile(hFile: THandle; dwFileOffsetLow, dwFileOffsetHigh: DWORD; nNumberOfBytesToUnlockLow, nNumberOfBytesToUnlockHigh: DWORD; const AllPages: Boolean; const PageNo: Integer): Boolean; // 05/16/2011 pb  CR 18797
    property VirtualLocks: Boolean read FVirtualLocks write FVirtualLocks;
  public
    constructor Create;
    destructor Destroy; override;

    procedure CloseFile; virtual;
    procedure OpenFile; virtual;
    procedure DeleteFile;
    procedure TryExclusive; virtual;
    procedure EndExclusive; virtual;
    procedure CheckExclusiveAccess;
    procedure DisableForceCreate;
{$ifdef SUPPORT_INT64}
    function  CalcPageOffset(const PageNo: Int64): Int64; // 03/04/2011 pb  CR 18372
{$else}
    function  CalcPageOffset(const PageNo: Integer): Integer;
{$endif}
    function  IsRecordPresent(IntRecNum: Integer): boolean;
// 06/24/2011 pb  CR 19106- ReadBlock moved here
{$ifdef SUPPORT_INT64}
    function  ReadBlock(const BlockPtr: Pointer; const ASize: Integer; const APosition: Int64): Integer; // 03/04/2011 pb  CR 18372
{$else}
    function  ReadBlock(const BlockPtr: Pointer; const ASize, APosition: Integer): Integer;
{$endif}
    function  ReadRecord(IntRecNum: Integer; Buffer: Pointer): Integer; virtual;
// 06/24/2011 pb  CR 19106- WriteBlock moved here
{$ifdef SUPPORT_INT64}
    procedure WriteBlock(const BlockPtr: Pointer; const ASize: Integer; const APosition: Int64); // 03/04/2011 pb  CR 18372
{$else}
    procedure WriteBlock(const BlockPtr: Pointer; const ASize, APosition: Integer);
{$endif}
    procedure WriteRecord(IntRecNum: Integer; Buffer: Pointer); virtual;
    procedure WriteHeader; virtual;
    function  FileCreated: Boolean;
    function  IsSharedAccess: Boolean;
    procedure ResetError; virtual;
    procedure DoProgress(Position, Max: Integer; Msg: string); // 03/10/2011 pb  CR 18709
    procedure ResyncSharedDisable; // 10/28/2011 pb  CR 19703
    procedure ResyncSharedEnable; // 10/28/2011 pb  CR 19703
    function  ResyncSharedReadBuffer: Boolean; // 10/28/2011 pb  CR 19703
    function  ResyncSharedFlushBuffer: Boolean; // 10/28/2011 pb  CR 19703

    function  LockPage(const PageNo: Integer; const Wait: Boolean): Boolean;
    function  LockAllPages(const Wait: Boolean): Boolean;
    procedure UnlockPage(const PageNo: Integer);
    procedure UnlockAllPages;

    procedure Flush; virtual;

    property Active: Boolean read FActive;
    property AutoCreate: Boolean read FAutoCreate write FAutoCreate;   // only write when closed!
    property Mode: TPagedFileMode read FMode write FMode;              // only write when closed!
    property TempMode: TPagedFileMode read FTempMode;
    property NeedLocks: Boolean read FNeedLocks;
    property HeaderOffset: Integer read FHeaderOffset write SetHeaderOffset;
    property HeaderSize: Integer read FHeaderSize write SetHeaderSize;
    property RecordSize: Integer read FRecordSize write SetRecordSize;
    property PageSize: Integer read FPageSize write SetPageSize;
    property PagesPerRecord: Integer read FPagesPerRecord;
    property RecordCount: Integer read GetRecordCount write SetRecordCount;
    property CachedRecordCount: Integer read FCachedRecordCount;
    property PageOffsetByHeader: Boolean read FPageOffsetbyHeader write SetPageOffsetByHeader;
    property FileLocked: Boolean read FFileLocked;
    property Header: PChar read FHeader;
    property FileName: string read FFileName write SetFileName;
    property Stream: TStream read FStream write SetStream;
    property BufferAhead: Boolean read FBufferAhead write SetBufferAhead;
    property WriteError: Boolean read FWriteError;
    property CachedSize: {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif} read FCachedSize;
{$ifdef SUPPORT_INT64}
    property CompatibleLockOffset: Boolean read FCompatibleLockOffset write FCompatibleLockOffset; // 05/10/2011 pb  CR 18996
{$endif}
    property OnProgress: TPagedFileProgressEvent read FOnProgress write FOnProgress; // 03/10/2011 pb  CR 18709
    property OnLockFile: TPagedFileLockUnlockFileEvent read FOnLockFile write FOnLockFile; // 05/16/2011 pb  CR 18797
    property OnUnlockFile: TPagedFileLockUnlockFileEvent read FOnUnlockFile write FOnUnlockFile; // 05/16/2011 pb  CR 18797
    property OnControlsDisabled: TPagedFileControlsDisabledEvent read FOnControlsDisabled write FOnControlsDisabled; // 10/28/2011 pb  CR 19703
  end;

// 03/04/2011 pb  CR 18759- Moved from the implementation section
// BDE compatible lock offset found!
const
{$ifdef WINDOWS}
  LockOffset = $EFFFFFFE;       // BDE compatible
  FileLockSize = 2;
{$else}
  LockOffset = $7FFFFFFF;
  FileLockSize = 1;
{$endif}

// dBase supports maximum of a billion records
//LockStart  = LockOffset - 1000000000;
  LockRange = 1000000000;

{$ifdef SUPPORT_INT64}
  LockOffsetLarge = $FFFFFFFFFFFFFFFD; // 05/10/2011 pb  CR 18996
{$endif}

implementation

uses
{$ifdef WINDOWS}
  Windows,
{$else}
{$ifdef KYLIX}
  Libc, 
{$endif}  
  Types, dbf_wtil,
{$endif}
  RTLConsts, // 03/14/2011 pb  CR 18703
  dbf_str;

//====================================================================
// TPagedFile
//====================================================================
constructor TPagedFile.Create;
begin
  FFileName := EmptyStr;
  FHeaderOffset := 0;
  FHeaderSize := 0;
  FRecordSize := 0;
  FRecordCount := 0;
  FPageSize := 0;
  FPagesPerRecord := 0;
  FActive := false;
  FHeaderModified := false;
  FPageOffsetByHeader := true;
  FNeedLocks := false;
  FMode := pfReadOnly;
  FTempMode := pfNone;
  FAutoCreate := false;
  FVirtualLocks := true;
  FFileLocked := false;
  FHeader := nil;
  FBufferPtr := nil;
  FBufferAhead := false;
  FBufferModified := false;
  FBufferSize := 0;
  FBufferMaxSize := 0;
  FBufferOffset := 0;
  FWriteError := false;
{$ifdef SUPPORT_INT64}
  FCompatibleLockOffset := true; // 05/10/2011 pb  CR 18996
{$endif}

  inherited;
end;

destructor TPagedFile.Destroy;
begin
  // close physical file
  if FFileLocked then UnlockAllPages;
  CloseFile;
  FFileLocked := false;

  // free mem
  if FHeader <> nil then
    FreeMem(FHeader);

  inherited;
end;

constructor EPagedFileOpenError.Create(FileName: string; AErrorCode: DWORD); // 03/14/2011 pb  CR 18703
begin
  inherited Create(@SFOpenErrorEx, FileName);
  fErrorCode:= AErrorCode;
end;

type
  TPagedFileStream = class(THandleStream) // 03/14/2011 pb  CR 18703
  public
    constructor Create2(const FileName: string; Mode: Word);
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override; // 05/10/2011 pb  CR 18997
    function Write(const Buffer; Count: Longint): Longint; override; // 05/10/2011 pb  CR 18997
{$ifdef SUPPORT_INT64}
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override; // 05/10/2011 pb  CR 18997
{$else}
    function Seek(Offset: Longint; Origin: Word): Longint; override; // 05/10/2011 pb  CR 18997
{$endif}
  end;

constructor TPagedFileStream.Create2(const FileName: string; Mode: Word); // 03/14/2011 pb  CR 18703
begin
  inherited Create(FileOpen(FileName, Mode));
  if FHandle < 0 then
    raise EPagedFileOpenError.Create(FileName, GetLastError);
end;

destructor TPagedFileStream.Destroy; // 03/14/2011 pb  CR 18703
begin
  if FHandle >= 0 then
    FileClose(FHandle);
  inherited Destroy;
end;

function TPagedFileStream.Read(var Buffer; Count: Longint): Longint; // 05/10/2011 pb  CR 18997
begin
  Result := FileRead(FHandle, Buffer, Count);
  if Result = -1 then RaiseLastOSError;
end;

function TPagedFileStream.Write(const Buffer; Count: Longint): Longint; // 05/10/2011 pb  CR 18997
begin
  Result := FileWrite(FHandle, Buffer, Count);
  if Result = -1 then RaiseLastOSError;
end;

{$ifdef SUPPORT_INT64}
function TPagedFileStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; // 05/10/2011 pb  CR 18997
begin
{$ifdef MSWINDOWS}
  Result:= Longint(SetFilePointer(FHandle, Longint(ULARGE_INTEGER(Offset).LowPart), @ULARGE_INTEGER(Offset).HighPart, Ord(Origin)));
  if (Result=-1 {INVALID_SET_FILE_POINTER}) and (GetLastError<>NO_ERROR) then
    RaiseLastOSError
  else
    ULARGE_INTEGER(Result).HighPart:= ULARGE_INTEGER(Offset).HighPart;
{$else}
  Result := FileSeek(FHandle, Offset, Ord(Origin));
{$endif}
end;
{$else}
function TPagedFileStream.Seek(Offset: Longint; Origin: Word): Longint; // 05/10/2011 pb  CR 18997
begin
  Result := FileSeek(FHandle, Offset, Ord(Origin));
end;
{$endif}

procedure TPagedFile.OpenFile;
var
  fileOpenMode: Word;
begin
  if FActive then exit;  

  // store user specified mode
  FUserMode := FMode;
  if not (FMode in [pfMemoryCreate, pfMemoryOpen]) then
  begin
    // test if file exists
    if not FileExists(FFileName) then
    begin
      // if auto-creating, adjust mode
      if FAutoCreate then case FMode of
        pfExclusiveOpen:             FMode := pfExclusiveCreate;
        pfReadWriteOpen, pfReadOnly: FMode := pfReadWriteCreate;
      end;
      // it seems the VCL cannot share a file that is created?
      // create file first, then open it in requested mode
      // filecreated means 'to be created' in this context ;-)
      if FileCreated then
        FileClose(FileCreate(FFileName))
      else
        raise EPagedFile.CreateFmt(STRING_FILE_NOT_FOUND,[FFileName]);
    end;
    // specify open mode
    case FMode of
//    pfExclusiveCreate: fileOpenMode := fmOpenReadWrite or fmShareDenyWrite;
//    pfExclusiveOpen:   fileOpenMode := fmOpenReadWrite or fmShareDenyWrite;
      pfExclusiveCreate: fileOpenMode := fmOpenReadWrite or fmShareExclusive; // 03/14/2011 pb  CR 18796
      pfExclusiveOpen:   fileOpenMode := fmOpenReadWrite or fmShareExclusive; // 03/14/2011 pb  CR 18796
      pfReadWriteCreate: fileOpenMode := fmOpenReadWrite or fmShareDenyNone;
      pfReadWriteOpen:   fileOpenMode := fmOpenReadWrite or fmShareDenyNone;
    else    // => readonly
                         fileOpenMode := fmOpenRead or fmShareDenyNone;
    end;
    // open file
//  FStream := TFileStream.Create(FFileName, fileOpenMode);
    FStream := TPagedFileStream.Create2(FFileName, fileOpenMode); // 03/14/2011 pb  CR 18703
    // if creating, then empty file
    if FileCreated then
      FStream.Size := 0;
  end else begin
    if FStream = nil then
    begin
      FMode := pfMemoryCreate;
      FStream := TMemoryStream.Create;
    end;
  end;
  // init size var
  FCachedSize := Stream.Size;
  // update whether we need locking
{$ifdef _DEBUG}
  FNeedLocks := true;
{$else}
  FNeedLocks := IsSharedAccess;
{$endif}
  FActive := true;
  // allocate memory for bufferahead
  UpdateBufferSize;
end;

procedure TPagedFile.CloseFile;
begin
  if FActive then
  begin
    FlushHeader;
    FlushBuffer;
    FlushOS; // 11/17/2011 pb  CR 19755
    // don't free the user's stream
    if not (FMode in [pfMemoryOpen, pfMemoryCreate]) then
      FreeAndNil(FStream);
    // free bufferahead buffer
    FreeMemAndNil(FBufferPtr);

    // mode possibly overridden in case of auto-created file
    FMode := FUserMode;
    FActive := false;
    FCachedRecordCount := 0;
  end;
end;

procedure TPagedFile.DeleteFile;
begin
  // opened -> we can not delete
  if not FActive then
    SysUtils.DeleteFile(FileName);
end;

function TPagedFile.FileCreated: Boolean;
const
  CreationModes: array [pfNone..pfReadOnly] of Boolean =
    (false, true, false, true, false, true, false, false);
//   node, memcr, memop, excr, exopn, rwcr, rwopn, rdonly
begin
  Result := CreationModes[FMode];
end;

function TPagedFile.IsSharedAccess: Boolean;
const
  SharedAccessModes: array [pfNone..pfReadOnly] of Boolean =
    (false, false, false, false, false, true, true,  true);
//   node,  memcr, memop, excr,  exopn, rwcr, rwopn, rdonly
begin
  Result := SharedAccessModes[FMode];
end;

procedure TPagedFile.CheckExclusiveAccess;
begin
  // in-memory => exclusive access!
  if IsSharedAccess then
    raise EDbfError.Create(STRING_NEED_EXCLUSIVE_ACCESS);
end;

{$ifdef SUPPORT_INT64}
function TPagedFile.CalcPageOffset(const PageNo: Int64): Int64; // 03/04/2011 pb  CR 18372
{$else}
function TPagedFile.CalcPageOffset(const PageNo: Integer): Integer;
{$endif}
begin
  if not FPageOffsetByHeader then
    Result := FPageSize * PageNo
  else if PageNo = 0 then
    Result := 0
  else
    Result := FHeaderOffset + FHeaderSize + (FPageSize * (PageNo - 1))
end;

{$ifdef SUPPORT_INT64}
procedure TPagedFile.CheckCachedSize(const APosition: Int64); // 03/04/2011 pb  CR 18372
{$else}
procedure TPagedFile.CheckCachedSize(const APosition: Integer);
{$endif}
begin
  // file expanded?
  if APosition > FCachedSize then
  begin
    FCachedSize := APosition;
    FNeedRecalc := true;
  end;
end;

function TPagedFile.Read(Buffer: Pointer; ASize: Integer): Integer;
var
  ErrorCode: DWORD; // 05/10/2011 pb  CR 18997
begin
  // if we cannot read due to a lock, then wait a bit
  repeat
    try
      ErrorCode := ERROR_SUCCESS; // 05/10/2011 pb  CR 18997
      Result := FStream.Read(Buffer^, ASize);
    except
      on E: EOSError do // 05/10/2011 pb  CR 18997
      begin
        ErrorCode := E.ErrorCode;
        Result := 0;
        if (ErrorCode <> ERROR_LOCK_VIOLATION) or VirtualLocks then
          raise;
      end;
    else
      raise; // 05/10/2011 pb  CR 18997
    end;
    if Result = 0 then
    begin
      // translation to linux???
//    if GetLastError = ERROR_LOCK_VIOLATION then
      if ErrorCode = ERROR_LOCK_VIOLATION then // 05/10/2011 pb  CR 18997
      begin
        // wait a bit until block becomes available
        Sleep(1);
      end else begin
        // return empty block
        exit;
      end;
    end else
      exit;
  until false;
end;

{$ifdef SUPPORT_INT64}
procedure TPagedFile.UpdateCachedSize(CurrPos: Int64); // 03/04/2011 pb  CR 18372
{$else}
procedure TPagedFile.UpdateCachedSize(CurrPos: Integer);
{$endif}
begin
  // have we added a record?
  if CurrPos > FCachedSize then
  begin
    // update cached size, always at end
    repeat
      Inc(FCachedSize, FRecordSize);
      Inc(FRecordCount, PagesPerRecord);
    until FCachedSize >= CurrPos;
  end;
end;

function TPagedFile.DoLockFile(hFile: THandle; dwFileOffsetLow, dwFileOffsetHigh: DWORD; nNumberOfBytesToLockLow, nNumberOfBytesToLockHigh: DWORD; const AllPages: Boolean; const PageNo: Integer): Boolean; // 05/16/2011 pb  CR 18797
var
  Handled: Boolean;
begin
  Handled := False;
  if Assigned(FOnLockFile) then
    FOnLockFile(Self, Handled, Result, hFile, dwFileOffsetLow, dwFileOffsetHigh, nNumberOfBytesToLockLow, nNumberOfBytesToLockHigh, AllPages, PageNo);
  if not Handled then
  begin
    if FFileLocked then
      Result := True
    else
      Result := LockFile(hFile, dwFileOffsetLow, dwFileOffsetHigh, nNumberOfBytesToLockLow, nNumberOfBytesToLockHigh);
  end;
end;

function TPagedFile.DoUnlockFile(hFile: THandle; dwFileOffsetLow, dwFileOffsetHigh: DWORD; nNumberOfBytesToUnlockLow, nNumberOfBytesToUnlockHigh: DWORD; const AllPages: Boolean; const PageNo: Integer): Boolean; // 05/16/2011 pb  CR 18797
var
  Handled: Boolean;
begin
  Handled := False;
  if Assigned(FOnUnlockFile) then
    FOnUnlockFile(Self, Handled, Result, hFile, dwFileOffsetLow, dwFileOffsetHigh, nNumberOfBytesToUnlockLow, nNumberOfBytesToUnlockHigh, AllPages, PageNo);
  if not Handled then
  begin
    if FFileLocked then
      Result := True
    else
      Result := UnlockFile(hFile, dwFileOffsetLow, dwFileOffsetHigh, nNumberOfBytesToUnlockLow, nNumberOfBytesToUnlockHigh);
  end;
end;

procedure TPagedFile.FlushBuffer;
begin
  if FBufferAhead and FBufferModified then
  begin
    WriteBlock(FBufferPtr, FBufferSize, FBufferOffset);
    FBufferModified := false;
  end;
end;

procedure TPagedFile.FlushOS; // 11/17/2011 pb  CR 19755
begin
{$ifdef WINDOWS}
  if FStream is THandleStream then
    FlushFileBuffers(THandleStream(FStream).Handle);
{$endif}
end;

function TPagedFile.SingleReadRecord(IntRecNum: Integer; Buffer: Pointer): Integer;
begin
  Result := ReadBlock(Buffer, RecordSize, CalcPageOffset(IntRecNum));
end;

procedure TPagedFile.SingleWriteRecord(IntRecNum: Integer; Buffer: Pointer);
begin
  WriteBlock(Buffer, RecordSize, CalcPageOffset(IntRecNum));
end;

function TPagedFile.ReadBuffer: Boolean; // 10/28/2011 pb  CR 19703
begin
  Result := FBufferAhead and (FBufferReadSize <> 0);
  if Result then
    FBufferReadSize := ReadBlock(FBufferPtr, FBufferReadSize, FBufferOffset);
end;

procedure TPagedFile.SynchronizeBuffer(IntRecNum: Integer);
var
  BufferPageMin: Integer; // 10/28/2011 pb  CR 19176
begin
  // record outside buffer, flush previous buffer
  FlushBuffer;
  // read new set of records
//FBufferPage := IntRecNum;
//FBufferOffset := CalcPageOffset(IntRecNum);
//if FBufferOffset + FBufferMaxSize > FCachedSize then
//  FBufferReadSize := FCachedSize - FBufferOffset
//else
//  FBufferReadSize := FBufferMaxSize;
  if (FBufferPage >= 0) and ((IntRecNum < Pred(FBufferPage)) or (IntRecNum > FBufferPage + (FBufferSize div PageSize))) then // 10/28/2011 pb  CR 19176
    FBufferReadSize := RecordSize // 10/28/2011 pb  CR 19176- Optimize for random access
  else
    FBufferReadSize := FBufferMaxSize; // 10/28/2011 pb  CR 19176- Optimize for sequential access
  if IntRecNum < FBufferPage then // 10/28/2011 pb  CR 19176
  begin
    if FPageOffsetByHeader then // 10/28/2011 pb  CR
      BufferPageMin := 1 // 10/28/2011 pb  CR
    else
      BufferPageMin := 0; // 10/28/2011 pb  CR
    FBufferPage := (IntRecNum + 1) - (FBufferReadSize div PageSize); // 10/28/2011 pb  CR 19176
    if FBufferPage < BufferPageMin then // 10/28/2011 pb  CR 19176
    begin
      Dec(FBufferReadSize, (BufferPageMin - FBufferPage) * PageSize); // 10/28/2011 pb  CR 19176 - Truncate buffer at BOF
      FBufferPage := BufferPageMin; // 10/28/2011 pb  CR 19176 - Truncate buffer at BOF
    end;
  end
  else
    FBufferPage := IntRecNum;
  FBufferOffset := CalcPageOffset(FBufferPage); // 10/28/2011 pb  CR 19176
  if FBufferOffset + FBufferReadSize > FCachedSize then // 10/28/2011 pb  CR 19176 - Truncate buffer at EOF
    FBufferReadSize := FCachedSize - FBufferOffset; // 10/28/2011 pb  CR 19176 - Truncate buffer at EOF
  FBufferSize := FBufferReadSize;
//if FBufferReadSize <> 0 then // 05/04/2011 pb  CR 18913
//  FBufferReadSize := ReadBlock(FBufferPtr, FBufferReadSize, FBufferOffset);
  ReadBuffer; // 10/28/2011 pb  CR 19703
end;

function TPagedFile.ResyncSharedEnabled: Boolean; // 10/28/2011 pb  CR 19703
begin
  Result := IsSharedAccess and (FResyncSharedEnabled >= 0);
  if Assigned(FOnControlsDisabled) then
    Result := Result and (not FOnControlsDisabled);
end;

function TPagedFile.ResyncSharedReadBuffer: Boolean; // 10/28/2011 pb  CR 19703
begin
  Result := ResyncSharedEnabled and (not FFileLocked);
  if Result then
    Result := ReadBuffer;
end;

function TPagedFile.ResyncSharedFlushBuffer: Boolean; // 10/28/2011 pb  CR 19703
begin
  Result := ResyncSharedEnabled;
  if Result then
    FlushBuffer;
end;

function TPagedFile.IsRecordPresent(IntRecNum: Integer): boolean;
begin
  // if in shared mode, recordcount can only increase, check if recordno
  // in range for cached recordcount
  if not IsSharedAccess or (IntRecNum > FCachedRecordCount) then
    FCachedRecordCount := RecordCount;
  Result := (0 <= IntRecNum) and (IntRecNum <= FCachedRecordCount);
end;

function TPagedFile.ReadRecord(IntRecNum: Integer; Buffer: Pointer): Integer;
var
//Offset: Integer;
  Offset: {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif}; // 03/04/2011 pb  CR 18372
begin
  if FBufferAhead then
  begin
//  Offset := (IntRecNum - FBufferPage) * PageSize;
    Offset := {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif}(IntRecNum - FBufferPage) * PageSize; // 03/04/2011 pb  CR 18372
//  if (FBufferPage <> -1) and (FBufferPage <= IntRecNum) and
//      (Offset+RecordSize <= FBufferReadSize) then
    if (FBufferPage <> -1) and (FBufferPage <= IntRecNum) and (Offset+RecordSize <= FBufferSize) then  // 10/28/2011 pb  CR 19176
    begin
      // have record in buffer, nothing to do here
    end else begin
      // need to update buffer
      SynchronizeBuffer(IntRecNum);
      // check if enough bytes read
      if RecordSize > FBufferReadSize then
      begin
        Result := 0;
        exit;
      end;
      // reset offset into buffer
//    Offset := 0;
      Offset := {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif}(IntRecNum - FBufferPage) * PageSize; // 10/28/2011 pb  CR 19176
    end;
    // now we have this record in buffer
    Move(PChar(FBufferPtr)[Offset], Buffer^, RecordSize);
    // successful
    Result := RecordSize;
  end else begin
    // no buffering
    Result := SingleReadRecord(IntRecNum, Buffer);
  end;
end;

procedure TPagedFile.WriteRecord(IntRecNum: Integer; Buffer: Pointer);
var
//RecEnd: Int64;
  RecEnd: {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif}; // 03/04/2011 pb  CR 18372
begin
  if FBufferAhead then
  begin
//  RecEnd := (IntRecNum - FBufferPage + PagesPerRecord) * PageSize;
    RecEnd := {$ifdef SUPPORT_INT64}Int64{$else}Integer{$endif}(IntRecNum - FBufferPage + PagesPerRecord) * PageSize; // 03/04/2011 pb  CR 18372
//  if (FBufferPage <> -1) and (FBufferPage <= IntRecNum) and
//      (RecEnd <= FBufferMaxSize) then
    if (FBufferPage <> -1) and (FBufferPage <= IntRecNum) and (RecEnd <= FBufferMaxSize) and (RecEnd <= FBufferSize + RecordSize) then // 10/28/2011 pb  CR 19176
    begin
      // extend buffer?
      if RecEnd > FBufferSize then
        FBufferSize := RecEnd;
    end else begin
      // record outside buffer, need to synchronize first
      SynchronizeBuffer(IntRecNum);
      RecEnd := PagesPerRecord * PageSize;
      FBufferSize := RecEnd; // 05/16/2011 pb  CR 18913
    end;
    // we can write this record to buffer
    Move(Buffer^, PChar(FBufferPtr)[RecEnd-RecordSize], RecordSize);
    FBufferModified := true;
    // update cached size
    UpdateCachedSize(FBufferOffset+RecEnd);
    ResyncSharedFlushBuffer; // 10/28/2011 pb  CR 19703
  end else begin
    // no buffering
    SingleWriteRecord(IntRecNum, Buffer);
    // update cached size
    UpdateCachedSize(FStream.Position);
  end;
end;

procedure TPagedFile.SetBufferAhead(NewValue: Boolean);
begin
  if FBufferAhead <> NewValue then
  begin
    FlushBuffer;
    FBufferAhead := NewValue;
    UpdateBufferSize;
  end;
end;

procedure TPagedFile.SetStream(NewStream: TStream);
begin
  if not FActive then
    FStream := NewStream;
end;

procedure TPagedFile.SetFileName(NewName: string);
begin
  if not FActive then
    FFileName := NewName;
end;

procedure TPagedFile.UpdateBufferSize;
begin
  if FBufferAhead then
  begin
    FBufferMaxSize := 65536;
    if RecordSize <> 0 then
//    Dec(FBufferMaxSize, FBufferMaxSize mod PageSize);
      Dec(FBufferMaxSize, FBufferMaxSize mod RecordSize); // 10/28/2011 pb  CR 19176
    if FBufferMaxSize < RecordSize then // 10/28/2011 pb  CR 19176
      FBufferMaxSize := RecordSize; // 10/28/2011 pb  CR 19176
  end else begin
    FBufferMaxSize := 0;
  end;

  if FBufferPtr <> nil then
    FreeMem(FBufferPtr);
  if FBufferAhead and (FBufferMaxSize <> 0) then
    GetMem(FBufferPtr, FBufferMaxSize)
  else
    FBufferPtr := nil;
  FBufferPage := -1;
  FBufferOffset := -1;
  FBufferModified := false;
end;

procedure TPagedFile.WriteHeader;
begin
  FHeaderModified := true;
  if FNeedLocks then
    FlushHeader;
end;

procedure TPagedFile.FlushHeader;
begin
  if FHeaderModified then
  begin
    FStream.Position := FHeaderOffset;
    FWriteError := (FStream.Write(FHeader^, FHeaderSize) = 0) or FWriteError;
    // test if written new header
    if FStream.Position > FCachedSize then
    begin
      // new header -> record count unknown
      FCachedSize := FStream.Position;
      FNeedRecalc := true;
    end;
    FHeaderModified := false;
  end;
end;

//procedure TPagedFile.ReadHeader;
function TPagedFile.ReadHeader: Integer; // 04/26/2011 pb  CR 18944
   { assumes header is large enough }
var
{$ifdef SUPPORT_INT64}
  size: Int64; // 03/04/2011 pb  CR 18372
{$else}
  size: Integer;
{$endif}
begin
  // save changes before reading new header
  FlushHeader;
  // check if header length zero
  if FHeaderSize <> 0 then
  begin
    // get size left in file for header
    size := FStream.Size - FHeaderOffset;
    // header start before EOF?
    if size >= 0 then
    begin
      // go to header start
      FStream.Position := FHeaderOffset;
      // whole header in file?
      if size >= FHeaderSize then
      begin
        // read header, nothing to be cleared
        Read(FHeader, FHeaderSize);
        size := FHeaderSize;
      end else begin
        // read what we can, clear rest
        Read(FHeader, size);
      end;
    end else begin
      // header start before EOF, clear header
      size := 0;
    end;
    FillChar(FHeader[size], FHeaderSize-size, 0);
    Result := size; // 04/26/2011 pb  CR 18944
  end
  else
    Result := 0; // 04/26/2011 pb  CR 18944
end;

procedure TPagedFile.TryExclusive;
const NewTempMode: array[pfReadWriteCreate..pfReadOnly] of TPagedFileMode =
    (pfReadWriteOpen, pfReadWriteOpen, pfReadOnly);
begin
  // already in temporary exclusive mode?
  if (FTempMode = pfNone) and IsSharedAccess then
  begin
    // save temporary mode, if now creating, then reopen non-create
    FTempMode := NewTempMode[FMode];
    // try exclusive mode
    CloseFile;
    FMode := pfExclusiveOpen;
    try
      OpenFile;
    except
      on EFOpenError do
      begin
        // we failed, reopen normally
        EndExclusive;
      end;
    end;
  end;
end;

procedure TPagedFile.EndExclusive;
begin
  // are we in temporary file mode?
  if FTempMode <> pfNone then
  begin
    CloseFile;
    FMode := FTempMode;
    FTempMode := pfNone;
    OpenFile;
  end;
end;

procedure TPagedFile.DisableForceCreate;
begin
  case FMode of
    pfExclusiveCreate: FMode := pfExclusiveOpen;
    pfReadWriteCreate: FMode := pfReadWriteOpen;
  end;
end;

procedure TPagedFile.SetHeaderOffset(NewValue: Integer);
//
// *) assumes is called right before SetHeaderSize
//
begin
  if FHeaderOffset <> NewValue then
  begin
    FlushHeader;
    FHeaderOffset := NewValue;
  end;
end;

procedure TPagedFile.SetHeaderSize(NewValue: Integer);
begin
  if FHeaderSize <> NewValue then
  begin
    FlushHeader;
    if (FHeader <> nil) and (NewValue <> 0) then
      FreeMem(FHeader);
    FHeaderSize := NewValue;
    if FHeaderSize <> 0 then
      GetMem(FHeader, FHeaderSize);
    FNeedRecalc := true;
    ReadHeader;
  end;
end;

procedure TPagedFile.SetRecordSize(NewValue: Integer);
begin
  if FRecordSize <> NewValue then
  begin
    FRecordSize := NewValue;
    FPageSize := NewValue;
    FNeedRecalc := true;
    RecalcPagesPerRecord;
  end;
end;

procedure TPagedFile.SetPageSize(NewValue: Integer);
begin
  if FPageSize <> NewValue then
  begin
    FPageSize := NewValue;
    FNeedRecalc := true;
    RecalcPagesPerRecord;
    UpdateBufferSize;
  end;
end;

procedure TPagedFile.RecalcPagesPerRecord;
begin
  if FPageSize = 0 then
    FPagesPerRecord := 0
  else
    FPagesPerRecord := FRecordSize div FPageSize;
end;

function TPagedFile.GetRecordCount: Integer;
var
{$ifdef SUPPORT_INT64}
  currSize: Int64; // 03/04/2011 pb  CR 18372
{$else}
  currSize: Integer;
{$endif}
begin
  // file size changed?
  if FNeedLocks then
  begin
    currSize := FStream.Size;
    if currSize <> FCachedSize then
    begin
      FCachedSize := currSize;
      FNeedRecalc := true;
    end;
  end;

  // try to optimize speed
  if FNeedRecalc then
  begin
    // no file? test flags
    if (FPageSize = 0) or not FActive then
      FRecordCount := 0
    else
    if FPageOffsetByHeader then
      FRecordCount := (FCachedSize - FHeaderSize - FHeaderOffset) div FPageSize
    else
      FRecordCount := FCachedSize div FPageSize;
    if FRecordCount < 0 then
      FRecordCount := 0;

    // count updated
    FNeedRecalc := false;
  end;
  Result := FRecordCount;
end;

procedure TPagedFile.SetRecordCount(NewValue: Integer);
begin
  if RecordCount <> NewValue then
  begin
    if FPageOffsetByHeader then
      FCachedSize := FHeaderSize + FHeaderOffset + FPageSize * NewValue
    else
      FCachedSize := FPageSize * NewValue;
//    FCachedSize := CalcPageOffset(NewValue);
    FRecordCount := NewValue;
    FStream.Size := FCachedSize;
  end;
end;

procedure TPagedFile.SetPageOffsetByHeader(NewValue: Boolean);
begin
  if FPageOffsetByHeader <> NewValue then
  begin
    FPageOffsetByHeader := NewValue;
    FNeedRecalc := true;
  end;
end;

procedure TPagedFile.WriteChar(c: Byte);
begin
  FWriteError := (FStream.Write(c, 1) = 0) or FWriteError;
end;

function TPagedFile.ReadChar: Byte;
begin
  Read(@Result, 1);
end;

procedure TPagedFile.Flush;
begin
end;

{$ifdef SUPPORT_INT64}
function TPagedFile.ReadBlock(const BlockPtr: Pointer; const ASize: Integer; const APosition: Int64): Integer; // 03/04/2011 pb  CR 18372
{$else}
function TPagedFile.ReadBlock(const BlockPtr: Pointer; const ASize, APosition: Integer): Integer;
{$endif}
begin
  FStream.Position := APosition;
  CheckCachedSize(APosition);
  Result := Read(BlockPtr, ASize);
end;

{$ifdef SUPPORT_INT64}
procedure TPagedFile.WriteBlock(const BlockPtr: Pointer; const ASize: Integer; const APosition: Int64); // 03/04/2011 pb  CR 18372
{$else}
procedure TPagedFile.WriteBlock(const BlockPtr: Pointer; const ASize, APosition: Integer);
{$endif}
  // assumes a lock is held if necessary prior to calling this function
begin
  FStream.Position := APosition;
  CheckCachedSize(APosition);
  FWriteError := (FStream.Write(BlockPtr^, ASize) = 0) or FWriteError;
end;

procedure TPagedFile.ResetError;
begin
  FWriteError := false;
end;

procedure TPagedFile.DoProgress(Position, Max: Integer; Msg: string); // 03/10/2011 pb  CR 18709
var
  Aborted: Boolean;
begin
  Aborted:= False;
  if Assigned(FOnProgress) then
    FOnProgress(Self, Position, Max, Aborted, Msg);
  if Aborted then
    Abort;
end;

procedure TPagedFile.ResyncSharedDisable; // 10/28/2011 pb  CR 19703
begin
  Dec(FResyncSharedEnabled);
end;

procedure TPagedFile.ResyncSharedEnable; // 10/28/2011 pb  CR 19703
begin
  Inc(FResyncSharedEnabled);
end;

// 03/04/2011 pb  CR 18759- Moved to the interface section
(*
// BDE compatible lock offset found!
const
{$ifdef WINDOWS}
  LockOffset = $EFFFFFFE;       // BDE compatible
  FileLockSize = 2;
{$else}
  LockOffset = $7FFFFFFF;
  FileLockSize = 1;
{$endif}

// dBase supports maximum of a billion records
  LockStart  = LockOffset - 1000000000;
*)

{$ifdef SUPPORT_INT64}
//function TPagedFile.LockSection(const Offset: Int64; const Length: Cardinal; const Wait: Boolean): Boolean; // 03/04/2011 pb  CR 18372
function TPagedFile.LockSection(const Offset: Int64; const Length: Cardinal; const Wait, AllPages: Boolean; const PageNo: Integer): Boolean; // 05/16/2011 pb  CR 18797
{$else}
//function TPagedFile.LockSection(const Offset, Length: Cardinal; const Wait: Boolean): Boolean;
function TPagedFile.LockSection(const Offset, Length: Cardinal; const Wait, AllPages: Boolean; const PageNo: Integer): Boolean; // 05/16/2011 pb  CR 18797
{$endif}
  // assumes FNeedLock = true
var
  Failed: Boolean;
begin
  // FNeedLocks => FStream is of type TFileStream
  Failed := false;
  repeat
{$ifdef SUPPORT_INT64}
//  Result := LockFile(TFileStream(FStream).Handle, ULARGE_INTEGER(Offset).LowPart, ULARGE_INTEGER(Offset).HighPart, Length, 0); // 03/04/2011 pb  CR 18372
//  Result := LockFile(THandleStream(FStream).Handle, ULARGE_INTEGER(Offset).LowPart, ULARGE_INTEGER(Offset).HighPart, Length, 0); // 03/14/2011 pb  CR 18703
    Result := DoLockFile(THandleStream(FStream).Handle, ULARGE_INTEGER(Offset).LowPart, ULARGE_INTEGER(Offset).HighPart, Length, 0, AllPages, PageNo); // 05/16/2011 pb  CR 18797
{$else}
//  Result := LockFile(TFileStream(FStream).Handle, Offset, 0, Length, 0);
//  Result := LockFile(THandleStream(FStream).Handle, Offset, 0, Length, 0); // 03/14/2011 pb  CR 18703
    Result := DoLockFile(THandleStream(FStream).Handle, Offset, 0, Length, 0, AllPages, PageNo); // 05/16/2011 pb  CR 18797
{$endif}
    // test if lock violation, then wait a bit and try again
    if not Result and Wait then
    begin
      if (GetLastError = ERROR_LOCK_VIOLATION) then
        Sleep(10)
      else
        Failed := true;
    end;
  until Result or not Wait or Failed;
end;

{$ifdef SUPPORT_INT64}
//function TPagedFile.UnlockSection(const Offset: Int64; const Length: Cardinal): Boolean; // 03/04/2011 pb  CR 18372
function TPagedFile.UnlockSection(const Offset: Int64; const Length: Cardinal; const AllPages: Boolean; const PageNo: Integer): Boolean; // 05/16/2011 pb  CR 18797
{$else}
//function TPagedFile.UnlockSection(const Offset, Length: Cardinal): Boolean;
function TPagedFile.UnlockSection(const Offset, Length: Cardinal; const AllPages: Boolean; const PageNo: Integer): Boolean; // 05/16/2011 pb  CR 18797
{$endif}
begin
//Result := UnlockFile(TFileStream(FStream).Handle, Offset, 0, Length, 0);
  if Assigned(FStream) then // 01/18/2011 dhd CR 18640
{$ifdef SUPPORT_INT64}
//  Result := UnlockFile(TFileStream(FStream).Handle, ULARGE_INTEGER(Offset).LowPart, ULARGE_INTEGER(Offset).HighPart, Length, 0) // 03/04/2011 pb  CR 18372
//  Result := UnlockFile(THandleStream(FStream).Handle, ULARGE_INTEGER(Offset).LowPart, ULARGE_INTEGER(Offset).HighPart, Length, 0) // 03/14/2011 pb  CR 18703
    Result := DoUnlockFile(THandleStream(FStream).Handle, ULARGE_INTEGER(Offset).LowPart, ULARGE_INTEGER(Offset).HighPart, Length, 0, AllPages, PageNo) // 05/16/2011 pb  CR 18797
{$else}
//  Result := UnlockFile(TFileStream(FStream).Handle, Offset, 0, Length, 0)
//  Result := UnlockFile(THandleStream(FStream).Handle, Offset, 0, Length, 0) // 03/14/2011 pb  CR 18703
    Result := DoUnlockFile(THandleStream(FStream).Handle, Offset, 0, Length, 0, AllPages, PageNo) // 05/16/2011 pb  CR 18797
{$endif}
  else
    Result := true;
end;

function TPagedFile.LockAllPages(const Wait: Boolean): Boolean;
var
  Offset: {$ifdef SUPPORT_INT64}Int64{$else}Cardinal{$endif};
  Length: Cardinal;
begin
  // do we need locking?
  if FNeedLocks and not FFileLocked then
  begin
    if FVirtualLocks then
    begin
{$ifdef SUPPORT_INT64}
      if FCompatibleLockOffset then // 05/10/2011 pb  CR 18996
      begin
{$endif}
{$ifdef SUPPORT_UINT32_CARDINAL}
//        Offset := LockStart;
//        Length := LockOffset - LockStart + FileLockSize;
        Offset := LockOffset; // 05/16/2011 pb  CR 18759
        Length := FileLockSize; // 05/16/2011 pb  CR 18759
{$else}
        // delphi 3 has strange types:
        // cardinal 0..2 GIG ?? does it produce correct code?
//      Offset := Cardinal(LockStart);
//      Length := Cardinal(LockOffset) - Cardinal(LockStart) + FileLockSize;
        Offset := Cardinal(LockOffset); // 05/16/2011 pb  CR 18759
        Length := Cardinal(FileLockSize); // 05/16/2011 pb  CR 18759
{$endif}
{$ifdef SUPPORT_INT64}
      end
      else
      begin
        Offset := LockOffsetLarge; // 05/10/2011 pb  CR 18996
        Length := FileLockSize; // 05/10/2011 pb  CR 18996
      end;
{$endif}
    end else begin
      Offset := 0;
      Length := $7FFFFFFF;
    end;
    // lock requested section
//  Result := LockSection(Offset, Length, Wait);
    Result := LockSection(Offset, Length, Wait, True, 0); // 05/16/2011 pb  CR 18797
    if FVirtualLocks and Result then // 05/16/2011 pb  CR 18759
    begin
//    Result := LockSection(Offset-LockRange, LockRange, Wait);
      Result := LockSection(Offset-LockRange, LockRange, Wait, False, 0); // 05/16/2011 pb  CR 18797
      if Result then
//      UnlockSection(Offset-LockRange, LockRange)
        UnlockSection(Offset-LockRange, LockRange, False, 0) // 05/16/2011 pb  CR 18797
      else
//      UnlockSection(Offset, Length);
        UnlockSection(Offset, Length, True, 0); // 05/16/2011 pb  CR 18797
    end;
    FFileLocked := Result;
  end else
    Result := true;
end;

procedure TPagedFile.UnlockAllPages;
var
  Offset: {$ifdef SUPPORT_INT64}Int64{$else}Cardinal{$endif};
  Length: Cardinal;
begin
  // do we need locking?
  if FNeedLocks and FFileLocked then
  begin
    if FVirtualLocks then
    begin
{$ifdef SUPPORT_INT64}
      if FCompatibleLockOffset then // 05/10/2011 pb  CR 18996
      begin
{$endif}
{$ifdef SUPPORT_UINT32_CARDINAL}
//      Offset := LockStart;
//      Length := LockOffset - LockStart + FileLockSize;
        Offset := LockOffset; // 05/16/2011 pb  CR 18759
        Length := FileLockSize; // 05/16/2011 pb  CR 18759
{$else}
        // delphi 3 has strange types:
        // cardinal 0..2 GIG ?? does it produce correct code?
//      Offset := Cardinal(LockStart);
//      Length := Cardinal(LockOffset) - Cardinal(LockStart) + FileLockSize;
        Offset := Cardinal(LockOffset); // 05/16/2011 pb  CR 18759
        Length := Cardinal(FileLockSize); // 05/16/2011 pb  CR 18759
{$endif}
{$ifdef SUPPORT_INT64}
      end
      else
      begin
        Offset := LockOffsetLarge; // 05/10/2011 pb  CR 18996
        Length := FileLockSize; // 05/10/2011 pb  CR 18996
      end;
{$endif}
    end else begin
      Offset := 0;
      Length := $7FFFFFFF;
    end;
    // unlock requested section
    // FNeedLocks => FStream is of type TFileStream
//  FFileLocked := not UnlockSection(Offset, Length);
    FFileLocked := not UnlockSection(Offset, Length, True, 0); // 05/16/2011 pb  CR 18797
  end;
end;

function TPagedFile.LockPage(const PageNo: Integer; const Wait: Boolean): Boolean;
var
  Offset: {$ifdef SUPPORT_INT64}Int64{$else}Cardinal{$endif}; // 03/04/2011 pb  CR 18372
  Length: Cardinal;
begin
  // do we need locking?
//if FNeedLocks and not FFileLocked then
  if FNeedLocks then // 05/16/2011 pb  CR 18797
  begin
    if FVirtualLocks then
    begin
{$ifdef SUPPORT_INT64}
      if FCompatibleLockOffset then // 05/10/2011 pb  CR 18996
      begin
{$endif}
        if PageNo >= 0 then
          Offset := LockOffset - Cardinal(PageNo)
        else
          Offset := LockOffset + Cardinal(-PageNo); // 05/27/2011 pb  CR 18759
        Length := 1;
{$ifdef SUPPORT_INT64}
      end
      else
      begin
        Offset := LockOffsetLarge - PageNo; // 05/10/2011 pb  CR 18996
        Length := 1; // 05/10/2011 pb  CR 18996
      end;
{$endif}
    end else begin
      Offset := CalcPageOffset(PageNo);
      Length := RecordSize;
    end;
    // lock requested section
//   Result := LockSection(Offset, Length, Wait);
    Result := LockSection(Offset, Length, Wait, False, PageNo); // 05/16/2011 pb  CR 18797
  end else
    Result := true;
end;

procedure TPagedFile.UnlockPage(const PageNo: Integer);
var
  Offset: {$ifdef SUPPORT_INT64}Int64{$else}Cardinal{$endif}; // 03/04/2011 pb  CR 18372
  Length: Cardinal;
begin
  // do we need locking?
//if FNeedLocks and not FFileLocked then
  if FNeedLocks then // 05/16/2011 pb  CR 18797
  begin
    // calc offset + length
    if FVirtualLocks then
    begin
{$ifdef SUPPORT_INT64}
      if FCompatibleLockOffset then // 05/10/2011 pb  CR 18996
      begin
{$endif}
        if PageNo >= 0 then
          Offset := LockOffset - Cardinal(PageNo)
        else
          Offset := LockOffset + Cardinal(-PageNo); // 05/27/2011 pb  CR 18759
        Length := 1;
{$ifdef SUPPORT_INT64}
      end
      else
      begin
        Offset := LockOffsetLarge - PageNo; // 05/10/2011 pb  CR 18996
        Length := 1; // 05/10/2011 pb  CR 18996
      end;
{$endif}
    end else begin
      Offset := CalcPageOffset(PageNo);
      Length := RecordSize;
    end;
    // unlock requested section
    // FNeedLocks => FStream is of type TFileStream
//  UnlockSection(Offset, Length);
    UnlockSection(Offset, Length, False, PageNo); // 05/16/2011 pb  CR 18797
  end;
end;

end.

