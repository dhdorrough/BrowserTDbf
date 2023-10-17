unit KillIt;

interface

implementation

uses
  Windows;

procedure KillTheApp;
begin
  TerminateProcess(GetCurrentProcess, 0);
end;


initialization
  ExitProcessProc := KillTheApp;
end.
 