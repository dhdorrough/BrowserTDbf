unit dbf_cursor;

// Modifications by BCC Software
// 08/18/2011 pb  CR 19448- 64-bit sequential record numbers to avoid "Integer overflow"

interface

{$I dbf_common.inc}

uses
  SysUtils,
  Classes,
  dbf_pgfile,
  dbf_common;

type

//====================================================================
  TVirtualCursor = class(TObject)
  private
    FFile: TPagedFile;

  protected
    function GetPhysicalRecno: Integer; virtual; abstract;
//  function GetSequentialRecno: Integer; virtual; abstract;
    function GetSequentialRecno: TSequentialRecNo; virtual; abstract; // 08/18/2011 pb  CR 19448
//  function GetSequentialRecordCount: Integer; virtual; abstract;
    function GetSequentialRecordCount: TSequentialRecNo; virtual; abstract; // 08/18/2011 pb  CR 19448
    procedure SetPhysicalRecno(Recno: Integer); virtual; abstract;
//  procedure SetSequentialRecno(Recno: Integer); virtual; abstract; // 08/18/2011 pb  CR 19448
    procedure SetSequentialRecno(Recno: TSequentialRecNo); virtual; abstract;

  public
    constructor Create(pFile: TPagedFile);
    destructor Destroy; override;

    function  RecordSize: Integer;

    function  Next: Boolean; virtual; abstract;
    function  Prev: Boolean; virtual; abstract;
    procedure First; virtual; abstract;
    procedure Last; virtual; abstract;

    property PagedFile: TPagedFile read FFile;
    property PhysicalRecNo: Integer read GetPhysicalRecNo write SetPhysicalRecNo;
//  property SequentialRecNo: Integer read GetSequentialRecNo write SetSequentialRecNo;
    property SequentialRecNo: TSequentialRecNo read GetSequentialRecNo write SetSequentialRecNo; // 08/18/2011 pb  CR 19448
//  property SequentialRecordCount: Integer read GetSequentialRecordCount;
    property SequentialRecordCount: TSequentialRecNo read GetSequentialRecordCount; // 08/18/2011 pb  CR 19448
  end;

implementation

constructor TVirtualCursor.Create(pFile: TPagedFile);
begin
  FFile := pFile;
end;

destructor TVirtualCursor.Destroy; {override;}
begin
end;

function TVirtualCursor.RecordSize : Integer;
begin
  if FFile = nil then
    Result := 0
  else
    Result := FFile.RecordSize;
end;

end.

