CREATE TABLE t1 (id INT, c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin);
CREATE TABLE t2 (id INT, c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin);
INSERT INTO t1 VALUES (1,'a'),(2,'b ');
INSERT INTO t2 VALUES (1,'a '),(2,'b'),(3,'c');
SET join_cache_level=4;
SELECT COUNT(t2.id) FROM t1 LEFT JOIN t2 ON t2.c = t1.c;
#CLI: 0; expected 2
#ERR: - (no error)

CREATE TABLE t1 (id INT, c VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_bin);
CREATE TABLE t2 (id INT, c VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_bin);
INSERT INTO t1 VALUES (1,'a'),(2,'b ');
INSERT INTO t2 VALUES (1,'a '),(2,'b'),(3,'c');
SET join_cache_level=3;
SELECT COUNT(*) FROM t1 JOIN t2 ON t2.c = t1.c;
#CLI: 0; expected 2
#ERR: - (no error)
