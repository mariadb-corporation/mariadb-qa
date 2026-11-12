SET NAMES utf8mb4;
CREATE TABLE t1 (c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci);
INSERT INTO t1 VALUES ('A'),('a');
SELECT COUNT(*) FROM t1 GROUP BY c HAVING c = 'A' COLLATE utf8mb4_bin;
#CLI: 1, with Warning 1292 Truncated incorrect BOOLEAN value: 'A'; expected 2
#ERR: - (no error)

SET NAMES utf8mb4;
CREATE TABLE t1 (c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci);
INSERT INTO t1 VALUES ('A'),('a');
SELECT cnt FROM (SELECT c, COUNT(*) AS cnt FROM t1 GROUP BY c) AS dt WHERE dt.c = 'A' COLLATE utf8mb4_bin;
#CLI: 1; expected 2
#ERR: - (no error)

SET NAMES utf8mb4;
CREATE TABLE t1 (c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci);
INSERT INTO t1 VALUES ('A'),('a');
SELECT cnt FROM (SELECT c, COUNT(*) OVER (PARTITION BY c) AS cnt FROM t1) AS dt WHERE dt.c = 'A' COLLATE utf8mb4_bin;
#CLI: 1; expected 2
#ERR: - (no error)
