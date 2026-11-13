SET timestamp= UNIX_TIMESTAMP('2026-01-01 00:00:00');
CREATE TABLE t1 (a INT, b VARCHAR(20), UNIQUE KEY (b) USING HASH) ENGINE=InnoDB WITH SYSTEM VERSIONING PARTITION BY SYSTEM_TIME INTERVAL 1 DAY AUTO;
INSERT INTO t1 VALUES (1, 'x');
SET timestamp= UNIX_TIMESTAMP('2026-01-03 00:00:00');
UPDATE t1 SET a = 2;
FLUSH TABLES;
SELECT * FROM t1;
#CLI: ERROR 1194 (HY000): Table 't1' is marked as crashed and should be repaired
#CLI: ERROR 1877 (HY000): Table `test`.`t1#P#p0` is corrupted. Please drop the table and recreate.
#ERR: [Warning] InnoDB: Table test/t1#P#p0 contains 5 user defined columns in InnoDB, but 4 columns in MariaDB. Please check INFORMATION_SCHEMA.INNODB_SYS_COLUMNS and https://mariadb.com/docs/server/server-usage/storage-engines/innodb/innodb-troubleshooting/innodb-data-dictionary-troubleshooting for how to resolve the issue.
#ERR: [ERROR] mariadbd: Table 't1' is marked as crashed and should be repaired
#ERR: [ERROR] mariadbd: Table `test`.`t1#P#p0` is corrupted. Please drop the table and recreate.
#ERR: [ERROR] Failed to open table test/t1#P#p0.
#ERR: (the last two lines then repeat, about 50000 times a second on an optimized build)
