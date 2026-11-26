SET timestamp= UNIX_TIMESTAMP('2026-05-02 00:00:00');
CREATE TABLE t1 (a INT) ENGINE=InnoDB WITH SYSTEM VERSIONING PARTITION BY SYSTEM_TIME INTERVAL 1 HOUR AUTO;
INSERT INTO t1 VALUES (1);
SET timestamp= UNIX_TIMESTAMP('2026-05-02 05:00:00');
LOCK TABLES t1 READ;
UPDATE t1 SET a = 2;
#CLI: - (the UPDATE never finishes); expected ERROR 1099 (HY000): Table 't1' was locked with a READ lock and can't be updated
#ERR: [Warning] mariadbd: Versioned table `test`.`t1`: last HISTORY partition (`p0`) is out of INTERVAL, need more HISTORY partitions

SET timestamp= UNIX_TIMESTAMP('2026-05-02 00:00:00');
CREATE TABLE t1 (a INT) ENGINE=InnoDB WITH SYSTEM VERSIONING PARTITION BY SYSTEM_TIME INTERVAL 1 HOUR AUTO;
INSERT INTO t1 VALUES (1);
LOCK TABLES t1 WRITE;
SET timestamp= UNIX_TIMESTAMP('2026-05-02 05:00:00');
ALTER TABLE t1 DROP PARTITION p_none;
UPDATE t1 SET a = 2;
#CLI: ERROR 4128 (HY000): Wrong partitions for `t1`: must have at least one HISTORY and exactly one last CURRENT
#CLI: - (the UPDATE never finishes); expected the UPDATE to finish
#ERR: - (no error)

SET timestamp= UNIX_TIMESTAMP('2000-01-01 10:00:00');
CREATE TABLE t1 (a INT) WITH SYSTEM VERSIONING PARTITION BY SYSTEM_TIME INTERVAL 1 HOUR STARTS '2000-01-01 00:00:00' AUTO;
CREATE TABLE t2 (a INT);
LOCK TABLES t1 WRITE, t2 WRITE;
SET timestamp= UNIX_TIMESTAMP('2000-01-01 15:00:00');
ALTER TABLE t1 ADD PARTITION (PARTITION px HISTORY);
SELECT COUNT(*) FROM t1;
#CLI: the ALTER TABLE gives Query OK, then the SELECT gives ERROR 1100 (HY000): Table 't1' was not locked with LOCK TABLES; expected 0, t1 still locked
#ERR: Protocol::end_statement(): Assertion `0' failed (debug builds)
