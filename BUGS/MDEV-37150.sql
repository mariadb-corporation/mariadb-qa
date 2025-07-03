# mysqld options required for replay:  --log-bin
set sql_mode='';
CREATE TABLE t (c POINT NOT NULL,SPATIAL (c));
INSERT INTO t VALUES (GEOMFROMTEXT ('POINT(1 312435220)'));
INSERT INTO t VALUES (ST_GEOMFROMTEXT ('POINT(1 526818004)'));
INSERT INTO t SELECT * FROM t;
SET GLOBAL innodb_limit_optimistic_insert_debug=4;
INSERT INTO t SELECT * FROM t;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
SET GLOBAL profiling=1;
INSERT INTO t SELECT * FROM t;
