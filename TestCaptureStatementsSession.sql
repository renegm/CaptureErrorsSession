USE Tools;
SET NOCOUNT ON;

DECLARE @result nvarchar(MAX), @SessionEvent sysname = 'SessionEventqqq';

EXEC Tools.CaptureStatements @SessionEvent = @SessionEvent, @Action = 'Create', @result = @result OUTPUT;
PRINT 'Create: ' + @result;
EXEC Tools.CaptureStatements @SessionEvent = @SessionEvent, @Action = 'Start', @result = @result OUTPUT;
--PRINT 'Start: ' + @result;
DECLARE @procname nvarchar(1280) = 'SELECT 1 AS qqq union all select 2 ;EXEC Tools.Trace ''Normal'' ,''2026-01-01'''
EXEC (@procname);
DECLARE @x int =23
SET @x=56

EXEC Tools.CaptureStatements @SessionEvent = @SessionEvent, @Action = 'Get', @result = @result OUTPUT ,@ProcedureName = 'TestqqProc';
PRINT 'Get: ' + @result;

--RETURN

EXEC Tools.CaptureStatements @SessionEvent = @SessionEvent, @Action = 'Stop', @result = @result OUTPUT;
PRINT 'Stop: ' + @result;
EXEC Tools.CaptureStatements @SessionEvent = @SessionEvent, @Action = 'Stop', @result = @result OUTPUT;
PRINT 'Doble Stop: ' + @result;
EXEC Tools.CaptureStatements @SessionEvent = @SessionEvent, @Action = 'Drop', @result = @result OUTPUT;
PRINT 'Drop: ' + @result;

SELECT * FROM Tools.CaptureStatementsLogs order by sessionseq desc,StartTime,  eventordinal 