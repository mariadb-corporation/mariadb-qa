CREATE TABLE t (c INT,INDEX (c)) ENGINE=InnoDB PARTITION BY LIST (c) (PARTITION p VALUES IN (1,2));
EXPLAIN SELECT * FROM t WHERE (t.c) IN (SELECT c FROM t);

CREATE TABLE t (c INT,INDEX (c)) ENGINE=InnoDB PARTITION BY LIST (c) (PARTITION p VALUES IN (1,2));
SELECT * FROM t WHERE (t.c) IN (SELECT c FROM t);
