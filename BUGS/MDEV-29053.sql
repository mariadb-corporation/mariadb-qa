# mysqld options required for replay: --log-bin
CREATE TABLE t (s CHAR(255),FULLTEXT (s)) DEFAULT CHARSET=utf8;
INSERT INTO t VALUES (10009);
SET GLOBAL binlog_checksum=NONE,innodb_trx_rseg_n_slots_debug=1,@@SESSION.pseudo_slave_mode=ON;
SHUTDOWN;
SET GLOBAL spider_buffer_pool_filename=NULL;
