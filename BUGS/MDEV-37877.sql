# mysqld options required for replay:  --log_bin=binlog
SET binlog_format='STATEMENT';
CREATE GLOBAL TEMPORARY TABLE gtt (x INT) ON COMMIT PRESERVE ROWS;
INSERT INTO gtt VALUES (1);
CREATE TABLE t (x INT, y INT);
CREATE TABLE tc LIKE t;
BEGIN;
CREATE TEMPORARY TABLE t LIKE tc;
INSERT t VALUES (1, 2);
UPDATE t, gtt SET t.y=1;
