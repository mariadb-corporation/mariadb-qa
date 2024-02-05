SET sql_mode='',autocommit=0;
CREATE TABLE t (c INT) ENGINE=foo;
CALL sys.statement_performance_analyzer ('OVERALL', NULL, 'with_full_table_scans');
DROP TABLES t;
CREATE TABLE t (c VARCHAR(64)) ENGINE=MyISAM;
INSERT DELAYED t VALUES (0);
