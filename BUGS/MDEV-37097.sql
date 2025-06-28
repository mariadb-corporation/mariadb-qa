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

SET sql_mode='';
SET NAMES latin1;
CREATE TABLE t (c CHAR KEY,INDEX(c)) ENGINE=InnoDB;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
INSERT INTO t VALUES ('İóëɠ'),(0),('20000');
DELETE FROM t LIMIT 3;
INSERT INTO t VALUES (1);
SET GLOBAL innodb_limit_optimistic_insert_debug=0;
DELETE FROM t LIMIT 1;
INSERT INTO t VALUES ('a');

SET sql_mode='';
SET NAMES latin1;
CREATE TABLE t (c CHAR KEY,INDEX(c)) ENGINE=InnoDB;
SET GLOBAL innodb_limit_optimistic_insert_debug=1;
INSERT INTO t VALUES ('İóëɠ'),(0),('20000');
DELETE FROM t LIMIT 2;
INSERT INTO t VALUES (1);
SET GLOBAL innodb_limit_optimistic_insert_debug=0;
DELETE FROM t LIMIT 1;
INSERT INTO t VALUES ('a');
