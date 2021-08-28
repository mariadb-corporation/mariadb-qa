# $ rm -Rf data*
# $ ./scripts/mariadb-install-db --no-defaults --force --auth-root-authentication-method=normal --innodb-force-recovery=254 --basedir=${PWD} --datadir=${PWD}/data
# $ ./scripts/mysql_install_db --no-defaults --force --auth-root-authentication-method=normal --innodb-force-recovery=254 --basedir=${PWD} --datadir=${PWD}/data

# mysqld options required for replay:  --innodb-force-recovery=24
INSERT INTO mysql.innodb_table_stats SELECT database_name,''AS table_name,laST_UPDATE,123 AS n_rows,clustered_index_size,sum_of_other_index_sizes FROM mysql.innodb_table_stats WHERE table_name='';

# mysqld options required for replay:  --innodb-force-recovery=24
XA START 'a','a',0;
SELECT stat_value>0 FROM mysql.innodb_index_stats WHERE table_name LIKE 'a' IN (0);
SELECT * FROM information_schema.innodb_lock_waits;

# mysqld options required for replay:  --innodb-force-recovery=6
USE test;
SET GLOBAL innodb_log_checkpoint_now=TRUE;

# mysqld options required for replay:  --innodb-force-recovery=254
INSERT INTO mysql.innodb_table_stats SELECT database_name,''AS table_name,laST_UPDATE,0 AS n_rows,clustered_index_size,sum_of_other_index_sizes FROM mysql.innodb_table_stats WHERE table_name='';
