SET timestamp= UNIX_TIMESTAMP('2026-05-02 00:00:00');
CREATE TABLE t1 (a INT) ENGINE=InnoDB WITH SYSTEM VERSIONING PARTITION BY SYSTEM_TIME INTERVAL 1 HOUR AUTO;
INSERT INTO t1 VALUES (1);
SET timestamp= UNIX_TIMESTAMP('2026-05-02 05:00:00');
LOCK TABLES t1 READ;
UPDATE t1 SET a = 2;
#CLI: - (the UPDATE never finishes); expected ERROR 1099 (HY000): Table 't1' was locked with a READ lock and can't be updated
#ERR: [Warning] mariadbd: Versioned table `test`.`t1`: last HISTORY partition (`p0`) is out of INTERVAL, need more HISTORY partitions
