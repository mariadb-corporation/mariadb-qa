CREATE SEQUENCE s1;
CREATE TABLE t1 (a INT) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1);
CREATE OR REPLACE TABLE t1 (a INT) ENGINE=InnoDB FOO=1 SELECT NEXTVAL(s1) AS a;
SELECT * FROM t1;
#CLI: SELECT gives ERROR 1146 (42S02): Table 'test.t1' doesn't exist; expected 1
#ERR: [ERROR] DDL_LOG: Got error 4091 when trying to execute action for entry 3 of type 'create table'
