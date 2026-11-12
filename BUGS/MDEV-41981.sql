CREATE TABLE t1 (c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci, KEY (c));
INSERT INTO t1 VALUES (_utf8mb4 0xC680),('a'),('b');
SELECT COUNT(*) FROM t1 WHERE UPPER(c) = _utf8mb4 0xC983 COLLATE utf8mb4_general_ci;
#CLI: 0; expected 1
#ERR: - (no error)

CREATE TABLE t1 (c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci, KEY (c));
INSERT INTO t1 VALUES (_utf8mb4 0xC680),('a'),('b');
SELECT COUNT(*) FROM t1 WHERE UPPER(c) = _utf8mb4 0xC680 COLLATE utf8mb4_general_ci;
#CLI: 1; expected 0
#ERR: - (no error)

CREATE TABLE t1 (c VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci, KEY (c));
INSERT INTO t1 VALUES (_utf8mb4 0xC680),('a'),('b');
SELECT COUNT(*) FROM t1 WHERE UPPER(c) IN (_utf8mb4 0xC983 COLLATE utf8mb4_general_ci, 'x');
#CLI: 0; expected 1
#ERR: - (no error)
