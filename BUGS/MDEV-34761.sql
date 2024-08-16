# mysqld options required for replay:  --log_bin
set session sql_mode='';
SET @@enforce_storage_engine=INNODB;
CREATE TABLE t1 (c INT ) ENGINE=ARIA;
INSERT INTO t1 VALUES (0);
