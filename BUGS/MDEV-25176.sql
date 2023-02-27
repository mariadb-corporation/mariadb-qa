DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET GLOBAL binlog_checksum=NONE;
SHUTDOWN;
SET GLOBAL event_scheduler=1;
SELECT SLEEP (3);

SHUTDOWN;
SET GLOBAL event_scheduler=1;
SELECT SLEEP (3);

SET GLOBAL event_scheduler=TRUE;
SHUTDOWN;
SET GLOBAL event_scheduler=TRUE;
SET GLOBAL event_scheduler=TRUE;
SET GLOBAL event_scheduler=TRUE;
