SET GLOBAL innodb_stats_persistent=DEFAULT;
CREATE TABLE t ENGINE=InnoDB AS SELECT 1;
XA START 'a';
INSERT INTO mysql.innodb_index_stats SELECT '','' AS table_name,index_name,LAST_UPDATE,stat_name,0 AS stat_value,sample_size,stat_description FROM mysql.innodb_index_stats WHERE table_name='dummy';  # Note the SELECT is empty
INSERT INTO t VALUES (1);
XA END 'a';
XA PREPARE 'a';
