# mysqld options required for replay:  --sql_mode=
SET NAMES latin1;
CREATE TABLE t (a INT KEY,c CHAR,INDEX sec_index (c));
INSERT INTO t VALUES (1,'İóëɠ');
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
INSERT INTO t VALUES (0,0);
INSERT INTO t VALUES ('24:00:00','24:00:');
DELETE FROM t LIMIT 3;
INSERT INTO t SET a=1;
SET GLOBAL innodb_limit_optimistic_insert_debug=0;
DELETE FROM t LIMIT 2;
INSERT INTO t VALUES (1,'a');
