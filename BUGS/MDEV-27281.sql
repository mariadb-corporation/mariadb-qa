SET use_stat_tables=PREFERABLY;
SET GLOBAL aria_encrypt_tables=ON;
TRUNCATE mysql.table_stats;
CREATE TABLE t1 (c1 CHAR(1)) ENGINE=INNODB;
ANALYZE TABLE t1;
ANALYZE TABLE t1;

