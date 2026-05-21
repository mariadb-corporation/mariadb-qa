SET @@GLOBAL.innodb_trx_purge_view_update_only_debug=1;
CREATE TABLE t1 (c1 INT   KEY) ENGINE=InnoDB PARTITION BY LINEAR HASH(c1) PARTITIONS 1;
