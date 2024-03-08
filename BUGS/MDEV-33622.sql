# mysqld options required for replay: --thread-stack=1024
CREATE TABLE t (a INT KEY);
INSERT INTO t VALUES (1),(2);
SELECT * FROM t;
UPDATE t SET a=2;
