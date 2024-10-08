CREATE TABLE t (a INT);
CREATE VIEW v AS SELECT 1 FROM t;
SET big_tables= 1; # Not needed for 10.5+
CREATE PROCEDURE p() SELECT 2 FROM v;
CREATE TEMPORARY TABLE v SELECT 3 AS b;
CALL p();
SET PSEUDO_THREAD_ID= 111;
CALL p();

CREATE TABLE t (a INT);
CREATE VIEW v AS SELECT 1 FROM t;
CREATE PROCEDURE p() SELECT 2 FROM v;
CREATE TEMPORARY TABLE v SELECT 3 AS b;
CALL p();
ALTER TABLE v RENAME TO vv;
CALL p();

CREATE VIEW v2 (c) as SELECT column_name FROM information_schema.COLUMNs;
CREATE TABLE t (a ENUM ('') CHARACTER SET utf32 COLLATE utf32_spanish2_ci) ENGINE=InnoDB PARTITION BY KEY(a) PARTITIONS 2;
RENAME TABLE t TO c,v2 TO t;
CREATE FUNCTION f() RETURNS INT RETURN (SELECT COUNT(*) FROM t);
CREATE TEMPORARY TABLE t (a INT);
INSERT INTO t VALUES (f());
DROP TEMPORARY TABLE t CASCADE;
SELECT f() FROM (SELECT 1) c;

CREATE VIEW v2 (c) as SELECT column_name FROM information_schema.COLUMNs;
CREATE TABLE t (a ENUM ('') CHARACTER SET utf32 COLLATE utf32_spanish2_ci) ENGINE=InnoDB PARTITION BY KEY(a) PARTITIONS 2;
RENAME TABLE t TO c,v2 TO t;
SET @@big_tables=1;
CREATE FUNCTION f() RETURNS INT RETURN (SELECT COUNT(*) FROM t);
CREATE TEMPORARY TABLE t (a INT);
INSERT INTO t VALUES (f());
DROP TEMPORARY TABLE t CASCADE;
SELECT f() FROM (SELECT 1) c;

SET GLOBAL log_bin_trust_function_creators=1;
CREATE VIEW v2 (c) as SELECT column_name FROM information_schema.COLUMNs;
CREATE TABLE t (a ENUM ('') CHARACTER SET utf32 COLLATE utf32_spanish2_ci) PARTITION BY KEY(a) PARTITIONS 2;
RENAME TABLE t TO c,v2 TO t;
CREATE FUNCTION f() RETURNS INT RETURN (SELECT COUNT(*) FROM t);
CREATE TEMPORARY TABLE t (a INT);
INSERT INTO t VALUES (f());
DROP TEMPORARY TABLE t CASCADE;
SELECT f() FROM (SELECT 1) c;
