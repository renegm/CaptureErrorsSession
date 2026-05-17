CREATE OR ALTER PROCEDURE Tools.CaptureStatements
    @SessionEvent sysname, @Action varchar(10), @result nvarchar(MAX) = NULL OUTPUT, @ProcedureName varchar (300) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @SessionEvent IS NULL
        OR @SessionEvent LIKE '%[^a-z0-9_]%'
        OR @SessionEvent LIKE '[^a-z]%'
    BEGIN
        SET @result = '{"status":"No funny names allowed"}';
        RETURN;
    END;
    IF @Action IS NULL
        OR @Action NOT IN ( 'CREATE', 'START', 'STOP', 'DROP', 'GET' )
    BEGIN
        SET @result = '{"status":"Invalid action"}';
        RETURN;
    END;



    DECLARE @SQL      nvarchar(MAX)
          , @Database bit          = IIF(SERVERPROPERTY('EngineEdition') IN ( 5, 12 ), 1, 0)
          , @Exist    bit          = 0
          , @Started  bit          = 0
          , @Xml      xml;

    SET @SQL
        = N'SET @Exist =IIF(EXISTS (SELECT NULL FROM sys.database_event_sessions WHERE name = @SessionEvent), 1, 0);';
    IF @Database = 0
        SET @SQL = REPLACE(@SQL, 'sys.database_event_sessions', 'sys.server_event_sessions');
    EXEC sys.sp_executesql @stmt = @SQL
                         , @params = N'@SessionEvent sysname, @Exist bit OUTPUT'
                         , @SessionEvent = @SessionEvent
                         , @Exist = @Exist OUTPUT;

    IF @Exist = 0
        AND @Action <> 'CREATE'
    BEGIN
        SET @result = '{"status":"SessionEvent doesn''t exist"}';
        RETURN;
    END;

    IF @Action = 'CREATE'
    BEGIN
        DECLARE @AppName nvarchar(300) = APP_NAME();

        IF @AppName IS NULL
            OR @AppName = ''
            OR CHARINDEX(CHAR(0), @AppName) > 0
        BEGIN
            SET @result = '{"status":"Invalid App Name"}';
            RETURN;
        END;

        SET @AppName = REPLACE(@AppName, '''', '''''');

        IF @Exist = 1
            SET @SQL = N'DROP EVENT SESSION @SessionEvent ON #DATABASE/SERVER#;' + CHAR(10);
        ELSE
            SET @SQL = N'';

        SET @SQL
            = @SQL
              + N'
CREATE EVENT SESSION @SessionEvent ON #DATABASE/SERVER#
    ADD EVENT sqlserver.sp_statement_completed  (
     WHERE sqlserver.session_id = @@SPID
         AND sqlserver.client_app_name = ''@AppName''
         AND sqlserver.is_system = 0
     )
     ,ADD EVENT sqlserver.sql_statement_completed  (
     WHERE sqlserver.session_id = @@SPID
         AND sqlserver.client_app_name = ''@AppName''
         AND sqlserver.is_system = 0
     )
ADD TARGET package0.ring_buffer
    (SET max_memory = 51200)
WITH (MAX_MEMORY = 16384KB
    , STARTUP_STATE = OFF
    , MAX_DISPATCH_LATENCY = 1 SECONDS
    , TRACK_CAUSALITY      = OFF
    );' ;


        SET @SQL = REPLACE(@SQL, '#DATABASE/SERVER#', IIF(@Database = 1, 'DATABASE', 'SERVER'));
        SET @SQL = REPLACE(@SQL, '@@SPID', CONVERT(nvarchar(10), @@SPID));
        SET @SQL = REPLACE(@SQL, '@SessionEvent', QUOTENAME(@SessionEvent));
        SET @SQL = REPLACE(@SQL, '@AppName', @AppName);

        EXEC sys.sp_executesql @stmt = @SQL;
        SET @result = '{"status":"CREATE Done"}';
        RETURN;
    END;

    IF @Action = 'DROP'
    BEGIN
        SET @SQL = N'DROP EVENT SESSION @SessionEvent ON #DATABASE/SERVER#;';

        SET @SQL = REPLACE(@SQL, '#DATABASE/SERVER#', IIF(@Database = 1, 'DATABASE', 'SERVER'));
        SET @SQL = REPLACE(@SQL, '@SessionEvent', QUOTENAME(@SessionEvent));

        EXEC sys.sp_executesql @stmt = @SQL;
        SET @result = '{"status":"DROP Done"}';
        RETURN;
    END;

    SET @SQL
        = N'SET @Started = IIF(EXISTS (SELECT NULL FROM sys.dm_xe_database_sessions WHERE name = @SessionEvent), 1, 0);';

    IF @Database = 0
        SET @SQL = REPLACE(@SQL, 'sys.dm_xe_database_sessions', 'sys.dm_xe_sessions');

    EXEC sys.sp_executesql @stmt = @SQL
                         , @params = N'@SessionEvent sysname, @Started bit OUTPUT'
                         , @SessionEvent = @SessionEvent
                         , @Started = @Started OUTPUT;

    IF @Action = 'START'
        AND @Started = 1
        OR @Action = 'STOP'
        AND @Started = 0
    BEGIN
        SET @result = '{"status":"SessionEvent already ' + IIF(@Action = 'START', 'started', 'stopped') + '"}';
        RETURN;
    END;


    IF @Action IN ( 'START', 'STOP' )
    BEGIN

        SET @SQL = N'ALTER EVENT SESSION @SessionEvent ON #DATABASE/SERVER# STATE = @Action';

        SET @SQL = REPLACE(@SQL, '#DATABASE/SERVER#', IIF(@Database = 1, 'DATABASE', 'SERVER'));
        SET @SQL = REPLACE(@SQL, '@SessionEvent', QUOTENAME(@SessionEvent));
        SET @SQL = REPLACE(@SQL, '@Action', @Action);

        EXEC sys.sp_executesql @stmt = @SQL;

        SET @result = '{"status":"' + UPPER(@Action) + ' Done"}';
        RETURN;
    END;

    /*Get*/

    IF @Started = 0
    BEGIN
        SET @result = '{"status":"SessionEvent is not started"}';
        RETURN;
    END;



    SET @SQL
        = N'SELECT    @Xml = CAST(T.target_data AS xml)
        FROM      sys.dm_xe_database_session_targets AS T
       INNER JOIN sys.dm_xe_database_sessions AS S
          ON T.event_session_address = S.address
        WHERE     S.name = @SessionEvent
            AND T.target_name = ''ring_buffer'';';

    IF @Database = 0
    BEGIN
        SET @SQL = REPLACE(@SQL, 'sys.dm_xe_database_sessions', 'sys.dm_xe_sessions');
        SET @SQL = REPLACE(@SQL, 'sys.dm_xe_database_session_targets', 'sys.dm_xe_session_targets');
    END;
    EXEC sys.sp_executesql @stmt = @SQL
                         , @params = N'@SessionEvent sysname, @Xml xml OUTPUT'
                         , @SessionEvent = @SessionEvent
                         , @Xml = @Xml OUTPUT;

    DROP TABLE IF EXISTS #RawXml;
    CREATE TABLE #RawXml
        (EventOrdinal int IDENTITY(1, 1)
       , N            xml
       , object_id    int);

    INSERT INTO #RawXml(N
                      , object_id)
    SELECT T.N.query('.'), object_id = T.N.value(N'(data[@name="object_id"]/value)[1]', N'int')
    FROM   @Xml.nodes(N'//RingBufferTarget/event') AS T(N);

    DECLARE @Row int = (   SELECT MIN(EventOrdinal)
                           FROM   #RawXml
                           WHERE  object_id IS DISTINCT FROM @@PROCID);
    DELETE FROM #RawXml WHERE EventOrdinal < @Row;
    SET @Row = (SELECT MIN(EventOrdinal)FROM #RawXml WHERE object_id = @@PROCID);
    DELETE FROM #RawXml WHERE EventOrdinal >= @Row;


    
    DECLARE @SessionSeq int = NEXT VALUE FOR Tools.CaptureStatementsSessionSeq;

    INSERT INTO Tools.CaptureStatementsLogs(SessionSeq
                                          , ProcedureName
                                          , EventOrdinal
                                          , source_database_id
                                          , object_id
                                          , object_type
                                          , object_type_text
                                          , duration
                                          , cpu_time
                                          , page_server_reads
                                          , physical_reads
                                          , logical_reads
                                          , writes
                                          , spills
                                          , row_count
                                          , last_row_count
                                          , nest_level
                                          , line_number
                                          , offset
                                          , offset_end
                                          , object_name
                                          , statement
                                          , EndTime
                                          , StartTime)
    SELECT    @SessionSeq
            , ProcedureName = @ProcedureName
            , EventOrdinal = ROW_NUMBER() OVER (ORDER BY(T.EventOrdinal))
            , source_database_id = T.N.value(N'(event/data[@name="source_database_id"]/value)[1]', N'int')
            , object_id = T.N.value(N'(event/data[@name="object_id"]/value)[1]', N'int')
            , object_type = T.N.value(N'(event/data[@name="object_type"]/value)[1]', N'int')
            , object_type_text = T.N.value(N'(event/data[@name="object_type"]/text)[1]', N'nvarchar(261)')
            , duration = T.N.value(N'(event/data[@name="duration"]/value)[1]', N'bigint')
            , cpu_time = T.N.value(N'(event/data[@name="cpu_time"]/value)[1]', N'bigint')
            , page_server_reads = T.N.value(N'(event/data[@name="page_server_reads"]/value)[1]', N'bigint')
            , physical_reads = T.N.value(N'(event/data[@name="physical_reads"]/value)[1]', N'bigint')
            , logical_reads = T.N.value(N'(event/data[@name="logical_reads"]/value)[1]', N'bigint')
            , writes = T.N.value(N'(event/data[@name="writes"]/value)[1]', N'bigint')
            , spills = T.N.value(N'(event/data[@name="spills"]/value)[1]', N'bigint')
            , row_count = T.N.value(N'(event/data[@name="row_count"]/value)[1]', N'bigint')
            , last_row_count = T.N.value(N'(event/data[@name="last_row_count"]/value)[1]', N'bigint')
            , nest_level = T.N.value(N'(event/data[@name="nest_level"]/value)[1]', N'int')
            , line_number = T.N.value(N'(event/data[@name="line_number"]/value)[1]', N'int')
            , offset = T.N.value(N'(event/data[@name="offset"]/value)[1]', N'int')
            , offset_end = T.N.value(N'(event/data[@name="offset_end"]/value)[1]', N'int')
            , object_name = T.N.value(N'(event/data[@name="object_name"]/value)[1]', N'nvarchar(261)')
            , statement = T.N.value(N'(event/data[@name="statement"]/value)[1]', N'nvarchar(MAX)')
            , EndTime
            , StartTime = DATEADD(MICROSECOND, -T.N.value(N'(event/data[@name="duration"]/value)[1]', N'BIGINT'), EndTime)
    FROM      #RawXml AS T
   CROSS APPLY(VALUES(T.N.value(N'(event/@timestamp)[1]', N'DATETIME2(7)'))) AS V(EndTime);
    SET @result = COALESCE(@result, '[]');
END;
GO

