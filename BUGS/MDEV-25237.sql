SET sql_mode='';
SET 'a';
SET collation_connection=utf6_unicode_520_ci;
SET GLOBAL session_track_system_variables='a';
SET GLOBAL event_scheduler=1;

SET sql_mode='ONLY_FULL_GROUP_BY';
SET 'a';
SET collation_connection=utf6_unicode_520_ci;
SET GLOBAL session_track_system_variables='a';
SET GLOBAL event_scheduler=1;

SET 'a';
SET collation_connection='a';
CHANGE MASTER TO master_host='a';
SET GLOBAL session_track_system_variables='a';

SET GLOBAL session_track_system_variables='a';
SET GLOBAL event_scheduler=TRUE;

SET sql_mode='';
CREATE TABLE t (a INT,b INT,c INT,d INT,e INT,f INT GENERATED ALWAYS AS (a+b) VIRTUAL,g INT,h BLOB,i INT,UNIQUE KEY(d,h)) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0,0,0,0,0,0,0,0);
SET GLOBAL session_track_system_variables='a';
INSERT INTO t SET c=CONCAT (REPEAT (0,0),0,0);
