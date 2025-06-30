# mysqld options required for replay: --log-bin 
SET SESSION binlog_format=STATEMENT;
CREATE TEMPORARY TABLE t (c INT);
INSERT INTO t VALUES (1),(1),(1);
DELETE FROM c,a USING t AS a JOIN t AS b JOIN t AS c;
