CREATE TABLE t1 (a INT, b INT, KEY(a));
INSERT INTO t1 SELECT seq, seq FROM seq_1_to_100;
SET optimizer_join_limit_pref_ratio=1;
SELECT * FROM seq_1_to_200, t1 WHERE a > 0 ORDER BY a LIMIT 1;
