CREATE TABLE t1(a TIMESTAMP,KEY(a)) ENGINE=INNODB;
SELECT * FROM t1 WHERE DATE(a) <= '2024-01-23';