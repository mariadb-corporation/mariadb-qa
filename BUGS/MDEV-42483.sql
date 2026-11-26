CREATE TABLE t1 (id INT PRIMARY KEY, t VARCHAR(10), v VARCHAR(20) AS (CONCAT(t, 'x')) VIRTUAL, KEY (v)) ENGINE=InnoDB PARTITION BY HASH (id) PARTITIONS 2;
INSERT INTO t1 (id, t) VALUES (2, 'e'), (4, 'a'), (1, 'b');
SELECT t FROM t1 ORDER BY v LIMIT 1;
DELETE FROM t1 ORDER BY v LIMIT 1;
SELECT id FROM t1 ORDER BY id;
#CLI: the first SELECT gives b; expected a. The DELETE removes id 1 instead of id 4: the last SELECT gives 2 and 4; expected 1 and 2
#ERR: - (no error)

CREATE TABLE t2 (a INT NOT NULL, b INT NOT NULL, v INT AS (b) VIRTUAL, KEY kv (v)) ENGINE=InnoDB PARTITION BY HASH (a) PARTITIONS 2;
INSERT INTO t2 (a, b) VALUES (1, 2), (2, 1), (3, 1), (4, 2);
SELECT v, COUNT(a) FROM t2 GROUP BY v;
#CLI: 4 groups of 1 row (v = 1, 2, 1, 2); expected 2 groups of 2 rows
#ERR: - (no error)
