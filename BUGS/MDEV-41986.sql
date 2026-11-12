SET NAMES utf8mb4;
CREATE TABLE t1 (c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin);
INSERT INTO t1 VALUES ('a'),('A'),('b');
SELECT COUNT(*) FROM t1 WHERE c IN ('a', 'A' COLLATE utf8mb4_general_ci);
#CLI: 1; expected 2
#ERR: - (no error)

SET NAMES utf8mb4;
CREATE TABLE t1 (c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin);
INSERT INTO t1 VALUES ('a'),('A'),('b');
SELECT COUNT(*) FROM t1 WHERE c NOT IN ('a', 'A' COLLATE utf8mb4_general_ci);
#CLI: 2; expected 1
#ERR: - (no error)

SET NAMES utf8mb4;
CREATE TABLE t1 (c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci);
INSERT INTO t1 VALUES ('a'),('A'),('b');
SELECT COUNT(*) FROM t1 WHERE c IN ('a', 'a' COLLATE utf8mb4_bin);
#CLI: 2; expected 1
#ERR: - (no error)
