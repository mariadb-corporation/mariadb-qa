SET autocommit=0;
CREATE TABLE t1 (c1 INT) ENGINE=foo;
CALL sys.statement_performance_analyzer('OVERALL', NULL, 'with_full_table_scans');
DROP TABLE IF EXISTS t1;
CREATE TABLE t1 (c1 VARCHAR(64), PRIMARY KEY(c1)) ENGINE=MyISAM;
INSERT DELAYED t1 VALUES (4);
# [ERROR] Slave SQL: Error executing row event: 'Table 'test.t1' doesn't exist', Gtid 0-1-4, Internal MariaDB error code: 1146
# [Warning] Slave: Table 'test.t1' doesn't exist Error_code: 1146
