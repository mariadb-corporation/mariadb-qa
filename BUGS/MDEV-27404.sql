# Sporadic issue, SIGSEGV requires about 5 to 20 executions, hang potentially more (less than 1000). SIGSEGV happens on optimized and debug builds. The hangs may be limited to debug builds only, though it is difficult to say as optimized builds hit the SIGSEGV first/earlier.
DROP DATABASE test;
CREATE DATABASE test;
USE test;
INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t1 (f VARBINARY(1)) ENGINE=SPIDER;
CREATE TABLE t2 (c INT KEY,c2 INT) ENGINE=SPIDER;
INSERT INTO t2 VALUES (0);
ALTER TABLE t1 CHANGE COLUMN a a INT;
ALTER TABLE t2 CHANGE COLUMN a a INT;
INSERT INTO t1 VALUES (0);
SELECT (SELECT * FROM t2) AS c FROM t2;
ALTER TABLE t2 CHANGE COLUMN a a INT;
CREATE TABLE t3 (a CHAR(1),FULLTEXT (a)) ENGINE=InnoDB;
INSERT INTO t2 VALUES (0);
DROP TABLE t3;
