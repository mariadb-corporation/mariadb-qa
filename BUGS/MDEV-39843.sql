SET NAMES utf8mb4;
CREATE TABLE t1 (c VARCHAR(10) COLLATE utf8mb4_uca1400_as_cs, KEY (c(1)));
INSERT INTO t1 VALUES ('A'), ('b'), ('x'), ('y'), ('z');
SELECT COUNT(*) FROM t1 WHERE c < 'ab';
#CLI: 0; expected 1 (as with IGNORE INDEX (c))
#ERR: - (no error)
