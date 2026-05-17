USE Tools;
CREATE SEQUENCE Tools.CaptureStatementsSessionSeq
AS int
START WITH 1
INCREMENT BY 1
MINVALUE 1
CACHE 20;

GO


DROP TABLE IF EXISTS Tools.CaptureStatementsLogs;

CREATE TABLE Tools.CaptureStatementsLogs
    (SessionSeq         int          NOT NULL
   , ProcedureName      nvarchar(300)
   , EventOrdinal       int          NOT NULL
   , source_database_id int
   , object_id          int
   , object_type        int
   , object_type_text   nvarchar(261)
   , duration           bigint
   , cpu_time           bigint
   , page_server_reads  bigint
   , physical_reads     bigint
   , logical_reads      bigint
   , writes             bigint
   , spills             bigint
   , row_count          bigint
   , last_row_count     bigint
   , nest_level         int
   , line_number        int
   , offset             int
   , offset_end         int
   , object_name        nvarchar(261)
   , statement          nvarchar(MAX)
   , EndTime            datetime2(7)
   , StartTime          datetime2(7)
   , PRIMARY KEY(SessionSeq, EventOrdinal)WITH(DATA_COMPRESSION = PAGE));