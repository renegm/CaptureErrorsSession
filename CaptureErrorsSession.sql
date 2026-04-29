CREATE OR ALTER PROCEDURE Tools.CaptureErrorsSession
    @SessionEvent sysname, @Action varchar(10), @result nvarchar(MAX) = NULL OUTPUT
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
          , @Database bit          = IIF(SERVERPROPERTY('EngineEdition') IN ( 5, 11, 12 ), 1, 0)
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
    ADD EVENT sqlserver.error_reported (
     WHERE severity >= 11
         AND sqlserver.session_id = @@SPID
         AND sqlserver.client_app_name = ''@AppName''
     )
    ADD TARGET package0.ring_buffer
    (SET max_memory = 4096)
WITH (MAX_MEMORY = 16384KB
    , STARTUP_STATE = OFF);';

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

    SET @result = (   SELECT error_number = X.event_data.value('(data[@name="error_number"]/value)[1]', 'int')
                           , severity = X.event_data.value('(data[@name="severity"]/value)[1]', 'int')
                           , message_text = X.event_data.value('(data[@name="message"]/value)[1]', 'nvarchar(MAX)')
                      FROM   @Xml.nodes('RingBufferTarget/event') AS X(event_data)
                      FOR JSON AUTO);
    SET @result = COALESCE(@result, '[]');
END;
GO
