CREATE DATABASE test2;
SET sql_mode=0,binlog_row_image=1;
CREATE TABLE t (a INT,b INT,PRIMARY KEY(a)) ENGINE=InnoDB;
ALTER TABLE t ADD COLUMN x1 BLOB GENERATED ALWAYS AS (CONCAT (a,b)) VIRTUAL,ADD COLUMN x2 BLOB GENERATED ALWAYS AS (CONCAT (a,b)) VIRTUAL,ADD INDEX (x1 (1),x2 (1));  
USE test2;
CREATE TEMPORARY TABLE t (a INT) ENGINE=InnoDB;
USE test;
INSERT INTO t VALUES (2,2,2,2);
SELECT * FROM performance_schema.file_summary_by_instance LIMIT 1;
UPDATE t SET b=0;
# [ERROR] InnoDB: Record in index `x1` of table `test`.`t` was not found on update: TUPLE (info_bits=0, 3 fields): {NULL,NULL,[4]    (0x80000002)} at: COMPACT RECORD(info_bits=0, 1 fields): {[8]infimum (0x696E66696D756D00)}
2024-06-10 08:24:27 0x14b9208cf6c0  InnoDB: Assertion failure in file /test/10.5_opt/storage/innobase/row/row0ins.cc line 219
