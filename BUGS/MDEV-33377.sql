SET autocommit=0;
CREATE TABLE t1 (c1 INT) ENGINE=InnoDB;
CALL sys.statement_performance_analyzer ('OVERALL', NULL, 'with_full_table_scans');
DROP TABLES t1;
CREATE TABLE t1 (c1 VARCHAR(64), PRIMARY KEY(c1)) ENGINE=MyISAM;
INSERT DELAYED t1 VALUES (1);
# [ERROR] Slave SQL: Column 0 of table 'test.t1' cannot be converted from type 'varchar(64 octets)' to type 'int(11)', Gtid 0-1-2, Internal MariaDB error code: 1677
# [ERROR] Error running query, slave SQL thread aborted. Fix the problem, and restart the slave SQL thread with "SLAVE START". We stopped at log 'master-bin.000001' position 485; GTID position '0-1-1'
# Or, with --slave_skip_errors=ALL, the same but as [Warning]
