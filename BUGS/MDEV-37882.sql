# mysqld options required for replay: --log-bin
SET binlog_format=STATEMENT;
SET GLOBAL read_only=ON;
CREATE TEMPORARY TABLE tt (x INT);
SET GLOBAL read_only=OFF;
INSERT INTO tt VALUES (1);
CREATE TEMPORARY TABLE t (x INT);
INSERT t SELECT * FROM tt;
INSERT t VALUES (1);
UPDATE t, tt SET t.x=2;
