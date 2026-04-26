--CREATE TABLE TestError (x int default (0))

DECLARE @result nvarchar(MAX), @SessionEvent sysname = 'SessionEventqqq';

EXEC Tools.CaptureErrorsSession @SessionEvent = @SessionEvent, @Action = 'Create', @result = @result OUTPUT;
PRINT 'Create' + @result;
EXEC Tools.CaptureErrorsSession @SessionEvent = @SessionEvent, @Action = 'Start', @result = @result OUTPUT;
PRINT 'Start' + @result;
BEGIN TRY
  
    ALTER TABLE dbo.TestError ALTER COLUMN x bigint;
    PRINT ''
END TRY
BEGIN CATCH
    PRINT '';
END CATCH;

EXEC Tools.CaptureErrorsSession @SessionEvent = @SessionEvent, @Action = 'Get', @result = @result OUTPUT;
PRINT 'Get' + @result;
EXEC Tools.CaptureErrorsSession @SessionEvent = @SessionEvent, @Action = 'Stop', @result = @result OUTPUT;
PRINT 'Stop' + @result;
EXEC Tools.CaptureErrorsSession @SessionEvent = @SessionEvent, @Action = 'Stop', @result = @result OUTPUT;
PRINT 'Stop' + @result;
EXEC Tools.CaptureErrorsSession @SessionEvent = @SessionEvent, @Action = 'Drop', @result = @result OUTPUT;
PRINT 'Drop' + @result;
