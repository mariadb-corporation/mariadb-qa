# Needs the partition plugin.
CREATE TABLE t1 (a INT NOT NULL, b INT, KEY kb (b, a)) ENGINE=InnoDB PARTITION BY RANGE (a) (PARTITION p0 VALUES LESS THAN (10), PARTITION p1 VALUES LESS THAN MAXVALUE);
INSERT INTO t1 VALUES (1, 26), (17, 17);
SELECT MIN(b) FROM t1;
SELECT MIN(b) FROM t1 WHERE b >= 10;
SELECT MAX(b) FROM t1 WHERE b <= 30;
#CLI: 26; expected 17
#CLI: 26; expected 17
#CLI: 17; expected 26
#ERR: - (no error)

CREATE TABLE t1 (a INT NOT NULL, b INT, KEY (b, a)) ENGINE=Aria PARTITION BY RANGE (a) (PARTITION p0 VALUES LESS THAN (10), PARTITION p1 VALUES LESS THAN (20), PARTITION p2 VALUES LESS THAN (30));
INSERT INTO t1 VALUES (26, 1), (8, 2);
SELECT b, MIN(a), MAX(a) FROM t1 WHERE a < 23 GROUP BY b;
#CLI: optimized build: the SELECT gives an empty set; expected one row: 2, 8, 8
#ERR: debug build: Assertion `(have_last && !have_first) || (have_last && have_first && (last_res == 0))' failed in QUICK_GROUP_MIN_MAX_SELECT::get_next
