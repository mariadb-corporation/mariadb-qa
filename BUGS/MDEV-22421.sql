SET @@local.sql_mode='no_field_options';
CREATE OR REPLACE TABLE t (a INT AS (b + 1), b INT, ROW_START BIGINT UNSIGNED AS ROW START INVISIBLE, ROW_END BIGINT UNSIGNED AS ROW END INVISIBLE, PERIOD FOR SYSTEM_TIME(ROW_START, ROW_END)) WITH SYSTEM VERSIONING ENGINE=InnoDB;
CREATE OR REPLACE TABLE t1 LIKE t;
INSERT IGNORE INTO t1 VALUES (1,1);
UPDATE t1 SET a=5 WHERE a !=3;