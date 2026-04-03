# mysqld options required for replay: --log_bin=binlog
SET binlog_format='STATEMENT';
CREATE GLOBAL TEMPORARY TABLE gtt (x INT) ON COMMIT PRESERVE ROWS;
INSERT INTO gtt VALUES (1);
CREATE TABLE t (x INT, y INT);
CREATE TABLE tc LIKE t;
BEGIN;
CREATE TEMPORARY TABLE t LIKE tc;
INSERT t VALUES (1, 2);
UPDATE t, gtt SET t.y=1;

# mysqld options required for replay: --log-bin
SET SESSION binlog_format=STATEMENT;
CREATE TEMPORARY TABLE t (y INT);
ALTER TABLE t DISCARD TABLESPACE;

# mysqld options required for replay: --log-bin --sql_mode=
SET binlog_format=STATEMENT;
CREATE GLOBAL TEMPORARY TABLE gtt (x INT) ON COMMIT PRESERVE ROWS;
SET SESSION enforce_storage_engine=MEMORY;
CREATE TABLE t (c INT KEY);
INSERT t VALUES (1);
REPLACE t VALUES (1);
INSERT INTO gtt VALUES (1);
CREATE TEMPORARY TABLE t (y INT);
INSERT INTO t VALUES (2);
UPDATE t,gtt SET t.y=1;

# mysqld options required for replay: --log-bin --sql_mode=
SET binlog_format=1;
CREATE GLOBAL TEMPORARY TABLE gtt (x INT) ON COMMIT PRESERVE ROWS;
SET SESSION enforce_storage_engine=MEMORY;
CREATE TABLE t (c INT KEY);
INSERT t VALUES (1);
REPLACE DELAYED t VALUES (1);
INSERT INTO gtt VALUES (1);
CREATE TEMPORARY TABLE t (y INT);
INSERT INTO t VALUES (2);
UPDATE t,gtt SET t.y=1;
