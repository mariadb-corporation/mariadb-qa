SET SESSION log_warnings=50, GLOBAL innodb_stats_persistent=ON;
CREATE TABLE t (c INT);
BEGIN;
INSERT INTO t VALUES (0),(0);
SELECT * FROM t;
SELECT * FROM mysql.innodb_table_stats WHERE table_name='a' FOR UPDATE;
# CLI: ERROR 1020 (HY000): Record has changed since last read in table 'innodb_table_stats'
# ERR: [ERROR] InnoDB: Transaction was aborted due to Record changed
