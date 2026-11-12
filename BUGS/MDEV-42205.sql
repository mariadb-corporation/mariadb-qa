CREATE TABLE t1 (a INT) ENGINE=InnoDB PARTITION BY HASH (a) PARTITIONS 2;
INSERT INTO t1 VALUES (1), (2);
LOCK TABLES t1 WRITE, t1 AS a1 READ;
ALTER TABLE t1 TRUNCATE PARTITION p0;
UNLOCK TABLES;
CREATE TABLE t2 (a INT) ENGINE=InnoDB;
INSERT INTO t2 SELECT seq FROM seq_1_to_100;
DELETE FROM t2;
SELECT SLEEP(10);
SHOW GLOBAL STATUS LIKE 'Innodb_history_list_length';
#CLI: ERROR 1205 (HY000): Lock wait timeout exceeded; try restarting transaction
#CLI: Innodb_history_list_length 11 after the 10 seconds; expected 0
#ERR: - (no error)
