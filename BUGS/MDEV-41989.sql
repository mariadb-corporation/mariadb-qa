CREATE TABLE t1 (id INT PRIMARY KEY, a INT) ENGINE=MyISAM PARTITION BY HASH (id) PARTITIONS 4;
INSERT INTO t1 VALUES (1, 1), (2, 2);
UPDATE t1 SET id = 2 WHERE id = 1;
#CLI: ERROR 1022 (23000): Can't write; duplicate key in table 't1'; expected ERROR 1062
#ERR: - (no error)

CREATE TABLE t2 (id INT PRIMARY KEY, a INT) ENGINE=Aria PARTITION BY HASH (id) PARTITIONS 4;
INSERT INTO t2 VALUES (1, 1), (2, 2);
UPDATE t2 SET id = 2 WHERE id = 1;
#CLI: ERROR 1022 (23000): Can't write; duplicate key in table 't2'; expected ERROR 1062
#ERR: - (no error)

CREATE TABLE t3 (a INT, b INT, c INT, PRIMARY KEY (a, b), UNIQUE KEY uc (a, c)) ENGINE=MyISAM PARTITION BY HASH (a) PARTITIONS 4;
INSERT INTO t3 VALUES (1, 1, 1), (2, 2, 1);
INSERT INTO t3 VALUES (1, 1, 9) ON DUPLICATE KEY UPDATE a = 2;
#CLI: ERROR 1062 (23000): Duplicate entry '2-1' for key 'PRIMARY'; expected key 'uc'
#ERR: - (no error)
