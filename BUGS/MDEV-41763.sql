SET NAMES utf8mb4;
CREATE TABLE t1 (c VARCHAR(10) COLLATE utf8mb4_bin, KEY (c));
INSERT INTO t1 VALUES ('a'), ('B'), ('A');
SELECT COUNT(*) FROM t1 WHERE c BETWEEN 'A' AND 'a';
#CLI: 1; expected 3 (as with IGNORE INDEX (c))
#ERR: - (no error)
