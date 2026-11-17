CREATE TABLE t(x VARCHAR(2));
INSERT INTO t VALUES ('1'), ('13');
SELECT 'heap' AS step, MAX(x) AS max_x FROM t WHERE x < 2;
ALTER TABLE t ADD KEY (x);
SELECT 'idx' AS step, MAX(x) AS max_x FROM t WHERE x < 2;
#CLI: heap 1, then idx 13; expected heap 1, then idx 1
#ERR: - (no error)

CREATE TABLE t1 (x VARCHAR(10), n INT, KEY (x, n));
INSERT INTO t1 VALUES ('2',5),('2.0',9),('3',1);
SELECT MAX(n) FROM t1 WHERE x = 2;
#CLI: 5; expected 9
#ERR: - (no error)

SET NAMES utf8mb4;
CREATE TABLE t1 (c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci, KEY (c));
INSERT INTO t1 VALUES ('a'),('B');
SELECT MAX(c) FROM t1 WHERE c < 'b' COLLATE utf8mb4_bin;
#CLI: a; expected B
#ERR: - (no error)

SET NAMES utf8mb4;
CREATE TABLE t1 (c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci, KEY (c));
INSERT INTO t1 VALUES ('a'),('B');
SELECT MIN(c) FROM t1 WHERE c = 'b' COLLATE utf8mb4_bin;
#CLI: B; expected NULL
#ERR: - (no error)

CREATE TABLE t1 (x ENUM('b','a'), KEY (x));
INSERT INTO t1 VALUES ('b'),('a');
SELECT MAX(x) FROM t1 WHERE x < 'b';
#CLI: NULL; expected a
#ERR: - (no error)

CREATE TABLE t1 (i INT, KEY (i));
INSERT INTO t1 VALUES (20010101),(20020101),(99999999);
SELECT MAX(i) FROM t1 WHERE i > DATE'2001-06-01';
#CLI: NULL; expected 20020101
#ERR: - (no error)
