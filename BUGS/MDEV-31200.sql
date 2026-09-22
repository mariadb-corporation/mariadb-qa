SET sql_mode='STRICT_TRANS_TABLES';
CREATE TABLE tbl1 (id VARCHAR(20));
INSERT INTO tbl1 VALUES ('abc');
UPDATE tbl1 SET id='x' WHERE id=0;
DELETE FROM tbl1 WHERE id=0;
#CLI: ERROR 1292 (22007): Truncated incorrect DECIMAL value: 'abc' on the UPDATE, Warning 1292 on the DELETE
#ERR: - (no error)

SET sql_mode='STRICT_TRANS_TABLES';
CREATE TABLE t1 (c1 INT, c2 VARCHAR(32));
INSERT INTO t1 VALUES (1,'a');
CREATE TABLE t2 (c1 INT);
INSERT INTO t2 VALUES (1);
UPDATE t1 AS a1 JOIN t2 AS a2 ON a1.c1=a2.c1 SET a1.c1=a1.c1 WHERE a1.c2=a1.c1;
DELETE FROM a1 USING t1 AS a1 JOIN t2 AS a2 ON a1.c1=a2.c1 WHERE a1.c2=a1.c1;
#CLI: ERROR 1292 (22007): Truncated incorrect DECIMAL value: 'a' on the UPDATE, Warning 1292 on the DELETE
#ERR: - (no error)
