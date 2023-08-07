# mysqld options required for replay:  --debug-assert-if-crashed-table=1
SET SESSION storage_engine=Aria;
CREATE TABLE t (a INT);
INSERT INTO t VALUES (0x1EA);
DELETE d1,d2 FROM t AS d1,t AS d2;
