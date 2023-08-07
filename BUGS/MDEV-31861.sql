# mysqld options required for replay:  --innodb-force-recovery=6
INSERT INTO mysql.innodb_index_stats SELECT * FROM mysql.innodb_index_stats WHERE table_name='';
